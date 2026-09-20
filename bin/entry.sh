#!/bin/bash
# omanomad privileged entry (root-owned; installed OUTSIDE the plugin tree).
#
# This file is NEVER executed from the plugin checkout. It is installed once
# by the user with the command in the README (Privileged helper section),
# which fetches these exact bytes from the marketplace-validated commit over
# TLS and places them at a fixed root-owned path. The panel then only ever
# invokes that path with small action tokens — no shell program, commit, or
# digest ever crosses from the user-writable plugin tree into root execution.
#
# Trust anchor: the two constants below live in this root-owned file, not in
# the checkout. SEALED_SHA names the immutable, marketplace-validated commit
# (a tag can be moved; a full commit sha cannot); SEALER_SHA256 is the sha256
# of bin/lib/seal.sh at that commit. Sealing fetches the sealer by the sha,
# verifies it against the digest, then byte-compares every lifecycle script
# against the checkout before anything is installed: a tampered checkout
# (before or after user consent) fails the comparison and nothing is
# installed. Root never executes any checkout pathname.
#
# Test overrides (never set in production): OMANOMAD_STORE, OMANOMAD_ETCDIR,
# OMANOMAD_UPSTREAM_BASE (e.g. a file:// directory mirroring the repo's
# bin/ layout).
set -euo pipefail

SEALED_SHA="PENDING_RELEASE_SHA"
SEALER_SHA256="PENDING_SEALER_SHA256"

STORE="${OMANOMAD_STORE:-/usr/local/share/omanomad/bin}"
UPSTREAM="${OMANOMAD_UPSTREAM_BASE:-https://raw.githubusercontent.com/SlowburnAZ/omanomad}"

case "${1:-}" in
  seal)
    srcbin="${2:?usage: entry seal <checkout-bin-dir> [--then start.sh|stop.sh]}"
    then_=""
    if [[ $# -ge 3 ]]; then
      if [[ "$3" != "--then" || $# -ne 4 ]]; then
        echo "entry: rejected arguments" >&2
        exit 1
      fi
      then_="$4"
    fi
    if [[ "$then_" != "" && "$then_" != "start.sh" && "$then_" != "stop.sh" ]]; then
      echo "entry: rejected continuation: ${then_}" >&2
      exit 1
    fi
    if [[ ! "$SEALED_SHA" =~ ^[0-9a-f]{40}$ ]]; then
      echo "entry: bad pinned sha" >&2
      exit 1
    fi
    # Fetch the sealer from the immutable pinned commit and verify it against
    # the pinned digest before executing it. A 404 or a tampered download
    # aborts here.
    u="${UPSTREAM}/${SEALED_SHA}/bin/lib/seal.sh"
    t="$(mktemp)"
    cleanup() { rm -f "$t"; }
    trap cleanup EXIT
    if ! curl -fsSL --retry 5 --retry-delay 3 --connect-timeout 15 --max-time 120 --max-filesize 1048576 "$u" -o "$t"; then
      echo "entry: sealer download failed" >&2
      exit 1
    fi
    if ! echo "$SEALER_SHA256  $t" | sha256sum -c --strict >/dev/null 2>&1; then
      echo "entry: downloaded sealer does not match pinned checksum" >&2
      exit 1
    fi
    # Runs the byte-compare + store install; a tampered checkout makes it
    # refuse. With set -e a failure exits this script with its status.
    bash "$t" "$srcbin" "$SEALED_SHA"
    if [[ "$then_" == "" ]]; then
      exit 0
    fi
    # Chained continuation for non-interactive actions (one polkit prompt for
    # seal + action). The allowlist gate stays in the root-owned run.sh.
    exec "$(dirname "$STORE")/run.sh" "$then_"
    ;;
  run)
    script="${2:?usage: entry run <lifecycle-script> [args]}"
    case "$script" in
      install.sh|start.sh|stop.sh|uninstall.sh|update.sh) ;;
      *) echo "entry: rejected script name" >&2; exit 1 ;;
    esac
    if [[ $# -gt 2 ]]; then
      if [[ "$script" != "uninstall.sh" || "$3" != "--purge-data" || $# -ne 3 ]]; then
        echo "entry: rejected arguments" >&2
        exit 1
      fi
    fi
    exec "$(dirname "$STORE")/run.sh" "${@:2}"
    ;;
  *)
    echo "usage: entry seal <checkout-bin-dir> [--then start.sh|stop.sh] | entry run <lifecycle-script> [args]" >&2
    exit 1
    ;;
esac
