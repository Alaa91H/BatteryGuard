<#
.SYNOPSIS
  Checks ScheduleRules overlap detection, including overnight and full-day windows.

.DESCRIPTION
  Builds GuardConfig objects with schedule windows and calls the shared
  ScheduleRules.FindConflict used by the tray at load time and by the settings
  save guard. No WMI, no elevation.
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

$configType = Get-AppType 'GuardConfig'
$ruleType = Get-AppType 'WindowRule'
$rulesType = Get-AppType 'ScheduleRules'
if (-not $configType -or -not $ruleType -or -not $rulesType) { throw 'schedule types not found' }

$find = $rulesType.GetMethod('FindConflict', [System.Reflection.BindingFlags]'Public,Static')
$script:failed = $false

function New-Config($windows) {
    $config = [Activator]::CreateInstance($configType)
    foreach ($window in $windows) {
        $rule = [Activator]::CreateInstance($ruleType)
        $rule.From = $window[0]
        $rule.To = $window[1]
        if ($null -ne $window[2]) { $rule.Ceiling = [int]$window[2] }
        [void]$config.Schedule.Add($rule)
    }
    return $config
}

function Check([string]$name, $windows, [bool]$expectConflict) {
    $config = New-Config $windows
    [object[]]$arguments = @($config, $null, $null)
    $result = $find.Invoke($null, $arguments)
    $hasConflict = [bool]$result

    $state = if ($hasConflict) { 'conflict' } else { 'clean' }
    $expected = if ($expectConflict) { 'conflict' } else { 'clean' }
    $status = if ($hasConflict -eq $expectConflict) { 'OK' } else { 'MISMATCH' }

    '{0}: {1} (expected {2}) -> {3}' -f $name, $state, $expected, $status
    if ($hasConflict -ne $expectConflict) {
        $script:failed = $true
        '  detail: ' + $result
    }
}

Check 'same-day overlap' @(@('00:00', '08:00', 60), @('07:00', '09:00', $null)) $true
Check 'adjacent windows' @(@('00:00', '08:00', 60), @('08:00', '10:00', 80)) $false
Check 'overnight overlap' @(@('22:00', '06:00', 60), @('05:00', '07:00', $null)) $true
Check 'overnight boundary' @(@('22:00', '06:00', 60), @('06:00', '08:00', 80)) $false
Check 'full-day window' @(@('00:00', '00:00', 60), @('12:00', '13:00', $null)) $true
Check 'three windows clean' @(@('00:00', '08:00', 60), @('08:00', '18:00', 80), @('18:00', '23:59', $null)) $false

if ($script:failed) { exit 1 }
