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
    internal static class Program
    {
        internal static readonly string BaseDirectory = ResolveBaseDirectory();
        internal static readonly string LocaleDirectory = Path.Combine(BaseDirectory, "locales");
        internal static readonly string ConfigPathVisible = Path.Combine(BaseDirectory, "settings.json");
        internal static readonly string LogPathVisible = Path.Combine(BaseDirectory, "application.log");
        internal static long MaxLogBytes = 1024 * 1024;
        private static Mutex _mutex;

        private static string ResolveBaseDirectory()
        {
            try
            {
                string home = Environment.GetEnvironmentVariable("BATTERYGUARD_HOME");
                if (!string.IsNullOrEmpty(home) && Directory.Exists(home)) return home;
                string location = typeof(Program).Assembly.Location;
                if (!string.IsNullOrEmpty(location)) return Path.GetDirectoryName(location);
            }
            catch { }
            return AppDomain.CurrentDomain.BaseDirectory;
        }

        // Older builds used product-named data files. Move them once so an
        // existing installation keeps its settings without keeping the old names.
        private static void MigrateLegacyDataFiles()
        {
            MoveIfMissing("BatteryGuard.config.json", "settings.json");
            MoveIfMissing("ui.txt", "interface.ini");
            MoveIfMissing("theme.txt", "theme.ini");
            MoveIfMissing("capacity.txt", "capacity.ini");
            MoveIfMissing("batteryguard.log", "application.log");
            MoveIfMissing("batteryguard.previous.log", "application.previous.log");
        }

        private static void MoveIfMissing(string oldName, string newName)
        {
            try
            {
                string oldPath = Path.Combine(BaseDirectory, oldName);
                string newPath = Path.Combine(BaseDirectory, newName);
                if (File.Exists(oldPath) && !File.Exists(newPath)) File.Move(oldPath, newPath);
            }
            catch { }
        }

        [STAThread]
        private static void Main(string[] args)
        {
            MigrateLegacyDataFiles();
            Native.SetProcessDPIAware();

            try
            {
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
            }
            catch { }

            if (HasArgument(args, "--install-autostart")) { Autostart.Install(); return; }
            if (HasArgument(args, "--remove-autostart")) { Autostart.Remove(); return; }

            if (HasArgument(args, "--status") || HasArgument(args, "--once"))
            {
                try
                {
                    using (var engine = new Engine())
                    {
                        string action = engine.Tick(HasArgument(args, "--once"));
                        Log(string.Format(CultureInfo.InvariantCulture, "cli {0}: {1}% ac={2} mode={3} policy={4} action={5}",
                            HasArgument(args, "--once") ? "--once" : "--status",
                            engine.Percent, engine.OnAc ? "yes" : "no", engine.Mode, engine.Current.Label, action));
                    }
                }
                catch (Exception ex)
                {
                    Log("cli error: " + ex.Message);
                }
                return;
            }

            bool created;
            _mutex = new Mutex(true, "Local\\BatteryGuardTray", out created);
            if (!created) return;

            try
            {
                AppIdentity.Install();
                using (var app = new TrayApp()) { app.Run(); }
            }
            catch (Exception ex)
            {
                Log("fatal: " + ex);
            }
        }

        private static bool HasArgument(string[] args, string name)
        {
            foreach (var argument in args)
                if (string.Equals(argument, name, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        internal static void Log(string message)
        {
            try
            {
                RotateLogIfNeeded();

                File.AppendAllText(LogPathVisible,
                    DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture) + "  [tray] " + message + Environment.NewLine,
                    new UTF8Encoding(false));
            }
            catch { }
        }

        private static void RotateLogIfNeeded()
        {
            if (!File.Exists(LogPathVisible)) return;

            var info = new FileInfo(LogPathVisible);
            if (info.Length < MaxLogBytes) return;

            string archive = Path.Combine(BaseDirectory, "application.previous.log");
            if (File.Exists(archive)) File.Delete(archive);
            File.Move(LogPathVisible, archive);
        }
    }
}
