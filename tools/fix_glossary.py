import io
import json
import os
from concurrent.futures import ThreadPoolExecutor

import make_locales as mt

OVERRIDES = {
    "Charge limit": "Maximum battery charge level",
    "Charge limit %": "Maximum battery charge level %",
    "Charge control": "Battery charging control",
    "Charge control…": "Battery charging control…",
    "Light theme": "Light appearance theme",
    "Dark theme": "Dark appearance theme",
    "One time window": "One schedule window",
    "Two time windows": "Two schedule windows",
    "Window ": "Schedule time range ",
    " time window": " schedule time range",
    " time windows": " schedule time ranges",
}

ARABIC = {
    "Charge limit": "سقف الشحن",
    "Charge limit %": "سقف الشحن %",
    "Charge control": "التحكم بالشحن",
    "Charge control…": "التحكم بالشحن…",
    "Light theme": "السمة الفاتحة",
    "Dark theme": "السمة الداكنة",
    "One time window": "نافذة زمنية واحدة",
    "Two time windows": "نافذتان زمنيتان",
    "Window ": "نافذة زمنية ",
    " time window": " نافذة زمنية",
    " time windows": " نوافذ زمنية",
}


def update(code):
    path = os.path.join("battery/locales", code + ".json")
    data = json.load(io.open(path, encoding="utf-8"))
    if code == "ar":
        for key, value in ARABIC.items():
            if key in data:
                data[key] = value
    elif code != "en":
        cache = {}
        for key, source in OVERRIDES.items():
            if key not in data:
                continue
            try:
                translated = mt.translate(source, code)
                data[key] = mt.preserve_space(OVERRIDES[key], translated)
            except Exception:
                pass
    io.open(path, "w", encoding="utf-8").write(
        json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True)
    )
    return code


def main():
    codes = [item[0] for item in mt.LANGUAGES]
    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(update, codes))
    print("updated", len(codes), "locales")


if __name__ == "__main__":
    main()
