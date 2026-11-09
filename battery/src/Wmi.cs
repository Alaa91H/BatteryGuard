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
    internal enum ChargeMode
    {
        Unsupported = -1,
        Auto = 0,
        ForceDischarge = 2,
        Inhibit = 4,
        InhibitExtended = 6
    }

    internal interface IBatteryController : IDisposable
    {
        string VendorName { get; }
        string ModelName { get; }
        bool CanControlCharge { get; }
        ChargeMode ReadMode();
        bool SetAuto();
        bool SetInhibit();
    }

    internal static class DeviceInfo
    {
        private static bool _loaded;
        private static DeviceFingerprint _fingerprint = new DeviceFingerprint();

        public static DeviceFingerprint Fingerprint
        {
            get { Load(); return _fingerprint; }
        }

        public static string Manufacturer { get { return Fingerprint.Manufacturer; } }
        public static string Model { get { return Fingerprint.Product; } }
        public static DeviceProfile Profile { get { return DeviceProfileCatalog.Match(Fingerprint); } }
        public static bool IsHp { get { return DeviceProfileCatalog.IsHpManufacturer(Fingerprint.Manufacturer); } }

        private static void Load()
        {
            if (_loaded) return;
            _loaded = true;
            _fingerprint = DeviceFingerprint.Read();
        }
    }

    internal sealed class GenericBatteryController : IChargeController
    {
        private readonly DeviceFingerprint _fingerprint;
        private readonly DeviceProfile _profile;

        public GenericBatteryController() : this(DeviceInfo.Fingerprint, DeviceInfo.Profile) { }

        internal GenericBatteryController(DeviceFingerprint fingerprint, DeviceProfile profile)
        {
            _fingerprint = fingerprint ?? new DeviceFingerprint();
            _profile = profile;
            VendorName = _fingerprint.Manufacturer;
            ModelName = _fingerprint.Product;
        }

        public string VendorName { get; private set; }
        public string ModelName { get; private set; }
        public DeviceFingerprint Fingerprint { get { return _fingerprint; } }
        public ControllerCapabilities Capabilities { get { return ControllerCapabilities.Monitoring(); } }
        public DeviceProfile Profile { get { return _profile; } }
        public bool CanControlCharge { get { return false; } }

        public ChargeMode ReadMode() { return ChargeMode.Unsupported; }
        public bool SetAuto() { return false; }
        public bool SetInhibit() { return false; }
        public ControllerResult RequestAuto(bool onAc) { return ControllerResult.Failure(ControllerResultStatus.Unsupported, "monitoring only"); }
        public ControllerResult RequestInhibit(bool onAc) { return ControllerResult.Failure(ControllerResultStatus.Unsupported, "monitoring only"); }
        public void Dispose() { }
    }

    internal sealed class HpBios : IChargeController
    {
        private readonly DeviceFingerprint _fingerprint;
        private readonly IWmiGateway _gateway;

        private const uint CommandRead = 0x01;
        private const uint CommandWrite = 0x02;
        private const uint TypeChargeControl = 0x1f;
        private const uint TypeChargeMode = 0x2b;

        public HpBios() : this(DeviceInfo.Fingerprint, new HpBiosWmiGateway()) { }

        internal HpBios(DeviceFingerprint fingerprint) : this(fingerprint, new HpBiosWmiGateway()) { }

        internal HpBios(DeviceFingerprint fingerprint, IWmiGateway gateway)
        {
            _fingerprint = fingerprint ?? new DeviceFingerprint { Manufacturer = "HP" };
            _gateway = gateway;
        }

        public string VendorName { get { return "HP"; } }
        public string ModelName { get { return _fingerprint.Product; } }
        public DeviceFingerprint Fingerprint { get { return _fingerprint; } }
        public ControllerCapabilities Capabilities { get { return DeviceProfileCatalog.HpCapabilities; } }
        public DeviceProfile Profile { get { return DeviceProfileCatalog.Hp; } }
        public bool CanControlCharge { get { return true; } }

        public ChargeMode ReadMode()
        {
            WmiCallResult result = _gateway.Invoke(CommandRead, TypeChargeMode, new byte[4]);
            if (!result.TransportOk || result.ReturnCode != 0 || result.Data == null || result.Data.Length == 0)
                return ChargeMode.Unsupported;

            switch (result.Data[0])
            {
                case 0: return ChargeMode.Auto;
                case 2: return ChargeMode.ForceDischarge;
                case 4:
                case 6: return ChargeMode.Inhibit;
                default: return ChargeMode.Unsupported;
            }
        }

        public bool WriteMode(uint commandType, byte value, out uint code)
        {
            WmiCallResult result = _gateway.Invoke(CommandWrite, commandType,
                new byte[] { 0x00, value, 0x00, 0x00 });
            code = result.ReturnCode;
            return result.TransportOk && result.ReturnCode == 0;
        }

        public bool SetInhibit()
        {
            uint code;
            if (!WriteMode(TypeChargeMode, 0x05, out code))
            {
                Program.Log("inhibit write rejected (rc=" + code.ToString(CultureInfo.InvariantCulture) + ")");
                return false;
            }
            return true;
        }

        public bool SetAuto()
        {
            uint code;
            if (WriteMode(TypeChargeMode, 0x00, out code)) return true;
            Program.Log("auto write via 0x2b rejected (rc=" + code.ToString(CultureInfo.InvariantCulture) + "), trying 0x1f");
            return WriteMode(TypeChargeControl, 0x00, out code);
        }

        public ControllerResult RequestInhibit(bool onAc)
        {
            return WriteGuard.Apply(Capabilities, onAc, ChargeMode.Inhibit, SetInhibit, ReadMode,
                delegate { SetAuto(); });
        }

        public ControllerResult RequestAuto(bool onAc)
        {
            return WriteGuard.Apply(Capabilities, onAc, ChargeMode.Auto, SetAuto, ReadMode, null);
        }

        public void Dispose()
        {
            if (_gateway != null) _gateway.Dispose();
        }
    }

    internal static class BatteryControllerFactory
    {
        private static readonly IControllerProvider[] Providers =
        {
            new HpControllerProvider(),
            new GenericControllerProvider()
        };

        public static IChargeController Create()
        {
            return Create(DeviceInfo.Fingerprint);
        }

        internal static IChargeController Create(DeviceFingerprint fingerprint)
        {
            fingerprint = fingerprint ?? new DeviceFingerprint();
            DeviceProfile profile = DeviceProfileCatalog.Match(fingerprint);

            if (profile != null)
            {
                Program.Log("controller profile: " + profile.Vendor + " " + profile.Interface +
                    " status=" + profile.Status + " capabilities=" + profile.Capabilities.Key);
            }

            // Explicit, fail-closed test path. Tests set this before launching the
            // tray; no provider or WMI gateway is constructed in this mode.
            string testController = Environment.GetEnvironmentVariable("BATTERYGUARD_TEST_CONTROLLER");
            if (string.Equals(testController, "monitoring", StringComparison.OrdinalIgnoreCase))
            {
                var test = new GenericBatteryController(fingerprint, null);
                Program.Log("test controller: monitoring-only; charge writes disabled (BATTERYGUARD_TEST_CONTROLLER=monitoring)");
                Program.Log("controller: " + test.VendorName + " " + test.ModelName +
                    " (test mode, monitoring only; no WMI/EC write path)");
                return test;
            }

            for (int index = 0; index < Providers.Length; index++)
            {
                IControllerProvider provider = Providers[index];
                if (provider.Profile == null || !provider.Profile.CanWrite) continue;
                if (!provider.Matches(fingerprint)) continue;

                try
                {
                    IChargeController controller = provider.Create(fingerprint);
                    Program.Log("controller: " + controller.VendorName + " " + controller.ModelName +
                        " (charge control, " + controller.Capabilities.Key + ")");
                    return controller;
                }
                catch (Exception ex)
                {
                    Program.Log(provider.Name + " controller unavailable: " + ex.Message);
                }
            }

            var generic = new GenericBatteryController(fingerprint, profile);
            Program.Log("controller: " + generic.VendorName + " " + generic.ModelName +
                " (monitoring only" + (profile == null ? "; no matching profile" : "; " + profile.Status) + ")");
            return generic;
        }
    }

    internal static class BatteryCapacity
    {
        private static readonly string CachePath = Path.Combine(Program.BaseDirectory, "capacity.ini");
        private static int _designed = -1;

        public static int Designed()
        {
            if (_designed > 0) return _designed;

            try
            {
                if (File.Exists(CachePath))
                {
                    foreach (string line in File.ReadAllLines(CachePath))
                    {
                        int split = line.IndexOf('=');
                        if (split <= 0) continue;
                        if (!string.Equals(line.Substring(0, split).Trim(), "designed", StringComparison.OrdinalIgnoreCase)) continue;

                        int cached;
                        if (int.TryParse(line.Substring(split + 1).Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out cached) && cached > 0)
                        {
                            _designed = cached;
                            return _designed;
                        }
                    }
                }

                int parsed = ReadFromReport();
                if (parsed > 0)
                {
                    _designed = parsed;
                    File.WriteAllText(CachePath,
                        "designed=" + parsed.ToString(CultureInfo.InvariantCulture) + Environment.NewLine,
                        new UTF8Encoding(false));
                }
            }
            catch (Exception ex)
            {
                Program.Log("capacity read error: " + ex.Message);
            }

            return _designed > 0 ? _designed : 0;
        }

        private static int ReadFromReport()
        {
            string report = Path.Combine(Path.GetTempPath(), "BatteryGuard-battery-report.xml");
            try
            {
                var info = new ProcessStartInfo("powercfg.exe", "/batteryreport /xml /output \"" + report + "\"");
                info.CreateNoWindow = true;
                info.UseShellExecute = false;
                info.RedirectStandardOutput = true;
                info.RedirectStandardError = true;

                using (var process = Process.Start(info))
                {
                    process.StandardOutput.ReadToEnd();
                    process.StandardError.ReadToEnd();
                    process.WaitForExit(20000);
                }

                if (!File.Exists(report)) return 0;

                string xml = File.ReadAllText(report);
                var match = System.Text.RegularExpressions.Regex.Match(xml, "<DesignCapacity>(\\d+)</DesignCapacity>");
                if (!match.Success) return 0;

                int value;
                if (int.TryParse(match.Groups[1].Value, NumberStyles.Integer, CultureInfo.InvariantCulture, out value)) return value;
                return 0;
            }
            catch (Exception ex)
            {
                Program.Log("capacity report error: " + ex.Message);
                return 0;
            }
            finally
            {
                try { if (File.Exists(report)) File.Delete(report); } catch { }
            }
        }
    }

    internal sealed class BatteryInfo
    {
        public int Percent = -1;
        public int Remaining;
        public int FullCharged;
        public int Designed;
        public int Voltage;
        public int ChargeRate;
        public int DischargeRate;
        public bool PowerOnline;
        public bool Charging;
        public bool Discharging;
        public int CycleCount = -1;
        public int TemperatureC = -1;

        public int Health
        {
            get { return Designed > 0 ? (int)Math.Round(FullCharged * 100.0 / Designed) : -1; }
        }

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
            return FormatElectrical(Voltage, PowerMilliwatts);
        }

        public static string FormatElectrical(int voltageMillivolts, int powerMilliwatts)
        {
            var parts = new List<string>();
            if (voltageMillivolts > 0)
                parts.Add((voltageMillivolts / 1000.0).ToString("0.0", CultureInfo.InvariantCulture) + " V");
            // Zero is a valid reading while the charger holds the battery idle;
            // show it when voltage confirms that a battery reading exists.
            if (powerMilliwatts > 0 || voltageMillivolts > 0)
                parts.Add((powerMilliwatts / 1000.0).ToString("0.0", CultureInfo.InvariantCulture) + " W");
            return string.Join(" · ", parts.ToArray());
        }

        public int MinutesRemaining(int targetPercent = 100)
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

        public static BatteryInfo Read()
        {
            var info = new BatteryInfo();

            try
            {
                var scope = new ManagementScope(@"\\.\root\wmi");
                scope.Connect();

                int remaining = 0;
                int full = 0;
                int voltage = 0;
                int chargeRate = 0;
                int dischargeRate = 0;
                bool online = false;
                bool charging = false;
                bool discharging = false;

                using (var statusClass = new ManagementClass(scope, new ManagementPath("BatteryStatus"), null))
                {
                    foreach (ManagementBaseObject status in statusClass.GetInstances())
                    {
                        remaining += ToInt(status["RemainingCapacity"]);
                        voltage = Math.Max(voltage, ToInt(status["Voltage"]));
                        chargeRate += Math.Max(0, ToInt(status["ChargeRate"]));
                        dischargeRate += Math.Max(0, ToInt(status["DischargeRate"]));
                        online |= ToBool(status["PowerOnline"]);
                        charging |= ToBool(status["Charging"]);
                        discharging |= ToBool(status["Discharging"]);

                        object temperature = TryGet(status, "Temperature");
                        if (temperature != null)
                        {
                            int tenths = ToInt(temperature);
                            if (tenths > 0) info.TemperatureC = (int)Math.Round(tenths / 10.0 - 273.15);
                        }
                    }
                }

                using (var fullClass = new ManagementClass(scope, new ManagementPath("BatteryFullChargedCapacity"), null))
                {
                    foreach (ManagementBaseObject capacity in fullClass.GetInstances())
                        full += ToInt(capacity["FullChargedCapacity"]);
                }

                int cycles = 0;
                try
                {
                    using (var cycleClass = new ManagementClass(scope, new ManagementPath("BatteryCycleCount"), null))
                    {
                        foreach (ManagementBaseObject cycle in cycleClass.GetInstances())
                        {
                            int count = ToInt(TryGet(cycle, "CycleCount"));
                            if (count > cycles) cycles = count;
                        }
                    }
                }
                catch { }

                info.Remaining = remaining;
                info.FullCharged = full;
                info.CycleCount = cycles > 0 ? cycles : -1;
                info.Designed = BatteryCapacity.Designed();
                info.Voltage = voltage;
                info.ChargeRate = chargeRate;
                info.DischargeRate = dischargeRate;
                info.PowerOnline = online;
                info.Charging = charging;
                info.Discharging = discharging;

                if (remaining > 0 && full > 0)
                {
                    double percent = remaining * 100.0 / full;
                    info.Percent = (int)Math.Round(Math.Max(0, Math.Min(100, percent)));
                }
            }
            catch (Exception ex)
            {
                Program.Log("battery info error: " + ex.Message);
            }

            if (info.Percent < 0)
            {
                int percent;
                bool onAc;
                Native.GetPowerState(out percent, out onAc);
                info.Percent = percent;
                info.PowerOnline = onAc;
            }

            return info;
        }

        private static int ToInt(object value)
        {
            try { return Convert.ToInt32(value, CultureInfo.InvariantCulture); }
            catch { return 0; }
        }

        private static bool ToBool(object value)
        {
            try { return Convert.ToBoolean(value, CultureInfo.InvariantCulture); }
            catch { return false; }
        }

        private static object TryGet(ManagementBaseObject item, string name)
        {
            try
            {
                var data = item.Properties[name];
                return data == null ? null : data.Value;
            }
            catch { return null; }
        }
    }
}
