// BatteryGuardTray - Windows notification identity for BatteryGuard.
// Windows attributes tray balloons and notifications to the process that owns
// the icon. When the UI is hosted by powershell.exe that label is PowerShell,
// so register a stable AUMID and a matching Start Menu shortcut.

using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

namespace BatteryGuardTray
{
    internal static class AppIdentity
    {
        internal const string AppId = "BatteryGuard.Tray";
        private const string ShortcutName = "BatteryGuard.lnk";
        private const ushort VtLpwstr = 31;

        private static readonly PROPERTYKEY PKEY_AppUserModel_ID = new PROPERTYKEY
        {
            FormatId = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"),
            PropertyId = 5
        };

        public static void Install()
        {
            try
            {
                int hr = Native.SetCurrentProcessExplicitAppUserModelID(AppId);
                if (hr != 0)
                    Program.Log("app identity: AUMID hr=" + hr.ToString(System.Globalization.CultureInfo.InvariantCulture));
            }
            catch (Exception ex)
            {
                Program.Log("app identity error: " + ex.Message);
            }

            try
            {
                EnsureShortcut();
            }
            catch (Exception ex)
            {
                Program.Log("shortcut error: " + ex.Message);
            }
        }

        private static void EnsureShortcut()
        {
            string folder = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                @"Microsoft\Windows\Start Menu\Programs");
            if (string.IsNullOrEmpty(folder)) return;

            Directory.CreateDirectory(folder);
            string shortcutPath = Path.Combine(folder, ShortcutName);

            string target;
            string arguments;
            if (!TryPowerShellHost(out target, out arguments))
            {
                target = Application.ExecutablePath;
                arguments = "";
            }

            if (string.IsNullOrEmpty(target) || !File.Exists(target)) return;

            string icon = Path.Combine(Program.BaseDirectory, @"resources\application.ico");
            if (!File.Exists(icon)) icon = target;

            IShellLinkW link = (IShellLinkW)new ShellLink();
            try
            {
                link.SetPath(target);
                link.SetArguments(arguments);
                link.SetWorkingDirectory(Program.BaseDirectory);
                link.SetDescription("BatteryGuard battery monitor");
                link.SetIconLocation(icon, 0);

                IPropertyStore store = (IPropertyStore)link;
                PROPERTYKEY key = PKEY_AppUserModel_ID;
                PROPVARIANT value = new PROPVARIANT();
                value.vt = VtLpwstr;
                value.pointerValue = Marshal.StringToCoTaskMemUni(AppId);
                try
                {
                    store.SetValue(ref key, ref value);
                    store.Commit();
                }
                finally
                {
                    PropVariantClear(ref value);
                }

                ((IPersistFile)link).Save(shortcutPath, true);
                Program.Log("app identity: shortcut " + shortcutPath);
            }
            finally
            {
                Marshal.ReleaseComObject(link);
            }
        }

        private static bool TryPowerShellHost(out string target, out string arguments)
        {
            target = null;
            arguments = null;

            string host = Environment.GetEnvironmentVariable("BATTERYGUARD_HOST");
            string entry = Environment.GetEnvironmentVariable("BATTERYGUARD_ENTRY");
            if (!string.Equals(host, "ps1", StringComparison.OrdinalIgnoreCase) ||
                string.IsNullOrEmpty(entry) || !File.Exists(entry)) return false;

            string powerShell = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System),
                @"WindowsPowerShell\v1.0\powershell.exe");
            if (!File.Exists(powerShell)) powerShell = "powershell.exe";

            target = powerShell;
            arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + entry + "\" -NoElevate";
            return true;
        }

        [DllImport("ole32.dll")]
        private static extern int PropVariantClear(ref PROPVARIANT value);

        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        private struct PROPERTYKEY
        {
            public Guid FormatId;
            public uint PropertyId;
        }

        // The extra pointer keeps the native PROPVARIANT size correct on both
        // 32-bit (16 bytes) and 64-bit (24 bytes) processes.
        [StructLayout(LayoutKind.Sequential, Pack = 8)]
        private struct PROPVARIANT
        {
            public ushort vt;
            public ushort wReserved1;
            public ushort wReserved2;
            public ushort wReserved3;
            public IntPtr pointerValue;
            public IntPtr padding;
        }

        [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
        private class ShellLink
        {
        }

        [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IShellLinkW
        {
            void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszFile, int cch, IntPtr pfd, uint fFlags);
            void GetIDList(out IntPtr ppidl);
            void SetIDList(IntPtr pidl);
            void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszName, int cch);
            void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);
            void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszDir, int cch);
            void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);
            void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszArgs, int cch);
            void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string pszArgs);
            void GetHotkey(out short pwHotkey);
            void SetHotkey(short wHotkey);
            void GetShowCmd(out int piShowCmd);
            void SetShowCmd(int iShowCmd);
            void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszIconPath, int cch, out int piIcon);
            void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string pszIconPath, int iIcon);
            void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string pszPathRel, uint dwReserved);
            void Resolve(IntPtr hwnd, uint fFlags);
            void SetPath([MarshalAs(UnmanagedType.LPWStr)] string pszFile);
        }

        [ComImport, Guid("0000010B-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IPersistFile
        {
            void GetClassID(out Guid pClassID);
            [PreserveSig] int IsDirty();
            void Load([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, uint dwMode);
            void Save([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, [MarshalAs(UnmanagedType.Bool)] bool fRemember);
            void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string pszFileName);
            void GetCurFile([MarshalAs(UnmanagedType.LPWStr)] out string ppszFileName);
        }

        [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IPropertyStore
        {
            void GetCount(out uint cProps);
            void GetAt(uint iProp, out PROPERTYKEY pkey);
            void GetValue(ref PROPERTYKEY key, out PROPVARIANT pv);
            void SetValue(ref PROPERTYKEY key, ref PROPVARIANT pv);
            void Commit();
        }
    }
}
