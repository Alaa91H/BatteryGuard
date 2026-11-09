<#
.SYNOPSIS
  Read-only probe for HP battery charge-control support (v5).

.DESCRIPTION
  v3/v4 decoding:
    rc 2 = HPWMI_RET_WRONG_SIGNATURE
    rc 3 = HPWMI_RET_UNKNOWN_COMMAND     <- what command 0x20008 returned
    rc 4 = HPWMI_RET_UNKNOWN_CMDTYPE
    rc 5 = HPWMI_RET_INVALID_PARAMETERS

  hp-wmi reads with command 0x01 (HPWMI_READ), not 0x20008 (GM), so v5 uses
  0x01 and also queries HPWMI_BATTERY_QUERY (0x07, insize 1) as a control that
  the dispatcher answers battery-related command types at all.

  Read-only only: 0x01/0x03 commands. No 0x02 or 0x20009 write.

.PARAMETER LogPath
  Transcript path. Defaults to probe-v5.log next to this script.
#>
[CmdletBinding()]
param(
    [string]$LogPath = (Join-Path $PSScriptRoot 'probe-v5.log')
)

$ErrorActionPreference = 'Continue'
$lines = New-Object System.Collections.Generic.List[string]

function Log {
    param([string]$Message)
    $lines.Add($Message)
    Write-Host $Message
}

$SECU = [byte[]](0x53, 0x45, 0x43, 0x55)   # "SECU" / 0x55434553

function Get-ReturnName {
    param([uint32]$Code)
    switch ($Code) {
        0 { 'SUCCESS' }
        2 { 'WRONG_SIGNATURE' }
        3 { 'UNKNOWN_COMMAND' }
        4 { 'UNKNOWN_CMDTYPE' }
        5 { 'INVALID_PARAMETERS' }
        default { 'other' }
    }
}

Log ('=== HP battery charge-control probe v5  {0:u} ===' -f (Get-Date))
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
Log ('User      : {0}  elevated={1}' -f $identity.Name, $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))

$session = $null
$biosMethods = $null
try {
    $session = New-CimSession -SkipTestConnection
    $biosMethods = Get-CimInstance -Namespace root\wmi -ClassName hpqBIntM -CimSession $session -ErrorAction Stop
    Log ('hpqBIntM  : acquired (Active={0})' -f $biosMethods.Active)
}
catch {
    Log ('hpqBIntM  : FAILED -> {0}' -f $_.Exception.Message)
}

function Send-HpBiosRead {
    param(
        [uint32]$Command,
        [uint32]$CommandType,
        [int]$InputSize = 0
    )

    $label = 'cmd=0x{0:x5} ctype=0x{1:x2} insize={2}' -f $Command, $CommandType, $InputSize

    if (-not $biosMethods) {
        Log ('  {0} -> skipped' -f $label)
        return
    }

    try {
        $props = @{
            Command     = [uint32]$Command
            CommandType = [uint32]$CommandType
            Size        = [uint32]$InputSize
            Sign        = $SECU
        }
        if ($InputSize -gt 0) { $props['hpqBData'] = (New-Object byte[] $InputSize) }

        $inData = New-CimInstance -Namespace root\wmi -ClassName hpqBDataIn -ClientOnly -Property $props
        $response = Invoke-CimMethod -InputObject $biosMethods -MethodName 'hpqBIOSInt128' `
            -Arguments @{ InData = [CimInstance]$inData } -ErrorAction Stop

        $out = $response.OutData
        if ($null -eq $out) {
            Log ('  {0} -> no OutData' -f $label)
            return
        }

        $rc = [uint32]$out.rwReturnCode
        $data = @($out.Data | Select-Object -First 12)
        Log ('  {0} -> rc={1} ({2})  data=[{3}]' -f $label, $rc, (Get-ReturnName $rc), ($data -join ','))
    }
    catch {
        Log ('  {0} -> ERR {1}' -f $label, $_.Exception.Message)
    }
}

Log ''
Log '--- control: battery query 0x07 (hp-wmi reads this with insize 1) ---'
Send-HpBiosRead -Command 0x01 -CommandType 0x07 -InputSize 1
Send-HpBiosRead -Command 0x01 -CommandType 0x07 -InputSize 0

Log '--- control: feature queries 0x0b / 0x0d ---'
Send-HpBiosRead -Command 0x01 -CommandType 0x0b -InputSize 4
Send-HpBiosRead -Command 0x01 -CommandType 0x0d -InputSize 4

Log '--- charge control 0x1f, charge mode 0x2b ---'
Send-HpBiosRead -Command 0x01 -CommandType 0x1f -InputSize 0
Send-HpBiosRead -Command 0x01 -CommandType 0x1f -InputSize 4
Send-HpBiosRead -Command 0x01 -CommandType 0x2b -InputSize 0
Send-HpBiosRead -Command 0x01 -CommandType 0x2b -InputSize 4

Log '--- compare: same types via GM 0x20008 (expected UNKNOWN_COMMAND here) ---'
Send-HpBiosRead -Command 0x20008 -CommandType 0x1f -InputSize 0
Send-HpBiosRead -Command 0x20008 -CommandType 0x2b -InputSize 0

Log ''
Log 'Read-only probe: no write command was issued.'

if ($session) { Remove-CimSession $session -ErrorAction SilentlyContinue }

try {
    Set-Content -Path $LogPath -Value $lines -Encoding UTF8 -ErrorAction Stop
    Write-Host ('Log written to {0}' -f $LogPath)
}
catch {
    Write-Host ('Could not write log: {0}' -f $_.Exception.Message)
}
