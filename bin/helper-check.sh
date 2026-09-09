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
  current="git:$(git -C "${BINDIR}/.." rev-parse HEAD 2>/dev/null)"
fi
if [[ -z "$current" || "$current" == "git:" ]]; then
  tree_hash="$(cd "$BINDIR" && sha256sum install.sh start.sh stop.sh uninstall.sh update.sh lib/preflight.sh lib/run.sh lib/provision.sh 2>/dev/null | sha256sum | cut -d' ' -f1)"
  current="tree:${tree_hash}"
fi

recorded="$(cat "$RECORDED" 2>/dev/null)"
if [[ -n "$current" && "$current" == "$recorded" ]]; then
  echo "state=ok"
else
  echo "state=stale"
fi
echo "source=${current}"
