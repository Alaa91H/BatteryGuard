<#
.SYNOPSIS
  Exercises application.exe end to end and records resource usage.

.DESCRIPTION
  1. configures ceiling 80 through the PowerShell engine,
  2. runs the exe in --status and --once modes,
  3. starts the tray app, measures working set / CPU / threads,
  4. captures a screenshot of the desktop,
  5. verifies autostart task creation and removal,
  6. stops the tray, restores normal charging and removes the task.

  Run elevated.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$engineScript = Join-Path $root 'scripts\control.ps1'
$exe = Join-Path $root 'application.exe'
$log = Join-Path $PSScriptRoot 'tray-test.log'
$shot = Join-Path $PSScriptRoot 'tray-screen.png'

function Say {
    param([string]$Text)
    Write-Host $Text
    Add-Content -Path $log -Value $Text -Encoding UTF8
}

Set-Content -Path $log -Value ('BatteryGuard tray test {0:u}' -f (Get-Date)) -Encoding UTF8

Say '--- 1. configure ceiling 80 via CLI ---'
& $engineScript -Limit 80 -ResumeDrop 5 -Once 2>&1 | ForEach-Object { Say $_ }
& $engineScript -Mode Auto 2>&1 | ForEach-Object { Say $_ }
& $engineScript -Status 2>&1 | ForEach-Object { Say $_ }

Say '--- 2. tray exe --status (read only) ---'
& $exe --status | Out-Null
Start-Sleep -Seconds 1

Say '--- 3. tray exe --once (must inhibit at 100% > 80%) ---'
& $exe --once | Out-Null
Start-Sleep -Seconds 1
& $engineScript -Status 2>&1 | ForEach-Object { Say $_ }

Say '--- 4. run tray app in background ---'
$process = Start-Process -FilePath $exe -PassThru
Start-Sleep -Seconds 10

if ($process.HasExited) {
    Say ('tray EXITED early, code={0}' -f $process.ExitCode)
}
else {
    $live = Get-Process -Id $process.Id
    Say ('tray alive pid={0}' -f $process.Id)
    Say ('working set = {0:N1} MB' -f ($live.WorkingSet64 / 1MB))
    Say ('private bytes = {0:N1} MB' -f ($live.PrivateMemorySize64 / 1MB))
    Say ('cpu time = {0:N2} s' -f $live.TotalProcessorTime.TotalSeconds)
    Say ('threads = {0}  handles = {1}' -f $live.Threads.Count, $live.HandleCount)
}

Say '--- 5. desktop screenshot ---'
try {
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    $graphics.Dispose()
    $bitmap.Save($shot, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    Say ('screenshot saved {0}x{1}' -f $bounds.Width, $bounds.Height)
}
catch {
    Say ('screenshot failed: {0}' -f $_.Exception.Message)
}

Say '--- 6. autostart task create/remove ---'
& $exe --install-autostart | Out-Null
Start-Sleep -Seconds 1
$created = schtasks /Query /TN BatteryGuardTray 2>&1
Say ('after install: exit={0}' -f $LASTEXITCODE)
& $exe --remove-autostart | Out-Null
Start-Sleep -Seconds 1
$removed = schtasks /Query /TN BatteryGuardTray 2>&1
Say ('after remove: exit={0}' -f $LASTEXITCODE)

Say '--- 7. cleanup ---'
if (-not $process.HasExited) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}
& $engineScript -Preset Off 2>&1 | ForEach-Object { Say $_ }
& $engineScript -Status 2>&1 | ForEach-Object { Say $_ }

Say '--- 8. tray log tail ---'
$trayLog = Join-Path $root 'application.log'
if (Test-Path $trayLog) {
    Get-Content $trayLog -Tail 25 | ForEach-Object { Say $_ }
}

Say 'done'
