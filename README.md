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
```

Opens an SSH tunnel on `localhost:18789`. Output:

```
Creating SSH tunnel: localhost:18789 -> 172.31.x.x:18789

  Gateway: http://localhost:18789/?token=<auto-fetched>
  Browser: http://localhost:18789/vnc?token=<auto-fetched>

Tunnel will remain active. Press Ctrl+C to close.
```

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
claw-connect -r              # Attach to "openclaw" session
claw-connect -r mysession    # Attach to specific session
claw-connect -l              # List sessions
claw-connect -k mysession    # Kill session
claw-connect --init-tmux     # Install tmux config on remote
```

### Plain SSH

```bash
claw-connect                 # Just SSH in
claw-connect -u root         # Override user
```

## Options

| Flag | Description |
|------|-------------|
| `-t, --tunnel` | SSH tunnel (gateway on `:18789` + `/vnc` viewer) |
| `-v, --vnc` | Direct VNC tunnel (`:5900`, needs VNC client) |
| `-r, --resume [NAME]` | Attach/create tmux session |
| `-l, --list` | List remote tmux sessions |
| `-k, --kill NAME` | Kill remote tmux session |
| `-p, --profile NAME` | Use named profile |
| `-u, --user USER` | Override SSH user |
| `--update` | Update claw-connect to latest version |
| `--init-tmux` | Install tmux config on remote |
| `--version` | Print version |
| `-h, --help` | Show help |

## Requirements

- SSH access to the remote server (PEM key)
- OpenClaw gateway running on remote (port 18789)
- For browser VNC: `gateway.browser.vnc.enabled: true` in `openclaw.json`
- For direct VNC: `Xvfb` + `x11vnc` on remote (port 5900)

## How It Works

1. **Token auto-fetch**: Reads gateway auth token from remote `openclaw.json` via SSH
2. **Single tunnel**: One SSH connection forwards port 18789 (gateway serves both UI and VNC)
3. **Built-in viewer**: The gateway's `/vnc` route serves noVNC — no separate proxy or scripts

---

MIT License
