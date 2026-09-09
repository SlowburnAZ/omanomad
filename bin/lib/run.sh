#!/bin/bash
# omanomad privileged bootstrap.
#
# This file runs as root via pkexec, but ONLY from its provisioned,
# root-owned location (/usr/local/share/omanomad/run.sh) — never from the
# user-writable plugin checkout. It executes a single lifecycle script from
# the root-owned store after verifying its checksum against the root-owned
# pins in /etc/omanomad/SHA256SUMS, so a compromised user session cannot
# redirect root execution by editing the checkout between UI confirmation
# and root's open: unknown names, unpinned names, tampered copies, links,
# and unexpected arguments all abort instead of executing.
#
# Test overrides (never set in production): OMANOMAD_STORE, OMANOMAD_PINS.
set -uo pipefail

STORE="${OMANOMAD_STORE:-/usr/local/share/omanomad/bin}"
PINS="${OMANOMAD_PINS:-/etc/omanomad/SHA256SUMS}"

name="${1:-}"
[[ "$name" =~ ^[a-z-]+\.sh$ ]] || { echo "run.sh: rejected script name" >&2; exit 1; }
shift || true

# uninstall.sh is the only script that takes an argument, and only this one.
if [[ "$name" == "uninstall.sh" ]]; then
  if [[ $# -gt 1 || ($# -eq 1 && "$1" != "--purge-data") ]]; then
    echo "run.sh: rejected argument" >&2
    exit 1
  fi
elif [[ $# -gt 0 ]]; then
  echo "run.sh: rejected argument" >&2
  exit 1
fi

target="${STORE}/${name}"
[[ -f "$target" && ! -L "$target" ]] || { echo "run.sh: ${name} is not provisioned" >&2; exit 1; }

# Dots are regex-active; escape them so the lookup cannot over-match.
name_esc="${name//./\\.}"
expected="$(grep -E "^[0-9a-f]{64}  ${name_esc}\$" "$PINS" 2>/dev/null)" \
  || { echo "run.sh: no pin for ${name}" >&2; exit 1; }
# Hash by relative name from inside the store: sha256sum prints the operand
# path, and the pins record relative names, so compare like with like.
actual="$(cd "$STORE" && sha256sum "$name")" || exit 1
[[ "$actual" == "$expected" ]] || { echo "run.sh: checksum mismatch for ${name}" >&2; exit 1; }

exec bash "$target" "$@"
