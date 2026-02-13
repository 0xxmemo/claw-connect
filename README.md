<p align="center">
  <img src="https://xaixapi.com/images/openclaw-lobster.svg" width="120" alt="Claw Connect" />
</p>

# Claw Connect

Remote browser management CLI. SSH into a server running a headless Chromium browser, view it via VNC in your browser, and manage sessions over tmux.

## Install

One-liner — resolves the latest release, clones to `~/.claw-connect`, symlinks to PATH, sets up shell completions:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/0xxmemo/claw-connect/main/install.sh)
```

Or manually:

```bash
git clone https://github.com/0xxmemo/claw-connect.git ~/.claw-connect
~/.claw-connect/install.sh
```

The installer fetches the latest semver release tag from GitHub (e.g. `v1.2.0`) and checks out that version. Re-running the installer updates to the newest release.

### Update

```bash
~/.claw-connect/install.sh
```

### Check version

```bash
claw-connect --version
```

### Uninstall

```bash
sudo rm -f /usr/local/bin/claw-connect
rm -rf ~/.claw-connect ~/.config/claw-connect
# Remove the "# claw-connect completions" block from your shell rc file
```

## Quick start

```bash
# 1. Interactive first-time setup
claw-connect setup

# 2. Deploy the VNC viewer stack to the remote server
claw-connect --deploy

# 3. Open the SSH tunnel
claw-connect --tunnel
# Prints Gateway and VNC URLs — open the VNC URL in your browser
```

## Setup

### Prerequisites (local)

- macOS or Linux with `ssh`, `scp`, and `git`

### Configuration

Run `claw-connect setup` to create a profile interactively. Config is stored per-profile in `~/.config/claw-connect/profiles/<name>/`:

```
~/.config/claw-connect/
  profiles/
    default/
      config       # IP, SSH_USER, TUNNEL_IP, REMOTE_DIR
      cred.pem     # PEM key (copied during setup)
    staging/
      config
      cred.pem
```

| Variable     | Description                                  | Example          |
| ------------ | -------------------------------------------- | ---------------- |
| `IP`         | Public IP of the remote server               | `1.2.3.4`        |
| `TUNNEL_IP`  | Private/tunnel IP (usually same host)        | `10.0.0.1`       |
| `SSH_USER`   | SSH username                                 | `ubuntu`         |
| `REMOTE_DIR` | Directory on the server for VNC viewer files | `/home/user/vnc` |

### Multiple profiles

```bash
claw-connect setup                # create/edit "default" profile
claw-connect setup staging        # create/edit "staging" profile
claw-connect profiles             # list configured profiles
claw-connect -p staging --tunnel  # use a named profile
```

## Commands

| Command | Description |
| --- | --- |
| `claw-connect` | SSH into the server |
| `claw-connect --tunnel` | SSH tunnel — gateway (18789) + VNC browser (6090) |
| `claw-connect --vnc` | Direct VNC tunnel on port 5900 (fastest, native client) |
| `claw-connect --deploy` | Deploy/update VNC stack on the remote server |
| `claw-connect --resume [name]` | Attach to a tmux session (default: `openclaw`) |
| `claw-connect --list` | List remote tmux sessions |
| `claw-connect --kill <name>` | Kill a remote tmux session |
| `claw-connect --init-tmux` | Install optimized tmux config on remote |
| `claw-connect setup [profile]` | Interactive setup wizard |
| `claw-connect profiles` | List configured profiles |
| `claw-connect --version` | Print installed version |
| `-p <profile>` | Use a named profile (works with any command) |
| `-u <user>` | Override SSH user |

### Deploy details

`--deploy` is idempotent — it skips what's already set up and only restarts the proxy when files change.

1. **Dependencies** — installs `bun`, `x11vnc`, `novnc` on the remote if missing
2. **Files** — uploads `viewer.html` and `novnc-proxy.mjs`
3. **Services** — creates and enables systemd units:
   - `xvfb` — virtual X display (1920x1080)
   - `x11vnc` — VNC server with server-side scaling
   - `openclaw-novnc-proxy` — auth proxy (Bun, WebSocket-to-TCP bridge)

## Releasing

Releases are automated via GitHub Actions. To publish a new version:

```bash
git tag v1.0.0
git push origin v1.0.0
```

This triggers the [release workflow](.github/workflows/release.yml) which:

1. Creates a GitHub Release with auto-generated notes
2. Prepends the release entry to [CHANGELOG.md](CHANGELOG.md) and commits it to `main`

Tags follow [semver](https://semver.org/): `vMAJOR.MINOR.PATCH`.

## Architecture

```
Local machine                          Remote server
--------------                         -------------

Browser path (--tunnel):
  browser → localhost:6090 ─── SSH ───→ novnc-proxy (Bun, :6090)
                tunnel                       │ direct TCP
                                        x11vnc (:5900)
                                             │
                                        Xvfb (:99, 1920×1080)
                                             │
                                        Chromium (headless)

Native VNC path (--vnc):
  VNC client → localhost:5900 ── SSH ──→ x11vnc (:5900)
                   tunnel                    │
                                         Xvfb (:99)
```

## Files

```
.
├── install.sh            # Installer (works via curl | bash too)
├── connect.sh            # Main CLI
├── CHANGELOG.md          # Auto-maintained by CI
├── .github/workflows/
│   └── release.yml       # Tag → Release + CHANGELOG automation
├── completions/
│   ├── _claw-connect     # zsh completions
│   └── claw-connect.bash # bash completions
└── vnc-viewer/
    ├── novnc-proxy.mjs   # Auth proxy + WS→TCP bridge (Bun)
    └── viewer.html       # noVNC browser client
```

Shell completions (bash, zsh, fish) are installed automatically.
