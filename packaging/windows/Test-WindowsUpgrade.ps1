<#
.SYNOPSIS
  Verifies the published v0.1.0 CLI MSI can be upgraded by the new EXE bundle.

.DESCRIPTION
  Runs only on a clean, elevated Windows host. It installs the published
  v0.1.0 x64 MSI, verifies its CLI payload, installs the new Burn EXE bundle
  over it, checks that the old MSI product is gone and the tray payload exists,
  then removes the bundle. This is an upgrade test, not an interactive UI test.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Bundle,

    [string]$OldMsiUrl = 'https://github.com/Alaa91H/BatteryGuard/releases/download/v0.1.0/BatteryGuard-0.1.0-windows-x64.msi'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'The Windows upgrade test must run elevated.'
}

$bundlePath = (Resolve-Path -LiteralPath $Bundle).Path
$installDir = Join-Path $env:ProgramFiles 'BatteryGuard'
$work = Join-Path $env:RUNNER_TEMP ('batteryguard-upgrade-' + [Guid]::NewGuid().ToString('N'))
$oldMsi = Join-Path $work 'BatteryGuard-0.1.0-windows-x64.msi'
$oldLog = Join-Path $work 'old-install.log'
$newLog = Join-Path $work 'new-install.log'
$removeLog = Join-Path $work 'new-uninstall.log'

function Get-BatteryGuardProducts {
    $paths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    @(Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -eq 'BatteryGuard' })
}

function Assert-ExitCode([int]$code, [string]$operation) {
    if ($code -notin @(0, 3010)) {
        throw "$operation failed with exit code $code"
    }
}

function Assert-File([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing expected payload: $path"
    }
}

New-Item -ItemType Directory -Force -Path $work | Out-Null
try {
    if (Test-Path -LiteralPath $installDir) {
        throw "The upgrade test requires a clean host; $installDir already exists."
    }
    if ((Get-BatteryGuardProducts).Count -ne 0) {
        throw 'The upgrade test requires a clean host; BatteryGuard is already registered.'
    }

    Write-Output 'Downloading published v0.1.0 x64 MSI'
    Invoke-WebRequest -Uri $OldMsiUrl -OutFile $oldMsi -UseBasicParsing
    Unblock-File -LiteralPath $oldMsi

    Write-Output 'Installing published v0.1.0 CLI MSI'
    $oldInstall = Start-Process -FilePath msiexec.exe -ArgumentList @(
        '/i', ('"' + $oldMsi + '"'), '/qn', '/norestart', '/l*v', ('"' + $oldLog + '"')
    ) -Wait -PassThru
    Assert-ExitCode $oldInstall.ExitCode 'old MSI install'

    $oldCli = Join-Path $installDir 'batteryguard.exe'
    Assert-File $oldCli
    $oldProducts = @(Get-BatteryGuardProducts)
    if ($oldProducts.Count -lt 1) {
        throw 'The old MSI did not register a BatteryGuard product.'
    }
    $oldCodes = @($oldProducts | ForEach-Object { $_.PSChildName })
    Write-Output ("Old products: " + ($oldCodes -join ', '))

    $oldVersion = (& $oldCli --version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $oldVersion -notmatch 'BatteryGuard portable core 0\.1\.0') {
        throw "Unexpected old CLI output: '$oldVersion'"
    }
    Write-Output "Old CLI: $oldVersion"

    Write-Output 'Installing new EXE bundle over v0.1.0'
    Unblock-File -LiteralPath $bundlePath
    $newInstall = Start-Process -FilePath $bundlePath -ArgumentList @(
        '/install', '/quiet', '/norestart', '/log', ('"' + $newLog + '"')
    ) -Wait -PassThru
    Assert-ExitCode $newInstall.ExitCode 'new EXE install'

    Assert-File (Join-Path $installDir 'application.exe')
    Assert-File (Join-Path $installDir 'application.exe.config')
    Assert-File (Join-Path $installDir 'batteryguard.exe')
    Assert-File (Join-Path $installDir 'resources\application.ico')
    Assert-File (Join-Path $installDir 'locales\ar.json')
    Assert-File (Join-Path $installDir 'locales\zh-CN.json')

    $shortcut = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\BatteryGuard\BatteryGuard.lnk'
    Assert-File $shortcut
    $uninstall = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\BatteryGuard\Uninstall BatteryGuard.lnk'
    Assert-File $uninstall

    $newProducts = @(Get-BatteryGuardProducts)
    foreach ($product in $newProducts) {
        Write-Output ("Registered product: " + $product.PSChildName + " version " + $product.DisplayVersion + " systemComponent=" + $product.SystemComponent)
    }
    $oldRemaining = @($newProducts | Where-Object { $oldCodes -contains $_.PSChildName })
    if ($oldRemaining.Count -gt 0) {
        throw ('The old MSI product remains after upgrade: ' + ($oldRemaining.PSChildName -join ', '))
    }
    $visibleProducts = @($newProducts | Where-Object { $_.SystemComponent -ne 1 })
    if ($visibleProducts.Count -ne 1) {
        throw ("Expected one visible BatteryGuard Apps & Features entry after upgrade, found $($visibleProducts.Count).")
    }
    if ($newProducts.Count -lt 2) {
        Write-Warning 'No hidden MSI registration was found behind the bundle.'
    }
    Write-Output ("Visible Apps & Features product: " + $visibleProducts[0].PSChildName)

    Write-Output 'Uninstalling new EXE bundle'
    $remove = Start-Process -FilePath $bundlePath -ArgumentList @(
        '/uninstall', '/quiet', '/norestart', '/log', ('"' + $removeLog + '"')
    ) -Wait -PassThru
    Assert-ExitCode $remove.ExitCode 'new EXE uninstall'
    if (Test-Path -LiteralPath $installDir) {
        throw "Install directory remains after uninstall: $installDir"
    }
    if ((Get-BatteryGuardProducts).Count -ne 0) {
        throw 'BatteryGuard remains registered after uninstall.'
    }

    Write-Output 'Upgrade test passed: v0.1.0 MSI -> new EXE bundle -> clean uninstall'
}
catch {
    Write-Output ('Upgrade test failed: ' + $_.Exception.Message)
    if (Test-Path -LiteralPath $oldLog) {
        Write-Output '--- old MSI log tail ---'
        Get-Content -LiteralPath $oldLog -Tail 80 -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $newLog) {
        Write-Output '--- new EXE log tail ---'
        Get-Content -LiteralPath $newLog -Tail 120 -ErrorAction SilentlyContinue
    }
    throw
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
