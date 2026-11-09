#!/usr/bin/env bash
# Production profile: unattended security updates, journald caps, time sync,
# optional SSH with key-only auth, and (optionally) fail2ban.

install_prod_base() {
    info "Installing production baseline"
    apt_install unattended-upgrades apt-listchanges logrotate

    cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

    # Security pockets only, so unattended upgrades never pull a new release.
    cat >/etc/apt/apt.conf.d/51wsl-unattended <<'EOF'
Unattended-Upgrade::Origins-Pattern {
        "origin=Ubuntu,archive=${distro_codename}-security";
        "origin=Ubuntu,archive=${distro_codename}-updates";
        "origin=Debian,codename=${distro_codename},label=Debian-Security";
};
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

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
        systemctl enable --now unattended-upgrades >/dev/null 2>&1 ||
            warn "could not enable unattended-upgrades"
    fi

    svc_enable systemd-timesyncd
    ok "unattended security updates, journald cap and NTP configured"
}

install_ssh() {
    info "Installing OpenSSH server"
    apt_install openssh-server

    local port=2222
    local password_auth=yes
    if [[ -s ${TARGET_HOME}/.ssh/authorized_keys ]]; then
        password_auth=no
    else
        warn "no ~/.ssh/authorized_keys for $TARGET_USER yet - password auth left enabled"
    fi

    cat >/etc/ssh/sshd_config.d/99-wsl.conf <<EOF
Port ${port}
PermitRootLogin no
PasswordAuthentication ${password_auth}
KbdInteractiveAuthentication no
PubkeyAuthentication yes
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers ${TARGET_USER}
EOF

    /usr/sbin/sshd -t || die "generated sshd configuration is invalid"
    svc_enable ssh

    ok "sshd on port ${port} (password auth: ${password_auth})"
    if [[ ${password_auth} == yes ]]; then
        warn "add a key: ssh-keygen -t ed25519  then  ssh-copy-id -p ${port} ${TARGET_USER}@localhost"
    fi
}

install_prod_extras() {
    install_prod_base
    if [[ ${WITH_SSH} -eq 1 ]]; then
        install_ssh
    fi
}
