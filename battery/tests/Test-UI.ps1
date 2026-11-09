<#
.SYNOPSIS
  Verifies the ceiling-number option end to end in the safe test controller.

.DESCRIPTION
  Sets BATTERYGUARD_TEST_CONTROLLER=monitoring, so start.ps1 hosts the UI in
  PowerShell and BatteryControllerFactory returns a monitoring-only controller.
  No HpBios, WMI gateway or WriteGuard is constructed. The test writes
  interface.ini with showCeiling on/off, restarts the tray, checks the new log,
  then restores interface.ini and stops the host.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$launcher = Join-Path $root 'scripts\start.ps1'
$log = Join-Path $root 'application.log'
$ui = Join-Path $root 'interface.ini'

$env:BATTERYGUARD_TEST_CONTROLLER = 'monitoring'
$originalUi = if (Test-Path $ui) { Get-Content $ui -Raw } else { $null }

function Stop-Tray {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like '*start.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Get-Process application -ErrorAction SilentlyContinue |
        ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
}

function Restart-Tray {
    Stop-Tray

    $before = if (Test-Path $log) { Get-Content $log -Raw } else { '' }
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"' + $launcher + '"'), '-NoElevate')
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -PassThru
    $deadline = (Get-Date).AddSeconds(30)
    $newLines = ''
    do {
        Start-Sleep -Milliseconds 500
        if ($process.HasExited) { throw ('BatteryGuard tray host exited early, code=' + $process.ExitCode) }
        $after = if (Test-Path $log) { Get-Content $log -Raw } else { '' }
        $newLines = if ($after.Length -gt $before.Length) { $after.Substring($before.Length) } else { '' }
    } while ($newLines -notmatch 'tray started' -and (Get-Date) -lt $deadline)
    if ($newLines -notmatch 'tray started') { throw 'BatteryGuard tray did not start within 30 s' }
    if ($newLines -notmatch 'test controller: monitoring-only|cap=monitoring') {
        throw 'BatteryGuard did not enter the injected monitoring-only test mode'
    }
    return $process
}

function Set-Ceiling([string]$value) {
    $lines = @()
    if (Test-Path $ui) { $lines = @(Get-Content $ui) }
    $found = $false
    $lines = @($lines | ForEach-Object {
        if ($_ -match '^showCeiling=') { $found = $true; 'showCeiling=' + $value } else { $_ }
    })
    if (-not $found) { $lines += 'showCeiling=' + $value }
    if (-not ($lines -match '^notifications=')) { $lines += 'notifications=on' }
    Set-Content -Path $ui -Value $lines -Encoding UTF8
}

try {
    Set-Ceiling 'on'
    $on = Restart-Tray
    '--- showCeiling=on ---'
    Get-Content $log -Tail 12 | Where-Object { $_ -like '*icon state=*' } | Select-Object -Last 2
    'tray alive=' + (-not $on.HasExited)

    Stop-Tray
    Set-Ceiling 'off'
    $off = Restart-Tray
    '--- showCeiling=off ---'
    Get-Content $log -Tail 12 | Where-Object { $_ -like '*icon state=*' } | Select-Object -Last 2
    'tray alive=' + (-not $off.HasExited)
    'test mode log:'
    Get-Content $log -Tail 40 | Where-Object { $_ -like '*test controller:*' -or $_ -like '*cap=monitoring*' } | Select-Object -Last 3
}
finally {
    Stop-Tray
    if ($null -ne $originalUi) {
        Set-Content -Path $ui -Value $originalUi -Encoding UTF8 -NoNewline
    }
    else {
        Remove-Item -LiteralPath $ui -ErrorAction SilentlyContinue
    }
}
