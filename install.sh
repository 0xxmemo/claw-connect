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

# Install completions
if [[ -d "$HOME/.bash_completion.d" ]] || mkdir -p "$HOME/.bash_completion.d"; then
  cp "$INSTALL_DIR/completions/claw-connect.bash" "$HOME/.bash_completion.d/claw-connect"
fi

echo ""
echo "Installed! Make sure $BIN_DIR is in your PATH:"
echo '  export PATH="$HOME/.local/bin:$PATH"'
echo ""
echo "Run: claw-connect setup"
