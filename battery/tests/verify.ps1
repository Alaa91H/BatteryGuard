<#
.SYNOPSIS
  Scenario checks for BatteryGuard against the real firmware.

.DESCRIPTION
  Covers: one-click presets (enable + disable), custom ceiling with a resume
  drop, explicit resume percentage, schedule windows (auto vs ceiling) and the
  watcher loop. Always finishes with normal charging restored, the logon task
  removed and the schedule disabled.

  Run elevated.
#>
[CmdletBinding()]
param(
    [int]$SettleSeconds = 8
)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$tool = Join-Path $root 'scripts\control.ps1'
$configPath = Join-Path $root 'settings.json'
$log = Join-Path $PSScriptRoot 'verify.log'
$outFile = Join-Path $PSScriptRoot 'watcher.out.log'
$errFile = Join-Path $PSScriptRoot 'watcher.err.log'

function Section {
    param([string]$Title)
    $line = '===== {0} =====' -f $Title
    Write-Host $line
    Add-Content -Path $log -Value $line -Encoding UTF8
}

function Line {
    param([string]$Text)
    Write-Host $Text
    Add-Content -Path $log -Value $Text -Encoding UTF8
}

function Show-Status {
    & $tool -Status 2>&1 | Tee-Object -FilePath $log -Append
}

function Show-Config {
    if (-not (Test-Path $configPath)) { Line 'config: (missing)'; return }
    $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
    Line ('config: preset={0} ceiling={1} resume={2} drop={3} schedule={4}' -f `
        $cfg.preset, $cfg.ceiling, $cfg.resume, $cfg.resumeDrop, $cfg.scheduleEnabled)
}

Set-Content -Path $log -Value ('BatteryGuard scenarios {0:u} on {1}' -f (Get-Date), $env:COMPUTERNAME) -Encoding UTF8
Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue

$watcher = $null

try {
    Section '1. baseline (Preset Off)'
    & $tool -Preset Off 2>&1 | Tee-Object -FilePath $log -Append
    Show-Status
    Show-Config
    Line ('task: {0}' -f $(if (Get-ScheduledTask -TaskName 'BatteryGuard' -ErrorAction SilentlyContinue) { 'present' } else { 'removed' }))

    Section '2. one-click enable: Preset Recommended'
    & $tool -Preset Recommended 2>&1 | Tee-Object -FilePath $log -Append
    Start-Sleep -Seconds $SettleSeconds
    Show-Status
    Show-Config
    $task = Get-ScheduledTask -TaskName 'BatteryGuard' -ErrorAction SilentlyContinue
    Line ('task: {0}' -f $(if ($task) { $task.State } else { 'NOT registered' }))

    Section '3. one-click disable: Preset Off'
    & $tool -Preset Off 2>&1 | Tee-Object -FilePath $log -Append
    Start-Sleep -Seconds 2
    Show-Status
    Line ('task: {0}' -f $(if (Get-ScheduledTask -TaskName 'BatteryGuard' -ErrorAction SilentlyContinue) { 'STILL present' } else { 'removed' }))

    Section '4. custom ceiling with resume drop 10'
    & $tool -Limit 80 -ResumeDrop 10 -Once 2>&1 | Tee-Object -FilePath $log -Append
    Show-Config
    Show-Status
    & $tool -Mode Auto 2>&1 | Tee-Object -FilePath $log -Append

    Section '5. explicit resume percentage'
    & $tool -Limit 70 -ResumeAt 62 -Once 2>&1 | Tee-Object -FilePath $log -Append
    Show-Config

    Section '6. schedule: auto window covering now'
    $now = Get-Date
    $autoFrom = $now.AddHours(-1).ToString('HH:mm')
    $autoTo = $now.AddHours(1).ToString('HH:mm')
    $otherFrom = $autoTo
    $otherTo = $autoFrom
    & $tool -Schedule ("{0}-{1}=auto,{2}-{3}=60" -f $autoFrom, $autoTo, $otherFrom, $otherTo) 2>&1 | Tee-Object -FilePath $log -Append
    & $tool -Mode Inhibit 2>&1 | Tee-Object -FilePath $log -Append
    & $tool -Once 2>&1 | Tee-Object -FilePath $log -Append
    Show-Status

    Section '7. schedule: ceiling window covering now'
    & $tool -Schedule ("{0}-{1}=60,{2}-{3}=auto" -f $autoFrom, $autoTo, $otherFrom, $otherTo) 2>&1 | Tee-Object -FilePath $log -Append
    & $tool -Mode Auto 2>&1 | Tee-Object -FilePath $log -Append
    & $tool -Once 2>&1 | Tee-Object -FilePath $log -Append
    Show-Status

    Section '8. watcher honours the schedule'
    $watcher = Start-Process powershell -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $outFile -RedirectStandardError $errFile `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tool, '-Watch')
    Start-Sleep -Seconds ($SettleSeconds + 4)
    $exited = $watcher.HasExited
    Line ('watcher: pid={0} exitedEarly={1}' -f $watcher.Id, $exited)
    if (-not $exited) { Stop-Process -Id $watcher.Id -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 1
    if (Test-Path $errFile) {
        $errors = Get-Content $errFile
        if ($errors) { Line ('watcher stderr: {0}' -f ($errors -join ' | ')) }
    }
    Show-Status
}
finally {
    Section '9. cleanup'
    & $tool -ScheduleOff 2>&1 | Tee-Object -FilePath $log -Append
    & $tool -Preset Off 2>&1 | Tee-Object -FilePath $log -Append
    & $tool -Status 2>&1 | Tee-Object -FilePath $log -Append
    Show-Config
    Line ('final task: {0}' -f $(if (Get-ScheduledTask -TaskName 'BatteryGuard' -ErrorAction SilentlyContinue) { 'STILL present' } else { 'removed' }))
}

Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue
Write-Host ('Log: {0}' -f $log)
