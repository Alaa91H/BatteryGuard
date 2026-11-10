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
    'ControllerCapabilities', 'ControllerResult', 'WmiCallResult', 'SimulatedWmiGateway', 'IWmiGateway',
    'HpBios', 'GenericBatteryController', 'WriteGuard', 'BatteryControllerFactory')
$types = @{}
foreach ($name in $typeNames) {
    $types[$name] = Get-AppType $name
    if (-not $types[$name]) { throw "$name type not found" }
}

$fingerprintType = $types['DeviceFingerprint']
$profileType = $types['DeviceProfile']
$capabilityType = $types['ControllerCapabilities']
$resultType = $types['WmiCallResult']
$controllerResultType = $types['ControllerResult']
$modeType = $types['ChargeMode']
$genericType = $types['GenericBatteryController']

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

# --- real fingerprint sources (read-only WMI) -----------------------------
$readFingerprint = $fingerprintType.GetMethod('Read', $flagsStatic)
if (-not $readFingerprint) { throw 'DeviceFingerprint.Read not found' }
$live = $readFingerprint.Invoke($null, @())
$liveManufacturer = (-not [string]::IsNullOrWhiteSpace($live.Manufacturer)) -and $live.Manufacturer -ne 'Unknown'
Check 'real fingerprint manufacturer' $liveManufacturer $live.Manufacturer
Check 'real fingerprint product' (-not [string]::IsNullOrWhiteSpace($live.Product)) $live.Product
Check 'real fingerprint board' (-not [string]::IsNullOrWhiteSpace($live.Board)) $live.Board
Check 'real fingerprint BIOS version' (-not [string]::IsNullOrWhiteSpace($live.BiosVersion)) $live.BiosVersion
Check 'real fingerprint BIOS release date' (-not [string]::IsNullOrWhiteSpace($live.BiosReleaseDate)) $live.BiosReleaseDate

# --- embedded registry order and write eligibility ------------------------
$catalogType = $types['DeviceProfileCatalog']
$allField = $catalogType.GetField('All', $flagsStatic)
if (-not $allField) { throw 'DeviceProfileCatalog.All not found' }
$allProfiles = @($allField.GetValue($null))
Check 'HP profile is first in the embedded catalog' ($allProfiles.Count -gt 0 -and $allProfiles[0].Vendor -eq 'HP') (($allProfiles | ForEach-Object { $_.Vendor }) -join ',')
$writableProfiles = @($allProfiles | Where-Object { [bool]$profileType.GetProperty('CanWrite').GetValue($_, $null) })
Check 'only the field-verified HP profile can write' ($writableProfiles.Count -eq 1 -and $writableProfiles[0].Vendor -eq 'HP') (($writableProfiles | ForEach-Object { $_.Vendor }) -join ',')
Check 'HP profile names its WMI interface' ($allProfiles[0].Interface -eq 'hpqBIntM') $allProfiles[0].Interface
$providersField = $types['BatteryControllerFactory'].GetField('Providers', $flagsStatic)
if (-not $providersField) { throw 'BatteryControllerFactory.Providers not found' }
$providers = @($providersField.GetValue($null))
Check 'providers are ordered HP then Generic' ($providers.Count -ge 2 -and $providers[0].Name -eq 'HP' -and $providers[1].Name -eq 'Generic') (($providers | ForEach-Object { $_.Name }) -join ',')

# A profile cannot match without an interface and explicit BIOS patterns.
$syntheticMatchProfile = [Activator]::CreateInstance($profileType)
$profileType.GetField('Vendor').SetValue($syntheticMatchProfile, 'Synthetic match')
$profileType.GetField('ManufacturerPatterns').SetValue($syntheticMatchProfile, [string[]]@('HP*'))
$profileType.GetField('ProductPatterns').SetValue($syntheticMatchProfile, [string[]]@('*'))
$biosPatternsField = $profileType.GetField('BiosPatterns')
$interfaceField = $profileType.GetField('Interface')
$biosPatternsField.SetValue($syntheticMatchProfile, [string[]]@('*'))
$interfaceField.SetValue($syntheticMatchProfile, '')
$profileMatches = $profileType.GetMethod('Matches', $flagsInstance)
Check 'profile without interface cannot match' (-not [bool]$profileMatches.Invoke($syntheticMatchProfile, @($hpFingerprint))) 'empty interface'
$interfaceField.SetValue($syntheticMatchProfile, 'synthetic')
$biosPatternsField.SetValue($syntheticMatchProfile, [string[]]@())
Check 'profile without BIOS patterns cannot match' (-not [bool]$profileMatches.Invoke($syntheticMatchProfile, @($hpFingerprint))) 'empty BIOS patterns'
$biosPatternsField.SetValue($syntheticMatchProfile, [string[]]@('*'))
Check 'profile with interface and BIOS patterns matches' ([bool]$profileMatches.Invoke($syntheticMatchProfile, @($hpFingerprint))) 'synthetic interface'

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

function Add-Reject([object]$gateway) {
    $response = $okMethod.Invoke($null, @([uint32]0xFFFF, [byte[]]@(0)))
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

# --- single write gate and numeric limit gate -----------------------------
$hpCapabilities = $profileType.GetField('Capabilities').GetValue($hpProfile)
$apply = $types['WriteGuard'].GetMethod('Apply', $flagsStatic)
if (-not $apply) { throw 'WriteGuard.Apply not found' }
$result = $apply.Invoke($null, [object[]]@($hpCapabilities, $true, $forceMode, $null, $null, $null))
Check 'forced discharge is rejected by the write gate' ((Get-Status $result) -eq 'Rejected') (Get-Status $result)

$applyLimit = $types['WriteGuard'].GetMethod('ApplyLimit', $flagsStatic)
if (-not $applyLimit) { throw 'WriteGuard.ApplyLimit not found' }
$fixedCapabilities = $capabilityType.GetMethod('FixedThreshold', $flagsStatic).Invoke($null, @(80))
$writeTrue = [System.Func[bool]] { return $true }
$rollback = [System.Action] { $script:rolledBack = $true }
$result = $applyLimit.Invoke($null, [object[]]@($fixedCapabilities, $true, [int]90, $null, $null, $null))
Check 'limit gate rejects a value outside a fixed 80% capability' ((Get-Status $result) -eq 'Rejected') (Get-Status $result)
$read80 = [System.Func[int]] { return 80 }
$result = $applyLimit.Invoke($null, [object[]]@($fixedCapabilities, $true, [int]80, $writeTrue, $read80, $rollback))
Check 'limit gate accepts the exact fixed limit' ((Get-Status $result) -eq 'Success') (Get-Status $result)
$observedPercent = [int]$result.GetType().GetField('ObservedPercent').GetValue($result)
Check 'limit gate reports the observed percentage' ($observedPercent -eq 80) ([string]$observedPercent)
$result = $applyLimit.Invoke($null, [object[]]@($fixedCapabilities, $false, [int]80, $null, $null, $null))
Check 'limit gate refuses AC loss' ((Get-Status $result) -eq 'NotOnAc') (Get-Status $result)
$read75 = [System.Func[int]] { return 75 }
$script:rolledBack = $false
$result = $applyLimit.Invoke($null, [object[]]@($fixedCapabilities, $true, [int]80, $writeTrue, $read75, $rollback))
Check 'limit read-back mismatch is reported' ((Get-Status $result) -eq 'ReadbackMismatch') (Get-Status $result)
Check 'limit read-back mismatch rolls back' ($script:rolledBack) 'rollback called'
$startStopCapabilitiesForGate = $capabilityType.GetMethod('StartStopThreshold', $flagsStatic).Invoke($null, @(50, 100, 80))
$result = $applyLimit.Invoke($null, [object[]]@($startStopCapabilitiesForGate, $true, [int]45, $null, $null, $null))
Check 'start-stop limit gate rejects 45' ((Get-Status $result) -eq 'Rejected') (Get-Status $result)
$read50 = [System.Func[int]] { return 50 }
$result = $applyLimit.Invoke($null, [object[]]@($startStopCapabilitiesForGate, $true, [int]50, $writeTrue, $read50, $rollback))
Check 'start-stop limit gate accepts 50' ((Get-Status $result) -eq 'Success') (Get-Status $result)
$result = $applyLimit.Invoke($null, [object[]]@($monitoring, $true, [int]80, $null, $null, $null))
Check 'limit gate rejects monitoring-only capability' ((Get-Status $result) -eq 'Unsupported') (Get-Status $result)

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
$requestLimit = $types['HpBios'].GetMethod('RequestLimit', $flagsInstance)
if (-not $requestLimit) { throw 'HpBios.RequestLimit not found' }
$result = $requestLimit.Invoke($hp, @([int]80))
Check 'HP percentage limit is unsupported' ((Get-Status $result) -eq 'Unsupported') (Get-Status $result)
Check 'HP percentage limit performs no write' ((Get-Calls $gateway).Count -eq 2) ('calls=' + (Get-Calls $gateway).Count)

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

# An unexpected mode byte must not be treated as success.
$gateway = New-Gateway
Add-Ok $gateway 0
Add-Ok $gateway 255
Add-Ok $gateway 0
$hp = New-Hp $hpFingerprint $gateway
$result = $requestInhibit.Invoke($hp, @($true))
$calls = Get-Calls $gateway
Check 'unexpected read byte is reported' ((Get-Status $result) -eq 'ReadbackMismatch') (Get-Status $result)
Check 'unexpected read byte rolls back once' ($calls.Count -eq 3 -and $calls[2].Value -eq 0) ('calls=' + $calls.Count + ' rollback=' + $calls[2].Value)

# Auto restore: success is confirmed by a read-back.
$gateway = New-Gateway
Add-Ok $gateway 0
Add-Ok $gateway 0
$hp = New-Hp $hpFingerprint $gateway
$result = $requestAuto.Invoke($hp, @($true))
$calls = Get-Calls $gateway
Check 'auto restore succeeds' ((Get-Status $result) -eq 'Success' -and $result.Observed.ToString() -eq 'Auto') (Get-Status $result)
Check 'auto restore writes only 0x00' ($calls.Count -eq 2 -and $calls[0].Value -eq 0) ('calls=' + $calls.Count)

# Auto fallback: 0x2b rejected, 0x1f accepted, still only 0x00.
$gateway = New-Gateway
Add-Reject $gateway
Add-Ok $gateway 0
Add-Ok $gateway 0
$hp = New-Hp $hpFingerprint $gateway
$result = $requestAuto.Invoke($hp, @($true))
$calls = Get-Calls $gateway
Check 'auto restore falls back to 0x1f' ((Get-Status $result) -eq 'Success') (Get-Status $result)
Check 'auto fallback writes only 0x00' ($calls.Count -eq 3 -and $calls[0].Value -eq 0 -and $calls[1].Value -eq 0 -and $calls[0].CommandType -eq 0x2b -and $calls[1].CommandType -eq 0x1f) ('calls=' + $calls.Count)

# Low-level allowlist: even the legacy writer cannot emit 0x02 or an unknown type.
$writeMode = $types['HpBios'].GetMethod('WriteMode', $flagsInstance)
if (-not $writeMode) { throw 'HpBios.WriteMode not found' }
$gateway = New-Gateway
$hp = New-Hp $hpFingerprint $gateway
$args = [object[]]@([uint32]0x2b, [byte]2, [uint32]0)
$applied = [bool]$writeMode.Invoke($hp, $args)
$blocked = (-not $applied) -and ((Get-Calls $gateway).Count -eq 0)
Check 'low-level gate blocks forced discharge byte' $blocked ($args[2].ToString())
$args = [object[]]@([uint32]0x99, [byte]0, [uint32]0)
$applied = [bool]$writeMode.Invoke($hp, $args)
$blocked = (-not $applied) -and ((Get-Calls $gateway).Count -eq 0)
Check 'low-level gate blocks an unknown command type' $blocked ($args[2].ToString())
$args = [object[]]@([uint32]0x1f, [byte]5, [uint32]0)
$applied = [bool]$writeMode.Invoke($hp, $args)
$blocked = (-not $applied) -and ((Get-Calls $gateway).Count -eq 0)
Check 'low-level gate blocks inhibit on the fallback command' $blocked ($args[2].ToString())
$gateway = New-Gateway
Add-Ok $gateway 0
$hp = New-Hp $hpFingerprint $gateway
$args = [object[]]@([uint32]0x2b, [byte]5, [uint32]0)
$applied = [bool]$writeMode.Invoke($hp, $args)
$calls = Get-Calls $gateway
$allowed = $applied -and $calls.Count -eq 1 -and $calls[0].Value -eq 5
Check 'low-level gate allows inhibit 0x05' $allowed ('calls=' + $calls.Count)

# The factory refuses to promote a candidate profile to a writer.
$create = $types['BatteryControllerFactory'].GetMethods($flagsStatic) |
    Where-Object { $_.Name -eq 'Create' -and $_.GetParameters().Count -eq 1 } |
    Select-Object -First 1
if (-not $create) { throw 'Factory Create(DeviceFingerprint) not found' }
$candidateController = $create.Invoke($null, @($acerFingerprint))
Check 'candidate device stays monitoring-only' (-not [bool]$candidateController.CanControlCharge) 'CanControlCharge=false'
$candidateController.Dispose()

# A provider construction failure must fall back to monitoring, never crash.
$env:BATTERYGUARD_TEST_WMI = 'missing'
try {
    $fallbackController = $create.Invoke($null, @($hpFingerprint))
    Check 'missing HP provider class falls back to monitoring' (-not [bool]$fallbackController.CanControlCharge) 'CanControlCharge=false'
    Check 'missing HP provider class is monitoring capability' ($fallbackController.Capabilities.Key -eq 'monitoring') $fallbackController.Capabilities.Key
    $fallbackController.Dispose()
}
finally {
    Remove-Item Env:BATTERYGUARD_TEST_WMI -ErrorAction SilentlyContinue
}

# Every generic request is unsupported and cannot reach a write path.
$genericCtor = $genericType.GetConstructor($flagsInstance, $null, [Type[]]@($fingerprintType, $profileType), $null)
if (-not $genericCtor) { throw 'GenericBatteryController constructor not found' }
$genericController = $genericCtor.Invoke([object[]]@($acerFingerprint, $acerProfile))
try {
    $genericAuto = $genericType.GetMethod('RequestAuto', $flagsInstance)
    $genericInhibit = $genericType.GetMethod('RequestInhibit', $flagsInstance)
    $genericLimit = $genericType.GetMethod('RequestLimit', $flagsInstance)
    if (-not $genericAuto -or -not $genericInhibit -or -not $genericLimit) { throw 'Generic Request methods not found' }
    $result = $genericAuto.Invoke($genericController, @($true))
    Check 'generic auto request is unsupported' ((Get-Status $result) -eq 'Unsupported') (Get-Status $result)
    $result = $genericInhibit.Invoke($genericController, @($true))
    Check 'generic inhibit request is unsupported' ((Get-Status $result) -eq 'Unsupported') (Get-Status $result)
    $result = $genericLimit.Invoke($genericController, @([int]80))
    Check 'generic limit request is unsupported' ((Get-Status $result) -eq 'Unsupported') (Get-Status $result)
    Check 'generic controller cannot control charge' (-not [bool]$genericType.GetProperty('CanControlCharge', $flagsInstance).GetValue($genericController, $null)) 'CanControlCharge=false'
}
finally {
    $genericController.Dispose()
}

# Static safety scan: source may not gain a firmware/EC writer or a loader.
$sourceText = (Get-ChildItem -Path (Join-Path $root 'src') -Filter '*.cs' |
    ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
$writeApis = $sourceText -match '(?i)SetFirmwareEnvironmentVariable|NtSetSystemEnvironmentValue|PhysicalMemory|WinRing0|Out32|WritePort'
Check 'source has no UEFI/NVRAM/EC/ACPI write API' (-not $writeApis) 'static scan'
$loaderApis = $sourceText -match '(?i)Assembly\.LoadFrom|Assembly\.LoadFile|WebClient|HttpClient|DownloadString|WebRequest'
Check 'source has no dynamic plugin or network loader' (-not $loaderApis) 'static scan'

if ($script:failed) { exit 1 }
