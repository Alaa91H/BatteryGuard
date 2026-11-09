#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="$root/target"
mkdir -p "$target"

rustc --edition=2021 --test "$root/src/lib.rs" -o "$target/batteryguard_core_tests"
"$target/batteryguard_core_tests"
