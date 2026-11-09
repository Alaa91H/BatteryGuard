<#
.SYNOPSIS
  End-to-end test of the PowerShell-hosted tray app.

.DESCRIPTION
  1. CLI pass-through (--status),
  2. policy enforcement via --once at a 80% ceiling,
  3. background tray run with memory and CPU measurement,
  4. full screenshot plus a 4x zoom of the notification area,
  5. logon task create / inspect / remove,
  6. cleanup back to normal charging.

  Run elevated.
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

function Say {
    param([string]$Text)
    Write-Host $Text
    Add-Content -Path $log -Value $Text -Encoding UTF8
}

Set-Content -Path $log -Value ('BatteryGuard host test {0:u}' -f (Get-Date)) -Encoding UTF8

Say '--- 1. set ceiling 80 and normal charging ---'
& $engine -Limit 80 -ResumeDrop 5 -Once 2>&1 | ForEach-Object { Say $_ }
& $engine -Mode Auto 2>&1 | ForEach-Object { Say $_ }

Say '--- 2. hosted CLI --status ---'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcher -NoElevate -Cli '--status'
Say ('status exit=' + $LASTEXITCODE)

Say '--- 3. hosted CLI --once (100% > ceiling 80 -> inhibit) ---'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcher -NoElevate -Cli '--once'
Say ('once exit=' + $LASTEXITCODE)
& $engine -Status 2>&1 | ForEach-Object { Say $_ }

Say '--- 4. run tray host in background ---'
$arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"' + $launcher + '"'), '-NoElevate')
$proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -PassThru
Start-Sleep -Seconds 12

if ($proc.HasExited) {
    Say ('tray host EXITED early, code=' + $proc.ExitCode)
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
Start-Sleep -Seconds 1
schtasks.exe /Query /TN BatteryGuardTray 2>&1 | ForEach-Object { Say $_ }
Say ('query exit=' + $LASTEXITCODE)
$xml = schtasks.exe /Query /TN BatteryGuardTray /XML 2>&1 | Out-String
$match = [regex]::Match($xml, '<Command>(.*?)</Command>')
$matchArgs = [regex]::Match($xml, '<Arguments>(.*?)</Arguments>')
Say ('task command  = ' + $match.Groups[1].Value)
Say ('task arguments= ' + $matchArgs.Groups[1].Value)
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcher -NoElevate -Cli '--remove-autostart'
Start-Sleep -Seconds 1
schtasks.exe /Query /TN BatteryGuardTray 2>&1 | Out-Null
Say ('after remove query exit=' + $LASTEXITCODE)

Say '--- 7. cleanup ---'
if (-not $proc.HasExited) {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}
& $engine -Preset Off 2>&1 | ForEach-Object { Say $_ }
& $engine -Status 2>&1 | ForEach-Object { Say $_ }

Say '--- 8. tray log tail ---'
$trayLog = Join-Path $root 'application.log'
if (Test-Path $trayLog) {
    Get-Content $trayLog -Tail 20 | ForEach-Object { Say $_ }
}

Say 'done'
