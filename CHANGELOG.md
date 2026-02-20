# Changelog

## [Unreleased]

- **Tunnel takeover**: Starting a tunnel now auto-kills any existing tunnel on port 18789
- **Token resolution**: `${VAR}` references in `openclaw.json` are resolved from `.env`
- **Host key handling**: Uses ephemeral known hosts (`UserKnownHostsFile=/dev/null`) — server reprovisioning no longer requires manual `known_hosts` cleanup
- **Zsh completions**: Installer now sets up zsh completions alongside bash
- **Gitignore**: Added `.DS_Store`

## [1.0.0] - 2026-02-13

Initial release.
