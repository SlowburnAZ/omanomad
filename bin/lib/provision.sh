#!/bin/bash
# omanomad privileged-helper provisioning.
#
# Usage: provision.sh <checkout-bin-dir> <source-id>
#
# Copies the plugin's lifecycle scripts from the user-writable checkout into
# the root-owned store (/usr/local/share/omanomad) and records their
# checksums plus the checkout's source id in root-owned pins
# (/etc/omanomad). Every later privileged action runs through the
# provisioned run.sh bootstrap, which refuses anything not pinned here.
#
# TRUST-ON-FIRST-USE: this must run only immediately after installing or
# updating the plugin from a source you trust. A same-UID attacker present
# at this exact moment could poison the seed; afterwards the root-owned
# pins and copies are immutable to non-root users, so checkout tampering
# can only make root refuse to run, never redirect it.
#
# Test overrides (never set in production): OMANOMAD_STORE, OMANOMAD_ETCDIR.
set -euo pipefail

STORE="${OMANOMAD_STORE:-/usr/local/share/omanomad/bin}"
ETCDIR="${OMANOMAD_ETCDIR:-/etc/omanomad}"
SRCBIN="${1:?usage: provision.sh <checkout-bin-dir> <source-id>}"
SOURCE_ID="${2:?usage: provision.sh <checkout-bin-dir> <source-id>}"

# The source id is only a drift-detection label (the pins below are the
# security boundary), but keep it to sane characters regardless. No dots
# or slashes: ids are `git:<sha>`, `tree:<hash>`, or simple labels, so
# path-like values (`../../x`) are never legitimate — reject them.
[[ "$SOURCE_ID" =~ ^[A-Za-z0-9_:+-]{1,128}$ ]] || { echo "provision.sh: bad source id" >&2; exit 1; }
[[ -d "$SRCBIN" ]] || { echo "provision.sh: not a directory: ${SRCBIN}" >&2; exit 1; }

# Lifecycle scripts executed as root, plus the library they source.
PINNED="install.sh start.sh stop.sh uninstall.sh update.sh lib/preflight.sh"
for f in $PINNED; do
  [[ -f "${SRCBIN}/${f}" && ! -L "${SRCBIN}/${f}" ]] \
    || { echo "provision.sh: missing or linked: ${f}" >&2; exit 1; }
done

RUN_SRC="${SRCBIN}/lib/run.sh"
[[ -f "$RUN_SRC" && ! -L "$RUN_SRC" ]] || { echo "provision.sh: missing lib/run.sh" >&2; exit 1; }

install -d -m 755 -o root -g root "$(dirname "$STORE")" "$STORE"
install -d -m 755 -o root -g root "$ETCDIR"

# Start clean so removed files cannot linger in the store, then recreate
# the layout (the wipe also removes lib/).
find "$STORE" -mindepth 1 -delete
install -d -m 755 -o root -g root "${STORE}/lib"
cp "${SRCBIN}/install.sh" "${SRCBIN}/start.sh" "${SRCBIN}/stop.sh" \
  "${SRCBIN}/uninstall.sh" "${SRCBIN}/update.sh" "$STORE/"
cp "${SRCBIN}/lib/preflight.sh" "${STORE}/lib/"
cp "$RUN_SRC" "$(dirname "$STORE")/run.sh"

chown -R root:root "$(dirname "$STORE")" "$ETCDIR"
find "$(dirname "$STORE")" -type d -exec chmod 755 {} +
find "$(dirname "$STORE")" -type f -exec chmod 644 {} +
chmod 755 "$(dirname "$STORE")/run.sh" \
  "$STORE/install.sh" "$STORE/start.sh" "$STORE/stop.sh" \
  "$STORE/uninstall.sh" "$STORE/update.sh"

(cd "$STORE" && sha256sum install.sh start.sh stop.sh uninstall.sh update.sh lib/preflight.sh) \
  | install -m 644 -o root -g root /dev/stdin "${ETCDIR}/SHA256SUMS"
printf '%s\n' "$SOURCE_ID" | install -m 644 -o root -g root /dev/stdin "${ETCDIR}/SOURCE"

echo "Privileged helper provisioned from ${SRCBIN} (source ${SOURCE_ID})."
