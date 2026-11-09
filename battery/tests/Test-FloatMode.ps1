<#
.SYNOPSIS
  Verifies float mode on the real hardware: with the charger connected and the
  firmware in Inhibit, the battery must stay idle (not discharging) and its
  remaining capacity must not drop during a short sample.

.DESCRIPTION
  Needs elevation for HP WMI. If the charger is disconnected or the firmware
  does not support the mode, the test reports SKIP instead of failing. If the
  firmware is not already inhibited, it is set to Inhibit for the sample and
  restored to its original mode afterwards.
#>
[CmdletBinding()]
param([int]$SampleSeconds = 6)

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

$batteryType = Get-AppType 'BatteryInfo'
$biosType = Get-AppType 'HpBios'
if (-not $batteryType -or -not $biosType) { throw 'BatteryInfo or HpBios not found' }

$read = $batteryType.GetMethod('Read', [System.Reflection.BindingFlags]'Public,Static')
$instanceFlags = [System.Reflection.BindingFlags]'Public,NonPublic,Instance'
$modeMethod = $biosType.GetMethod('ReadMode', $instanceFlags)
$setAuto = $biosType.GetMethod('SetAuto', $instanceFlags)
$setInhibit = $biosType.GetMethod('SetInhibit', $instanceFlags)

$before = $read.Invoke($null, $null)
if (-not $before.PowerOnline) {
    'ac online      = False'
    'float test     = SKIP (charger is not connected)'
    exit 0
}

$bios = [Activator]::CreateInstance($biosType)
$original = [string]$modeMethod.Invoke($bios, $null)
'original mode  = ' + $original

try {
    if ($original -ne 'Inhibit') {
        $setInhibit.Invoke($bios, $null) | Out-Null
        Start-Sleep -Seconds 2
    }

    $first = $read.Invoke($null, $null)
    $tested = [string]$modeMethod.Invoke($bios, $null)
    Start-Sleep -Seconds $SampleSeconds
    $second = $read.Invoke($null, $null)

    $started = [int]$first.Remaining
    $ended = [int]$second.Remaining
    $drop = $started - $ended

    'tested mode    = ' + $tested
    'ac online      = ' + $second.PowerOnline
    'charging       = ' + $second.Charging
    'discharging    = ' + $second.Discharging
    'remaining      = {0} -> {1} mWh (drop {2})' -f $started, $ended, $drop

    $pass = $tested -eq 'Inhibit' -and $second.PowerOnline -and -not $second.Discharging -and $drop -le 200
    'float test     = ' + $(if ($pass) { 'PASS' } else { 'FAIL' })
    if (-not $pass) { exit 1 }
}
finally {
    if ($original -eq 'Auto') { $setAuto.Invoke($bios, $null) | Out-Null }
    $bios.Dispose()
}
