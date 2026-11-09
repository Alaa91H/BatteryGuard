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
    internal static class UiLayout
    {
        // A DPI-scaled dialog can grow past a small working area. Clamp it once;
        // AutoScroll keeps the remaining content reachable.
        public static void Fit(Form form)
        {
            try
            {
                Rectangle area = Screen.FromControl(form).WorkingArea;
                int maxWidth = Math.Max(320, area.Width - 32);
                int maxHeight = Math.Max(240, area.Height - 32);

                // The design minimum must not force a window past a small working
                // area. Lower it first; the scrollable content remains reachable.
                int minWidth = Math.Min(form.MinimumSize.Width, maxWidth);
                int minHeight = Math.Min(form.MinimumSize.Height, maxHeight);
                if (form.MinimumSize.Width > minWidth || form.MinimumSize.Height > minHeight)
                    form.MinimumSize = new Size(minWidth, minHeight);

                int width = Math.Min(Math.Max(form.Width, minWidth), maxWidth);
                int height = Math.Min(Math.Max(form.Height, minHeight), maxHeight);
                form.Size = new Size(width, height);
            }
            catch { }
        }
    }

    internal sealed class WindowRuleForm : Form
    {
        private readonly DateTimePicker _from = new DateTimePicker();
        private readonly DateTimePicker _to = new DateTimePicker();
        private readonly CheckBox _normal = new CheckBox();
        private readonly NumericUpDown _ceiling = new NumericUpDown();

        public WindowRule Rule { get; private set; }

        public WindowRuleForm(WindowRule existing)
        {
            Rule = existing ?? new WindowRule();

            Text = existing == null ? Loc.T("Add a scheduling time window") : Loc.T("Edit schedule time window");
            FormBorderStyle = FormBorderStyle.FixedDialog;
            StartPosition = FormStartPosition.CenterParent;
            MaximizeBox = false;
            MinimizeBox = false;
            ShowInTaskbar = false;
            ShowIcon = false;
            AutoScaleMode = AutoScaleMode.Dpi;
            ClientSize = new Size(500, 400);
            MinimumSize = new Size(440, 320);
            RightToLeft = UiSettings.Rtl ? RightToLeft.Yes : RightToLeft.No;
            RightToLeftLayout = UiSettings.Rtl;
            Font = new Font("Segoe UI", 9.5f);

            var content = new Panel();
            content.Name = "RuleContent";
            content.Dock = DockStyle.Fill;
            content.AutoScroll = true;
            content.Margin = new Padding(0);
            Controls.Add(content);

            var layout = new TableLayoutPanel();
            layout.Name = "RuleLayout";
            layout.Dock = DockStyle.Top;
            layout.AutoSize = true;
            layout.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            layout.MinimumSize = new Size(360, 0);
            layout.ColumnCount = 2;
            layout.Padding = new Padding(14, 12, 14, 10);
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 45f));
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 55f));
            content.Controls.Add(layout);

            _from.Format = DateTimePickerFormat.Custom;
            _from.CustomFormat = "HH:mm";
            _from.ShowUpDown = true;
            _from.Value = ParseTime(Rule.From);

            _to.Format = DateTimePickerFormat.Custom;
            _to.CustomFormat = "HH:mm";
            _to.ShowUpDown = true;
            _to.Value = ParseTime(Rule.To);

            _normal.Text = Loc.T("Standard charging in this time window");
            _normal.AutoSize = true;
            _normal.Checked = !Rule.Ceiling.HasValue;
            _normal.CheckedChanged += delegate { _ceiling.Enabled = !_normal.Checked; };

            _ceiling.Minimum = 50;
            _ceiling.Maximum = 100;
            _ceiling.Value = Clamp(Rule.Ceiling ?? 80, 50, 100);
            _ceiling.Enabled = Rule.Ceiling.HasValue;

            AddRow(layout, Loc.T("From"), _from);
            AddRow(layout, Loc.T("To"), _to);
            AddWide(layout, _normal);
            AddRow(layout, Loc.T("Charge limit %"), _ceiling);

            var note = new Label();
            note.Name = "RuleNote";
            note.Text = Loc.T("If the start and end times are the same, the time window is applied to the entire day.");
            note.AutoSize = true;
            note.MaximumSize = new Size(420, 0);
            note.Dock = DockStyle.None;
            note.Anchor = AnchorStyles.Left | AnchorStyles.Right;
            note.TextAlign = UiSettings.Rtl ? ContentAlignment.MiddleRight : ContentAlignment.MiddleLeft;
            AddWide(layout, note);

            content.Resize += delegate
            {
                layout.Width = Math.Max(360, content.ClientSize.Width);
                note.MaximumSize = new Size(Math.Max(240, layout.Width - 32), 0);
            };

            var buttons = new FlowLayoutPanel();
            buttons.Dock = DockStyle.Bottom;
            buttons.Height = 48;
            buttons.FlowDirection = UiSettings.Rtl ? FlowDirection.RightToLeft : FlowDirection.LeftToRight;
            if (UiSettings.Rtl) buttons.RightToLeft = RightToLeft.No;
            buttons.Padding = new Padding(12, 8, 12, 8);

            var ok = new Button();
            ok.Name = "RuleSave";
            ok.Text = Loc.T("Save");
            ok.AutoSize = true;
            ok.MinimumSize = new Size(96, 30);

            var cancel = new Button();
            cancel.Name = "RuleCancel";
            cancel.Text = Loc.T("Cancel");
            cancel.AutoSize = true;
            cancel.MinimumSize = new Size(96, 30);
            cancel.DialogResult = DialogResult.Cancel;

            ok.Click += delegate
            {
                Rule.From = _from.Value.ToString("HH:mm", CultureInfo.InvariantCulture);
                Rule.To = _to.Value.ToString("HH:mm", CultureInfo.InvariantCulture);
                Rule.Ceiling = _normal.Checked ? (int?)null : (int)_ceiling.Value;
                DialogResult = DialogResult.OK;
            };

            buttons.Controls.Add(ok);
            buttons.Controls.Add(cancel);
            Controls.Add(buttons);

            AcceptButton = ok;
            CancelButton = cancel;

            UiTheme.Apply(this);
            bool dark = ThemeSettings.MenuDark;
            note.ForeColor = UiTheme.Muted(dark);
            UiTheme.Primary(ok, dark);
            UiLayout.Fit(this);
        }

        private static void AddRow(TableLayoutPanel layout, string label, Control control)
        {
            var text = new Label();
            text.Text = label;
            text.AutoSize = true;
            text.Anchor = AnchorStyles.Right;
            text.Margin = new Padding(4, 9, 4, 9);

            control.Anchor = AnchorStyles.Left | AnchorStyles.Right;
            control.Margin = new Padding(4, 5, 4, 5);

            layout.Controls.Add(text);
            layout.Controls.Add(control);
        }

        private static void AddWide(TableLayoutPanel layout, Control control)
        {
            control.Margin = new Padding(4, 10, 4, 4);
            layout.Controls.Add(control);
            layout.SetColumnSpan(control, 2);
        }

        private static decimal Clamp(int value, int minimum, int maximum)
        {
            if (value < minimum) return minimum;
            if (value > maximum) return maximum;
            return value;
        }

        private static DateTime ParseTime(string text)
        {
            DateTime parsed;
            if (DateTime.TryParseExact(text, "HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out parsed)) return parsed;
            return DateTime.Today;
        }
    }

    internal sealed class SettingsForm : Form
    {
        private readonly string _configPath;
        private readonly Action<string, string, uint> _testNotify;
        private readonly List<Button> _chips = new List<Button>();
        private readonly CheckBox _limitEnabled = new CheckBox();
        private readonly DualRangeSlider _slider = new DualRangeSlider();
        private readonly NumericUpDown _ceilingValue = new NumericUpDown();
        private readonly NumericUpDown _resumeValue = new NumericUpDown();
        private readonly CheckBox _floatMode = new CheckBox();
        private readonly CheckBox _schedule = new CheckBox();
        private readonly ListView _scheduleList = new ListView();
        private readonly Button _scheduleAdd = new Button();
        private readonly Button _scheduleEdit = new Button();
        private readonly Button _scheduleRemove = new Button();
        private readonly CheckBox _fullNotify = new CheckBox();
        private readonly NumericUpDown _fullThreshold = new NumericUpDown();
        private readonly CheckBox _lowNotify = new CheckBox();
        private readonly NumericUpDown _lowThreshold = new NumericUpDown();
        private readonly CheckBox _healthNotify = new CheckBox();
        private readonly NumericUpDown _healthThreshold = new NumericUpDown();
        private readonly ComboBox _language = new ComboBox();
        private readonly ComboBox _direction = new ComboBox();
        private readonly CheckBox _showCeiling = new CheckBox();
        private readonly CheckBox _notifications = new CheckBox();
        private readonly Label _batteryInfo = new Label();
        private readonly Label _scheduleHint = new Label();
        private readonly Label _scheduleEmpty = new Label();
        private readonly Button _saveButton = new Button();
        private readonly Label _footerHint = new Label();
        private TableLayoutPanel _scheduleGrid;
        private readonly ToolTip _tips = new ToolTip();
        internal bool SuppressMessages { get; set; }
        internal string ValidationError;
        private bool _syncing;
        private bool _adjustingFooter;

        public SettingsForm(string configPath, Action<string, string, uint> testNotify)
        {
            _configPath = configPath;
            _testNotify = testNotify;
            UiSettings.Load();
            BuildUi();
            LoadValues(GuardConfig.Load(configPath));
            UpdateBatteryInfo();
            ApplyTheme();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing) _tips.Dispose();
            base.Dispose(disposing);
        }

        private void BuildUi()
        {
            SuspendLayout();

            Text = Loc.T("BatteryGuard — Settings");
            FormBorderStyle = FormBorderStyle.Sizable;
            StartPosition = FormStartPosition.CenterScreen;
            MaximizeBox = false;
            MinimizeBox = false;
            TopMost = true;
            ShowInTaskbar = true;
            AutoScaleMode = AutoScaleMode.Dpi;
            ClientSize = new Size(780, 1000);
            MinimumSize = new Size(620, 480);
            Font = new Font("Segoe UI", 9.5f);
            AutoScroll = false;
            RightToLeft = UiSettings.Rtl ? RightToLeft.Yes : RightToLeft.No;
            RightToLeftLayout = UiSettings.Rtl;

            var content = new Panel();
            content.Name = "SettingsContent";
            content.Dock = DockStyle.Fill;
            content.AutoScroll = true;
            content.Margin = new Padding(0);

            var root = new TableLayoutPanel();
            root.Name = "SettingsRoot";
            root.Dock = DockStyle.None;
            root.AutoSize = false;
            root.Location = new Point(0, 0);
            root.Width = 780;
            root.Height = 930;
            root.ColumnCount = 1;
            root.RowCount = 5;
            root.Padding = new Padding(14, 12, 14, 8);
            root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 104f));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 240f));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 210f));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 180f));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 176f));
            content.Controls.Add(root);

            var battery = new CardPanel(Loc.T("Battery"));
            battery.Dock = DockStyle.Fill;
            _batteryInfo.Dock = DockStyle.Fill;
            _batteryInfo.AutoSize = false;
            _batteryInfo.AutoEllipsis = false;
            _batteryInfo.Font = new Font("Segoe UI", 10.25f);
            _batteryInfo.TextAlign = UiSettings.Rtl ? ContentAlignment.MiddleRight : ContentAlignment.MiddleLeft;
            battery.Controls.Add(_batteryInfo);
            root.Controls.Add(battery);

            root.Controls.Add(BuildChargeCard());
            root.Controls.Add(BuildScheduleCard());
            root.Controls.Add(BuildNotificationsCard());
            root.Controls.Add(BuildInterfaceCard());

            var footer = BuildButtons();
            footer.Name = "SettingsFooter";
            content.Resize += delegate { root.Width = Math.Max(660, content.ClientSize.Width); };
            Controls.Add(content);
            Controls.Add(footer);
            Resize += delegate { AdjustFooter(footer); };
            AdjustFooter(footer);

            _tips.SetToolTip(_limitEnabled, Loc.T("When activated, charging stops at the specified limit instead of 100%."));
            _tips.SetToolTip(_slider, Loc.T("Drag the green handle to cap the charge and the orange to recharge (up to 1%)."));
            _tips.SetToolTip(_ceilingValue, Loc.T("The highest percentage that charging reaches before stopping (50–100%)."));
            _tips.SetToolTip(_resumeValue, Loc.T("The percentage at which charging resumes after a drop, from 1% to 5 points below the limit."));
            _tips.SetToolTip(_floatMode, Loc.T("After reaching the limit, the device remains on charger power and does not return to the battery."));
            _tips.SetToolTip(_schedule, Loc.T("Multiple time windows; each has its own limit or standard charging."));
            _tips.SetToolTip(_scheduleList, Loc.T("Schedule time windows are checked in order; the first matching time window applies."));
            _tips.SetToolTip(_scheduleAdd, Loc.T("Add a new time window (from/to/limit)."));
            _tips.SetToolTip(_scheduleEdit, Loc.T("Edit the selected time window."));
            _tips.SetToolTip(_scheduleRemove, Loc.T("Delete the selected time window."));
            _tips.SetToolTip(_fullNotify, Loc.T("Notification when the specified charging completion percentage is reached."));
            _tips.SetToolTip(_fullThreshold, Loc.T("Full threshold (50–100%)."));
            _tips.SetToolTip(_lowNotify, Loc.T("Notification when the battery drops below the specified limit."));
            _tips.SetToolTip(_lowThreshold, Loc.T("Low threshold (5–50%)."));
            _tips.SetToolTip(_healthNotify, Loc.T("Notification when battery health deteriorates below limit."));
            _tips.SetToolTip(_healthThreshold, Loc.T("Health threshold (40–95%)."));
            _tips.SetToolTip(_direction, Loc.T("Interface direction: Automatic by system, or explicit RTL/LTR."));
            _tips.SetToolTip(_showCeiling, Loc.T("Show the limit number inside the battery icon."));
            _tips.SetToolTip(_notifications, Loc.T("Turn all system notifications on or off (test notifications are always on)."));

            ResumeLayout(false);
            PerformLayout();
            UiLayout.Fit(this);
        }

        private Control BuildChargeCard()
        {
            var card = new CardPanel(Loc.T("Charge control"));
            card.Dock = DockStyle.Fill;

            var layout = new TableLayoutPanel();
            layout.Dock = DockStyle.Fill;
            layout.ColumnCount = 1;
            layout.RowCount = 5;
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 26f));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 66f));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 34f));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 34f));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 32f));
            card.Controls.Add(layout);

            _limitEnabled.Text = Loc.T("Apply charge limit and resume level");
            _limitEnabled.AutoSize = true;
            _limitEnabled.CheckedChanged += delegate { UpdateEnabled(); };
            layout.Controls.Add(_limitEnabled);

            _slider.Dock = DockStyle.Fill;
            _slider.MinimumValue = 1;
            _slider.MaximumValue = 100;
            _slider.Gap = 5;
            _slider.ValuesChanged += OnSliderChanged;
            layout.Controls.Add(_slider);

            var values = new FlowLayoutPanel();
            values.Dock = DockStyle.Fill;
            values.FlowDirection = FlowDirection.LeftToRight; // the form mirrors the row in RTL
            values.WrapContents = false;
            values.Margin = new Padding(0);

            _ceilingValue.Minimum = 50;
            _ceilingValue.Maximum = 100;
            _ceilingValue.Value = 80;
            _ceilingValue.Width = 64;
            _ceilingValue.ValueChanged += OnCeilingValueChanged;

            _resumeValue.Minimum = 1;
            _resumeValue.Maximum = 95;
            _resumeValue.Value = 75;
            _resumeValue.Width = 64;
            _resumeValue.ValueChanged += OnResumeValueChanged;

            values.Controls.Add(MakeCaption(Loc.T("Charge limit")));
            values.Controls.Add(_ceilingValue);
            values.Controls.Add(MakeCaption("%"));
            values.Controls.Add(MakeSpacer(14));
            values.Controls.Add(MakeCaption(Loc.T("Recharge")));
            values.Controls.Add(_resumeValue);
            values.Controls.Add(MakeCaption("%"));
            layout.Controls.Add(values);

            var presets = new FlowLayoutPanel();
            presets.Dock = DockStyle.Fill;
            presets.FlowDirection = FlowDirection.LeftToRight; // the form mirrors the row in RTL
            presets.WrapContents = false;
            presets.Margin = new Padding(0);
            presets.Controls.Add(MakeChip("100 / 95", 100, 95));
            presets.Controls.Add(MakeChip("80 / 75", 80, 75));
            presets.Controls.Add(MakeChip("60 / 55", 60, 55));
            layout.Controls.Add(presets);

            _floatMode.Text = Loc.T("Float mode — keep the device on charger power after limit");
            _floatMode.AutoSize = true;
            layout.Controls.Add(_floatMode);

            return card;
        }

        private Control BuildScheduleCard()
        {
            var card = new CardPanel(Loc.T("Schedule"));
            card.Dock = DockStyle.Fill;

            var layout = new TableLayoutPanel();
            layout.Dock = DockStyle.Fill;
            layout.ColumnCount = 1;
            layout.RowCount = 4;
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 30f));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 0f));
            layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 36f));
            card.Controls.Add(layout);
            _scheduleGrid = layout;

            _schedule.Text = Loc.T("Enable scheduling");
            _schedule.AutoSize = true;
            _schedule.CheckedChanged += delegate { UpdateEnabled(); RefreshScheduleState(); };
            layout.Controls.Add(_schedule, 0, 0);

            _scheduleHint.Dock = DockStyle.Fill;
            _scheduleHint.AutoSize = false;
            _scheduleHint.AutoEllipsis = true;
            _scheduleHint.TextAlign = UiSettings.Rtl ? ContentAlignment.MiddleRight : ContentAlignment.MiddleLeft;
            _scheduleHint.Margin = new Padding(0, 2, 0, 2);
            _scheduleHint.Visible = false;
            layout.Controls.Add(_scheduleHint, 0, 1);

            var listHost = new Panel();
            listHost.Dock = DockStyle.Fill;
            listHost.Margin = new Padding(0);

            _scheduleList.Dock = DockStyle.Fill;
            _scheduleList.View = View.Details;
            _scheduleList.RightToLeftLayout = UiSettings.Rtl;
            _scheduleList.FullRowSelect = true;
            _scheduleList.MultiSelect = false;
            _scheduleList.HideSelection = false;
            _scheduleList.Columns.Add(Loc.T("From"), 90);
            _scheduleList.Columns.Add(Loc.T("To"), 90);
            _scheduleList.Columns.Add(Loc.T("Limit"), 150);
            _scheduleList.SelectedIndexChanged += delegate { UpdateEnabled(); };
            _scheduleList.DoubleClick += delegate { EditScheduleRule(); };
            _scheduleList.Resize += delegate { ResizeScheduleColumns(); };
            listHost.Controls.Add(_scheduleList);

            _scheduleEmpty.Dock = DockStyle.Fill;
            _scheduleEmpty.AutoSize = false;
            _scheduleEmpty.TextAlign = ContentAlignment.MiddleCenter;
            _scheduleEmpty.Visible = false;
            listHost.Controls.Add(_scheduleEmpty);
            _scheduleEmpty.BringToFront();

            layout.Controls.Add(listHost, 0, 2);

            _scheduleAdd.Text = Loc.T("Add…");
            _scheduleAdd.Width = 84;
            _scheduleAdd.Height = 28;
            _scheduleAdd.Click += delegate { AddScheduleRule(); };

            _scheduleEdit.Text = Loc.T("Edit…");
            _scheduleEdit.Width = 84;
            _scheduleEdit.Height = 28;
            _scheduleEdit.Click += delegate { EditScheduleRule(); };

            _scheduleRemove.Text = Loc.T("Delete");
            _scheduleRemove.Width = 84;
            _scheduleRemove.Height = 28;
            _scheduleRemove.Click += delegate { RemoveScheduleRule(); };

            var buttons = new FlowLayoutPanel();
            buttons.Dock = DockStyle.Fill;
            buttons.FlowDirection = FlowDirection.LeftToRight; // the form mirrors the row in RTL
            buttons.WrapContents = false;
            buttons.Margin = new Padding(0);
            buttons.Controls.Add(_scheduleAdd);
            buttons.Controls.Add(_scheduleEdit);
            buttons.Controls.Add(_scheduleRemove);
            layout.Controls.Add(buttons, 0, 3);

            return card;
        }

        private void ResizeScheduleColumns()
        {
            if (_scheduleList.Columns.Count < 3) return;

            int width = _scheduleList.ClientSize.Width;
            if (width < 160) return;

            int edge = Math.Max(64, (width - 8) / 3);
            _scheduleList.Columns[0].Width = edge;
            _scheduleList.Columns[1].Width = edge;
            _scheduleList.Columns[2].Width = Math.Max(64, width - edge - edge - 4);
        }

        private void RefreshScheduleState()
        {
            bool dark = ThemeSettings.MenuDark;
            Color normal = UiTheme.Ink(dark);
            Color conflict = UiTheme.Warning(dark);

            var rules = new List<WindowRule>();
            foreach (ListViewItem item in _scheduleList.Items)
            {
                rules.Add(RuleFromItem(item));
                item.ForeColor = normal;
            }

            string warning = null;
            for (int first = 0; first < rules.Count && warning == null; first++)
            {
                for (int second = first + 1; second < rules.Count; second++)
                {
                    if (!ScheduleRules.Overlaps(rules[first], rules[second])) continue;

                    warning = ScheduleRules.Describe(rules[first]) + " ↔ " + ScheduleRules.Describe(rules[second]);
                    _scheduleList.Items[first].ForeColor = conflict;
                    _scheduleList.Items[second].ForeColor = conflict;
                    break;
                }
            }

            _scheduleHint.Text = warning == null ? string.Empty : "! " + warning + Loc.T(" — adjust one before saving.");
            _scheduleHint.ForeColor = conflict;
            _scheduleHint.Visible = warning != null;
            if (_scheduleGrid != null)
                _scheduleGrid.RowStyles[1].Height = warning == null ? 0f : 34f;

            bool empty = _scheduleList.Items.Count == 0;
            _scheduleEmpty.Visible = empty;
            _scheduleEmpty.ForeColor = UiTheme.Muted(dark);
            _scheduleEmpty.Text = _schedule.Checked
                ? Loc.T("No schedule time windows yet.\nClick “Add…” to create the first one.")
                : Loc.T("Schedule is off.\nEnable scheduling, then add a window.");
        }

        private void AddScheduleRule()
        {
            using (var dialog = new WindowRuleForm(null))
            {
                if (dialog.ShowDialog(this) != DialogResult.OK) return;

                string conflict = FindConflict(dialog.Rule, -1);
                if (conflict != null) { Fail(conflict); return; }

                AddScheduleItem(dialog.Rule);
                _schedule.Checked = true;
                RefreshScheduleState();
            }
        }

        private void EditScheduleRule()
        {
            if (_scheduleList.SelectedIndices.Count == 0) return;

            int index = _scheduleList.SelectedIndices[0];
            var rule = RuleFromItem(_scheduleList.Items[index]);

            using (var dialog = new WindowRuleForm(rule))
            {
                if (dialog.ShowDialog(this) != DialogResult.OK) return;

                string conflict = FindConflict(dialog.Rule, index);
                if (conflict != null) { Fail(conflict); return; }

                _scheduleList.Items.RemoveAt(index);
                AddScheduleItem(dialog.Rule);
                RefreshScheduleState();
            }
        }

        private void RemoveScheduleRule()
        {
            if (_scheduleList.SelectedItems.Count == 0) return;
            _scheduleList.Items.Remove(_scheduleList.SelectedItems[0]);
            RefreshScheduleState();
        }

        private void AddScheduleItem(WindowRule rule)
        {
            var item = new ListViewItem(rule.From);
            item.SubItems.Add(rule.To);
            item.SubItems.Add(rule.Ceiling.HasValue
                ? rule.Ceiling.Value.ToString(CultureInfo.InvariantCulture) + "%"
                : Loc.T("Standard"));
            _scheduleList.Items.Add(item);
        }

        private static int? ParseCeiling(string text)
        {
            if (string.IsNullOrEmpty(text) || text == Loc.T("Standard")) return null;
            int value;
            if (int.TryParse(text.TrimEnd('%'), NumberStyles.Integer, CultureInfo.InvariantCulture, out value)) return value;
            return null;
        }

        private static WindowRule RuleFromItem(ListViewItem item)
        {
            var rule = new WindowRule();
            rule.From = item.SubItems[0].Text;
            rule.To = item.SubItems[1].Text;
            rule.Ceiling = ParseCeiling(item.SubItems[2].Text);
            return rule;
        }

        private string FindConflict(WindowRule candidate, int skipIndex)
        {
            for (int index = 0; index < _scheduleList.Items.Count; index++)
            {
                if (index == skipIndex) continue;

                var existing = RuleFromItem(_scheduleList.Items[index]);
                if (ScheduleRules.Overlaps(candidate, existing))
                    return Loc.T("Window ") + ScheduleRules.Describe(candidate) + Loc.T(" with ") + ScheduleRules.Describe(existing) + Loc.T(". Adjust the times before saving.");
            }

            return null;
        }

        private bool Fail(string message)
        {
            ValidationError = message;
            if (!SuppressMessages)
                MessageBox.Show(this, message, "BatteryGuard", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return false;
        }

        private Control BuildNotificationsCard()
        {
            var card = new CardPanel(Loc.T("Notifications"));
            card.Dock = DockStyle.Fill;

            var layout = new TableLayoutPanel();
            layout.Dock = DockStyle.Fill;
            layout.ColumnCount = 1;
            layout.RowCount = 3;
            layout.RowStyles.Add(new RowStyle(SizeType.Percent, 33.33f));
            layout.RowStyles.Add(new RowStyle(SizeType.Percent, 33.33f));
            layout.RowStyles.Add(new RowStyle(SizeType.Percent, 33.34f));

            _fullNotify.Text = Loc.T("Notify when charge reaches");
            _fullNotify.AutoSize = true;
            _fullNotify.CheckedChanged += delegate { UpdateEnabled(); };

            _fullThreshold.Minimum = 50;
            _fullThreshold.Maximum = 100;
            _fullThreshold.Value = 100;
            _fullThreshold.Width = 60;

            _lowNotify.Text = Loc.T("Low battery under");
            _lowNotify.AutoSize = true;
            _lowNotify.CheckedChanged += delegate { UpdateEnabled(); };

            _lowThreshold.Minimum = 5;
            _lowThreshold.Maximum = 50;
            _lowThreshold.Value = 20;
            _lowThreshold.Width = 60;

            _healthNotify.Text = Loc.T("Low battery health under");
            _healthNotify.AutoSize = true;
            _healthNotify.CheckedChanged += delegate { UpdateEnabled(); };

            _healthThreshold.Minimum = 40;
            _healthThreshold.Maximum = 95;
            _healthThreshold.Value = 70;
            _healthThreshold.Width = 60;

            layout.Controls.Add(NotificationRow(_fullNotify, _fullThreshold));
            layout.Controls.Add(NotificationRow(_lowNotify, _lowThreshold));
            layout.Controls.Add(NotificationRow(_healthNotify, _healthThreshold));
            card.Controls.Add(layout);

            return card;
        }

        private static Control NotificationRow(CheckBox check, NumericUpDown value)
        {
            var row = new FlowLayoutPanel();
            row.Dock = DockStyle.Fill;
            row.FlowDirection = FlowDirection.LeftToRight; // the form mirrors the row in RTL
            row.WrapContents = false;
            row.Margin = new Padding(0);
            row.Controls.Add(check);
            row.Controls.Add(MakeSpacer(8));
            row.Controls.Add(value);
            row.Controls.Add(MakeCaption("%"));
            return row;
        }

        private Control BuildInterfaceCard()
        {
            var card = new CardPanel(Loc.T("Interface and behavior"));
            card.Dock = DockStyle.Fill;

            var layout = new TableLayoutPanel();
            layout.Dock = DockStyle.Fill;
            layout.ColumnCount = 1;
            layout.RowCount = 4;
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 32f));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 32f));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 32f));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 32f));

            _language.DropDownStyle = ComboBoxStyle.DropDownList;
            _language.Width = 190;
            _language.Items.Add(Loc.T("Automatic (system)"));
            foreach (var language in Loc.All) _language.Items.Add(language.Name);

            var languageRow = new FlowLayoutPanel();
            languageRow.Dock = DockStyle.Fill;
            languageRow.FlowDirection = FlowDirection.LeftToRight; // the form mirrors the row in RTL
            languageRow.WrapContents = false;
            languageRow.Margin = new Padding(0);
            languageRow.Controls.Add(MakeCaption(Loc.T("Language")));
            languageRow.Controls.Add(_language);
            layout.Controls.Add(languageRow);

            _direction.DropDownStyle = ComboBoxStyle.DropDownList;
            _direction.Width = 190;
            _direction.Items.Add(Loc.T("Automatic (system)"));
            _direction.Items.Add(Loc.T("Right to left (RTL)"));
            _direction.Items.Add(Loc.T("Left to right (LTR)"));

            var directionRow = new FlowLayoutPanel();
            directionRow.Dock = DockStyle.Fill;
            directionRow.FlowDirection = FlowDirection.LeftToRight; // the form mirrors the row in RTL
            directionRow.WrapContents = false;
            directionRow.Margin = new Padding(0);
            directionRow.Controls.Add(MakeCaption(Loc.T("Interface direction")));
            directionRow.Controls.Add(_direction);
            layout.Controls.Add(directionRow);

            _showCeiling.Text = Loc.T("Show the limit number on the icon");
            _showCeiling.AutoSize = true;
            layout.Controls.Add(_showCeiling);

            _notifications.Text = Loc.T("Enable system notifications");
            _notifications.AutoSize = true;
            layout.Controls.Add(_notifications);

            card.Controls.Add(layout);
            return card;
        }

        private FlowLayoutPanel BuildButtons()
        {
            var buttons = new FlowLayoutPanel();
            buttons.Dock = DockStyle.Bottom;
            buttons.Height = 52;
            buttons.FlowDirection = FlowDirection.LeftToRight; // the form mirrors the row in RTL
            buttons.WrapContents = true;
            buttons.Margin = new Padding(0);
            buttons.Padding = new Padding(14, 8, 14, 8);

            _saveButton.Text = Loc.T("Save");
            _saveButton.AutoSize = true;
            _saveButton.MinimumSize = new Size(96, 32);
            _saveButton.Click += OnSave;

            var cancel = new Button();
            cancel.Text = Loc.T("Cancel");
            cancel.AutoSize = true;
            cancel.MinimumSize = new Size(96, 32);
            cancel.DialogResult = DialogResult.Cancel;

            var test = new Button();
            test.Text = Loc.T("Test notification");
            test.AutoSize = true;
            test.MinimumSize = new Size(124, 32);
            test.Click += delegate
            {
                if (_testNotify != null)
                    _testNotify("BatteryGuard", Loc.T("Demo notification — Notifications are working."), Native.NIIF_INFO);
            };

            _footerHint.Text = Loc.T("Changes apply immediately when saved.");
            _footerHint.AutoSize = true;
            _footerHint.MaximumSize = new Size(260, 0);
            _footerHint.Margin = new Padding(14, 10, 0, 0);

            buttons.Controls.Add(_saveButton);
            buttons.Controls.Add(cancel);
            buttons.Controls.Add(test);
            buttons.Controls.Add(_footerHint);

            _tips.SetToolTip(test, Loc.T("Sends an immediate notification to verify delivery, even when notifications are off."));

            AcceptButton = _saveButton;
            CancelButton = cancel;
            return buttons;
        }

        private void AdjustFooter(FlowLayoutPanel footer)
        {
            if (footer == null || _adjustingFooter) return;

            _adjustingFooter = true;
            try
            {
                int width = Math.Max(360, ClientSize.Width);
                int height = Math.Max(52, footer.GetPreferredSize(new Size(width, 0)).Height);
                if (footer.Height != height) footer.Height = height;
            }
            finally { _adjustingFooter = false; }
        }

        private Button MakeChip(string text, int ceiling, int resume)
        {
            var button = new Button();
            button.Text = text;
            button.AutoSize = true;
            button.Height = 26;
            button.Margin = new Padding(0, 0, 8, 0);
            button.FlatStyle = FlatStyle.Flat;
            button.Click += delegate
            {
                _limitEnabled.Checked = true;
                _syncing = true;
                _ceilingValue.Value = ceiling;
                _resumeValue.Maximum = Math.Max(1, ceiling - 5);
                _resumeValue.Value = Math.Min(resume, (int)_resumeValue.Maximum);
                _syncing = false;
                _slider.SetValuesSilent((int)_resumeValue.Value, ceiling);
            };
            _chips.Add(button);
            return button;
        }

        private static Label MakeCaption(string text)
        {
            var label = new Label();
            label.Text = text;
            label.AutoSize = true;
            label.Margin = new Padding(0, 9, 6, 0);
            return label;
        }

        private static Control MakeSpacer(int width)
        {
            var spacer = new Panel();
            spacer.Width = width;
            spacer.Height = 1;
            spacer.Margin = new Padding(0);
            return spacer;
        }

        private void OnSliderChanged(object sender, EventArgs e)
        {
            _syncing = true;
            _ceilingValue.Value = _slider.UpperValue;
            _resumeValue.Value = _slider.LowerValue;
            _syncing = false;
        }

        private void OnCeilingValueChanged(object sender, EventArgs e)
        {
            if (_syncing) return;

            int ceiling = (int)_ceilingValue.Value;
            _syncing = true;
            _resumeValue.Maximum = Math.Max(1, ceiling - 5);
            if (_resumeValue.Value > _resumeValue.Maximum) _resumeValue.Value = _resumeValue.Maximum;
            _slider.SetValuesSilent((int)_resumeValue.Value, ceiling);
            _syncing = false;
        }

        private void OnResumeValueChanged(object sender, EventArgs e)
        {
            if (_syncing) return;

            int resume = (int)_resumeValue.Value;
            _syncing = true;
            if (resume > _ceilingValue.Value - 5)
                _ceilingValue.Value = Math.Min(100, resume + 5);
            _syncing = false;
            _slider.SetValuesSilent(resume, (int)_ceilingValue.Value);
        }

        private void UpdateBatteryInfo()
        {
            var info = BatteryInfo.Read();
            string state = info.Charging ? Loc.T("Charging") : (info.Discharging ? Loc.T("On battery") : (info.PowerOnline ? Loc.T("Plugged in") : Loc.T("Idle")));

            var text = new StringBuilder();
            text.AppendFormat(CultureInfo.InvariantCulture, Loc.T("Battery {0}% · {1}"), info.Percent, state);

            if (info.Health > 0)
                text.AppendFormat(CultureInfo.InvariantCulture, Loc.T(" · Battery health {0}%"), info.Health);

            // Keep the long capacity/estimate tail on its own line so the
            // health sentence is never truncated in longer languages.
            text.Append(Environment.NewLine);

            if (info.Designed > 0)
                text.AppendFormat(CultureInfo.InvariantCulture, "{0:N0} / {1:N0} mWh", info.FullCharged, info.Designed);
            else
                text.AppendFormat(CultureInfo.InvariantCulture, "{0:N0} mWh", info.FullCharged);

            string electrical = info.ElectricalText();
            if (electrical.Length > 0) text.Append(" · " + electrical);

            if (!DeviceInfo.IsHp)
                text.Append(" · " + Loc.T("Monitoring only"));

            if (info.CycleCount > 0)
                text.AppendFormat(CultureInfo.InvariantCulture, Loc.T(" · Cycles {0}"), info.CycleCount);
            if (info.TemperatureC > 0)
                text.AppendFormat(CultureInfo.InvariantCulture, Loc.T(" · {0}°C"), info.TemperatureC);

            int remaining = info.MinutesRemaining();
            if (remaining > 0)
                text.AppendFormat(CultureInfo.InvariantCulture, " · {0} ≈ {1}",
                    info.Charging ? Loc.T("Charging") : Loc.T("Discharging"), Engine.FormatMinutes(remaining));

            _batteryInfo.Text = text.ToString();
        }

        private void LoadValues(GuardConfig config)
        {
            bool off = string.Equals(config.Preset, "Off", StringComparison.OrdinalIgnoreCase) || !config.Ceiling.HasValue;
            int ceiling = (int)Clamp(config.Ceiling ?? 80, 50, 100);
            int resume = (int)Clamp(config.Resume ?? (ceiling - Math.Max(5, config.ResumeDrop)), 1, ceiling - 5);

            _limitEnabled.Checked = !off;
            _syncing = true;
            _ceilingValue.Value = ceiling;
            _resumeValue.Maximum = Math.Max(1, ceiling - 5);
            _resumeValue.Value = resume;
            _syncing = false;
            _slider.SetValuesSilent(resume, ceiling);

            _schedule.Checked = config.ScheduleEnabled && config.Schedule.Count > 0;
            _scheduleList.Items.Clear();
            foreach (var rule in config.Schedule)
                AddScheduleItem(rule);

            _floatMode.Checked = config.FloatMode;

            _fullNotify.Checked = UiSettings.FullNotify;
            _fullThreshold.Value = Clamp(UiSettings.FullThreshold, 50, 100);
            _lowNotify.Checked = UiSettings.LowNotify;
            _lowThreshold.Value = Clamp(UiSettings.LowThreshold, 5, 50);
            _healthNotify.Checked = UiSettings.HealthNotify;
            _healthThreshold.Value = Clamp(UiSettings.HealthThreshold, 40, 95);

            _language.SelectedIndex = 0;
            for (int index = 0; index < Loc.All.Length; index++)
                if (string.Equals(Loc.All[index].Code, UiSettings.Language, StringComparison.OrdinalIgnoreCase))
                    _language.SelectedIndex = index + 1;

            _direction.SelectedIndex = string.Equals(UiSettings.Direction, "rtl", StringComparison.OrdinalIgnoreCase) ? 1
                : (string.Equals(UiSettings.Direction, "ltr", StringComparison.OrdinalIgnoreCase) ? 2 : 0);
            _showCeiling.Checked = UiSettings.ShowCeiling;
            _notifications.Checked = UiSettings.Notifications;

            UpdateEnabled();
            RefreshScheduleState();
        }

        private void UpdateEnabled()
        {
            bool on = _limitEnabled.Checked;

            _slider.Enabled = on;
            _ceilingValue.Enabled = on;
            _resumeValue.Enabled = on;
            _floatMode.Enabled = on;
            foreach (var chip in _chips)
                chip.Enabled = on;

            bool scheduled = _schedule.Checked;
            _scheduleList.Enabled = scheduled;
            _scheduleAdd.Enabled = true;
            _scheduleEdit.Enabled = scheduled && _scheduleList.SelectedItems.Count > 0;
            _scheduleRemove.Enabled = _scheduleEdit.Enabled;

            _fullThreshold.Enabled = _fullNotify.Checked;
            _lowThreshold.Enabled = _lowNotify.Checked;
            _healthThreshold.Enabled = _healthNotify.Checked;
        }

        private void OnSave(object sender, EventArgs e)
        {
            ValidationError = null;

            var config = new GuardConfig();
            config.IntervalSeconds = 60;
            config.ScheduleEnabled = false;
            config.Schedule.Clear();

            if (_limitEnabled.Checked)
            {
                int ceiling = (int)_ceilingValue.Value;
                int resume = Math.Max(1, Math.Min((int)_resumeValue.Value, ceiling - 5));

                config.Preset = ceiling == 80 && resume == 75 ? "Recommended"
                    : (ceiling == 60 && resume == 55 ? "Longevity" : "Custom");
                config.Ceiling = ceiling;
                config.Resume = resume;
                config.ResumeDrop = 5;
                config.FloatMode = _floatMode.Checked;
            }
            else
            {
                config.Preset = "Off";
                config.Ceiling = null;
                config.Resume = null;
                config.ResumeDrop = 5;
                config.FloatMode = false;
            }

            if (_schedule.Checked)
            {
                if (_scheduleList.Items.Count == 0)
                {
                    Fail(Loc.T("Add at least one scheduling time window or stop scheduling."));
                    return;
                }

                var rules = new List<WindowRule>();
                foreach (ListViewItem item in _scheduleList.Items)
                    rules.Add(RuleFromItem(item));

                for (int first = 0; first < rules.Count; first++)
                {
                    for (int second = first + 1; second < rules.Count; second++)
                    {
                        if (!ScheduleRules.Overlaps(rules[first], rules[second])) continue;

                        Fail(Loc.T("Window ") + ScheduleRules.Describe(rules[first]) + Loc.T(" with ") + ScheduleRules.Describe(rules[second]) + Loc.T(". Adjust the times before saving."));
                        return;
                    }
                }

                foreach (var rule in rules)
                    config.Schedule.Add(rule);
                config.ScheduleEnabled = true;
            }

            UiSettings.FullNotify = _fullNotify.Checked;
            UiSettings.FullThreshold = (int)_fullThreshold.Value;
            UiSettings.LowNotify = _lowNotify.Checked;
            UiSettings.LowThreshold = (int)_lowThreshold.Value;
            UiSettings.HealthNotify = _healthNotify.Checked;
            UiSettings.HealthThreshold = (int)_healthThreshold.Value;

            UiSettings.Language = _language.SelectedIndex <= 0 ? "auto" : Loc.All[_language.SelectedIndex - 1].Code;
            UiSettings.Direction = _direction.SelectedIndex == 1 ? "rtl" : (_direction.SelectedIndex == 2 ? "ltr" : "auto");
            UiSettings.ShowCeiling = _showCeiling.Checked;
            UiSettings.Notifications = _notifications.Checked;
            UiSettings.Save();

            config.Save(_configPath);
            DialogResult = DialogResult.OK;
            Close();
        }

        private void ApplyTheme()
        {
            UiTheme.Apply(this);

            bool dark = ThemeSettings.MenuDark;
            _footerHint.ForeColor = UiTheme.Muted(dark);
            _batteryInfo.ForeColor = UiTheme.Ink(dark);
            UiTheme.Primary(_saveButton, dark);
            RefreshScheduleState();
        }

        private static decimal Clamp(int value, int minimum, int maximum)
        {
            if (value < minimum) return minimum;
            if (value > maximum) return maximum;
            return value;
        }

        private static DateTime ParseTime(string text)
        {
            DateTime parsed;
            if (DateTime.TryParseExact(text, "HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out parsed)) return parsed;
            return DateTime.Today;
        }
    }

    internal sealed class LogForm : Form
    {
        private readonly string _logPath;
        private readonly TextBox _text = new TextBox();
        private readonly Label _status = new Label();

        public LogForm(string logPath)
        {
            _logPath = logPath;
            RightToLeft = UiSettings.Rtl ? RightToLeft.Yes : RightToLeft.No;
            RightToLeftLayout = UiSettings.Rtl;

            Text = Loc.T("BatteryGuard — Activity log");
            StartPosition = FormStartPosition.CenterScreen;
            MinimizeBox = false;
            ShowInTaskbar = true;
            ShowIcon = false;
            TopMost = true;
            AutoScaleMode = AutoScaleMode.Dpi;
            ClientSize = new Size(760, 560);
            MinimumSize = new Size(520, 360);
            Font = new Font("Segoe UI", 9.5f);

            _text.Multiline = true;
            _text.ReadOnly = true;
            _text.ScrollBars = ScrollBars.Both;
            _text.WordWrap = false;
            _text.Dock = DockStyle.Fill;
            _text.BorderStyle = BorderStyle.FixedSingle;
            _text.Font = new Font("Consolas", 9f);
            _text.RightToLeft = RightToLeft.No;
            _text.TabStop = false;

            var bar = new FlowLayoutPanel();
            bar.Dock = DockStyle.Bottom;
            bar.AutoSize = true;
            bar.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            bar.Height = 46;
            bar.FlowDirection = UiSettings.Rtl ? FlowDirection.RightToLeft : FlowDirection.LeftToRight;
            if (UiSettings.Rtl) bar.RightToLeft = RightToLeft.No;
            bar.WrapContents = true;
            bar.Padding = new Padding(6);

            var refresh = new Button();
            refresh.Text = Loc.T("Refresh");
            refresh.AutoSize = true;
            refresh.MinimumSize = new Size(88, 28);
            refresh.FlatStyle = FlatStyle.Flat;
            refresh.Click += delegate { LoadLines(); };

            var close = new Button();
            close.Text = Loc.T("Close");
            close.AutoSize = true;
            close.MinimumSize = new Size(88, 28);
            close.FlatStyle = FlatStyle.Flat;
            close.DialogResult = DialogResult.OK;

            var export = new Button();
            export.Text = Loc.T("Export…");
            export.AutoSize = true;
            export.MinimumSize = new Size(88, 28);
            export.FlatStyle = FlatStyle.Flat;
            export.Click += delegate { ExportLog(); };

            _status.AutoSize = true;
            _status.MaximumSize = new Size(360, 0);
            _status.Margin = new Padding(14, 9, 0, 0);
            _status.Text = string.Empty;

            bar.Controls.Add(refresh);
            bar.Controls.Add(export);
            bar.Controls.Add(close);
            bar.Controls.Add(_status);

            Controls.Add(_text);
            Controls.Add(bar);

            AcceptButton = refresh;
            CancelButton = close;
            KeyPreview = true;
            KeyDown += delegate(object sender, KeyEventArgs e)
            {
                if (e.Control && e.KeyCode == Keys.R)
                {
                    LoadLines();
                    e.Handled = true;
                    e.SuppressKeyPress = true;
                }
                else if (e.Control && e.KeyCode == Keys.E)
                {
                    ExportLog();
                    e.Handled = true;
                    e.SuppressKeyPress = true;
                }
            };

            UiTheme.Apply(this);
            bool dark = ThemeSettings.MenuDark;
            _text.BackColor = dark ? Color.FromArgb(24, 26, 30) : Color.FromArgb(252, 252, 253);
            _text.ForeColor = dark ? Color.FromArgb(224, 228, 232) : Color.FromArgb(30, 34, 38);
            _status.ForeColor = UiTheme.Muted(dark);

            LoadLines();
            UiLayout.Fit(this);
        }

        private void LoadLines()
        {
            try
            {
                if (!File.Exists(_logPath))
                {
                    _text.Text = Loc.T("No activity log entries yet.");
                    _status.Text = Loc.T("No activity log entries yet.");
                    return;
                }

                string[] lines = File.ReadAllLines(_logPath);
                int start = Math.Max(0, lines.Length - 300);
                var builder = new StringBuilder();
                for (int index = start; index < lines.Length; index++)
                    builder.AppendLine(lines[index]);

                _text.Text = builder.ToString();
                _text.SelectionStart = _text.TextLength;
                _text.ScrollToCaret();

                _status.Text = string.Format(CultureInfo.InvariantCulture, Loc.T("Showing {0} of {1} lines · {2}"),
                    lines.Length - start, lines.Length, DateTime.Now.ToString("HH:mm:ss", CultureInfo.InvariantCulture));
            }
            catch (Exception ex)
            {
                _text.Text = Loc.T("Could not read the activity log:") + ex.Message;
                _status.Text = Loc.T("Could not read the activity log.");
            }
        }

        private void ExportLog()
        {
            using (var dialog = new SaveFileDialog())
            {
                dialog.Title = Loc.T("Export activity log");
                dialog.Filter = Loc.T("Text file (*.txt)|*.txt|All files (*.*)|*.*");
                dialog.FileName = "batteryguard-" + DateTime.Now.ToString("yyyyMMdd-HHmm", CultureInfo.InvariantCulture) + ".txt";
                if (dialog.ShowDialog(this) != DialogResult.OK) return;

                try
                {
                    if (File.Exists(_logPath))
                        File.Copy(_logPath, dialog.FileName, true);
                    else
                        File.WriteAllText(dialog.FileName, _text.Text);

                    MessageBox.Show(this, Loc.T("Activity log exported to:\n") + dialog.FileName, "BatteryGuard",
                        MessageBoxButtons.OK, MessageBoxIcon.Information);
                }
                catch (Exception ex)
                {
                    MessageBox.Show(this, Loc.T("Export failed:") + ex.Message, "BatteryGuard",
                        MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
        }
    }
}
