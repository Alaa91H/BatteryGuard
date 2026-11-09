#!/usr/bin/env python3
"""Point build and test scripts at every file in battery/src.

After the Application.cs split there is no single application source file.
Scripts that used to list Localization.cs and Application.cs now enumerate
src/*.cs, so adding a module never requires touching each script again.

Run from the workspace root:
    python tools/update_source_lists.py
"""

import glob
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = sorted(
    glob.glob(os.path.join(ROOT, "battery", "scripts", "*.ps1"))
    + glob.glob(os.path.join(ROOT, "battery", "tests", "*.ps1"))
)

INLINE = re.compile(
    r"(?m)^([ \t]*)Add-Type -Path @\(\(Join-Path \$root "
    r"'src\\Localization\.cs'\), \(Join-Path \$root 'src\\Application\.cs'\)\)(.*)$"
)
ARRAY = re.compile(
    r"\$sources = @\(\r?\n\s*\(Join-Path \$root 'src\\Localization\.cs'\),"
    r"\r?\n\s*\(Join-Path \$root 'src\\Application\.cs'\)\r?\n\)"
)

ENUMERATE = (
    "$sources = @(Get-ChildItem -Path (Join-Path $root 'src') -Filter '*.cs' "
    "| Sort-Object Name | ForEach-Object { $_.FullName })"
)

changed = []
for path in FILES:
    text = open(path, encoding="utf-8-sig", newline="").read()
    newline = "\r\n" if "\r\n" in text else "\n"
    updated = ARRAY.sub(ENUMERATE, text)
    updated = INLINE.sub(
        lambda match: match.group(1)
        + ENUMERATE
        + newline
        + match.group(1)
        + "Add-Type -Path $sources"
        + match.group(2),
        updated,
    )
    if updated != text:
        open(path, "w", encoding="utf-8-sig", newline="").write(updated)
        changed.append(os.path.relpath(path, ROOT))

print("updated:", ", ".join(changed) if changed else "none")
