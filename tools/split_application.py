#!/usr/bin/env python3
"""One-time split of battery/src/Application.cs into focused modules.

The original file kept every top-level type in one place. This utility groups
the exact source blocks into separate files without editing their contents, so
behavior stays identical. It leaves the original as Application.cs.splitbak
until the build and tests pass.

Run from the workspace root:
    python tools/split_application.py
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "battery", "src")
SOURCE = os.path.join(SRC, "Application.cs")

# Groups follow the requested module boundaries: engine, WMI/battery, settings,
# and dialogs, with the tray shell, native interop, theme and entry point split
# out as well.
GROUPS = {
    "Config.cs": [
        "WindowRule",
        "ScheduleRules",
        "GuardConfig",
        "UiSettings",
        "Autostart",
    ],
    "Wmi.cs": [
        "ChargeMode",
        "IBatteryController",
        "DeviceInfo",
        "GenericBatteryController",
        "HpBios",
        "BatteryControllerFactory",
        "BatteryCapacity",
        "BatteryInfo",
    ],
    "Engine.cs": [
        "Policy",
        "ChargeAction",
        "ChargeDecision",
        "ChargePolicy",
        "Engine",
    ],
    "Theme.cs": [
        "ThemeMode",
        "ThemeSettings",
        "CardPanel",
        "UiTheme",
        "DualRangeSlider",
    ],
    "Dialogs.cs": [
        "UiLayout",
        "WindowRuleForm",
        "SettingsForm",
        "LogForm",
    ],
    "TrayApp.cs": ["TrayApp"],
    "Native.cs": ["Native"],
    "Program.cs": ["Program"],
}

DECLARATION = re.compile(
    r"^    (?:(?:internal|public|private|protected)\s+)?"
    r"(?:(?:static|sealed|abstract|partial)\s+)*"
    r"(?:class|struct|enum|interface|delegate)\s+([A-Za-z_][A-Za-z0-9_]*)"
)


def main():
    raw = open(SOURCE, encoding="utf-8-sig", newline="").read()
    lines = raw.splitlines(keepends=True)
    newline = "\r\n" if "\r\n" in raw else "\n"

    starts = []
    for index, line in enumerate(lines):
        match = DECLARATION.match(line)
        if match:
            starts.append((index, match.group(1)))

    if not starts:
        raise SystemExit("no top-level declarations found")

    namespace_close = max(
        index for index, line in enumerate(lines) if line.strip() == "}"
    )
    header = lines[: starts[0][0]]

    blocks = {}
    for position, (index, name) in enumerate(starts):
        end = starts[position + 1][0] if position + 1 < len(starts) else namespace_close
        if name in blocks:
            raise SystemExit("duplicate top-level declaration: " + name)
        blocks[name] = lines[index:end]

    assigned = []
    for names in GROUPS.values():
        assigned.extend(names)

    missing = sorted(set(blocks) - set(assigned))
    unknown = sorted(set(assigned) - set(blocks))

    if len(assigned) != len(set(assigned)):
        raise SystemExit("a type is assigned to more than one module")

    if missing or unknown:
        raise SystemExit(
            "module map is incomplete; missing=%s unknown=%s" % (missing, unknown)
        )

    written = []
    for filename, names in GROUPS.items():
        body = []
        for name in names:
            body.extend(blocks[name])
        text = "".join(header + body).rstrip("\r\n") + newline + "}" + newline
        target = os.path.join(SRC, filename)
        open(target, "w", encoding="utf-8-sig", newline="").write(text)
        written.append((filename, len(header + body) + 1))

    backup = SOURCE + ".splitbak"
    if os.path.exists(backup):
        os.remove(backup)
    os.replace(SOURCE, backup)

    print("wrote:", ", ".join("%s (%d lines)" % item for item in written))
    print("original kept at:", os.path.basename(backup))


if __name__ == "__main__":
    main()
