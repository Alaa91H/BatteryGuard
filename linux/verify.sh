#!/usr/bin/env bash
#
# Health check for the provisioned WSL environment.
# Exit code 0 = every required component is healthy, 1 = at least one failure.
#
#   wsl-verify              # human readable
#   wsl-verify --quiet      # only failures + summary (used by the systemd timer)
#   wsl-verify --offline    # skip internet checks

set -uo pipefail

QUIET=0
OFFLINE=0
TARGET_USER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -q | --quiet) QUIET=1; shift ;;
        --offline) OFFLINE=1; shift ;;
        --user) TARGET_USER=${2:?--user needs a value}; shift 2 ;;
        -h | --help)
            echo "Usage: wsl-verify [--quiet] [--offline] [--user NAME]"
            exit 0
            ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

if [[ -z ${TARGET_USER} ]]; then
    if [[ -n ${SUDO_USER:-} && ${SUDO_USER} != root ]]; then
        TARGET_USER=${SUDO_USER}
    elif [[ -r /etc/wsl.conf ]]; then
        TARGET_USER=$(awk -F= '/^[[:space:]]*default[[:space:]]*=/{gsub(/[[:space:]]/, "", $2); print $2; exit}' /etc/wsl.conf)
    fi
    [[ -n ${TARGET_USER} ]] || TARGET_USER=dev
fi

if [[ -t 1 && ${QUIET} -eq 0 ]]; then
    G=$'\033[32m' R=$'\033[31m' Y=$'\033[33m' B=$'\033[1m' N=$'\033[0m'
else
    G='' R='' Y='' B='' N=''
fi

PASS=0
FAIL=0
WARN=0

pass() {
    PASS=$((PASS + 1))
    [[ ${QUIET} -eq 0 ]] && printf '  %s[ok]%s   %s\n' "$G" "$N" "$*"
    return 0
}
fail() {
    FAIL=$((FAIL + 1))
    printf '  %s[FAIL]%s %s\n' "$R" "$N" "$*"
    return 0
}
note() {
    WARN=$((WARN + 1))
    [[ ${QUIET} -eq 0 ]] && printf '  %s[warn]%s %s\n' "$Y" "$N" "$*"
    return 0
}

check() {
    local label=$1
    shift
    if "$@" >/dev/null 2>&1; then pass "$label"; else fail "$label"; fi
}

version_of() {
    "$@" 2>/dev/null | head -n 1
}

[[ ${QUIET} -eq 0 ]] && printf '\n%sWSL environment check%s (user: %s)\n\n' "$B" "$N" "$TARGET_USER"

# ---------------------------------------------------------------- platform
check "Microsoft WSL kernel" grep -qi microsoft /proc/version
check "systemd is PID 1" bash -c '[[ "$(ps -p 1 -o comm=)" == systemd ]]'
check "/etc/wsl.conf enables systemd" grep -qE '^[[:space:]]*systemd[[:space:]]*=[[:space:]]*true' /etc/wsl.conf
check "default user is ${TARGET_USER}" bash -c "awk -F= '/^[[:space:]]*default[[:space:]]*=/{gsub(/[[:space:]]/,\"\",\$2); print \$2}' /etc/wsl.conf | grep -qx '${TARGET_USER}'"
check "C: drive mounted at /mnt/c" test -d /mnt/c/Windows

# ---------------------------------------------------------------- identity
check "sudo group membership" bash -c "id -nG '$TARGET_USER' | tr ' ' '\n' | grep -qx sudo"
if sudo -u "$TARGET_USER" -H sudo -n true >/dev/null 2>&1; then
    pass "passwordless sudo enabled"
else
    note "passwordless sudo is off (valid with --secure-sudo; use a password)"
fi
check "docker group membership" bash -c "id -nG '$TARGET_USER' | tr ' ' '\n' | grep -qx docker"

# ---------------------------------------------------------------- toolchain
[[ ${QUIET} -eq 0 ]] && printf '\n  versions: git %s | node %s | pnpm %s | python %s | go %s\n\n' \
    "$(git --version 2>/dev/null | awk '{print $3}')" \
    "$(node --version 2>/dev/null || echo '-')" \
    "$(pnpm --version 2>/dev/null || echo '-')" \
    "$(python3 --version 2>/dev/null | awk '{print $2}')" \
    "$(go version 2>/dev/null | awk '{print $3}')"

for tool in git curl wget jq rg fdfind batcat tmux htop rsync; do
    check "binary: ${tool}" command -v "$tool"
done

check "node (LTS)" node --version
check "npm" npm --version
check "pnpm" pnpm --version
check "python3" python3 --version
check "pipx" pipx --version
check "uv" uv --version
check "go" bash -c 'command -v go >/dev/null || /usr/local/go/bin/go version >/dev/null'
check "docker CLI" docker --version
check "docker compose plugin" docker compose version
check "docker daemon reachable" docker info

# ---------------------------------------------------------------- environment
check "UTF-8 locale" bash -c 'locale charmap 2>/dev/null | grep -qi utf-8'
check "timezone configured" test -e /etc/localtime
check "inotify watch limit" bash -c '(( $(sysctl -n fs.inotify.max_user_watches) >= 524288 ))'
check "vm.max_map_count" bash -c '(( $(sysctl -n vm.max_map_count) >= 262144 ))'
check "journald size cap" test -f /etc/systemd/journald.conf.d/99-wsl.conf
check "open file limit (soft)" bash -lc '(( $(ulimit -Sn) >= 65535 ))'
check "health timer enabled" systemctl is-enabled wsl-healthcheck.timer
check "health timer active" systemctl is-active wsl-healthcheck.timer

# Optional local Git forge (installed with --with-forge).
if [[ -f /opt/wsl-forgejo/compose.yaml ]]; then
    check "forgejo container running" bash -c '[[ $(docker inspect -f "{{.State.Running}}" forgejo 2>/dev/null) == true ]]'
    check "forgejo responds on localhost:3000" curl -fsS -m 5 -o /dev/null http://127.0.0.1:3000/api/healthz
fi

free_kb=$(df -Pk / | awk 'NR==2 {print $4}')
if [[ ${free_kb:-0} -ge 5242880 ]]; then
    pass "free disk space (>= 5 GB)"
else
    fail "free disk space (${free_kb:-0} KB available, need 5 GB)"
fi

# ---------------------------------------------------------------- network
check "DNS resolution" getent hosts github.com
if [[ ${OFFLINE} -eq 0 ]]; then
    check "HTTPS egress" curl -fsS -m 8 -o /dev/null https://registry.npmjs.org
else
    note "HTTPS egress skipped (--offline)"
fi

# ---------------------------------------------------------------- summary
total=$((PASS + FAIL))
printf '\n  %sSummary:%s %d/%d checks passed, %d failed\n' "$B" "$N" "$PASS" "$total" "$FAIL"

if [[ ${FAIL} -gt 0 ]]; then
    printf '  %sEnvironment is NOT ready.%s See the failures above.\n\n' "$R" "$N"
    result="FAIL"
else
    printf '  %sEnvironment is healthy.%s\n\n' "$G" "$N"
    result="OK"
fi

if [[ -w /var/log ]]; then
    printf '%s user=%s pass=%d fail=%d warn=%d\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TARGET_USER" "$PASS" "$FAIL" "$WARN" \
        >>/var/log/wsl-verify.log 2>/dev/null || true
fi

[[ ${result} == "OK" ]]
