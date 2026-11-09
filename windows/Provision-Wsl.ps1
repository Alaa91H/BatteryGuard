#Requires -Version 5.1
<#
.SYNOPSIS
    Provisions the Linux side of a WSL2 distribution from this repository.

.DESCRIPTION
    Copies .\linux into /opt/wsl-provision inside the distro and runs the
    idempotent bootstrap.sh as root. Because systemd only becomes PID 1 after
    /etc/wsl.conf is written and the distro is restarted, the script runs the
    bootstrap twice: once to lay down configuration, then after
    `wsl --terminate`, once more to enable and start services.

.PARAMETER Distro
    Target distribution (default Ubuntu-24.04).

.PARAMETER Profile
    dev    - toolchains + Docker, tuned for daily development.
    prod   - hardened base + Docker + updates + health timer + optional SSH.
    full   - dev + prod together.

.PARAMETER User
    Linux account to create or reuse (default dev).

.PARAMETER Timezone
    IANA timezone, default Etc/UTC.

.PARAMETER Locale
    Primary UTF-8 locale. ar_SA.UTF-8 is always generated as well.

.PARAMETER WithSsh
    Install and configure OpenSSH server on port 2222.

.PARAMETER WithDatabases
    Write a PostgreSQL + Redis Compose stack to /opt/wsl-stack.

.PARAMETER StartDatabases
    Start that stack immediately (implies -WithDatabases).

.PARAMETER WithForge
    Install and start a local-only Forgejo Git server on http://localhost:3000.

.PARAMETER WithGpu
    Install the NVIDIA container toolkit when a WSL GPU is detected.

.PARAMETER WithRust
    Install the Rust toolchain for the target user.

.PARAMETER WithZsh
    Install zsh with autosuggestions and syntax highlighting.

.PARAMETER NoDocker
    Skip Docker Engine installation.

.PARAMETER Upgrade
    Run a full apt upgrade during provisioning (slower, closer to prod).

.PARAMETER SecureSudo
    Do not grant passwordless sudo (the account password stays locked).

.PARAMETER SinglePass
    Do not restart the distro between the two bootstrap passes.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\windows\Provision-Wsl.ps1 -Profile dev

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\windows\Provision-Wsl.ps1 -Profile prod -WithSsh -Upgrade
#>
[CmdletBinding()]
param(
    [string]$Distro = 'Ubuntu-24.04',
    [ValidateSet('dev', 'prod', 'full')]
    [string]$Profile = 'dev',
    [string]$User = 'dev',
    [string]$Timezone = 'Etc/UTC',
    [string]$Locale = 'en_US.UTF-8',
    [switch]$WithSsh,
    [switch]$WithDatabases,
    [switch]$StartDatabases,
    [switch]$WithForge,
    [switch]$WithGpu,
    [switch]$WithRust,
    [switch]$WithZsh,
    [switch]$NoDocker,
    [switch]$Upgrade,
    [switch]$SecureSudo,
    [switch]$SinglePass
)

$ErrorActionPreference = 'Stop'
$script:Root = Split-Path -Parent $PSScriptRoot
$script:LinuxDir = Join-Path $script:Root 'linux'

function Write-Step { param([string]$Message) Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-Ok { param([string]$Message) Write-Host "  [ok]   $Message" -ForegroundColor Green }
function Write-Note { param([string]$Message) Write-Host "  [info] $Message" -ForegroundColor Gray }
function Write-Err2 { param([string]$Message) Write-Host "  [FAIL] $Message" -ForegroundColor Red }

function Get-InstalledDistros {
    $raw = & wsl.exe --list --quiet 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return @() }
    return @($raw | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
}

function Invoke-Wsl {
    param([string[]]$Arguments)
    & wsl.exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "wsl.exe $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

if (-not (Test-Path $script:LinuxDir)) {
    throw "Missing Linux payload directory: $script:LinuxDir"
}
if ((Get-InstalledDistros) -notcontains $Distro) {
    throw "$Distro is not installed. Run .\windows\Install-Wsl2.ps1 -Resume first."
}

if ($StartDatabases) { $WithDatabases = $true }

$bootstrapArgs = @(
    'bash', '/opt/wsl-provision/bootstrap.sh',
    '--profile', $Profile,
    '--user', $User,
    '--timezone', $Timezone,
    '--locale', $Locale
)
if ($WithSsh) { $bootstrapArgs += '--with-ssh' }
if ($WithDatabases) { $bootstrapArgs += '--with-databases' }
if ($StartDatabases) { $bootstrapArgs += '--start-databases' }
if ($WithForge) { $bootstrapArgs += '--with-forge' }
if ($WithGpu) { $bootstrapArgs += '--with-gpu' }
if ($WithRust) { $bootstrapArgs += '--with-rust' }
if ($WithZsh) { $bootstrapArgs += '--with-zsh' }
if ($NoDocker) { $bootstrapArgs += '--no-docker' }
if ($Upgrade) { $bootstrapArgs += '--upgrade' }
if ($SecureSudo) { $bootstrapArgs += '--secure-sudo' }

Write-Step "Copying provisioning payload into $Distro"
$windowsPath = $script:LinuxDir -replace '\\', '/'
$wslPath = (& wsl.exe -d $Distro -u root -- wslpath -a $windowsPath 2>$null | Out-String).Trim()
if (-not $wslPath -or $LASTEXITCODE -ne 0) {
    throw "Could not translate $windowsPath into a WSL path."
}
Write-Ok "Payload available at $wslPath"

$copy = "set -euo pipefail; rm -rf /opt/wsl-provision; mkdir -p /opt/wsl-provision; cp -a " +
        "'$wslPath'/. /opt/wsl-provision/; chmod +x /opt/wsl-provision/bootstrap.sh"
Invoke-Wsl -Arguments @('-d', $Distro, '-u', 'root', '--', 'bash', '-c', $copy)
Write-Ok 'Payload copied to /opt/wsl-provision'

Write-Step "Bootstrap pass 1/2 ($Profile profile)"
Invoke-Wsl -Arguments (@('-d', $Distro, '-u', 'root', '--') + $bootstrapArgs)

if (-not $SinglePass) {
    Write-Step 'Restarting the distribution so systemd becomes PID 1'
    & wsl.exe --terminate $Distro | Out-Null
    Start-Sleep -Seconds 2

    Write-Step 'Bootstrap pass 2/2 (services and verification)'
    Invoke-Wsl -Arguments (@('-d', $Distro, '-u', 'root', '--') + $bootstrapArgs)
}

Write-Step 'Verification'
& wsl.exe -d $Distro -u root -- sudo -u $User -H bash -lc 'wsl-verify'
$verifyCode = $LASTEXITCODE
if ($verifyCode -ne 0) {
    Write-Err2 'Verification reported failures - see the output above.'
    exit $verifyCode
}

Write-Step 'Ready'
Write-Host @"
  Enter the environment:
    wsl -d $Distro

  Check health at any time:
    wsl -d $Distro -u $User -- wsl-verify

  Export a backup before risky changes:
    powershell -ExecutionPolicy Bypass -File .\windows\Export-Wsl.ps1
"@ -ForegroundColor Green
exit 0
