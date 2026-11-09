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

case "$arch" in
    x64)
        deb_arch=amd64
        rpm_arch=x86_64
        appimage_arch=x86_64
        ;;
    arm64)
        deb_arch=arm64
        rpm_arch=aarch64
        appimage_arch=aarch64
        ;;
    *)
        echo "unsupported Linux architecture: $arch" >&2
        exit 2
        ;;
esac

if [ ! -x "$binary" ]; then
    echo "batteryguard binary is missing or not executable: $binary" >&2
    exit 1
fi

mkdir -p "$out"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
name="BatteryGuard-${version}${suffix}-linux-${arch}"

# Debian package.
deb_root="$work/deb"
install -Dm755 "$binary" "$deb_root/usr/bin/batteryguard"
mkdir -p "$deb_root/DEBIAN"
installed_size="$(du -sk "$deb_root/usr" | awk '{print $1}')"
cat > "$deb_root/DEBIAN/control" <<EOF
Package: batteryguard
Version: ${version}${suffix}
Section: utils
Priority: optional
Architecture: ${deb_arch}
Installed-Size: ${installed_size}
Maintainer: BatteryGuard <batteryguard@users.noreply.github.com>
Homepage: https://github.com/Alaa91H/BatteryGuard
Description: Read-only battery monitor for Windows, Linux and macOS
 BatteryGuard reports battery percentage, voltage, power, health,
 cycles and remaining time from the native platform interface.
EOF
dpkg-deb --build --root-owner-group "$deb_root" "$out/${name}.deb" >/dev/null

# RPM package.
rpm_root="$work/rpm"
mkdir -p "$rpm_root"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
cp "$binary" "$rpm_root/SOURCES/batteryguard"
snapshot="${suffix#-}"
if [ -n "$snapshot" ]; then
    rpm_release="0.1.${snapshot//-/.}"
else
    rpm_release="1"
fi
changelog_date="$(date -u '+%a %b %d %Y')"
cat > "$rpm_root/SPECS/batteryguard.spec" <<EOF
Name: batteryguard
Version: ${version}
Release: ${rpm_release}
Summary: Read-only battery monitor for Windows, Linux and macOS
License: Proprietary
URL: https://github.com/Alaa91H/BatteryGuard
Source0: batteryguard
BuildArch: ${rpm_arch}
AutoReqProv: no

%description
BatteryGuard reports battery percentage, voltage, power, health,
cycles and remaining time from the native platform interface.

%prep

%build

%install
install -Dm755 %{_sourcedir}/batteryguard %{buildroot}%{_bindir}/batteryguard

%files
%{_bindir}/batteryguard

%changelog
* ${changelog_date} BatteryGuard <batteryguard@users.noreply.github.com> - ${version}-${rpm_release}
- Automated release build
EOF
rpmbuild --define "_topdir $rpm_root" \
    --define "_sourcedir $rpm_root/SOURCES" \
    --define "_specdir $rpm_root/SPECS" \
    -bb "$rpm_root/SPECS/batteryguard.spec" >/dev/null
rpm_file="$(find "$rpm_root/RPMS" -type f -name '*.rpm' | head -n 1)"
if [ -z "$rpm_file" ]; then
    echo "rpmbuild produced no RPM" >&2
    exit 1
fi
cp "$rpm_file" "$out/${name}.rpm"

# Portable AppImage.
appdir="$work/AppDir"
install -Dm755 "$binary" "$appdir/usr/bin/batteryguard"
install -Dm644 "packaging/linux/batteryguard.desktop" "$appdir/batteryguard.desktop"
install -Dm644 "packaging/linux/batteryguard.svg" "$appdir/batteryguard.svg"
ln -s batteryguard.svg "$appdir/.DirIcon"
cat > "$appdir/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/bin/batteryguard" "$@"
EOF
chmod 755 "$appdir/AppRun"

tool="$work/appimagetool"
curl -fsSL "https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-${appimage_arch}.AppImage" -o "$tool"
chmod 755 "$tool"
APPIMAGE_EXTRACT_AND_RUN=1 ARCH="$appimage_arch" "$tool" "$appdir" "$out/${name}.AppImage" >/dev/null

printf 'created %s.deb\ncreated %s.rpm\ncreated %s.AppImage\n' "$out/$name" "$out/$name" "$out/$name"
