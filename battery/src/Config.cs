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
    internal sealed class WindowRule
    {
        public string From = "00:00";
        public string To = "23:59";
        public int? Ceiling;
    }

    internal static class ScheduleRules
    {
        public static bool Overlaps(WindowRule first, WindowRule second)
        {
            int aStart, aEnd, bStart, bEnd;
            if (!TryClock(first.From, out aStart) || !TryClock(first.To, out aEnd)) return false;
            if (!TryClock(second.From, out bStart) || !TryClock(second.To, out bEnd)) return false;

            if (aStart == aEnd || bStart == bEnd) return true;

            foreach (var left in Segments(aStart, aEnd))
                foreach (var right in Segments(bStart, bEnd))
                    if (left[0] < right[1] && right[0] < left[1]) return true;

            return false;
        }

        public static string FindConflict(GuardConfig config, out WindowRule first, out WindowRule second)
        {
            first = null;
            second = null;
            if (config == null || config.Schedule == null) return null;

            for (int i = 0; i < config.Schedule.Count; i++)
            {
                for (int j = i + 1; j < config.Schedule.Count; j++)
                {
                    if (!Overlaps(config.Schedule[i], config.Schedule[j])) continue;

                    first = config.Schedule[i];
                    second = config.Schedule[j];
                    return Describe(first) + " ↔ " + Describe(second);
                }
            }

            return null;
        }

        public static string Describe(WindowRule rule)
        {
            return rule.From + "–" + rule.To + (rule.Ceiling.HasValue
                ? Loc.T(" (limit ") + rule.Ceiling.Value.ToString(CultureInfo.InvariantCulture) + "%)"
                : Loc.T(" (standard)"));
        }

        private static List<int[]> Segments(int start, int end)
        {
            var segments = new List<int[]>();
            if (start < end)
            {
                segments.Add(new[] { start, end });
            }
            else
            {
                segments.Add(new[] { start, 1440 });
                segments.Add(new[] { 0, end });
            }
            return segments;
        }

        private static bool TryClock(string text, out int minutes)
        {
            minutes = 0;
            if (string.IsNullOrEmpty(text)) return false;

            var parts = text.Split(':');
            int hour, minute;
            if (parts.Length != 2) return false;
            if (!int.TryParse(parts[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out hour)) return false;
            if (!int.TryParse(parts[1], NumberStyles.Integer, CultureInfo.InvariantCulture, out minute)) return false;
            if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return false;

            minutes = hour * 60 + minute;
            return true;
        }
    }

    internal sealed class GuardConfig
    {
        public string Preset = "Off";
        public int? Ceiling;
        public int? Resume;
        public int ResumeDrop = 5;
        public int IntervalSeconds = 60;
        public bool ScheduleEnabled;
        public bool FloatMode;
        public List<WindowRule> Schedule = new List<WindowRule>();

        public static GuardConfig Load(string path)
        {
            var config = new GuardConfig();
            if (!File.Exists(path)) return config;

            try
            {
                var json = File.ReadAllText(path);
                if (string.IsNullOrWhiteSpace(json)) return config;

                var serializer = new JavaScriptSerializer();
                var map = serializer.Deserialize<Dictionary<string, object>>(json);
                if (map == null) return config;

                object value;
                if (map.TryGetValue("preset", out value) && value != null) config.Preset = Convert.ToString(value, CultureInfo.InvariantCulture);
                if (map.TryGetValue("ceiling", out value) && value != null) config.Ceiling = ToInt(value);
                if (map.TryGetValue("resume", out value) && value != null) config.Resume = ToInt(value);
                if (map.TryGetValue("resumeDrop", out value) && value != null) config.ResumeDrop = ToInt(value);
                if (map.TryGetValue("intervalSeconds", out value) && value != null) config.IntervalSeconds = ToInt(value);
                if (map.TryGetValue("scheduleEnabled", out value) && value != null) config.ScheduleEnabled = Convert.ToBoolean(value, CultureInfo.InvariantCulture);
                if (map.TryGetValue("floatMode", out value) && value != null) config.FloatMode = Convert.ToBoolean(value, CultureInfo.InvariantCulture);

                if (map.TryGetValue("schedule", out value) && value != null)
                {
                    var list = value as System.Collections.ArrayList;
                    if (list != null)
                    {
                        foreach (var entry in list)
                        {
                            var window = entry as Dictionary<string, object>;
                            if (window == null) continue;

                            var rule = new WindowRule();
                            object field;
                            if (window.TryGetValue("from", out field) && field != null) rule.From = Convert.ToString(field, CultureInfo.InvariantCulture);
                            if (window.TryGetValue("to", out field) && field != null) rule.To = Convert.ToString(field, CultureInfo.InvariantCulture);
                            if (window.TryGetValue("ceiling", out field) && field != null) rule.Ceiling = ToInt(field);
                            config.Schedule.Add(rule);
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Program.Log("config read error: " + ex.Message);
            }

            return config;
        }

        public void Save(string path)
        {
            var builder = new StringBuilder();
            builder.AppendLine("{");
            builder.AppendLine("  \"preset\": \"" + JsonEscape(Preset) + "\",");
            builder.AppendLine("  \"ceiling\": " + (Ceiling.HasValue ? Ceiling.Value.ToString(CultureInfo.InvariantCulture) : "null") + ",");
            builder.AppendLine("  \"resume\": " + (Resume.HasValue ? Resume.Value.ToString(CultureInfo.InvariantCulture) : "null") + ",");
            builder.AppendLine("  \"resumeDrop\": " + ResumeDrop.ToString(CultureInfo.InvariantCulture) + ",");
            builder.AppendLine("  \"intervalSeconds\": " + IntervalSeconds.ToString(CultureInfo.InvariantCulture) + ",");
            builder.AppendLine("  \"scheduleEnabled\": " + (ScheduleEnabled ? "true" : "false") + ",");
            builder.AppendLine("  \"floatMode\": " + (FloatMode ? "true" : "false") + ",");
            builder.AppendLine("  \"schedule\": [");
            for (int i = 0; i < Schedule.Count; i++)
            {
                var rule = Schedule[i];
                builder.Append("    { \"from\": \"" + JsonEscape(rule.From) + "\", \"to\": \"" + JsonEscape(rule.To) + "\", \"ceiling\": ");
                builder.Append(rule.Ceiling.HasValue ? rule.Ceiling.Value.ToString(CultureInfo.InvariantCulture) : "null");
                builder.Append(" }");
                if (i < Schedule.Count - 1) builder.Append(",");
                builder.AppendLine();
            }
            builder.AppendLine("  ]");
            builder.AppendLine("}");

            File.WriteAllText(path, builder.ToString(), new UTF8Encoding(false));
        }

        private static int ToInt(object value)
        {
            return Convert.ToInt32(value, CultureInfo.InvariantCulture);
        }

        private static string JsonEscape(string text)
        {
            if (string.IsNullOrEmpty(text)) return string.Empty;
            return text.Replace("\\", "\\\\").Replace("\"", "\\\"");
        }
    }

    internal static class UiSettings
    {
        private static readonly string FilePath = Path.Combine(Program.BaseDirectory, "interface.ini");

        public static bool ShowCeiling;
        public static bool Notifications = true;
        public static bool FullNotify = true;
        public static int FullThreshold = 100;
        public static bool LowNotify = true;
        public static int LowThreshold = 20;
        public static bool HealthNotify = true;
        public static int HealthThreshold = 70;
        public static string Language = "auto";
        public static string Direction = "auto";

        public static bool Rtl
        {
            get
            {
                if (string.Equals(Direction, "rtl", StringComparison.OrdinalIgnoreCase)) return true;
                if (string.Equals(Direction, "ltr", StringComparison.OrdinalIgnoreCase)) return false;
                return Loc.IsRtl(Loc.Code);
            }
        }

        public static void Load()
        {
            try
            {
                if (File.Exists(FilePath))
                foreach (string line in File.ReadAllLines(FilePath))
                {
                    int split = line.IndexOf('=');
                    if (split <= 0) continue;

                    string key = line.Substring(0, split).Trim();
                    string value = line.Substring(split + 1).Trim();
                    bool on = string.Equals(value, "on", StringComparison.OrdinalIgnoreCase) ||
                              value == "1" || string.Equals(value, "true", StringComparison.OrdinalIgnoreCase);

                    if (string.Equals(key, "showCeiling", StringComparison.OrdinalIgnoreCase)) ShowCeiling = on;
                    else if (string.Equals(key, "notifications", StringComparison.OrdinalIgnoreCase)) Notifications = on;
                    else if (string.Equals(key, "fullNotify", StringComparison.OrdinalIgnoreCase)) FullNotify = on;
                    else if (string.Equals(key, "lowNotify", StringComparison.OrdinalIgnoreCase)) LowNotify = on;
                    else if (string.Equals(key, "fullThreshold", StringComparison.OrdinalIgnoreCase)) FullThreshold = ParseInt(value, 100);
                    else if (string.Equals(key, "lowThreshold", StringComparison.OrdinalIgnoreCase)) LowThreshold = ParseInt(value, 20);
                    else if (string.Equals(key, "healthNotify", StringComparison.OrdinalIgnoreCase)) HealthNotify = on;
                    else if (string.Equals(key, "healthThreshold", StringComparison.OrdinalIgnoreCase)) HealthThreshold = ParseInt(value, 70);
                    else if (string.Equals(key, "language", StringComparison.OrdinalIgnoreCase)) Language = value;
                    else if (string.Equals(key, "direction", StringComparison.OrdinalIgnoreCase)) Direction = value;
                }
            }
            catch (Exception ex)
            {
                Program.Log("ui settings read error: " + ex.Message);
            }

            Loc.Load(Language);
        }

        public static void Save()
        {
            try
            {
                File.WriteAllText(FilePath,
                    "showCeiling=" + (ShowCeiling ? "on" : "off") + Environment.NewLine +
                    "notifications=" + (Notifications ? "on" : "off") + Environment.NewLine +
                    "fullNotify=" + (FullNotify ? "on" : "off") + Environment.NewLine +
                    "fullThreshold=" + FullThreshold.ToString(CultureInfo.InvariantCulture) + Environment.NewLine +
                    "lowNotify=" + (LowNotify ? "on" : "off") + Environment.NewLine +
                    "lowThreshold=" + LowThreshold.ToString(CultureInfo.InvariantCulture) + Environment.NewLine +
                    "healthNotify=" + (HealthNotify ? "on" : "off") + Environment.NewLine +
                    "healthThreshold=" + HealthThreshold.ToString(CultureInfo.InvariantCulture) + Environment.NewLine +
                    "language=" + Language + Environment.NewLine +
                    "direction=" + Direction + Environment.NewLine,
                    new UTF8Encoding(false));
            }
            catch (Exception ex)
            {
                Program.Log("ui settings write error: " + ex.Message);
            }
        }

        private static int ParseInt(string text, int fallback)
        {
            int value;
            if (int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out value)) return value;
            return fallback;
        }
    }

    internal static class Autostart
    {
        private const string TaskName = "BatteryGuardTray";
        private const string LegacyTask = "BatteryGuard";

        public static bool IsInstalled()
        {
            return Run("schtasks.exe", "/Query /TN " + TaskName) == 0;
        }

        public static bool Install()
        {
            string command = BuildCommand();
            string trigger = "/TR \"" + command.Replace("\"", "\\\"") + "\"";
            int code = Run("schtasks.exe", "/Create /TN " + TaskName + " " + trigger + " /SC ONLOGON /RL HIGHEST /F");
            Run("schtasks.exe", "/Delete /TN " + LegacyTask + " /F");
            Program.Log("autostart install exit=" + code.ToString(CultureInfo.InvariantCulture));
            return code == 0;
        }

        private static string BuildCommand()
        {
            string host = Environment.GetEnvironmentVariable("BATTERYGUARD_HOST");
            string entry = Environment.GetEnvironmentVariable("BATTERYGUARD_ENTRY");
            if (string.Equals(host, "ps1", StringComparison.OrdinalIgnoreCase) && !string.IsNullOrEmpty(entry))
            {
                string powerShell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
                return "\"" + powerShell + "\" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + entry + "\" -NoElevate";
            }
            return "\"" + System.Reflection.Assembly.GetExecutingAssembly().Location + "\"";
        }

        public static bool Remove()
        {
            int code = Run("schtasks.exe", "/Delete /TN " + TaskName + " /F");
            Program.Log("autostart remove exit=" + code.ToString(CultureInfo.InvariantCulture));
            return code == 0;
        }

        private static int Run(string file, string arguments)
        {
            try
            {
                var info = new ProcessStartInfo(file, arguments);
                info.CreateNoWindow = true;
                info.UseShellExecute = false;
                info.RedirectStandardOutput = true;
                info.RedirectStandardError = true;
                using (var process = Process.Start(info))
                {
                    process.StandardOutput.ReadToEnd();
                    process.StandardError.ReadToEnd();
                    process.WaitForExit(15000);
                    return process.HasExited ? process.ExitCode : -1;
                }
            }
            catch (Exception ex)
            {
                Program.Log("schtasks error: " + ex.Message);
                return -1;
            }
        }
    }
}
