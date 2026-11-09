# Restarts the tray app from the current source and prints startup log lines.
# Run elevated.

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$launcher = Join-Path $PSScriptRoot 'start.ps1'
$log = Join-Path $root 'application.log'

Get-CimInstance Win32_Process |
    Where-Object {
        $_.ProcessId -ne $PID -and (
            $_.CommandLine -like ('*' + $launcher + '*') -or
            $_.CommandLine -like '*Start-BatteryGuardTray.ps1*' -or
            $_.Name -eq 'BatteryGuardTray.exe'
        )
    } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2

$arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"' + $launcher + '"'), '-NoElevate')
$process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -PassThru
Start-Sleep -Seconds 10

'tray pid=' + $process.Id + ' alive=' + (-not $process.HasExited)
Get-Content $log -Tail 12
