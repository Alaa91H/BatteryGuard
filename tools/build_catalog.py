import io
import json
import time
import urllib.parse
import urllib.request

SOURCE = "tools/strings.json"
CACHE = "tools/cache_ar_en.json"
OUTPUT = "tools/arabic_en.json"


def translate(text, source="ar", target="en"):
    query = urllib.parse.urlencode({
        "client": "gtx",
        "sl": source,
        "tl": target,
        "dt": "t",
        "q": text,
    })
    url = "https://translate.googleapis.com/translate_a/single?" + query
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=25) as response:
                data = json.loads(response.read().decode("utf-8"))
            return "".join(segment[0] for segment in data[0] if segment and segment[0])
        except Exception:
            if attempt == 3:
                raise
            time.sleep(1.5 * (attempt + 1))


def main():
    entries = json.load(io.open(SOURCE, encoding="utf-8"))
    try:
        cache = json.load(io.open(CACHE, encoding="utf-8"))
    except Exception:
        cache = {}

    result = []
    for index, entry in enumerate(entries):
        arabic = entry["text"]
        if arabic not in cache:
            english = translate(arabic.replace("\\n", "\n")).replace("\r", "")
            cache[arabic] = "\\n".join(english.split("\n")) if "\n" in arabic else english
            if index % 10 == 0:
                io.open(CACHE, "w", encoding="utf-8").write(
                    json.dumps(cache, ensure_ascii=False, indent=2)
                )
            time.sleep(0.12)
        result.append({
            "arabic": arabic,
            "english": cache[arabic],
            "count": entry["count"],
            "lines": entry["lines"],
        })

    io.open(CACHE, "w", encoding="utf-8").write(
        json.dumps(cache, ensure_ascii=False, indent=2)
    )
    io.open(OUTPUT, "w", encoding="utf-8").write(
        json.dumps(result, ensure_ascii=False, indent=2)
    )
    print("entries=%d translated=%d" % (len(result), len(cache)))


if __name__ == "__main__":
    main()
