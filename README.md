# OmaNomad — Project NOMAD for Omarchy

Omarchy shell bar-widget plugin: install, start, stop, and open the
[Project NOMAD](https://github.com/Crosstalk-Solutions/project-nomad)
offline knowledge server (Command Center on `http://localhost:8080`).

## Install

```bash
omarchy plugin add https://github.com/SlowburnAZ/omanomad --enable
```

The NOMAD widget appears in the bar (right section). Open it and press
**Install Project NOMAD**.

To remove the plugin itself: `omarchy plugin remove slowburnaz.omanomad`. The NOMAD
stack stays installed until you uninstall it from the panel (see
[Uninstall and `--purge-data`](#uninstall-and---purge-data)).

## Requirements

- Arch-based system (Omarchy), `x86_64` (other architectures warn and continue, upstream images are x86_64-only)
- 5 GB free disk space
- Docker — installed automatically from the official Arch repos via pacman; nothing to do by hand

## VPNs

Disconnect before installing, updating, or running: the panel detects a
running stack by polling `http://localhost:8080/api/health`, and some VPN
clients (observed with Nym) break localhost HTTP entirely — the panel then
shows an unreachable-health error with a disconnect hint instead of a state.
A refused or reset connection simply reports stopped (nothing listening yet,
or the stack still starting); the hint only fires on genuine observability
failures such as timeouts.
The installer also derives the printed LAN URL from the default route, so it
shows the VPN endpoint instead of the LAN address while connected.

## What the panel does

| UI action                | Command run                                                  |
|--------------------------|--------------------------------------------------------------|
| Status polling           | `bin/status.sh` (unprivileged; every `refreshIntervalSec` in panel, every 2 min for the bar icon; refused/reset health (curl 7/52/56) counts as stopped, other curl failures exit 2 + reason) |
| Retry status check       | re-runs `bin/status.sh` immediately (unknown state)          |
| Install                  | floating terminal: sealed helper runs `install.sh`           |
| Start / Stop (icon)      | sealed helper runs `start.sh` / `stop.sh`; start also restarts installed components once the Command Center is healthy |
| Stack update (icon)      | floating terminal: sealed helper runs `update.sh` (confirm)  |
| Uninstall (icon)         | opens the chooser — Just uninstall or Delete data too; each choice gets a confirmation dialog |
| — Just uninstall         | floating terminal: sealed helper runs `uninstall.sh` (confirm) |
| — Delete data too        | floating terminal: sealed helper runs `uninstall.sh --purge-data` (confirm) |
| Open Command Center      | browser at `http://localhost:8080`                           |

## Privileged helper

Install, stack update, uninstall, start, and stop run as root — but never
from the plugin checkout itself, and root never even *reads* a script out
of the checkout. When the helper is missing or stale, the panel's pkexec
entry runs a fixed, root-owned `bash -c` one-liner that downloads the
sealer (`bin/lib/seal.sh`) from the plugin's **marketplace-validated full
commit sha** on GitHub and executes the fetched bytes only after their
sha256 matches a checksum constant committed in the validated panel —
a moved tag cannot substitute code. The sealer then downloads every
lifecycle script from that same immutable commit and requires them to
match your checkout **byte-for-byte** before installing anything: the
root-owned copies in `/usr/local/share/omanomad` and the sha256 pins in
root-owned `/etc/omanomad` always contain exactly the code the marketplace
validated at that commit. A tampered checkout — before or after you
confirm — makes root refuse instead of installing the tampered copy.

Every privileged action then runs `pkexec /usr/local/share/omanomad/run.sh
<script>`, and that bootstrap executes only a script whose checksum
matches its pin — unknown names, tampered copies, links, and unexpected
arguments abort instead of running. A compromised user session therefore
cannot redirect root execution by editing the checkout between your
confirmation and root's open, and there is no race window on the
provisioning path either: the sealer and the sealed scripts are fetched
over HTTPS from the validated commit, not read from user-writable
storage.

The stack's container images are likewise pinned by immutable digest in
the compose file (see *Upstream divergences*), so an upstream tag change
cannot swap the running images underneath an approved install.

To remove the helper (e.g. before removing the plugin):
`sudo rm -rf /usr/local/share/omanomad /etc/omanomad`.

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

- Upstream assets (`management_compose.yaml`, the start/stop/update helper
  scripts) are pinned to the upstream `v1.34.1` release commit and verified
  against sha256 checksums committed here; a tampered or changed download
  aborts the install
- All six container images are re-written to immutable
  `image@sha256:…` digest pins before use; a stack update refuses a
  compose file with any mutable image reference. Bumping a digest is a
  plugin release (fresh marketplace validation), never a runtime pull of
  "whatever the tag holds now"
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
