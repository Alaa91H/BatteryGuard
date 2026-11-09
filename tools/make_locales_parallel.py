import io
import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

import make_locales as base


def is_complete(path, expected):
    try:
        data = json.load(io.open(path, encoding="utf-8"))
        return len(data) >= expected
    except Exception:
        return False


def main():
    entries = json.load(io.open(base.CATALOG, encoding="utf-8"))
    english = []
    arabic = {}
    for item in entries:
        value = item["english"]
        if value not in english:
            english.append(value)
        arabic.setdefault(value, item["arabic"])

    os.makedirs(base.OUT_DIR, exist_ok=True)
    os.makedirs(base.CACHE_DIR, exist_ok=True)

    def build(language):
        code, native, rtl = language
        target = os.path.join(base.OUT_DIR, code + ".json")
        if code in ("en", "ar"):
            return code + ": ready"
        if is_complete(target, len(english)):
            return code + ": skipped"

        cache_path = os.path.join(base.CACHE_DIR, code + ".json")
        try:
            cache = json.load(io.open(cache_path, encoding="utf-8"))
        except Exception:
            cache = {}

        base.translate_many(english, code, cache)
        io.open(cache_path, "w", encoding="utf-8").write(
            json.dumps(cache, ensure_ascii=False, indent=2)
        )
        data = {item: cache.get(item, item) for item in english}
        io.open(target, "w", encoding="utf-8").write(
            json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True)
        )
        return code + ": done"

    pending = [item for item in base.LANGUAGES if item[0] not in ("en", "ar")]
    with ThreadPoolExecutor(max_workers=4) as pool:
        futures = [pool.submit(build, item) for item in pending if not is_complete(
            os.path.join(base.OUT_DIR, item[0] + ".json"), len(english))]
        for future in as_completed(futures):
            try:
                print(future.result(), flush=True)
            except Exception as exc:
                print("ERROR:", exc, flush=True)
    print("DONE", flush=True)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
