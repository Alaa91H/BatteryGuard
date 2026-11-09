<#
.SYNOPSIS
  Checks the real battery readings used by the tray app.

.DESCRIPTION
  Compiles the app source, calls BatteryInfo.Read() through reflection, prints
  the raw capacities, the computed percentage and health, and verifies the
  arithmetic. Read-only.
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

$type = $null
foreach ($assembly in [AppDomain]::CurrentDomain.GetAssemblies()) {
    $candidate = $assembly.GetType('BatteryGuardTray.BatteryInfo', $false)
    if ($candidate) { $type = $candidate; break }
}
if (-not $type) { throw 'BatteryInfo not found' }

$read = $type.GetMethod('Read', [System.Reflection.BindingFlags]'Public,Static')
$info = $read.Invoke($null, $null)

$percent = $type.GetField('Percent').GetValue($info)
$remaining = $type.GetField('Remaining').GetValue($info)
$full = $type.GetField('FullCharged').GetValue($info)
$designed = $type.GetField('Designed').GetValue($info)
$voltage = $type.GetField('Voltage').GetValue($info)
$chargeRate = $type.GetField('ChargeRate').GetValue($info)
$dischargeRate = $type.GetField('DischargeRate').GetValue($info)
$power = $type.GetProperty('PowerMilliwatts').GetValue($info, $null)
$online = $type.GetField('PowerOnline').GetValue($info)
$charging = $type.GetField('Charging').GetValue($info)
$discharging = $type.GetField('Discharging').GetValue($info)
$health = $type.GetProperty('Health').GetValue($info, $null)

'remaining      = {0} mWh' -f $remaining
'full charged   = {0} mWh' -f $full
'designed       = {0} mWh' -f $designed
'percent        = {0}%' -f $percent
'health         = {0}%' -f $health
'voltage        = {0} mV' -f $voltage
'charge rate    = {0} mW' -f $chargeRate
'discharge rate = {0} mW' -f $dischargeRate
'power          = {0} mW' -f $power
'power online   = {0}' -f $online
'charging       = {0}' -f $charging
'discharging    = {0}' -f $discharging

$instanceFlags = [System.Reflection.BindingFlags]'Public,Instance'
$electrical = $type.GetMethod('ElectricalText', $instanceFlags).Invoke($info, $null)
'electrical     = {0}' -f $electrical

$format = $type.GetMethod('FormatElectrical', [System.Reflection.BindingFlags]'Public,Static')
if ($format) {
    $sample = [string]$format.Invoke($null, @(11781, 6500))
    'format         = {0} -> {1}' -f $sample, $(if ($sample -eq '11.8 V · 6.5 W') { 'OK' } else { 'MISMATCH' })
    $idle = [string]$format.Invoke($null, @(11781, 0))
    'idle format    = {0} -> {1}' -f $idle, $(if ($idle -eq '11.8 V · 0.0 W') { 'OK' } else { 'MISMATCH' })
    $empty = [string]$format.Invoke($null, @(0, 0))
    'empty format   = {0} -> {1}' -f $empty, $(if ($empty.Length -eq 0) { 'OK' } else { 'MISMATCH' })
} else {
    'format          = missing'
}

if ($full -gt 0) {
    $expected = [math]::Round($remaining * 100.0 / $full)
    'expected percent= {0}% -> {1}' -f $expected, $(if ($expected -eq $percent) { 'OK' } else { 'MISMATCH' })
}
if ($designed -gt 0) {
    $expectedHealth = [math]::Round($full * 100.0 / $designed)
    'expected health = {0}% -> {1}' -f $expectedHealth, $(if ($expectedHealth -eq $health) { 'OK' } else { 'MISMATCH' })
}

$estimate = -1
if ($charging -and $chargeRate -gt 0 -and $full -gt $remaining) {
    $estimate = [int][math]::Round(($full - $remaining) * 60.0 / $chargeRate)
} elseif ($discharging -and $dischargeRate -gt 0) {
    $estimate = [int][math]::Round($remaining * 60.0 / $dischargeRate)
}
if ($estimate -gt 0) {
    'estimate       = {0} min -> {1}' -f $estimate, $(if ($estimate -ge 1 -and $estimate -le 2000) { 'OK' } else { 'SUSPICIOUS' })
} else {
    'estimate       = n/a (rate not reported)'
}

function Get-AppType([string]$name) {
    foreach ($assembly in [AppDomain]::CurrentDomain.GetAssemblies()) {
        $candidate = $assembly.GetType($name, $false)
        if ($candidate) { return $candidate }
    }
    return $null
}

$engineType = Get-AppType 'BatteryGuardTray.Engine'
if ($engineType) {
    $engine = [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject($engineType)
    $bind = [System.Reflection.BindingFlags]'Public,Instance'
    $engineType.GetField('Charging').SetValue($engine, $true)
    $engineType.GetField('Discharging').SetValue($engine, $false)
    $engineType.GetField('ChargeRate').SetValue($engine, 10000)
    $engineType.GetField('FullCharged').SetValue($engine, 40000)
    $engineType.GetField('Remaining').SetValue($engine, 20000)
    $chargeMinutes = $engineType.GetMethod('MinutesRemaining', $bind).Invoke($engine, $null)
    'charge estimate   = {0} min (expected 120) -> {1}' -f $chargeMinutes, $(if ($chargeMinutes -eq 120) { 'OK' } else { 'MISMATCH' })

    $limitMinutes = $engineType.GetMethod('MinutesToPercent', $bind).Invoke($engine, @(60))
    'limit estimate    = {0} min (expected 24) -> {1}' -f $limitMinutes, $(if ($limitMinutes -eq 24) { 'OK' } else { 'MISMATCH' })

    $policyType = $engineType.Assembly.GetType('BatteryGuardTray.Policy', $false)
    if ($policyType) {
        $policy = [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject($policyType)
        $policyType.GetField('Auto').SetValue($policy, $false)
        $policyType.GetField('Ceiling').SetValue($policy, 60)
        $engineType.GetField('Current').SetValue($engine, $policy)
        $configuredMinutes = $engineType.GetMethod('MinutesRemaining', $bind).Invoke($engine, $null)
        'configured time   = {0} min (expected 24) -> {1}' -f $configuredMinutes, $(if ($configuredMinutes -eq 24) { 'OK' } else { 'MISMATCH' })
    } else {
        'configured time   = Policy type not found'
    }

    $engineType.GetField('Charging').SetValue($engine, $false)
    $engineType.GetField('Discharging').SetValue($engine, $true)
    $engineType.GetField('DischargeRate').SetValue($engine, 8000)
    $dischargeMinutes = $engineType.GetMethod('MinutesRemaining', $bind).Invoke($engine, $null)
    'discharge estimate= {0} min (expected 150) -> {1}' -f $dischargeMinutes, $(if ($dischargeMinutes -eq 150) { 'OK' } else { 'MISMATCH' })
} else {
    'engine type not found'
}

$trayType = Get-AppType 'BatteryGuardTray.Engine'
if ($trayType) {
    $format = $trayType.GetMethod('FormatMinutes', [System.Reflection.BindingFlags]'Public,Static')
    'format 45  = {0}' -f $format.Invoke($null, @(45))
    'format 120 = {0}' -f $format.Invoke($null, @(120))
    'format 125 = {0}' -f $format.Invoke($null, @(125))
} else {
    'tray type not found'
}

'capacity.ini:'
if (Test-Path (Join-Path $root 'capacity.ini')) { Get-Content (Join-Path $root 'capacity.ini') } else { 'not created yet' }
