#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="$root/target"
mkdir -p "$target"

rustc --edition=2021 --crate-name batteryguard_core --crate-type=lib "$root/src/lib.rs" --out-dir "$target"
library="$(find "$target" -maxdepth 1 -name '*batteryguard_core*.rlib' | head -n 1)"
if [ -z "$library" ]; then
    echo "rustc did not produce a portable core library" >&2
    exit 1
fi

rustc --edition=2021 --crate-name batteryguard \
    -L "dependency=$target" \
    --extern "batteryguard_core=$library" \
    "$root/src/main.rs" \
    -o "$target/batteryguard"

echo "built $target/batteryguard"
