#!/usr/bin/env bash
#
# Idempotent provisioner for a WSL2 / Ubuntu development and production host.
# Run as root inside the distribution:
#
#   sudo bash /opt/wsl-provision/bootstrap.sh --profile dev
#
# Every module checks before it acts, so re-running is safe and is in fact
# required once after systemd becomes PID 1 (see windows/Provision-Wsl.ps1).

set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

PROFILE="dev"
TARGET_USER=""
TARGET_HOME=""
TIMEZONE="Etc/UTC"
LOCALE_PRIMARY="en_US.UTF-8"
LOCALE_EXTRA="ar_SA.UTF-8"
WSL_HOSTNAME="${WSL_HOSTNAME:-wsl}"
WITH_DOCKER=1
WITH_SSH=0
WITH_DB=0
START_DB=0
WITH_FORGE=0
WITH_GPU=0
WITH_RUST=0
WITH_ZSH=0
DO_UPGRADE=0
SECURE_SUDO=0

OS_ID=""
OS_CODENAME=""
OS_PRETTY=""
ARCH=""

usage() {
    cat <<'EOF'
Usage: bootstrap.sh [options]

Profiles
  --profile dev|prod|full   dev = toolchains + docker (default)
                            prod = hardened base, updates, docker, health timer
                            full = dev + prod

Identity
  --user NAME               Linux account to create/reuse (default: dev)
  --timezone AREA/CITY      IANA timezone (default: Etc/UTC)
  --locale LOCALE           Primary locale (default: en_US.UTF-8)

Components
  --with-ssh                Install OpenSSH server on port 2222
  --with-databases          Write a PostgreSQL + Redis Compose stack
  --start-databases         Start that stack now (implies --with-databases)
  --with-forge              Local Forgejo Git server on http://localhost:3000
  --with-gpu                Install the NVIDIA container toolkit when detected
  --with-rust               Install the Rust toolchain for the target user
  --with-zsh                Install and enable zsh
  --no-docker               Skip Docker Engine
  --upgrade                 Run a full apt upgrade first (slower)
  --secure-sudo             Do not grant passwordless sudo

  -h, --help                Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --profile) PROFILE=${2:?--profile needs a value}; shift 2 ;;
        --user) TARGET_USER=${2:?--user needs a value}; shift 2 ;;
        --timezone) TIMEZONE=${2:?--timezone needs a value}; shift 2 ;;
        --locale) LOCALE_PRIMARY=${2:?--locale needs a value}; shift 2 ;;
        --with-ssh) WITH_SSH=1; shift ;;
        --with-databases) WITH_DB=1; shift ;;
        --start-databases) WITH_DB=1; START_DB=1; shift ;;
        --with-forge) WITH_FORGE=1; shift ;;
        --with-gpu) WITH_GPU=1; shift ;;
        --with-rust) WITH_RUST=1; shift ;;
        --with-zsh) WITH_ZSH=1; shift ;;
        --no-docker) WITH_DOCKER=0; shift ;;
        --upgrade) DO_UPGRADE=1; shift ;;
        --secure-sudo) SECURE_SUDO=1; shift ;;
        -h | --help) usage; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
done

case $PROFILE in
    dev | prod | full) ;;
    *) die "--profile must be one of: dev, prod, full" ;;
esac

if [[ -z ${TARGET_USER} ]]; then
    TARGET_USER=${SUDO_USER:-dev}
    [[ ${TARGET_USER} == root ]] && TARGET_USER=dev
fi
[[ ${TARGET_USER} =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] ||
    die "invalid user name: ${TARGET_USER}"

require_root
trap 'err "provisioning failed near line ${LINENO}"' ERR

for module in "${SCRIPT_DIR}"/modules/*.sh; do
    # shellcheck disable=SC1090
    source "$module"
done

info "WSL provisioning - profile: ${PROFILE}, user: ${TARGET_USER}"
detect_system

if ! grep -qi microsoft /proc/version; then
    warn "not running under a Microsoft kernel; WSL-specific steps are inert"
fi

install_base_packages
create_user
configure_sudo
configure_locales
configure_timezone
write_wsl_conf
install_sysctl
install_limits
configure_journald
install_shell_env
install_shell_extras
install_toolchains_core

if [[ ${WITH_DOCKER} -eq 1 ]]; then
    install_docker
else
    warn "Docker skipped (--no-docker)"
fi

case $PROFILE in
    prod | full) install_prod_extras ;;
esac
case $PROFILE in
    dev | full) install_toolchains_extra ;;
esac

install_gpu
install_databases
install_forgejo
install_healthcheck

info "Provisioning complete"
printf '  %-16s %s\n' \
    "Profile" "$PROFILE" \
    "User" "$TARGET_USER" \
    "Home" "$TARGET_HOME" \
    "Timezone" "$TIMEZONE" \
    "Locale" "$LOCALE_PRIMARY"

if ! have_systemd; then
    echo
    warn "systemd is not PID 1 in this session."
    warn "Restart the distro (wsl --shutdown) and re-run this script, or use"
    warn "windows/Provision-Wsl.ps1 which performs both passes automatically."
fi

echo
info "Verify at any time:  sudo -u ${TARGET_USER} -H wsl-verify"
