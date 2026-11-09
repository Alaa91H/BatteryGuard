import io
import json
import re

CATALOG = "tools/catalog.json"
SOURCE = "battery/native/BatteryGuardTray.cs"
LITERAL = re.compile(r'"(?:\\.|[^"\\])*"')
ARABIC = re.compile(r"[\u0600-\u06ff]")
ESCAPES = {"n": "\n", "r": "\r", "t": "\t", "\\": "\\", '"': '"', "0": "\0"}


def decode_csharp(text):
    out = []
    index = 0
    while index < len(text):
        char = text[index]
        if char == "\\" and index + 1 < len(text):
            code = text[index + 1]
            if code == "u" and index + 5 < len(text):
                out.append(chr(int(text[index + 2:index + 6], 16)))
                index += 6
                continue
            out.append(ESCAPES.get(code, code))
            index += 2
            continue
        out.append(char)
        index += 1
    return "".join(out)


def encode_csharp(text):
    result = []
    for char in text:
        if char == "\\":
            result.append("\\\\")
        elif char == '"':
            result.append('\\"')
        elif char == "\n":
            result.append("\\n")
        elif char == "\r":
            result.append("\\r")
        elif char == "\t":
            result.append("\\t")
        else:
            result.append(char)
    return '"' + "".join(result) + '"'


def main():
    entries = json.load(io.open(CATALOG, encoding="utf-8"))
    catalog = {}
    for item in entries:
        catalog[item["arabic"]] = item["english"]

    source = io.open(SOURCE, encoding="utf-8").read()
    replaced = 0
    misses = []

    def substitute(match):
        nonlocal replaced
        literal = match.group(0)
        raw = literal[1:-1]
        decoded = decode_csharp(raw)
        if not ARABIC.search(decoded):
            return literal
        english = catalog.get(decoded)
        if english is None:
            misses.append(decoded)
            return literal
        replaced += 1
        return "Loc.T(" + encode_csharp(english) + ")"

    output = LITERAL.sub(substitute, source)
    io.open(SOURCE, "w", encoding="utf-8").write(output)

    remaining = []
    for match in LITERAL.finditer(output):
        decoded = decode_csharp(match.group(0)[1:-1])
        if ARABIC.search(decoded):
            remaining.append(decoded)

    print("replaced=%d missing=%d remaining=%d" % (replaced, len(misses), len(remaining)))
    for item in misses:
        print("MISS:", item.replace("\n", "\\n"))
    for item in remaining:
        print("LEFT:", item.replace("\n", "\\n"))


if __name__ == "__main__":
    main()
