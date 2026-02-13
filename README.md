# Claw Connect

Remote browser management toolkit. SSH into an AWS instance running a headless Chromium browser, view it via VNC in your browser, and manage sessions over tmux.

## Quick start

```bash
# 1. Copy and fill in your config
cp .env.example .env
# Edit .env with your server IP, SSH user, and PEM filename

# 2. Deploy the VNC viewer stack to the remote server
./connect.sh --deploy

# 3. Open the SSH tunnel
./connect.sh --tunnel
# Prints Gateway and VNC URLs — open the VNC URL in your browser
```

## Setup

### Prerequisites (local)

- macOS or Linux with `ssh` and `scp`
- A PEM key file for the remote server (default: `cred.pem`)

### Configuration

All config lives in `.env` (git-ignored). Copy `.env.example` and fill in your values:

| Variable     | Description                                     | Example                          |
| ------------ | ----------------------------------------------- | -------------------------------- |
| `IP`         | Public IP of the remote server                  | `1.2.3.4`                        |
| `TUNNEL_IP`  | Private/tunnel IP (usually same host)           | `10.0.0.1`                       |
| `SSH_USER`   | SSH username                                    | `ubuntu`                         |
| `PEM_FILE`   | PEM key filename (relative to project root)     | `cred.pem`                       |
| `REMOTE_DIR` | Directory on the server for VNC viewer files     | `/home/ubuntu/vnc`               |

## Commands

### `./connect.sh` -- SSH

Plain SSH connection to the remote server.

```bash
./connect.sh              # Connect with default user from .env
./connect.sh -u ec2-user  # Override SSH user
```

### `./connect.sh --tunnel` -- SSH tunnel

Creates an SSH tunnel forwarding two ports to localhost:

- **18789** -- OpenClaw gateway
- **6090** -- VNC viewer (noVNC auth proxy)

Prints clickable URLs with the gateway token. Open the VNC URL in your browser to see the remote desktop.

```bash
./connect.sh --tunnel
# Gateway: http://localhost:18789/?token=...
# VNC:     http://localhost:6090/?token=...
```

### `./connect.sh --deploy` -- Deploy VNC stack

Deploys and configures the full VNC viewer stack on the remote server. Idempotent -- skips what's already set up, only restarts the proxy when files change.

What it does:

1. **Dependencies** -- installs `bun`, `x11vnc`, `websockify`, `novnc` if missing
2. **Files** -- uploads `viewer.html` and `novnc-proxy.mjs`
3. **Services** -- creates systemd services (if missing) for the full stack:
   - `xvfb.service` -- virtual X display (1920x1080)
   - `x11vnc.service` -- VNC server on the virtual display
   - `websockify.service` -- WebSocket bridge (port 6080)
   - `openclaw-novnc-proxy.service` -- authenticated noVNC proxy (port 6090, Bun)

All services are enabled for auto-start on boot.

```bash
./connect.sh --deploy
```

### `./connect.sh --resume` -- Tmux sessions

Attach to (or create) a tmux session on the remote server. Optimized for low-latency remote CLI use.

```bash
./connect.sh --resume                # Attach to 'openclaw' session
./connect.sh --resume mysession      # Attach to 'mysession'
./connect.sh --list                  # List all tmux sessions
./connect.sh --kill mysession        # Kill a session
./connect.sh --init-tmux             # Install optimized tmux config (once)
```

## Architecture

```
Local machine                          Remote server (AWS)
--------------                         -------------------
browser ──> localhost:6090 ─── SSH ───> novnc-proxy (Bun, :6090)
                tunnel                      │
                                       websockify (:6080)
                                            │
                                       x11vnc (:5900)
                                            │
                                       Xvfb (:99, 1920x1080)
                                            │
                                       Chromium (headless)
```

### VNC viewer (`vnc-viewer/`)

- **`novnc-proxy.mjs`** -- Bun server that authenticates via `OPENCLAW_GATEWAY_TOKEN`, serves `viewer.html`, and proxies WebSocket VNC traffic to websockify.
- **`viewer.html`** -- Minimal noVNC client. Connects to the VNC stream, auto-reconnects with backoff if the server is down. No tab selector (the remote browser tabs are visible in the VNC stream itself).

## Files

```
.
├── .env.example        # Config template
├── .env                # Your config (git-ignored)
├── .gitignore
├── connect.sh          # Main CLI tool
├── cred.pem            # SSH key (git-ignored)
├── README.md
└── vnc-viewer/
    ├── novnc-proxy.mjs # Auth proxy server (Bun)
    └── viewer.html     # noVNC browser client
```
