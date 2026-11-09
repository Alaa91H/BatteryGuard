<#
.SYNOPSIS
  Verifies the controller profile, capability and safety layer without hardware.

.DESCRIPTION
  Compiles the application, constructs synthetic device fingerprints, and drives
  HpBios through a simulated WMI gateway. No real WMI provider, firmware write,
  battery or elevation is used. The test covers unsupported profiles, the
  auto/inhibit allow-list, unplugged inhibition, WMI access denial, an empty
  read-back, a read-back mismatch with rollback, and the absence of a
  ForceDischarge path.
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

function Check([string]$name, [bool]$ok, [string]$detail) {
    if ($ok) {
        '{0}: OK{1}' -f $name, $(if ($detail) { ' (' + $detail + ')' } else { '' })
    }
    else {
        '{0}: FAIL{1}' -f $name, $(if ($detail) { ' (' + $detail + ')' } else { '' })
        $script:failed = $true
    }
}

$flagsInstance = [System.Reflection.BindingFlags]'Public,NonPublic,Instance'
$flagsStatic = [System.Reflection.BindingFlags]'Public,NonPublic,Static'
$typeNames = @('ChargeMode', 'DeviceFingerprint', 'DeviceProfileCatalog', 'DeviceProfile',
    'ControllerCapabilities', 'WmiCallResult', 'SimulatedWmiGateway', 'IWmiGateway',
    'HpBios', 'WriteGuard', 'BatteryControllerFactory')
$types = @{}
foreach ($name in $typeNames) {
    $types[$name] = Get-AppType $name
    if (-not $types[$name]) { throw "$name type not found" }
}

$fingerprintType = $types['DeviceFingerprint']
$profileType = $types['DeviceProfile']
$capabilityType = $types['ControllerCapabilities']
$resultType = $types['WmiCallResult']
$modeType = $types['ChargeMode']

function New-Fingerprint([string]$manufacturer, [string]$product, [string]$bios) {
    $fingerprint = [Activator]::CreateInstance($fingerprintType)
    $fingerprintType.GetField('Manufacturer').SetValue($fingerprint, $manufacturer)
    $fingerprintType.GetField('Product').SetValue($fingerprint, $product)
    $fingerprintType.GetField('BiosVersion').SetValue($fingerprint, $bios)
    return $fingerprint
}

$match = $types['DeviceProfileCatalog'].GetMethod('Match', $flagsStatic)
$script:failed = $false

# --- profile matching and write eligibility -------------------------------
$hpFingerprint = New-Fingerprint 'HP' 'HP ENVY x360' 'F.28'
$hpProfile = $match.Invoke($null, @($hpFingerprint))
Check 'HP profile matches' ($hpProfile -and $hpProfile.Vendor -eq 'HP') ($hpProfile.Vendor)
Check 'HP profile can write' ($hpProfile -and [bool]$profileType.GetProperty('CanWrite').GetValue($hpProfile, $null)) 'field-verified'

$acerFingerprint = New-Fingerprint 'Acer' 'Nitro AN515-57' 'V1.22'
$acerProfile = $match.Invoke($null, @($acerFingerprint))
Check 'Acer profile is detected' ($acerProfile -and $acerProfile.Vendor -eq 'Acer') ($acerProfile.Vendor)
Check 'Acer profile is not write-enabled' ($acerProfile -and -not [bool]$profileType.GetProperty('CanWrite').GetValue($acerProfile, $null)) 'documented only'
$acerCapabilities = $profileType.GetField('Capabilities').GetValue($acerProfile)
$acerLimits = @(
    [int]$capabilityType.GetField('MinPercent').GetValue($acerCapabilities),
    [int]$capabilityType.GetField('MaxPercent').GetValue($acerCapabilities),
    [int]$capabilityType.GetField('DefaultLimit').GetValue($acerCapabilities)
)
Check 'Acer profile is fixed at 80%' (($acerCapabilities.Kind.ToString() -eq 'FixedThreshold') -and ($acerLimits -join ',') -eq '80,80,80') ($acerLimits -join ',')
$allows = $capabilityType.GetMethod('Allows', $flagsInstance)
Check 'fixed profile allows only its exact limit' ([bool]$allows.Invoke($acerCapabilities, @(80)) -and -not [bool]$allows.Invoke($acerCapabilities, @(90))) '80 allowed, 90 rejected'
$displayName = [string]$capabilityType.GetProperty('DisplayName', $flagsInstance).GetValue($acerCapabilities, $null)
Check 'fixed capability describes 80%' ($displayName -eq 'Charge limit 80%') $displayName
$startStop = $capabilityType.GetMethod('StartStopThreshold', $flagsStatic).Invoke($null, @(50, 100, 80))
$startStopName = [string]$capabilityType.GetProperty('DisplayName', $flagsInstance).GetValue($startStop, $null)
Check 'start-stop capability describes its range' ($startStopName -eq ('Charge limit 50%' + [char]0x2013 + '100%')) $startStopName
$monitoring = $capabilityType.GetMethod('Monitoring', $flagsStatic).Invoke($null, @())
$monitoringName = [string]$capabilityType.GetProperty('DisplayName', $flagsInstance).GetValue($monitoring, $null)
Check 'monitoring capability describes monitoring only' ($monitoringName -eq 'Monitoring only') $monitoringName

$dellFingerprint = New-Fingerprint 'Dell Inc.' 'XPS 13 9310' '2.8.0'
$dellProfile = $match.Invoke($null, @($dellFingerprint))
Check 'Dell profile is candidate only' ($dellProfile -and $dellProfile.Vendor -eq 'Dell' -and -not [bool]$profileType.GetProperty('CanWrite').GetValue($dellProfile, $null)) 'candidate'
$unknownProfile = $match.Invoke($null, @(New-Fingerprint 'Example Corp' 'Laptop' '1.0'))
Check 'unknown profile has no writer' ($null -eq $unknownProfile) 'no match'

# --- mode allow-list ------------------------------------------------------
$safeMode = $types['WriteGuard'].GetMethod('IsSafeMode', $flagsStatic)
$autoMode = [Enum]::Parse($modeType, 'Auto')
$inhibitMode = [Enum]::Parse($modeType, 'Inhibit')
$forceMode = [Enum]::Parse($modeType, 'ForceDischarge')
Check 'auto is an allowed mode' ([bool]$safeMode.Invoke($null, @($autoMode))) 'Auto'
Check 'inhibit is an allowed mode' ([bool]$safeMode.Invoke($null, @($inhibitMode))) 'Inhibit'
Check 'forced discharge is rejected' (-not [bool]$safeMode.Invoke($null, @($forceMode))) 'ForceDischarge'

# --- simulated HP WMI contract -------------------------------------------
$gatewayInterface = $types['IWmiGateway']
$hpCtor = $types['HpBios'].GetConstructor($flagsInstance, $null,
    [Type[]]@($fingerprintType, $gatewayInterface), $null)
$requestInhibit = $types['HpBios'].GetMethod('RequestInhibit', $flagsInstance)
$requestAuto = $types['HpBios'].GetMethod('RequestAuto', $flagsInstance)
$okMethod = $resultType.GetMethod('Ok', $flagsStatic)
$failMethod = $resultType.GetMethod('Fail', $flagsStatic)
if (-not $hpCtor -or -not $requestInhibit -or -not $requestAuto -or -not $okMethod -or -not $failMethod) {
    throw 'HP simulation methods not found'
}

function New-Gateway {
    return [Activator]::CreateInstance($types['SimulatedWmiGateway'])
}

function Add-Ok([object]$gateway, [byte]$value) {
    $response = $okMethod.Invoke($null, @([uint32]0, [byte[]]@($value)))
    [void]$types['SimulatedWmiGateway'].GetMethod('Enqueue').Invoke($gateway, @($response))
}

function Add-Failure([object]$gateway, [string]$message) {
    $response = $failMethod.Invoke($null, @($message))
    [void]$types['SimulatedWmiGateway'].GetMethod('Enqueue').Invoke($gateway, @($response))
}

function Add-Empty([object]$gateway) {
    $response = $okMethod.Invoke($null, @([uint32]0, [byte[]]@()))
    [void]$types['SimulatedWmiGateway'].GetMethod('Enqueue').Invoke($gateway, @($response))
}

function New-Hp([object]$fingerprint, [object]$gateway) {
    return $hpCtor.Invoke([object[]]@($fingerprint, $gateway))
}

function Get-Calls([object]$gateway) {
    $calls = $types['SimulatedWmiGateway'].GetField('Calls').GetValue($gateway)
    return @($calls)
}

function Get-Status([object]$result) {
    return $result.GetType().GetField('Status').GetValue($result).ToString()
}

# Normal inhibit: write succeeds, readback says Inhibit.
$gateway = New-Gateway
Add-Ok $gateway 0
Add-Ok $gateway 4
$hp = New-Hp $hpFingerprint $gateway
$result = $requestInhibit.Invoke($hp, @($true))
$calls = Get-Calls $gateway
Check 'inhibit succeeds with read-back' ((Get-Status $result) -eq 'Success') (Get-Status $result)
Check 'inhibit observes the requested mode' ($result.Observed.ToString() -eq 'Inhibit') $result.Observed
Check 'inhibit writes only 0x05' ($calls.Count -eq 2 -and $calls[0].Value -eq 5 -and $calls[1].Command -eq 1) ('calls=' + $calls.Count)
Check 'no forced discharge write' (@($calls | Where-Object { $_.Value -eq 2 }).Count -eq 0) 'values=0x05'

# Unplugged: safety gate rejects before touching the gateway.
$gateway = New-Gateway
$hp = New-Hp $hpFingerprint $gateway
$result = $requestInhibit.Invoke($hp, @($false))
Check 'unplugged inhibit is refused' ((Get-Status $result) -eq 'NotOnAc') (Get-Status $result)
Check 'unplugged inhibit performs no write' ((Get-Calls $gateway).Count -eq 0) 'calls=0'

# Access denied: a transport failure is reported, not retried forever.
$gateway = New-Gateway
Add-Failure $gateway 'access denied'
$hp = New-Hp $hpFingerprint $gateway
$result = $requestInhibit.Invoke($hp, @($true))
Check 'access denied is reported' ((Get-Status $result) -eq 'WriteFailed') (Get-Status $result)
Check 'access denied stops after one write' ((Get-Calls $gateway).Count -eq 1) ('calls=' + (Get-Calls $gateway).Count)

# Missing provider/class: the simulator has no queued response at all.
$gateway = New-Gateway
$hp = New-Hp $hpFingerprint $gateway
$result = $requestInhibit.Invoke($hp, @($true))
Check 'missing provider response is reported' ((Get-Status $result) -eq 'WriteFailed') (Get-Status $result)
Check 'missing provider performs one failed call' ((Get-Calls $gateway).Count -eq 1) ('calls=' + (Get-Calls $gateway).Count)

# Unexpected/empty read-back: mismatch, then one rollback write.
$gateway = New-Gateway
Add-Ok $gateway 0
Add-Ok $gateway 0
Add-Ok $gateway 0
$hp = New-Hp $hpFingerprint $gateway
$result = $requestInhibit.Invoke($hp, @($true))
$calls = Get-Calls $gateway
Check 'read-back mismatch is reported' ((Get-Status $result) -eq 'ReadbackMismatch') (Get-Status $result)
Check 'mismatch rolls back to auto once' ($calls.Count -eq 3 -and $calls[2].Value -eq 0) ('calls=' + $calls.Count + ' rollback=' + $calls[2].Value)

# Empty read-back: not even a mode byte, still one safe rollback.
$gateway = New-Gateway
Add-Ok $gateway 0
Add-Empty $gateway
Add-Ok $gateway 0
$hp = New-Hp $hpFingerprint $gateway
$result = $requestInhibit.Invoke($hp, @($true))
$calls = Get-Calls $gateway
Check 'empty read-back is reported' ((Get-Status $result) -eq 'ReadbackMismatch') (Get-Status $result)
Check 'empty read-back rolls back once' ($calls.Count -eq 3 -and $calls[2].Value -eq 0) ('calls=' + $calls.Count + ' rollback=' + $calls[2].Value)

# Auto restore: success is confirmed by a read-back.
$gateway = New-Gateway
Add-Ok $gateway 0
Add-Ok $gateway 0
$hp = New-Hp $hpFingerprint $gateway
$result = $requestAuto.Invoke($hp, @($true))
$calls = Get-Calls $gateway
Check 'auto restore succeeds' ((Get-Status $result) -eq 'Success' -and $result.Observed.ToString() -eq 'Auto') (Get-Status $result)
Check 'auto restore writes only 0x00' ($calls.Count -eq 2 -and $calls[0].Value -eq 0) ('calls=' + $calls.Count)

# The factory refuses to promote a candidate profile to a writer.
$create = $types['BatteryControllerFactory'].GetMethods($flagsStatic) |
    Where-Object { $_.Name -eq 'Create' -and $_.GetParameters().Count -eq 1 } |
    Select-Object -First 1
if (-not $create) { throw 'Factory Create(DeviceFingerprint) not found' }
$candidateController = $create.Invoke($null, @($acerFingerprint))
Check 'candidate device stays monitoring-only' (-not [bool]$candidateController.CanControlCharge) 'CanControlCharge=false'
$candidateController.Dispose()

if ($script:failed) { exit 1 }
