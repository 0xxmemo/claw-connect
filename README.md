<p align="center">
  <img src="https://xaixapi.com/images/openclaw-lobster.svg" width="120" alt="Claw Connect" />
</p>

# Claw Connect

Remote OpenClaw gateway helper CLI.

`claw-connect` now targets **fork-native noVNC integration** first (served by the OpenClaw gateway itself), while preserving a graceful fallback path for older external noVNC setups.

---

## Compatibility Matrix

| OpenClaw runtime | noVNC mode | `claw-connect --tunnel` behavior |
| --- | --- | --- |
| Fork with built-in VNC (`browser.vnc.enabled: true`) | Native gateway routes (`/vnc`, `/vnc/ws`) | ✅ Primary path (`localhost:18789/vnc`) |
| Older setup with external noVNC/proxy on `:6090` | Legacy | ✅ Fallback URL shown; optional forced tunnel via `--legacy-vnc` |

> Fork-native mode is the recommended default.

---

## Install

One-liner (latest release):

```bash
curl -fsSL https://raw.githubusercontent.com/0xxmemo/claw-connect/main/install.sh | bash
```

Or manually:

```bash
git clone https://github.com/0xxmemo/claw-connect.git ~/.claw-connect
~/.claw-connect/install.sh
```

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

---

## Quickstart (Fork-native)

```bash
# 1) Configure server access profile
claw-connect setup

# 2) On the remote host, enable VNC in OpenClaw config:
# browser.vnc.enabled: true
# then start/restart gateway

# 3) Open tunnels and use native gateway VNC route
claw-connect --tunnel
```

When token discovery succeeds, `--tunnel` prints:

- `Gateway: http://localhost:18789/?token=...`
- `VNC native: http://localhost:18789/vnc?token=...`

If legacy port `6090` exists on remote, a legacy URL is shown automatically.

---

## Setup

### Prerequisites (local)

- macOS or Linux with `ssh`, `scp`, and `git`

### Configuration

Run `claw-connect setup` to create a profile interactively. Config is stored per profile:

```text
~/.config/claw-connect/
  profiles/
    default/
      config       # IP, SSH_USER, TUNNEL_IP
      cred.pem     # PEM key (copied during setup)
```

| Variable | Description | Example |
| --- | --- | --- |
| `IP` | Public IP of remote server | `1.2.3.4` |
| `TUNNEL_IP` | Private/tunnel IP (or same host) | `10.0.0.1` |
| `SSH_USER` | SSH username | `ubuntu` |

---

## Commands

| Command | Description |
| --- | --- |
| `claw-connect` | SSH into the server |
| `claw-connect --tunnel` | SSH tunnel for gateway + native VNC route |
| `claw-connect --tunnel --legacy-vnc` | Force-add legacy `:6090` browser tunnel |
| `claw-connect --vnc` | Direct VNC tunnel on `:5900` |
| `claw-connect --resume [name]` | Attach to a tmux session |
| `claw-connect --list` | List remote tmux sessions |
| `claw-connect --kill <name>` | Kill a remote tmux session |
| `claw-connect --init-tmux` | Install optimized tmux config on remote |
| `claw-connect setup [profile]` | Interactive setup wizard |
| `claw-connect profiles` | List configured profiles |
| `claw-connect --version` | Print installed version |
| `-p <profile>` | Use a named profile |
| `-u <user>` | Override SSH user |

---

## Migration Guide (Old Flow → Fork-native)

### Old flow (removed)

- `claw-connect --deploy`
- Upload custom `viewer.html` + `novnc-proxy.mjs`
- Manage custom `websockify` / proxy services

### New flow (recommended)

1. Use OpenClaw fork with built-in noVNC + gateway integration.
2. Set `browser.vnc.enabled: true` in `openclaw.json`.
3. Restart gateway.
4. Use `claw-connect --tunnel`.
5. Open `http://localhost:18789/vnc?token=...`.

### Temporary fallback for older hosts

If you still run an external legacy noVNC stack on `:6090`:

```bash
claw-connect --tunnel --legacy-vnc
```

or rely on auto-detection (legacy URL is shown when remote `:6090` is open).

---

## Breaking / Behavioral Changes

- `--deploy` is now **deprecated** and exits with migration guidance.
- Custom bundled legacy scripts (`vnc-viewer/novnc-proxy.mjs`, `vnc-viewer/viewer.html`) were removed.
- Primary VNC URL is now gateway-native: `http://localhost:18789/vnc`.

---

## Releasing

Releases are automated via GitHub Actions:

```bash
git tag v1.0.0
git push origin v1.0.0
```

Tags follow [semver](https://semver.org/): `vMAJOR.MINOR.PATCH`.
