<#
.SYNOPSIS
  Checks the charge/float decision table without touching hardware.

.DESCRIPTION
  Compiles the application and calls ChargePolicy.Evaluate directly. Float must
  only latch after the ceiling is reached, keep the battery on charger power
  until the resume point, and never start while charging is still below the
  configured limit. No WMI reads or writes and no elevation.
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

$policyType = Get-AppType 'ChargePolicy'
$modeType = Get-AppType 'ChargeMode'
if (-not $policyType -or -not $modeType) { throw 'charge policy types not found' }

$evaluate = $policyType.GetMethod('Evaluate', [System.Reflection.BindingFlags]'Public,Static')
$script:failed = $false

function Evaluate([bool]$standardCharging, [bool]$onAc, [int]$percent, $ceiling, $resume, [bool]$floatMode, [bool]$floatActive, [string]$mode) {
    $modeValue = [Enum]::Parse($modeType, $mode)
    [object[]]$arguments = @($standardCharging, $onAc, $percent, $ceiling, $resume, $floatMode, $floatActive, $modeValue)
    return $evaluate.Invoke($null, $arguments)
}

function Check([string]$name, $decision, [string]$action, [bool]$floatActive) {
    $actualAction = $decision.Action.ToString()
    $ok = $actualAction -eq $action -and [bool]$decision.FloatActive -eq $floatActive
    '{0}: action={1} float={2} (expected {3}/{4}) -> {5}' -f $name, $actualAction, $decision.FloatActive, $action, $floatActive, $(if ($ok) { 'OK' } else { 'MISMATCH' })
    if (-not $ok) { $script:failed = $true }
}

# The requirement: charge fully to the limit first, then float. Below the
# ceiling no inhibit is requested and the latch stays off.
Check 'below limit, auto' (Evaluate $false $true 70 80 75 $true $false 'Auto') 'None' $false
Check 'one point below limit' (Evaluate $false $true 79 80 75 $true $false 'Auto') 'None' $false

# Reaching the ceiling stops charging and latches float (when enabled).
Check 'at limit, auto' (Evaluate $false $true 80 80 75 $true $false 'Auto') 'Inhibit' $true
Check 'above limit, auto' (Evaluate $false $true 85 80 75 $true $false 'Auto') 'Inhibit' $true
Check 'at limit, float off' (Evaluate $false $true 80 80 75 $false $false 'Auto') 'Inhibit' $false

# While floating, small drops must not cycle the battery; the resume point
# releases the latch and restores charging.
Check 'float holds above resume' (Evaluate $false $true 78 80 75 $true $true 'Inhibit') 'None' $true
Check 'float holds at limit' (Evaluate $false $true 80 80 75 $true $true 'Inhibit') 'None' $true
Check 'resume point reached' (Evaluate $false $true 75 80 75 $true $true 'Inhibit') 'Auto' $false
Check 'below resume' (Evaluate $false $true 70 80 75 $true $true 'Inhibit') 'Auto' $false

# A stale inhibit below the target is not float: release it so charging can
# reach the limit. This was the original bug.
Check 'stale inhibit below limit' (Evaluate $false $true 70 80 75 $true $false 'Inhibit') 'Auto' $false

# No float on battery power, without a limit or in standard-charging windows.
Check 'on battery at limit' (Evaluate $false $false 80 80 75 $true $false 'Inhibit') 'Auto' $false
Check 'standard charging window' (Evaluate $true $true 80 80 75 $true $false 'Inhibit') 'Auto' $false
Check 'no ceiling configured' (Evaluate $false $true 80 $null $null $true $false 'Auto') 'None' $false

if ($script:failed) { exit 1 }
