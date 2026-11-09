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
    internal enum ThemeMode
    {
        Auto,
        Light,
        Dark
    }

    internal static class ThemeSettings
    {
        private static readonly object Gate = new object();
        private static readonly string FilePath = Path.Combine(Program.BaseDirectory, "theme.ini");
        private static int _appsLight = -1;
        private static int _systemLight = -1;

        public static ThemeMode Mode = ThemeMode.Auto;

        public static string ModeName
        {
            get
            {
                if (Mode == ThemeMode.Dark) return "dark";
                if (Mode == ThemeMode.Light) return "light";
                return "auto";
            }
        }

        public static void Load()
        {
            try
            {
                if (!File.Exists(FilePath)) return;
                string text = File.ReadAllText(FilePath).Trim().ToLowerInvariant();
                if (text == "dark") Mode = ThemeMode.Dark;
                else if (text == "light") Mode = ThemeMode.Light;
                else Mode = ThemeMode.Auto;
            }
            catch (Exception ex)
            {
                Program.Log("theme read error: " + ex.Message);
            }
        }

        public static void Save()
        {
            try
            {
                File.WriteAllText(FilePath, ModeName + Environment.NewLine, new UTF8Encoding(false));
            }
            catch (Exception ex)
            {
                Program.Log("theme write error: " + ex.Message);
            }
        }

        public static void SetMode(ThemeMode mode)
        {
            Mode = mode;
            Save();
            Apply();
        }

        public static bool AppsLight
        {
            get
            {
                lock (Gate)
                {
                    if (_appsLight < 0) _appsLight = Read("AppsUseLightTheme") ? 1 : 0;
                    return _appsLight == 1;
                }
            }
        }

        public static bool SystemLight
        {
            get
            {
                lock (Gate)
                {
                    if (_systemLight < 0) _systemLight = Read("SystemUsesLightTheme") ? 1 : 0;
                    return _systemLight == 1;
                }
            }
        }

        public static bool MenuDark
        {
            get { return Mode == ThemeMode.Dark || (Mode == ThemeMode.Auto && !AppsLight); }
        }

        public static bool TaskbarDark
        {
            get { return Mode == ThemeMode.Dark || (Mode == ThemeMode.Auto && !SystemLight); }
        }

        public static Color Ink
        {
            get { return TaskbarDark ? Color.FromArgb(235, 240, 245) : Color.FromArgb(24, 30, 36); }
        }

        public static void Invalidate()
        {
            lock (Gate)
            {
                _appsLight = -1;
                _systemLight = -1;
            }
        }

        public static void Apply()
        {
            int preferred = Mode == ThemeMode.Dark ? 2 : (Mode == ThemeMode.Light ? 3 : 1);
            try
            {
                Native.SetPreferredAppMode(preferred);
                Native.FlushMenuThemes();
            }
            catch (Exception ex)
            {
                Program.Log("theme apply error: " + ex.Message);
            }

            Program.Log(string.Format(CultureInfo.InvariantCulture,
                "theme mode={0} appsLight={1} systemLight={2} menu={3} glyph={4}",
                ModeName, AppsLight ? "yes" : "no", SystemLight ? "yes" : "no",
                MenuDark ? "dark" : "light", TaskbarDark ? "light" : "dark"));
        }

        private static bool Read(string valueName)
        {
            try
            {
                object value = Microsoft.Win32.Registry.GetValue(
                    @"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", valueName, null);
                if (value is int) return (int)value != 0;
                if (value is long) return (long)value != 0;
            }
            catch { }
            return true;
        }
    }

    internal sealed class CardPanel : Panel
    {
        private readonly string _title;

        public CardPanel(string title)
        {
            _title = title;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.UserPaint, true);
            Padding = new Padding(14, 34, 14, 12);
            Margin = new Padding(0);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            bool dark = ThemeSettings.MenuDark;
            bool rtl = UiSettings.Rtl;
            Color background = UiTheme.CardBack(dark);
            Color border = dark ? Color.FromArgb(64, 68, 74) : Color.FromArgb(214, 218, 224);
            Color ink = UiTheme.Ink(dark);
            Color accent = UiTheme.Accent(dark);

            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;

            using (var path = RoundedRect(new Rectangle(0, 0, Width - 1, Height - 1), 10f))
            using (var fill = new SolidBrush(background))
            using (var pen = new Pen(border))
            {
                e.Graphics.FillPath(fill, path);
                e.Graphics.DrawPath(pen, path);
            }

            int barX = rtl ? Width - 19 : 16;
            using (var bar = new SolidBrush(accent))
                e.Graphics.FillRectangle(bar, barX, 13, 3, 14);

            using (var titleFont = new Font(Font.FontFamily, Font.Size + 0.5f, FontStyle.Bold))
            {
                TextFormatFlags flags = TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis;
                flags |= rtl ? TextFormatFlags.Right : TextFormatFlags.Left;
                var area = rtl ? new Rectangle(16, 8, Width - 42, 22) : new Rectangle(28, 8, Width - 42, 22);
                TextRenderer.DrawText(e.Graphics, _title, titleFont, area, ink, flags);
            }
        }

        private static GraphicsPath RoundedRect(Rectangle bounds, float radius)
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
    }

    internal static class UiTheme
    {
        public static Color FormBack(bool dark)
        {
            return dark ? Color.FromArgb(32, 34, 38) : Color.FromArgb(247, 248, 250);
        }

        public static Color CardBack(bool dark)
        {
            return dark ? Color.FromArgb(40, 43, 48) : Color.White;
        }

        public static Color Ink(bool dark)
        {
            return dark ? Color.FromArgb(236, 241, 246) : Color.FromArgb(28, 34, 40);
        }

        public static Color Muted(bool dark)
        {
            return dark ? Color.FromArgb(158, 167, 177) : Color.FromArgb(105, 112, 120);
        }

        public static Color Accent(bool dark)
        {
            return dark ? Color.FromArgb(72, 196, 128) : Color.FromArgb(24, 145, 84);
        }

        public static Color Warning(bool dark)
        {
            return dark ? Color.FromArgb(240, 168, 72) : Color.FromArgb(176, 98, 0);
        }

        public static void Apply(Form form)
        {
            bool dark = ThemeSettings.MenuDark;
            Color back = FormBack(dark);
            Color fore = Ink(dark);

            form.BackColor = back;
            form.ForeColor = fore;
            Style(form, back, fore, dark);
        }

        public static void Primary(Button button, bool dark)
        {
            button.FlatStyle = FlatStyle.Flat;
            button.FlatAppearance.BorderSize = 0;
            button.FlatAppearance.MouseOverBackColor = dark ? Color.FromArgb(56, 180, 116) : Color.FromArgb(20, 130, 74);
            button.FlatAppearance.MouseDownBackColor = dark ? Color.FromArgb(38, 140, 88) : Color.FromArgb(18, 112, 64);
            button.BackColor = Accent(dark);
            button.ForeColor = Color.White;
        }

        private static void Style(Control control, Color back, Color fore, bool dark)
        {
            var card = control as CardPanel;
            if (card != null)
            {
                Color surface = CardBack(dark);
                card.BackColor = surface;
                card.ForeColor = fore;
                foreach (Control child in card.Controls)
                    Style(child, surface, fore, dark);
                return;
            }

            try { control.BackColor = back; } catch { }
            try { control.ForeColor = fore; } catch { }

            var button = control as Button;
            if (button != null)
            {
                button.FlatStyle = FlatStyle.Flat;
                button.FlatAppearance.BorderSize = 1;
                button.FlatAppearance.BorderColor = dark ? Color.FromArgb(78, 84, 92) : Color.FromArgb(198, 202, 208);
                button.BackColor = dark ? Color.FromArgb(48, 52, 58) : Color.White;
                button.ForeColor = fore;
            }

            var combo = control as ComboBox;
            if (combo != null)
            {
                combo.FlatStyle = FlatStyle.Flat;
                combo.BackColor = dark ? Color.FromArgb(44, 47, 52) : Color.White;
                combo.ForeColor = fore;
            }

            var list = control as ListView;
            if (list != null)
            {
                list.BackColor = dark ? Color.FromArgb(44, 47, 52) : Color.White;
                list.ForeColor = fore;
            }

            var numeric = control as NumericUpDown;
            if (numeric != null)
            {
                numeric.BackColor = dark ? Color.FromArgb(44, 47, 52) : Color.White;
                numeric.ForeColor = fore;
            }

            var text = control as TextBox;
            if (text != null)
            {
                text.BackColor = dark ? Color.FromArgb(44, 47, 52) : Color.White;
                text.ForeColor = fore;
            }

            var date = control as DateTimePicker;
            if (date != null)
            {
                try
                {
                    date.CalendarMonthBackground = dark ? Color.FromArgb(44, 47, 52) : Color.White;
                    date.CalendarForeColor = fore;
                    date.CalendarTitleBackColor = dark ? Color.FromArgb(48, 52, 58) : Color.FromArgb(236, 238, 241);
                    date.CalendarTitleForeColor = fore;
                }
                catch { }
            }

            foreach (Control child in control.Controls)
                Style(child, back, fore, dark);
        }
    }

    internal sealed class DualRangeSlider : Control
    {
        private int _lower = 55;
        private int _upper = 60;
        private int _drag;

        public int MinimumValue;
        public int MaximumValue;
        public int Gap;
        public event EventHandler ValuesChanged;

        public DualRangeSlider()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.UserPaint | ControlStyles.Selectable, true);

            MinimumValue = 40;
            MaximumValue = 100;
            Gap = 5;
            Height = 64;
            TabStop = true;
        }

        public int LowerValue
        {
            get { return _lower; }
            set { SetValues(value, _upper); }
        }

        public int UpperValue
        {
            get { return _upper; }
            set { SetValues(_lower, value); }
        }

        public void SetValues(int lower, int upper)
        {
            int lo = Math.Max(MinimumValue, Math.Min(lower, MaximumValue));
            int hi = Math.Max(MinimumValue, Math.Min(upper, MaximumValue));

            if (hi < lo + Gap) hi = Math.Min(MaximumValue, lo + Gap);
            if (hi < lo + Gap) lo = Math.Max(MinimumValue, hi - Gap);

            bool changed = lo != _lower || hi != _upper;
            _lower = lo;
            _upper = hi;

            if (!changed) return;
            Invalidate();
            var handler = ValuesChanged;
            if (handler != null) handler(this, EventArgs.Empty);
        }

        public void SetValuesSilent(int lower, int upper)
        {
            int lo = Math.Max(MinimumValue, Math.Min(lower, MaximumValue));
            int hi = Math.Max(MinimumValue, Math.Min(upper, MaximumValue));
            if (hi < lo + Gap) hi = Math.Min(MaximumValue, lo + Gap);
            if (hi < lo + Gap) lo = Math.Max(MinimumValue, hi - Gap);
            _lower = lo;
            _upper = hi;
            Invalidate();
        }

        private int TrackLeft { get { return 16; } }
        private int TrackRight { get { return Width - 17; } }

        private int ValueToX(int value)
        {
            double fraction = (value - MinimumValue) / (double)(MaximumValue - MinimumValue);
            if (RightToLeft == RightToLeft.Yes) fraction = 1 - fraction;
            return TrackLeft + (int)Math.Round(fraction * (TrackRight - TrackLeft));
        }

        private double XToFraction(int x)
        {
            double fraction = (x - TrackLeft) / (double)(TrackRight - TrackLeft);
            fraction = Math.Max(0, Math.Min(1, fraction));
            if (RightToLeft == RightToLeft.Yes) fraction = 1 - fraction;
            return fraction;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            bool dark = ThemeSettings.MenuDark;
            bool enabled = Enabled;
            Color track = dark ? Color.FromArgb(64, 68, 75) : Color.FromArgb(214, 218, 223);
            Color accent = enabled
                ? (dark ? Color.FromArgb(72, 196, 128) : Color.FromArgb(24, 145, 84))
                : (dark ? Color.FromArgb(92, 98, 104) : Color.FromArgb(168, 172, 178));
            Color resume = enabled
                ? (dark ? Color.FromArgb(240, 168, 72) : Color.FromArgb(200, 118, 20))
                : (dark ? Color.FromArgb(92, 98, 104) : Color.FromArgb(168, 172, 178));

            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;

            int y = 26;
            int lowerX = ValueToX(_lower);
            int upperX = ValueToX(_upper);
            int left = Math.Min(lowerX, upperX);
            int right = Math.Max(lowerX, upperX);

            using (var back = new Pen(track, 6f))
            {
                back.StartCap = LineCap.Round;
                back.EndCap = LineCap.Round;
                e.Graphics.DrawLine(back, TrackLeft, y, TrackRight, y);
            }

            using (var fill = new Pen(accent, 6f))
            {
                fill.StartCap = LineCap.Round;
                fill.EndCap = LineCap.Round;
                e.Graphics.DrawLine(fill, left, y, right, y);
            }

            DrawThumb(e.Graphics, lowerX, y, resume, dark);
            DrawThumb(e.Graphics, upperX, y, accent, dark);

            TextFormatFlags flags = TextFormatFlags.NoPadding | TextFormatFlags.SingleLine;
            Color faint = dark ? Color.FromArgb(160, 168, 178) : Color.FromArgb(110, 116, 124);
            bool rtl = RightToLeft == RightToLeft.Yes;
            string leftLabel = rtl ? MaximumValue.ToString(CultureInfo.InvariantCulture) : MinimumValue.ToString(CultureInfo.InvariantCulture);
            string rightLabel = rtl ? MinimumValue.ToString(CultureInfo.InvariantCulture) : MaximumValue.ToString(CultureInfo.InvariantCulture);
            TextRenderer.DrawText(e.Graphics, leftLabel, Font,
                new Rectangle(TrackLeft - 4, 42, 40, 18), faint, flags | TextFormatFlags.Left);
            TextRenderer.DrawText(e.Graphics, rightLabel, Font,
                new Rectangle(TrackRight - 36, 42, 40, 18), faint, flags | TextFormatFlags.Right);

            if (Focused)
            {
                using (var pen = new Pen(accent) { DashStyle = DashStyle.Dot })
                    e.Graphics.DrawRectangle(pen, 1, 1, Width - 3, Height - 3);
            }
        }

        private static void DrawThumb(Graphics graphics, int x, int y, Color color, bool dark)
        {
            using (var brush = new SolidBrush(color))
            using (var ring = new Pen(dark ? Color.FromArgb(24, 26, 30) : Color.White, 2f))
            {
                graphics.FillEllipse(brush, x - 8, y - 8, 16, 16);
                graphics.DrawEllipse(ring, x - 8, y - 8, 16, 16);
            }
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (!Enabled) return;

            Focus();
            int lowerX = ValueToX(_lower);
            int upperX = ValueToX(_upper);

            if (Math.Abs(e.X - upperX) <= 12 || Math.Abs(e.X - lowerX) <= 12)
                _drag = Math.Abs(e.X - upperX) <= Math.Abs(e.X - lowerX) ? 2 : 1;
            else
            {
                double fraction = XToFraction(e.X);
                int value = MinimumValue + (int)Math.Round(fraction * (MaximumValue - MinimumValue));
                _drag = Math.Abs(value - _upper) <= Math.Abs(value - _lower) ? 2 : 1;
            }

            ApplyDrag(e.X);
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            if (_drag != 0) ApplyDrag(e.X);
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            _drag = 0;
        }

        private void ApplyDrag(int x)
        {
            double fraction = XToFraction(x);
            int value = MinimumValue + (int)Math.Round(fraction * (MaximumValue - MinimumValue));

            if (_drag == 1)
                SetValues(Math.Min(value, _upper - Gap), _upper);
            else if (_drag == 2)
                SetValues(_lower, Math.Max(value, _lower + Gap));
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            base.OnKeyDown(e);
            int step = e.Shift ? 5 : 1;

            if (e.KeyCode == Keys.Up || e.KeyCode == Keys.Right)
            {
                SetValues(_lower, Math.Min(MaximumValue, _upper + step));
                e.Handled = true;
            }
            else if (e.KeyCode == Keys.Down || e.KeyCode == Keys.Left)
            {
                SetValues(_lower, Math.Max(_lower + Gap, _upper - step));
                e.Handled = true;
            }
        }
    }
}
