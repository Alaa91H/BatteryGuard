<#
.SYNOPSIS
  Captures the Settings, schedule and log windows for visual review.

.DESCRIPTION
  Compiles a small DPI-aware host from the same sources and the real
  application config, then captures the actual window surface without desktop
  edges or the Windows touch keyboard. The host backs up and restores
  interface.ini and theme.ini. No WMI writes, charge-mode changes or elevation
  are used. Generated PNGs match the tests/*.png ignore rule.

  Run through PowerShell 5.1:
    powershell -File battery/tests/VisualCapture.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $compiler)) {
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
}
if (-not (Test-Path $compiler)) { throw 'The .NET Framework compiler was not found.' }

$sources = @(Get-ChildItem -Path (Join-Path $root 'src') -Filter '*.cs' |
    Sort-Object Name | ForEach-Object { $_.FullName })
$hostSource = Join-Path $PSScriptRoot 'VisualCaptureHost.cs'
$manifest = Join-Path $PSScriptRoot 'VisualCaptureHost.manifest'
$appConfig = Join-Path $root 'resources\application.config'
$hostExe = Join-Path $PSScriptRoot 'VisualCaptureHost.exe'
$hostConfig = $hostExe + '.config'

foreach ($file in @($sources + $hostSource + $manifest + $appConfig)) {
    if (-not (Test-Path $file)) { throw "Missing capture input: $file" }
}

$arguments = @(
    '-nologo'
    '-target:exe'
    '-codepage:65001'
    '-main:BatteryGuardTray.VisualCaptureHost'
    ('-win32manifest:' + $manifest)
    ('-out:' + $hostExe)
    '-r:System.dll'
    '-r:System.Drawing.dll'
    '-r:System.Management.dll'
    '-r:System.Web.Extensions.dll'
    '-r:System.Windows.Forms.dll'
) + $sources + $hostSource

try {
    & $compiler @arguments
    if ($LASTEXITCODE -ne 0) { throw "csc failed with exit code $LASTEXITCODE" }
    Copy-Item $appConfig $hostConfig -Force
    & $hostExe $root $PSScriptRoot
    if ($LASTEXITCODE -ne 0) { throw "visual capture host failed with exit code $LASTEXITCODE" }
}
finally {
    Remove-Item $hostExe, $hostConfig -Force -ErrorAction SilentlyContinue
}
