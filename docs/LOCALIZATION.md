# Localization

## Languages

| Code | Language | Direction |
| --- | --- | --- |
| `en` | English | LTR |
| `ar` | العربية | RTL |
| `es` | Español | LTR |
| `fr` | Français | LTR |
| `de` | Deutsch | LTR |
| `pt` | Português | LTR |
| `it` | Italiano | LTR |
| `ru` | Русский | LTR |
| `zh-CN` | 简体中文 | LTR |
| `zh-TW` | 繁體中文 | LTR |
| `ja` | 日本語 | LTR |
| `ko` | 한국어 | LTR |
| `hi` | हिन्दी | LTR |
| `bn` | বাংলা | LTR |
| `ur` | اردو | RTL |
| `fa` | فارسی | RTL |
| `tr` | Türkçe | LTR |
| `nl` | Nederlands | LTR |
| `pl` | Polski | LTR |
| `uk` | Українська | LTR |
| `ro` | Română | LTR |
| `el` | Ελληνικά | LTR |
| `cs` | Čeština | LTR |
| `sv` | Svenska | LTR |
| `da` | Dansk | LTR |
| `fi` | Suomi | LTR |
| `he` | עברית | RTL |
| `th` | ไทย | LTR |
| `vi` | Tiếng Việt | LTR |
| `id` | Bahasa Indonesia | LTR |

## Resolution

`language=` in `interface.ini` accepts `auto` or one of the codes above.

- `auto` uses `CultureInfo.CurrentUICulture` (the Windows display language).
- Chinese is mapped by script/region: Hant/TW/HK/MO → `zh-TW`; other Chinese → `zh-CN`.
- Legacy .NET codes `iw` and `in` normalize to `he` and `id`.
- An unsupported language falls back to English.
- `direction=auto` follows the language; `rtl`/`ltr` override it.

## Catalog format

`locales/<code>.json` is a flat object:

```json
{
  "Save": "حفظ",
  "Battery {0}% · {1}": "البطارية {0}% · {1}"
}
```

Keys are the exact English source strings used in `Loc.T()` or `Loc.F()`. Values are the translation. A missing or empty value falls back to the English key.

English itself is returned directly by `Loc.T`; `en.json` exists for inventory and validation.

## Placeholders

Preserve every placeholder exactly:

- `{0}`, `{1}`, `{2}`
- Format specifiers such as `{0:N0}`
- Literal `%`, `°C`, `mWh` and separators

The maintenance validator compares the placeholder set in each key with its value and reports mismatches.

## Adding a language

1. Add a `LocaleInfo` entry in `src/Localization.cs` with code, native name and RTL flag.
2. Create `locales/<code>.json` with every key from `en.json`.
3. Translate values, preserving placeholders and leading/trailing spaces used by composed labels.
4. Validate keys and placeholders.
5. Build and test at least one right-to-left and one long-text language if the new language is RTL or has long compounds.

## Maintenance utilities

`tools/` contains the one-time and repeatable helpers used for this catalog:

- `make_catalog.py` / `fix_catalog.py` / `refine_catalog.py` — build and refine the English source.
- `make_locales.py` / `make_locales_parallel.py` — generate catalogs and caches.
- `fix_glossary.py` — context-specific re-translation for ambiguous labels.
- `apply_localization.py` — replace Arabic literals with `Loc.T`/`Loc.F`.
- `patch_test_sources.py` / `fix_paths_after_move.py` — one-time repository maintenance.

These utilities are not part of the runtime and require Python 3. Network access is needed only when regenerating catalogs.

## Quality status

The catalogs include the device-state key **Monitoring only** for hardware without charge control. The catalogs are structurally complete: 30 files × 151 keys, zero missing keys and zero placeholder mismatches. They are **machine-generated** from the curated English source with targeted glossary corrections. Native-speaker review is still recommended, particularly for long sentences, HP-specific terminology and languages with strong compound-word conventions (German, Finnish, Hungarian-style constructions).

The most visible terms were corrected explicitly: maximum battery charge level, battery charging control, light/dark appearance theme, schedule window and schedule time range.
