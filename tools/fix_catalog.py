import io
import json

PATH = "tools/catalog.json"

FIXES = {
    1: "On battery",
    2: "Plugged in",
    3: " · Health {0}%",
    4: " min",
    5: " with ",
    10: "Window ",
    14: "Charging",
    15: "Normal",
    16: "No log entries yet.",
    18: " (ceiling ",
    19: " (normal)",
    20: " · {0}°C",
    21: " · Float mode on",
    22: " · Ceiling {0}%",
    23: " · Cycles {0}",
    24: " h",
    25: " h ",
    26: " window",
    27: " windows",
    28: " — adjust one before saving.",
    33: "{0:N0} / {1:N0} mWh · Health {2}%",
    37: "°C",
    67: "Schedule on · ",
    69: "Schedule is off.\nEnable scheduling, then add a window.",
    74: "Remaining ≈ ",
    83: "Warning: battery is draining despite the charger",
    104: "Log exported to:\n",
    106: "Schedule ",
    108: "Until full ≈ ",
    122: "Normal charging · ",
    136: "No schedule windows yet.\nClick “Add…” to create the first one.",
    139: "Text file (*.txt)|*.txt|All files (*.*)|*.*",
}


def main():
    entries = json.load(io.open(PATH, encoding="utf-8"))
    for index, english in FIXES.items():
        entries[index]["english"] = english
    io.open(PATH, "w", encoding="utf-8").write(
        json.dumps(entries, ensure_ascii=False, indent=2)
    )
    print("fixed=%d" % len(FIXES))


if __name__ == "__main__":
    main()
