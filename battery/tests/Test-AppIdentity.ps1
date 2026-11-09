<#
.SYNOPSIS
  Checks the Windows notification identity used by BatteryGuard.

.DESCRIPTION
  Compiles the app source, invokes AppIdentity.Install(), and verifies that a
  BatteryGuard Start Menu shortcut exists, launches the PowerShell-hosted app,
  and carries the expected System.AppUserModel.ID. No hardware writes and no
  elevation required.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$root = Split-Path -Parent $PSScriptRoot
$env:BATTERYGUARD_HOME = $root
$env:BATTERYGUARD_HOST = 'ps1'
$env:BATTERYGUARD_ENTRY = Join-Path $root 'scripts\start.ps1'
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

$type = Get-AppType 'AppIdentity'
if (-not $type) { throw 'AppIdentity not found' }
$method = $type.GetMethod('Install', [System.Reflection.BindingFlags]'Public,Static')
if (-not $method) { throw 'AppIdentity.Install not found' }
$script:failed = $false

[void]$method.Invoke($null, $null)

$shortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\BatteryGuard.lnk'
Check 'Start Menu shortcut exists' (Test-Path -LiteralPath $shortcut) $shortcut
if (Test-Path -LiteralPath $shortcut) {
    try {
        $shell = New-Object -ComObject Shell.Application
        $folder = $shell.NameSpace((Split-Path -Parent $shortcut))
        $item = $folder.ParseName((Split-Path -Leaf $shortcut))
        $appId = [string]$item.ExtendedProperty('System.AppUserModel.ID')
        Check 'shortcut AUMID' ($appId -eq 'BatteryGuard.Tray') $appId
    }
    catch {
        Check 'shortcut AUMID' $false $_.Exception.Message
    }

    try {
        $wsh = New-Object -ComObject WScript.Shell
        $link = $wsh.CreateShortcut($shortcut)
        Check 'shortcut target' ($link.TargetPath -like '*powershell.exe') $link.TargetPath
        Check 'shortcut arguments' ($link.Arguments -match 'start\.ps1' -and $link.Arguments -match '-NoElevate') $link.Arguments
        Check 'shortcut description' ($link.Description -eq 'BatteryGuard battery monitor') $link.Description
    }
    catch {
        Check 'shortcut target' $false $_.Exception.Message
    }
}

if ($script:failed) { exit 1 }
