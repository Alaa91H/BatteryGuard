<#
.SYNOPSIS
  Verifies the tray popup menu shows charge time next to the active limit.

.DESCRIPTION
  Compiles the app source, builds the real Win32 popup menu with a synthetic
  charging state, and reads its item labels. The test covers a 60% limit at
  50% charge (24 minutes), the exact limit (no time left), standard charging
  to 100% (2 hours), and the Language submenu above Appearance. It also checks
  that a manual language selection is saved to a temporary interface.ini. A
  synthetic Acer candidate controller verifies that a non-HP device shows
  Monitoring only in both the tray menu and Settings, and that Settings does
  not attach a 50-100% threshold slider. A synthetic writable fixed-80%
  profile verifies the future capability-only card; no writer is enabled. No
  menu is shown, no hardware is written, no real settings are changed and no
  elevation is required.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$root = Split-Path -Parent $PSScriptRoot
$sources = @(Get-ChildItem -Path (Join-Path $root 'src') -Filter '*.cs' | Sort-Object Name | ForEach-Object { $_.FullName })
Add-Type -Path $sources -ReferencedAssemblies 'System.dll', 'System.Drawing.dll', 'System.Management.dll', 'System.Web.Extensions.dll', 'System.Windows.Forms.dll'

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class TrayMenuProbe
{
    [DllImport("user32.dll")]
    public static extern int GetMenuItemCount(IntPtr hMenu);

    [DllImport("user32.dll")]
    public static extern IntPtr GetSubMenu(IntPtr hMenu, int nPos);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "GetMenuStringW")]
    public static extern int GetMenuString(IntPtr hMenu, uint uIDItem, StringBuilder lpString, int nMaxCount, uint uFlag);

    [DllImport("user32.dll")]
    public static extern bool DestroyMenu(IntPtr hMenu);
}
'@

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

function Get-MenuLabels([IntPtr]$menu) {
    $count = [TrayMenuProbe]::GetMenuItemCount($menu)
    if ($count -lt 0) { throw 'GetMenuItemCount failed' }

    $labels = @()
    for ($i = 0; $i -lt $count; $i++) {
        $buffer = New-Object System.Text.StringBuilder 512
        $length = [TrayMenuProbe]::GetMenuString($menu, [uint32]$i, $buffer, $buffer.Capacity, [uint32]0x400)
        if ($length -gt 0) { $labels += $buffer.ToString() }
    }
    return $labels
}

function Get-MenuPosition([IntPtr]$menu, [string]$text) {
    $count = [TrayMenuProbe]::GetMenuItemCount($menu)
    for ($i = 0; $i -lt $count; $i++) {
        $buffer = New-Object System.Text.StringBuilder 512
        [void][TrayMenuProbe]::GetMenuString($menu, [uint32]$i, $buffer, $buffer.Capacity, [uint32]0x400)
        if ($buffer.ToString() -eq $text) { return $i }
    }
    return -1
}

function Test-InterfaceLine([string]$path, [string]$expected) {
    if (-not (Test-Path $path)) { return $false }
    return @(Get-Content $path | Where-Object { $_ -eq $expected }).Count -gt 0
}

function Find-NamedControl($parent, [string]$name) {
    if ($null -eq $parent) { return $null }
    foreach ($child in $parent.Controls) {
        if ($child.Name -eq $name) { return $child }
        $found = Find-NamedControl $child $name
        if ($found) { return $found }
    }
    return $null
}

$flags = [System.Reflection.BindingFlags]'Public,NonPublic,Instance'
$trayType = Get-AppType 'TrayApp'
$engineType = Get-AppType 'Engine'
$policyType = Get-AppType 'Policy'
$locType = Get-AppType 'Loc'
$controllerType = Get-AppType 'IChargeController'
$genericType = Get-AppType 'GenericBatteryController'
$fingerprintType = Get-AppType 'DeviceFingerprint'
$profileCatalogType = Get-AppType 'DeviceProfileCatalog'
$profileType = Get-AppType 'DeviceProfile'
$capabilityType = Get-AppType 'ControllerCapabilities'
$supportStatusType = Get-AppType 'DeviceSupportStatus'
if (-not $trayType -or -not $engineType -or -not $policyType -or -not $locType -or
    -not $controllerType -or -not $genericType -or -not $fingerprintType -or
    -not $profileCatalogType -or -not $profileType -or -not $capabilityType -or -not $supportStatusType) {
    throw 'Tray menu test types not found'
}

$trayCtor = $trayType.GetConstructor($flags, $null, [Type[]]@(), $null)
$policyCtor = $policyType.GetConstructor($flags, $null, [Type[]]@(), $null)
if (-not $trayCtor -or -not $policyCtor) { throw 'Tray menu constructors not found' }

$locType.GetMethod('Load', [System.Reflection.BindingFlags]'Public,Static').Invoke($null, @('en'))
$uiType = Get-AppType 'UiSettings'
$allField = $locType.GetField('All', [System.Reflection.BindingFlags]'Public,Static')
if (-not $uiType -or -not $allField) { throw 'language test types not found' }
$localeCount = @($allField.GetValue($null)).Count

$tempHome = Join-Path ([IO.Path]::GetTempPath()) ('batteryguard-menu-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempHome | Out-Null
$env:BATTERYGUARD_HOME = $tempHome

$middot = [char]0x00B7
$approx = [char]0x2248
$emdash = [char]0x2014
$expectedLimit = 'Limit 60% ' + $middot + ' Resume 55% ' + $middot + ' ' + $approx + ' 24 min'
$expectedStandardLimit = 'Standard charging ' + $emdash + ' no limit'
$expectedFull = 'Until full ' + $approx + ' 2 h'
$script:failed = $false

$tray = $null
try {
    $tray = $trayCtor.Invoke($null)
    $engine = $trayType.GetField('_engine', $flags).GetValue($tray)
    $buildMenu = $trayType.GetMethod('BuildPopupMenu', $flags)
    $setLanguage = $trayType.GetMethod('SetLanguage', $flags)
    if (-not $buildMenu -or -not $setLanguage) { throw 'Tray menu language methods not found' }

    $policy = $policyCtor.Invoke($null)
    $policyType.GetField('Auto').SetValue($policy, $false)
    $policyType.GetField('Ceiling').SetValue($policy, 60)
    $policyType.GetField('Resume').SetValue($policy, 55)
    $engineType.GetField('Current').SetValue($engine, $policy)
    $engineType.GetField('Charging').SetValue($engine, $true)
    $engineType.GetField('Discharging').SetValue($engine, $false)
    $engineType.GetField('ChargeRate').SetValue($engine, 10000)
    $engineType.GetField('DischargeRate').SetValue($engine, 0)
    $engineType.GetField('FullCharged').SetValue($engine, 40000)
    $engineType.GetField('Remaining').SetValue($engine, 20000)
    $engineType.GetField('Percent').SetValue($engine, 50)
    $engineType.GetField('OnAc').SetValue($engine, $true)
    $engineType.GetField('Health').SetValue($engine, 80)
    $engineType.GetField('Designed').SetValue($engine, 51000)
    $engineType.GetField('Voltage').SetValue($engine, 11800)
    $engineType.GetField('FloatActive').SetValue($engine, $false)

    $menu = $buildMenu.Invoke($tray, $null)
    try {
        $labels = @(Get-MenuLabels $menu)
        $languagePosition = Get-MenuPosition $menu 'Language'
        $appearancePosition = Get-MenuPosition $menu 'Appearance'
        $languageMenu = if ($languagePosition -ge 0) { [TrayMenuProbe]::GetSubMenu($menu, $languagePosition) } else { [IntPtr]::Zero }
        $languageLabels = if ($languageMenu -ne [IntPtr]::Zero) { @(Get-MenuLabels $languageMenu) } else { @() }
    }
    finally {
        [void][TrayMenuProbe]::DestroyMenu($menu)
    }

    '--- limited charge: 50% -> 60% ---'
    $labels | ForEach-Object { '  menu: ' + $_ }
    $limitLines = @($labels | Where-Object { $_ -like 'Limit 60%*' })
    Check 'one limited-charge line' ($limitLines.Count -eq 1) ('count=' + $limitLines.Count)
    Check 'time is next to the limit' ($limitLines.Count -eq 1 -and $limitLines[0] -eq $expectedLimit) $limitLines[0]
    Check 'no separate full estimate' (-not ($labels -contains $expectedFull)) $expectedFull
    Check 'language menu above appearance' ($languagePosition -ge 0 -and $appearancePosition -eq ($languagePosition + 1)) ('language=' + $languagePosition + ' appearance=' + $appearancePosition)
    Check 'language submenu exists' ($languageMenu -ne [IntPtr]::Zero) 'language submenu'
    Check 'language submenu has automatic and all languages' ($languageLabels.Count -eq ($localeCount + 1)) ('count=' + $languageLabels.Count + ' expected=' + ($localeCount + 1))
    Check 'automatic language is first' ($languageLabels.Count -gt 0 -and $languageLabels[0] -eq 'Automatic (system)') $languageLabels[0]
    Check 'English is in the language menu' ($languageLabels -contains 'English') 'English'

    $engineType.GetField('Remaining').SetValue($engine, 24000)
    $engineType.GetField('Percent').SetValue($engine, 60)
    $menu = $buildMenu.Invoke($tray, $null)
    try {
        $atLimitLabels = @(Get-MenuLabels $menu)
    }
    finally {
        [void][TrayMenuProbe]::DestroyMenu($menu)
    }

    '--- reached limit: 60% -> 60% ---'
    $atLimitLine = @($atLimitLabels | Where-Object { $_ -like 'Limit 60%*' })
    Check 'at-limit line has no stale time' ($atLimitLine.Count -eq 1 -and $atLimitLine[0] -eq ('Limit 60% ' + $middot + ' Resume 55%')) $atLimitLine[0]

    $policyType.GetField('Auto').SetValue($policy, $true)
    $policyType.GetField('Ceiling').SetValue($policy, 0)
    $policyType.GetField('Resume').SetValue($policy, 0)
    $engineType.GetField('Remaining').SetValue($engine, 20000)
    $engineType.GetField('Percent').SetValue($engine, 50)
    $menu = $buildMenu.Invoke($tray, $null)
    try {
        $standardLabels = @(Get-MenuLabels $menu)
    }
    finally {
        [void][TrayMenuProbe]::DestroyMenu($menu)
    }

    '--- standard charging: 50% -> 100% ---'
    Check 'standard limit line' ($standardLabels -contains $expectedStandardLimit) $expectedStandardLimit
    Check 'standard full estimate' ($standardLabels -contains $expectedFull) $expectedFull
    $numberedLimits = @($standardLabels | Where-Object { $_ -like 'Limit *' })
    Check 'standard has no numbered limit' ($numberedLimits.Count -eq 0) ('count=' + $numberedLimits.Count)

    $setLanguage.Invoke($tray, @('en'))
    $interfacePath = Join-Path $tempHome 'interface.ini'
    $savedLanguage = $uiType.GetField('Language', [System.Reflection.BindingFlags]'Public,Static').GetValue($null)
    Check 'manual language updates runtime' ($savedLanguage -eq 'en') $savedLanguage
    Check 'manual language persists' (Test-InterfaceLine $interfacePath 'language=en') $interfacePath

    $setLanguage.Invoke($tray, @('auto'))
    $savedLanguage = $uiType.GetField('Language', [System.Reflection.BindingFlags]'Public,Static').GetValue($null)
    Check 'automatic language persists' ($savedLanguage -eq 'auto' -and (Test-InterfaceLine $interfacePath 'language=auto')) $interfacePath

    # Non-HP capability path: a candidate profile must not offer a threshold.
    $acerFingerprint = [Activator]::CreateInstance($fingerprintType)
    $fingerprintType.GetField('Manufacturer').SetValue($acerFingerprint, 'Acer')
    $fingerprintType.GetField('Product').SetValue($acerFingerprint, 'Nitro AN515-57')
    $fingerprintType.GetField('BiosVersion').SetValue($acerFingerprint, 'V1.22')
    $acerProfile = $profileCatalogType.GetMethod('Match', [System.Reflection.BindingFlags]'Public,Static').Invoke($null, @($acerFingerprint))
    $deviceInfoType = Get-AppType 'DeviceInfo'
    $settingsType = Get-AppType 'SettingsForm'
    $genericCtor = $genericType.GetConstructor($flags, $null, [Type[]]@($fingerprintType, $profileType), $null)
    $engineInjectedCtor = $engineType.GetConstructor($flags, $null, [Type[]]@($controllerType), $null)
    $trayInjectedCtor = $trayType.GetConstructor($flags, $null, [Type[]]@($engineType), $null)
    if (-not $acerProfile -or -not $genericCtor -or -not $engineInjectedCtor -or -not $trayInjectedCtor) {
        throw 'Non-HP capability test constructors not found'
    }

    $candidateController = $genericCtor.Invoke([object[]]@($acerFingerprint, $acerProfile))
    $candidateEngine = $engineInjectedCtor.Invoke([object[]]@($candidateController))
    $candidateTray = $trayInjectedCtor.Invoke([object[]]@($candidateEngine))
    try {
        $engineType.GetField('Percent').SetValue($candidateEngine, 59)
        $engineType.GetField('OnAc').SetValue($candidateEngine, $false)
        $engineType.GetField('FullCharged').SetValue($candidateEngine, 40000)
        $engineType.GetField('Health').SetValue($candidateEngine, 80)
        $engineType.GetField('Designed').SetValue($candidateEngine, 51000)
        $candidateMenu = $buildMenu.Invoke($candidateTray, $null)
        try {
            $candidateLabels = @(Get-MenuLabels $candidateMenu)
        }
        finally {
            [void][TrayMenuProbe]::DestroyMenu($candidateMenu)
        }

        $candidateText = [string]$engineType.GetMethod('CapabilityText', $flags).Invoke($candidateEngine, $null)
        '--- candidate Acer capability ---'
        '  capability: ' + $candidateText
        $candidateLabels | ForEach-Object { '  menu: ' + $_ }
        Check 'candidate profile reports monitoring only' ($candidateText -eq 'Monitoring only') $candidateText
        Check 'candidate menu has monitoring label' ($candidateLabels -contains 'Monitoring only') 'Monitoring only'
        Check 'candidate menu offers no threshold' ($candidateLabels -notcontains 'Charge limit 80%' -and @($candidateLabels | Where-Object { $_ -like 'Limit *' }).Count -eq 0) 'no Limit item'
    }
    finally {
        $candidateTray.Dispose()
    }

    # Settings uses the same capability gate: hide the generic slider entirely.
    $staticFlags = [System.Reflection.BindingFlags]'NonPublic,Static'
    $deviceInfoType.GetField('_fingerprint', $staticFlags).SetValue($null, $acerFingerprint)
    $deviceInfoType.GetField('_loaded', $staticFlags).SetValue($null, $true)
    $settingsNotify = [System.Action[string, string, System.UInt32]] { param($title, $text, $flags) }
    $settingsCtor = $settingsType.GetConstructor($flags, $null, [Type[]]@([string], [System.Action[string, string, System.UInt32]]), $null)
    if (-not $settingsCtor) { throw 'Settings constructor not found' }
    $settings = $settingsCtor.Invoke([object[]]@([string](Join-Path $tempHome 'settings.json'), $settingsNotify))
    try {
        $settingsLimit = $settingsType.GetField('_limitEnabled', $flags).GetValue($settings)
        $settingsSlider = $settingsType.GetField('_slider', $flags).GetValue($settings)
        $settingsBattery = $settingsType.GetField('_batteryInfo', $flags).GetValue($settings)
        $canControl = [bool]$settingsType.GetField('_canControl', $flags).GetValue($settings)
        '--- candidate Acer settings ---'
        '  battery: ' + $settingsBattery.Text
        Check 'candidate settings can control charge' (-not $canControl) 'false'
        Check 'candidate settings hides limit slider' ($settingsSlider.Parent -eq $null) 'no slider parent'
        Check 'candidate settings hides limit checkbox' ($settingsLimit.Parent -eq $null) 'no checkbox parent'
        Check 'candidate settings reports monitoring only' ($settingsBattery.Text -like '*Monitoring only*') $settingsBattery.Text
    }
    finally {
        $settings.Dispose()
    }

    # Future fixed-threshold provider: capability-only card, never a 50-100% slider.
    $fixedCapabilities = $capabilityType.GetMethod('FixedThreshold', [System.Reflection.BindingFlags]'Public,Static').Invoke($null, @(80))
    $fixedProfile = [Activator]::CreateInstance($profileType)
    $profileType.GetField('Vendor').SetValue($fixedProfile, 'Synthetic fixed')
    $profileType.GetField('ManufacturerPatterns').SetValue($fixedProfile, [string[]]@('Synthetic*'))
    $profileType.GetField('ProductPatterns').SetValue($fixedProfile, [string[]]@('*'))
    $profileType.GetField('BiosPatterns').SetValue($fixedProfile, [string[]]@('*'))
    $profileType.GetField('Interface').SetValue($fixedProfile, 'synthetic')
    $profileType.GetField('Capabilities').SetValue($fixedProfile, $fixedCapabilities)
    $profileType.GetField('Status').SetValue($fixedProfile, [Enum]::Parse($supportStatusType, 'LabVerified'))
    $profileType.GetField('Evidence').SetValue($fixedProfile, 'synthetic test only')
    $fixedCtor = $settingsType.GetConstructor($flags, $null,
        [Type[]]@([string], [System.Action[string, string, System.UInt32]], $profileType), $null)
    if (-not $fixedCtor) { throw 'Fixed Settings constructor not found' }
    $fixedSettings = $fixedCtor.Invoke([object[]]@([string](Join-Path $tempHome 'fixed-settings.json'), $settingsNotify, $fixedProfile))
    try {
        $fixedSlider = $settingsType.GetField('_slider', $flags).GetValue($fixedSettings)
        $fixedLimit = $settingsType.GetField('_limitEnabled', $flags).GetValue($fixedSettings)
        $fixedFull = [bool]$settingsType.GetField('_fullControl', $flags).GetValue($fixedSettings)
        $fixedLabel = Find-NamedControl $fixedSettings 'ChargeCapabilityOnly'
        '--- synthetic fixed-80 capability ---'
        '  label: ' + $(if ($fixedLabel) { $fixedLabel.Text } else { '<missing>' })
        Check 'fixed profile is writable in the synthetic test' ([bool]$settingsType.GetField('_canControl', $flags).GetValue($fixedSettings)) 'true'
        Check 'fixed profile does not get full slider' (-not $fixedFull) 'fullControl=false'
        Check 'fixed profile hides the generic slider' ($fixedSlider.Parent -eq $null) 'no slider parent'
        Check 'fixed profile hides the generic limit checkbox' ($fixedLimit.Parent -eq $null) 'no checkbox parent'
        Check 'fixed profile shows capability-only label' ($fixedLabel -and $fixedLabel.Text -eq 'Charge limit 80%') 'Charge limit 80%'
    }
    finally {
        $fixedSettings.Dispose()
    }
}
finally {
    if ($tray) { $tray.Dispose() }
    Remove-Item $tempHome -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:failed) { exit 1 }
