<#
.SYNOPSIS
  BatteryGuard - charge-ceiling manager for HP notebooks whose BIOS hides the
  battery care feature.

.DESCRIPTION
  Talks to HP's undocumented BIOS WMI charge-mode command (command type 0x2b,
  GBCO/SBCO) and switches between:
      Auto    -> firmware charges normally
      Inhibit -> AC stays connected, charging stops ("plugged in, not charging")

  The firmware only offers modes, not percentages, so this tool enforces the
  ceiling in software:

    * charging is inhibited when the battery reaches the ceiling,
    * charging resumes when the level drops to the resume point, which is
      either an explicit percentage or "ceiling minus N points" (default 5),
    * optional time windows switch between a ceiling and normal charging
      (for example: ceiling 80 from 00:00 to 12:00, normal charging after).

  Settings live in settings.json at the project root, so the logon
  task and manual runs always share the same policy.

  Requires an elevated PowerShell session: HP's WMI provider denies non-admin
  access to hpqBIntM. The tool never uses force-discharge; it writes only
  0x00 (auto) and 0x05 (inhibit).

.PARAMETER Status
  Show battery level, AC state, firmware mode, saved policy and task state.

.PARAMETER Mode
  Set the charge mode directly: Auto or Inhibit (does not change settings).

.PARAMETER Limit
  Save a custom ceiling (40-95%) and start watching. Combine with -ResumeAt or
  -ResumeDrop to control when charging resumes.

.PARAMETER ResumeAt
  Explicit resume percentage; must be lower than the ceiling.

.PARAMETER ResumeDrop
  Resume when the level falls this many points below the ceiling (default 5).

.PARAMETER Preset
  Recommended -> ceiling 80%, resume at 75% (HP/Apple-style battery care).
  Longevity   -> ceiling 60%, resume at 55% for a laptop that stays plugged in.
  Off         -> normal charging, stops the watcher and removes the logon task.
  Applying a preset is the one-click enable/disable path.

.PARAMETER Schedule
  Time windows, e.g. "00:00-12:00=80,12:00-23:59=auto". Values may be a
  percentage or "auto" (normal charging). Windows may wrap past midnight.

.PARAMETER ScheduleOff
  Disable time windows (the ceiling/resume settings stay saved).

.PARAMETER Install
  Register the logon task that runs the watcher with the saved settings.

.PARAMETER Uninstall
  Stop and remove the logon task (charging mode is not changed).

.PARAMETER Watch
  Run the watcher in the foreground. This is what the logon task executes.

.PARAMETER Once
  Evaluate the saved policy a single time and exit.

.PARAMETER ConfigPath
  Settings file. Defaults to settings.json at the project root.

.PARAMETER LogPath
  Log file. Defaults to application.log at the project root.

.EXAMPLE
  .\control.ps1 -Status

.EXAMPLE
  .\control.ps1 -Preset Recommended

.EXAMPLE
  .\control.ps1 -Preset Off

.EXAMPLE
  .\control.ps1 -Limit 60 -ResumeDrop 5

.EXAMPLE
  .\control.ps1 -Limit 80 -ResumeAt 70 -Once

.EXAMPLE
  .\control.ps1 -Schedule "00:00-12:00=80,12:00-23:59=auto"

.EXAMPLE
  .\control.ps1 -Mode Auto
#>
[CmdletBinding()]
param(
    [switch]$Status,
    [ValidateSet('Auto', 'Inhibit')][string]$Mode,
    [int]$Limit = 0,
    [int]$ResumeAt = 0,
    [int]$ResumeDrop = 5,
    [ValidateSet('Recommended', 'Longevity', 'Off')][string]$Preset,
    [string]$Schedule,
    [switch]$ScheduleOff,
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Watch,
    [switch]$Once,
    [string]$ConfigPath,
    [string]$LogPath
)

# $PSScriptRoot is empty inside param() defaults when started with -File.
$scriptDirectory = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$root = Split-Path -Parent $scriptDirectory
if ([string]::IsNullOrEmpty($ConfigPath)) { $ConfigPath = Join-Path $root 'settings.json' }
if ([string]::IsNullOrEmpty($LogPath)) { $LogPath = Join-Path $root 'application.log' }

$ErrorActionPreference = 'Stop'

# --- HP WMI protocol constants -------------------------------------------------
$SIGNATURE         = [byte[]](0x53, 0x45, 0x43, 0x55)   # "SECU" / 0x55434553
$CMD_READ          = [uint32]0x01                       # HPWMI_READ
$CMD_WRITE         = [uint32]0x02                       # HPWMI_WRITE
$CTYPE_CHARGE_CTL  = [uint32]0x1f                       # GBCC / SBCC (auto)
$CTYPE_CHARGE_MODE = [uint32]0x2b                       # GBCO / SBCO (inhibit)

$TASK_NAME = 'BatteryGuard'

$PRESETS = @{
    Recommended = @{ Ceiling = 80; ResumeDrop = 5 }
    Longevity   = @{ Ceiling = 60; ResumeDrop = 5 }
}

# --- helpers -------------------------------------------------------------------
function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'BatteryGuard needs an elevated PowerShell session (Run as Administrator).'
    }
}

function Write-Log {
    param([string]$Message)
    $line = '{0:u}  {1}' -f (Get-Date), $Message
    try { Add-Content -Path $LogPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue } catch { }
    Write-Host $line
}

function New-DefaultConfig {
    [pscustomobject]@{
        preset          = 'Off'
        ceiling         = $null
        resume          = $null
        resumeDrop      = 5
        intervalSeconds = 60
        scheduleEnabled = $false
        schedule        = @()
    }
}

function Read-Config {
    if (-not (Test-Path $ConfigPath)) { return (New-DefaultConfig) }
    try {
        $raw = Get-Content -Path $ConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json
    }
    catch {
        Write-Host ('Config file is unreadable ({0}); using defaults.' -f $_.Exception.Message)
        return (New-DefaultConfig)
    }

    $config = New-DefaultConfig
    if ($raw.PSObject.Properties['preset'] -and $raw.preset) { $config.preset = [string]$raw.preset }
    if ($raw.PSObject.Properties['ceiling'] -and $null -ne $raw.ceiling) { $config.ceiling = [int]$raw.ceiling }
    if ($raw.PSObject.Properties['resume'] -and $null -ne $raw.resume) { $config.resume = [int]$raw.resume }
    if ($raw.PSObject.Properties['resumeDrop'] -and $null -ne $raw.resumeDrop) { $config.resumeDrop = [int]$raw.resumeDrop }
    if ($raw.PSObject.Properties['intervalSeconds'] -and $null -ne $raw.intervalSeconds) { $config.intervalSeconds = [int]$raw.intervalSeconds }
    if ($raw.PSObject.Properties['scheduleEnabled']) { $config.scheduleEnabled = [bool]$raw.scheduleEnabled }
    if ($raw.PSObject.Properties['schedule']) { $config.schedule = @($raw.schedule) }
    return $config
}

function Save-Config {
    param([pscustomobject]$Config)
    $Config | ConvertTo-Json -Depth 6 | Set-Content -Path $ConfigPath -Encoding UTF8
}

function Convert-ToMinutes {
    param([string]$Clock)
    if ($Clock -notmatch '^([01]?\d|2[0-3]):([0-5]\d)$') { throw ('Invalid time "{0}" — use HH:mm.' -f $Clock) }
    return ([int]$matches[1] * 60 + [int]$matches[2])
}

function Test-InWindow {
    param([string]$From, [string]$To, [int]$NowMinutes)
    $start = Convert-ToMinutes $From
    $end = Convert-ToMinutes $To
    if ($start -eq $end) { return $true }
    if ($start -lt $end) { return ($NowMinutes -ge $start -and $NowMinutes -lt $end) }
    return ($NowMinutes -ge $start -or $NowMinutes -lt $end)
}

function ConvertFrom-ScheduleText {
    param([string]$Text)

    $windows = @()
    foreach ($part in ($Text -split '[,;]')) {
        $entry = $part.Trim()
        if (-not $entry) { continue }
        if ($entry -notmatch '^([0-2]?\d:[0-5]\d)\s*-\s*([0-2]?\d:[0-5]\d)\s*=\s*(auto|off|\d{1,3})$') {
            throw ('Cannot parse schedule entry "{0}". Use HH:mm-HH:mm=<percent|auto>.' -f $entry)
        }

        $from = $matches[1]
        $to = $matches[2]
        $value = $matches[3].ToLowerInvariant()
        [void](Convert-ToMinutes $from)
        [void](Convert-ToMinutes $to)

        if ($value -in @('auto', 'off')) {
            $windows += [pscustomobject]@{ from = $from; to = $to; ceiling = $null }
        }
        else {
            $ceiling = [int]$value
            if ($ceiling -lt 40 -or $ceiling -gt 95) { throw ('Ceiling {0}% is outside 40-95%.' -f $ceiling) }
            $windows += [pscustomobject]@{ from = $from; to = $to; ceiling = $ceiling }
        }
    }

    if ($windows.Count -eq 0) { throw 'The schedule is empty.' }
    return $windows
}

function Resolve-Resume {
    param([int]$Ceiling, [Nullable[int]]$Explicit, [int]$Drop)
    if ($null -ne $Explicit -and $Explicit -gt 0) {
        if ($Explicit -ge $Ceiling) { throw ('ResumeAt ({0}) must be lower than the ceiling ({1}).' -f $Explicit, $Ceiling) }
        return [int]$Explicit
    }
    return [Math]::Max(30, $Ceiling - [Math]::Max(1, $Drop))
}

function Resolve-Policy {
    param([pscustomobject]$Config)

    if ($Config.scheduleEnabled -and @($Config.schedule).Count -gt 0) {
        $now = Get-Date
        $minutes = $now.Hour * 60 + $now.Minute
        foreach ($window in @($Config.schedule)) {
            if (-not $window.from -or -not $window.to) { continue }
            if (-not (Test-InWindow -From $window.from -To $window.to -NowMinutes $minutes)) { continue }

            if ($null -eq $window.ceiling) {
                return [pscustomobject]@{
                    Kind  = 'Auto'
                    Label = ('schedule {0}-{1}: normal charging' -f $window.from, $window.to)
                }
            }

            $ceiling = [int]$window.ceiling
            $resume = Resolve-Resume -Ceiling $ceiling -Explicit $null -Drop ([int]$Config.resumeDrop)
            return [pscustomobject]@{
                Kind    = 'Ceiling'
                Ceiling = $ceiling
                Resume  = $resume
                Label   = ('schedule {0}-{1}: ceiling {2}%' -f $window.from, $window.to, $ceiling)
            }
        }

        return [pscustomobject]@{ Kind = 'Auto'; Label = 'no active schedule window' }
    }

    if ($Config.preset -eq 'Off' -or $null -eq $Config.ceiling) {
        return [pscustomobject]@{ Kind = 'Auto'; Label = ('preset {0}' -f $Config.preset) }
    }

    $ceiling = [int]$Config.ceiling
    $resume = Resolve-Resume -Ceiling $ceiling -Explicit $Config.resume -Drop ([int]$Config.resumeDrop)
    return [pscustomobject]@{
        Kind    = 'Ceiling'
        Ceiling = $ceiling
        Resume  = $resume
        Label   = ('preset {0}: ceiling {1}%' -f $Config.preset, $ceiling)
    }
}

# --- WMI layer -----------------------------------------------------------------
function New-HpContext {
    $session = New-CimSession -SkipTestConnection
    try {
        $instance = Get-CimInstance -Namespace root\wmi -ClassName hpqBIntM -CimSession $session -ErrorAction Stop
    }
    catch {
        Remove-CimSession $session -ErrorAction SilentlyContinue
        throw ('Cannot open the HP BIOS WMI interface: {0}' -f $_.Exception.Message)
    }
    [pscustomobject]@{ Session = $session; Instance = $instance }
}

function Invoke-HpCommand {
    param(
        [pscustomobject]$Context,
        [uint32]$Command,
        [uint32]$CommandType,
        [byte[]]$Data,
        [int]$OutSize = 128
    )

    $properties = @{
        Command     = $Command
        CommandType = $CommandType
        Size        = [uint32]$Data.Length
        Sign        = $SIGNATURE
    }
    if ($Data.Length -gt 0) { $properties['hpqBData'] = $Data }

    $inData = New-CimInstance -Namespace root\wmi -ClassName hpqBDataIn -ClientOnly -Property $properties
    $response = Invoke-CimMethod -InputObject $Context.Instance -MethodName ('hpqBIOSInt{0}' -f $OutSize) `
        -Arguments @{ InData = [CimInstance]$inData } -ErrorAction Stop

    $out = $response.OutData
    if ($null -eq $out) { return [pscustomobject]@{ ReturnCode = [uint32]0xFFFF; Data = @() } }
    [pscustomobject]@{ ReturnCode = [uint32]$out.rwReturnCode; Data = @($out.Data) }
}

function Get-ChargeMode {
    param([pscustomobject]$Context)
    $result = Invoke-HpCommand -Context $Context -Command $CMD_READ -CommandType $CTYPE_CHARGE_MODE -Data ([byte[]](0, 0, 0, 0))
    if ($result.ReturnCode -ne 0 -or $result.Data.Count -eq 0) { return $null }
    return [int]$result.Data[0]
}

function Get-ModeName {
    param([Nullable[int]]$Code)
    if ($null -eq $Code) { return 'unsupported' }
    switch ($Code) {
        0 { 'Auto' }
        2 { 'ForceDischarge' }
        4 { 'Inhibit' }
        6 { 'Inhibit (extended)' }
        default { 'Unknown(0x{0:x})' -f $Code }
    }
}

function Set-ChargeBehaviour {
    param(
        [pscustomobject]$Context,
        [ValidateSet('Auto', 'Inhibit')][string]$Behaviour
    )

    $value = if ($Behaviour -eq 'Auto') { 0x00 } else { 0x05 }
    $payload = [byte[]](0x00, [byte]$value, 0x00, 0x00)

    # GBCO (0x2b) is the verified path. Some firmware accepts a GBCC (0x1f)
    # write with rc=0 but ignores it, so 0x1f is only the AUTO fallback.
    $targets = if ($Behaviour -eq 'Inhibit') { @($CTYPE_CHARGE_MODE) } else { @($CTYPE_CHARGE_MODE, $CTYPE_CHARGE_CTL) }

    foreach ($ctype in $targets) {
        $result = Invoke-HpCommand -Context $Context -Command $CMD_WRITE -CommandType $ctype -Data $payload
        if ($result.ReturnCode -ne 0) {
            Write-Log ('write ctype=0x{0:x2} value=0x{1:x2} rejected (rc={2})' -f $ctype, $value, $result.ReturnCode)
            continue
        }

        Start-Sleep -Milliseconds 400
        $mode = Get-ChargeMode -Context $Context
        $ok = if ($Behaviour -eq 'Inhibit') { $mode -in 4, 6 } else { $mode -eq 0 }
        if ($ok) {
            Write-Log ('charge mode set to {0} (firmware readback: {1})' -f $Behaviour, (Get-ModeName $mode))
            return $true
        }
        Write-Log ('write ctype=0x{0:x2} accepted but readback is {1}' -f $ctype, (Get-ModeName $mode))
    }

    Write-Log ('could not switch charge mode to {0}' -f $Behaviour)
    return $false
}

function Get-BatteryState {
    $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $battery) { return [pscustomobject]@{ Percent = $null; OnAc = $null } }
    [pscustomobject]@{
        Percent = [int]$battery.EstimatedChargeRemaining
        OnAc    = ($battery.BatteryStatus -eq 2)
    }
}

function Invoke-Policy {
    param(
        [pscustomobject]$Context,
        [pscustomobject]$Policy
    )

    $mode = Get-ChargeMode -Context $Context
    if ($null -eq $mode) {
        Write-Log 'firmware does not answer the charge-mode command; nothing to enforce'
        return
    }

    if ($Policy.Kind -eq 'Auto') {
        if ($mode -in 4, 6) {
            Set-ChargeBehaviour -Context $Context -Behaviour Auto | Out-Null
            Write-Log ('{0}: charging restored' -f $Policy.Label)
        }
        return
    }

    $state = Get-BatteryState
    if ($null -eq $state.Percent) { return }

    if (-not $state.OnAc) {
        if ($mode -in 4, 6) {
            Set-ChargeBehaviour -Context $Context -Behaviour Auto | Out-Null
            Write-Log 'on battery power: charge mode restored to Auto'
        }
        return
    }

    if ($state.Percent -ge $Policy.Ceiling -and $mode -eq 0) {
        Set-ChargeBehaviour -Context $Context -Behaviour Inhibit | Out-Null
        Write-Log ('reached {0}% (ceiling {1}%): charging inhibited' -f $state.Percent, $Policy.Ceiling)
    }
    elseif ($state.Percent -le $Policy.Resume -and $mode -in 4, 6) {
        Set-ChargeBehaviour -Context $Context -Behaviour Auto | Out-Null
        Write-Log ('dropped to {0}% (resume {1}%): charging restored' -f $state.Percent, $Policy.Resume)
    }
}

# --- status --------------------------------------------------------------------
function Get-TaskState {
    $task = Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
    if (-not $task) { return 'not installed' }
    return [string]$task.State
}

function Show-Status {
    param([pscustomobject]$Context, [pscustomobject]$Config, [pscustomobject]$Policy)

    $state = Get-BatteryState
    $mode = Get-ChargeMode -Context $Context
    $onAc = if ($null -eq $state.OnAc) { 'unknown' } elseif ($state.OnAc) { 'yes' } else { 'no' }

    Write-Host ''
    Write-Host ('  Battery        : {0}%' -f $state.Percent)
    Write-Host ('  AC connected   : {0}' -f $onAc)
    Write-Host ('  Firmware mode  : {0}' -f (Get-ModeName $mode))
    Write-Host ('  Preset         : {0}' -f $Config.preset)
    if ($null -ne $Config.ceiling) {
        $resume = Resolve-Resume -Ceiling ([int]$Config.ceiling) -Explicit $Config.resume -Drop ([int]$Config.resumeDrop)
        Write-Host ('  Ceiling        : {0}%  (resume at {1}%)' -f $Config.ceiling, $resume)
    }
    else {
        Write-Host '  Ceiling        : none (normal charging)'
    }
    Write-Host ('  Schedule       : {0}' -f $(if ($Config.scheduleEnabled) { 'enabled' } else { 'disabled' }))
    if ($Config.scheduleEnabled) {
        foreach ($window in @($Config.schedule)) {
            $value = if ($null -eq $window.ceiling) { 'normal charging' } else { ('ceiling {0}%' -f $window.ceiling) }
            Write-Host ('    {0} - {1} : {2}' -f $window.from, $window.to, $value)
        }
    }
    Write-Host ('  Policy now     : {0}' -f $Policy.Label)
    Write-Host ('  Logon task     : {0}' -f (Get-TaskState))
    Write-Host ''
}

# --- settings ------------------------------------------------------------------
function Save-CustomCeiling {
    param([int]$Ceiling, [int]$ExplicitResume, [int]$Drop)

    if ($Ceiling -lt 40 -or $Ceiling -gt 95) { throw 'Limit must be between 40 and 95.' }
    $config = Read-Config
    $config.preset = 'Custom'
    $config.ceiling = $Ceiling
    $config.resume = if ($ExplicitResume -gt 0) { Resolve-Resume -Ceiling $Ceiling -Explicit $ExplicitResume -Drop $Drop } else { $null }
    $config.resumeDrop = [Math]::Max(1, $Drop)
    Save-Config $config
    return $config
}

function Set-Schedule {
    param([string]$Text, [switch]$Disable)

    $config = Read-Config
    if ($Disable) {
        $config.scheduleEnabled = $false
        $config.schedule = @()
        Save-Config $config
        Write-Host 'Schedule disabled.'
        return
    }

    $config.schedule = @(ConvertFrom-ScheduleText $Text)
    $config.scheduleEnabled = $true
    Save-Config $config
    Write-Host ('Schedule enabled with {0} window(s):' -f @($config.schedule).Count)
    foreach ($window in @($config.schedule)) {
        $value = if ($null -eq $window.ceiling) { 'normal charging' } else { ('ceiling {0}%' -f $window.ceiling) }
        Write-Host ('  {0} - {1} : {2}' -f $window.from, $window.to, $value)
    }
}

# --- logon task ----------------------------------------------------------------
function Install-Task {
    Assert-Admin
    $arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Watch' -f $PSCommandPath

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arguments
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -UserId ('{0}\{1}' -f $env:COMPUTERNAME, $env:USERNAME) `
        -RunLevel Highest -LogonType Interactive
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    Register-ScheduledTask -TaskName $TASK_NAME -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force | Out-Null
    Write-Host ('Logon task "{0}" registered.' -f $TASK_NAME)
}

function Uninstall-Task {
    Assert-Admin
    $task = Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host ('Logon task "{0}" was not installed.' -f $TASK_NAME)
        return
    }
    Stop-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false
    Write-Host ('Logon task "{0}" removed.' -f $TASK_NAME)
}

function Apply-Preset {
    param([string]$Name)

    Assert-Admin
    $config = Read-Config

    if ($Name -eq 'Off') {
        $config.preset = 'Off'
        $config.ceiling = $null
        $config.resume = $null
        $config.scheduleEnabled = $false
        Save-Config $config

        Uninstall-Task

        $context = New-HpContext
        try { Set-ChargeBehaviour -Context $context -Behaviour Auto | Out-Null }
        finally { Remove-CimSession $context.Session -ErrorAction SilentlyContinue }

        Write-Host 'BatteryGuard disabled: normal charging restored, logon task removed.'
        return
    }

    $preset = $PRESETS[$Name]
    $config.preset = $Name
    $config.ceiling = [int]$preset.Ceiling
    $config.resume = $null
    $config.resumeDrop = [int]$preset.ResumeDrop
    $config.scheduleEnabled = $false
    $config.schedule = @()
    Save-Config $config

    $resume = Resolve-Resume -Ceiling ([int]$config.ceiling) -Explicit $null -Drop ([int]$config.resumeDrop)
    Write-Host ('Preset {0}: ceiling {1}%, resume at {2}%.' -f $Name, $config.ceiling, $resume)

    Install-Task
    Start-ScheduledTask -TaskName $TASK_NAME
    Write-Host 'Watcher started; settings apply immediately and at every logon.'
}

# --- watcher -------------------------------------------------------------------
function Start-Watch {
    Assert-Admin
    $context = New-HpContext
    Write-Log 'watcher started'

    try {
        while ($true) {
            $config = Read-Config
            $policy = Resolve-Policy -Config $config
            try {
                Invoke-Policy -Context $context -Policy $policy
            }
            catch {
                Write-Log ('watch loop error: {0}' -f $_.Exception.Message)
                try {
                    Remove-CimSession $context.Session -ErrorAction SilentlyContinue
                    $context = New-HpContext
                }
                catch { }
            }

            $interval = if ($config.intervalSeconds) { [int]$config.intervalSeconds } else { 60 }
            Start-Sleep -Seconds ([Math]::Max(5, $interval))
        }
    }
    finally {
        if ($context -and $context.Session) { Remove-CimSession $context.Session -ErrorAction SilentlyContinue }
    }
}

# --- entry point ---------------------------------------------------------------
if ($Uninstall) {
    Uninstall-Task
    return
}

if ($Install) {
    Install-Task
    return
}

if ($Preset) {
    Apply-Preset -Name $Preset
    return
}

if ($Schedule -or $ScheduleOff) {
    Assert-Admin
    Set-Schedule -Text $Schedule -Disable:$ScheduleOff
    if ($Once) {
        $context = New-HpContext
        try { Invoke-Policy -Context $context -Policy (Resolve-Policy -Config (Read-Config)) }
        finally { Remove-CimSession $context.Session -ErrorAction SilentlyContinue }
    }
    return
}

Assert-Admin

if ($Mode) {
    $context = New-HpContext
    try {
        if (Set-ChargeBehaviour -Context $context -Behaviour $Mode) { exit 0 } else { exit 1 }
    }
    finally { Remove-CimSession $context.Session -ErrorAction SilentlyContinue }
}

if ($Limit -gt 0) {
    $null = Save-CustomCeiling -Ceiling $Limit -ExplicitResume $ResumeAt -Drop $ResumeDrop
    if (-not $Once) { Start-Watch; return }
}

if ($Watch) { Start-Watch; return }

$config = Read-Config
$policy = Resolve-Policy -Config $config

if ($Once) {
    $context = New-HpContext
    try { Invoke-Policy -Context $context -Policy $policy }
    finally { Remove-CimSession $context.Session -ErrorAction SilentlyContinue }
    return
}

$statusContext = New-HpContext
try { Show-Status -Context $statusContext -Config $config -Policy $policy }
finally { Remove-CimSession $statusContext.Session -ErrorAction SilentlyContinue }
