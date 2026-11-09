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
    internal sealed class TrayApp : IDisposable
    {
        private const uint WM_TRAYICON = Native.WM_TRAYICON;
        private const uint TimerId = 1;
        private const uint LanguageCommandBase = 200;
        private const uint WM_LBUTTONUP = 0x0202;
        private const uint WM_LBUTTONDBLCLK = 0x0203;
        private const uint WM_RBUTTONUP = 0x0205;

        private readonly Engine _engine;
        private Native.WndProcDelegate _windowProc;
        private IntPtr _window;
        private IntPtr _icon;
        private string _lastStatus = "";
        private string _lastAction = "none";
        private string _lastVisual = "";
        private bool _tickFailed;
        private DateTime _lastNotify = DateTime.MinValue;
        private string _lastNotifyKey = "";
        private bool _fullNotified;
        private bool _lowNotified;
        private bool _healthNotified;
        private string _scheduleWarning;
        private string _lastScheduleLog;
        private string _conflictNotified;
        private int _floatLastRemaining = -1;
        private DateTime _lastFloatLog = DateTime.MinValue;
        private int _settingsOpen;
        private int _logOpen;

        public TrayApp() : this(new Engine()) { }

        internal TrayApp(Engine engine)
        {
            _engine = engine ?? new Engine();
        }

        public void Run()
        {
            ThemeSettings.Load();
            ThemeSettings.Apply();
            UiSettings.Load();

            _windowProc = WindowProc;

            var windowClass = new Native.WNDCLASSEX();
            windowClass.cbSize = (uint)Marshal.SizeOf(typeof(Native.WNDCLASSEX));
            windowClass.lpfnWndProc = Marshal.GetFunctionPointerForDelegate(_windowProc);
            windowClass.hInstance = Native.GetModuleHandle(null);
            windowClass.hCursor = Native.LoadCursor(IntPtr.Zero, (IntPtr)32512);
            windowClass.lpszClassName = "BatteryGuardTrayWindow";
            Native.RegisterClassEx(ref windowClass);

            _window = Native.CreateWindowEx(0, "BatteryGuardTrayWindow", "BatteryGuard", 0,
                0, 0, 0, 0, IntPtr.Zero, IntPtr.Zero, windowClass.hInstance, IntPtr.Zero);

            if (_window == IntPtr.Zero)
            {
                Program.Log("failed to create window");
                return;
            }

            AddTrayIcon();
            Program.Log("tray started");

            Tick();
            Native.SetTimer(_window, (UIntPtr)TimerId, 30000, IntPtr.Zero);

            Native.MSG message;
            while (Native.GetMessage(out message, IntPtr.Zero, 0, 0) > 0)
            {
                Native.TranslateMessage(ref message);
                Native.DispatchMessage(ref message);
            }

            RemoveTrayIcon();
        }

        private IntPtr WindowProc(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam)
        {
            switch (message)
            {
                case Native.WM_TIMER:
                    Tick();
                    return IntPtr.Zero;

                case WM_TRAYICON:
                    uint mouseEvent = (uint)(lParam.ToInt64() & 0xFFFF);
                    if (mouseEvent == WM_RBUTTONUP) ShowMenu();
                    else if (mouseEvent == WM_LBUTTONDBLCLK) ShowMenu();
                    else if (mouseEvent == WM_LBUTTONUP) ShowStatusBalloon();
                    return IntPtr.Zero;

                case Native.WM_SETTINGCHANGE:
                    if (lParam != IntPtr.Zero && Marshal.PtrToStringUni(lParam) == "ImmersiveColorSet")
                    {
                        ThemeSettings.Invalidate();
                        ThemeSettings.Apply();
                        UpdateIcon();
                    }
                    return IntPtr.Zero;

                case Native.WM_REFRESH:
                    UiSettings.Load();
                    ThemeSettings.Load();
                    ThemeSettings.Apply();
                    Tick();
                    return IntPtr.Zero;

                case Native.WM_DESTROY:
                    Native.PostQuitMessage(0);
                    return IntPtr.Zero;
            }

            return Native.DefWindowProc(hWnd, message, wParam, lParam);
        }

        private void Tick()
        {
            string action;
            _tickFailed = false;
            try
            {
                action = _engine.Tick(true);
            }
            catch (Exception ex)
            {
                Program.Log("tick error: " + ex.Message);
                _tickFailed = true;
                action = "error";
            }

            var status = string.Format(CultureInfo.InvariantCulture, "{0:HH:mm:ss} {1}% ac={2} mode={3} policy={4} action={5} float={6} control={7} cap={8} health={9} full={10}/{11} mWh v={12}mV p={13}mW",
                DateTime.Now, _engine.Percent, _engine.OnAc ? "yes" : "no", _engine.Mode, _engine.Current.Label, action,
                _engine.FloatActive ? "yes" : "no", _engine.CanControlCharge ? "full" : "monitor",
                _engine.Capabilities == null ? "unknown" : _engine.Capabilities.Key,
                _engine.Health, _engine.FullCharged, _engine.Designed, _engine.Voltage, _engine.PowerMilliwatts);

            UpdateIcon();

            if (_tickFailed || (_engine.CanControlCharge && _engine.Mode == ChargeMode.Unsupported))
                Notify(Loc.T("Unable to read battery status"), Loc.T("The HP battery provider did not respond. Retrying automatically."), Native.NIIF_ERROR);

            CheckBatteryAlerts();
            CheckScheduleConflict();
            CheckFloatMode();

            if (!string.Equals(status, _lastStatus, StringComparison.Ordinal))
            {
                Program.Log("tick: " + status);
                _lastStatus = status;
            }

            if (action != "none" && action != "error")
            {
                _lastAction = action;
                bool stopped = _engine.Mode == ChargeMode.Inhibit;
                string detail = string.Format(CultureInfo.InvariantCulture, "{0}%", _engine.Percent);
                if (!_engine.Current.Auto)
                    detail += string.Format(CultureInfo.InvariantCulture, Loc.T(" · Limit {0}%"), _engine.Current.Ceiling);

                Notify(stopped ? Loc.T("Charging has been stopped") : Loc.T("Charging has resumed"), detail,
                    stopped ? Native.NIIF_WARNING : Native.NIIF_INFO);

                int interval = Math.Max(15, _engine.Config.IntervalSeconds);
                Native.SetTimer(_window, (UIntPtr)TimerId, (uint)(interval * 1000), IntPtr.Zero);
            }
        }

        private void CheckScheduleConflict()
        {
            WindowRule first, second;
            string conflict = ScheduleRules.FindConflict(_engine.Config, out first, out second);
            _scheduleWarning = conflict;

            if (!string.Equals(conflict ?? "", _lastScheduleLog ?? "", StringComparison.Ordinal))
            {
                _lastScheduleLog = conflict;
                if (conflict != null) Program.Log("schedule conflict: " + conflict);
            }

            if (conflict == null)
            {
                _conflictNotified = null;
            }
            else if (!string.Equals(conflict, _conflictNotified, StringComparison.Ordinal))
            {
                _conflictNotified = conflict;
                Notify(Loc.T("Schedule conflict"), conflict, Native.NIIF_WARNING);
            }
        }

        private void CheckFloatMode()
        {
            bool active = _engine.FloatActive && _engine.OnAc;
            if (!active)
            {
                _floatLastRemaining = -1;
                return;
            }

            int drop = 0;
            if (_floatLastRemaining > 0 && _engine.Remaining > 0 && _engine.Remaining < _floatLastRemaining)
                drop = _floatLastRemaining - _engine.Remaining;

            _floatLastRemaining = _engine.Remaining;

            if (!_engine.Discharging && drop < 150) return;
            if ((DateTime.Now - _lastFloatLog).TotalMinutes < 10) return;

            _lastFloatLog = DateTime.Now;
            Program.Log(string.Format(CultureInfo.InvariantCulture,
                "float warning: discharging={0} drop={1} mWh remaining={2} percent={3}%",
                _engine.Discharging, drop, _engine.Remaining, _engine.Percent));

            Notify(Loc.T("Float mode warning"), Loc.T("The battery is draining even though the charger is connected."), Native.NIIF_ERROR);
        }

        private Color StateColor()
        {
            if (_tickFailed) return Color.FromArgb(248, 81, 73);
            if (!_engine.CanControlCharge) return Color.FromArgb(120, 144, 176);
            if (_engine.Mode == ChargeMode.Unsupported) return Color.FromArgb(248, 81, 73);
            if (_engine.FloatActive) return Color.FromArgb(45, 185, 170);
            if (_engine.Current.Auto) return Color.FromArgb(248, 81, 73);
            if (_engine.Mode == ChargeMode.Inhibit) return Color.FromArgb(240, 150, 40);
            return Color.FromArgb(63, 185, 80);
        }

        private string StateName()
        {
            if (_tickFailed) return "error";
            if (!_engine.CanControlCharge) return "monitoring";
            if (_engine.Mode == ChargeMode.Unsupported) return "error";
            if (_engine.FloatActive) return "float";
            if (_engine.Current.Auto) return "disabled";
            return _engine.Mode == ChargeMode.Inhibit ? "stopped" : "active";
        }

        private int? Badge()
        {
            if (!_engine.CanControlCharge) return null;
            if (!UiSettings.ShowCeiling) return null;
            if (_engine.Current.Auto) return null;
            return _engine.Current.Ceiling;
        }

        private void CheckBatteryAlerts()
        {
            if (_engine.Percent < 0) return;

            if (UiSettings.FullNotify && _engine.OnAc && _engine.Percent >= UiSettings.FullThreshold)
            {
                if (!_fullNotified)
                {
                    _fullNotified = true;
                    Program.Log("alert: full at " + _engine.Percent.ToString(CultureInfo.InvariantCulture) + "%");
                    Notify(Loc.T("Battery fully charged"),
                        string.Format(CultureInfo.InvariantCulture, Loc.T("{0}% · You can disconnect the charger"), _engine.Percent),
                        Native.NIIF_INFO);
                }
            }
            else if (_engine.Percent <= Math.Max(0, UiSettings.FullThreshold - 5))
            {
                _fullNotified = false;
            }

            if (UiSettings.LowNotify && !_engine.OnAc && _engine.Percent <= UiSettings.LowThreshold)
            {
                if (!_lowNotified)
                {
                    _lowNotified = true;
                    Program.Log("alert: low at " + _engine.Percent.ToString(CultureInfo.InvariantCulture) + "%");
                    Notify(Loc.T("Battery is low"),
                        string.Format(CultureInfo.InvariantCulture, Loc.T("{0}% · Charge soon"), _engine.Percent),
                        Native.NIIF_WARNING);
                }
            }
            else if (_engine.Percent >= Math.Min(100, UiSettings.LowThreshold + 5))
            {
                _lowNotified = false;
            }

            if (UiSettings.HealthNotify && _engine.Health > 0 && _engine.Health <= UiSettings.HealthThreshold)
            {
                if (!_healthNotified)
                {
                    _healthNotified = true;
                    Program.Log("alert: health " + _engine.Health.ToString(CultureInfo.InvariantCulture) + "%");
                    Notify(Loc.T("Low battery health"),
                        string.Format(CultureInfo.InvariantCulture, Loc.T("{0}% · Capacity {1:N0} of {2:N0} mWh"),
                            _engine.Health, _engine.FullCharged, _engine.Designed),
                        Native.NIIF_WARNING);
                }
            }
            else if (_engine.Health >= UiSettings.HealthThreshold + 3)
            {
                _healthNotified = false;
            }
        }

        private void OpenSettings()
        {
            if (Interlocked.CompareExchange(ref _settingsOpen, 1, 0) != 0) return;

            var thread = new Thread(delegate()
            {
                try
                {
                    using (var form = new SettingsForm(Program.ConfigPathVisible, ShowBalloon))
                    {
                        if (form.ShowDialog() == DialogResult.OK)
                        {
                            Program.Log("settings saved from window");
                            Native.PostMessage(_window, Native.WM_REFRESH, IntPtr.Zero, IntPtr.Zero);
                        }
                    }
                }
                catch (Exception ex)
                {
                    Program.Log("settings window error: " + ex.Message);
                }
                finally
                {
                    Interlocked.Exchange(ref _settingsOpen, 0);
                }
            });
            thread.SetApartmentState(ApartmentState.STA);
            thread.IsBackground = true;
            thread.Start();
        }

        private void OpenLog()
        {
            if (Interlocked.CompareExchange(ref _logOpen, 1, 0) != 0) return;

            var thread = new Thread(delegate()
            {
                try
                {
                    using (var form = new LogForm(Program.LogPathVisible)) { form.ShowDialog(); }
                }
                catch (Exception ex)
                {
                    Program.Log("log window error: " + ex.Message);
                }
                finally
                {
                    Interlocked.Exchange(ref _logOpen, 0);
                }
            });
            thread.SetApartmentState(ApartmentState.STA);
            thread.IsBackground = true;
            thread.Start();
        }

        private void UpdateIcon()
        {
            int percent = _engine.Percent < 0 ? 0 : Math.Min(100, _engine.Percent);
            bool error = _tickFailed || (_engine.CanControlCharge && _engine.Mode == ChargeMode.Unsupported);
            int? badge = Badge();
            IntPtr next = CreateBatteryIcon(percent, StateColor(), error, badge);

            if (_icon != IntPtr.Zero) Native.DestroyIcon(_icon);
            _icon = next;

            var data = BuildIconData(Native.NIF_ICON | Native.NIF_TIP);
            Native.Shell_NotifyIcon(Native.NIM_MODIFY, ref data);

            string visual = StateName() + (badge.HasValue ? " ceiling=" + badge.Value.ToString(CultureInfo.InvariantCulture) : "");
            if (!string.Equals(visual, _lastVisual, StringComparison.Ordinal))
            {
                Program.Log("icon state=" + visual);
                _lastVisual = visual;
            }
        }

        private void ShowStatusBalloon()
        {
            if (!UiSettings.Notifications)
            {
                ShowMenu();
                return;
            }

            var detail = _engine.Current.Auto
                ? (Loc.T("Standard charging · ") + (_engine.OnAc ? Loc.T("Plugged in") : Loc.T("On battery")))
                : string.Format(CultureInfo.InvariantCulture, "{0} · {1}%", _engine.Current.Label, _engine.Percent);

            string electrical = _engine.ElectricalText();
            if (electrical.Length > 0) detail += " · " + electrical;

            if (_engine.Health > 0)
                detail += string.Format(CultureInfo.InvariantCulture, Loc.T(" · Battery health {0}%"), _engine.Health);

            ShowBalloon("BatteryGuard", detail, Native.NIIF_INFO);
        }

        private void ShowBalloon(string title, string text, uint flags)
        {
            var data = BuildIconData(Native.NIF_INFO);
            data.szInfoTitle = Truncate(title, 63);
            data.szInfo = Truncate(text, 255);
            data.dwInfoFlags = flags;
            Native.Shell_NotifyIcon(Native.NIM_MODIFY, ref data);
        }

        private void Notify(string title, string text, uint flags)
        {
            Notify(title, text, flags, false);
        }

        private void Notify(string title, string text, uint flags, bool force)
        {
            if (!UiSettings.Notifications) return;

            string key = title + "|" + text;
            if (!force && string.Equals(key, _lastNotifyKey, StringComparison.Ordinal) &&
                (DateTime.Now - _lastNotify).TotalSeconds < 600) return;

            _lastNotify = DateTime.Now;
            _lastNotifyKey = key;
            ShowBalloon(title, text, flags);
        }

        private Native.NOTIFYICONDATA BuildIconData(uint extraFlags)
        {
            var data = new Native.NOTIFYICONDATA();
            data.cbSize = (uint)Marshal.SizeOf(typeof(Native.NOTIFYICONDATA));
            data.hWnd = _window;
            data.uID = 1;
            data.uFlags = Native.NIF_MESSAGE | Native.NIF_ICON | Native.NIF_TIP | extraFlags;
            data.uCallbackMessage = WM_TRAYICON;
            data.hIcon = _icon;
            data.szTip = Truncate(_engine.Tooltip(), 127);
            data.szInfo = "";
            data.szInfoTitle = "";
            return data;
        }

        private void AddTrayIcon()
        {
            _icon = CreateBatteryIcon(_engine.Percent < 0 ? 0 : Math.Min(100, _engine.Percent), StateColor(), false, Badge());
            var data = BuildIconData(Native.NIF_SHOWTIP);
            data.szTip = "BatteryGuard";
            bool added = Native.Shell_NotifyIcon(Native.NIM_ADD, ref data);
            Program.Log("tray icon added=" + added);
        }

        private void RemoveTrayIcon()
        {
            var data = BuildIconData(0);
            Native.Shell_NotifyIcon(Native.NIM_DELETE, ref data);
            if (_icon != IntPtr.Zero)
            {
                Native.DestroyIcon(_icon);
                _icon = IntPtr.Zero;
            }
        }

        // Build the popup separately from TrackPopupMenu so the menu content
        // can be verified without opening a modal menu loop.
        private IntPtr BuildPopupMenu()
        {
            var config = _engine.Config;
            bool control = _engine.CanControlCharge;
            bool fullControl = control && _engine.Capabilities != null &&
                (_engine.Capabilities.Kind & ControllerCapability.AutoInhibit) != 0;
            IntPtr menu = Native.CreatePopupMenu();

            AddInfo(menu, string.Format(CultureInfo.InvariantCulture, "BatteryGuard — {0}% · {1}", _engine.Percent, _engine.ModeText()));
            AddInfo(menu, _engine.OnAc ? Loc.T("Plugged in") : Loc.T("Runs on battery"));
            if (!string.IsNullOrEmpty(_engine.VendorName))
                AddInfo(menu, (_engine.VendorName + " " + _engine.ModelName).Trim());
            if (_engine.Designed > 0)
                AddInfo(menu, string.Format(CultureInfo.InvariantCulture, Loc.T("{0:N0} / {1:N0} mWh · Health {2}%"),
                    _engine.FullCharged, _engine.Designed, _engine.Health));
            else
                AddInfo(menu, string.Format(CultureInfo.InvariantCulture, Loc.T("Current capacity {0:N0} mWh"), _engine.FullCharged));

            string electrical = _engine.ElectricalText();
            if (electrical.Length > 0) AddInfo(menu, electrical);

            string limit = _engine.Current.Auto
                ? Loc.T("Standard charging — no limit")
                : string.Format(CultureInfo.InvariantCulture, Loc.T("Limit {0}% · Resume {1}%"), _engine.Current.Ceiling, _engine.Current.Resume);

            int estimate = _engine.MinutesRemaining();
            bool limitedCharge = _engine.Charging && !_engine.Current.Auto && _engine.Current.Ceiling > 0 && estimate > 0;
            if (limitedCharge)
                limit += " · ≈ " + Engine.FormatMinutes(estimate);
            AddInfo(menu, limit);

            if (estimate > 0 && !limitedCharge)
                AddInfo(menu, (_engine.Charging ? Loc.T("Until full ≈ ") : Loc.T("Remaining ≈ ")) + Engine.FormatMinutes(estimate));

            string schedule = config.ScheduleEnabled && config.Schedule.Count > 0
                ? Loc.T("Schedule on · ") + WindowCount(config.Schedule.Count)
                : Loc.T("Schedule off");
            if (config.FloatMode) schedule += Loc.T(" · Float mode on");
            AddInfo(menu, schedule);

            if (!control) AddInfo(menu, Loc.T("Monitoring only"));
            else if (_engine.Capabilities != null && (_engine.Capabilities.Kind & ControllerCapability.AutoInhibit) == 0)
                AddInfo(menu, _engine.CapabilityText());
            else if (_engine.FloatActive && _engine.OnAc) AddInfo(menu, Loc.T("Charger power · battery idle"));

            if (!string.IsNullOrEmpty(_scheduleWarning))
            {
                AddInfo(menu, Loc.T("! Schedule time windows overlap"));
                AddItem(menu, 184, Loc.T("Resolve schedule conflict…"));
            }

            AddSeparator(menu);
            AddItem(menu, 182, Loc.T("Charge control…"), control);
            if (fullControl)
            {
                AddCheck(menu, 102, Loc.T("Standard charging (no limit)"), config.Preset == "Off" || !config.Ceiling.HasValue, true);
                AddCheck(menu, 100, Loc.T("Recommended — 80% / 75%"), config.Preset == "Recommended", true);
                AddCheck(menu, 101, Loc.T("Longevity — 60% / 55%"), config.Preset == "Longevity", true);
                AddCheck(menu, 103, Loc.T("Custom limit…"), config.Preset == "Custom", true);
                AddCheck(menu, 183, Loc.T("Float mode (charger power)"), config.FloatMode, true);
            }

            AddSeparator(menu);
            AddCheck(menu, 172, Loc.T("Schedule"), config.ScheduleEnabled && config.Schedule.Count > 0, fullControl);
            AddItem(menu, 173, Loc.T("Edit schedule…"), fullControl);

            AddSeparator(menu);
            AddItem(menu, 180, Loc.T("Settings…"));
            AddItem(menu, 181, Loc.T("Activity log…"));

            IntPtr languages = Native.CreatePopupMenu();
            AddCheck(languages, LanguageCommandBase, Loc.T("Automatic (system)"),
                string.Equals(UiSettings.Language, "auto", StringComparison.OrdinalIgnoreCase));
            for (int index = 0; index < Loc.All.Length; index++)
            {
                var language = Loc.All[index];
                AddCheck(languages, (uint)(LanguageCommandBase + 1 + index), language.Name,
                    string.Equals(UiSettings.Language, language.Code, StringComparison.OrdinalIgnoreCase));
            }
            AddSubMenu(menu, languages, Loc.T("Language"));

            IntPtr themes = Native.CreatePopupMenu();
            AddCheck(themes, 160, Loc.T("Auto (system theme)"), ThemeSettings.Mode == ThemeMode.Auto);
            AddCheck(themes, 161, Loc.T("Light theme"), ThemeSettings.Mode == ThemeMode.Light);
            AddCheck(themes, 162, Loc.T("Dark theme"), ThemeSettings.Mode == ThemeMode.Dark);
            AddSubMenu(menu, themes, Loc.T("Appearance"));

            AddCheck(menu, 140, Loc.T("Launch at startup"), Autostart.IsInstalled());
            AddSeparator(menu);
            AddItem(menu, 150, Loc.T("Exit"));

            return menu;
        }

        private void ShowMenu()
        {
            IntPtr menu = BuildPopupMenu();

            Native.POINT point;
            Native.GetCursorPos(out point);
            Native.SetForegroundWindow(_window);
            uint alignment = UiSettings.Rtl ? Native.TPM_RIGHTALIGN : Native.TPM_LEFTALIGN;
            int command = Native.TrackPopupMenu(menu, Native.TPM_RETURNCMD | Native.TPM_RIGHTBUTTON | alignment,
                point.X, point.Y, 0, _window, IntPtr.Zero);
            Native.PostMessage(_window, 0, IntPtr.Zero, IntPtr.Zero);
            Native.DestroyMenu(menu);

            if (command > 0) HandleCommand((uint)command);
        }

        private void HandleCommand(uint command)
        {
            switch (command)
            {
                case 100: ApplyPreset("Recommended", 80, 75); break;
                case 101: ApplyPreset("Longevity", 60, 55); break;
                case 102: ApplyPreset("Off", null, 0); break;

                case 103:
                case 182:
                case 184:
                    OpenSettings();
                    break;

                case 172: ToggleSchedule(); break;
                case 173: OpenSettings(); break;

                case 183:
                    var updated = GuardConfig.Load(Program.ConfigPathVisible);
                    updated.FloatMode = !updated.FloatMode;
                    updated.Save(Program.ConfigPathVisible);
                    Program.Log("float -> " + (updated.FloatMode ? "on" : "off"));
                    break;

                case 140:
                    if (Autostart.IsInstalled()) Autostart.Remove();
                    else Autostart.Install();
                    break;

                case 160:
                case 161:
                case 162:
                    ThemeSettings.SetMode(command == 160 ? ThemeMode.Auto : (command == 161 ? ThemeMode.Light : ThemeMode.Dark));
                    UpdateIcon();
                    break;

                case 180: OpenSettings(); break;
                case 181: OpenLog(); break;
                case 150: Native.DestroyWindow(_window); break;

                default:
                    int languageIndex = (int)command - (int)LanguageCommandBase;
                    if (languageIndex >= 0 && languageIndex <= Loc.All.Length)
                    {
                        SetLanguage(languageIndex == 0 ? "auto" : Loc.All[languageIndex - 1].Code);
                    }
                    break;
            }

            if (command >= 100 && command != 150) Tick();
        }

        private void SetLanguage(string code)
        {
            // Keep an explicit direction choice; automatic direction follows the
            // newly loaded language.
            UiSettings.Language = string.IsNullOrEmpty(code) ? "auto" : code;
            UiSettings.Save();
            Loc.Load(UiSettings.Language);
            Program.Log("language -> " + UiSettings.Language);
        }

        private void ApplyPreset(string preset, int? ceiling, int resume)
        {
            var config = GuardConfig.Load(Program.ConfigPathVisible);
            config.Preset = preset;
            config.Ceiling = ceiling;
            config.Resume = ceiling.HasValue && resume > 0 ? (int?)resume : null;
            config.ResumeDrop = 5;
            config.Save(Program.ConfigPathVisible);

            if (preset == "Off") _engine.ForceAuto();
            Program.Log("preset -> " + preset);
        }

        private void ToggleSchedule()
        {
            var config = GuardConfig.Load(Program.ConfigPathVisible);
            config.ScheduleEnabled = !(config.ScheduleEnabled && config.Schedule.Count > 0);

            if (config.ScheduleEnabled && config.Schedule.Count == 0)
            {
                var rule = new WindowRule();
                rule.From = "00:00";
                rule.To = "08:00";
                rule.Ceiling = config.Ceiling;
                config.Schedule.Add(rule);
            }

            config.Save(Program.ConfigPathVisible);
            Program.Log("schedule -> " + (config.ScheduleEnabled ? "on" : "off"));
        }

        private static string WindowCount(int count)
        {
            if (count == 1) return Loc.T("One time window");
            if (count == 2) return Loc.T("Two time windows");
            if (count <= 10) return count.ToString(CultureInfo.InvariantCulture) + Loc.T(" time windows");
            return count.ToString(CultureInfo.InvariantCulture) + Loc.T(" time window");
        }

        private static uint MenuFlags(uint flags)
        {
            return UiSettings.Rtl ? flags | Native.MFT_RTL : flags;
        }

        private static void AddItem(IntPtr menu, uint id, string text, bool enabled = true)
        {
            uint flags = Native.MF_STRING | (enabled ? 0 : Native.MF_GRAYED);
            Native.AppendMenu(menu, MenuFlags(flags), (UIntPtr)id, text);
        }

        private static void AddCheck(IntPtr menu, uint id, string text, bool isChecked, bool enabled = true)
        {
            uint flags = Native.MF_STRING | (isChecked ? Native.MF_CHECKED : 0) | (enabled ? 0 : Native.MF_GRAYED);
            Native.AppendMenu(menu, MenuFlags(flags), (UIntPtr)id, text);
        }

        private static void AddInfo(IntPtr menu, string text)
        {
            Native.AppendMenu(menu, MenuFlags(Native.MF_STRING | Native.MF_GRAYED), UIntPtr.Zero, text);
        }

        private static void AddSeparator(IntPtr menu)
        {
            Native.AppendMenu(menu, Native.MF_SEPARATOR, UIntPtr.Zero, null);
        }

        private static void AddSubMenu(IntPtr parent, IntPtr child, string text)
        {
            Native.AppendMenu(parent, MenuFlags(Native.MF_POPUP), (UIntPtr)child.ToInt64(), text);
        }

        private static void OpenWithDefault(string path)
        {
            try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); }
            catch (Exception ex) { Program.Log("open failed: " + ex.Message); }
        }

        private static string Truncate(string text, int limit)
        {
            if (string.IsNullOrEmpty(text)) return string.Empty;
            return text.Length <= limit ? text : text.Substring(0, limit);
        }

        private static IntPtr CreateBatteryIcon(int percent, Color fill, bool alert, int? badge)
        {
            using (var bitmap = new Bitmap(32, 32, PixelFormat.Format32bppArgb))
            {
                using (var graphics = Graphics.FromImage(bitmap))
                {
                    graphics.SmoothingMode = SmoothingMode.AntiAlias;
                    graphics.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAlias;
                    graphics.Clear(Color.Transparent);

                    using (var body = RoundedRect(new RectangleF(1.5f, 5.5f, 25f, 21f), 4.5f))
                    using (var outline = new Pen(ThemeSettings.Ink, 2.4f))
                        graphics.DrawPath(outline, body);

                    using (var terminal = new SolidBrush(ThemeSettings.Ink))
                        graphics.FillRectangle(terminal, 27f, 11.5f, 3f, 9f);

                    float width = 20f * Math.Max(0, Math.Min(100, percent)) / 100f;
                    if (width > 0f)
                    {
                        using (var brush = new SolidBrush(fill))
                            graphics.FillRectangle(brush, 4f, 8f, width, 16f);
                    }

                    if (alert)
                    {
                        DrawAlert(graphics);
                    }
                    else if (badge.HasValue)
                    {
                        DrawBadge(graphics, badge.Value);
                    }
                }

                return bitmap.GetHicon();
            }
        }

        private static void DrawBadge(Graphics graphics, int value)
        {
            string text = Math.Max(0, Math.Min(999, value)).ToString(CultureInfo.InvariantCulture);
            using (var font = new Font("Segoe UI", text.Length > 2 ? 11f : 13f, FontStyle.Bold, GraphicsUnit.Pixel))
            using (var format = new StringFormat())
            {
                format.Alignment = StringAlignment.Center;
                format.LineAlignment = StringAlignment.Center;
                var area = new RectangleF(1.5f, 5.5f, 25f, 21f);

                using (var halo = new SolidBrush(Color.FromArgb(210, 10, 12, 14)))
                {
                    graphics.DrawString(text, font, halo, new RectangleF(area.X + 1f, area.Y, area.Width, area.Height), format);
                    graphics.DrawString(text, font, halo, new RectangleF(area.X - 1f, area.Y, area.Width, area.Height), format);
                    graphics.DrawString(text, font, halo, new RectangleF(area.X, area.Y + 1f, area.Width, area.Height), format);
                    graphics.DrawString(text, font, halo, new RectangleF(area.X, area.Y - 1f, area.Width, area.Height), format);
                }

                using (var brush = new SolidBrush(Color.White))
                    graphics.DrawString(text, font, brush, area, format);
            }
        }

        private static void DrawAlert(Graphics graphics)
        {
            using (var font = new Font("Segoe UI", 17f, FontStyle.Bold, GraphicsUnit.Pixel))
            using (var format = new StringFormat())
            {
                format.Alignment = StringAlignment.Center;
                format.LineAlignment = StringAlignment.Center;
                var area = new RectangleF(1.5f, 5.5f, 25f, 21f);

                using (var halo = new SolidBrush(Color.FromArgb(210, 10, 12, 14)))
                {
                    graphics.DrawString("!", font, halo, new RectangleF(area.X + 1f, area.Y, area.Width, area.Height), format);
                    graphics.DrawString("!", font, halo, new RectangleF(area.X - 1f, area.Y, area.Width, area.Height), format);
                    graphics.DrawString("!", font, halo, new RectangleF(area.X, area.Y + 1f, area.Width, area.Height), format);
                    graphics.DrawString("!", font, halo, new RectangleF(area.X, area.Y - 1f, area.Width, area.Height), format);
                }

                using (var brush = new SolidBrush(Color.White))
                    graphics.DrawString("!", font, brush, area, format);
            }
        }

        private static GraphicsPath RoundedRect(RectangleF bounds, float radius)
        {
            var path = new GraphicsPath();
            float diameter = radius * 2f;
            path.AddArc(bounds.X, bounds.Y, diameter, diameter, 180f, 90f);
            path.AddArc(bounds.Right - diameter, bounds.Y, diameter, diameter, 270f, 90f);
            path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0f, 90f);
            path.AddArc(bounds.X, bounds.Bottom - diameter, diameter, diameter, 90f, 90f);
            path.CloseFigure();
            return path;
        }

        public void Dispose()
        {
            _engine.Dispose();
        }
    }
}
