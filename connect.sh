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
SESSION_STATE_DIR="$CONFIG_DIR/sessions"
PROFILE="default"
VERSION="$(git -C "$SCRIPT_DIR" describe --tags --abbrev=0 2>/dev/null || echo "dev")"

DTACH_SESSION_DIR="~/.local/share/claw-connect/sessions"

usage() {
  cat << 'EOF'
Claw Connect — Remote OpenClaw gateway helper

Usage: claw-connect [options] [command]

Commands:
  setup [PROFILE]         Interactive setup wizard (default profile: "default")
  profiles                List configured profiles
  sessions                List tracked session states
  clean-sessions          Remove stale session state files

Options:
  -p, --profile PROFILE   Use a named profile (default: "default")
  -t, --tunnel            Create SSH tunnel (gateway + VNC on /vnc route)
  -v, --vnc               Direct VNC tunnel (raw protocol, needs VNC client)
  -r, --resume [SESSION]  Resume/attach to session (default: openclaw)
  -l, --list              List all remote sessions
  -k, --kill SESSION      Kill a specific remote session
  -u, --user USER         Override SSH user
      --update            Update claw-connect to latest version (git pull)
  -s, --session NAME      Connect to specific session (create or join)
      --version           Print version
  -h, --help              Show this help message

Session Tracking:
  Sessions are automatically tracked when attached. Disconnected sessions
  persist on the remote and will be reattached automatically.
  Running claw-connect without flags defaults to resume mode.
  Detach from a session with Ctrl+\ to leave it running in the background.

Examples:
  claw-connect                    # Resume session (default)
  claw-connect setup
  claw-connect --tunnel
  claw-connect -p staging --vnc
  claw-connect --resume
EOF
}

# Session tracking functions
get_session_state_file() {
  local profile="$1"
  local session="$2"
  mkdir -p "$SESSION_STATE_DIR"
  echo "$SESSION_STATE_DIR/${profile}__${session}.state"
}

save_session_state() {
  local profile="$1"
  local session="$2"
  local state="$3"  # "attached", "detached", "exited"
  local cwd="${4:-}"   # optional: last working directory
  local timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local state_file="$(get_session_state_file "$profile" "$session")"
  local cwd_json=""
  if [[ -n "$cwd" ]]; then
    cwd_json=",\"cwd\":\"$cwd\""
  fi
  echo "{\"session\":\"$session\",\"profile\":\"$profile\",\"state\":\"$state\",\"last_seen\":\"$timestamp\"$cwd_json}" > "$state_file"
}

get_session_state() {
  local profile="$1"
  local session="$2"
  local state_file="$(get_session_state_file "$profile" "$session")"
  if [[ -f "$state_file" ]]; then
    cat "$state_file"
  else
    echo ""
  fi
}

get_session_cwd() {
  local profile="$1"
  local session="$2"
  # First try to get CWD from state file
  local state="$(get_session_state "$profile" "$session")"
  if [[ -n "$state" ]]; then
    local cwd="$(echo "$state" | grep -o '"cwd":"[^"]*"' | cut -d'"' -f4)"
    if [[ -n "$cwd" ]]; then
      echo "$cwd"
      return
    fi
  fi
  # Fallback: check cwd directory on remote (from bash EXIT hook)
  local remote_cwd="$(ssh "${SSH_OPTS[@]}" "$SSH_USER@$IP" "cat ~/.config/claw-connect/cwd/${session}.cwd 2>/dev/null" || echo "")"
  if [[ -n "$remote_cwd" ]]; then
    echo "$remote_cwd"
  else
    echo ""
  fi
}

# Check if a dtach session exists on remote (socket file present)
session_exists_remote() {
  local session="$1"
  set +e
  ssh "${SSH_OPTS[@]}" "$SSH_USER@$IP" "test -S ${DTACH_SESSION_DIR}/${session}.sock" 2>/dev/null
  local result=$?
  set -e
  return $result
}

# Ensure dtach is installed on remote (one-time, silent)
ensure_dtach() {
  ssh "${SSH_OPTS[@]}" "$SSH_USER@$IP" "which dtach >/dev/null 2>&1 || (sudo apt-get update -qq && sudo apt-get install -y -qq dtach)" 2>/dev/null
}

# Install bash hook for CWD saving (idempotent)
install_cwd_hook() {
  ssh "${SSH_OPTS[@]}" "$SSH_USER@$IP" "
# Add shell hook to save CWD on exit (idempotent - check if already present)
if ! grep -q '_claw_save_state' ~/.bashrc 2>/dev/null; then
  cat >> ~/.bashrc << 'BASH_EOF'

# Save CWD when shell exits (for claw-connect session tracking)
_claw_save_state() {
  if [[ -n \"\${CLAW_SESSION:-}\" ]]; then
    mkdir -p ~/.config/claw-connect/cwd 2>/dev/null
    echo \"\$PWD\" > \"\$HOME/.config/claw-connect/cwd/\${CLAW_SESSION}.cwd\" 2>/dev/null
  fi
}
trap _claw_save_state EXIT
BASH_EOF
fi

# Migrate old tmux-based hook to new CLAW_SESSION-based hook
if grep -q 'tmux display-message' ~/.bashrc 2>/dev/null; then
  sed -i '/# Save CWD when shell exits/,/^trap _claw_save_state EXIT$/c\\
# Save CWD when shell exits (for claw-connect session tracking)\\
_claw_save_state() {\\
  if [[ -n \"\${CLAW_SESSION:-}\" ]]; then\\
    mkdir -p ~/.config/claw-connect/cwd 2>/dev/null\\
    echo \"\$PWD\" > \"\$HOME/.config/claw-connect/cwd/\${CLAW_SESSION}.cwd\" 2>/dev/null\\
  fi\\
}\\
trap _claw_save_state EXIT' ~/.bashrc
fi

# Ensure session directory exists
mkdir -p ${DTACH_SESSION_DIR}
" 2>/dev/null
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

list_sessions() {
  echo "Tracked session states:"
  if [[ "$PROFILE" != "default" ]]; then
    echo "Profile filter: $PROFILE"
  fi
  echo ""
  local found=false
  if [[ -d "$SESSION_STATE_DIR" ]]; then
    for state_file in "$SESSION_STATE_DIR"/*.state; do
      [[ -f "$state_file" ]] || continue
      local content profile_name session_name state last_seen cwd
      content="$(cat "$state_file")"
      profile_name="$(echo "$content" | grep -o '"profile":"[^"]*"' | cut -d'"' -f4)"
      session_name="$(echo "$content" | grep -o '"session":"[^"]*"' | cut -d'"' -f4)"
      state="$(echo "$content" | grep -o '"state":"[^"]*"' | cut -d'"' -f4)"
      last_seen="$(echo "$content" | grep -o '"last_seen":"[^"]*"' | cut -d'"' -f4)"
      cwd="$(echo "$content" | grep -o '"cwd":"[^"]*"' | cut -d'"' -f4)"

      # Filter by profile if specified
      if [[ "$PROFILE" != "default" && "$profile_name" != "$PROFILE" ]]; then
        continue
      fi

      echo "  $profile_name / $session_name"
      echo "    State: $state, Last seen: $last_seen"
      if [[ -n "$cwd" ]]; then
        echo "    CWD: $cwd"
      fi
      found=true
    done
  fi
  if [[ "$found" == false ]]; then
    if [[ "$PROFILE" != "default" ]]; then
      echo "  (no tracked sessions for profile '$PROFILE')"
    else
      echo "  (no tracked sessions)"
    fi
  fi
  exit 0
}

clean_sessions() {
  echo "Cleaning stale session state files..."
  if [[ "$PROFILE" != "default" ]]; then
    echo "Profile filter: $PROFILE"
  fi
  echo ""
  local removed=0
  if [[ -d "$SESSION_STATE_DIR" ]]; then
    for state_file in "$SESSION_STATE_DIR"/*.state; do
      [[ -f "$state_file" ]] || continue
      local content profile_name session_name
      content="$(cat "$state_file")"
      profile_name="$(echo "$content" | grep -o '"profile":"[^"]*"' | cut -d'"' -f4)"
      session_name="$(echo "$content" | grep -o '"session":"[^"]*"' | cut -d'"' -f4)"

      # Filter by profile if specified
      if [[ "$PROFILE" != "default" && "$profile_name" != "$PROFILE" ]]; then
        continue
      fi

      # Check if profile still exists
      local profile_dir="$CONFIG_DIR/profiles/$profile_name"
      if [[ ! -d "$profile_dir" ]]; then
        echo "  Removing: $profile_name / $session_name (profile no longer exists)"
        rm -f "$state_file"
        ((removed++))
        continue
      fi

      # Load profile config for SSH access
      source "$profile_dir/config"
      [[ -f "$profile_dir/cred.pem" ]] || { echo "  Skipping: $profile_name / $session_name (PEM not found)"; continue; }
      SSH_USER="${SSH_USER:-ubuntu}"

      # Build SSH opts for this profile
      local clean_ssh_opts=(
        -i "$profile_dir/cred.pem"
        -o "StrictHostKeyChecking=no"
        -o "UserKnownHostsFile=/dev/null"
        -o "LogLevel=ERROR"
        -o "ConnectTimeout=5"
      )

      # Check if dtach session socket exists on remote
      if ! ssh "${clean_ssh_opts[@]}" "$SSH_USER@$IP" "test -S ${DTACH_SESSION_DIR}/${session_name}.sock" 2>/dev/null; then
        echo "  Removing: $profile_name / $session_name (session no longer exists on remote)"
        rm -f "$state_file"
        ((removed++))
      fi
    done
  fi
  echo ""
  echo "Removed $removed stale session state file(s)."
  exit 0
}

TUNNEL_MODE=false
VNC_MODE=false
RESUME_MODE=false
LIST_MODE=false
SETUP_MODE=false
PROFILES_MODE=false
SESSIONS_MODE=false
CLEAN_SESSIONS_MODE=false
KILL_SESSION=""
SESSION_NAME="openclaw"
SPECIFIC_SESSION=""

case "${1:-}" in
  setup) SETUP_MODE=true; shift ;;
  profiles) PROFILES_MODE=true; shift ;;
  sessions) SESSIONS_MODE=true; shift ;;
  clean-sessions) CLEAN_SESSIONS_MODE=true; shift ;;
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
    -s|--session)
      SPECIFIC_SESSION="${2:-}"
      [[ -n "$SPECIFIC_SESSION" ]] || { echo "Error: --session requires a session name"; exit 1; }
      shift 2
      ;;
    -l|--list) LIST_MODE=true; shift ;;
    -k|--kill)
      KILL_SESSION="${2:-}"
      [[ -n "$KILL_SESSION" ]] || { echo "Error: --kill requires a session name"; exit 1; }
      shift 2
      ;;
    --update) echo "Updating claw-connect..."; git -C "$SCRIPT_DIR" pull --ff-only && echo "Updated to $(git -C "$SCRIPT_DIR" describe --tags --abbrev=0 2>/dev/null || git -C "$SCRIPT_DIR" rev-parse --short HEAD)"; exit 0 ;;
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
[[ "$SESSIONS_MODE" == true ]] && list_sessions
[[ "$CLEAN_SESSIONS_MODE" == true ]] && clean_sessions

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
  echo "Listing remote sessions on $SSH_USER@$IP..."
  echo ""
  ssh "${SSH_OPTS[@]}" "$SSH_USER@$IP" "
    session_dir=${DTACH_SESSION_DIR}
    if [[ ! -d \"\$session_dir\" ]] || ! ls \"\$session_dir\"/*.sock &>/dev/null 2>&1; then
      echo 'No active sessions found'
      exit 0
    fi
    for sock in \"\$session_dir\"/*.sock; do
      name=\"\$(basename \"\$sock\" .sock)\"
      if [[ -S \"\$sock\" ]]; then
        # Check if the process behind the socket is still alive
        if dtach -a \"\$sock\" -e '' -z /bin/true 2>/dev/null; then
          status='active'
        else
          status='stale (socket exists but process dead)'
        fi
      else
        status='stale (not a socket)'
      fi
      cwd=''
      if [[ -f ~/.config/claw-connect/cwd/\${name}.cwd ]]; then
        cwd=\" (cwd: \$(cat ~/.config/claw-connect/cwd/\${name}.cwd))\"
      fi
      echo \"  \$name: \$status\$cwd\"
    done
  "
  exit 0
fi

if [[ -n "$KILL_SESSION" ]]; then
  echo "Killing session '$KILL_SESSION' on $SSH_USER@$IP..."
  ssh "${SSH_OPTS[@]}" "$SSH_USER@$IP" "
    sock=${DTACH_SESSION_DIR}/${KILL_SESSION}.sock
    if [[ -S \"\$sock\" ]]; then
      # Find and kill the process group behind the dtach socket
      pid=\$(lsof -t \"\$sock\" 2>/dev/null | head -1)
      if [[ -n \"\$pid\" ]]; then
        # Kill the entire process tree rooted at dtach
        pkill -TERM -P \"\$pid\" 2>/dev/null || true
        kill \"\$pid\" 2>/dev/null || true
      fi
      rm -f \"\$sock\"
      echo 'Session killed successfully'
    else
      echo 'Error: Session not found or already dead'
    fi
  "
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
  # Kill only existing SSH tunnel processes on port 18789 (not other claw-connect sessions)
  # Match only 'ssh -N' (tunnel-only) processes bound to port 18789
  existing_pids="$(lsof -ti :18789 -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -n "$existing_pids" ]]; then
    for pid in $existing_pids; do
      # Only kill if the process is an ssh tunnel (ssh -N), not a regular session
      if ps -p "$pid" -o args= 2>/dev/null | grep -q 'ssh.*-N.*-L.*18789'; then
        kill "$pid" 2>/dev/null || true
      fi
    done
    sleep 0.5
  fi

  # Fetch gateway token from remote
  GATEWAY_TOKEN="$(ssh "${SSH_OPTS[@]}" "$SSH_USER@$IP" python3 - 2>/dev/null <<'PY'
import json, os, pathlib, re
home = pathlib.Path.home()
cfg = home / ".openclaw" / "openclaw.json"
env = home / ".openclaw" / ".env"

def load_env(path):
    vals = {}
    if path.exists():
        for line in path.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                vals[k.strip()] = v.strip().strip("\"'")
    return vals

def resolve(s, env_vals):
    if not s:
        return s
    return re.sub(r"\$\{(\w+)\}", lambda m: env_vals.get(m.group(1), m.group(0)), s)

env_vals = load_env(env)
tok = ""
if cfg.exists():
    try:
        data = json.loads(cfg.read_text())
        tok = data.get("gateway", {}).get("auth", {}).get("token", "")
    except Exception:
        pass

tok = resolve(tok, env_vals)

if not tok:
    tok = env_vals.get("OPENCLAW_GATEWAY_TOKEN", "")
print(tok)
PY
  )"

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

# Handle session tracking on script exit
cleanup_and_save_state() {
  if [[ "$RESUME_MODE" == true && -n "$SESSION_NAME" ]]; then
    set +e
    if session_exists_remote "$SESSION_NAME" 2>/dev/null; then
      # Session still exists - we detached normally
      # Get the CWD from remote cwd file (saved by bash EXIT hook)
      local cwd="$(ssh "${SSH_OPTS[@]}" "$SSH_USER@$IP" "cat ~/.config/claw-connect/cwd/${SESSION_NAME}.cwd 2>/dev/null" || echo "")"
      if [[ -n "$cwd" ]]; then
        save_session_state "$PROFILE" "$SESSION_NAME" "detached" "$cwd"
      else
        save_session_state "$PROFILE" "$SESSION_NAME" "detached"
      fi
    else
      # Session no longer exists - it was killed or the shell exited
      local prev_state="$(get_session_state "$PROFILE" "$SESSION_NAME")"
      local saved_cwd="$(echo "$prev_state" | grep -o '"cwd":"[^"]*"' | cut -d'"' -f4)"
      if [[ -n "$saved_cwd" ]]; then
        save_session_state "$PROFILE" "$SESSION_NAME" "exited" "$saved_cwd"
      else
        save_session_state "$PROFILE" "$SESSION_NAME" "exited"
      fi
    fi
    set -e
  fi
}
trap cleanup_and_save_state EXIT

# Save working directory for a session
save_session_cwd() {
  local profile="$1"
  local session="$2"
  local cwd="$3"
  local state_file="$(get_session_state_file "$profile" "$session")"
  if [[ -f "$state_file" ]]; then
    local content="$(cat "$state_file")"
    # Update existing state file with cwd
    local timestamp="$(echo "$content" | grep -o '"last_seen":"[^"]*"' | cut -d'"' -f4)"
    local state="$(echo "$content" | grep -o '"state":"[^"]*"' | cut -d'"' -f4)"
    echo "{\"session\":\"$session\",\"profile\":\"$profile\",\"state\":\"$state\",\"last_seen\":\"$timestamp\",\"cwd\":\"$cwd\"}" > "$state_file"
  fi
}

# Resume session with tracking and reconnection logic
do_resume_session() {
  set +e
  # Ensure dtach is installed and CWD hook is present
  ensure_dtach
  install_cwd_hook

  local prev_state="$(get_session_state "$PROFILE" "$SESSION_NAME")"
  local last_state="unknown"
  local last_seen="never"
  local saved_cwd=""
  # Get saved CWD from state file first, then try remote cwd file
  if [[ -n "$prev_state" ]]; then
    last_state="$(echo "$prev_state" | grep -o '"state":"[^"]*"' | cut -d'"' -f4 || echo "")"
    last_seen="$(echo "$prev_state" | grep -o '"last_seen":"[^"]*"' | cut -d'"' -f4 || echo "")"
    saved_cwd="$(echo "$prev_state" | grep -o '"cwd":"[^"]*"' | cut -d'"' -f4 || echo "")"
  fi
  # Fallback: check remote cwd file (from bash EXIT hook)
  if [[ -z "$saved_cwd" ]]; then
    saved_cwd="$(ssh "${SSH_OPTS[@]}" "$SSH_USER@$IP" "cat ~/.config/claw-connect/cwd/${SESSION_NAME}.cwd 2>/dev/null" || echo "")"
  fi

  local sock="${DTACH_SESSION_DIR}/${SESSION_NAME}.sock"

  # Check if session exists on remote
  set +e
  local session_exists=false
  if session_exists_remote "$SESSION_NAME" 2>/dev/null; then
    session_exists=true
  fi

  if [[ "$session_exists" == true ]]; then
    echo "Session '$SESSION_NAME' exists, reattaching..."
    save_session_state "$PROFILE" "$SESSION_NAME" "attached"
    ssh "${SSH_OPTS[@]}" -t "$SSH_USER@$IP" "dtach -a ${sock} -z"
  else
    # Session doesn't exist - create it
    if [[ -n "$prev_state" ]]; then
      echo "Session '$SESSION_NAME' was last seen as '$last_state' at $last_seen"
      if [[ -n "$saved_cwd" ]]; then
        echo "  Restoring working directory: $saved_cwd"
      fi
    fi
    echo "Creating new session '$SESSION_NAME'..."
    save_session_state "$PROFILE" "$SESSION_NAME" "attached"
    if [[ -n "$saved_cwd" ]]; then
      ssh "${SSH_OPTS[@]}" -t "$SSH_USER@$IP" "cd '$saved_cwd' 2>/dev/null; CLAW_SESSION='$SESSION_NAME' dtach -A ${sock} -z bash -l"
    else
      ssh "${SSH_OPTS[@]}" -t "$SSH_USER@$IP" "CLAW_SESSION='$SESSION_NAME' dtach -A ${sock} -z bash -l"
    fi
  fi

  # After detach/disconnect, save state
  local current_cwd="$(ssh "${SSH_OPTS[@]}" "$SSH_USER@$IP" "cat ~/.config/claw-connect/cwd/${SESSION_NAME}.cwd 2>/dev/null" || echo "")"
  if [[ -n "$current_cwd" ]]; then
    save_session_cwd "$PROFILE" "$SESSION_NAME" "$current_cwd"
    save_session_state "$PROFILE" "$SESSION_NAME" "detached" "$current_cwd"
  else
    save_session_state "$PROFILE" "$SESSION_NAME" "detached"
  fi
  set -e
}

echo "Connecting to $SSH_USER@$IP..."
# Default to resume mode if no explicit mode specified
if [[ "$TUNNEL_MODE" == false && "$VNC_MODE" == false && "$RESUME_MODE" == false && "$LIST_MODE" == false && -z "$SPECIFIC_SESSION" ]]; then
  RESUME_MODE=true
fi

# Handle specific session flag (create or join)
if [[ -n "$SPECIFIC_SESSION" ]]; then
  SESSION_NAME="$SPECIFIC_SESSION"
  do_resume_session
  exit 0
fi

if [[ "$RESUME_MODE" == true ]]; then
  do_resume_session
  exit 0
else
  ssh "${SSH_OPTS[@]}" "$SSH_USER@$IP"
fi
