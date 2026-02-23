# claw-connect

SSH helper for remote [OpenClaw](https://github.com/openclaw/openclaw) gateways.

Tunnels, tmux sessions, and browser VNC — all through one command.

## Install

```bash
curl -sL https://raw.githubusercontent.com/0xxmemo/claw-connect/main/install.sh | bash
```

Or clone manually:

```bash
git clone https://github.com/0xxmemo/claw-connect.git ~/claw-connect
chmod +x ~/claw-connect/connect.sh
ln -sf ~/claw-connect/connect.sh ~/.local/bin/claw-connect
```

### Shell Completions

**Bash** — installed automatically, or copy manually:

```bash
cp completions/claw-connect.bash ~/.bash_completion.d/claw-connect
```

**Zsh** — add the completions directory to your `fpath`:

```zsh
# Add to ~/.zshrc
fpath=(~/claw-connect/completions $fpath)
autoload -Uz compinit && compinit
```

## Setup

```bash
claw-connect setup
```

Prompts for server IP, SSH user, and PEM key. Saves to `~/.config/claw-connect/profiles/default/`.

Multiple profiles:

```bash
claw-connect setup production
claw-connect setup staging
claw-connect -p staging --tunnel
```

## Usage

### SSH Tunnel (gateway + browser VNC)

```bash
claw-connect -t
claw-connect -t -p quantide    # specific profile
```

Opens an SSH tunnel on `localhost:18789`. Output:

```
Creating SSH tunnel: localhost:18789 -> 172.31.x.x:18789

  Gateway: http://localhost:18789/?token=<auto-fetched>
  Browser: http://localhost:18789/vnc?token=<auto-fetched>

Tunnel will remain active. Press Ctrl+C to close.
```

Switching profiles automatically kills any existing tunnel on port 18789 before starting the new one — no manual cleanup needed.

The gateway token is auto-fetched from the remote server. It reads `openclaw.json` first and resolves any `${VAR}` references against `.env`, falling back to `OPENCLAW_GATEWAY_TOKEN` in `.env` directly.

The `/vnc` route serves a built-in noVNC viewer — no external scripts needed. Enable it on the server:

```json
{
  "gateway": {
    "browser": {
      "vnc": { "enabled": true }
    }
  }
}
```

### Direct VNC (raw protocol)

```bash
claw-connect -v
```

Tunnels `localhost:5900` for use with native VNC clients (TigerVNC, macOS Screen Sharing).

### Tmux Sessions

```bash
claw-connect                 # Attach to "openclaw" session (default)
claw-connect -r mysession    # Attach to specific session
claw-connect -l              # List sessions
claw-connect -k mysession    # Kill session
claw-connect --init-tmux     # Install tmux config on remote
```

**Session auto-create** — Uses `tmux new-session -A` which attaches if the session exists or creates it if not. No manual session management needed.

**Working directory & history preserved** — When you detach or your shell exits, claw-connect saves your last working directory. Reconnecting restores it automatically.

### Session Tracking

Session state is automatically tracked per profile for working directory restoration.

```bash
claw-connect sessions                # List tracked session states (includes last CWD)
claw-connect -p staging sessions     # Filter by profile
claw-connect clean-sessions          # Remove stale session states
```

When you run `claw-connect` without flags, it defaults to resume mode — automatically attaching to your last session or creating a new one.

### Plain SSH

```bash
claw-connect                 # Just SSH in
claw-connect -u root         # Override user
```

## Options

| Flag | Description |
|------|-------------|
| *(none)* | Default: resume tmux session |
| `-t, --tunnel` | SSH tunnel (gateway on `:18789` + `/vnc` viewer) |
| `-v, --vnc` | Direct VNC tunnel (`:5900`, needs VNC client) |
| `-r, --resume [NAME]` | Attach/create tmux session (default: "openclaw") |
| `-l, --list` | List remote tmux sessions |
| `-k, --kill NAME` | Kill remote tmux session |
| `-p, --profile NAME` | Use named profile |
| `-u, --user USER` | Override SSH user |
| `--update` | Update claw-connect to latest version |
| `--init-tmux` | Install tmux config (enables `remain-on-exit` to preserve history) |
| `--version` | Print version |
| `-h, --help` | Show help |

## Session Management Commands

| Command | Description |
|---------|-------------|
| `sessions` | List tracked session states (all profiles) |
| `sessions -p NAME` | List sessions for a specific profile |
| `clean-sessions` | Remove stale session states |
| `clean-sessions -p NAME` | Clean sessions for a specific profile |

## Requirements

- SSH access to the remote server (PEM key)
- OpenClaw gateway running on remote (port 18789)
- For browser VNC: `gateway.browser.vnc.enabled: true` in `openclaw.json`
- For direct VNC: `Xvfb` + `x11vnc` on remote (port 5900)

## How It Works

1. **Token auto-fetch**: Reads gateway auth token from remote `openclaw.json`, resolves `${VAR}` references from `.env`
2. **Tunnel takeover**: Starting a tunnel automatically kills any existing tunnel on the same port
3. **Host key handling**: Uses ephemeral known hosts — server reprovisioning never causes connection failures
4. **Single tunnel**: One SSH connection forwards port 18789 (gateway serves both UI and VNC)
5. **Built-in viewer**: The gateway's `/vnc` route serves noVNC — no separate proxy or scripts

---

MIT License
