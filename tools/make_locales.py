import io
import json
import os
import re
import time
import urllib.parse
import urllib.request

CATALOG = "tools/catalog.json"
OUT_DIR = "battery/locales"
CACHE_DIR = "tools/locale_cache"

LANGUAGES = [
    ("en", "English", False),
    ("ar", "العربية", True),
    ("es", "Español", False),
    ("fr", "Français", False),
    ("de", "Deutsch", False),
    ("pt", "Português", False),
    ("it", "Italiano", False),
    ("ru", "Русский", False),
    ("zh-CN", "简体中文", False),
    ("zh-TW", "繁體中文", False),
    ("ja", "日本語", False),
    ("ko", "한국어", False),
    ("hi", "हिन्दी", False),
    ("bn", "বাংলা", False),
    ("ur", "اردو", True),
    ("fa", "فارسی", True),
    ("tr", "Türkçe", False),
    ("nl", "Nederlands", False),
    ("pl", "Polski", False),
    ("uk", "Українська", False),
    ("ro", "Română", False),
    ("el", "Ελληνικά", False),
    ("cs", "Čeština", False),
    ("sv", "Svenska", False),
    ("da", "Dansk", False),
    ("fi", "Suomi", False),
    ("he", "עברית", True),
    ("th", "ไทย", False),
    ("vi", "Tiếng Việt", False),
    ("id", "Bahasa Indonesia", False),
]

PLACEHOLDER = re.compile(r"\{[0-9]+(?::[^}]*)?\}")


def translate(text, target, source="en"):
    query = urllib.parse.urlencode({
        "client": "gtx",
        "sl": source,
        "tl": target,
        "dt": "t",
        "q": text,
    })
    url = "https://translate.googleapis.com/translate_a/single?" + query
    for attempt in range(5):
        try:
            with urllib.request.urlopen(url, timeout=30) as response:
                data = json.loads(response.read().decode("utf-8"))
            return "".join(segment[0] for segment in data[0] if segment and segment[0])
        except Exception:
            if attempt == 4:
                raise
            time.sleep(1.5 * (attempt + 1))


def preserve_space(english, translated):
    lead = english[: len(english) - len(english.lstrip())]
    trail = english[len(english.rstrip()):]
    return lead + translated.strip() + trail


def translate_text(english, code, cache):
    if english in cache:
        return cache[english]
    if "\n" in english:
        parts = english.split("\n")
        translated = "\n".join(translate(part, code) if part else "" for part in parts)
    else:
        translated = translate(english, code)
    translated = preserve_space(english, translated)
    if sorted(PLACEHOLDER.findall(english)) != sorted(PLACEHOLDER.findall(translated)):
        translated = english
    cache[english] = translated
    return translated


def translate_many(strings, code, cache):
    missing = [item for item in strings if item not in cache and "\n" not in item]
    for start in range(0, len(missing), 18):
        batch = missing[start:start + 18]
        try:
            output = translate("\n".join(batch), code)
            lines = output.split("\n")
            if len(lines) == len(batch):
                for english, translated in zip(batch, lines):
                    fixed = preserve_space(english, translated)
                    if sorted(PLACEHOLDER.findall(english)) == sorted(PLACEHOLDER.findall(fixed)):
                        cache[english] = fixed
        except Exception:
            pass
        time.sleep(0.15)
    for english in strings:
        if english not in cache:
            try:
                translate_text(english, code, cache)
            except Exception:
                cache[english] = english
            time.sleep(0.08)


def main():
    entries = json.load(io.open(CATALOG, encoding="utf-8"))
    english = []
    arabic = {}
    for item in entries:
        value = item["english"]
        if value not in english:
            english.append(value)
        arabic.setdefault(value, item["arabic"])

    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(CACHE_DIR, exist_ok=True)

    for code, native, rtl in LANGUAGES:
        target = os.path.join(OUT_DIR, code + ".json")
        if code == "en":
            data = {item: item for item in english}
            io.open(target, "w", encoding="utf-8").write(
                json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True)
            )
            print("%s: english" % code)
            continue
        if code == "ar":
            data = {item: arabic.get(item, item) for item in english}
            io.open(target, "w", encoding="utf-8").write(
                json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True)
            )
            print("%s: source arabic" % code)
            continue

        cache_path = os.path.join(CACHE_DIR, code + ".json")
        try:
            cache = json.load(io.open(cache_path, encoding="utf-8"))
        except Exception:
            cache = {}

        translate_many(english, code, cache)
        io.open(cache_path, "w", encoding="utf-8").write(
            json.dumps(cache, ensure_ascii=False, indent=2)
        )
        data = {item: cache.get(item, item) for item in english}
        io.open(target, "w", encoding="utf-8").write(
            json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True)
        )
        print("%s: %s (%d/%d)" % (code, native, sum(1 for v in data.values() if v), len(english)))


if __name__ == "__main__":
    main()
