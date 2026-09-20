#!/bin/bash
# omanomad privileged-helper sealer.
#
# This file is NEVER executed from the plugin checkout. The panel's pkexec
# entry fetches it from a full commit sha on GitHub, verifies the download
# against the sealer sha256 constant committed in the panel, and only then
# runs the fetched bytes as root; this checkout copy exists so the release
# is reviewable and so the marketplace scanner sees the real provisioning
# logic.
#
# Usage (root): seal.sh <checkout-bin-dir> <commit-sha>
#
# Trust anchor: the sha names the immutable, marketplace-validated commit
# on SlowburnAZ/omanomad — a tag can be moved; a full commit sha cannot.
# Every lifecycle script is fetched from that commit over HTTPS and
# byte-compared against the local checkout; only the fetched, verified
# bytes are copied into the root-owned store, and SOURCE records the sha.
# A tampered checkout (before or after user consent) fails the comparison
# and nothing is installed. Root never executes any checkout pathname.
#
# Test overrides (never set in production): OMANOMAD_STORE, OMANOMAD_ETCDIR,
# OMANOMAD_UPSTREAM_BASE (e.g. a file:// directory mirroring the repo's
# bin/ layout).
set -euo pipefail

STORE="${OMANOMAD_STORE:-/usr/local/share/omanomad/bin}"
ETCDIR="${OMANOMAD_ETCDIR:-/etc/omanomad}"
UPSTREAM="${OMANOMAD_UPSTREAM_BASE:-https://raw.githubusercontent.com/SlowburnAZ/omanomad}"
SRCBIN="${1:?usage: seal.sh <checkout-bin-dir> <commit-sha>}"
REF="${2:?usage: seal.sh <checkout-bin-dir> <commit-sha>}"

# The sha selects the immutable, marketplace-validated commit. A tag
# can be moved; a full commit sha cannot. Every fetch below uses the
# sha, so all downloaded bytes are bound to that exact snapshot.
[[ "$REF" =~ ^[0-9a-f]{40}$ ]] || { echo "seal.sh: bad commit sha" >&2; exit 1; }
[[ -d "$SRCBIN" ]] || { echo "seal.sh: not a directory: ${SRCBIN}" >&2; exit 1; }
[[ -d "${SRCBIN}/lib" ]] || { echo "seal.sh: missing lib directory" >&2; exit 1; }

STAGE="$(mktemp -d /tmp/omanomad-seal.XXXXXXXX)"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT
install -d -m 700 "${STAGE}/bin/lib"

# Fetch the release's scripts into a root-owned staging dir. A 404 or a
# truncated body leaves the stage incomplete and the comparisons below
# fail closed.
PINNED="install.sh start.sh stop.sh uninstall.sh update.sh lib/preflight.sh lib/run.sh lib/seal.sh"
for f in $PINNED; do
  curl -fsSL --retry 5 --retry-delay 3 --connect-timeout 15 --max-time 120 --max-filesize 1048576 "${UPSTREAM}/${REF}/bin/${f}" -o "${STAGE}/bin/${f}"
done

# The checkout must byte-match the validated release: a same-UID attacker
# who edited any lifecycle script (before consent or during the race)
# makes root refuse instead of installing the tampered copy.
for f in $PINNED; do
  [[ -f "${SRCBIN}/${f}" && ! -L "${SRCBIN}/${f}" ]] \
    || { echo "seal.sh: missing or linked in checkout: ${f}" >&2; exit 1; }
  cmp -s "${STAGE}/bin/${f}" "${SRCBIN}/${f}" \
    || { echo "seal.sh: checkout ${f} does not match release ${REF}" >&2; exit 1; }
done

install -d -m 755 -o root -g root "$(dirname "$STORE")" "$STORE"
install -d -m 755 -o root -g root "$ETCDIR"

# Build the store layout from the verified stage only (never re-read the
# checkout after validation).
find "$STORE" -mindepth 1 -delete
install -d -m 755 -o root -g root "${STORE}/lib"
cp "${STAGE}/bin/install.sh" "${STAGE}/bin/start.sh" "${STAGE}/bin/stop.sh" \
  "${STAGE}/bin/uninstall.sh" "${STAGE}/bin/update.sh" "$STORE/"
cp "${STAGE}/bin/lib/preflight.sh" "${STORE}/lib/"
cp "${STAGE}/bin/lib/run.sh" "$(dirname "$STORE")/run.sh"

chown -R root:root "$(dirname "$STORE")" "$ETCDIR"
find "$(dirname "$STORE")" -type d -exec chmod 755 {} +
find "$(dirname "$STORE")" -type f -exec chmod 644 {} +
chmod 755 "$(dirname "$STORE")/run.sh" \
  "$STORE/install.sh" "$STORE/start.sh" "$STORE/stop.sh" \
  "$STORE/uninstall.sh" "$STORE/update.sh"

(cd "$STORE" && sha256sum install.sh start.sh stop.sh uninstall.sh update.sh lib/preflight.sh) \
  | install -m 644 -o root -g root /dev/stdin "${ETCDIR}/SHA256SUMS"
printf '%s\n' "$REF" | install -m 644 -o root -g root /dev/stdin "${ETCDIR}/SOURCE"

echo "Privileged helper sealed from release ${REF}."
