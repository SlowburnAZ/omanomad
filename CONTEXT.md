# omanomad

Omarchy bar-widget plugin that installs and controls the Project NOMAD offline knowledge server on Arch-based systems.

## Language

**Project NOMAD**:
The upstream offline knowledge server (Crosstalk Solutions), administered through its Command Center web UI.
_Avoid_: NOMAD stack (means the running containers, not the project)

**Command Center**:
Project NOMAD's management web interface at `http://localhost:8080`.
_Avoid_: dashboard, admin UI, management interface

**Stack update**:
Pulling the latest NOMAD container images and force-recreating the containers (`bin/update.sh`). No data loss expected.
_Avoid_: upgrade, refresh, update (bare — ambiguous with plugin update)

**Plugin update**:
Releasing or installing a new version of omanomad itself (`omarchy plugin update slowburnaz.omanomad`).
_Avoid_: update (bare — ambiguous with stack update)

**Purge**:
Uninstalling with `--purge-data`: removes `/opt/project-nomad` and the shared volume. Without the flag, uninstall keeps data.
_Avoid_: full uninstall, wipe, clean uninstall

**Not-installed / stopped / running**:
The three states from `bin/status.sh`: compose file absent, compose present but health check failing, health check passing. The panel shows `unknown` (Checking…) plus the reason when the check itself fails (exit 2, e.g. a VPN breaking localhost).
_Avoid_: installed (ambiguous — means compose present, i.e. stopped or running)

**Privileged helper**:
Root-owned copies of the lifecycle scripts at
`/usr/local/share/omanomad` plus sha256 pins at `/etc/omanomad`, run
through the root-owned **entry** (`/usr/local/share/omanomad/entry`,
installed once by the user from the validated commit — it owns the trust
constants; never executed from the checkout). The entry fetches
`bin/lib/seal.sh` by its pinned sha, verifies the pinned sealer checksum,
seals the store (byte-compared against the checkout before install), and
dispatches lifecycle actions to the root-owned `bin/lib/run.sh`, which
allowlist-verifies the checksum before exec. The panel only passes the
entry's fixed path plus action tokens — no program, sha, or digest from
the writable checkout ever reaches root. Root never opens the
user-writable checkout except to read scripts for the byte comparison.
_Avoid_: pkexec script (sounds like the checkout path is executed),
provision (the old checkout-run provisioner is gone — say "seal" or
"seal the helper")
