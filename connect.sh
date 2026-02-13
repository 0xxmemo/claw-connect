#!/bin/bash

# AWS Instance Connection Script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Load .env ─────────────────────────────────────────────────
ENV_FILE="$SCRIPT_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo "Error: .env not found at $ENV_FILE"
    echo "Copy .env.example to .env and fill in your values."
    exit 1
fi
set -a
source "$ENV_FILE"
set +a

# ── Resolve paths ────────────────────────────────────────────
PEM_FILE="$SCRIPT_DIR/$PEM_FILE"

if [[ ! -f "$PEM_FILE" ]]; then
    echo "Error: PEM file not found at $PEM_FILE"
    exit 1
fi

# Ensure correct permissions on PEM file
chmod 400 "$PEM_FILE" 2>/dev/null || true

# Create control path directory for SSH multiplexing
CONTROL_PATH="$HOME/.ssh/control-%C"
mkdir -p "$HOME/.ssh" 2>/dev/null || true

# SSH options for stability and performance
SSH_OPTS=(
    -i "$PEM_FILE"
    -o "StrictHostKeyChecking=no"
    -o "ServerAliveInterval=30"
    -o "ServerAliveCountMax=3"
    -o "ConnectTimeout=10"
    -o "TCPKeepAlive=yes"
    -C  # Enable compression for better performance
    -o "ControlMaster=auto"
    -o "ControlPath=$CONTROL_PATH"
    -o "ControlPersist=10m"
)

usage() {
    cat << EOF
AWS Instance Connection Script

Usage: $0 [options]

Configuration is loaded from .env (see .env.example).

Options:
    -u, --user USER         SSH user (overrides .env)
    -t, --tunnel            Create SSH tunnel (gateway + VNC)
    -r, --resume [SESSION]  Resume/attach to tmux session (default: openclaw)
    -l, --list              List all remote tmux sessions
    -k, --kill SESSION      Kill a specific tmux session
    --init-tmux             Install optimized tmux config on remote server
    -d, --deploy            Deploy VNC viewer & set up services on remote
    -h, --help              Show this help message

Examples:
    $0                          # SSH into the server
    $0 --tunnel                 # Tunnel gateway (18789) + VNC (6090)
    $0 --deploy                 # Deploy VNC viewer to remote
    $0 --resume                 # Attach to tmux session 'openclaw'
    $0 --resume mysession       # Attach to tmux session 'mysession'
    $0 --list                   # List remote tmux sessions
    $0 --kill mysession         # Kill a tmux session
    $0 --init-tmux              # Install tmux config (run once)
EOF
}

# Parse arguments
TUNNEL_MODE=false
RESUME_MODE=false
LIST_MODE=false
INIT_TMUX=false
DEPLOY_MODE=false
KILL_SESSION=""
SESSION_NAME="openclaw"

while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--user)
            SSH_USER="$2"
            shift 2
            ;;
        -t|--tunnel)
            TUNNEL_MODE=true
            shift
            ;;
        -r|--resume)
            RESUME_MODE=true
            # Check if next arg is a session name (not a flag)
            if [[ -n "$2" && "$2" != -* ]]; then
                SESSION_NAME="$2"
                shift 2
            else
                shift
            fi
            ;;
        -l|--list)
            LIST_MODE=true
            shift
            ;;
        -k|--kill)
            KILL_SESSION="$2"
            if [[ -z "$KILL_SESSION" ]]; then
                echo "Error: --kill requires a session name"
                exit 1
            fi
            shift 2
            ;;
        --init-tmux)
            INIT_TMUX=true
            shift
            ;;
        -d|--deploy)
            DEPLOY_MODE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Override SSH user if provided via flag

# Handle list mode
if [[ "$LIST_MODE" == true ]]; then
    echo "Listing remote tmux sessions on $SSH_USER@$IP..."
    echo ""
    ssh "${SSH_OPTS[@]}" "$SSH_USER@$IP" "tmux ls 2>/dev/null || echo 'No active tmux sessions found'"
    exit 0
fi

# Handle kill session
if [[ -n "$KILL_SESSION" ]]; then
    echo "Killing tmux session '$KILL_SESSION' on $SSH_USER@$IP..."
    ssh "${SSH_OPTS[@]}" "$SSH_USER@$IP" "tmux kill-session -t '$KILL_SESSION' 2>/dev/null && echo 'Session killed successfully' || echo 'Error: Session not found or could not be killed'"
    exit 0
fi

# Handle init-tmux
if [[ "$INIT_TMUX" == true ]]; then
    echo "Installing optimized tmux config on $SSH_USER@$IP..."
    ssh "${SSH_OPTS[@]}" "$SSH_USER@$IP" "cat > ~/.tmux.conf << 'TMUX_EOF'
# Optimized tmux configuration for remote CLI use

# Reduce escape time for better vim/CLI responsiveness
set -sg escape-time 10

# Increase history limit
set -g history-limit 50000

# Enable mouse support
set -g mouse on

# Set default terminal with 256 color support
set -g default-terminal \"screen-256color\"

# Faster status bar refresh (reduce from default 15s)
set -g status-interval 5

# Start window/pane numbering at 1
set -g base-index 1
setw -g pane-base-index 1

# Renumber windows when one is closed
set -g renumber-windows on

# Enable focus events for vim/CLI tools
set -g focus-events on

# Increase scrollback buffer
set -g history-limit 50000

# Don't wait for escape sequences
set -s escape-time 0

# Enable clipboard integration
set -g set-clipboard on

# Better status bar
set -g status-style bg=black,fg=white
set -g status-left-length 40
set -g status-left \"#[fg=green]Session: #S #[fg=yellow]#I #[fg=cyan]#P\"
set -g status-right \"#[fg=cyan]%d %b %R\"

# Easier pane navigation
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

# Reload config
bind r source-file ~/.tmux.conf \\; display \"Config reloaded!\"
TMUX_EOF
echo 'Tmux config installed successfully at ~/.tmux.conf'
echo 'Your next tmux session will use these optimized settings.'"
    exit 0
fi

# Handle deploy mode
if [[ "$DEPLOY_MODE" == true ]]; then
    echo "Deploying vnc-viewer to $SSH_USER@$IP ..."
    echo ""

    # 1. Check & install dependencies only if missing
    echo "[1/3] Dependencies..."
    ssh "${SSH_OPTS[@]}" "$SSH_USER@$IP" '
        MISSING=""
        command -v bun >/dev/null 2>&1 || test -f "$HOME/.bun/bin/bun" || MISSING="$MISSING bun"
        command -v x11vnc >/dev/null 2>&1 || MISSING="$MISSING x11vnc"
        command -v websockify >/dev/null 2>&1 || MISSING="$MISSING websockify"
        dpkg -s novnc >/dev/null 2>&1 || MISSING="$MISSING novnc"

        if [ -z "$(echo $MISSING | tr -d " ")" ]; then
            echo "  All dependencies present, skipping"
        else
            echo "  Missing:$MISSING"

            # apt packages
            APT_PKGS=""
            echo "$MISSING" | grep -q x11vnc && APT_PKGS="$APT_PKGS x11vnc"
            echo "$MISSING" | grep -q websockify && APT_PKGS="$APT_PKGS websockify"
            echo "$MISSING" | grep -q novnc && APT_PKGS="$APT_PKGS novnc"
            if [ -n "$APT_PKGS" ]; then
                echo "  Installing:$APT_PKGS"
                sudo apt-get update -qq && sudo apt-get install -y -qq $APT_PKGS
            fi

            # bun
            if echo "$MISSING" | grep -q bun; then
                echo "  Installing Bun..."
                curl -fsSL https://bun.sh/install | bash
            fi
        fi
    '

    # 2. Upload files (always — this is the point of deploy)
    echo "[2/3] Uploading files..."
    ssh "${SSH_OPTS[@]}" "$SSH_USER@$IP" "mkdir -p '$REMOTE_DIR'"
    scp "${SSH_OPTS[@]}" \
        "$SCRIPT_DIR/vnc-viewer/viewer.html" \
        "$SCRIPT_DIR/vnc-viewer/novnc-proxy.mjs" \
        "$SSH_USER@$IP:$REMOTE_DIR/"
    echo "  viewer.html     -> deployed"
    echo "  novnc-proxy.mjs -> deployed"

    # 3. Services — install if missing, start if not running, restart only the proxy
    echo "[3/3] Services..."
    ssh "${SSH_OPTS[@]}" "$SSH_USER@$IP" '
        REMOTE_DIR="'"$REMOTE_DIR"'"
        CHANGED=false

        # Resolve bun path (could be in PATH or ~/.bun/bin)
        BUN_PATH="$(command -v bun 2>/dev/null)"
        if [ -z "$BUN_PATH" ] && [ -f "$HOME/.bun/bin/bun" ]; then
            BUN_PATH="$HOME/.bun/bin/bun"
        fi
        if [ -z "$BUN_PATH" ]; then
            echo "  ERROR: bun not found — cannot set up proxy service"
            exit 1
        fi

        # Read gateway token
        TOKEN=""
        if [ -f "$HOME/.openclaw/openclaw.json" ]; then
            TOKEN=$(python3 -c "import json; print(json.load(open(\"$HOME/.openclaw/openclaw.json\"))[\"gateway\"][\"auth\"][\"token\"])" 2>/dev/null) || true
        fi
        if [ -z "$TOKEN" ] && [ -f "$HOME/.openclaw/.env" ]; then
            TOKEN=$(grep "^OPENCLAW_GATEWAY_TOKEN=" "$HOME/.openclaw/.env" 2>/dev/null | cut -d= -f2-) || true
        fi
        if [ -z "$TOKEN" ]; then
            echo "  Warning: OPENCLAW_GATEWAY_TOKEN not found"
            echo "  Set it in ~/.openclaw/.env"
        fi

        # --- xvfb ---
        if [ ! -f /etc/systemd/system/xvfb.service ]; then
            echo "  Creating xvfb.service"
            sudo tee /etc/systemd/system/xvfb.service >/dev/null <<EOF
[Unit]
Description=X Virtual Frame Buffer
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/Xvfb :99 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
            CHANGED=true
        else
            echo "  xvfb.service            -> exists, skipping"
        fi

        # --- x11vnc ---
        if [ ! -f /etc/systemd/system/x11vnc.service ]; then
            echo "  Creating x11vnc.service"
            sudo tee /etc/systemd/system/x11vnc.service >/dev/null <<EOF
[Unit]
Description=x11vnc VNC Server
After=xvfb.service
Requires=xvfb.service

[Service]
Type=simple
User='"$SSH_USER"'
Environment=DISPLAY=:99
ExecStart=/usr/bin/x11vnc -display :99 -nopw -forever -shared -rfbport 5900 -ncache 10
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
            CHANGED=true
        else
            echo "  x11vnc.service          -> exists, skipping"
        fi

        # --- websockify ---
        if [ ! -f /etc/systemd/system/websockify.service ]; then
            echo "  Creating websockify.service"
            sudo tee /etc/systemd/system/websockify.service >/dev/null <<EOF
[Unit]
Description=Websockify VNC Bridge
After=x11vnc.service
Requires=x11vnc.service

[Service]
Type=simple
User='"$SSH_USER"'
ExecStart=/usr/bin/websockify --web /usr/share/novnc 127.0.0.1:6080 localhost:5900
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
            CHANGED=true
        else
            echo "  websockify.service      -> exists, skipping"
        fi

        # --- novnc-proxy (always update — token or bun path may change) ---
        sudo tee /etc/systemd/system/openclaw-novnc-proxy.service >/dev/null <<EOF
[Unit]
Description=OpenClaw noVNC Auth Proxy
After=websockify.service
Requires=websockify.service

[Service]
Type=simple
User='"$SSH_USER"'
Environment=OPENCLAW_GATEWAY_TOKEN=$TOKEN
ExecStart=$BUN_PATH $REMOTE_DIR/novnc-proxy.mjs
Restart=always
RestartSec=3
WorkingDirectory=$REMOTE_DIR

[Install]
WantedBy=multi-user.target
EOF

        sudo systemctl daemon-reload

        # If new services were created, enable and start everything
        if [ "$CHANGED" = true ]; then
            echo "  New services detected — enabling and starting stack"
            sudo systemctl enable xvfb x11vnc websockify openclaw-novnc-proxy 2>/dev/null

            # Kill stale bare processes and free ports
            pkill -f "x11vnc.*display" 2>/dev/null || true
            pkill -f "websockify.*6080" 2>/dev/null || true
            sudo fuser -k 5900/tcp 2>/dev/null || true
            sudo fuser -k 6080/tcp 2>/dev/null || true
            sleep 2

            sudo systemctl restart xvfb && sleep 2
            sudo systemctl restart x11vnc && sleep 1
            sudo systemctl restart websockify && sleep 1
            sudo systemctl restart openclaw-novnc-proxy && sleep 1
        else
            # Just ensure the base stack is running (no restart), only restart the proxy
            echo "  Stack already set up"
            for svc in xvfb x11vnc websockify; do
                if ! systemctl is-active --quiet "$svc"; then
                    echo "  $svc was stopped — starting"
                    sudo systemctl start "$svc"
                    sleep 1
                fi
            done
            echo "  Restarting novnc-proxy (files updated)..."
            sudo systemctl restart openclaw-novnc-proxy
            sleep 1
        fi

        echo ""
        echo "  xvfb:                 $(systemctl is-active xvfb)"
        echo "  x11vnc:               $(systemctl is-active x11vnc)"
        echo "  websockify:           $(systemctl is-active websockify)"
        echo "  openclaw-novnc-proxy: $(systemctl is-active openclaw-novnc-proxy)"
    '
    echo ""
    echo "Done. Hard-refresh the viewer in your browser (Cmd+Shift+R)."
    exit 0
fi

# Handle tunnel mode
if [[ "$TUNNEL_MODE" == true ]]; then
    echo "Creating SSH tunnel: localhost:18789 -> $TUNNEL_IP:18789, localhost:6090 -> $TUNNEL_IP:6090"

    # Fetch gateway token from remote openclaw config
    GATEWAY_TOKEN=$(ssh "${SSH_OPTS[@]}" "$SSH_USER@$IP" \
        "cat ~/.openclaw/openclaw.json 2>/dev/null" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['gateway']['auth']['token'])" 2>/dev/null) || true

    echo ""
    if [[ -n "$GATEWAY_TOKEN" ]]; then
        echo "  Gateway: http://localhost:18789/?token=$GATEWAY_TOKEN"
        echo "  VNC:     http://localhost:6090/?token=$GATEWAY_TOKEN"
    else
        echo "  Gateway: http://localhost:18789"
        echo "  VNC:     http://localhost:6090"
        echo "  (could not fetch gateway token from remote)"
    fi
    echo ""

    echo "Tunnel will remain active. Press Ctrl+C to close."
    ssh "${SSH_OPTS[@]}" -N \
        -L 18789:127.0.0.1:18789 \
        -L 6090:127.0.0.1:6090 \
        "$SSH_USER@$IP"
    exit 0
fi

echo "Connecting to $SSH_USER@$IP..."

# Handle resume mode with tmux
if [[ "$RESUME_MODE" == true ]]; then
    echo "Attaching to tmux session '$SESSION_NAME' (or creating new one)..."
    echo "Tip: Run './connect.sh --init-tmux' once for optimal performance"
    # Use optimized settings (config file if exists, otherwise inline)
    TMUX_CMD="TERM=screen-256color tmux -u attach -t '$SESSION_NAME' 2>/dev/null || TERM=screen-256color tmux -u new -s '$SESSION_NAME'"
    ssh "${SSH_OPTS[@]}" -t "$SSH_USER@$IP" "$TMUX_CMD"
else
    ssh "${SSH_OPTS[@]}" "$SSH_USER@$IP"
fi
