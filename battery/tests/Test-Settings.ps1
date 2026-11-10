<#
.SYNOPSIS
  Exercises the settings window logic without showing it.

.DESCRIPTION
  Backs up the config and interface.ini, constructs SettingsForm from the compiled
  source, verifies the loaded values, adds two schedule windows, enables float
  mode and a 1% resume, saves, checks both files, then restores the originals.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$root = Split-Path -Parent $PSScriptRoot
$sources = @(Get-ChildItem -Path (Join-Path $root 'src') -Filter '*.cs' | Sort-Object Name | ForEach-Object { $_.FullName })
$configPath = Join-Path $root 'settings.json'
$uiPath = Join-Path $root 'interface.ini'
$themePath = Join-Path $root 'theme.ini'
$configBackup = Join-Path $root 'config.test-backup.json'
$uiBackup = Join-Path $root 'ui.test-backup.txt'
$themeBackup = Join-Path $root 'theme.test-backup.txt'

Copy-Item $configPath $configBackup -Force
if (Test-Path $uiPath) { Copy-Item $uiPath $uiBackup -Force }
$themeExisted = Test-Path $themePath
if ($themeExisted) { Copy-Item $themePath $themeBackup -Force }

try {
    $env:BATTERYGUARD_HOME = $root
    Add-Type -Path $sources -ReferencedAssemblies 'System.dll', 'System.Drawing.dll', 'System.Management.dll', 'System.Web.Extensions.dll', 'System.Windows.Forms.dll'

    $type = $null
    foreach ($assembly in [AppDomain]::CurrentDomain.GetAssemblies()) {
        $candidate = $assembly.GetType('BatteryGuardTray.SettingsForm', $false)
        if ($candidate) { $type = $candidate; break }
    }
    if (-not $type) { throw 'SettingsForm not found' }

    $flags = [System.Reflection.BindingFlags]'Public,NonPublic,Instance'
    $notificationType = [System.Action[string, string, System.UInt32]]
    $ctor = $type.GetConstructor($flags, $null, [Type[]]@([string], $notificationType), $null)
    $testNotification = [System.Action[string, string, System.UInt32]] { param($title, $text, $flags) }
    [object[]]$constructorArgs = @([string]$configPath, $testNotification)
    $form = $ctor.Invoke($constructorArgs)

    $limit = $type.GetField('_limitEnabled', $flags).GetValue($form)
    $ceiling = $type.GetField('_ceilingValue', $flags).GetValue($form)
    $resume = $type.GetField('_resumeValue', $flags).GetValue($form)
    $slider = $type.GetField('_slider', $flags).GetValue($form)
    $floatMode = $type.GetField('_floatMode', $flags).GetValue($form)
    $schedule = $type.GetField('_schedule', $flags).GetValue($form)
    $scheduleList = $type.GetField('_scheduleList', $flags).GetValue($form)
    $appearance = $type.GetField('_appearance', $flags).GetValue($form)
    $direction = $type.GetField('_direction', $flags).GetValue($form)
    $versionLabel = $type.GetField('_versionLabel', $flags).GetValue($form)
    $fullThreshold = $type.GetField('_fullThreshold', $flags).GetValue($form)
    $lowThreshold = $type.GetField('_lowThreshold', $flags).GetValue($form)

    'form title      = ' + $form.Text
    'form size       = ' + $form.ClientSize.Width + 'x' + $form.ClientSize.Height
    'limit enabled   = ' + $limit.Checked
    'ceiling value   = ' + $ceiling.Value
    'resume value    = ' + $resume.Value
    'slider upper    = ' + $slider.UpperValue
    'slider lower    = ' + $slider.LowerValue
    'float mode      = ' + $floatMode.Checked
    'schedule count  = ' + $scheduleList.Items.Count
    'appearance index= ' + $appearance.SelectedIndex
    'direction index = ' + $direction.SelectedIndex
    'version label   = ' + $versionLabel.Text
    'schedule checked= ' + $schedule.Checked
    'full threshold  = ' + $fullThreshold.Value
    'low threshold   = ' + $lowThreshold.Value
    'rtl             = ' + $form.RightToLeft

    # custom 70% ceiling, resume all the way down to 1%, float mode on
    $limit.Checked = $true
    $ceiling.Value = 70
    $resume.Value = 1
    $floatMode.Checked = $true
    $schedule.Checked = $true
    $direction.SelectedIndex = 2
    $fullThreshold.Value = 95
    $lowThreshold.Value = 25

    $type.GetProperty('SuppressMessages', $flags).SetValue($form, $true)
    $save = $type.GetMethod('OnSave', [System.Reflection.BindingFlags]'NonPublic,Instance')
    [object[]]$saveArgs = @($null, [System.EventArgs]::Empty)

    # overlapping windows must abort the save and leave the config untouched
    foreach ($window in @(@('00:00', '08:00', '60%'), @('07:00', '09:00', 'طبيعي'))) {
        $item = New-Object System.Windows.Forms.ListViewItem($window[0])
        [void]$item.SubItems.Add($window[1])
        [void]$item.SubItems.Add($window[2])
        [void]$scheduleList.Items.Add($item)
    }

    $configBefore = Get-Content $configPath -Raw
    $save.Invoke($form, $saveArgs)
    'conflict error  = ' + $type.GetField('ValidationError', $flags).GetValue($form)
    'config unchanged= ' + ((Get-Content $configPath -Raw) -eq $configBefore)

    # valid, non-overlapping windows save normally
    $scheduleList.Items.Clear()
    foreach ($window in @(@('00:00', '08:00', '60%'), @('12:00', '14:00', 'طبيعي'))) {
        $item = New-Object System.Windows.Forms.ListViewItem($window[0])
        [void]$item.SubItems.Add($window[1])
        [void]$item.SubItems.Add($window[2])
        [void]$scheduleList.Items.Add($item)
    }

    $save.Invoke($form, $saveArgs)
    $form.Dispose()

    $logType = $null
    foreach ($assembly in [AppDomain]::CurrentDomain.GetAssemblies()) {
        $candidate = $assembly.GetType('BatteryGuardTray.LogForm', $false)
        if ($candidate) { $logType = $candidate; break }
    }
    if ($logType) {
        $logConstructor = $logType.GetConstructor($flags, $null, [Type[]]@([string]), $null)
        [object[]]$logArguments = @([string](Join-Path $root 'application.log'))
        $logForm = $logConstructor.Invoke($logArguments)
        $logBox = $logType.GetField('_text', $flags).GetValue($logForm)
        'log window lines = ' + (($logBox.Text -split "`r?`n") | Where-Object { $_ }).Count
        $logForm.Dispose()
    }

    '--- saved config ---'
    Get-Content $configPath
    '--- saved interface.ini ---'
    Get-Content $uiPath
}
finally {
    Copy-Item $configBackup $configPath -Force
    if (Test-Path $uiBackup) { Copy-Item $uiBackup $uiPath -Force }
    if ($themeExisted) { Copy-Item $themeBackup $themePath -Force }
    else { Remove-Item $themePath -Force -ErrorAction SilentlyContinue }
    Remove-Item $configBackup, $uiBackup, $themeBackup -Force -ErrorAction SilentlyContinue
    '--- restored config ---'
    Get-Content $configPath
}
