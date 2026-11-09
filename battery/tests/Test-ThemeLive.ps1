<#
.SYNOPSIS
  Verifies that the running tray app reacts to a live Windows theme change.

.DESCRIPTION
  Saves the current AppsUseLightTheme value, flips it, broadcasts
  WM_SETTINGCHANGE("ImmersiveColorSet") the way Windows does, checks the theme
  line the tray writes, then restores the original value and verifies it.
  Run elevated.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$log = Join-Path $root 'application.log'
$out = Join-Path $PSScriptRoot 'theme-live.log'

function Say {
    param([string]$Text)
    Write-Host $Text
    Add-Content -Path $out -Value $Text -Encoding UTF8
}

Set-Content -Path $out -Value ('live theme test {0:u}' -f (Get-Date)) -Encoding UTF8

$apps = (Get-ItemProperty $key -Name AppsUseLightTheme).AppsUseLightTheme
$system = (Get-ItemProperty $key -Name SystemUsesLightTheme).SystemUsesLightTheme
Say ('original apps=' + $apps + ' system=' + $system)

$tray = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like '*start.ps1*' }
Say ('tray processes = ' + @($tray).Count)

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class ThemeBroadcast
{
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, IntPtr wParam, string lParam, uint flags, uint timeout, out IntPtr result);

    public static void Notify()
    {
        IntPtr result;
        SendMessageTimeout((IntPtr)0xffff, 0x001A, IntPtr.Zero, "ImmersiveColorSet", 2, 1000, out result);
    }
}
'@ -Language CSharp -ReferencedAssemblies 'System.dll'

function Show-LastTheme {
    Get-Content $log -Tail 30 | Where-Object { $_ -like '*theme mode=*' } | Select-Object -Last 1 | ForEach-Object { Say $_ }
}

try {
    Say '--- flip to light ---'
    Set-ItemProperty $key -Name AppsUseLightTheme -Value 1 -Type DWord
    [ThemeBroadcast]::Notify()
    Start-Sleep -Seconds 3
    Show-LastTheme

    Say '--- restore original ---'
    Set-ItemProperty $key -Name AppsUseLightTheme -Value $apps -Type DWord
    [ThemeBroadcast]::Notify()
    Start-Sleep -Seconds 3
    Show-LastTheme
}
finally {
    Set-ItemProperty $key -Name AppsUseLightTheme -Value $apps -Type DWord
    [ThemeBroadcast]::Notify()
    Start-Sleep -Seconds 2
    $restored = (Get-ItemProperty $key -Name AppsUseLightTheme).AppsUseLightTheme
    $restoredSystem = (Get-ItemProperty $key -Name SystemUsesLightTheme).SystemUsesLightTheme
    Say ('restored apps=' + $restored + ' system=' + $restoredSystem + ' (original apps=' + $apps + ' system=' + $system + ')')
}

Say 'done'
