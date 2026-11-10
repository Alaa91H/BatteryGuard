using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace BatteryGuardTray
{
    internal static class VisualCaptureHost
    {
        private const int WmClose = 0x0010;
        private const int DwmwaExtendedFrameBounds = 9;

        [StructLayout(LayoutKind.Sequential)]
        private struct Rect
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr FindWindow(string className, string windowName);

        [DllImport("user32.dll")]
        private static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern bool PrintWindow(IntPtr window, IntPtr hdc, uint flags);

        [DllImport("user32.dll")]
        private static extern uint GetDpiForWindow(IntPtr window);

        [DllImport("dwmapi.dll")]
        private static extern int DwmGetWindowAttribute(IntPtr window, int attribute, out Rect value, int size);

        [STAThread]
        private static void Main(string[] args)
        {
            string root = args.Length > 0 ? Path.GetFullPath(args[0]) : Environment.CurrentDirectory;
            string output = args.Length > 1 ? Path.GetFullPath(args[1]) : AppDomain.CurrentDomain.BaseDirectory;
            Environment.SetEnvironmentVariable("BATTERYGUARD_HOME", root);

            string uiPath = Path.Combine(root, "interface.ini");
            string themePath = Path.Combine(root, "theme.ini");
            string configPath = Path.Combine(root, "visual.test-backup.json");
            string logPath = Path.Combine(root, "visual.test-backup.log");
            byte[] uiBackup = File.Exists(uiPath) ? File.ReadAllBytes(uiPath) : null;
            byte[] themeBackup = File.Exists(themePath) ? File.ReadAllBytes(themePath) : null;

            try
            {
                File.WriteAllText(configPath, ConfigJson(), new UTF8Encoding(false));
                File.WriteAllText(logPath, LogText(), new UTF8Encoding(false));

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);

                foreach (string theme in new[] { "light", "dark" })
                {
                    foreach (string language in new[] { "en", "ar" })
                    {
                        SetLanguage(uiPath, language);
                        SetTheme(themePath, theme);
                        UiSettings.Load();
                        ThemeSettings.Load();
                        ThemeSettings.Apply();

                        string suffix = language + "-" + theme;
                        using (var settings = new SettingsForm(configPath, delegate { }))
                            Capture(settings, Path.Combine(output, "visual-settings-" + suffix + ".png"));
                        using (var schedule = new WindowRuleForm(null))
                            Capture(schedule, Path.Combine(output, "visual-schedule-" + suffix + ".png"));
                        using (var log = new LogForm(logPath))
                            Capture(log, Path.Combine(output, "visual-log-" + suffix + ".png"));
                    }
                }
            }
            finally
            {
                Restore(uiPath, uiBackup);
                Restore(themePath, themeBackup);
                Remove(configPath);
                Remove(logPath);
            }
        }

        private static void Capture(Form form, string path)
        {
            form.TopMost = true;
            form.ShowInTaskbar = false;
            form.StartPosition = FormStartPosition.Manual;
            form.Location = new Point(20, 20);
            form.Show();
            Application.DoEvents();
            Thread.Sleep(300);

            HideTouchKeyboard();
            form.Activate();
            form.BringToFront();
            Button button = FindButton(form);
            if (button != null) button.Focus();
            Application.DoEvents();
            Thread.Sleep(180);
            HideTouchKeyboard();

            Rect frame;
            if (DwmGetWindowAttribute(form.Handle, DwmwaExtendedFrameBounds, out frame, Marshal.SizeOf(typeof(Rect))) != 0)
            {
                frame = new Rect { Left = form.Left, Top = form.Top, Right = form.Right, Bottom = form.Bottom };
            }

            int width = Math.Max(1, frame.Right - frame.Left);
            int height = Math.Max(1, frame.Bottom - frame.Top);
            using (var bitmap = new Bitmap(width, height))
            using (var graphics = Graphics.FromImage(bitmap))
            {
                graphics.CopyFromScreen(frame.Left, frame.Top, 0, 0, new Size(width, height));
                bitmap.Save(path, ImageFormat.Png);
            }

            string variant = Path.Combine(Path.GetDirectoryName(path), Path.GetFileNameWithoutExtension(path) + "-client.png");
            Rectangle client = form.RectangleToScreen(form.ClientRectangle);
            using (var bitmap = new Bitmap(client.Width, client.Height))
            using (var graphics = Graphics.FromImage(bitmap))
            {
                graphics.CopyFromScreen(client.Left, client.Top, 0, 0, client.Size);
                bitmap.Save(variant, ImageFormat.Png);
            }

            variant = Path.Combine(Path.GetDirectoryName(path), Path.GetFileNameWithoutExtension(path) + "-draw.png");
            using (var bitmap = new Bitmap(form.Width, form.Height))
            {
                form.DrawToBitmap(bitmap, new Rectangle(0, 0, form.Width, form.Height));
                bitmap.Save(variant, ImageFormat.Png);
            }

            variant = Path.Combine(Path.GetDirectoryName(path), Path.GetFileNameWithoutExtension(path) + "-print.png");
            using (var bitmap = new Bitmap(form.Width, form.Height))
            using (var graphics = Graphics.FromImage(bitmap))
            {
                IntPtr hdc = graphics.GetHdc();
                try { PrintWindow(form.Handle, hdc, 2); }
                finally { graphics.ReleaseHdc(hdc); }
                bitmap.Save(variant, ImageFormat.Png);
            }

            Rectangle clientScreen = form.RectangleToScreen(form.ClientRectangle);
            Console.WriteLine(
                Path.GetFileName(path) + ": dpi=" + form.DeviceDpi +
                " windowDpi=" + GetDpiForWindow(form.Handle) +
                " client=" + form.ClientSize.Width + "x" + form.ClientSize.Height +
                " image=" + width + "x" + height +
                " frame=" + frame.Left + "," + frame.Top + "," + frame.Right + "," + frame.Bottom +
                " clientScreen=" + clientScreen.Left + "," + clientScreen.Top + "," + clientScreen.Right + "," + clientScreen.Bottom);
            if (form is LogForm)
            {
                var status = (Label)form.GetType().GetField("_status", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic).GetValue(form);
                var bar = status.Parent;
                Console.WriteLine("log status=" + status.Bounds + " bar=" + bar.Bounds + " barClient=" + bar.ClientSize + " text=" + status.Text);
            }
            if (form is SettingsForm)
            {
                var limit = (CheckBox)form.GetType().GetField("_limitEnabled", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic).GetValue(form);
                var schedule = (CheckBox)form.GetType().GetField("_schedule", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic).GetValue(form);
                var list = (ListView)form.GetType().GetField("_scheduleList", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic).GetValue(form);
                Console.WriteLine("settings limit=" + limit.Bounds + " font=" + limit.Font.Size + " schedule=" + schedule.Bounds + " font=" + schedule.Font.Size);
                Console.WriteLine("scheduleList client=" + list.ClientSize + " columns=" + list.Columns[0].Width + "," + list.Columns[1].Width + "," + list.Columns[2].Width);
            }
            form.Hide();
        }

        private static Button FindButton(Control root)
        {
            foreach (Control child in root.Controls)
            {
                var button = child as Button;
                if (button != null && button.Visible && button.Enabled) return button;
                Button nested = FindButton(child);
                if (nested != null) return nested;
            }
            return null;
        }

        private static void HideTouchKeyboard()
        {
            CloseWindow(FindWindow("IPTip_Main_Window", null));
            CloseWindow(FindWindow("Windows.UI.Core.CoreWindow", "Microsoft Text Input Application"));
        }

        private static void CloseWindow(IntPtr window)
        {
            if (window != IntPtr.Zero) PostMessage(window, WmClose, IntPtr.Zero, IntPtr.Zero);
        }

        private static void SetLanguage(string path, string code)
        {
            string direction = code == "ar" ? "rtl" : "ltr";
            File.WriteAllText(path,
                "showCeiling=on" + Environment.NewLine +
                "notifications=on" + Environment.NewLine +
                "language=" + code + Environment.NewLine +
                "direction=" + direction + Environment.NewLine,
                new UTF8Encoding(false));
        }

        private static void SetTheme(string path, string theme)
        {
            File.WriteAllText(path, theme + Environment.NewLine, new UTF8Encoding(false));
        }

        private static void Restore(string path, byte[] contents)
        {
            if (contents == null) Remove(path);
            else File.WriteAllBytes(path, contents);
        }

        private static void Remove(string path)
        {
            try { if (File.Exists(path)) File.Delete(path); } catch { }
        }

        private static string ConfigJson()
        {
            return @"{
  ""preset"": ""Custom"",
  ""ceiling"": 80,
  ""resume"": 75,
  ""resumeDrop"": 5,
  ""intervalSeconds"": 60,
  ""scheduleEnabled"": true,
  ""floatMode"": true,
  ""schedule"": [
    { ""from"": ""00:00"", ""to"": ""08:00"", ""ceiling"": 60 },
    { ""from"": ""12:00"", ""to"": ""14:00"", ""ceiling"": null }
  ]
}";
        }

        private static string LogText()
        {
            var text = new StringBuilder();
            for (int index = 0; index < 32; index++)
            {
                text.Append("2026-11-10 12:00:");
                text.Append(index.ToString("00"));
                text.Append("  [tray] controller: HP ENVY x360 Convertible 13-ay0xxx (monitoring only); inhibit write rejected (rc=65535); charge write blocked before transport; policy=Custom; battery=80%; ac=yes");
                text.AppendLine();
            }
            return text.ToString();
        }
    }
}
