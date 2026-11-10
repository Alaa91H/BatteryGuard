#!/usr/bin/env bash
# Optional: NVIDIA GPU passthrough for containers.

install_gpu() {
    [[ ${WITH_GPU} -eq 1 ]] || return 0

    if [[ ! -e /usr/lib/wsl/lib/libcuda.so.1 ]] && ! have nvidia-smi; then
        warn "no WSL GPU detected (missing /usr/lib/wsl/lib/libcuda.so.1) - skipping"
        warn "install a recent Windows NVIDIA driver with WSL support first"
        return 0
    fi

    info "Installing the NVIDIA container toolkit"
    install -m 0755 -d /usr/share/keyrings
    if ! fetch https://nvidia.github.io/libnvidia-container/gpgkey |
        gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg 2>/dev/null; then
        warn "could not fetch the NVIDIA repository key"
        return 0
    fi

    fetch https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list |
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
            >/etc/apt/sources.list.d/nvidia-container-toolkit.list

    APT_UPDATED=0
    apt_install nvidia-container-toolkit || {
        warn "nvidia-container-toolkit install failed"
        return 0
    }

    if have nvidia-ctk && have_systemd; then
        nvidia-ctk runtime configure --runtime=docker >/dev/null 2>&1 || true
        systemctl restart docker >/dev/null 2>&1 || true
        ok "docker GPU runtime configured"
    fi
}
