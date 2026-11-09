<#
.SYNOPSIS
  End-to-end test of the PowerShell-hosted tray app.

.DESCRIPTION
  Safe test mode only: sets BATTERYGUARD_TEST_CONTROLLER=monitoring, so the
  factory returns a monitoring-only controller and no HpBios/WMI/WriteGuard is
  constructed. It checks CLI --status, the PowerShell-hosted tray, memory/CPU,
  screenshots and the logon task. control.ps1 and --once are skipped. No charge
  write is possible; the test fails if the new log contains any charge write.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $root 'scripts\control.ps1'
$launcher = Join-Path $root 'scripts\start.ps1'
$log = Join-Path $PSScriptRoot 'tray-host-test.log'
$shot = Join-Path $PSScriptRoot 'tray-screen.png'
$zoom = Join-Path $PSScriptRoot 'tray-zoom.png'
$culture = [System.Globalization.CultureInfo]::InvariantCulture
$env:BATTERYGUARD_TEST_CONTROLLER = 'monitoring'
$testMode = $true
$failed = $false
$beforeLog = if (Test-Path (Join-Path $root 'application.log')) { Get-Content (Join-Path $root 'application.log') -Raw } else { '' }

function Say {
    param([string]$Text)
    Write-Host $Text
    Add-Content -Path $log -Value $Text -Encoding UTF8
}

Set-Content -Path $log -Value ('BatteryGuard host test {0:u}' -f (Get-Date)) -Encoding UTF8

Say '--- 1. skipped hardware control (injected monitoring-only controller) ---'

Say '--- 2. hosted CLI --status ---'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcher -NoElevate -Cli '--status'
Say ('status exit=' + $LASTEXITCODE)

Say '--- 3. skipped --once (test mode has no charge write path) ---'

Say '--- 4. run tray host in background ---'
$arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"' + $launcher + '"'), '-NoElevate')
$proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -PassThru
Start-Sleep -Seconds 12

if ($proc.HasExited) {
    Say ('tray host EXITED early, code=' + $proc.ExitCode)
    $failed = $true
}
else {
    $live = Get-Process -Id $proc.Id
    Say ('tray host alive pid=' + $proc.Id)
    Say ('working set  = ' + ($live.WorkingSet64 / 1MB).ToString('N1', $culture) + ' MB')
    Say ('private bytes = ' + ($live.PrivateMemorySize64 / 1MB).ToString('N1', $culture) + ' MB')
    Say ('handles       = ' + $live.HandleCount)
    Say ('threads       = ' + $live.Threads.Count)

    $cpuStart = (Get-Process -Id $proc.Id).TotalProcessorTime.TotalSeconds
    Start-Sleep -Seconds 30
    $cpuEnd = (Get-Process -Id $proc.Id).TotalProcessorTime.TotalSeconds
    $cores = [Environment]::ProcessorCount
    $total = ($cpuEnd - $cpuStart) / 30.0
    Say ('cpu over 30 s = ' + $total.ToString('N3', $culture) + ' s  (' + ($total / $cores * 100).ToString('N2', $culture) + '% of ' + $cores + ' cores, ' + ($total * 100).ToString('N2', $culture) + '% of one core)')
    $live.Refresh()
    Say ('working set after 42 s = ' + ($live.WorkingSet64 / 1MB).ToString('N1', $culture) + ' MB')
}

Say '--- 5. screenshots ---'
try {
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    $graphics.Dispose()

    $cropWidth = 460
    $cropHeight = 70
    $rect = New-Object System.Drawing.Rectangle ($bounds.Width - $cropWidth), ($bounds.Height - $cropHeight), $cropWidth, $cropHeight
    $crop = $bitmap.Clone($rect, $bitmap.PixelFormat)
    $bitmap.Save($shot, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()

    $scale = 4
    $zoomed = New-Object System.Drawing.Bitmap ($cropWidth * $scale), ($cropHeight * $scale)
    $zoomGraphics = [System.Drawing.Graphics]::FromImage($zoomed)
    $zoomGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $zoomGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $zoomGraphics.DrawImage($crop, 0, 0, $zoomed.Width, $zoomed.Height)
    $zoomGraphics.Dispose()
    $zoomed.Save($zoom, [System.Drawing.Imaging.ImageFormat]::Png)
    $zoomed.Dispose()
    $crop.Dispose()
    Say ('screenshots saved ' + $bounds.Width + 'x' + $bounds.Height)
}
catch {
    Say ('screenshot failed: ' + $_.Exception.Message)
}

Say '--- 6. logon task ---'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcher -NoElevate -Cli '--install-autostart'
Start-Sleep -Seconds 2
$task = Get-ScheduledTask -TaskName 'BatteryGuardTray' -ErrorAction SilentlyContinue
if (-not $task) {
    Say 'FAIL: logon task was not created (install needs an elevated shell)'
    $failed = $true
}
else {
    Say ('task state      = ' + $task.State)
    $action = @($task.Actions)[0]
    Say ('task command    = ' + $action.Execute)
    Say ('task arguments  = ' + $action.Arguments)
    $target = $action.Execute.Trim('"')
    if (-not (Test-Path -LiteralPath $target)) {
        Say ('FAIL: task target does not exist: ' + $target)
        $failed = $true
    }
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcher -NoElevate -Cli '--remove-autostart'
Start-Sleep -Seconds 2
$taskAfter = Get-ScheduledTask -TaskName 'BatteryGuardTray' -ErrorAction SilentlyContinue
if ($taskAfter) {
    Say 'FAIL: logon task is still installed after remove'
    $failed = $true
}
else {
    Say 'task removed'
}

Say '--- 7. cleanup ---'
if (-not $proc.HasExited) {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}
Get-Process application -ErrorAction SilentlyContinue |
    ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
Say 'cleanup: stopped the PowerShell-hosted tray; no control.ps1 invoked'

Say '--- 8. tray log tail and safety assertions ---'
$trayLog = Join-Path $root 'application.log'
$afterLog = if (Test-Path $trayLog) { Get-Content $trayLog -Raw } else { '' }
$newLines = if ($afterLog.Length -gt $beforeLog.Length) { $afterLog.Substring($beforeLog.Length) } else { '' }
if (Test-Path $trayLog) {
    Get-Content $trayLog -Tail 25 | ForEach-Object { Say $_ }
}
if ($newLines -notmatch 'test controller: monitoring-only') {
    Say 'FAIL: injected test controller log line is missing'
    $failed = $true
}
if ($newLines -notmatch 'cap=monitoring') {
    Say 'FAIL: cap=monitoring is missing from the test tray log'
    $failed = $true
}
if ($newLines -match 'charge mode set|action=(auto|inhibit)|inhibit write|auto write') {
    Say 'FAIL: a charge-write line appeared during the safe test'
    $failed = $true
}
if (-not $testMode) {
    Say 'FAIL: hardware mode is not allowed in this test'
    $failed = $true
}

if ($failed) { Say 'test FAILED'; exit 1 }
Say 'test PASS; no charge write was issued'
