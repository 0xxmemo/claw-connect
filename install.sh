#!/bin/bash
set -e

# Claw Connect — Installer
# Works both locally (from a clone) and remotely (curl | bash).

BIN_NAME="claw-connect"
REPO="https://github.com/0xxmemo/claw-connect.git"
GH_API="https://api.github.com/repos/0xxmemo/claw-connect/releases/latest"
CLONE_DIR="$HOME/.claw-connect"
CONFIG_DIR="$HOME/.config/claw-connect"
COMPLETION_TAG="# claw-connect completions"

echo "Claw Connect — Installer"
echo ""

# ── Resolve latest release tag ────────────────────────────────
resolve_version() {
    # Try GitHub API for latest release tag
    if command -v curl &>/dev/null; then
        curl -fsSL "$GH_API" 2>/dev/null \
            | grep '"tag_name"' | head -1 | cut -d'"' -f4 && return
    elif command -v wget &>/dev/null; then
        wget -qO- "$GH_API" 2>/dev/null \
            | grep '"tag_name"' | head -1 | cut -d'"' -f4 && return
    fi
    # Fallback: query git ls-remote for the latest vX.Y.Z tag
    git ls-remote --tags --sort=-v:refname "$REPO" 'v*' 2>/dev/null \
        | head -1 | sed 's|.*refs/tags/||' | sed 's/\^{}//' && return
    echo ""
}

VERSION="$(resolve_version)"
if [[ -n "$VERSION" ]]; then
    echo "Latest release: $VERSION"
else
    echo "Warning: could not resolve latest release — using main branch"
fi

# ── Clone or update repo ─────────────────────────────────────
# If run via curl-pipe-bash there's no local repo, so clone one.
# If run from an existing clone, use that directory instead.

SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"

if [[ -n "$SCRIPT_SOURCE" && -f "$SCRIPT_SOURCE" ]]; then
    INSTALL_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
else
    # Piped from curl — clone the repo
    INSTALL_DIR="$CLONE_DIR"
fi

if [[ "$INSTALL_DIR" != "$CLONE_DIR" && -f "$INSTALL_DIR/connect.sh" ]]; then
    # Running from an existing local clone — use it as-is
    :
elif [[ -d "$CLONE_DIR/.git" ]]; then
    echo "Updating existing install..."
    git -C "$CLONE_DIR" fetch --tags --quiet
    if [[ -n "$VERSION" ]]; then
        git -C "$CLONE_DIR" checkout --quiet "$VERSION"
    else
        git -C "$CLONE_DIR" pull --ff-only --quiet
    fi
    INSTALL_DIR="$CLONE_DIR"
else
    echo "Cloning repository..."
    if [[ -n "$VERSION" ]]; then
        git clone --quiet --branch "$VERSION" --depth 1 "$REPO" "$CLONE_DIR"
    else
        git clone --quiet --depth 1 "$REPO" "$CLONE_DIR"
    fi
    INSTALL_DIR="$CLONE_DIR"
fi

# Create config directory
mkdir -p "$CONFIG_DIR/profiles"

# Make the main script executable
chmod +x "$INSTALL_DIR/connect.sh"

# ── Symlink ──────────────────────────────────────────────────
install_bin() {
    local target="$1"
    local link="$target/$BIN_NAME"
    mkdir -p "$target" 2>/dev/null || sudo mkdir -p "$target" 2>/dev/null || return 1

    if [[ -L "$link" || -f "$link" ]]; then
        rm -f "$link" 2>/dev/null || sudo rm -f "$link" 2>/dev/null || return 1
    fi
    ln -s "$INSTALL_DIR/connect.sh" "$link" 2>/dev/null || sudo ln -s "$INSTALL_DIR/connect.sh" "$link" 2>/dev/null || return 1
    echo "Installed: $link -> $INSTALL_DIR/connect.sh"
    return 0
}

BIN_INSTALLED=false
if install_bin "/usr/local/bin"; then
    BIN_INSTALLED=true
else
    echo "/usr/local/bin not writable, trying ~/.local/bin..."
    mkdir -p "$HOME/.local/bin"
    if install_bin "$HOME/.local/bin"; then
        BIN_INSTALLED=true
        if ! echo "$PATH" | tr ':' '\n' | grep -qx "$HOME/.local/bin"; then
            echo "Note: ~/.local/bin is not in your PATH."
            echo "  Add this to your shell rc:  export PATH=\"\$HOME/.local/bin:\$PATH\""
        fi
    fi
fi

if [[ "$BIN_INSTALLED" != true ]]; then
    echo "Warning: Could not create symlink. Run with sudo or add $INSTALL_DIR to your PATH."
fi

# ── Shell completions ────────────────────────────────────────
install_completions_rc() {
    local rc_file="$1"
    local shell_type="$2"

    touch "$rc_file"

    if grep -qF "$COMPLETION_TAG" "$rc_file" 2>/dev/null; then
        echo "Completions: already in $(basename "$rc_file")"
        return 0
    fi

    if [[ "$shell_type" == "zsh" ]]; then
        cat >> "$rc_file" << EOF

$COMPLETION_TAG
fpath=("$INSTALL_DIR/completions" \$fpath)
autoload -Uz compinit && compinit -C
EOF
    else
        cat >> "$rc_file" << EOF

$COMPLETION_TAG
[[ -f "$INSTALL_DIR/completions/claw-connect.bash" ]] && source "$INSTALL_DIR/completions/claw-connect.bash"
EOF
    fi

    echo "Completions: added to $(basename "$rc_file")"
}

CURRENT_SHELL="$(basename "${SHELL:-/bin/bash}")"

case "$CURRENT_SHELL" in
    zsh)
        install_completions_rc "$HOME/.zshrc" "zsh"
        ;;
    bash)
        if [[ "$(uname)" == "Darwin" ]]; then
            install_completions_rc "${HOME}/.bash_profile" "bash"
        else
            install_completions_rc "${HOME}/.bashrc" "bash"
        fi
        ;;
    fish)
        fish_dir="$HOME/.config/fish/conf.d"
        mkdir -p "$fish_dir"
        if [[ ! -f "$fish_dir/claw-connect.fish" ]]; then
            cat > "$fish_dir/claw-connect.fish" << 'FISH_EOF'
# claw-connect completions
complete -c claw-connect -f
complete -c claw-connect -n '__fish_use_subcommand' -a 'setup' -d 'Interactive setup wizard'
complete -c claw-connect -n '__fish_use_subcommand' -a 'profiles' -d 'List configured profiles'
complete -c claw-connect -n '__fish_use_subcommand' -s t -l tunnel -d 'SSH tunnel (gateway + VNC browser)'
complete -c claw-connect -n '__fish_use_subcommand' -s v -l vnc -d 'Direct VNC tunnel'
complete -c claw-connect -n '__fish_use_subcommand' -s d -l deploy -d 'Deploy VNC stack to remote'
complete -c claw-connect -n '__fish_use_subcommand' -s r -l resume -d 'Resume tmux session'
complete -c claw-connect -n '__fish_use_subcommand' -s l -l list -d 'List remote tmux sessions'
complete -c claw-connect -n '__fish_use_subcommand' -s k -l kill -d 'Kill tmux session'
complete -c claw-connect -n '__fish_use_subcommand' -s u -l user -d 'Override SSH user'
complete -c claw-connect -n '__fish_use_subcommand' -l init-tmux -d 'Install tmux config on remote'
complete -c claw-connect -n '__fish_use_subcommand' -s p -l profile -d 'Use a named profile'
complete -c claw-connect -n '__fish_use_subcommand' -s h -l help -d 'Show help'
FISH_EOF
            echo "Completions: added fish conf.d/claw-connect.fish"
        else
            echo "Completions: fish already configured"
        fi
        ;;
    *)
        echo "Completions: unsupported shell '$CURRENT_SHELL' — skipping"
        ;;
esac

echo ""
if [[ -n "$VERSION" ]]; then
    echo "Claw Connect $VERSION installed."
else
    echo "Claw Connect installed (from main)."
fi
echo "Run 'claw-connect setup' to configure a server profile."
case "$CURRENT_SHELL" in
    zsh)  echo "Restart your shell (or run 'source ~/.zshrc') for tab completions." ;;
    bash) echo "Restart your shell (or run 'source ~/.bashrc') for tab completions." ;;
    fish) echo "Completions are ready — open a new fish shell." ;;
esac
