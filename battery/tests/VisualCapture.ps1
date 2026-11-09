<#
.SYNOPSIS
  Captures the Settings, schedule and log windows for visual review.

.DESCRIPTION
  Constructs each WinForms dialog from the compiled source, forces English or
  Arabic plus light or dark theme, shows it briefly and writes a PNG next to
  this script. The settings window is also captured at full content height so
  every section can be reviewed without relying on the live window height.

  interface.ini and theme.ini are backed up and restored. No WMI writes, no
  charge-mode changes and no elevation required. Generated PNGs match the
  tests/*.png ignore rule.

  Run through PowerShell 5.1:
    powershell -File battery/tests/VisualCapture.ps1
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

$flags = [System.Reflection.BindingFlags]'Public,NonPublic,Instance'
$staticFlags = [System.Reflection.BindingFlags]'Public,Static'
$settingsType = Get-AppType 'SettingsForm'
$ruleFormType = Get-AppType 'WindowRuleForm'
$logType = Get-AppType 'LogForm'
$ruleType = Get-AppType 'WindowRule'
$themeType = Get-AppType 'ThemeSettings'
if (-not $settingsType -or -not $ruleFormType -or -not $logType -or -not $ruleType -or -not $themeType) {
    throw 'visual capture types not found'
}

$uiPath = Join-Path $root 'interface.ini'
$themePath = Join-Path $root 'theme.ini'
$uiBackup = Join-Path $root 'visual.test-backup.ini'
$themeBackup = Join-Path $root 'visual-theme.test-backup.ini'
$configPath = Join-Path $root 'visual.test-backup.json'
$outDir = $PSScriptRoot

if (Test-Path $uiPath) { Copy-Item $uiPath $uiBackup -Force }
if (Test-Path $themePath) { Copy-Item $themePath $themeBackup -Force }

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

function Set-Language([string]$code, [string]$direction) {
    $text = [IO.File]::ReadAllText($uiPath)
    if ($text -match '(?m)^language=') {
        $text = [regex]::Replace($text, '(?m)^language=.*$', 'language=' + $code)
    } else {
        $text = $text.TrimEnd() + [Environment]::NewLine + 'language=' + $code + [Environment]::NewLine
    }
    if ($text -match '(?m)^direction=') {
        $text = [regex]::Replace($text, '(?m)^direction=.*$', 'direction=' + $direction)
    } else {
        $text = $text.TrimEnd() + [Environment]::NewLine + 'direction=' + $direction + [Environment]::NewLine
    }
    [IO.File]::WriteAllText($uiPath, $text, (New-Object System.Text.UTF8Encoding($false)))
    $uiType = Get-AppType 'UiSettings'
    if ($uiType) { $uiType.GetMethod('Load', $staticFlags).Invoke($null, $null) }
}

function Set-Theme([string]$mode) {
    [IO.File]::WriteAllText($themePath, $mode + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    $themeType.GetMethod('Load', $staticFlags).Invoke($null, $null)
    $themeType.GetMethod('Apply', $staticFlags).Invoke($null, $null)
}

function Capture-Form([System.Windows.Forms.Form]$form, [string]$name) {
    $form.TopMost = $false
    $form.ShowInTaskbar = $false
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $form.Location = New-Object System.Drawing.Point(12, 12)
    $form.Show()
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 450

    # DrawToBitmap uses the form's logical surface and is not affected by the
    # host process DPI virtualization that makes CopyFromScreen crop the edge.
    $width = $form.Width
    $height = $form.Height
    'geometry ' + $name + ': ' + $width + 'x' + $height + ' client ' + $form.ClientSize.Width + 'x' + $form.ClientSize.Height
    $bitmap = New-Object System.Drawing.Bitmap($width, $height)
    $form.DrawToBitmap($bitmap, (New-Object System.Drawing.Rectangle(0, 0, $width, $height)))
    $bitmap.Save((Join-Path $outDir $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    $form.Hide()
    'saved ' + $name
}

function Capture-Full([System.Windows.Forms.Form]$form, [string]$name) {
    $form.TopMost = $false
    $form.ShowInTaskbar = $false
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $form.Location = New-Object System.Drawing.Point(12, 12)
    $form.Show()
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 300

    # Windows clamps a form to the screen tracking size, so render the full
    # SettingsRoot panel instead of trying to make the window taller.
    $root = $form.Controls[0]
    $content = $null
    foreach ($child in $form.Controls) {
        if ($child.Name -eq 'SettingsContent') { $content = $child; break }
    }
    if ($content -and $content.Controls.Count -gt 0) { $root = $content.Controls[0] }
    $root.PerformLayout()
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 300

    $bitmap = New-Object System.Drawing.Bitmap($root.Width, $root.Height)
    $root.DrawToBitmap($bitmap, (New-Object System.Drawing.Rectangle(0, 0, $root.Width, $root.Height)))
    $bitmap.Save((Join-Path $outDir $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    $form.Hide()
    'saved ' + $name
}

$notificationType = [System.Action[string, string, System.UInt32]]
$testNotify = [System.Action[string, string, System.UInt32]] { param($title, $text, $level) }
$settingsCtor = $settingsType.GetConstructor($flags, $null, [Type[]]@([string], $notificationType), $null)
$ruleCtor = $ruleFormType.GetConstructor($flags, $null, [Type[]]@($ruleType), $null)
$logCtor = $logType.GetConstructor($flags, $null, [Type[]]@([string]), $null)

try {
    foreach ($theme in @('light', 'dark')) {
        foreach ($language in @(@('en', 'ltr'), @('ar', 'rtl'))) {
            Set-Language $language[0] $language[1]
            Set-Theme $theme

            [object[]]$settingsArgs = @([string]$configPath, $testNotify)
            $settings = $settingsCtor.Invoke($settingsArgs)
            Capture-Form $settings ('visual-settings-' + $language[0] + '-' + $theme + '.png')
            $settings.Dispose()

            [object[]]$ruleArgs = @($null)
            $rule = $ruleCtor.Invoke($ruleArgs)
            Capture-Form $rule ('visual-schedule-' + $language[0] + '-' + $theme + '.png')
            $rule.Dispose()

            [object[]]$logArgs = @([string](Join-Path $root 'application.log'))
            $log = $logCtor.Invoke($logArgs)
            Capture-Form $log ('visual-log-' + $language[0] + '-' + $theme + '.png')
            $log.Dispose()
        }
    }

    Set-Language 'ar' 'rtl'
    Set-Theme 'light'
    [object[]]$fullArgs = @([string]$configPath, $testNotify)
    $full = $settingsCtor.Invoke($fullArgs)
    Capture-Full $full 'visual-settings-ar-light-full.png'
    $full.Dispose()
}
finally {
    if (Test-Path $uiBackup) { Copy-Item $uiBackup $uiPath -Force }
    if (Test-Path $themeBackup) { Copy-Item $themeBackup $themePath -Force }
    Remove-Item $uiBackup, $themeBackup, $configPath -Force -ErrorAction SilentlyContinue
}
