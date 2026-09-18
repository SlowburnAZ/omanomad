#!/bin/bash
# omanomad: report privileged-helper state for the panel (unprivileged).
# Prints KEY=VALUE lines: state=(missing|stale|ok) plus source=<tree id>.
# Best-effort UX signal only: root verifies pins on every privileged run
# regardless of what this reports, so a wrong answer here cannot weaken
# root — at worst the user runs a stale helper until re-provisioning.
# Test overrides (never set in production): OMANOMAD_RUN, OMANOMAD_PINS,
# OMANOMAD_SOURCE. Harmless: root never consumes this script's output.
RUN="${OMANOMAD_RUN:-/usr/local/share/omanomad/run.sh}"
PINS="${OMANOMAD_PINS:-/etc/omanomad/SHA256SUMS}"
RECORDED="${OMANOMAD_SOURCE:-/etc/omanomad/SOURCE}"

if [[ ! -f "$RUN" || ! -f "$PINS" || ! -f "$RECORDED" ]]; then
  echo "state=missing"
  exit 0
fi

BINDIR="$(dirname "${BASH_SOURCE[0]}")"
current=""
if [[ -e "${BINDIR}/../.git" ]] && command -v git &> /dev/null; then
  # The helper is sealed from a marketplace-validated release tag; the
  # checkout is current when HEAD sits exactly on a release tag matching
  # the recorded SOURCE. Dev commits or tag drift read as stale and route
  # the next privileged action through the refresh dialog.
  if ref="$(git -C "${BINDIR}/.." describe --tags --exact-match HEAD 2>/dev/null)" \
    && [[ "$ref" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    current="$ref"
  fi
fi
if [[ -z "$current" ]]; then
  tree_hash="$(cd "$BINDIR" && sha256sum install.sh start.sh stop.sh uninstall.sh update.sh lib/preflight.sh lib/run.sh lib/seal.sh 2>/dev/null | sha256sum | cut -d' ' -f1)"
  current="tree:${tree_hash}"
fi

recorded="$(cat "$RECORDED" 2>/dev/null)"
if [[ -n "$current" && "$current" == "$recorded" ]]; then
  echo "state=ok"
else
  echo "state=stale"
fi
echo "source=${current}"
