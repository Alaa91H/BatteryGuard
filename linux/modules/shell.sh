#!/usr/bin/env bash
# Shell ergonomics: PATH, aliases, git defaults, optional zsh.

install_shell_env() {
    cat >/etc/profile.d/10-wsl-env.sh <<'EOF'
# Managed by wsl-provision - do not edit, it is regenerated.
export PATH="/usr/local/go/bin:${HOME}/.cargo/bin:${HOME}/.local/bin:${PATH}"
export EDITOR="${EDITOR:-vim}"
export VISUAL="${VISUAL:-$EDITOR}"
export PAGER="${PAGER:-less}"
export LESS="${LESS:--R}"
export HISTCONTROL="ignoreboth"
export HISTSIZE=50000
EOF
    chmod 0644 /etc/profile.d/10-wsl-env.sh

    local bashrc="${TARGET_HOME}/.bashrc"
    ensure_managed_block "$bashrc" "shell" \
        '# ~/.local/bin must win over Windows paths
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) PATH="$HOME/.local/bin:$PATH" ;;
esac
alias ll='"'"'ls -alF --color=auto'"'"'
alias la='"'"'ls -A --color=auto'"'"'
alias gs='"'"'git status -sb'"'"'
alias dc='"'"'docker compose'"'"'
alias ports='"'"'ss -tulpn'"'"'
alias wslip='"'"'ip -4 addr show eth0'"'"''
    chown "$TARGET_USER:$TARGET_USER" "$bashrc"

    if have git; then
        git config --system init.defaultBranch main
        git config --system core.autocrlf input
        git config --system pull.rebase false
        git lfs install --system >/dev/null 2>&1 || true
        ok "git defaults set (main, autocrlf=input, git-lfs)"
    fi

    ok "shell environment configured"
}

install_shell_extras() {
    [[ ${WITH_ZSH} -eq 1 ]] || return 0

    info "Installing zsh"
    apt_install zsh zsh-autosuggestions zsh-syntax-highlighting

    local zshrc="${TARGET_HOME}/.zshrc"
    if [[ ! -f ${zshrc} ]]; then
        cat >"$zshrc" <<'EOF'
# Minimal zsh setup managed by wsl-provision.
autoload -Uz compinit && compinit
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt hist_ignore_dups share_history

source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh 2>/dev/null
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh 2>/dev/null

export PATH="$HOME/.local/bin:$PATH"
export EDITOR="${EDITOR:-vim}"

alias ll='ls -alF --color=auto'
alias gs='git status -sb'
alias dc='docker compose'
EOF
        chown "$TARGET_USER:$TARGET_USER" "$zshrc"
    fi

    if chsh -s /bin/zsh "$TARGET_USER" >/dev/null 2>&1; then
        ok "zsh enabled for $TARGET_USER"
    else
        warn "could not change the login shell to zsh"
    fi
}
