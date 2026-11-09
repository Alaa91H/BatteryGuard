import glob
import io
import os

FILES = glob.glob("battery/Test-*.ps1") + ["battery/Start-BatteryGuardTray.ps1"]
ROOT_PAIR = "Add-Type -Path @((Join-Path $root 'native\\Localization.cs'), (Join-Path $root 'native\\BatteryGuardTray.cs'))"
PS_PAIR = "Add-Type -Path @((Join-Path $PSScriptRoot 'native\\Localization.cs'), (Join-Path $PSScriptRoot 'native\\BatteryGuardTray.cs'))"

for path in FILES:
    if not os.path.exists(path):
        continue
    text = io.open(path, encoding="utf-8-sig").read()
    before = text

    text = text.replace(
        "Add-Type -Path (Join-Path $root 'native\\BatteryGuardTray.cs')",
        ROOT_PAIR)
    text = text.replace(
        "Add-Type -Path (Join-Path $PSScriptRoot 'native\\BatteryGuardTray.cs')",
        PS_PAIR)
    text = text.replace(
        "$source = Join-Path $root 'native\\BatteryGuardTray.cs'",
        "$sources = @(\n    (Join-Path $root 'native\\Localization.cs'),\n    (Join-Path $root 'native\\BatteryGuardTray.cs')\n)")
    text = text.replace(
        "$source = Join-Path $PSScriptRoot 'native\\BatteryGuardTray.cs'",
        "$sources = @(\n    (Join-Path $PSScriptRoot 'native\\Localization.cs'),\n    (Join-Path $PSScriptRoot 'native\\BatteryGuardTray.cs')\n)")
    text = text.replace("Add-Type -Path $source", "Add-Type -Path $sources")

    if text != before:
        io.open(path, "w", encoding="utf-8-sig").write(text)
        print("updated", path)
    else:
        print("unchanged", path)
