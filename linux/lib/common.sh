#!/usr/bin/env bash
# Shared helpers for the WSL provisioning modules.
# Sourced by bootstrap.sh - never executed directly.

if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'
    C_INFO=$'\033[36m'
    C_OK=$'\033[32m'
    C_WARN=$'\033[33m'
    C_ERR=$'\033[31m'
else
    C_RESET='' C_INFO='' C_OK='' C_WARN='' C_ERR=''
fi

info() { printf '%s==>%s %s\n' "$C_INFO" "$C_RESET" "$*"; }
ok() { printf '  %s[ok]%s %s\n' "$C_OK" "$C_RESET" "$*"; }
warn() { printf '  %s[warn]%s %s\n' "$C_WARN" "$C_RESET" "$*" >&2; }
err() { printf '  %s[error]%s %s\n' "$C_ERR" "$C_RESET" "$*" >&2; }
die() {
    err "$*"
    exit 1
}

have() { command -v "$1" >/dev/null 2>&1; }

require_root() {
    [[ ${EUID} -eq 0 ]] || die "This provisioner must run as root (wsl -u root, or sudo)."
}

have_systemd() {
    [[ -d /run/systemd/system ]] && have systemctl
}

svc_enable() {
    local unit=$1
    if ! have_systemd; then
        warn "systemd is not PID 1 yet; $unit will start after the distro restart."
        return 0
    fi
    if systemctl enable --now "$unit" >/dev/null 2>&1; then
        ok "service $unit enabled"
    else
        warn "could not enable $unit (check: systemctl status $unit)"
    fi
}

# ---------------------------------------------------------------- apt helpers

APT_UPDATED=0

apt_refresh() {
    [[ ${APT_UPDATED} -eq 1 ]] && return 0
    info "Refreshing APT package lists"
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    APT_UPDATED=1
}

apt_install() {
    [[ $# -gt 0 ]] || return 0
    apt_refresh
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        -o Dpkg::Options::=--force-confdef \
        -o Dpkg::Options::=--force-confold "$@"
}

apt_upgrade() {
    apt_refresh
    info "Upgrading installed packages"
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
        -o Dpkg::Options::=--force-confdef \
        -o Dpkg::Options::=--force-confold
}

# ------------------------------------------------------------ file utilities

backup_file() {
    local file=$1
    [[ -e ${file} ]] || return 0
    cp -a "$file" "${file}.bak.$(date +%Y%m%d%H%M%S)"
}

ensure_line() {
    local file=$1 line=$2
    touch "$file"
    grep -qxF -- "$line" "$file" || printf '%s\n' "$line" >>"$file"
}

# Replaces (or appends) a marked block inside a file, leaving the rest intact.
ensure_managed_block() {
    local file=$1 tag=$2 content=$3
    local begin="# >>> wsl-provision:${tag} >>>"
    local end="# <<< wsl-provision:${tag} <<<"
    local tmp
    touch "$file"
    tmp=$(mktemp)
    awk -v b="$begin" -v e="$end" '
        BEGIN { skip = 0 }
        $0 == b { skip = 1; next }
        $0 == e { skip = 0; next }
        skip == 0 { print }
    ' "$file" >"$tmp"
    printf '%s\n%s\n%s\n' "$begin" "$content" "$end" >>"$tmp"
    cat "$tmp" >"$file"
    rm -f "$tmp"
}

fetch() {
    curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 "$@"
}

fetch_to() {
    local url=$1 dest=$2
    curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 -o "$dest" "$url"
}

run_as_user() {
    local user=$1
    shift
    sudo -u "$user" -H -- bash -lc "$*"
}
