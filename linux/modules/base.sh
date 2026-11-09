#!/usr/bin/env bash
# Base layer: OS detection, user, locales, kernel tuning, host config.

detect_system() {
    [[ -r /etc/os-release ]] || die "/etc/os-release is missing - unsupported image."
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID=${ID:-unknown}
    OS_CODENAME=${VERSION_CODENAME:-}
    OS_PRETTY=${PRETTY_NAME:-$OS_ID}
    ARCH=$(dpkg --print-architecture)

    case $OS_ID in
        ubuntu | debian) ;;
        *) die "Only Ubuntu/Debian are supported (found: $OS_ID)." ;;
    esac
    [[ -n ${OS_CODENAME} ]] || die "VERSION_CODENAME not found in /etc/os-release."
    ok "$OS_PRETTY ($ARCH)"
}

create_user() {
    if id "$TARGET_USER" >/dev/null 2>&1; then
        ok "user $TARGET_USER already exists"
    else
        info "Creating Linux user $TARGET_USER"
        useradd --create-home --user-group --shell /bin/bash --groups sudo "$TARGET_USER"
        # The account stays password-locked; WSL enters it directly and sudo is
        # configured below. This prevents empty-password logins over SSH.
        passwd -l "$TARGET_USER" >/dev/null 2>&1 || true
        ok "user $TARGET_USER created"
    fi

    if ! id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx sudo; then
        usermod -aG sudo "$TARGET_USER"
    fi

    TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    [[ -d ${TARGET_HOME} ]] || die "home directory for $TARGET_USER is missing"
}

configure_sudo() {
    local file="/etc/sudoers.d/90-wsl-${TARGET_USER}"

    if [[ ${SECURE_SUDO} -eq 1 ]]; then
        rm -f "$file"
        warn "passwordless sudo disabled; set a password with: sudo passwd $TARGET_USER"
        return 0
    fi

    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$TARGET_USER" >"$file"
    chmod 0440 "$file"
    visudo -cf "$file" >/dev/null || die "generated sudoers file is invalid"
    ok "passwordless sudo for $TARGET_USER (use --secure-sudo to disable)"
}

configure_timezone() {
    if [[ ! -e "/usr/share/zoneinfo/${TIMEZONE}" ]]; then
        warn "unknown timezone ${TIMEZONE}; keeping the current one"
        return 0
    fi
    ln -snf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
    printf '%s\n' "$TIMEZONE" >/etc/timezone
    if have dpkg-reconfigure; then
        dpkg-reconfigure -f noninteractive tzdata >/dev/null 2>&1 || true
    fi
    ok "timezone ${TIMEZONE}"
}

configure_locales() {
    local generated=0

    # locale-gen accepts explicit locale names and is idempotent.
    if locale-gen "$LOCALE_PRIMARY" "$LOCALE_EXTRA" >/dev/null 2>&1; then
        generated=1
    fi
    if [[ ${generated} -eq 0 ]]; then
        warn "locale-gen failed for $LOCALE_PRIMARY / $LOCALE_EXTRA"
        return 0
    fi

    update-locale LANG="$LOCALE_PRIMARY" >/dev/null 2>&1 || true
    ok "locales: $LOCALE_PRIMARY, $LOCALE_EXTRA"
}

write_wsl_conf() {
    local conf=/etc/wsl.conf
    local rendered
    rendered=$(mktemp)

    sed -e "s|@USER@|${TARGET_USER}|g" \
        -e "s|@HOSTNAME@|${WSL_HOSTNAME}|g" \
        "${SCRIPT_DIR}/config/wsl.conf.template" >"$rendered"

    if [[ -f ${conf} ]] && cmp -s "$rendered" "$conf"; then
        rm -f "$rendered"
        ok "/etc/wsl.conf already up to date"
        return 0
    fi

    if [[ -f ${conf} ]]; then
        backup_file "$conf"
    fi
    install -m 0644 "$rendered" "$conf"
    rm -f "$rendered"
    ok "/etc/wsl.conf written (systemd=true, default user ${TARGET_USER})"
}

install_sysctl() {
    install -m 0644 "${SCRIPT_DIR}/config/99-wsl-sysctl.conf" /etc/sysctl.d/99-wsl-sysctl.conf
    if have sysctl; then
        sysctl --system >/dev/null 2>&1 || warn "some sysctl keys could not be applied"
    fi
    ok "kernel tuning applied (inotify, map_count, somaxconn)"
}

install_limits() {
    install -m 0644 "${SCRIPT_DIR}/config/99-wsl-limits.conf" /etc/security/limits.d/99-wsl-limits.conf

    # WSL's init starts sessions without PAM, so pam_limits never runs.
    # Raise the soft limit from the login profile instead (hard limit is 1048576).
    cat >/etc/profile.d/99-wsl-limits.sh <<'EOF'
# Managed by wsl-provision
ulimit -n 65535 2>/dev/null || true
EOF
    chmod 0644 /etc/profile.d/99-wsl-limits.sh
    ok "file descriptor limits raised (limits.d + login profile)"
}

install_base_packages() {
    local packages=(
        ca-certificates openssl curl wget gnupg lsb-release apt-transport-https
        software-properties-common
        build-essential pkg-config make cmake git git-lfs openssh-client
        unzip zip tar xz-utils zstd jq tree less nano vim
        locales tzdata sudo bash-completion man-db file
        ripgrep fd-find fzf bat htop btop tmux ncdu rsync
        net-tools dnsutils iputils-ping iproute2 lsof strace sysstat iotop
        shellcheck direnv sqlite3 dos2unix
    )

    if [[ ${DO_UPGRADE} -eq 1 ]]; then
        apt_upgrade
    fi

    info "Installing base packages"
    apt_install "${packages[@]}"
    ok "base packages installed"
}

configure_journald() {
    install -d -m 0755 /etc/systemd/journald.conf.d
    cat >/etc/systemd/journald.conf.d/99-wsl.conf <<'EOF'
[Journal]
SystemMaxUse=500M
SystemMaxFileSize=50M
RuntimeMaxUse=100M
ForwardToSyslog=no
EOF

    if have_systemd; then
        systemctl restart systemd-journald >/dev/null 2>&1 || true
    fi
    ok "journald capped at 500M"
}

install_healthcheck() {
    install -d -m 0755 /usr/local/bin
    install -m 0755 "${SCRIPT_DIR}/verify.sh" /usr/local/bin/wsl-verify
    install -m 0644 "${SCRIPT_DIR}/systemd/wsl-healthcheck.service" /etc/systemd/system/wsl-healthcheck.service
    install -m 0644 "${SCRIPT_DIR}/systemd/wsl-healthcheck.timer" /etc/systemd/system/wsl-healthcheck.timer

    if have_systemd; then
        systemctl daemon-reload
        systemctl enable --now wsl-healthcheck.timer >/dev/null 2>&1 ||
            warn "could not enable wsl-healthcheck.timer"
        ok "wsl-healthcheck.timer active (every 6h, journal: wsl-healthcheck)"
    else
        warn "health timer installed; it activates after the distro restart."
    fi
}
