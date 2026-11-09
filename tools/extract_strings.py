import io
import json
import re

path = "battery/native/BatteryGuardTray.cs"
text = io.open(path, encoding="utf-8-sig").read()
pattern = re.compile(r'"(?:[^"\\]|\\.)*"')
items = []
for match in pattern.finditer(text):
    raw = match.group(0)[1:-1]
    if re.search(r"[\u0600-\u06FF]", raw):
        line = text.count("\n", 0, match.start()) + 1
        items.append((line, raw))

seen = {}
for line, value in items:
    entry = seen.setdefault(value, {"text": value, "count": 0, "lines": []})
    entry["count"] += 1
    entry["lines"].append(line)

ordered = sorted(seen.values(), key=lambda item: (-item["count"], item["text"]))
with io.open("tools/strings.json", "w", encoding="utf-8") as handle:
    json.dump(ordered, handle, ensure_ascii=False, indent=2)

for entry in ordered:
    print("%2d %s" % (entry["count"], entry["text"]))
print("---")
print("occurrences=%d distinct=%d" % (len(items), len(ordered)))
