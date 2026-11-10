#!/usr/bin/env bash
# Docker Engine + Compose plugin from the official apt repository.
# Runs natively inside WSL2 (no Docker Desktop required).

install_docker() {
    local conflicts=(docker.io docker-doc docker-compose podman-docker containerd runc)
    local installed=()

    for pkg in "${conflicts[@]}"; do
        if dpkg -s "$pkg" >/dev/null 2>&1; then
            installed+=("$pkg")
        fi
    done
    if [[ ${#installed[@]} -gt 0 ]]; then
        info "Removing conflicting container packages: ${installed[*]}"
        apt-get remove -y "${installed[@]}" >/dev/null
    fi

    # Ubuntu and Debian publish separate Docker repositories.
    local repo_os=$OS_ID
    install -m 0755 -d /etc/apt/keyrings
    if [[ ! -s /etc/apt/keyrings/docker.asc ]]; then
        fetch_to "https://download.docker.com/linux/${repo_os}/gpg" /etc/apt/keyrings/docker.asc ||
            die "could not download the Docker repository key"
        chmod a+r /etc/apt/keyrings/docker.asc
    fi

    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/%s %s stable\n' \
        "$ARCH" "$repo_os" "$OS_CODENAME" >/etc/apt/sources.list.d/docker.list

    APT_UPDATED=0
    info "Installing Docker Engine"
    apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    if [[ ! -f /etc/docker/daemon.json ]]; then
        install -d -m 0755 /etc/docker
        cat >/etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  },
  "features": {
    "buildkit": true
  }
}
EOF
        ok "docker daemon configured with log rotation"
    else
        warn "/etc/docker/daemon.json exists; leaving it untouched"
    fi

    if ! id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx docker; then
        usermod -aG docker "$TARGET_USER"
        ok "user $TARGET_USER added to the docker group (re-login required)"
    fi

    svc_enable docker

    if have_systemd; then
        # Give dockerd a moment to create its socket, then report honestly.
        local i
        for i in 1 2 3 4 5 6 7 8 9 10; do
            docker info >/dev/null 2>&1 && break
            sleep 1
        done
    fi

    if docker info >/dev/null 2>&1; then
        ok "docker $(docker --version | awk '{print $3}' | tr -d ',') / compose $(docker compose version --short 2>/dev/null || echo n/a)"
    else
        warn "docker is installed but the daemon is not responding yet"
    fi
}
