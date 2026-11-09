#Requires -Version 5.1
<#
.SYNOPSIS
    Exports a WSL distribution to a portable tar archive (full backup).

.DESCRIPTION
    Produces a complete image of the distro: packages, /home, Docker volumes,
    systemd units and configuration. Restore with:

        wsl --import <NewName> <InstallDir> <Archive> --version 2

.PARAMETER Distro
    Distribution to export (default Ubuntu-24.04).

.PARAMETER Path
    Output file. Defaults to .\exports\<distro>-<timestamp>.tar

.PARAMETER Vhd
    Export the raw ext4.vhdx instead of a tar (faster, larger, less portable).

.PARAMETER StopFirst
    Terminate the distro before exporting for a consistent snapshot.

.PARAMETER Force
    Overwrite an existing archive.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\windows\Export-Wsl.ps1 -StopFirst
#>
[CmdletBinding()]
param(
    [string]$Distro = 'Ubuntu-24.04',
    [string]$Path,
    [switch]$Vhd,
    [switch]$StopFirst,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$script:Root = Split-Path -Parent $PSScriptRoot

function Write-Step { param([string]$Message) Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-Ok { param([string]$Message) Write-Host "  [ok]   $Message" -ForegroundColor Green }
function Write-Warn2 { param([string]$Message) Write-Host "  [warn] $Message" -ForegroundColor Yellow }

$raw = & wsl.exe --list --quiet 2>$null
$distros = @($raw | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
if ($distros -notcontains $Distro) {
    throw "$Distro is not installed."
}

if (-not $Path) {
    $extension = if ($Vhd) { '.vhdx' } else { '.tar' }
    $exportDir = Join-Path $script:Root 'exports'
    if (-not (Test-Path $exportDir)) {
        New-Item -ItemType Directory -Path $exportDir | Out-Null
    }
    $Path = Join-Path $exportDir ("{0}-{1}{2}" -f $Distro, (Get-Date -Format 'yyyyMMdd-HHmmss'), $extension)
}

if ((Test-Path $Path) -and -not $Force) {
    throw "$Path already exists (use -Force to overwrite)."
}

if ($StopFirst) {
    Write-Step "Stopping $Distro for a consistent snapshot"
    & wsl.exe --terminate $Distro | Out-Null
    Start-Sleep -Seconds 2
    Write-Ok 'Stopped'
}
else {
    Write-Warn2 'Exporting a running distro. Use -StopFirst for a consistent backup.'
}

$parent = Split-Path -Parent $Path
if ($parent -and -not (Test-Path $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}

Write-Step "Exporting to $Path"
$wslTarget = $Path -replace '\\', '/'
$arguments = @('--export', $Distro, $wslTarget)
if ($Vhd) {
    # --vhd exports the disk image instead of a tar archive.
    $arguments = @('--export', $Distro, $wslTarget, '--vhd')
}
& wsl.exe @arguments
if ($LASTEXITCODE -ne 0) {
    throw "wsl --export failed with exit code $LASTEXITCODE"
}

$size = [math]::Round((Get-Item $Path).Length / 1GB, 2)
Write-Ok "Archive written: $Path ($size GB)"

$restoredName = "$Distro-restored"
$restoreDir = Join-Path $env:USERPROFILE "WSL\$restoredName"
Write-Step 'Restore command (keep for your runbook)'
Write-Host @"
  wsl --import $restoredName "$restoreDir" "$Path" --version 2
  wsl --set-default $restoredName

  Note: an imported distro starts as root. Set the default user in
  /etc/wsl.conf ([user] default=<name>).
"@ -ForegroundColor Gray
exit 0
