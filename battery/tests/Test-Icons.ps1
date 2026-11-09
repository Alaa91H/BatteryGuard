<#
.SYNOPSIS
  Renders the tray icon variants into one PNG contact sheet.

.DESCRIPTION
  Compiles the app source in memory, calls the private icon renderer through
  reflection for four states, and draws them on a dark and a light strip:
  green/active, orange/stopped with ceiling 60, red/error and red/disabled.

  Read-only: no WMI calls, no settings written.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Add-Type -AssemblyName System.Drawing

$sources = @(Get-ChildItem -Path (Join-Path $root 'src') -Filter '*.cs' | Sort-Object Name | ForEach-Object { $_.FullName })
$preview = Join-Path $PSScriptRoot 'icon-preview.png'

$env:BATTERYGUARD_HOME = $root
Add-Type -Path $sources -ReferencedAssemblies 'System.dll', 'System.Drawing.dll', 'System.Management.dll', 'System.Web.Extensions.dll', 'System.Windows.Forms.dll'

$appType = $null
$themeType = $null
foreach ($assembly in [AppDomain]::CurrentDomain.GetAssemblies()) {
    if (-not $appType) { $appType = $assembly.GetType('BatteryGuardTray.TrayApp', $false) }
    if (-not $themeType) { $themeType = $assembly.GetType('BatteryGuardTray.ThemeSettings', $false) }
}
if (-not $appType) { throw 'TrayApp type not found' }

$flags = [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Static
$render = $appType.GetMethod('CreateBatteryIcon', $flags)
$modeField = $themeType.GetField('Mode', [System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Static)
$modeEnum = $themeType.Assembly.GetType('BatteryGuardTray.ThemeMode')

function New-Icon {
    param([int]$Percent, [System.Drawing.Color]$Fill, [bool]$Alert, $Badge)

    $arguments = New-Object 'object[]' 4
    $arguments[0] = $Percent
    $arguments[1] = $Fill
    $arguments[2] = $Alert
    $arguments[3] = $Badge

    $handle = $render.Invoke($null, $arguments)
    $icon = [System.Drawing.Icon]::FromHandle($handle)
    $bitmap = $icon.ToBitmap()
    $icon.Dispose()
    return $bitmap
}

$green = [System.Drawing.Color]::FromArgb(63, 185, 80)
$orange = [System.Drawing.Color]::FromArgb(240, 150, 40)
$red = [System.Drawing.Color]::FromArgb(248, 81, 73)

$scale = 5
$cell = 32 * $scale
$columnGap = 12
$sheet = New-Object System.Drawing.Bitmap (($cell * 4) + ($columnGap * 5)), ((($cell + 16) * 2) + 16)
$graphics = [System.Drawing.Graphics]::FromImage($sheet)
$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half

$darkBack = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(32, 34, 38))
$lightBack = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(243, 243, 243))
$graphics.FillRectangle($darkBack, 0, 0, $sheet.Width, ($cell + 24))
$graphics.FillRectangle($lightBack, 0, ($cell + 24), $sheet.Width, $sheet.Height)

$variants = @(
    @{ Percent = 76; Fill = $green; Alert = $false; Badge = $null },
    @{ Percent = 60; Fill = $orange; Alert = $false; Badge = 60 },
    @{ Percent = 0; Fill = $red; Alert = $true; Badge = $null },
    @{ Percent = 80; Fill = $red; Alert = $false; Badge = $null }
)

$row = 0
foreach ($background in @('dark', 'light')) {
    if ($background -eq 'dark') { $modeField.SetValue($null, [Enum]::Parse($modeEnum, 'Dark')) }
    else { $modeField.SetValue($null, [Enum]::Parse($modeEnum, 'Light')) }

    $index = 0
    foreach ($variant in $variants) {
        $bitmap = New-Icon -Percent $variant.Percent -Fill $variant.Fill -Alert $variant.Alert -Badge $variant.Badge
        $graphics.DrawImage($bitmap, $columnGap + ($index * ($cell + $columnGap)), 8 + ($row * ($cell + 16)), $cell, $cell)
        $bitmap.Dispose()
        $index++
    }
    $row++
}

$graphics.Dispose()
$sheet.Save($preview, [System.Drawing.Imaging.ImageFormat]::Png)
$sheet.Dispose()

$modeField.SetValue($null, [Enum]::Parse($modeEnum, 'Auto'))
'saved ' + $preview
