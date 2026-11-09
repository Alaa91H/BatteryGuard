<#
.SYNOPSIS
  Replays controller WMI scenarios without hardware.

.DESCRIPTION
  This is the fixture runner for the controller simulator. It drives HpBios
  through SimulatedWmiGateway using synthetic read-only/write responses and
  prints the result. It cannot reach a real WMI provider. Use it to reproduce
  a tester report or a contract failure without changing charge state.

  No battery, firmware, WMI provider, settings file or elevation is used.
#>
[CmdletBinding()]
param(
    [ValidateSet('success', 'unplugged', 'denied', 'missing', 'mismatch', 'empty-read')]
    [string]$Scenario = 'success'
)

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

$fingerprintType = Get-AppType 'DeviceFingerprint'
$gatewayType = Get-AppType 'SimulatedWmiGateway'
$resultType = Get-AppType 'WmiCallResult'
$hpType = Get-AppType 'HpBios'
$interfaceType = Get-AppType 'IWmiGateway'
if (-not $fingerprintType -or -not $gatewayType -or -not $resultType -or -not $hpType -or -not $interfaceType) {
    throw 'controller simulator types not found'
}

$fingerprint = [Activator]::CreateInstance($fingerprintType)
$fingerprintType.GetField('Manufacturer').SetValue($fingerprint, 'HP')
$fingerprintType.GetField('Product').SetValue($fingerprint, 'Simulated notebook')
$fingerprintType.GetField('BiosVersion').SetValue($fingerprint, 'S.01')
$gateway = [Activator]::CreateInstance($gatewayType)
$ok = $resultType.GetMethod('Ok', [System.Reflection.BindingFlags]'Public,Static')
$fail = $resultType.GetMethod('Fail', [System.Reflection.BindingFlags]'Public,Static')
$enqueue = $gatewayType.GetMethod('Enqueue')

function Add-Ok([byte]$value) {
    [void]$enqueue.Invoke($gateway, @($ok.Invoke($null, @([uint32]0, [byte[]]@($value)))))
}
function Add-Failure([string]$message) {
    [void]$enqueue.Invoke($gateway, @($fail.Invoke($null, @($message))))
}
function Add-Empty {
    [void]$enqueue.Invoke($gateway, @($ok.Invoke($null, @([uint32]0, [byte[]]@()))))
}

switch ($Scenario) {
    'success' {
        Add-Ok 0
        Add-Ok 4
        $onAc = $true
    }
    'unplugged' {
        $onAc = $false
    }
    'denied' {
        Add-Failure 'simulated access denied'
        $onAc = $true
    }
    'missing' {
        $onAc = $true
    }
    'mismatch' {
        Add-Ok 0
        Add-Ok 0
        Add-Ok 0
        $onAc = $true
    }
    'empty-read' {
        Add-Ok 0
        Add-Empty
        Add-Ok 0
        $onAc = $true
    }
}

$ctor = $hpType.GetConstructor([System.Reflection.BindingFlags]'Public,NonPublic,Instance', $null,
    [Type[]]@($fingerprintType, $interfaceType), $null)
$hp = $ctor.Invoke([object[]]@($fingerprint, $gateway))
try {
    $method = $hpType.GetMethod('RequestInhibit', [System.Reflection.BindingFlags]'Public,NonPublic,Instance')
    $result = $method.Invoke($hp, @($onAc))
    $detail = if ($result.Detail) { ' - ' + $result.Detail } else { '' }
    'scenario: ' + $Scenario
    'result:   ' + $result.Status + $detail
    'observed: ' + $result.Observed
    'gateway calls: ' + @($gatewayType.GetField('Calls').GetValue($gateway)).Count
    'No real hardware was touched.'
}
finally {
    $hp.Dispose()
}
