#Requires -Version 5.1
<#
.SYNOPSIS
    Installs WSL2 plus an Ubuntu distribution on Windows 10 2004+ / Windows 11.

.DESCRIPTION
    Phase 1 (default): enables the two Windows optional features, sets WSL2 as
    the default version, installs the WSL package and asks for a reboot.
    Phase 2 (-Resume): after the reboot, installs the requested distro and
    applies the tuned %UserProfile%\.wslconfig.

    The script is idempotent: re-running it never duplicates work and never
    overwrites an existing .wslconfig unless -Force is given.

.PARAMETER Distro
    Distribution to install. Ubuntu-24.04 (LTS) by default.

.PARAMETER Resume
    Run the post-reboot phase.

.PARAMETER SkipDistro
    Only enable WSL2, do not install a distribution.

.PARAMETER SkipWslConfig
    Do not copy .wslconfig to the user profile.

.PARAMETER Force
    Overwrite an existing %UserProfile%\.wslconfig (a .bak is kept).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\windows\Install-Wsl2.ps1

.EXAMPLE
    # after the reboot
    powershell -ExecutionPolicy Bypass -File .\windows\Install-Wsl2.ps1 -Resume
#>
[CmdletBinding()]
param(
    [string]$Distro = 'Ubuntu-24.04',
    [switch]$Resume,
    [switch]$SkipDistro,
    [switch]$SkipWslConfig,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$script:Root = Split-Path -Parent $PSScriptRoot
$script:RebootRequired = $false

function Write-Step { param([string]$Message) Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-Ok { param([string]$Message) Write-Host "  [ok]   $Message" -ForegroundColor Green }
function Write-Note { param([string]$Message) Write-Host "  [info] $Message" -ForegroundColor Gray }
function Write-Warn2 { param([string]$Message) Write-Host "  [warn] $Message" -ForegroundColor Yellow }
function Write-Err2 { param([string]$Message) Write-Host "  [FAIL] $Message" -ForegroundColor Red }

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WindowsBuild {
    return [int](Get-CimInstance -ClassName Win32_OperatingSystem).BuildNumber
}

function Test-RebootPending {
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        return $true
    }
    $sessionManager = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    $pending = (Get-ItemProperty -Path $sessionManager -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
    return [bool]$pending
}

function Get-InstalledDistros {
    $raw = & wsl.exe --list --quiet 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return @() }
    return @($raw | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
}

function Enable-WindowsFeature {
    param([string]$Name)

    Write-Note "Enabling optional feature $Name (this can take a minute)"
    $output = & dism.exe /online /enable-feature /featurename:$Name /all /norestart 2>&1
    $code = $LASTEXITCODE
    # 0 = done, 3010 = done but a reboot is required.
    if ($code -eq 3010) {
        $script:RebootRequired = $true
        Write-Ok "$Name enabled (reboot required)"
        return
    }
    if ($code -ne 0) {
        $output | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
        throw "Failed to enable $Name (dism exit code $code)."
    }
    Write-Ok "$Name enabled"
}

function Set-WslDefaults {
    $lxss = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss'
    if (-not (Test-Path $lxss)) {
        New-Item -Path $lxss -Force | Out-Null
    }
    New-ItemProperty -Path $lxss -Name DefaultVersion -Value 2 -PropertyType DWord -Force | Out-Null
    Write-Ok 'Default WSL version set to 2'
}

function Update-WslPackage {
    Write-Note 'Updating the WSL package from Microsoft'
    $output = & wsl.exe --update --web-download 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warn2 'WSL package update failed (the inbox build will be used).'
        return
    }
    Write-Ok 'WSL package is up to date'
}

function Install-WslConfig {
    if ($SkipWslConfig) {
        Write-Note 'Skipping .wslconfig (per -SkipWslConfig)'
        return
    }

    $source = Join-Path $script:Root '.wslconfig'
    $target = Join-Path $env:USERPROFILE '.wslconfig'

    if (-not (Test-Path $source)) {
        Write-Warn2 "No .wslconfig found at $source"
        return
    }
    if ((Test-Path $target) -and -not $Force) {
        Write-Warn2 "$target already exists - left untouched (use -Force to replace)"
        return
    }
    if (Test-Path $target) {
        $backup = "$target.bak.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -Path $target -Destination $backup -Force
        Write-Note "Existing config backed up to $backup"
    }
    Copy-Item -Path $source -Destination $target -Force
    Write-Ok "Installed $target"
}

function Assert-SupportedHost {
    if (-not (Test-Admin)) {
        throw 'This script must run from an elevated PowerShell (Run as administrator).'
    }
    $build = Get-WindowsBuild
    if ($build -lt 19041) {
        throw "Windows build $build is too old. WSL2 requires build 19041 (Windows 10 2004) or newer."
    }
    Write-Ok "Windows build $build"
}

function Invoke-InstallPhase {
    Write-Step 'Phase 1/2 - Windows features and WSL package'
    Assert-SupportedHost

    Enable-WindowsFeature -Name 'Microsoft-Windows-Subsystem-Linux'
    Enable-WindowsFeature -Name 'VirtualMachinePlatform'
    Set-WslDefaults
    Update-WslPackage
    Install-WslConfig

    if ($script:RebootRequired -or (Test-RebootPending)) {
        Write-Step 'Reboot required'
        Write-Host @'
  WSL2 is enabled but Windows must restart before the Linux kernel is usable.

  Next steps:
    1. Restart Windows.
    2. Run again from an elevated PowerShell:
         powershell -ExecutionPolicy Bypass -File .\windows\Install-Wsl2.ps1 -Resume
'@ -ForegroundColor Yellow
        return 3
    }

    if (-not $SkipDistro) {
        Invoke-DistroPhase
    }
    return 0
}

function Invoke-DistroPhase {
    Write-Step "Phase 2/2 - Installing distribution $Distro"
    Assert-SupportedHost

    $distros = Get-InstalledDistros
    if ($distros -contains $Distro) {
        Write-Ok "$Distro is already installed"
    }
    elseif ($SkipDistro) {
        Write-Note 'Skipping distribution install (per -SkipDistro)'
        return 0
    }
    else {
        Write-Note "Installing $Distro (no interactive user prompt)"
        & wsl.exe --install --distribution $Distro --no-launch --web-download
        if ($LASTEXITCODE -ne 0) {
            throw @"
Failed to install $Distro (wsl exit code $LASTEXITCODE).
If the Store is blocked, run: wsl --list --online
and install the distro manually with: wsl --install -d $Distro --no-launch
"@
        }
        $distros = Get-InstalledDistros
        if ($distros -notcontains $Distro) {
            throw "$Distro is still not registered after installation."
        }
        Write-Ok "$Distro installed"
    }

    & wsl.exe --set-version $Distro 2 | Out-Null
    Write-Ok "$Distro pinned to WSL version 2"

    & wsl.exe --set-default $Distro | Out-Null
    Write-Ok "$Distro is the default distribution"

    # Sparse VHD support exists on WSL 2.0+; ignore failures on older builds.
    & wsl.exe --manage $Distro --set-sparse true 2>$null | Out-Null

    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        throw 'wsl.exe is not on PATH.'
    }

    Write-Step 'Next step'
    Write-Host @"
  Provision the distribution (no admin shell needed):
    powershell -ExecutionPolicy Bypass -File .\windows\Provision-Wsl.ps1 -Profile dev
"@ -ForegroundColor Green
    return 0
}

try {
    if ($Resume) {
        $code = Invoke-DistroPhase
    }
    else {
        $code = Invoke-InstallPhase
    }
    exit $code
}
catch {
    Write-Err2 $_.Exception.Message
    exit 1
}
