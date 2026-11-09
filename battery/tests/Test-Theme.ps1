<#
.SYNOPSIS
  Verifies theme resolution and live start in the safe test controller.

.DESCRIPTION
  Sets BATTERYGUARD_TEST_CONTROLLER=monitoring, so no HpBios, WMI gateway or
  WriteGuard is constructed. For dark / light / auto it writes theme.ini,
  starts the PowerShell-hosted tray, checks the new log, then stops it. The
  original theme.ini is restored and no tray process is left behind.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$launcher = Join-Path $root 'scripts\start.ps1'
$themeFile = Join-Path $root 'theme.ini'
$log = Join-Path $root 'application.log'
$out = Join-Path $PSScriptRoot 'theme-test.log'

$env:BATTERYGUARD_TEST_CONTROLLER = 'monitoring'
$originalTheme = if (Test-Path $themeFile) { Get-Content $themeFile -Raw } else { $null }

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
    Get-Process application -ErrorAction SilentlyContinue |
        ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
}

function Start-Tray {
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

try {
    Stop-Tray

    foreach ($mode in @('dark', 'light', 'auto')) {
        Stop-Tray
        Set-Content -Path $themeFile -Value $mode -Encoding ASCII
        Say ('--- theme.ini = ' + $mode + ' ---')
        $process = Start-Tray
        $line = Get-Content $log -Tail 80 | Where-Object { $_ -like '*theme mode=*' } | Select-Object -Last 1
        Say ('resolved: ' + $line)
        Say ('tray alive = ' + (-not $process.HasExited))
        Say ('mode check = ' + ((Get-Content $log -Tail 80 | Where-Object { $_ -like '*test controller: monitoring-only*' -or $_ -like '*cap=monitoring*' } | Select-Object -Last 1)))
        Stop-Tray
    }

    Say '--- final: auto, stopped and cleaned ---'
    Set-Content -Path $themeFile -Value 'auto' -Encoding ASCII
    $final = Start-Tray
    Say ('final pid = ' + $final.Id + ' alive = ' + (-not $final.HasExited))
    Get-Content $log -Tail 12 | ForEach-Object { Say $_ }
    Stop-Tray
    Say 'done; no tray process left'
}
finally {
    Stop-Tray
    if ($null -ne $originalTheme) {
        Set-Content -Path $themeFile -Value $originalTheme -Encoding ASCII -NoNewline
    }
    else {
        Remove-Item -LiteralPath $themeFile -ErrorAction SilentlyContinue
    }
}
