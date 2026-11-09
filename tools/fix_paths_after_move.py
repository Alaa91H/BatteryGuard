import glob
import io
import os

TESTS = "battery/tests"
SCRIPTS = "battery/scripts"


def read(path):
    return io.open(path, encoding="utf-8-sig").read()


def write(path, text):
    io.open(path, "w", encoding="utf-8-sig").write(text)


for path in glob.glob(os.path.join(TESTS, "*.ps1")):
    text = read(path)
    text = text.replace("$root = $PSScriptRoot", "$root = Split-Path -Parent $PSScriptRoot")
    if "$root = Split-Path -Parent $PSScriptRoot" not in text:
        text = text.replace("$ErrorActionPreference = 'Stop'",
                            "$ErrorActionPreference = 'Stop'\n$root = Split-Path -Parent $PSScriptRoot", 1)
    text = text.replace("Join-Path $PSScriptRoot 'src\\", "Join-Path $root 'src\\")
    text = text.replace("$env:BATTERYGUARD_HOME = $PSScriptRoot", "$env:BATTERYGUARD_HOME = $root")
    text = text.replace("Join-Path $PSScriptRoot 'start.ps1'", "Join-Path $root 'scripts\\start.ps1'")
    text = text.replace("Join-Path $PSScriptRoot 'control.ps1'", "Join-Path $root 'scripts\\control.ps1'")
    text = text.replace("Join-Path $PSScriptRoot 'theme.ini'", "Join-Path $root 'theme.ini'")
    text = text.replace("Join-Path $PSScriptRoot 'interface.ini'", "Join-Path $root 'interface.ini'")
    text = text.replace("Join-Path $PSScriptRoot 'application.log'", "Join-Path $root 'application.log'")
    text = text.replace("Join-Path $PSScriptRoot 'application.exe'", "Join-Path $root 'application.exe'")
    text = text.replace("Join-Path $PSScriptRoot 'settings.json'", "Join-Path $root 'settings.json'")
    text = text.replace("Join-Path $PSScriptRoot 'start.ps1'", "Join-Path $root 'scripts\\start.ps1'")
    write(path, text)
    print("fixed", path)

build = os.path.join(SCRIPTS, "build.ps1")
text = read(build).replace("$root = $PSScriptRoot", "$root = Split-Path -Parent $PSScriptRoot")
write(build, text)
print("fixed", build)

restart = os.path.join(SCRIPTS, "restart.ps1")
text = read(restart)
text = text.replace("$ErrorActionPreference = 'Continue'",
                    "$ErrorActionPreference = 'Continue'\n$root = Split-Path -Parent $PSScriptRoot")
text = text.replace("$log = Join-Path $PSScriptRoot 'application.log'", "$log = Join-Path $root 'application.log'")
text = text.replace("$_.CommandLine -like '*start.ps1*'", "$_.CommandLine -like ('*' + $launcher + '*')")
write(restart, text)
print("fixed", restart)

start = os.path.join(SCRIPTS, "start.ps1")
text = read(start).replace("BatteryGuardTray.cs", "Application.cs")
write(start, text)
print("fixed", start)
