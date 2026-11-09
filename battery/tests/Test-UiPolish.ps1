<#
.SYNOPSIS
  Checks the settings, schedule and log windows without showing them.

.DESCRIPTION
  Loads a temporary config with two overlapping windows and verifies the
  in-window warning banner, the expanded warning row and the colored rows.
  Then checks the clean and empty states, the full-day hint in the window
  dialog, and the log status line. No WMI writes and no file changes outside
  the temporary config.
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

$uiPath = Join-Path $root 'interface.ini'
$uiBackup = Join-Path $root 'ui.test-backup.txt'
$uiExisted = Test-Path $uiPath
if ($uiExisted) { Copy-Item $uiPath $uiBackup -Force }
Set-Content -Path $uiPath -Value 'language=en' -Encoding ASCII

function Get-AppType([string]$name) {
    foreach ($assembly in [AppDomain]::CurrentDomain.GetAssemblies()) {
        $candidate = $assembly.GetType('BatteryGuardTray.' + $name, $false)
        if ($candidate) { return $candidate }
    }
    return $null
}

$settingsType = Get-AppType 'SettingsForm'
$ruleType = Get-AppType 'WindowRule'
$ruleFormType = Get-AppType 'WindowRuleForm'
$logType = Get-AppType 'LogForm'
$themeType = Get-AppType 'ThemeSettings'
$themeTypeUi = Get-AppType 'UiTheme'
if (-not $settingsType -or -not $ruleType -or -not $ruleFormType -or -not $logType) {
    throw 'UI types not found'
}

$flags = [System.Reflection.BindingFlags]'Public,NonPublic,Instance'
$staticFlags = [System.Reflection.BindingFlags]'Public,Static'
$notificationType = [System.Action[string, string, System.UInt32]]
$settingsCtor = $settingsType.GetConstructor($flags, $null, [Type[]]@([string], $notificationType), $null)
$testNotify = [System.Action[string, string, System.UInt32]] { param($title, $text, $level) }
$script:failed = $false

$temp = Join-Path ([IO.Path]::GetTempPath()) ('batteryguard-ui-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
$configPath = Join-Path $temp 'settings.json'

function Write-Utf8([string]$path, [string]$text) {
    [IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
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

function New-Settings([string]$json) {
    Write-Utf8 $configPath $json
    [object[]]$constructorArgs = @([string]$configPath, $testNotify)
    return $settingsCtor.Invoke($constructorArgs)
}

function Get-Field($form, [string]$name) {
    return $settingsType.GetField($name, $flags).GetValue($form)
}

function Find-Control($parent, [string]$text, [bool]$contains) {
    foreach ($child in $parent.Controls) {
        $match = if ($contains) { $child.Text -like ('*' + $text + '*') } else { $child.Text -eq $text }
        if ($match) { return $child }
        $found = Find-Control $child $text $contains
        if ($found) { return $found }
    }
    return $null
}

try {
    $overlap = @'
{
  "preset": "Custom",
  "ceiling": 70,
  "resume": 65,
  "resumeDrop": 5,
  "intervalSeconds": 60,
  "scheduleEnabled": true,
  "floatMode": true,
  "schedule": [
    { "from": "00:00", "to": "08:00", "ceiling": 60 },
    { "from": "07:00", "to": "09:00", "ceiling": null }
  ]
}
'@
    $form = New-Settings $overlap
    $hint = Get-Field $form '_scheduleHint'
    $grid = Get-Field $form '_scheduleGrid'
    $list = Get-Field $form '_scheduleList'

    Check 'load-time conflict banner' ($hint.Text -match '07:00' -and $hint.Text -match '08:00') $hint.Text
    Check 'banner row expanded' ([double]$grid.RowStyles[1].Height -gt 0) ('row=' + $grid.RowStyles[1].Height)

    if ($themeType -and $themeTypeUi) {
        $dark = $themeType.GetProperty('MenuDark', $staticFlags).GetValue($null, $null)
        $warning = $themeTypeUi.GetMethod('Warning', $staticFlags).Invoke($null, @([bool]$dark))
        Check 'conflicting rows highlighted' ($list.Items[0].ForeColor.ToArgb() -eq $warning.ToArgb() -and $list.Items[1].ForeColor.ToArgb() -eq $warning.ToArgb()) ('rows=' + $list.Items.Count)
    }

    $form.Dispose()

    $clean = @'
{
  "preset": "Off",
  "ceiling": null,
  "resume": null,
  "resumeDrop": 5,
  "intervalSeconds": 60,
  "scheduleEnabled": false,
  "floatMode": false,
  "schedule": []
}
'@
    $form = New-Settings $clean
    $hint = Get-Field $form '_scheduleHint'
    $grid = Get-Field $form '_scheduleGrid'
    $empty = Get-Field $form '_scheduleEmpty'
    $schedule = Get-Field $form '_schedule'

    Check 'clean config has no banner' ($hint.Text -eq '' -and [double]$grid.RowStyles[1].Height -eq 0)
    Check 'empty schedule explains paused state' ($empty.Text -match 'Schedule is off') $empty.Text

    $schedule.Checked = $true
    Check 'empty schedule invites adding' ($empty.Text -match 'No schedule time windows') $empty.Text
    $form.Dispose()

    $rule = [Activator]::CreateInstance($ruleType)
    $rule.From = '00:00'
    $rule.To = '00:00'
    $ruleCtor = $ruleFormType.GetConstructor($flags, $null, [Type[]]@($ruleType), $null)
    [object[]]$ruleArgs = @($rule)
    $ruleForm = $ruleCtor.Invoke($ruleArgs)
    $fullDayNote = Find-Control $ruleForm 'entire day' $true
    $ok = Find-Control $ruleForm 'Save' $false

    Check 'full-day hint present' ($null -ne $fullDayNote)
    Check 'dialog exposes primary action' ($null -ne $ok -and $ok.Width -ge 90)

    if ($ok) {
        $onClick = $ok.GetType().GetMethod('OnClick', $flags)
        [void]$onClick.Invoke($ok, @([EventArgs]::Empty))
        Check 'equal times accepted' ($ruleForm.Rule.From -eq '00:00' -and $ruleForm.Rule.To -eq '00:00' -and $ruleForm.DialogResult -eq [System.Windows.Forms.DialogResult]::OK) ('from=' + $ruleForm.Rule.From + ' to=' + $ruleForm.Rule.To)
    }
    $ruleForm.Dispose()

    $logCtor = $logType.GetConstructor($flags, $null, [Type[]]@([string]), $null)
    [object[]]$logArgs = @([string](Join-Path $root 'application.log'))
    $logForm = $logCtor.Invoke($logArgs)
    $status = $logType.GetField('_status', $flags).GetValue($logForm)
    $box = $logType.GetField('_text', $flags).GetValue($logForm)

    Check 'log status line present' ($status.Text -match '(line|entries|No activity)') $status.Text
    Check 'log content populated' ($box.Text.Length -gt 0)
    $logForm.Dispose()
}
finally {
    if ($uiExisted) { Copy-Item $uiBackup $uiPath -Force }
    else { Remove-Item $uiPath -Force -ErrorAction SilentlyContinue }
    Remove-Item $uiBackup -Force -ErrorAction SilentlyContinue
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:failed) { exit 1 }
