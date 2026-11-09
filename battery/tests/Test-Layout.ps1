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
    $direction = $settingsType.GetField('_direction', $flags).GetValue($settings)

    if (-not $content -or -not $footer -or -not $rootPanel) { throw 'settings content/footer not found' }

    foreach ($size in @(@(780, 601), @(700, 520), @(620, 480), @(560, 420))) {
        $settings.ClientSize = New-Object System.Drawing.Size([int]$size[0], [int]$size[1])
        $settings.PerformLayout()
        $content.PerformLayout()
        $footer.PerformLayout()
        [System.Windows.Forms.Application]::DoEvents()
        $tag = '{0}x{1}' -f $size[0], $size[1]

        Check "settings footer inside $tag" ($footer.Bottom -le $settings.ClientSize.Height + 1 -and $footer.Height -ge 48) ('footer=' + $footer.Bounds)
        Check "settings action usable $tag" ($save.Width -ge 80 -and $save.Height -ge 28) ('save=' + $save.Bounds)
        Check "settings content scrolls $tag" ($content.AutoScroll -and $content.VerticalScroll.Maximum -gt $content.ClientSize.Height) ('max=' + $content.VerticalScroll.Maximum + ' client=' + $content.ClientSize.Height)
        Check "settings root keeps width $tag" ($rootPanel.Width -ge 660 -and $rootPanel.Height -ge 900) ('root=' + $rootPanel.Bounds)
        Check "settings schedule list usable $tag" ($scheduleList.Height -ge 40) ('list=' + $scheduleList.Height)
        Check "settings add button usable $tag" ($add.Width -ge 60) ('add=' + $add.Bounds)
        Check "settings footer hint visible $tag" ($hint.Width -gt 0) ('hint=' + $hint.Bounds)
        Check "settings language combo usable $tag" ($language.Width -ge 150 -and $language.SelectedIndex -ge 0 -and $language.Text.Length -gt 0) ('language=' + $language.Bounds + ' index=' + $language.SelectedIndex + ' text=' + $language.Text)
        Check "settings direction combo usable $tag" ($direction.Width -ge 150 -and $direction.SelectedIndex -ge 0 -and $direction.Text.Length -gt 0) ('direction=' + $direction.Bounds + ' index=' + $direction.SelectedIndex + ' text=' + $direction.Text)
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

    foreach ($size in @(@(500, 400), @(440, 320), @(380, 300))) {
        $ruleForm.ClientSize = New-Object System.Drawing.Size([int]$size[0], [int]$size[1])
        $ruleForm.PerformLayout()
        $ruleContent.PerformLayout()
        [System.Windows.Forms.Application]::DoEvents()
        $tag = '{0}x{1}' -f $size[0], $size[1]

        Check "rule action inside $tag" ($ok.Width -ge 90 -and $ok.Parent.Bottom -le $ruleForm.ClientSize.Height + 1) ('ok=' + $ok.Bounds + ' bar=' + $ok.Parent.Bounds)
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

if ($script:failed) { exit 1 }
