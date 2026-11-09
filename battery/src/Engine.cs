// BatteryGuardTray - native Win32 tray monitor for BatteryGuard.
// One small exe using the .NET Framework that ships with Windows: a message-only
// window, Shell_NotifyIcon and owner-drawn menus. The optional settings/log
// dialogs use the WinForms that ships with the framework; no external packages.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Management;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace BatteryGuardTray
{
    internal sealed class Policy
    {
        public bool Auto;
        public int Ceiling;
        public int Resume;
        public string Label = "";
    }

    internal enum ChargeAction
    {
        None,
        Auto,
        Inhibit
    }

    internal sealed class ChargeDecision
    {
        public ChargeAction Action;
        public bool FloatActive;
    }

    internal static class ChargePolicy
    {
        // Pure decision logic, kept separate from WMI so it can be tested
        // without a battery. Float is only latched after the ceiling is reached.
        //
        // Firmware ceiling: the HP firmware can enforce its own charge limit
        // (Battery Care Function, SystemConfig 0x23E in the F.28 setup store).
        // That limit is independent of and invisible to this policy, so the
        // effective ceiling is min(app ceiling, firmware ceiling). When the
        // firmware stops charging first, the WMI mode stays Auto, the percentage
        // plateaus below the configured ceiling and float never latches. That is
        // not a controller failure: the app has no read path for the firmware
        // value and must not retry or override it.
        public static ChargeDecision Evaluate(bool standardCharging, bool onAc, int percent,
            int? ceiling, int? resume, bool floatMode, bool floatActive, ChargeMode mode)
        {
            var result = new ChargeDecision { Action = ChargeAction.None, FloatActive = floatActive };

            if (standardCharging || !ceiling.HasValue)
            {
                result.FloatActive = false;
                if (mode == ChargeMode.Inhibit) result.Action = ChargeAction.Auto;
                return result;
            }

            if (!onAc)
            {
                result.FloatActive = false;
                if (mode == ChargeMode.Inhibit) result.Action = ChargeAction.Auto;
                return result;
            }

            int limit = ceiling.Value;
            int resumeAt = resume ?? Math.Max(1, limit - 5);

            if (percent >= limit)
            {
                result.FloatActive = floatMode;
                if (mode == ChargeMode.Auto) result.Action = ChargeAction.Inhibit;
                return result;
            }

            if (mode == ChargeMode.Inhibit)
            {
                if (floatActive)
                {
                    // Once float is active, stay on charger power until the
                    // explicit resume point; a small drop must not cycle the battery.
                    if (percent <= resumeAt)
                    {
                        result.FloatActive = false;
                        result.Action = ChargeAction.Auto;
                    }
                    return result;
                }

                // Inhibit below the target is not float. Release it so charging
                // reaches the configured limit before float can start.
                if (floatMode)
                {
                    result.FloatActive = false;
                    result.Action = ChargeAction.Auto;
                }
                return result;
            }

            result.FloatActive = false;
            return result;
        }
    }

    internal sealed class Engine : IDisposable
    {
        private readonly IChargeController _controller;

        public GuardConfig Config = new GuardConfig();
        public bool FloatActive;
        public Policy Current = new Policy { Auto = true, Label = Loc.T("Standard charging") };
        public ChargeMode Mode = ChargeMode.Unsupported;
        public int Percent = -1;
        public bool OnAc;
        public int Health = -1;
        public int Remaining;
        public int FullCharged;
        public int Designed;
        public int Voltage;
        public bool Charging;
        public bool Discharging;
        public int ChargeRate;
        public int DischargeRate;
        public int CycleCount = -1;
        public int TemperatureC = -1;

        public int PowerMilliwatts
        {
            get
            {
                if (Charging && ChargeRate > 0) return ChargeRate;
                if (Discharging && DischargeRate > 0) return DischargeRate;
                return Math.Max(ChargeRate, DischargeRate);
            }
        }

        public string ElectricalText()
        {
            return BatteryInfo.FormatElectrical(Voltage, PowerMilliwatts);
        }

        public Engine() : this(BatteryControllerFactory.Create()) { }

        internal Engine(IChargeController controller)
        {
            if (controller == null) throw new ArgumentNullException("controller");
            _controller = controller;
        }

        public string VendorName { get { return _controller.VendorName; } }
        public string ModelName { get { return _controller.ModelName; } }
        public bool CanControlCharge { get { return _controller.CanControlCharge; } }
        public ControllerCapabilities Capabilities { get { return _controller.Capabilities; } }
        public DeviceProfile ControllerProfile { get { return _controller.Profile; } }
        public bool IsHpDevice { get { return DeviceInfo.IsHp; } }

        public string Tick(bool apply)
        {
            Config = GuardConfig.Load(Program.ConfigPathVisible);
            Mode = _controller.ReadMode();
            RefreshPower();
            Current = ResolvePolicy(Config, DateTime.Now);

            string action = "none";

            if (!CanControlCharge)
            {
                FloatActive = false;
                return action;
            }

            // Evaluate the latch on every tick so the tray reflects it even
            // before the next hardware write. Float never activates below the
            // ceiling: charging must reach the limit first.
            ChargeDecision decision = ChargePolicy.Evaluate(Current.Auto, OnAc, Percent,
                Current.Ceiling, Current.Resume, Config.FloatMode, FloatActive, Mode);
            FloatActive = decision.FloatActive;

            if (!apply) return action;

            if (decision.Action == ChargeAction.Auto && Mode == ChargeMode.Inhibit)
            {
                if (SetAutoConfirmed())
                {
                    FloatActive = false;
                    action = Current.Auto ? "auto" : (!OnAc ? "auto-on-battery" : (Percent <= Current.Resume ? "resume" : "resume-float"));
                }
            }
            else if (decision.Action == ChargeAction.Inhibit && Mode == ChargeMode.Auto)
            {
                if (SetInhibitConfirmed())
                {
                    FloatActive = decision.FloatActive;
                    action = "inhibit";
                }
            }

            return action;
        }

        public void ForceAuto()
        {
            if (!CanControlCharge) return;
            ControllerResult result = _controller.RequestAuto(OnAc);
            Mode = result.Observed;
            if (!result.Ok)
            {
                Program.Log("manual auto failed: " + result);
                return;
            }
            FloatActive = false;
            Program.Log("manual auto, readback " + Mode);
        }

        public void ForceInhibit()
        {
            if (!CanControlCharge) return;
            ControllerResult result = _controller.RequestInhibit(OnAc);
            Mode = result.Observed;
            if (!result.Ok)
            {
                Program.Log("manual inhibit failed: " + result);
                return;
            }
            FloatActive = Config.FloatMode && OnAc && Percent >= Current.Ceiling;
            Program.Log("manual inhibit, readback " + Mode);
        }

        private bool SetInhibitConfirmed()
        {
            ControllerResult result = _controller.RequestInhibit(OnAc);
            Mode = result.Observed;
            bool ok = result.Ok && Mode == ChargeMode.Inhibit;
            Program.Log(ok ? "charge inhibited" : "inhibit not confirmed: " + result);
            return ok;
        }

        private bool SetAutoConfirmed()
        {
            ControllerResult result = _controller.RequestAuto(OnAc);
            Mode = result.Observed;
            bool ok = result.Ok && Mode == ChargeMode.Auto;
            Program.Log(ok ? "charging restored" : "auto not confirmed: " + result);
            return ok;
        }

        private void RefreshPower()
        {
            var info = BatteryInfo.Read();
            Percent = info.Percent;
            Health = info.Health;
            Remaining = info.Remaining;
            FullCharged = info.FullCharged;
            Designed = info.Designed;
            Voltage = info.Voltage;
            Charging = info.Charging;
            Discharging = info.Discharging;
            ChargeRate = info.ChargeRate;
            DischargeRate = info.DischargeRate;
            CycleCount = info.CycleCount;
            TemperatureC = info.TemperatureC;
            OnAc = info.PowerOnline;
        }

        public int TargetPercent()
        {
            return Current != null && !Current.Auto && Current.Ceiling > 0
                ? Current.Ceiling
                : 100;
        }

        public int MinutesToPercent(int targetPercent)
        {
            if (Charging && ChargeRate > 0 && FullCharged > 0)
            {
                int targetCapacity = (int)Math.Round(
                    FullCharged * Math.Max(0, Math.Min(100, targetPercent)) / 100.0);
                if (targetCapacity > Remaining)
                    return (int)Math.Round((targetCapacity - Remaining) * 60.0 / ChargeRate);
            }

            if (Discharging && DischargeRate > 0 && Remaining > 0)
                return (int)Math.Round(Remaining * 60.0 / DischargeRate);
            return -1;
        }

        public int MinutesRemaining()
        {
            // Charging estimates follow the active ceiling, not always 100%.
            return MinutesToPercent(TargetPercent());
        }

        public string EstimateText()
        {
            int minutes = MinutesRemaining();
            if (minutes <= 0) return "";
            return (Charging ? Loc.T("Charging") : Loc.T("Discharging")) + " ≈ " + FormatMinutes(minutes);
        }

        public static string FormatMinutes(int minutes)
        {
            if (minutes < 60) return minutes.ToString(CultureInfo.InvariantCulture) + Loc.T(" min");

            int hours = minutes / 60;
            int rest = minutes % 60;
            return rest == 0
                ? hours.ToString(CultureInfo.InvariantCulture) + Loc.T(" h")
                : hours.ToString(CultureInfo.InvariantCulture) + Loc.T(" h ") + rest.ToString(CultureInfo.InvariantCulture) + Loc.T(" min");
        }

        public string ModeText()
        {
            switch (Mode)
            {
                case ChargeMode.Auto: return Loc.T("Standard charging");
                case ChargeMode.Inhibit: return Loc.T("Charging stopped");
                case ChargeMode.ForceDischarge: return Loc.T("Forced discharge");
                default: return CanControlCharge ? Loc.T("Unsupported") : Loc.T("Monitoring only");
            }
        }

        public string CapabilityText()
        {
            if (!CanControlCharge) return Loc.T("Monitoring only");
            if (Capabilities == null) return Loc.T("Charge control");
            return Capabilities.DisplayName;
        }

        public string Tooltip()
        {
            var parts = new List<string>();
            // Keep the electrical reading near the start: the tray tooltip is
            // capped at 127 characters and later details can be truncated.
            parts.Add(string.Format(CultureInfo.InvariantCulture, "{0}% · {1}", Percent, ModeText()));

            string electrical = ElectricalText();
            if (electrical.Length > 0) parts.Add(electrical);

            if (Current.Auto)
                parts.Add(Loc.T("Standard charging"));
            else
                parts.Add(string.Format(CultureInfo.InvariantCulture, Loc.T("Limit {0}% · Resume {1}%"), Current.Ceiling, Current.Resume));

            if (FloatActive && OnAc)
                parts.Add(Discharging ? Loc.T("Warning: battery is draining despite the charger") : Loc.T("Charger power · battery idle"));
            else
                parts.Add(OnAc ? Loc.T("Plugged in") : Loc.T("On battery"));

            if (Health > 0) parts.Add(string.Format(CultureInfo.InvariantCulture, Loc.T("Battery health {0}%"), Health));
            if (TemperatureC > 0) parts.Add(TemperatureC.ToString(CultureInfo.InvariantCulture) + Loc.T("°C"));

            string estimate = EstimateText();
            if (estimate.Length > 0) parts.Add(estimate);

            WindowRule firstWindow, secondWindow;
            if (ScheduleRules.FindConflict(Config, out firstWindow, out secondWindow) != null)
                parts.Add(Loc.T("Schedule conflict"));

            string text = string.Join(" · ", parts.ToArray());
            return text.Length <= 127 ? text : text.Substring(0, 126) + "…";
        }

        public static Policy ResolvePolicy(GuardConfig config, DateTime now)
        {
            var policy = new Policy { Auto = true };

            if (config.ScheduleEnabled && config.Schedule.Count > 0)
            {
                int minutes = now.Hour * 60 + now.Minute;
                foreach (var window in config.Schedule)
                {
                    if (!InWindow(window.From, window.To, minutes)) continue;

                    if (!window.Ceiling.HasValue)
                    {
                        policy.Auto = true;
                        policy.Label = Loc.T("Schedule ") + window.From + "-" + window.To + Loc.T(": Standard charging");
                        return policy;
                    }

                    policy.Auto = false;
                    policy.Ceiling = window.Ceiling.Value;
                    policy.Resume = ResumeFor(policy.Ceiling, null, config.ResumeDrop);
                    policy.Label = string.Format(CultureInfo.InvariantCulture, Loc.T("Schedule {0}–{1}: limit {2}%"), window.From, window.To, policy.Ceiling);
                    return policy;
                }

                policy.Auto = true;
                policy.Label = Loc.T("No active schedule time window");
                return policy;
            }

            if (string.Equals(config.Preset, "Off", StringComparison.OrdinalIgnoreCase) || !config.Ceiling.HasValue)
            {
                policy.Auto = true;
                policy.Label = Loc.T("Standard charging");
                return policy;
            }

            policy.Auto = false;
            policy.Ceiling = config.Ceiling.Value;
            policy.Resume = ResumeFor(policy.Ceiling, config.Resume, config.ResumeDrop);
            policy.Label = string.Format(CultureInfo.InvariantCulture, Loc.T("Limit {0}% (resume {1}%)"), policy.Ceiling, policy.Resume);
            return policy;
        }

        public static int ResumeFor(int ceiling, int? explicitResume, int drop)
        {
            if (explicitResume.HasValue && explicitResume.Value > 0) return explicitResume.Value;
            return Math.Max(1, ceiling - Math.Max(1, drop));
        }

        private static bool InWindow(string from, string to, int minutes)
        {
            int start, end;
            if (!TryMinutes(from, out start) || !TryMinutes(to, out end)) return false;
            if (start == end) return true;
            if (start < end) return minutes >= start && minutes < end;
            return minutes >= start || minutes < end;
        }

        private static bool TryMinutes(string clock, out int minutes)
        {
            minutes = 0;
            if (string.IsNullOrEmpty(clock)) return false;
            var parts = clock.Split(':');
            if (parts.Length != 2) return false;
            int hour, minute;
            if (!int.TryParse(parts[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out hour)) return false;
            if (!int.TryParse(parts[1], NumberStyles.Integer, CultureInfo.InvariantCulture, out minute)) return false;
            if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return false;
            minutes = hour * 60 + minute;
            return true;
        }

        public void Dispose()
        {
            _controller.Dispose();
        }
    }
}
