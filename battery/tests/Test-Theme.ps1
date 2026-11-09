<#
.SYNOPSIS
  Verifies theme resolution and live start of the tray app.

.DESCRIPTION
  For each of dark / light / auto it writes theme.ini, starts the tray app,
  waits for it to come up and reports the resolved theme line from the log.
  Finishes with auto running. Run elevated.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$launcher = Join-Path $root 'scripts\start.ps1'
$themeFile = Join-Path $root 'theme.ini'
$log = Join-Path $root 'application.log'
$out = Join-Path $PSScriptRoot 'theme-test.log'

function Say {
    param([string]$Text)
    Write-Host $Text
    Add-Content -Path $out -Value $Text -Encoding UTF8
}

Set-Content -Path $out -Value ('theme test {0:u}' -f (Get-Date)) -Encoding UTF8

function Stop-Tray {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like '*start.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
}

function Start-Tray {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"' + $launcher + '"'), '-NoElevate')
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -PassThru
    Start-Sleep -Seconds 8
    return $process
}

Stop-Tray

foreach ($mode in @('dark', 'light', 'auto')) {
    Set-Content -Path $themeFile -Value $mode -Encoding ASCII
    Say ('--- theme.ini = ' + $mode + ' ---')
    $process = Start-Tray
    $line = Get-Content $log -Tail 60 | Where-Object { $_ -like '*theme mode=*' } | Select-Object -Last 1
    Say ('resolved: ' + $line)
    Say ('tray alive = ' + (-not $process.HasExited))
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
}

Say '--- final: auto, left running ---'
Set-Content -Path $themeFile -Value 'auto' -Encoding ASCII
$final = Start-Tray
Say ('final pid = ' + $final.Id + ' alive = ' + (-not $final.HasExited))
Get-Content $log -Tail 8 | ForEach-Object { Say $_ }

Say 'done'
