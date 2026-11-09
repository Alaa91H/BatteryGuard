// BatteryGuardTray - controller capability, profile, WMI gateway and safety layer.
// All classes here are vendor-neutral except HpBiosWmiGateway, which isolates the
// existing HP hpqBIntM calls so tests can replay them without hardware.

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management;
using System.Threading;

namespace BatteryGuardTray
{
    [Flags]
    internal enum ControllerCapability
    {
        MonitoringOnly = 0,
        AutoInhibit = 1,
        FixedThreshold = 2,
        StartStopThreshold = 4
    }

    internal enum ControllerResultStatus
    {
        Success,
        Unsupported,
        Rejected,
        NotOnAc,
        WriteFailed,
        ReadbackMismatch
    }

    internal enum DeviceSupportStatus
    {
        MonitoringOnly,
        Candidate,
        Documented,
        LabVerified,
        FieldVerified,
        Blocked
    }

    internal sealed class ControllerResult
    {
        public ControllerResultStatus Status;
        public ChargeMode Observed = ChargeMode.Unsupported;
        public string Detail = "";

        public bool Ok { get { return Status == ControllerResultStatus.Success; } }

        public static ControllerResult Success(ChargeMode observed)
        {
            return new ControllerResult { Status = ControllerResultStatus.Success, Observed = observed };
        }

        public static ControllerResult Failure(ControllerResultStatus status, string detail)
        {
            return new ControllerResult { Status = status, Detail = detail ?? "" };
        }

        public override string ToString()
        {
            return Status + (Observed == ChargeMode.Unsupported ? "" : " (" + Observed + ")") +
                (string.IsNullOrEmpty(Detail) ? "" : ": " + Detail);
        }
    }

    internal sealed class ControllerCapabilities
    {
        public ControllerCapability Kind;
        public int MinPercent;
        public int MaxPercent;
        public int Step = 1;
        public int DefaultLimit;
        public bool SupportsResume;
        public bool SupportsFloat;
        public bool CanRestoreAuto;

        public bool CanControlCharge { get { return Kind != ControllerCapability.MonitoringOnly; } }
        public bool CanInhibit { get { return (Kind & ControllerCapability.AutoInhibit) != 0; } }
        public bool IsThreshold
        {
            get { return (Kind & (ControllerCapability.FixedThreshold | ControllerCapability.StartStopThreshold)) != 0; }
        }

        public bool Allows(int percent)
        {
            if (!IsThreshold) return false;
            if (percent < MinPercent || percent > MaxPercent) return false;
            return Step <= 1 || (percent - MinPercent) % Step == 0;
        }

        public string Key
        {
            get
            {
                if ((Kind & ControllerCapability.AutoInhibit) != 0) return "auto-inhibit";
                if ((Kind & ControllerCapability.FixedThreshold) != 0) return "fixed-" + DefaultLimit;
                if ((Kind & ControllerCapability.StartStopThreshold) != 0) return "start-stop";
                return "monitoring";
            }
        }

        public string DisplayName
        {
            get
            {
                if (!CanControlCharge) return Loc.T("Monitoring only");
                if ((Kind & ControllerCapability.FixedThreshold) != 0)
                    return Loc.T("Charge limit") + " " + DefaultLimit.ToString(CultureInfo.InvariantCulture) + "%";
                if ((Kind & ControllerCapability.StartStopThreshold) != 0)
                    return Loc.T("Charge limit") + " " + MinPercent.ToString(CultureInfo.InvariantCulture) +
                        "%–" + MaxPercent.ToString(CultureInfo.InvariantCulture) + "%";
                return Loc.T("Charge control");
            }
        }

        public static ControllerCapabilities Monitoring()
        {
            return new ControllerCapabilities { Kind = ControllerCapability.MonitoringOnly, Step = 1 };
        }

        public static ControllerCapabilities AutoInhibit(int min, int max, int defaultLimit, bool resume, bool floatMode)
        {
            return new ControllerCapabilities
            {
                Kind = ControllerCapability.AutoInhibit,
                MinPercent = min,
                MaxPercent = max,
                Step = 1,
                DefaultLimit = defaultLimit,
                SupportsResume = resume,
                SupportsFloat = floatMode,
                CanRestoreAuto = true
            };
        }

        public static ControllerCapabilities FixedThreshold(int percent)
        {
            return new ControllerCapabilities
            {
                Kind = ControllerCapability.FixedThreshold,
                MinPercent = percent,
                MaxPercent = percent,
                Step = 1,
                DefaultLimit = percent,
                CanRestoreAuto = true
            };
        }

        public static ControllerCapabilities StartStopThreshold(int min, int max, int defaultLimit)
        {
            return new ControllerCapabilities
            {
                Kind = ControllerCapability.StartStopThreshold,
                MinPercent = min,
                MaxPercent = max,
                Step = 1,
                DefaultLimit = defaultLimit,
                SupportsResume = true,
                CanRestoreAuto = true
            };
        }
    }

    internal sealed class DeviceFingerprint
    {
        public string Manufacturer = "Unknown";
        public string Product = "";
        public string Board = "";
        public string BiosVersion = "";
        public string BiosReleaseDate = "";
        public string Family = "";
        public string SystemSku = "";

        public string DisplayName
        {
            get
            {
                string text = ((Manufacturer ?? "") + " " + (Product ?? "")).Trim();
                return text.Length == 0 ? "Unknown" : text;
            }
        }

        public static DeviceFingerprint Read()
        {
            var fingerprint = new DeviceFingerprint();

            try
            {
                using (var searcher = new ManagementObjectSearcher(
                    "SELECT Manufacturer, Model, SystemFamily, SystemSKUNumber FROM Win32_ComputerSystem"))
                {
                    foreach (ManagementObject item in searcher.Get())
                    {
                        fingerprint.Manufacturer = Value(item, "Manufacturer", fingerprint.Manufacturer);
                        fingerprint.Product = Value(item, "Model", fingerprint.Product);
                        fingerprint.Family = Value(item, "SystemFamily", fingerprint.Family);
                        fingerprint.SystemSku = Value(item, "SystemSKUNumber", fingerprint.SystemSku);
                        break;
                    }
                }
            }
            catch (Exception ex)
            {
                Program.Log("fingerprint computer error: " + ex.Message);
            }

            try
            {
                using (var searcher = new ManagementObjectSearcher(
                    "SELECT Product, Manufacturer FROM Win32_BaseBoard"))
                {
                    foreach (ManagementObject item in searcher.Get())
                    {
                        fingerprint.Board = Value(item, "Product", fingerprint.Board);
                        if (string.IsNullOrEmpty(fingerprint.Manufacturer) || fingerprint.Manufacturer == "Unknown")
                            fingerprint.Manufacturer = Value(item, "Manufacturer", fingerprint.Manufacturer);
                        break;
                    }
                }
            }
            catch (Exception ex)
            {
                Program.Log("fingerprint board error: " + ex.Message);
            }

            try
            {
                using (var searcher = new ManagementObjectSearcher(
                    "SELECT SMBIOSBIOSVersion, ReleaseDate FROM Win32_BIOS"))
                {
                    foreach (ManagementObject item in searcher.Get())
                    {
                        fingerprint.BiosVersion = Value(item, "SMBIOSBIOSVersion", fingerprint.BiosVersion);
                        fingerprint.BiosReleaseDate = Value(item, "ReleaseDate", fingerprint.BiosReleaseDate);
                        break;
                    }
                }
            }
            catch (Exception ex)
            {
                Program.Log("fingerprint bios error: " + ex.Message);
            }

            if (string.IsNullOrEmpty(fingerprint.Manufacturer)) fingerprint.Manufacturer = "Unknown";
            if (fingerprint.Product == null) fingerprint.Product = "";
            if (fingerprint.Board == null) fingerprint.Board = "";
            if (fingerprint.BiosVersion == null) fingerprint.BiosVersion = "";
            if (fingerprint.BiosReleaseDate == null) fingerprint.BiosReleaseDate = "";
            if (fingerprint.Family == null) fingerprint.Family = "";
            if (fingerprint.SystemSku == null) fingerprint.SystemSku = "";
            return fingerprint;
        }

        private static string Value(ManagementBaseObject item, string property, string fallback)
        {
            try
            {
                string text = Convert.ToString(item[property], CultureInfo.InvariantCulture);
                return string.IsNullOrEmpty(text) ? fallback : text.Trim();
            }
            catch
            {
                return fallback;
            }
        }
    }

    internal sealed class DeviceProfile
    {
        public string Vendor;
        public string[] ManufacturerPatterns;
        public string[] ProductPatterns;
        public string[] BiosPatterns;
        public string Interface;
        public ControllerCapabilities Capabilities;
        public DeviceSupportStatus Status;
        public string Evidence = "";

        public bool CanWrite
        {
            get
            {
                return Capabilities != null && Capabilities.CanControlCharge &&
                    (Status == DeviceSupportStatus.LabVerified || Status == DeviceSupportStatus.FieldVerified);
            }
        }

        public bool Matches(DeviceFingerprint fingerprint)
        {
            if (fingerprint == null) return false;
            if (!AnyMatch(ManufacturerPatterns, fingerprint.Manufacturer)) return false;
            if (!AnyMatch(ProductPatterns, fingerprint.Product)) return false;
            if (!AnyMatch(BiosPatterns, fingerprint.BiosVersion)) return false;
            return true;
        }

        public string Key
        {
            get
            {
                return (Vendor ?? "Unknown") + "|" + (Interface ?? "") + "|" +
                    (Capabilities == null ? "monitoring" : Capabilities.Key) + "|" + Status;
            }
        }

        private static bool AnyMatch(string[] patterns, string value)
        {
            if (patterns == null || patterns.Length == 0) return true;
            string text = value ?? "";
            for (int index = 0; index < patterns.Length; index++)
            {
                if (Wildcard(patterns[index], text)) return true;
            }
            return false;
        }

        private static bool Wildcard(string pattern, string value)
        {
            if (string.IsNullOrEmpty(pattern)) return true;
            int p = 0;
            int v = 0;
            int star = -1;
            int match = 0;

            while (v < value.Length)
            {
                if (p < pattern.Length && (pattern[p] == '?' || char.ToUpperInvariant(pattern[p]) == char.ToUpperInvariant(value[v])))
                {
                    p++;
                    v++;
                }
                else if (p < pattern.Length && pattern[p] == '*')
                {
                    star = p++;
                    match = v;
                }
                else if (star >= 0)
                {
                    p = star + 1;
                    v = ++match;
                }
                else
                {
                    return false;
                }
            }

            while (p < pattern.Length && pattern[p] == '*') p++;
            return p == pattern.Length;
        }
    }

    internal static class DeviceProfileCatalog
    {
        public static readonly ControllerCapabilities HpCapabilities =
            ControllerCapabilities.AutoInhibit(50, 100, 80, true, true);

        public static readonly DeviceProfile Hp = new DeviceProfile
        {
            Vendor = "HP",
            ManufacturerPatterns = new[] { "HP*", "Hewlett*", "HPE*" },
            ProductPatterns = new[] { "*" },
            BiosPatterns = new[] { "*" },
            Interface = "hpqBIntM",
            Capabilities = HpCapabilities,
            Status = DeviceSupportStatus.FieldVerified,
            Evidence = "Existing HP hardware tests and iqBIntM read-back."
        };

        public static readonly DeviceProfile Acer = new DeviceProfile
        {
            Vendor = "Acer",
            ManufacturerPatterns = new[] { "Acer*" },
            ProductPatterns = new[] { "*Aspire*", "*Swift*", "*Nitro*", "*Predator*" },
            BiosPatterns = new[] { "*" },
            Interface = "root\\WMI BatteryControl",
            Capabilities = ControllerCapabilities.FixedThreshold(80),
            Status = DeviceSupportStatus.Documented,
            Evidence = "Acer BatteryControl health-mode interface; not verified on hardware and no writer is enabled."
        };

        public static readonly DeviceProfile Lenovo = new DeviceProfile
        {
            Vendor = "Lenovo",
            ManufacturerPatterns = new[] { "LENOVO*", "Lenovo*" },
            ProductPatterns = new[] { "ThinkPad*", "IdeaPad*", "Legion*" },
            BiosPatterns = new[] { "*" },
            Interface = "Lenovo WMI/ACPI variants",
            Capabilities = ControllerCapabilities.StartStopThreshold(60, 100, 80),
            Status = DeviceSupportStatus.Candidate,
            Evidence = "Multiple ThinkPad/IdeaPad/Legion interfaces; no single verified Windows writer."
        };

        public static readonly DeviceProfile Dell = new DeviceProfile
        {
            Vendor = "Dell",
            ManufacturerPatterns = new[] { "Dell*" },
            ProductPatterns = new[] { "*" },
            BiosPatterns = new[] { "*" },
            Interface = "Dell BIOS/WMI",
            Capabilities = ControllerCapabilities.StartStopThreshold(50, 100, 80),
            Status = DeviceSupportStatus.Candidate,
            Evidence = "BIOS/Dell WMI is model-specific and may require a BIOS password; not verified."
        };

        public static readonly DeviceProfile Asus = MonitoringProfile("ASUS",
            new[] { "ASUSTeK*", "ASUS*" }, "ASUS ACPI/EC or System Control Interface");
        public static readonly DeviceProfile Msi = MonitoringProfile("MSI",
            new[] { "Micro-Star*", "MSI*" }, "MSI ACPI/EC");
        public static readonly DeviceProfile Razer = MonitoringProfile("Razer",
            new[] { "Razer*" }, "Razer ACPI/EC");
        public static readonly DeviceProfile Samsung = MonitoringProfile("Samsung",
            new[] { "Samsung*" }, "Samsung ACPI/EC");
        public static readonly DeviceProfile Toshiba = MonitoringProfile("Toshiba/Dynabook",
            new[] { "TOSHIBA*", "Dynabook*" }, "Toshiba/Dynabook ACPI/EC");
        public static readonly DeviceProfile Fujitsu = MonitoringProfile("Fujitsu",
            new[] { "FUJITSU*" }, "Fujitsu ACPI/EC");
        public static readonly DeviceProfile Microsoft = MonitoringProfile("Microsoft",
            new[] { "Microsoft*" }, "Surface UEFI; no Windows charge-write interface");
        public static readonly DeviceProfile Framework = MonitoringProfile("Framework",
            new[] { "Framework*" }, "Framework EC/UEFI; no verified Windows writer");

        public static readonly DeviceProfile[] All =
        {
            Hp, Acer, Lenovo, Dell, Asus, Msi, Razer, Samsung, Toshiba, Fujitsu, Microsoft, Framework
        };

        public static DeviceProfile Match(DeviceFingerprint fingerprint)
        {
            if (fingerprint == null) return null;
            for (int index = 0; index < All.Length; index++)
            {
                if (All[index].Matches(fingerprint)) return All[index];
            }
            return null;
        }

        public static bool IsHpManufacturer(string manufacturer)
        {
            return Hp.Matches(new DeviceFingerprint { Manufacturer = manufacturer ?? "" });
        }

        private static DeviceProfile MonitoringProfile(string vendor, string[] manufacturers, string interfaceName)
        {
            return new DeviceProfile
            {
                Vendor = vendor,
                ManufacturerPatterns = manufacturers,
                ProductPatterns = new[] { "*" },
                BiosPatterns = new[] { "*" },
                Interface = interfaceName,
                Capabilities = ControllerCapabilities.Monitoring(),
                Status = DeviceSupportStatus.MonitoringOnly,
                Evidence = "No verified and documented charge-write interface."
            };
        }
    }

    internal interface IControllerProvider
    {
        string Name { get; }
        DeviceProfile Profile { get; }
        bool Matches(DeviceFingerprint fingerprint);
        IChargeController Create(DeviceFingerprint fingerprint);
    }

    internal interface IChargeController : IBatteryController
    {
        DeviceFingerprint Fingerprint { get; }
        ControllerCapabilities Capabilities { get; }
        DeviceProfile Profile { get; }
        ControllerResult RequestInhibit(bool onAc);
        ControllerResult RequestAuto(bool onAc);
    }

    internal sealed class HpControllerProvider : IControllerProvider
    {
        public string Name { get { return "HP"; } }
        public DeviceProfile Profile { get { return DeviceProfileCatalog.Hp; } }

        public bool Matches(DeviceFingerprint fingerprint)
        {
            return DeviceProfileCatalog.Hp.Matches(fingerprint);
        }

        public IChargeController Create(DeviceFingerprint fingerprint)
        {
            return new HpBios(fingerprint);
        }
    }

    internal sealed class GenericControllerProvider : IControllerProvider
    {
        public string Name { get { return "Generic"; } }
        public DeviceProfile Profile { get { return null; } }

        public bool Matches(DeviceFingerprint fingerprint) { return true; }

        public IChargeController Create(DeviceFingerprint fingerprint)
        {
            return new GenericBatteryController(fingerprint, DeviceProfileCatalog.Match(fingerprint));
        }
    }

    internal static class WriteGuard
    {
        public static bool IsSafeMode(ChargeMode mode)
        {
            return mode == ChargeMode.Auto || mode == ChargeMode.Inhibit;
        }

        // The only entry point for a firmware write. It validates capability,
        // AC state and mode, then requires a read-back and rolls back on mismatch.
        public static ControllerResult Apply(ControllerCapabilities capabilities,
            bool onAc, ChargeMode expected, Func<bool> write, Func<ChargeMode> read, Action rollback)
        {
            if (!IsSafeMode(expected))
                return ControllerResult.Failure(ControllerResultStatus.Rejected, "unsafe charge mode");
            if (capabilities == null || !capabilities.CanControlCharge)
                return ControllerResult.Failure(ControllerResultStatus.Unsupported, "monitoring only");
            if (expected == ChargeMode.Inhibit && !onAc)
                return ControllerResult.Failure(ControllerResultStatus.NotOnAc, "charger is not connected");
            if (expected == ChargeMode.Inhibit && !capabilities.CanInhibit)
                return ControllerResult.Failure(ControllerResultStatus.Unsupported, "inhibit is not supported");
            if (expected == ChargeMode.Auto && !capabilities.CanRestoreAuto)
                return ControllerResult.Failure(ControllerResultStatus.Unsupported, "auto restore is not supported");

            bool applied;
            try
            {
                applied = write();
            }
            catch (Exception ex)
            {
                return ControllerResult.Failure(ControllerResultStatus.WriteFailed, ex.Message);
            }

            if (!applied)
                return ControllerResult.Failure(ControllerResultStatus.WriteFailed, "write was rejected");

            Thread.Sleep(400);

            ChargeMode observed;
            try
            {
                observed = read();
            }
            catch (Exception ex)
            {
                Rollback(rollback);
                return ControllerResult.Failure(ControllerResultStatus.WriteFailed, "read-back failed: " + ex.Message);
            }

            if (observed != expected)
            {
                string detail = "expected " + expected + ", read " + observed;
                Rollback(rollback);
                ControllerResult mismatch = ControllerResult.Failure(ControllerResultStatus.ReadbackMismatch, detail);
                mismatch.Observed = observed;
                return mismatch;
            }

            return ControllerResult.Success(observed);
        }

        private static void Rollback(Action rollback)
        {
            if (rollback == null) return;
            try { rollback(); }
            catch (Exception ex) { Program.Log("write rollback error: " + ex.Message); }
        }
    }

    internal sealed class WmiCall
    {
        public uint Command;
        public uint CommandType;
        public byte[] Payload;

        public byte Value
        {
            get { return Payload != null && Payload.Length > 1 ? Payload[1] : (byte)0xFF; }
        }
    }

    internal sealed class WmiCallResult
    {
        public bool TransportOk;
        public uint ReturnCode = 0xFFFF;
        public byte[] Data = new byte[0];
        public string Error = "";

        public static WmiCallResult Ok(uint returnCode, byte[] data)
        {
            return new WmiCallResult
            {
                TransportOk = true,
                ReturnCode = returnCode,
                Data = data == null ? new byte[0] : (byte[])data.Clone()
            };
        }

        public static WmiCallResult Fail(string error)
        {
            return new WmiCallResult { TransportOk = false, Error = error ?? "WMI failure" };
        }
    }

    internal interface IWmiGateway : IDisposable
    {
        WmiCallResult Invoke(uint command, uint commandType, byte[] payload);
    }

    internal sealed class HpBiosWmiGateway : IWmiGateway
    {
        private static readonly byte[] Signature = { 0x53, 0x45, 0x43, 0x55 };
        private readonly ManagementScope _scope;
        private readonly ManagementObject _bios;
        private readonly ManagementClass _inputClass;
        private readonly object _gate = new object();

        public HpBiosWmiGateway()
        {
            _scope = new ManagementScope(@"\\.\root\wmi");
            _scope.Connect();
            _bios = GetBiosInstance(_scope);
            _inputClass = new ManagementClass(_scope, new ManagementPath("hpqBDataIn"), null);
            _inputClass.Get();
        }

        private static ManagementObject GetBiosInstance(ManagementScope scope)
        {
            var biosClass = new ManagementClass(scope, new ManagementPath("hpqBIntM"), null);
            try
            {
                foreach (ManagementObject instance in biosClass.GetInstances())
                    return instance;
            }
            finally
            {
                biosClass.Dispose();
            }
            throw new InvalidOperationException("hpqBIntM instance not found (HP BIOS WMI provider unavailable)");
        }

        public WmiCallResult Invoke(uint command, uint commandType, byte[] payload)
        {
            lock (_gate)
            {
                try
                {
                    using (ManagementBaseObject input = _inputClass.CreateInstance())
                    {
                        input["Command"] = command;
                        input["CommandType"] = commandType;
                        input["Size"] = (uint)payload.Length;
                        input["hpqBData"] = payload;
                        input["Sign"] = Signature;

                        using (ManagementBaseObject parameters = _bios.GetMethodParameters("hpqBIOSInt128"))
                        {
                            parameters["InData"] = input;
                            using (ManagementBaseObject output = _bios.InvokeMethod("hpqBIOSInt128", parameters, null))
                            {
                                var outData = output["OutData"] as ManagementBaseObject;
                                if (outData == null) return WmiCallResult.Fail("hpqBIntM returned no OutData");
                                uint code = Convert.ToUInt32(outData["rwReturnCode"], CultureInfo.InvariantCulture);
                                byte[] data = (outData["Data"] as byte[]) ?? new byte[0];
                                return WmiCallResult.Ok(code, data);
                            }
                        }
                    }
                }
                catch (Exception ex)
                {
                    return WmiCallResult.Fail("wmi error: " + ex.Message);
                }
            }
        }

        public void Dispose()
        {
            try { _bios.Dispose(); } catch { }
            try { _inputClass.Dispose(); } catch { }
        }
    }

    internal sealed class SimulatedWmiGateway : IWmiGateway
    {
        private readonly Queue<WmiCallResult> _responses = new Queue<WmiCallResult>();
        public readonly List<WmiCall> Calls = new List<WmiCall>();

        public void Enqueue(WmiCallResult response)
        {
            _responses.Enqueue(response);
        }

        public WmiCallResult Invoke(uint command, uint commandType, byte[] payload)
        {
            Calls.Add(new WmiCall
            {
                Command = command,
                CommandType = commandType,
                Payload = payload == null ? new byte[0] : (byte[])payload.Clone()
            });

            if (_responses.Count == 0)
                return WmiCallResult.Fail("simulator has no response");
            return _responses.Dequeue();
        }

        public void Dispose() { }
    }
}
