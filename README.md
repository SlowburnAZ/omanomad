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
from the plugin checkout itself. Root work goes through a small **entry**
program that lives outside the plugin tree and owns the entire privileged
program plus its trust constants (the validated commit sha and the
sealer's checksum). The panel only ever invokes the fixed root-owned path
with small action tokens — no shell program, commit sha, or digest ever
reaches root from the user-writable checkout, so a tampered checkout
cannot change what root executes.

### One-time entry install

Before the first privileged action — and again after a plugin update that
bumps the sealing commit — run this once from a terminal. A single
root-owned process downloads the entry into its own private temporary
directory (mode 700, unprivileged users cannot read or write it), verifies
the pinned sha256 **there**, installs it root-owned at a fixed path, and
removes the staging directory when the process exits — success or failure:

```bash
sudo bash -c 'd=$(mktemp -d /tmp/omanomad-entry.XXXXXXXXXX); chmod 700 "$d"; trap "rm -rf \"$d\"" EXIT; curl -fsSL --retry 5 --retry-delay 3 --connect-timeout 15 --max-time 120 --max-filesize 1048576 "https://raw.githubusercontent.com/SlowburnAZ/omanomad/main/bin/entry.sh" -o "$d/entry" && echo "633d6f24930b64d53a825e5c3fb85f27a7a24fc4f9e6ef67f8de7ed32766655c  $d/entry" | sha256sum -c --strict && install -d -m 755 /usr/local/share/omanomad && install -m 700 "$d/entry" /usr/local/share/omanomad/entry'
```

The fetch locator (`main`) is just transport: the pinned sha256 is the
trust anchor, and the same privileged process that downloads the bytes also
verifies and installs them — inside the root-private staging directory, and
from there into `/usr/local/share/omanomad`, both of which the unprivileged
user cannot write. There is no window where a user-writable file sits
between verification and installation, and the staged bytes are removed
with the process, so nothing attacker-influenceable survives a failed or
interrupted run. Take this command from this README **as published on
GitHub** — not from any local copy, which is user-writable. After a
release that changes the entry, the hash above is updated in the same
release.

When you then trigger a privileged action, pkexec asks once for
confirmation and the root-owned entry takes over: it fetches the sealer
(`bin/lib/seal.sh`) by its pinned commit sha, verifies it against its
pinned sha256, and only then executes it. The sealer downloads every
lifecycle script from the same immutable commit and requires them to
match your checkout **byte-for-byte** before installing anything: the
root-owned copies in `/usr/local/share/omanomad` and the sha256 pins in
root-owned `/etc/omanomad` always contain exactly the code the marketplace
validated at that commit. A tampered checkout — before or after you
confirm — makes root refuse instead of installing the tampered copy; a
stale entry (pinned to an older commit than your updated checkout) fails
the comparison the same way until you re-run the install command.

Every privileged action then runs `pkexec /usr/local/share/omanomad/entry
run <script>`, and the entry dispatches only allowlisted lifecycle names
to the root-owned `bin/lib/run.sh` bootstrap, which executes only a
script whose checksum matches its pin — unknown names, tampered copies,
links, and unexpected arguments abort instead of running. A compromised
user session therefore cannot redirect root execution by editing the
checkout between your confirmation and root's open, and there is no race
window on the provisioning path either: the sealer and the sealed scripts
are fetched over HTTPS from the validated commit, not read from
user-writable storage.

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
  against sha256 checksums committed here; each download is staged in a
  root-private directory, checksum-checked there, and refused if a symlink
  or non-regular file was planted at the destination before the verified
  bytes are installed. A tampered or changed download aborts the install
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
