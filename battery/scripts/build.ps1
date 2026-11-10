<#
.SYNOPSIS
  Builds application.exe with the .NET Framework compiler that ships with Windows.

.DESCRIPTION
  Uses the same flags as the documented manual command, fails on compiler errors,
  and prints the resulting executable size. No elevation and no external packages.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $compiler)) {
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
}
if (-not (Test-Path $compiler)) {
    throw 'The .NET Framework 4.x C# compiler (csc.exe) was not found.'
}

$sources = @(Get-ChildItem -Path (Join-Path $root 'src') -Filter '*.cs' | Sort-Object Name | ForEach-Object { $_.FullName })
$output = Join-Path $root 'application.exe'
$manifest = Join-Path $root 'resources\application.manifest'
$appConfig = Join-Path $root 'resources\application.config'
$icon = Join-Path $root 'resources\application.ico'

foreach ($file in @($sources + $manifest + $appConfig + $icon)) {
    if (-not (Test-Path $file)) { throw "Missing build input: $file" }
}

$arguments = @(
    '-nologo'
    '-target:winexe'
    '-platform:anycpu'
    '-optimize+'
    '-codepage:65001'
    '-win32manifest:' + $manifest
    '-win32icon:' + $icon
    '-out:' + $output
    '-r:System.dll'
    '-r:System.Drawing.dll'
    '-r:System.Management.dll'
    '-r:System.Web.Extensions.dll'
    '-r:System.Windows.Forms.dll'
) + $sources

& $compiler @arguments
if ($LASTEXITCODE -ne 0) {
    throw "csc failed with exit code $LASTEXITCODE"
}

Copy-Item $appConfig ($output + '.config') -Force
$file = Get-Item $output
'built {0} ({1:N0} bytes)' -f $file.FullName, $file.Length
'config {0}' -f ($output + '.config')
