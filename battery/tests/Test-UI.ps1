<#
.SYNOPSIS
  Verifies the ceiling-number option end to end.

.DESCRIPTION
  Writes interface.ini with showCeiling on, restarts the tray, reports the logged
  icon state, then sets showCeiling off again and restarts, leaving the
  defaults in place. Run elevated.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$launcher = Join-Path $root 'scripts\start.ps1'
$log = Join-Path $root 'application.log'
$ui = Join-Path $root 'interface.ini'

function Restart-Tray {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like '*start.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2

    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"' + $launcher + '"'), '-NoElevate')
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -PassThru
    Start-Sleep -Seconds 9
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

Set-Ceiling 'on'
$on = Restart-Tray
'--- showCeiling=on ---'
Get-Content $log -Tail 10 | Where-Object { $_ -like '*icon state=*' } | Select-Object -Last 2
'tray alive=' + (-not $on.HasExited)

Set-Ceiling 'off'
$off = Restart-Tray
'--- showCeiling=off ---'
Get-Content $log -Tail 10 | Where-Object { $_ -like '*icon state=*' } | Select-Object -Last 2
'tray alive=' + (-not $off.HasExited)
'interface.ini:'
Get-Content $ui
