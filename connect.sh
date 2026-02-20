#!/bin/bash

# Claw Connect — Remote OpenClaw gateway helper

set -euo pipefail

# Resolve symlinks to find the real install directory
SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
CONFIG_DIR="$HOME/.config/claw-connect"
PROFILE="default"
VERSION="$(git -C "$SCRIPT_DIR" describe --tags --abbrev=0 2>/dev/null || echo "dev")"

usage() {
  cat << 'EOF'
Claw Connect — Remote OpenClaw gateway helper

Usage: claw-connect [options] [command]

Commands:
  setup [PROFILE]         Interactive setup wizard (default profile: "default")
  profiles                List configured profiles

Options:
  -p, --profile PROFILE   Use a named profile (default: "default")
  -t, --tunnel            Create SSH tunnel (gateway + VNC on /vnc route)
  -v, --vnc               Direct VNC tunnel (raw protocol, needs VNC client)
  -r, --resume [SESSION]  Resume/attach to tmux session (default: openclaw)
  -l, --list              List all remote tmux sessions
  -k, --kill SESSION      Kill a specific tmux session
  -u, --user USER         Override SSH user
      --update            Update claw-connect to latest version (git pull)
      --init-tmux         Install optimized tmux config on remote
      --version           Print version
  -h, --help              Show this help message

Examples:
  claw-connect setup
  claw-connect --tunnel
  claw-connect -p staging --vnc
  claw-connect --resume
EOF
}

run_setup() {
  local profile_name="${1:-default}"
  local profile_dir="$CONFIG_DIR/profiles/$profile_name"
  mkdir -p "$profile_dir"

  echo "Claw Connect — Setup"
  echo ""
  echo "Profile: $profile_name"
  echo "Config:  $profile_dir/"
  echo ""

  local cur_ip="" cur_tunnel_ip="" cur_ssh_user="ubuntu"
  if [[ -f "$profile_dir/config" ]]; then
    source "$profile_dir/config"
    cur_ip="${IP:-}"
    cur_tunnel_ip="${TUNNEL_IP:-}"
    cur_ssh_user="${SSH_USER:-ubuntu}"
  fi

  read -rp "Server public IP [$cur_ip]: " input_ip
  IP="${input_ip:-$cur_ip}"
  [[ -n "$IP" ]] || { echo "Error: IP is required."; exit 1; }

  read -rp "Tunnel IP (private/internal) [$cur_tunnel_ip]: " input_tunnel_ip
  TUNNEL_IP="${input_tunnel_ip:-$cur_tunnel_ip}"
  [[ -n "$TUNNEL_IP" ]] || TUNNEL_IP="$IP"

  read -rp "SSH user [$cur_ssh_user]: " input_ssh_user
  SSH_USER="${input_ssh_user:-$cur_ssh_user}"

  local cur_pem=""
  [[ -f "$profile_dir/cred.pem" ]] && cur_pem="(already configured)"
  read -rp "Path to PEM key file $cur_pem: " input_pem

  if [[ -n "$input_pem" ]]; then
    input_pem="${input_pem/#\~/$HOME}"
    [[ -f "$input_pem" ]] || { echo "Error: File not found: $input_pem"; exit 1; }
    cp "$input_pem" "$profile_dir/cred.pem"
    chmod 400 "$profile_dir/cred.pem"
    echo "  PEM key copied to $profile_dir/cred.pem"
  elif [[ ! -f "$profile_dir/cred.pem" ]]; then
    echo "Error: PEM key is required for first-time setup."
    exit 1
  fi

  cat > "$profile_dir/config" << CONF
IP=$IP
TUNNEL_IP=$TUNNEL_IP
SSH_USER=$SSH_USER
CONF

  echo ""
  echo "Profile '$profile_name' saved to $profile_dir/"
  echo "Run: claw-connect${profile_name:+ -p $profile_name} --tunnel"
  exit 0
}

list_profiles() {
  echo "Configured profiles:"
  echo ""
  local found=false
  if [[ -d "$CONFIG_DIR/profiles" ]]; then
    for dir in "$CONFIG_DIR/profiles"/*/; do
      [[ -d "$dir" && -f "$dir/config" ]] || continue
      local name ip
      name="$(basename "$dir")"
      ip="$(grep '^IP=' "$dir/config" 2>/dev/null | cut -d= -f2-)"
      echo "  $name  ($ip)"
      found=true
    done
  fi
  if [[ "$found" == false ]]; then
    echo "  (none)"
    echo ""
    echo "Run 'claw-connect setup' to create one."
  fi
  exit 0
}

TUNNEL_MODE=false
VNC_MODE=false
RESUME_MODE=false
LIST_MODE=false
INIT_TMUX=false
SETUP_MODE=false
PROFILES_MODE=false
KILL_SESSION=""
SESSION_NAME="openclaw"

case "${1:-}" in
  setup) SETUP_MODE=true; shift ;;
  profiles) PROFILES_MODE=true; shift ;;
esac

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--profile) PROFILE="$2"; shift 2 ;;
    -u|--user) SSH_USER_OVERRIDE="$2"; shift 2 ;;
    -t|--tunnel) TUNNEL_MODE=true; shift ;;
    -v|--vnc) VNC_MODE=true; shift ;;
    -r|--resume)
      RESUME_MODE=true
      if [[ -n "${2:-}" && "$2" != -* ]]; then SESSION_NAME="$2"; shift 2; else shift; fi
      ;;
    -l|--list) LIST_MODE=true; shift ;;
    -k|--kill)
      KILL_SESSION="${2:-}"
      [[ -n "$KILL_SESSION" ]] || { echo "Error: --kill requires a session name"; exit 1; }
      shift 2
      ;;
    --update) echo "Updating claw-connect..."; git -C "$SCRIPT_DIR" pull --ff-only && echo "Updated to $(git -C "$SCRIPT_DIR" describe --tags --abbrev=0 2>/dev/null || git -C "$SCRIPT_DIR" rev-parse --short HEAD)"; exit 0 ;;
    --init-tmux) INIT_TMUX=true; shift ;;
    --version) echo "claw-connect $VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ "$SETUP_MODE" == true ]]; then PROFILE="$1"; shift
      else echo "Unknown option: $1"; usage; exit 1; fi
      ;;
  esac
done

[[ "$PROFILES_MODE" == true ]] && list_profiles
[[ "$SETUP_MODE" == true ]] && run_setup "$PROFILE"

PROFILE_DIR="$CONFIG_DIR/profiles/$PROFILE"
if [[ ! -f "$PROFILE_DIR/config" ]]; then
  if ! ls "$CONFIG_DIR/profiles"/*/config &>/dev/null; then
    echo "No profiles configured. Running first-time setup..."
    echo ""
    run_setup "$PROFILE"
  else
    echo "Error: Profile '$PROFILE' not found."
    echo "Available profiles:"
    for dir in "$CONFIG_DIR/profiles"/*/; do
      [[ -f "$dir/config" ]] && echo "  $(basename "$dir")"
    done
    exit 1
  fi
fi

set -a
source "$PROFILE_DIR/config"
set +a
PEM_FILE="$PROFILE_DIR/cred.pem"

if [[ -n "${SSH_USER_OVERRIDE:-}" ]]; then SSH_USER="$SSH_USER_OVERRIDE"; fi
[[ -f "$PEM_FILE" ]] || { echo "Error: PEM file not found at $PEM_FILE"; exit 1; }
chmod 400 "$PEM_FILE" 2>/dev/null || true

CONTROL_PATH="$HOME/.ssh/control-%C"
mkdir -p "$HOME/.ssh" 2>/dev/null || true
SSH_OPTS=(
  -i "$PEM_FILE"
  -o "StrictHostKeyChecking=no"
  -o "UserKnownHostsFile=/dev/null"
  -o "LogLevel=ERROR"
  -o "ServerAliveInterval=30"
  -o "ServerAliveCountMax=3"
  -o "ConnectTimeout=10"
  -o "TCPKeepAlive=yes"
  -C
  -o "ControlMaster=auto"
  -o "ControlPath=$CONTROL_PATH"
  -o "ControlPersist=10m"
)

if [[ "$LIST_MODE" == true ]]; then
  echo "Listing remote tmux sessions on $SSH_USER@$IP..."
  echo ""
  ssh "${SSH_OPTS[@]}" "$SSH_USER@$IP" "tmux ls 2>/dev/null || echo 'No active tmux sessions found'"
  exit 0
fi

if [[ -n "$KILL_SESSION" ]]; then
  echo "Killing tmux session '$KILL_SESSION' on $SSH_USER@$IP..."
  ssh "${SSH_OPTS[@]}" "$SSH_USER@$IP" "tmux kill-session -t '$KILL_SESSION' 2>/dev/null && echo 'Session killed successfully' || echo 'Error: Session not found or could not be killed'"
  exit 0
fi

if [[ "$INIT_TMUX" == true ]]; then
  echo "Installing optimized tmux config on $SSH_USER@$IP..."
  ssh "${SSH_OPTS[@]}" "$SSH_USER@$IP" "cat > ~/.tmux.conf << 'TMUX_EOF'
set -sg escape-time 10
set -g history-limit 50000
set -g mouse on
set -g default-terminal \"screen-256color\"
set -g status-interval 5
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
set -g focus-events on
set -s escape-time 0
set -g set-clipboard on
set -g status-style bg=black,fg=white
set -g status-left-length 40
set -g status-left \"#[fg=green]Session: #S #[fg=yellow]#I #[fg=cyan]#P\"
set -g status-right \"#[fg=cyan]%d %b %R\"
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R
bind r source-file ~/.tmux.conf \\\; display \"Config reloaded!\"
TMUX_EOF
echo 'Tmux config installed successfully at ~/.tmux.conf'"
  exit 0
fi

if [[ "$VNC_MODE" == true ]]; then
  echo "Direct VNC tunnel: localhost:5900 -> $IP:5900"
  echo "Connect your VNC client to: localhost:5900"
  echo ""
  echo "macOS:    open vnc://localhost:5900"
  echo "TigerVNC: vncviewer localhost:5900"
  echo ""
  echo "Tunnel active. Press Ctrl+C to close."
  ssh "${SSH_OPTS[@]}" -N -L 5900:127.0.0.1:5900 "$SSH_USER@$IP"
  exit 0
fi

if [[ "$TUNNEL_MODE" == true ]]; then
  # Kill any existing SSH tunnels on port 18789
  existing_pids="$(lsof -ti :18789 -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -n "$existing_pids" ]]; then
    echo "$existing_pids" | xargs kill 2>/dev/null || true
    sleep 0.5
  fi

  # Fetch gateway token from remote
  GATEWAY_TOKEN="$(ssh "${SSH_OPTS[@]}" "$SSH_USER@$IP" '
    python3 - <<"PY"
import json, os, pathlib
home = pathlib.Path.home()
cfg = home / ".openclaw" / "openclaw.json"
env = home / ".openclaw" / ".env"

tok = ""
if cfg.exists():
    try:
        data = json.loads(cfg.read_text())
        tok = data.get("gateway", {}).get("auth", {}).get("token", "")
    except Exception:
        pass
if not tok and env.exists():
    for line in env.read_text().splitlines():
        if line.startswith("OPENCLAW_GATEWAY_TOKEN="):
            tok = line.split("=",1)[1].strip()
            break
print(tok)
PY
  ' 2>/dev/null || true)"

  echo "Creating SSH tunnel: localhost:18789 -> $TUNNEL_IP:18789"
  echo ""

  if [[ -n "$GATEWAY_TOKEN" ]]; then
    echo "  Gateway: http://localhost:18789/?token=$GATEWAY_TOKEN"
    echo "  Browser: http://localhost:18789/vnc?token=$GATEWAY_TOKEN"
  else
    echo "  Gateway: http://localhost:18789"
    echo "  Browser: http://localhost:18789/vnc"
    echo "  (could not fetch gateway token from remote)"
  fi
  echo ""
  echo "Tunnel will remain active. Press Ctrl+C to close."

  ssh "${SSH_OPTS[@]}" -N -L 18789:127.0.0.1:18789 "$SSH_USER@$IP"
  exit 0
fi

echo "Connecting to $SSH_USER@$IP..."
if [[ "$RESUME_MODE" == true ]]; then
  echo "Attaching to tmux session '$SESSION_NAME' (or creating new one)..."
  TMUX_CMD="TERM=screen-256color tmux -u attach -t '$SESSION_NAME' 2>/dev/null || TERM=screen-256color tmux -u new -s '$SESSION_NAME'"
  ssh "${SSH_OPTS[@]}" -t "$SSH_USER@$IP" "$TMUX_CMD"
else
  ssh "${SSH_OPTS[@]}" "$SSH_USER@$IP"
fi
