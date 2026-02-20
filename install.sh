#!/bin/bash
set -euo pipefail

REPO_URL="https://github.com/0xxmemo/claw-connect.git"
INSTALL_DIR="${1:-$HOME/claw-connect}"

echo "Installing claw-connect to $INSTALL_DIR..."

if [[ -d "$INSTALL_DIR/.git" ]]; then
  echo "Updating existing installation..."
  git -C "$INSTALL_DIR" pull --ff-only
else
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

chmod +x "$INSTALL_DIR/connect.sh"

# Symlink to PATH
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
ln -sf "$INSTALL_DIR/connect.sh" "$BIN_DIR/claw-connect"

# Install bash completions
if [[ -d "$HOME/.bash_completion.d" ]] || mkdir -p "$HOME/.bash_completion.d"; then
  cp "$INSTALL_DIR/completions/claw-connect.bash" "$HOME/.bash_completion.d/claw-connect"
  echo "  Bash completions installed to ~/.bash_completion.d/"
fi

# Install zsh completions
ZSH_COMP_DIR="${ZDOTDIR:-$HOME}/.zfunc"
if command -v zsh &>/dev/null; then
  mkdir -p "$ZSH_COMP_DIR"
  cp "$INSTALL_DIR/completions/_claw-connect" "$ZSH_COMP_DIR/_claw-connect"
  echo "  Zsh completions installed to $ZSH_COMP_DIR/"
  if ! grep -q 'fpath.*\.zfunc' "${ZDOTDIR:-$HOME}/.zshrc" 2>/dev/null; then
    echo ""
    echo "Add to your ~/.zshrc for zsh completions:"
    echo "  fpath=(~/.zfunc \$fpath)"
    echo "  autoload -Uz compinit && compinit"
  fi
fi

echo ""
echo "Installed! Make sure $BIN_DIR is in your PATH:"
echo '  export PATH="$HOME/.local/bin:$PATH"'
echo ""
echo "Run: claw-connect setup"
