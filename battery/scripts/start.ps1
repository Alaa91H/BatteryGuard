<#
.SYNOPSIS
  Runs BatteryGuard's native Win32 tray UI (src/*.cs) inside a
  Microsoft-signed PowerShell host.

.DESCRIPTION
  Smart App Control blocks unsigned executables on this machine, so the
  separately compiled application.exe cannot start. This launcher compiles
  the exact same C# source in memory with Add-Type and runs it inside
  powershell.exe, which is trusted. The UI is still raw Win32: Shell_NotifyIcon,
  an owner-drawn popup menu and a WM_TIMER loop, with no WinForms.

  Parameters:
    -Cli "<args>"   Run one CLI pass, e.g. -Cli "--status" or -Cli "--once".
    -NoElevate      Do not relaunch elevated (used by the logon task).

  Without -Cli the tray icon runs until the process is stopped.
#>
[CmdletBinding()]
param(
    [string]$Cli,
    [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$sources = @(Get-ChildItem -Path (Join-Path $root 'src') -Filter '*.cs' | Sort-Object Name | ForEach-Object { $_.FullName })
foreach ($item in $sources) {
    if (-not (Test-Path -LiteralPath $item)) { throw "Source file not found at $item" }
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal $identity
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin -and -not $NoElevate) {
    $arguments = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', ('"' + $PSCommandPath + '"'), '-NoElevate'
    )
    if ($Cli) { $arguments += @('-Cli', ('"' + $Cli + '"')) }
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments | Out-Null
    return
}

# Prefer the compiled exe (30 KB, no PowerShell host) whenever Smart App Control
# is not blocking unsigned binaries. Fall back to the in-process host otherwise.
$sacEnforced = $false
try {
    $policy = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -Name VerifiedAndReputablePolicyState -ErrorAction Stop
    $sacEnforced = ($policy.VerifiedAndReputablePolicyState -eq 1)
}
catch { $sacEnforced = $false }

$exe = Join-Path $root 'application.exe'
if (-not $sacEnforced -and (Test-Path -LiteralPath $exe)) {
    try {
        if ($Cli) {
            & $exe @($Cli.Split(' '))
        }
        else {
            Start-Process -FilePath $exe | Out-Null
        }
        return
    }
    catch {
        Write-Warning ('compiled exe failed (' + $_.Exception.Message + '), hosting in PowerShell instead')
    }
}

$env:BATTERYGUARD_HOME = $root
$env:BATTERYGUARD_HOST = 'ps1'
$env:BATTERYGUARD_ENTRY = $PSCommandPath

Add-Type -Path $sources -ReferencedAssemblies 'System.dll', 'System.Drawing.dll', 'System.Management.dll', 'System.Web.Extensions.dll', 'System.Windows.Forms.dll'

$program = $null
foreach ($assembly in [AppDomain]::CurrentDomain.GetAssemblies()) {
    $candidate = $assembly.GetType('BatteryGuardTray.Program', $false)
    if ($candidate) { $program = $candidate; break }
}
if (-not $program) { throw 'BatteryGuardTray.Program was not found after compilation' }

$flags = [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Static
$main = $program.GetMethod('Main', $flags)

$argv = New-Object 'object[]' 1
if ($Cli) { $argv[0] = [string[]]$Cli.Split(' ') } else { $argv[0] = [string[]]@() }

$main.Invoke($null, $argv)
