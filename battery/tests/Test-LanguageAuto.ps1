<#
.SYNOPSIS
  Verifies automatic language follows the Windows user UI language.

.DESCRIPTION
  Reproduces the hosted-tray problem: PowerShell reports en-US as its
  CurrentUICulture on this Arabic Windows installation. The test reads the
  Windows user UI language directly, changes the process UI culture to a
  different supported language, and verifies Loc.Resolve("auto") still follows
  Windows. It does not read or write interface.ini, use the battery or require
  elevation.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$root = Split-Path -Parent $PSScriptRoot
$sources = @(Get-ChildItem -Path (Join-Path $root 'src') -Filter '*.cs' | Sort-Object Name | ForEach-Object { $_.FullName })
Add-Type -Path $sources -ReferencedAssemblies 'System.dll', 'System.Drawing.dll', 'System.Management.dll', 'System.Web.Extensions.dll', 'System.Windows.Forms.dll'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class WindowsUiLanguageProbe
{
    [DllImport("kernel32.dll")]
    public static extern ushort GetUserDefaultUILanguage();
}
'@

function Get-AppType([string]$name) {
    foreach ($assembly in [AppDomain]::CurrentDomain.GetAssemblies()) {
        $candidate = $assembly.GetType('BatteryGuardTray.' + $name, $false)
        if ($candidate) { return $candidate }
    }
    return $null
}

function Check([string]$name, [bool]$ok, [string]$detail) {
    if ($ok) {
        '{0}: OK{1}' -f $name, $(if ($detail) { ' (' + $detail + ')' } else { '' })
    }
    else {
        '{0}: FAIL{1}' -f $name, $(if ($detail) { ' (' + $detail + ')' } else { '' })
        $script:failed = $true
    }
}

$locType = Get-AppType 'Loc'
if (-not $locType) { throw 'Loc type not found' }
$resolve = $locType.GetMethod('Resolve', [System.Reflection.BindingFlags]'Public,Static')
if (-not $resolve) { throw 'Loc.Resolve not found' }

$languageId = [WindowsUiLanguageProbe]::GetUserDefaultUILanguage()
if ($languageId -eq 0) { throw 'GetUserDefaultUILanguage returned zero' }
$windowsCulture = [System.Globalization.CultureInfo]::GetCultureInfo([int]$languageId)

# Convert the Windows culture to the code Resolve accepts (for example ar-SA
# becomes ar and zh-TW stays zh-TW); unsupported languages resolve to English.
if ($windowsCulture.Name.StartsWith('zh', [StringComparison]::OrdinalIgnoreCase)) {
    $expectedInput = if ($windowsCulture.Name.IndexOf('Hant', [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $windowsCulture.Name.EndsWith('TW', [StringComparison]::OrdinalIgnoreCase) -or
        $windowsCulture.Name.EndsWith('HK', [StringComparison]::OrdinalIgnoreCase) -or
        $windowsCulture.Name.EndsWith('MO', [StringComparison]::OrdinalIgnoreCase)) { 'zh-TW' } else { 'zh-CN' }
}
else {
    $expectedInput = $windowsCulture.TwoLetterISOLanguageName.ToLowerInvariant()
    if ($expectedInput -eq 'iw') { $expectedInput = 'he' }
    if ($expectedInput -eq 'in') { $expectedInput = 'id' }
}
$expected = [string]$resolve.Invoke($null, @($expectedInput))

# Force the process UI culture to a different supported language. On Arabic
# Windows, this is the en-US culture PowerShell was reporting before the fix.
if ($expected -eq 'fr') {
    $processCulture = 'de-DE'
    $processCode = 'de'
}
else {
    $processCulture = 'fr-FR'
    $processCode = 'fr'
}

$thread = [System.Threading.Thread]::CurrentThread
$originalCulture = $thread.CurrentUICulture
$actual = ''
try {
    $thread.CurrentUICulture = [System.Globalization.CultureInfo]::GetCultureInfo($processCulture)
    $actual = [string]$resolve.Invoke($null, @('auto'))
}
finally {
    $thread.CurrentUICulture = $originalCulture
}

'--- automatic language ---'
'windows language id = 0x{0:X4}' -f $languageId
'windows culture     = ' + $windowsCulture.Name
'expected code       = ' + $expected
'process culture     = ' + $processCulture
'resolved auto       = ' + $actual
$script:failed = $false
Check 'auto follows Windows UI language' ($actual -eq $expected) $actual
Check 'auto ignores process UI culture' ($actual -ne $processCode) ($actual + ' != ' + $processCode)

if ($script:failed) { exit 1 }
