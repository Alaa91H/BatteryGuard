<#
.SYNOPSIS
  Read-only inventory for BatteryGuard controller support.

.DESCRIPTION
  Collects the device fingerprint, battery readings, battery/charge-related WMI
  classes and method names, ACPI device prefixes and relevant vendor drivers.
  It never invokes a WMI method, never writes a firmware/EC value and never
  changes BatteryGuard settings. Serial numbers are deliberately omitted.

  The report is intended for a GitHub issue or a hardware-validation request.
  It is a capability inventory, not proof that a write path works.

.PARAMETER OutputPath
  JSON report path. Defaults to controller-probe.json next to this script.
#>
[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot 'controller-probe.json')
)

$ErrorActionPreference = 'Continue'

function Get-FirstValue {
    param($Instance, [string]$Property)
    if ($null -eq $Instance) { return '' }
    try {
        $value = $Instance.$Property
        if ($null -eq $value) { return '' }
        return ([string]$value).Trim()
    }
    catch {
        return ''
    }
}

function Get-Fingerprint {
    $system = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue | Select-Object -First 1
    $board = Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction SilentlyContinue | Select-Object -First 1
    $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue | Select-Object -First 1

    [ordered]@{
        manufacturer   = Get-FirstValue $system 'Manufacturer'
        product        = Get-FirstValue $system 'Model'
        family         = Get-FirstValue $system 'SystemFamily'
        systemSku      = Get-FirstValue $system 'SystemSKUNumber'
        board          = Get-FirstValue $board 'Product'
        biosVersion    = Get-FirstValue $bios 'SMBIOSBIOSVersion'
        biosReleaseDate = Get-FirstValue $bios 'ReleaseDate'
    }
}

function Get-BatterySnapshot {
    try {
        $batteries = @(Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue)
    }
    catch {
        $batteries = @()
    }

    $items = @()
    foreach ($battery in $batteries) {
        $items += [ordered]@{
            name                    = Get-FirstValue $battery 'Name'
            status                  = Get-FirstValue $battery 'BatteryStatus'
            estimatedChargeRemaining = Get-FirstValue $battery 'EstimatedChargeRemaining'
            designCapacity          = Get-FirstValue $battery 'DesignCapacity'
            fullChargeCapacity      = Get-FirstValue $battery 'FullChargeCapacity'
            chemistry               = Get-FirstValue $battery 'Chemistry'
        }
    }

    $wmiStatus = @()
    try {
        foreach ($status in @(Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue)) {
            $wmiStatus += [ordered]@{
                remainingCapacity   = Get-FirstValue $status 'RemainingCapacity'
                fullChargedCapacity = Get-FirstValue $status 'FullChargedCapacity'
                voltage             = Get-FirstValue $status 'Voltage'
                chargeRate          = Get-FirstValue $status 'ChargeRate'
                dischargeRate       = Get-FirstValue $status 'DischargeRate'
                powerOnline         = Get-FirstValue $status 'PowerOnline'
                charging            = Get-FirstValue $status 'Charging'
                discharging         = Get-FirstValue $status 'Discharging'
            }
        }
    }
    catch { }

    [ordered]@{
        batteries = $items
        wmiStatus = $wmiStatus
    }
}

function Get-WmiInventory {
    $patterns = @('*Battery*', '*Charge*', '*BIOS*', '*Bios*', 'hpq*', '*Lenovo*', '*Dell*', '*ASUS*', '*Acer*', '*MSI*')
    $namespaces = @('root\wmi', 'root\dcim\sysman')
    $classes = @{}

    foreach ($namespace in $namespaces) {
        foreach ($pattern in $patterns) {
            try {
                $found = @(Get-CimClass -Namespace $namespace -ClassName $pattern -ErrorAction SilentlyContinue)
            }
            catch {
                $found = @()
            }

            foreach ($class in $found) {
                $name = [string]$class.CimClassName
                if ([string]::IsNullOrEmpty($name) -or $classes.ContainsKey($name)) { continue }

                $methods = @()
                try {
                    $methods = @($class.CimClass.CimClassMethods | ForEach-Object { [string]$_.Name } | Sort-Object -Unique)
                }
                catch { }

                $classes[$name] = [ordered]@{
                    namespace = [string]$class.CimSystemProperties.Namespace
                    name      = $name
                    methods   = $methods
                }
            }
        }
    }

    return @($classes.Values | Sort-Object { $_.name })
}

function Get-AcpiInventory {
    $devices = @()
    try {
        $devices = @(Get-CimInstance -ClassName Win32_PnPEntity -Filter "PNPDeviceID LIKE 'ACPI%'" -ErrorAction SilentlyContinue)
    }
    catch {
        return @()
    }

    $seen = @{}
    $items = @()
    foreach ($device in $devices) {
        $id = Get-FirstValue $device 'PNPDeviceID'
        if ($id -match '^(ACPI\\[^\\]+)') {
            $prefix = $matches[1]
        }
        else {
            continue
        }
        if ($seen.ContainsKey($prefix)) { continue }
        $seen[$prefix] = $true
        $items += [ordered]@{
            acpiId     = $prefix
            name       = Get-FirstValue $device 'Name'
            deviceClass = Get-FirstValue $device 'PNPClass'
        }
    }
    return @($items | Sort-Object { $_.acpiId })
}

function Get-DriverInventory {
    $items = @()
    try {
        $drivers = @(Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction SilentlyContinue |
            Where-Object { $_.DeviceClass -match '^(Battery|Firmware|System)$' })
    }
    catch {
        return @()
    }

    foreach ($driver in $drivers) {
        $items += [ordered]@{
            deviceClass = Get-FirstValue $driver 'DeviceClass'
            deviceName  = Get-FirstValue $driver 'DeviceName'
            driverVersion = Get-FirstValue $driver 'DriverVersion'
            provider    = Get-FirstValue $driver 'DriverProviderName'
        }
    }
    return @($items | Sort-Object { $_.deviceClass + '|' + $_.deviceName } | Select-Object -First 80)
}

$report = [ordered]@{
    schemaVersion = 1
    probe         = 'BatteryGuard controller probe'
    readOnly      = $true
    note          = 'Inventory only. No WMI method, firmware, EC or settings write is performed. Serial numbers are omitted.'
    fingerprint   = Get-Fingerprint
    battery       = Get-BatterySnapshot
    wmiClasses    = @(Get-WmiInventory)
    acpiDevices   = @(Get-AcpiInventory)
    drivers       = @(Get-DriverInventory)
}

try {
    $directory = Split-Path -Parent $OutputPath
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $json = $report | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($OutputPath, $json, (New-Object Text.UTF8Encoding($false)))
    'Report written to ' + $OutputPath
}
catch {
    'Could not write report: ' + $_.Exception.Message
    exit 1
}

$fingerprint = $report.fingerprint
'Device: {0} {1} (BIOS {2})' -f $fingerprint.manufacturer, $fingerprint.product, $fingerprint.biosVersion
'WMI classes collected: {0}' -f @($report.wmiClasses).Count
'ACPI prefixes collected: {0}' -f @($report.acpiDevices).Count
''
'This report is read-only. It does not prove that a charge-write interface exists.'
