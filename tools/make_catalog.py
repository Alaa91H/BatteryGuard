import io
import json
import re

SOURCE = "tools/arabic_en.json"
OUTPUT = "tools/catalog.json"

# Terms the first pass translated too literally for a battery UI.
GLOBAL = [
    ("shipping", "charging"),
    ("Shipping", "Charging"),
    ("roof", "ceiling"),
    ("Roof", "Ceiling"),
    ("Courses", "Cycles"),
    ("record", "log"),
    ("Record", "Log"),
    ("natural", "normal"),
    ("Natural", "Normal"),
    ("Residual", "Remaining"),
    ("correct", "health"),
    ("Correct", "Health"),
]

FIXES = {
    "with": "with",
    "cancellation": "Cancel",
    "to": "To",
    "Scheduling": "Schedule",
    "The window conflicts": "Window",
    "discharge": "Discharging",
    "save": "Save",
    "Cap {0}% Resume {1}%": "Ceiling {0}% · Resume {1}%",
    "No record yet.": "No log entries yet.",
    "from": "From",
    "(roof": "(ceiling",
    "(natural)": "(normal)",
    "· Float is enabled": "· Float mode on",
    "— Edit one of them before saving.": "— adjust one before saving.",
    "! Overlapping of scheduling windows": "! Schedule windows overlap",
    ": Normal charging": ": Normal charging",
    "BatteryGuard — log": "BatteryGuard — Log",
    "{0:N0} / {1:N0} mWh {2}% health": "{0:N0} / {1:N0} mWh · Health {2}%",
    "{0}% · Charge the device soon": "{0}% · Charge soon",
    "addition…": "Add…",
    "Show the charging cap number on the icon": "Show the ceiling number on the icon",
    "closing": "Close",
    "Interface orientation": "Interface direction",
    "Alert test": "Test notification",
    "When charging is complete": "Notify when charge reaches",
    "The battery is fully charged": "Battery fully charged",
    "The battery dies even though the charger is connected.": "The battery is draining even though the charger is connected.",
    "Charge control...": "Charge control…",
    "Operating with Windows": "Start with Windows",
    "Alerts": "Notifications",
    "Scheduling is enabled ·": "Schedule on ·",
    "Scheduling is suspended": "Schedule off",
    "Scheduling is suspended.\\nEnable “Enable scheduling” and then add a window.": "Schedule is off.\\nEnable scheduling, then add a window.",
    "The log…": "Log…",
    "Current capacity {0:N0} mWh": "Current capacity {0:N0} mWh",
    "Charging is suspended": "Charging stopped",
    "Residual ≈": "Remaining ≈",
    "to update": "Refresh",
    "Schedule nesting": "Schedule conflict",
    "Overlapping in scheduling": "Schedule conflict",
    "Export the log": "Export log",
    "export…": "Export…",
    "Recharge cap and recharge application": "Apply charge ceiling and resume level",
    "Modify the schedule...": "Edit schedule…",
    "Modify the scheduling window": "Edit schedule window",
    "amendment…": "Edit…",
    "Unable to export:": "Export failed:",
    "The log could not be read.": "Could not read the log.",
    "Unable to read log:": "Could not read the log:",
    "Activate system notifications": "Enable system notifications",
    "Activate scheduling": "Enable scheduling",
    "Auto (System Theme)": "Auto (system theme)",
    "Automatic (depending on the system)": "Automatic (system)",
    "Changes are applied immediately upon saving.": "Changes apply immediately when saved.",
    "Scheduling": "Schedule",
    "Tab {0}-{1}: ceiling {2}%": "Schedule {0}–{1}: ceiling {2}%",
    "Completeness limit (50–100%).": "Full threshold (50–100%).",
    "Decrease limit (5–50%).": "Low threshold (5–50%).",
    "Limit health (40–95%).": "Health threshold (40–95%).",
    "delete": "Delete",
    "Solution for scheduling interference...": "Resolve schedule conflict…",
    "idle": "Idle",
    "exit": "Exit",
    "dark": "Dark",
    "cap {0}% (resume {1}%)": "Ceiling {0}% (resume {1}%)",
    "Charging cap": "Charge ceiling",
    "Charging cap %": "Charge ceiling %",
    "Custom roof…": "Custom ceiling…",
    "Normal charging (no cap)": "Normal charging (no ceiling)",
    "Normal charging inside the window": "Normal charging in this window",
    "Normal charging — no cap": "Normal charging — no ceiling",
    "Charger power · Battery is idle": "Charger power · battery idle",
    "Display {0} of {1} lines · {2}": "Showing {0} of {1} lines · {2}",
    "On electricity": "Plugged in",
    "Longer life — 60% / 55%": "Longevity — 60% / 55%",
    "light": "Light",
    "Under shipment": "Charging",
    "There are no scheduling windows yet.\\nClick “Add…” to create the first window.": "No schedule windows yet.\\nClick “Add…” to create the first one.",
    "No active scheduling window": "No active schedule window",
    "The HP provider did not respond to charge control. You will be retried automatically.": "The HP battery provider did not respond. Retrying automatically.",
    "Single window": "One window",
    "Scheduling windows in order; The first time matching window is the one that is applied.": "Schedule windows are checked in order; the first matching window applies.",
    "Multiple time windows; Each window has an independent ceiling or normal charge.": "Multiple time windows; each has its own ceiling or normal charging.",
    "Sends a push notification to make sure alerts arrive, even if notifications are turned off.": "Sends an immediate notification to verify delivery, even when notifications are off.",
    "Displays the cap number inside the battery icon.": "Show the ceiling number inside the battery icon.",
    "Battery {0}% · {1}": "Battery {0}% · {1}",
    "Not supported": "Unsupported",
}

MINUTE = "\u062f"
HOUR = "\u0633"


def polish(value):
    text = value
    for before, after in GLOBAL:
        text = re.sub(r"\b" + re.escape(before) + r"\b", after, text)
    stripped = text.strip()
    if stripped in FIXES:
        text = FIXES[stripped]
    return text


def main():
    entries = json.load(io.open(SOURCE, encoding="utf-8"))
    result = []
    for entry in entries:
        original = entry["english"]
        leading = original[: len(original) - len(original.lstrip())]
        trailing = original[len(original.rstrip()):]
        fixed = polish(original)
        if original.strip() in (MINUTE, HOUR):
            fixed = " min" if original.strip() == MINUTE else " h"
        elif original.startswith(" ") and original.strip() not in ("س", "د"):
            fixed = " " + fixed.strip()
        if original.endswith(" "):
            fixed = fixed.rstrip() + " "
        result.append({
            "arabic": entry["arabic"],
            "english": fixed,
            "count": entry["count"],
            "lines": entry["lines"],
        })

    io.open(OUTPUT, "w", encoding="utf-8").write(
        json.dumps(result, ensure_ascii=False, indent=2)
    )
    unique = {}
    for item in result:
        unique[item["english"]] = unique.get(item["english"], 0) + 1
    print("entries=%d unique_english=%d" % (len(result), len(unique)))


if __name__ == "__main__":
    main()
