#!/usr/bin/env bash
# Language runtimes: Python (+uv), Node LTS (+pnpm), Go, Rust.

install_python() {
    info "Installing Python tooling"
    apt_install python3 python3-venv python3-dev python3-pip pipx

    run_as_user "$TARGET_USER" "pipx ensurepath" >/dev/null 2>&1 || true

    if have uv; then
        ok "uv already installed"
    else
        if fetch https://astral.sh/uv/install.sh |
            env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh >/dev/null 2>&1; then
            ok "uv installed"
        else
            warn "uv download failed; install later with: pipx install uv"
        fi
    fi

    local py
    py=$(python3 --version 2>&1)
    ok "python: $py"
}

install_node() {
    if have node; then
        ok "node already installed ($(node --version))"
    else
        info "Installing Node.js LTS from NodeSource"
        local setup=/tmp/nodesource_setup.sh
        if fetch_to https://deb.nodesource.com/setup_lts.x "$setup"; then
            bash "$setup" >/dev/null 2>&1 || warn "NodeSource setup script reported an error"
            APT_UPDATED=0
            apt_install nodejs || warn "node installation failed"
            rm -f "$setup"
        else
            warn "could not reach deb.nodesource.com; install Node manually"
            return 0
        fi
    fi

    have node || return 0

    if have corepack; then
        corepack enable >/dev/null 2>&1 || true
    fi

    if ! have pnpm; then
        npm install -g pnpm@latest --silent >/dev/null 2>&1 ||
            warn "could not install pnpm globally"
    fi

    run_as_user "$TARGET_USER" "npm config set fund false" >/dev/null 2>&1 || true
    run_as_user "$TARGET_USER" "npm config set update-notifier false" >/dev/null 2>&1 || true

    ok "node $(node --version), npm $(npm --version), pnpm $(pnpm --version 2>/dev/null || echo 'n/a')"
}

install_uv_python() {
    # Optional managed interpreters, only when uv is available.
    have uv || return 0
    run_as_user "$TARGET_USER" "uv python install --quiet 3.12" >/dev/null 2>&1 ||
        warn "uv could not download CPython 3.12 (offline?)"
}

install_go() {
    if have go || [[ -x /usr/local/go/bin/go ]]; then
        ok "go already installed ($(/usr/local/go/bin/go version 2>/dev/null | awk '{print $3}'))"
        return 0
    fi

    info "Installing the latest stable Go"
    local json version url tmp
    if ! json=$(fetch 'https://go.dev/dl/?mode=json'); then
        warn "could not reach go.dev; skipping Go"
        return 0
    fi
    version=$(printf '%s' "$json" | jq -r '[.[] | select(.stable)][0].version // empty')
    if [[ -z ${version} ]]; then
        warn "could not parse the Go release index; skipping Go"
        return 0
    fi

    url="https://go.dev/dl/${version}.linux-${ARCH}.tar.gz"
    tmp=$(mktemp /tmp/go-download.XXXXXX.tar.gz)
    if ! fetch_to "$url" "$tmp"; then
        warn "Go download failed; skipping Go"
        rm -f "$tmp"
        return 0
    fi

    rm -rf /usr/local/go
    install -d -m 0755 /usr/local
    tar -C /usr/local -xzf "$tmp"
    rm -f "$tmp"
    ok "go ${version#go} installed to /usr/local/go"
}

install_rust() {
    [[ ${WITH_RUST} -eq 1 ]] || return 0

    if [[ -x ${TARGET_HOME}/.cargo/bin/rustup ]]; then
        ok "rust already installed"
        return 0
    fi

    info "Installing Rust (minimal profile) for $TARGET_USER"
    if run_as_user "$TARGET_USER" \
        "curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --no-modify-path" \
        >/dev/null 2>&1; then
        ok "rust toolchain installed"
    else
        warn "rustup failed; rerun manually as $TARGET_USER"
    fi
}

install_toolchains_core() {
    install_python
    install_node
}

install_toolchains_extra() {
    install_go
    install_rust
}
