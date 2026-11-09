import glob
import io
import os

for path in glob.glob("battery/tests/*.ps1"):
    text = io.open(path, encoding="utf-8-sig").read()
    if "$root = Split-Path -Parent $PSScriptRoot" not in text:
        for old in ("$ErrorActionPreference = 'Stop'", "$ErrorActionPreference = 'Continue'"):
            if old in text:
                text = text.replace(old, old + "\n$root = Split-Path -Parent $PSScriptRoot", 1)
                break
        io.open(path, "w", encoding="utf-8-sig").write(text)
        print("root added", path)

path = "battery/scripts/control.ps1"
text = io.open(path, encoding="utf-8-sig").read()
text = text.replace(
    "$scriptDirectory = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }\nif ([string]::IsNullOrEmpty($ConfigPath)) { $ConfigPath = Join-Path $scriptDirectory 'settings.json' }\nif ([string]::IsNullOrEmpty($LogPath)) { $LogPath = Join-Path $scriptDirectory 'application.log' }",
    "$scriptDirectory = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }\n$root = Split-Path -Parent $scriptDirectory\nif ([string]::IsNullOrEmpty($ConfigPath)) { $ConfigPath = Join-Path $root 'settings.json' }\nif ([string]::IsNullOrEmpty($LogPath)) { $LogPath = Join-Path $root 'application.log' }")
text = text.replace("Settings live in settings.json next to this script", "Settings live in settings.json at the project root")
text = text.replace("Defaults to settings.json next to this script.", "Defaults to settings.json at the project root.")
text = text.replace("Defaults to application.log next to this script.", "Defaults to application.log at the project root.")
io.open(path, "w", encoding="utf-8-sig").write(text)
print("control paths fixed")

# Test-Tray and Test-TrayHost use the repository root for the shared log.
for path in ("battery/tests/Test-Tray.ps1", "battery/tests/Test-TrayHost.ps1"):
    text = io.open(path, encoding="utf-8-sig").read()
    if "$root = Split-Path -Parent $PSScriptRoot" not in text:
        text = text.replace("$ErrorActionPreference = 'Continue'",
                            "$ErrorActionPreference = 'Continue'\n$root = Split-Path -Parent $PSScriptRoot", 1)
    text = text.replace("$trayLog = Join-Path $PSScriptRoot 'application.log'",
                        "$trayLog = Join-Path $root 'application.log'")
    text = text.replace("$trayLog = Join-Path $PSScriptRoot 'application.log'",
                        "$trayLog = Join-Path $root 'application.log'")
    io.open(path, "w", encoding="utf-8-sig").write(text)
    print("tray root fixed", path)
