<#
.SYNOPSIS
  Checks automatic log rotation without touching the real log.

.DESCRIPTION
  Points BATTERYGUARD_HOME at a temporary folder, lowers Program.MaxLogBytes,
  writes enough lines through Program.Log() to force rotations, and verifies
  that application.log restarted and application.previous.log holds the old
  content. Cleans up afterwards.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ('bg-rotate-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
$previousHome = $env:BATTERYGUARD_HOME
$env:BATTERYGUARD_HOME = $temp

try {
    $sources = @(Get-ChildItem -Path (Join-Path $root 'src') -Filter '*.cs' | Sort-Object Name | ForEach-Object { $_.FullName })
    Add-Type -Path $sources -ReferencedAssemblies 'System.dll', 'System.Drawing.dll', 'System.Management.dll', 'System.Web.Extensions.dll', 'System.Windows.Forms.dll'

    $programType = $null
    foreach ($assembly in [AppDomain]::CurrentDomain.GetAssemblies()) {
        $candidate = $assembly.GetType('BatteryGuardTray.Program', $false)
        if ($candidate) { $programType = $candidate; break }
    }
    if (-not $programType) { throw 'Program type not found' }

    $programType.GetField('MaxLogBytes', [System.Reflection.BindingFlags]'NonPublic,Static').SetValue($null, [long]300)
    $logMethod = $programType.GetMethod('Log', [System.Reflection.BindingFlags]'NonPublic,Static')

    1..12 | ForEach-Object { $logMethod.Invoke($null, @("rotation probe line $_")) }

    $main = Join-Path $temp 'application.log'
    $archive = Join-Path $temp 'application.previous.log'

    'main exists    = {0}' -f (Test-Path $main)
    'archive exists = {0}' -f (Test-Path $archive)
    if (Test-Path $main) {
        'main lines     = {0}' -f (Get-Content $main).Count
        'main bytes     = {0}' -f (Get-Item $main).Length
    }
    if (Test-Path $archive) {
        $archived = Get-Content $archive
        'archive lines  = {0}' -f $archived.Count
        'archive kept old content = {0}' -f [bool]($archived -match 'rotation probe line 1$')
    }
} finally {
    $env:BATTERYGUARD_HOME = $previousHome
    Remove-Item -Path $temp -Recurse -Force -ErrorAction SilentlyContinue
}
