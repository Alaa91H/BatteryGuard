import io
import json
import re

PATH = "tools/catalog.json"


def refine(text):
    value = text
    # "Ceiling" is a literal roof in many languages; "limit" is the battery meaning.
    value = re.sub(r"\bCeiling\b", "Limit", value)
    value = re.sub(r"\bceiling\b", "limit", value)
    # Schedule windows are time ranges, not OS windows.
    value = re.sub(r"(?<!time )\bwindows\b", "time windows", value)
    value = re.sub(r"(?<!time )\bwindow\b", "time window", value)
    value = value.replace("Time window ", "Time window ")
    value = value.replace("One window", "One time window")
    value = value.replace("Two windows", "Two time windows")
    value = value.replace("Schedule windows", "Schedule time windows")
    value = value.replace("No schedule windows", "No schedule time windows")
    # "Log" as a verb is wrong in several languages.
    value = value.replace("BatteryGuard — Log", "BatteryGuard — Activity log")
    value = value.replace("Log…", "Activity log…")
    value = value.replace("Log exported to", "Activity log exported to")
    value = value.replace("Export log", "Export activity log")
    value = value.replace("No log entries", "No activity log entries")
    value = value.replace("Could not read the log", "Could not read the activity log")
    value = value.replace("The log could not be read", "The activity log could not be read")
    value = value.replace("the log", "the activity log")
    value = value.replace("The log", "The activity log")
    # Theme names need the noun so they are not translated as illumination.
    value = re.sub(r"\bLight\b", "Light theme", value)
    value = re.sub(r"\bDark\b", "Dark theme", value)
    # Windows here is the OS, but "start with" is a verb in some languages.
    value = value.replace("Start with Windows", "Launch at startup")
    # Standalone health means battery health.
    value = value.replace("· Health {0}%", "· Battery health {0}%")
    value = value.replace("Health {0}%", "Battery health {0}%")
    # Normal is an adjective that inflects badly as a fragment.
    value = re.sub(r"\bNormal charging\b", "Standard charging", value)
    value = re.sub(r"\bnormal charging\b", "standard charging", value)
    value = re.sub(r"\bNormal\b", "Standard", value)
    value = re.sub(r"\bnormal\b", "standard", value)
    return value


def main():
    entries = json.load(io.open(PATH, encoding="utf-8"))
    for item in entries:
        item["english"] = refine(item["english"])
    io.open(PATH, "w", encoding="utf-8").write(
        json.dumps(entries, ensure_ascii=False, indent=2)
    )
    print("refined=%d" % len(entries))


if __name__ == "__main__":
    main()
