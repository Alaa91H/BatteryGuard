import glob
import io
import os
import shutil

ROOT = "battery"


def move(src, dst):
    src = os.path.join(ROOT, src)
    dst = os.path.join(ROOT, dst)
    if not os.path.exists(src):
        return
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if os.path.exists(dst):
        os.remove(dst)
    shutil.move(src, dst)
    print("moved", src, "->", dst)


def main():
    for folder in ("src", "resources", "scripts", "tests"):
        os.makedirs(os.path.join(ROOT, folder), exist_ok=True)

    fixed = [
        ("native/Localization.cs", "src/Localization.cs"),
        ("native/BatteryGuardTray.cs", "src/Application.cs"),
        ("native/app.manifest", "resources/application.manifest"),
        ("native/app.ico", "resources/application.ico"),
        ("Build-Tray.ps1", "scripts/build.ps1"),
        ("Start-BatteryGuardTray.ps1", "scripts/start.ps1"),
        ("Restart-Tray.ps1", "scripts/restart.ps1"),
        ("BatteryGuard.ps1", "scripts/control.ps1"),
        ("Probe-HpBatteryApi.ps1", "scripts/probe-hp-battery.ps1"),
        ("Probe-TrayWmi.ps1", "scripts/probe-tray-wmi.ps1"),
        ("Verify-BatteryGuard.ps1", "tests/verify.ps1"),
        ("BatteryGuardTray.exe", "application.exe"),
        ("BatteryGuard.config.json", "settings.json"),
        ("ui.txt", "interface.ini"),
        ("theme.txt", "theme.ini"),
        ("capacity.txt", "capacity.ini"),
        ("batteryguard.log", "application.log"),
        ("batteryguard.previous.log", "application.previous.log"),
        ("icon-preview.png", "tests/icon-preview.png"),
        ("verify.log", "tests/verify.log"),
    ]
    for src, dst in fixed:
        move(src, dst)

    for path in glob.glob(os.path.join(ROOT, "Test-*.ps1")):
        move(os.path.basename(path), os.path.join("tests", os.path.basename(path)))

    native = os.path.join(ROOT, "native")
    if os.path.isdir(native) and not os.listdir(native):
        os.rmdir(native)

    replacements = [
        ("batteryguard.previous.log", "application.previous.log"),
        ("BatteryGuardTray.exe", "application.exe"),
        ("BatteryGuard.config.json", "settings.json"),
        ("batteryguard.log", "application.log"),
        ("native\\BatteryGuardTray.cs", "src\\Application.cs"),
        ("native\\Localization.cs", "src\\Localization.cs"),
        ("native\\app.manifest", "resources\\application.manifest"),
        ("native\\app.ico", "resources\\application.ico"),
        ("native/BatteryGuardTray.cs", "src/Application.cs"),
        ("native/Localization.cs", "src/Localization.cs"),
        ("native/app.manifest", "resources/application.manifest"),
        ("native/app.ico", "resources/application.ico"),
        ("Start-BatteryGuardTray.ps1", "start.ps1"),
        ("Build-Tray.ps1", "build.ps1"),
        ("Restart-Tray.ps1", "restart.ps1"),
        ("BatteryGuard.ps1", "control.ps1"),
        ("Verify-BatteryGuard.ps1", "verify.ps1"),
        ("Probe-HpBatteryApi.ps1", "probe-hp-battery.ps1"),
        ("Probe-TrayWmi.ps1", "probe-tray-wmi.ps1"),
        ("ui.txt", "interface.ini"),
        ("theme.txt", "theme.ini"),
        ("capacity.txt", "capacity.ini"),
    ]

    for path in glob.glob(os.path.join(ROOT, "**", "*"), recursive=True):
        if not os.path.isfile(path):
            continue
        if path.endswith((".ps1", ".cs", ".md", ".json", ".txt")):
            if os.sep + "locales" + os.sep in path:
                continue
            try:
                text = io.open(path, encoding="utf-8-sig").read()
            except Exception:
                continue
            changed = text
            for before, after in replacements:
                changed = changed.replace(before, after)
            if changed != text:
                io.open(path, "w", encoding="utf-8-sig").write(changed)
                print("updated", path)

    print("restructure complete")


if __name__ == "__main__":
    main()
