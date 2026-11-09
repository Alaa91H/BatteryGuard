#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 5 ]; then
    echo "usage: $0 <binary> <version> <suffix> <arch> <out-dir>" >&2
    exit 2
fi

binary=$1
version=$2
suffix=$3
arch=$4
out=$5

if [ ! -x "$binary" ]; then
    echo "batteryguard binary is missing or not executable: $binary" >&2
    exit 1
fi

case "$arch" in
    x64|arm64) ;;
    *)
        echo "unsupported macOS architecture: $arch" >&2
        exit 2
        ;;
esac

mkdir -p "$out"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
stage="$work/root"
mkdir -p "$stage/usr/local/bin"
cp "$binary" "$stage/usr/local/bin/batteryguard"
chmod 755 "$stage/usr/local/bin/batteryguard"

name="BatteryGuard-${version}${suffix}-macos-${arch}.pkg"
pkgbuild \
    --root "$stage" \
    --identifier "com.batteryguard.cli.${arch}" \
    --version "$version" \
    --install-location "/" \
    --ownership recommended \
    "$out/$name"

printf 'created %s\n' "$out/$name"
