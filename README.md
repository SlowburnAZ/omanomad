# omanomad — Project NOMAD for Omarchy

Omarchy shell bar-widget plugin: install, start, stop, and open the
[Project NOMAD](https://github.com/Crosstalk-Solutions/project-nomad)
offline knowledge server (Command Center on `http://localhost:8080`).

## Install

```bash
omarchy plugin add https://github.com/SlowburnAZ/omanomad --enable
```

The NOMAD widget appears in the bar (right section). Open it and press
**Install Project NOMAD**.

## Requirements

- Arch-based system (Omarchy), `x86_64` (other architectures warn and continue, upstream images are x86_64-only)
- 5 GB free disk space
- Docker — installed automatically from the official Arch repos via pacman; nothing to do by hand

## VPNs

Disconnect before installing, updating, or running: the panel detects a
running stack by polling `http://localhost:8080/api/health`, and some VPN
clients (observed with Nym) break localhost HTTP entirely — the panel then
shows an unreachable-health error with a disconnect hint instead of a state.
The installer also derives the printed LAN URL from the default route, so it
shows the VPN endpoint instead of the LAN address while connected.

## What the panel does

| UI action           | Command run                                                  |
|---------------------|--------------------------------------------------------------|
| Status polling      | `bin/status.sh` (unprivileged, every `refreshIntervalSec`; exit 2 + reason when unobservable) |
| Install             | floating terminal: `pkexec bash bin/install.sh`             |
| Start               | `pkexec bash bin/start.sh`                                   |
| Stop                | `pkexec bash bin/stop.sh`                                    |
| Update              | floating terminal: `pkexec bash bin/update.sh` (confirm)     |
| Open Command Center | browser at `http://localhost:8080`                           |
| Uninstall…          | floating terminal: `pkexec bash bin/uninstall.sh` (confirm)  |
| …with purge         | same, with `--purge-data` (second confirm)                   |

`pkexec` (not `sudo`) is used because the panel has no terminal for a
password prompt. Install/update/uninstall run in a floating terminal so their
interactive prompts (confirmation, license) work.

## Uninstall and `--purge-data`

- **Uninstall** stops and removes the containers, helpers, and
  `compose.yml`, but keeps `storage/`, `mysql/`, `redis/`, and the
  `nomad-update-shared` volume. The panel returns to the Install state;
  reinstalling regenerates `compose.yml` with fresh secrets.
- **Uninstall with `--purge-data`** additionally deletes
  `/opt/project-nomad` entirely and removes the
  `project-nomad_nomad-update-shared` volume. Storage is never deleted
  without this flag.

## Upstream divergences

Arch port of upstream `install/install_nomad.sh` (Debian-only upstream):

- pacman packages instead of apt: `curl`, `gnupg`, `pciutils`, `jq`,
  `docker`, `docker-compose`, `nvidia-container-toolkit`
- Docker from the Arch repos (`systemctl enable --now`); the
  `https://get.docker.com` convenience script is never fetched or executed
- Arch gate (`/etc/arch-release`) instead of the Debian gate
- `chown` targets `${SUDO_USER}` instead of `$(whoami)` (correct owner
  when run under elevated privileges)
- No `usermod -aG docker` (avoids forcing a re-login); `sudo docker`
  invocations kept
- No firewall rules (nothing blocks `localhost:8080` by default)
- Upstream's dead commented-out `free_space_check()` not ported
  (references another project's files)

Stack update is an Arch port of upstream `install/update_nomad.sh` (v1.0.1)
with the same adaptations (Arch gate, `ip`-first LAN discovery,
`sudo`-prefixed compose calls). Shared pre-flight checks, colors, and LAN
discovery live once in `bin/lib/preflight.sh`, sourced by both scripts.

## License

MIT — see `LICENSE`. (Upstream Project NOMAD itself is Apache-2.0; the
installer still presents its Apache terms during install.)
