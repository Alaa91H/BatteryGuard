<#
.SYNOPSIS
  Read-only probe for the HP/Insyde setup variables behind the F.28 BIOS.

.DESCRIPTION
  Prints the current bytes of SystemConfig and AdvanceConfig
  (f4274aa0-00df-424d-b552-39511302113d), H19SetupUtilityConfig
  (746d2526-c058-6441-bbaa-99f203e1f522) and H19SetupVariable
  (a5f3fe30-29ba-6747-9f11-7c7fd606ffa6) and decodes the offsets documented
  in docs/DEVICE_SUPPORT.md for the HP ENVY x360 13-ay.

  Firmware is never written: only GetFirmwareEnvironmentVariable is called.
  The script needs an elevated PowerShell to enable SeSystemEnvironmentPrivilege.
  It writes a log next to itself unless -LogPath is supplied.

.PARAMETER LogPath
  Transcript path. Defaults to probe-bios-settings.log next to this script.

.PARAMETER Full
  Dump the whole variable instead of the first 128 bytes.
#>
[CmdletBinding()]
param(
    [string]$LogPath = (Join-Path $PSScriptRoot 'probe-bios-settings.log'),
    [switch]$Full
)

$ErrorActionPreference = 'Continue'
$lines = New-Object System.Collections.Generic.List[string]

function Log {
    param([string]$Message = '')
    $lines.Add($Message)
    Write-Host $Message
}

$source = @'
using System;
using System.Runtime.InteropServices;

public static class FirmwareProbe
{
    [StructLayout(LayoutKind.Sequential)]
    public struct Luid { public uint LowPart; public int HighPart; }

    [StructLayout(LayoutKind.Sequential)]
    public struct LuidAndAttributes { public Luid Luid; public uint Attributes; }

    [StructLayout(LayoutKind.Sequential)]
    public struct TokenPrivileges { public uint PrivilegeCount; public LuidAndAttributes Privilege; }

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr GetCurrentProcess();

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool LookupPrivilegeValue(string system, string name, out Luid luid);

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll, ref TokenPrivileges state,
        uint length, IntPtr previous, IntPtr returnLength);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern uint GetFirmwareEnvironmentVariable(string name, string guid, byte[] buffer, uint size);

    public static int EnablePrivilege(string name)
    {
        IntPtr token;
        if (!OpenProcessToken(GetCurrentProcess(), 0x28, out token))
            return Marshal.GetLastWin32Error();
        Luid luid;
        if (!LookupPrivilegeValue(null, name, out luid))
            return Marshal.GetLastWin32Error();
        TokenPrivileges state = new TokenPrivileges();
        state.PrivilegeCount = 1;
        state.Privilege.Luid = luid;
        state.Privilege.Attributes = 0x2;
        if (!AdjustTokenPrivileges(token, false, ref state, 0, IntPtr.Zero, IntPtr.Zero))
            return Marshal.GetLastWin32Error();
        return Marshal.GetLastWin32Error();
    }
}
'@

Add-Type -TypeDefinition $source -Language CSharp

function Get-Win32Text {
    param([int]$Code)
    try { return (New-Object System.ComponentModel.Win32Exception($Code)).Message }
    catch { return 'unknown error' }
}

function Write-HexDump {
    param([byte[]]$Data, [int]$MaxBytes)
    $limit = [Math]::Min($Data.Length, $MaxBytes)
    for ($i = 0; $i -lt $limit; $i += 16) {
        $end = [Math]::Min($i + 15, $limit - 1)
        $chunk = $Data[$i..$end]
        $hex = ($chunk | ForEach-Object { $_.ToString('x2') }) -join ' '
        Log ('  {0:x4}  {1}' -f $i, $hex)
    }
    if ($Data.Length -gt $MaxBytes) {
        Log ('  ... {0} more bytes (use -Full)' -f ($Data.Length - $MaxBytes))
    }
}

function Show-Field {
    param([byte[]]$Data, [int]$Offset, [string]$Name, [hashtable]$Map)
    if ($Offset -ge $Data.Length) {
        Log ('  0x{0:x4}  {1,-38} out of range (size {2})' -f $Offset, $Name, $Data.Length)
        return
    }
    $value = [int]$Data[$Offset]
    $meaning = ''
    if ($Map -and $Map.ContainsKey([string]$value)) { $meaning = $Map[[string]$value] }
    Log ('  0x{0:x4}  {1,-38} = {2,3} (0x{2:x2})  {3}' -f $Offset, $Name, $value, $meaning)
}

function Read-SetupVariable {
    param([string]$Name, [string]$Guid, [int]$Expected)
    $buffer = New-Object byte[] 8192
    $guidText = '{' + $Guid + '}'
    $size = [FirmwareProbe]::GetFirmwareEnvironmentVariable($Name, $guidText, $buffer, $buffer.Length)
    if ($size -eq 0) {
        $error = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Log ('{0}: read failed (Win32 {1}: {2})' -f $Name, $error, (Get-Win32Text $error))
        if ($error -eq 203) {
            Log '  The variable is not exposed at runtime under this name.'
            Log '  A UEFI shell dump is the only remaining read-only option.'
        }
        return $null
    }
    $data = New-Object byte[] $size
    [Array]::Copy($buffer, $data, $size)
    $suffix = ''
    if ($Expected -gt 0 -and $size -ne $Expected) { $suffix = ' (expected ' + $Expected + ')' }
    Log ('{0}: {1} bytes{2}' -f $Name, $size, $suffix)
    return $data
}

Log '=== BIOS setup variable probe (read-only) ==='
Log ('Time     : {0:u}' -f (Get-Date))

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$elevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Log ('User     : {0}  elevated={1}' -f $identity.Name, $elevated)

if (-not $elevated) {
    Log 'Run this probe from an elevated PowerShell; it needs SeSystemEnvironmentPrivilege.'
    try { Set-Content -Path $LogPath -Value $lines -Encoding UTF8 -ErrorAction Stop } catch { }
    exit 2
}

$privilege = [FirmwareProbe]::EnablePrivilege('SeSystemEnvironmentPrivilege')
if ($privilege -ne 0) {
    Log ('SeSystemEnvironmentPrivilege was not enabled (Win32 {0}: {1})' -f $privilege, (Get-Win32Text $privilege))
} else {
    Log 'SeSystemEnvironmentPrivilege: enabled'
}
Log ''

$systemConfig = Read-SetupVariable -Name 'SystemConfig' `
    -Guid 'f4274aa0-00df-424d-b552-39511302113d' -Expected 700
$utilityConfig = Read-SetupVariable -Name 'H19SetupUtilityConfig' `
    -Guid '746d2526-c058-6441-bbaa-99f203e1f522' -Expected 44
$h19Variable = Read-SetupVariable -Name 'H19SetupVariable' `
    -Guid 'a5f3fe30-29ba-6747-9f11-7c7fd606ffa6' -Expected 17
$advanceConfig = Read-SetupVariable -Name 'AdvanceConfig' `
    -Guid 'f4274aa0-00df-424d-b552-39511302113d' -Expected 8

if ($systemConfig) {
    Log ''
    Log '--- SystemConfig ---'
    $max = if ($Full) { $systemConfig.Length } else { 128 }
    Write-HexDump -Data $systemConfig -MaxBytes $max
    Log ''
    Log 'Documented fields:'
    Show-Field $systemConfig 0x23E 'Battery Care Function' @{ '0' = '100%'; '1' = '80%'; '2' = '50%' }
    Show-Field $systemConfig 0x240 'Adaptive Battery Optimizer' @{ '0' = 'Disabled'; '1' = 'Enabled' }
    Show-Field $systemConfig 0x23C 'Battery Remaining Time' @{ '0' = 'Disabled'; '1' = 'Enabled' }
    Show-Field $systemConfig 0x237 'USB Charging' @{ '0' = 'Disabled'; '1' = 'Enabled' }
    Show-Field $systemConfig 0xEE 'SVM support / Virtualization' @{ '0' = 'Disabled'; '1' = 'Enabled' }
    Show-Field $systemConfig 0xEF 'SVM Lock' @{ '0' = 'Disabled'; '1' = 'Enabled' }
    Show-Field $systemConfig 0x220 'Virtualization Technology gate' @{}
    Show-Field $systemConfig 0x1FF 'Secure Biometrics Camera Support' @{ '0' = 'Disabled'; '1' = 'Enabled' }
}

if ($utilityConfig) {
    Log ''
    Log '--- H19SetupUtilityConfig ---'
    Write-HexDump -Data $utilityConfig -MaxBytes $utilityConfig.Length
    Log ''
    Log 'Documented feature gates (non-zero builds the dependent setting):'
    Show-Field $utilityConfig 0x17 'Battery Care Function gate' @{}
    Show-Field $utilityConfig 0x23 'Adaptive Battery Optimizer gate' @{}
    Show-Field $utilityConfig 0x15 'Battery Remaining Time gate' @{}
    Show-Field $utilityConfig 0x02 'USB Charging gate' @{}
    Show-Field $utilityConfig 0x08 'Integrated Camera gate' @{}
    Show-Field $utilityConfig 0x09 'Fingerprint Reader gate' @{}
}

if ($h19Variable) {
    Log ''
    Log '--- H19SetupVariable ---'
    Write-HexDump -Data $h19Variable -MaxBytes $h19Variable.Length
    Log ''
    Log 'Documented fields:'
    Show-Field $h19Variable 0x0D 'Integrated Camera' @{ '0' = 'Disabled'; '1' = 'Enabled' }
    Show-Field $h19Variable 0x0F 'Fingerprint Reader' @{ '0' = 'Disabled'; '1' = 'Enabled' }
}

if ($advanceConfig) {
    Log ''
    Log '--- AdvanceConfig ---'
    Write-HexDump -Data $advanceConfig -MaxBytes $advanceConfig.Length
    Log ''
    Log 'Internal variables (no UI prompt in the F.28 IFR):'
    for ($i = 0; $i -lt $advanceConfig.Length; $i++) {
        Log ('  0x{0:x4}  internal value                          = {1,3} (0x{1:x2})' -f $i, [int]$advanceConfig[$i])
    }
}

if ($utilityConfig) {
    Log ''
    Log 'Effective visibility:'
    $pairs = @(
        @{ Gate = 0x17; Offset = 0x23E; Name = 'Battery Care Function'; Source = 'system' },
        @{ Gate = 0x23; Offset = 0x240; Name = 'Adaptive Battery Optimizer'; Source = 'system' },
        @{ Gate = 0x15; Offset = 0x23C; Name = 'Battery Remaining Time'; Source = 'system' },
        @{ Gate = 0x02; Offset = 0x237; Name = 'USB Charging'; Source = 'system' },
        @{ Gate = 0x08; Offset = 0x0D; Name = 'Integrated Camera'; Source = 'h19' },
        @{ Gate = 0x09; Offset = 0x0F; Name = 'Fingerprint Reader'; Source = 'h19' }
    )
    foreach ($pair in $pairs) {
        $sourceData = if ($pair.Source -eq 'h19') { $h19Variable } else { $systemConfig }
        if (-not $sourceData) { continue }
        $gate = 0
        if ($pair.Gate -lt $utilityConfig.Length) { $gate = [int]$utilityConfig[$pair.Gate] }
        $value = 'n/a'
        if ($pair.Offset -lt $sourceData.Length) { $value = [string][int]$sourceData[$pair.Offset] }
        $state = if ($gate -ne 0) { 'built' } else { 'hidden by gate' }
        Log ('  0x{0:x3}  {1,-30} value={2}  gate={3}  {4}' -f $pair.Offset, $pair.Name, $value, $gate, $state)
    }
}

Log ''
Log 'Read-only probe: no firmware write was performed.'

try {
    Set-Content -Path $LogPath -Value $lines -Encoding UTF8 -ErrorAction Stop
    Write-Host ('Log written to {0}' -f $LogPath)
}
catch {
    Write-Host ('Could not write log: {0}' -f $_.Exception.Message)
}
