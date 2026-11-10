<#
.SYNOPSIS
  Checks that the dialogs stay usable at several window sizes.

.DESCRIPTION
  Constructs SettingsForm, WindowRuleForm and LogForm without a message loop,
  resizes them to representative client sizes, and verifies that action bars
  remain inside the window, content scrolls when needed, and key controls keep
  a usable size. No hardware writes, no elevation and no file changes outside
  a temporary settings file.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$root = Split-Path -Parent $PSScriptRoot
$env:BATTERYGUARD_HOME = $root
$sources = @(Get-ChildItem -Path (Join-Path $root 'src') -Filter '*.cs' | Sort-Object Name | ForEach-Object { $_.FullName })
Add-Type -Path $sources -ReferencedAssemblies 'System.dll', 'System.Drawing.dll', 'System.Management.dll', 'System.Web.Extensions.dll', 'System.Windows.Forms.dll'

function Get-AppType([string]$name) {
    foreach ($assembly in [AppDomain]::CurrentDomain.GetAssemblies()) {
        $candidate = $assembly.GetType('BatteryGuardTray.' + $name, $false)
        if ($candidate) { return $candidate }
    }
    return $null
}

function Find-Named($parent, [string]$name) {
    foreach ($child in $parent.Controls) {
        if ($child.Name -eq $name) { return $child }
        $found = Find-Named $child $name
        if ($found) { return $found }
    }
    return $null
}

function Find-Text($parent, [string]$text) {
    foreach ($child in $parent.Controls) {
        if ($child.Text -eq $text) { return $child }
        $found = Find-Text $child $text
        if ($found) { return $found }
    }
    return $null
}

function Check([string]$name, [bool]$ok, [string]$detail) {
    if ($ok) {
        '{0}: OK{1}' -f $name, $(if ($detail) { ' (' + $detail + ')' } else { '' })
    }
    else {
        '{0}: FAIL{1}' -f $name, $(if ($detail) { ' (' + $detail + ')' } else { '' })
        $script:failed = $true
    }
}

function Show-Offscreen($form) {
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $form.Location = New-Object System.Drawing.Point(-30000, -30000)
    $form.TopMost = $false
    $form.ShowInTaskbar = $false
    $form.Show()
    [System.Windows.Forms.Application]::DoEvents()
    $form.PerformLayout()
}

$flags = [System.Reflection.BindingFlags]'Public,NonPublic,Instance'
$staticFlags = [System.Reflection.BindingFlags]'Public,Static'
$nativeType = Get-AppType 'Native'
if ($nativeType) { [void]$nativeType.GetMethod('SetProcessDPIAware', $staticFlags).Invoke($null, @()) }
$settingsType = Get-AppType 'SettingsForm'
$ruleFormType = Get-AppType 'WindowRuleForm'
$ruleType = Get-AppType 'WindowRule'
$logType = Get-AppType 'LogForm'
if (-not $settingsType -or -not $ruleFormType -or -not $ruleType -or -not $logType) {
    throw 'layout test types not found'
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ('batteryguard-layout-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
$configPath = Join-Path $temp 'settings.json'
$config = @'
{
  "preset": "Custom",
  "ceiling": 80,
  "resume": 75,
  "resumeDrop": 5,
  "intervalSeconds": 60,
  "scheduleEnabled": true,
  "floatMode": true,
  "schedule": [
    { "from": "00:00", "to": "08:00", "ceiling": 60 },
    { "from": "12:00", "to": "14:00", "ceiling": null }
  ]
}
'@
[IO.File]::WriteAllText($configPath, $config, (New-Object System.Text.UTF8Encoding($false)))
$testNotify = [System.Action[string, string, System.UInt32]] { param($title, $text, $level) }
$script:failed = $false

try {
    $settingsCtor = $settingsType.GetConstructor($flags, $null, [Type[]]@([string], $testNotify.GetType()), $null)
    [object[]]$settingsArgs = @([string]$configPath, $testNotify)
    $settings = $settingsCtor.Invoke($settingsArgs)
    $settings.CreateControl()
    $settings.MinimumSize = New-Object System.Drawing.Size(320, 240)
    Show-Offscreen $settings

    $content = Find-Named $settings 'SettingsContent'
    $footer = Find-Named $settings 'SettingsFooter'
    $rootPanel = if ($content -and $content.Controls.Count -gt 0) { $content.Controls[0] } else { $null }
    $save = $settingsType.GetField('_saveButton', $flags).GetValue($settings)
    $scheduleList = $settingsType.GetField('_scheduleList', $flags).GetValue($settings)
    $add = $settingsType.GetField('_scheduleAdd', $flags).GetValue($settings)
    $hint = $settingsType.GetField('_footerHint', $flags).GetValue($settings)
    $language = $settingsType.GetField('_language', $flags).GetValue($settings)
    $appearance = $settingsType.GetField('_appearance', $flags).GetValue($settings)
    $direction = $settingsType.GetField('_direction', $flags).GetValue($settings)
    $versionLabel = $settingsType.GetField('_versionLabel', $flags).GetValue($settings)

    if (-not $content -or -not $footer -or -not $rootPanel) { throw 'settings content/footer not found' }

    Check 'settings language row is above appearance' ($language.Parent.Top -lt $appearance.Parent.Top) ('language=' + $language.Parent.Top + ' appearance=' + $appearance.Parent.Top)
    Check 'settings appearance has three modes' ($appearance.Items.Count -eq 3) ('count=' + $appearance.Items.Count)
    Check 'settings installed version shown' ($versionLabel.Text -match '\d+\.\d+\.\d+') $versionLabel.Text

    foreach ($size in @(@(980, 620), @(780, 600), @(620, 480), @(560, 420))) {
        $settings.ClientSize = New-Object System.Drawing.Size([int]$size[0], [int]$size[1])
        $settings.PerformLayout()
        $content.PerformLayout()
        $footer.PerformLayout()
        [System.Windows.Forms.Application]::DoEvents()
        $tag = '{0}x{1}' -f $size[0], $size[1]

        Check "settings footer inside $tag" ($footer.Bottom -le $settings.ClientSize.Height + 1 -and $footer.Height -ge 48) ('footer=' + $footer.Bounds)
        Check "settings action usable $tag" ($save.Width -ge 80 -and $save.Height -ge 28) ('save=' + $save.Bounds)
        $contentFits = ($rootPanel.Bottom -le $content.ClientSize.Height + 1) -or ($content.VerticalScroll.Maximum -gt $content.ClientSize.Height)
        Check "settings content fits or scrolls $tag" ($content.AutoScroll -and $contentFits) ('root=' + $rootPanel.Bounds + ' max=' + $content.VerticalScroll.Maximum + ' client=' + $content.ClientSize.Height)
        Check "settings root keeps content width $tag" ($rootPanel.Width -ge 520 -and $rootPanel.Height -ge 500) ('root=' + $rootPanel.Bounds)
        Check "settings schedule list usable $tag" ($scheduleList.Height -ge 40) ('list=' + $scheduleList.Height)
        Check "settings add button usable $tag" ($add.Width -ge 60) ('add=' + $add.Bounds)
        Check "settings footer hint visible $tag" ($hint.Width -gt 0) ('hint=' + $hint.Bounds)
        Check "settings language combo usable $tag" ($language.Width -ge 150 -and $language.SelectedIndex -ge 0 -and $language.Text.Length -gt 0) ('language=' + $language.Bounds + ' index=' + $language.SelectedIndex + ' text=' + $language.Text)
        Check "settings appearance combo usable $tag" ($appearance.Width -ge 150 -and $appearance.SelectedIndex -ge 0 -and $appearance.Text.Length -gt 0) ('appearance=' + $appearance.Bounds + ' index=' + $appearance.SelectedIndex + ' text=' + $appearance.Text)
        Check "settings direction combo usable $tag" ($direction.Width -ge 150 -and $direction.SelectedIndex -ge 0 -and $direction.Text.Length -gt 0) ('direction=' + $direction.Bounds + ' index=' + $direction.SelectedIndex + ' text=' + $direction.Text)
        if ($size[0] -ge 900) {
            Check "settings wide layout shows all cards $tag" ($rootPanel.Bottom -le $content.ClientSize.Height + 1) ('root=' + $rootPanel.Bounds + ' client=' + $content.ClientSize.Height)
            Check "settings wide layout avoids horizontal scroll $tag" (-not $content.HorizontalScroll.Visible) ('hscroll=' + $content.HorizontalScroll.Visible)
        }
        else {
            Check "settings narrow layout stacks cards $tag" ($rootPanel.Height -ge 900) ('root=' + $rootPanel.Bounds)
            Check "settings narrow layout avoids horizontal scroll $tag" (-not $content.HorizontalScroll.Visible) ('hscroll=' + $content.HorizontalScroll.Visible)
        }
    }
    $settings.Dispose()

    $ruleCtor = $ruleFormType.GetConstructor($flags, $null, [Type[]]@($ruleType), $null)
    [object[]]$ruleArgs = @($null)
    $ruleForm = $ruleCtor.Invoke($ruleArgs)
    $ruleForm.CreateControl()
    $ruleForm.MinimumSize = New-Object System.Drawing.Size(320, 240)
    Show-Offscreen $ruleForm
    $ruleContent = Find-Named $ruleForm 'RuleContent'
    $ruleLayout = Find-Named $ruleForm 'RuleLayout'
    $note = Find-Named $ruleForm 'RuleNote'
    $ok = Find-Named $ruleForm 'RuleSave'
    if (-not $ruleContent -or -not $ruleLayout -or -not $note -or -not $ok) { throw 'rule layout elements not found' }

    foreach ($size in @(@(500, 350), @(440, 350), @(380, 350))) {
        $ruleForm.ClientSize = New-Object System.Drawing.Size([int]$size[0], [int]$size[1])
        $ruleForm.PerformLayout()
        $ruleContent.PerformLayout()
        [System.Windows.Forms.Application]::DoEvents()
        $tag = '{0}x{1}' -f $size[0], $size[1]

        Check "rule action inside $tag" ($ok.Width -ge 90 -and $ok.Height -ge 30 -and $ok.Bottom -le $ok.Parent.ClientSize.Height + 1 -and $ok.Parent.Bottom -le $ruleForm.ClientSize.Height + 1) ('ok=' + $ok.Bounds + ' bar=' + $ok.Parent.Bounds)
        Check "rule note complete $tag" ($note.Height -ge 20 -and $note.Width -gt 100 -and $note.Text.Length -gt 20) ('note=' + $note.Bounds)
        Check "rule content fits or scrolls $tag" (($ruleContent.VerticalScroll.Maximum -gt $ruleContent.ClientSize.Height) -or ($ruleLayout.Bottom -le $ruleContent.ClientSize.Height + 1)) ('layout=' + $ruleLayout.Bounds + ' client=' + $ruleContent.ClientSize.Height)
        Check "rule avoids sideways scroll $tag" (-not $ruleContent.HorizontalScroll.Visible) ('hscroll=' + $ruleContent.HorizontalScroll.Visible)
    }
    $ruleForm.Dispose()

    $logCtor = $logType.GetConstructor($flags, $null, [Type[]]@([string]), $null)
    [object[]]$logArgs = @([string](Join-Path $root 'application.log'))
    $logForm = $logCtor.Invoke($logArgs)
    $logForm.CreateControl()
    $logForm.MinimumSize = New-Object System.Drawing.Size(320, 240)
    Show-Offscreen $logForm
    $status = $logType.GetField('_status', $flags).GetValue($logForm)
    $box = $logType.GetField('_text', $flags).GetValue($logForm)
    $bar = $status.Parent
    if (-not $bar) { throw 'log bar not found' }

    foreach ($size in @(@(760, 560), @(520, 360), @(440, 300))) {
        $logForm.ClientSize = New-Object System.Drawing.Size([int]$size[0], [int]$size[1])
        $logForm.PerformLayout()
        $bar.PerformLayout()
        [System.Windows.Forms.Application]::DoEvents()
        $tag = '{0}x{1}' -f $size[0], $size[1]

        Check "log bar inside $tag" ($bar.Bottom -le $logForm.ClientSize.Height + 1 -and $bar.Height -ge 40) ('bar=' + $bar.Bounds)
        Check "log status visible $tag" ($status.Width -gt 0 -and $status.Text.Length -gt 0) ('status=' + $status.Bounds)
        Check "log text area usable $tag" ($box.Height -ge 40) ('text=' + $box.Height)
    }
    $logForm.Dispose()
}
finally {
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
}

# --- DPI simulation: en/ar at 100%, 125% and 150% -------------------------
$uiPath = Join-Path $root 'interface.ini'
$uiOriginal = if (Test-Path $uiPath) { Get-Content $uiPath -Raw } else { $null }
$dpiTemp = Join-Path ([IO.Path]::GetTempPath()) ('batteryguard-dpi-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $dpiTemp | Out-Null
$dpiConfig = Join-Path $dpiTemp 'settings.json'
[IO.File]::WriteAllText($dpiConfig, $config, (New-Object System.Text.UTF8Encoding($false)))

function Set-TestLanguage([string]$code) {
    $direction = if ($code -eq 'ar') { 'rtl' } else { 'ltr' }
    $text = "showCeiling=on`r`nnotifications=on`r`nlanguage=$code`r`ndirection=$direction`r`n"
    [IO.File]::WriteAllText($uiPath, $text, (New-Object System.Text.UTF8Encoding($true)))
}

function Capture-ScaledFonts([System.Windows.Forms.Control]$control) {
    if ($control.Font) { $script:fontMap[$control] = $control.Font }
    foreach ($child in $control.Controls) { Capture-ScaledFonts $child }
}

function Apply-ScaledFonts([System.Windows.Forms.Control]$control, [single]$scale) {
    if ($script:fontMap.ContainsKey($control)) {
        $original = $script:fontMap[$control]
        $control.Font = New-Object System.Drawing.Font($original.FontFamily, [single]($original.Size * $scale), $original.Style, $original.Unit)
    }
    foreach ($child in $control.Controls) { Apply-ScaledFonts $child $scale }
}

function Set-LayoutDpiForTest([System.Windows.Forms.Form]$form, [int]$dpi) {
    $field = $form.GetType().GetField('LayoutDpiForTest', $flags)
    if (-not $field) { throw 'LayoutDpiForTest field missing' }
    $field.SetValue($form, $dpi)
}

function Scale-TestForm([System.Windows.Forms.Form]$form, [double]$factor) {
    $form.CreateControl()
    if ($factor -le 1.0) { return }
    $script:fontMap = New-Object 'System.Collections.Generic.Dictionary[System.Windows.Forms.Control,System.Drawing.Font]'
    Capture-ScaledFonts $form
    $form.Scale((New-Object System.Drawing.SizeF([single]$factor, [single]$factor)))
    Apply-ScaledFonts $form ([single]$factor)
    $form.PerformLayout()
}

function Resize-Clamped([System.Windows.Forms.Form]$form) {
    $area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $maxWidth = [Math]::Max(320, $area.Width - 32)
    $maxHeight = [Math]::Max(240, $area.Height - 32)
    $minimum = $form.MinimumSize
    $newMinimum = New-Object System.Drawing.Size([Math]::Min($minimum.Width, $maxWidth), [Math]::Min($minimum.Height, $maxHeight))
    if ($minimum.Width -gt $maxWidth -or $minimum.Height -gt $maxHeight) { $form.MinimumSize = $newMinimum }
    $width = [int][Math]::Min([Math]::Max(1, $form.Width), $maxWidth)
    $height = [int][Math]::Min([Math]::Max(1, $form.Height), $maxHeight)
    $form.Size = New-Object System.Drawing.Size($width, $height)
    $form.PerformLayout()
}

function Get-LayoutIssues([System.Windows.Forms.Control]$parent, [string]$path) {
    $issues = @()
    foreach ($child in $parent.Controls) {
        if (-not $child.Visible -or $child.Width -le 0 -or $child.Height -le 0) { continue }
        if ($child.Left -lt -1 -or $child.Top -lt -1 -or $child.Right -gt $parent.ClientSize.Width + 1 -or $child.Bottom -gt $parent.ClientSize.Height + 1) {
            $name = if ($child.Name) { $child.Name } else { $child.GetType().Name }
            $issues += ($path + '/' + $name + '=' + $child.Bounds + ' parent=' + $parent.ClientSize)
        }
        $issues += Get-LayoutIssues $child ($path + '/' + $child.GetType().Name)
    }
    return $issues
}

function Invoke-SettingsLayout([System.Windows.Forms.Form]$form) {
    $content = [System.Windows.Forms.Panel](Find-Named $form 'SettingsContent')
    $footer = [System.Windows.Forms.FlowLayoutPanel](Find-Named $form 'SettingsFooter')
    if (-not $content -or -not $footer) { throw 'settings content/footer not found' }
    $adjust = $form.GetType().GetMethod('AdjustFooter', $flags)
    $apply = $form.GetType().GetMethod('ApplySettingsLayout', $flags)
    if (-not $adjust -or -not $apply) { throw 'settings layout methods missing' }
    for ($pass = 0; $pass -lt 2; $pass++) {
        $content.PerformLayout()
        $footer.PerformLayout()
        [void]$adjust.Invoke($form, [object[]]@($footer))
        [void]$apply.Invoke($form, [object[]]@([int]$content.ClientSize.Width))
    }
    $content.PerformLayout()
    $footer.PerformLayout()
    return @($content, $footer)
}

function Test-DpiSettings([string]$lang, [double]$factor) {
    Set-TestLanguage $lang
    $ctor = $settingsType.GetConstructor($flags, $null, [Type[]]@([string], $testNotify.GetType()), $null)
    $form = [System.Windows.Forms.Form]$ctor.Invoke([object[]]@([string]$dpiConfig, $testNotify))
    try {
        Scale-TestForm $form $factor
        Set-LayoutDpiForTest $form ([int][Math]::Round(96 * $factor))
        $form.Opacity = 0
        Show-Offscreen $form
        if ($factor -le 1.0) { $form.ClientSize = New-Object System.Drawing.Size(980, 620) } else { Resize-Clamped $form }
        $parts = Invoke-SettingsLayout $form
        $content = [System.Windows.Forms.Panel]$parts[0]
        $footer = [System.Windows.Forms.FlowLayoutPanel]$parts[1]
        $rootPanel = if ($content.Controls.Count -gt 0) { $content.Controls[0] } else { $null }
        if (-not $rootPanel) { throw 'settings root not found' }
        $save = $settingsType.GetField('_saveButton', $flags).GetValue($form)
        $scheduleList = $settingsType.GetField('_scheduleList', $flags).GetValue($form)
        $add = $settingsType.GetField('_scheduleAdd', $flags).GetValue($form)
        $hint = $settingsType.GetField('_footerHint', $flags).GetValue($form)
        $language = $settingsType.GetField('_language', $flags).GetValue($form)
        $appearance = $settingsType.GetField('_appearance', $flags).GetValue($form)
        $version = $settingsType.GetField('_versionLabel', $flags).GetValue($form)
        $floatMode = $settingsType.GetField('_floatMode', $flags).GetValue($form)
        $cards = @('_batteryCard', '_chargeCard', '_scheduleCard', '_notificationsCard', '_interfaceCard') | ForEach-Object { $settingsType.GetField($_, $flags).GetValue($form) }
        $footerButtons = @($footer.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] })
        $tag = "$lang " + ('{0:0.00}' -f $factor)
        $scale = $factor
        $logicalWidth = [int][Math]::Round($form.ClientSize.Width / $scale)
        $expectedRootHeight = if ($logicalWidth -ge 900) { 554 } else { 944 }
        $allCardsInside = $true
        foreach ($card in $cards) {
            if ($card.Right -gt $rootPanel.ClientSize.Width + 1 -or $card.Bottom -gt $rootPanel.ClientSize.Height + 1) { $allCardsInside = $false }
        }
        $allButtonsInside = ($footerButtons.Count -eq 3)
        foreach ($button in $footerButtons) {
            if ($button.Right -gt $footer.ClientSize.Width + 1 -or $button.Bottom -gt $footer.ClientSize.Height + 1) { $allButtonsInside = $false }
        }
        $versionInside = $version.Left -ge 0 -and $version.Top -ge 0 -and $version.Right -le $version.Parent.ClientSize.Width + 1 -and $version.Bottom -le $version.Parent.ClientSize.Height + 1
        $contentFits = ($rootPanel.Bottom -le $content.ClientSize.Height + 1) -or $content.VerticalScroll.Visible
        $nestedIssues = @()
        foreach ($card in $cards) { $nestedIssues += Get-LayoutIssues $card ('card:' + $card.Name) }
        $nestedIssues += Get-LayoutIssues $footer 'footer'

        Check "dpi settings $tag footer inside" ($footer.Bottom -le $form.ClientSize.Height + 1 -and $footer.Height -ge 48) ('footer=' + $footer.Bounds + ' client=' + $form.ClientSize)
        Check "dpi settings $tag actions inside" $allButtonsInside ('buttons=' + ($footerButtons | ForEach-Object { $_.Bounds } | Out-String).Trim())
        Check "dpi settings $tag content reachable" ($content.AutoScroll -and $contentFits) ('root=' + $rootPanel.Bounds + ' client=' + $content.ClientSize + ' vscroll=' + $content.VerticalScroll.Visible)
        Check "dpi settings $tag no horizontal scroll" (-not $content.HorizontalScroll.Visible -and $rootPanel.Right -le $content.ClientSize.Width + 1) ('hscroll=' + $content.HorizontalScroll.Visible + ' root=' + $rootPanel.Bounds + ' client=' + $content.ClientSize)
        Check "dpi settings $tag cards inside root" $allCardsInside ('root=' + $rootPanel.ClientSize + ' cards=' + (($cards | ForEach-Object { $_.Bounds }) | Out-String).Trim())
        Check "dpi settings $tag nested controls inside" ($nestedIssues.Count -eq 0) (($nestedIssues | Select-Object -First 3) -join '; ')
        Check "dpi settings $tag root height scaled" ($rootPanel.Height -ge [int][Math]::Ceiling($expectedRootHeight * $scale) - 2) ('root=' + $rootPanel.Height + ' expected>=' + [int][Math]::Ceiling($expectedRootHeight * $scale))
        Check "dpi settings $tag language above appearance" ($language.Parent.Top -lt $appearance.Parent.Top) ('language=' + $language.Parent.Top + ' appearance=' + $appearance.Parent.Top)
        Check "dpi settings $tag version shown" ($version.Text -match '\d+\.\d+\.\d+' -and $version.Width -gt 0 -and $versionInside) ('version=' + $version.Bounds + ' text=' + $version.Text)
        Check "dpi settings $tag schedule usable" ($scheduleList.Height -ge [int][Math]::Floor(40 * $factor) -and $add.Width -ge [int][Math]::Floor(60 * $factor)) ('list=' + $scheduleList.Height + ' add=' + $add.Bounds)
        Check "dpi settings $tag combos usable" ($language.Width -ge [int][Math]::Floor(150 * $factor) -and $appearance.Width -ge [int][Math]::Floor(150 * $factor)) ('language=' + $language.Bounds + ' appearance=' + $appearance.Bounds)
        Check "dpi settings $tag footer hint visible" ($hint.Width -gt 0 -and $hint.Height -gt 0) ('hint=' + $hint.Bounds)
        $floatText = [System.Windows.Forms.TextRenderer]::MeasureText($floatMode.Text, $floatMode.Font)
        Check "dpi settings $tag float label fits" ($floatMode.Width -gt 0 -and $floatText.Width -le $floatMode.ClientSize.Width) ('text=' + $floatText.Width + ' control=' + $floatMode.ClientSize.Width + ' label=' + $floatMode.Text)
        Check "dpi settings $tag save usable" ($save.Width -ge [int][Math]::Floor(80 * $factor) -and $save.Height -ge 28) ('save=' + $save.Bounds)
    }
    finally { $form.Dispose() }
}

function Test-DpiRule([string]$lang, [double]$factor) {
    Set-TestLanguage $lang
    $ctor = $ruleFormType.GetConstructor($flags, $null, [Type[]]@($ruleType), $null)
    $form = [System.Windows.Forms.Form]$ctor.Invoke([object[]]@($null))
    try {
        Scale-TestForm $form $factor
        $form.Opacity = 0
        Show-Offscreen $form
        if ($factor -le 1.0) { $form.ClientSize = New-Object System.Drawing.Size(500, 350) } else { Resize-Clamped $form }
        $content = [System.Windows.Forms.Panel](Find-Named $form 'RuleContent')
        $layout = [System.Windows.Forms.TableLayoutPanel](Find-Named $form 'RuleLayout')
        $note = [System.Windows.Forms.Label](Find-Named $form 'RuleNote')
        $ok = [System.Windows.Forms.Button](Find-Named $form 'RuleSave')
        $cancel = [System.Windows.Forms.Button](Find-Named $form 'RuleCancel')
        if (-not $content -or -not $layout -or -not $note -or -not $ok -or -not $cancel) { throw 'rule layout elements not found' }
        $content.PerformLayout()
        $layout.Width = [Math]::Max(360, $content.ClientSize.Width)
        $note.MaximumSize = New-Object System.Drawing.Size([Math]::Max(240, $layout.Width - 32), 0)
        $layout.PerformLayout()
        $content.PerformLayout()
        $bar = [System.Windows.Forms.FlowLayoutPanel]$ok.Parent
        $tag = "$lang " + ('{0:0.00}' -f $factor)
        $contentFits = ($layout.Bottom -le $content.ClientSize.Height + 1) -or $content.VerticalScroll.Visible
        $nestedIssues = @()
        $nestedIssues += Get-LayoutIssues $layout 'rule-layout'
        $nestedIssues += Get-LayoutIssues $bar 'rule-bar'
        Check "dpi rule $tag nested controls inside" ($nestedIssues.Count -eq 0) (($nestedIssues | Select-Object -First 3) -join '; ')
        Check "dpi rule $tag action inside" ($ok.Width -ge 90 -and $ok.Height -ge 30 -and $ok.Bottom -le $bar.ClientSize.Height + 1 -and $bar.Bottom -le $form.ClientSize.Height + 1) ('ok=' + $ok.Bounds + ' bar=' + $bar.Bounds + ' client=' + $form.ClientSize)
        Check "dpi rule $tag cancel inside" ($cancel.Width -ge 90 -and $cancel.Height -ge 30 -and $cancel.Bottom -le $bar.ClientSize.Height + 1) ('cancel=' + $cancel.Bounds)
        Check "dpi rule $tag content fits or scrolls" $contentFits ('layout=' + $layout.Bounds + ' client=' + $content.ClientSize + ' vscroll=' + $content.VerticalScroll.Visible)
        Check "dpi rule $tag avoids sideways scroll" (-not $content.HorizontalScroll.Visible -and $layout.Right -le $content.ClientSize.Width + 1) ('hscroll=' + $content.HorizontalScroll.Visible + ' layout=' + $layout.Bounds)
        Check "dpi rule $tag note complete" ($note.Height -ge 20 -and $note.Width -gt 100 -and $note.Text.Length -gt 20) ('note=' + $note.Bounds)
    }
    finally { $form.Dispose() }
}

function Test-DpiLog([string]$lang, [double]$factor) {
    Set-TestLanguage $lang
    $ctor = $logType.GetConstructor($flags, $null, [Type[]]@([string]), $null)
    $form = [System.Windows.Forms.Form]$ctor.Invoke([object[]]@([string](Join-Path $root 'application.log')))
    try {
        Scale-TestForm $form $factor
        $form.Opacity = 0
        Show-Offscreen $form
        if ($factor -le 1.0) { $form.ClientSize = New-Object System.Drawing.Size(760, 560) } else { Resize-Clamped $form }
        $box = [System.Windows.Forms.TextBox]$logType.GetField('_text', $flags).GetValue($form)
        $status = [System.Windows.Forms.Label]$logType.GetField('_status', $flags).GetValue($form)
        $bar = [System.Windows.Forms.FlowLayoutPanel]$status.Parent
        $form.PerformLayout()
        $bar.PerformLayout()
        $tag = "$lang " + ('{0:0.00}' -f $factor)
        $buttons = @($bar.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] })
        $buttonsInside = ($buttons.Count -eq 3)
        foreach ($button in $buttons) {
            if ($button.Right -gt $bar.ClientSize.Width + 1 -or $button.Bottom -gt $bar.ClientSize.Height + 1) { $buttonsInside = $false }
        }
        $nestedIssues = Get-LayoutIssues $bar 'log-bar'
        Check "dpi log $tag nested controls inside" ($nestedIssues.Count -eq 0) (($nestedIssues | Select-Object -First 3) -join '; ')
        Check "dpi log $tag bar inside" ($bar.Bottom -le $form.ClientSize.Height + 1 -and $bar.Height -ge 40) ('bar=' + $bar.Bounds + ' client=' + $form.ClientSize)
        Check "dpi log $tag actions inside" $buttonsInside ('buttons=' + (($buttons | ForEach-Object { $_.Bounds }) | Out-String).Trim())
        Check "dpi log $tag status visible" ($status.Width -gt 0 -and $status.Text.Length -gt 0 -and $status.Right -le $bar.ClientSize.Width + 1) ('status=' + $status.Bounds + ' bar=' + $bar.ClientSize)
        Check "dpi log $tag text area usable" ($box.Height -ge [int][Math]::Floor(40 * $factor)) ('text=' + $box.Bounds)
        Check "dpi log $tag wraps long lines" ($box.WordWrap -and $box.ScrollBars -eq [System.Windows.Forms.ScrollBars]::Vertical) ('wordWrap=' + $box.WordWrap + ' scroll=' + $box.ScrollBars)
    }
    finally { $form.Dispose() }
}

try {
    foreach ($lang in @('en', 'ar')) {
        foreach ($factor in @(1.0, 1.25, 1.5)) {
            Test-DpiSettings $lang $factor
            Test-DpiRule $lang $factor
            Test-DpiLog $lang $factor
        }
    }
}
finally {
    if ($null -ne $uiOriginal) {
        [IO.File]::WriteAllText($uiPath, $uiOriginal, (New-Object System.Text.UTF8Encoding($false)))
    } else {
        Remove-Item $uiPath -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $dpiTemp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:failed) { exit 1 }
