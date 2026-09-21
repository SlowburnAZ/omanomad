#!/bin/bash
# omanomad: report privileged-helper state for the panel (unprivileged).
# Prints KEY=VALUE lines: state=(missing|stale|ok) plus source=<tree id>.
# Best-effort UX signal only: root verifies pins on every privileged run
# regardless of what this reports, so a wrong answer here cannot weaken
# root — at worst the user runs a stale helper until re-provisioning.
# Test overrides (never set in production): OMANOMAD_RUN, OMANOMAD_PINS,
# OMANOMAD_SOURCE, OMANOMAD_ENTRY. Harmless: root never consumes this
# script's output.
RUN="${OMANOMAD_RUN:-/usr/local/share/omanomad/run.sh}"
PINS="${OMANOMAD_PINS:-/etc/omanomad/SHA256SUMS}"
RECORDED="${OMANOMAD_SOURCE:-/etc/omanomad/SOURCE}"
ENTRY="${OMANOMAD_ENTRY:-/usr/local/share/omanomad/entry}"

entry_present="absent"
if [[ -f "$ENTRY" && ! -L "$ENTRY" ]]; then
  entry_present="present"
fi
echo "entry=${entry_present}"

if [[ ! -f "$RUN" || ! -f "$PINS" || ! -f "$RECORDED" || "$entry_present" == "absent" ]]; then
  echo "state=missing"
  exit 0
fi

BINDIR="$(dirname "${BASH_SOURCE[0]}")"
# Content identity: the sealed store's SHA256SUMS pins exactly what root
# runs, and the checkout is current when its lifecycle set hashes to the
# same bytes. (Comparing HEAD against the recorded sealing commit could
# never read ok: the release merge is always one constants-commit past the
# sealing commit, so every freshly sealed helper reported stale. Root
# verifies these same pins on every privileged run regardless; this signal
# only drives the panel's refresh prompt.)
sealed="$(cat "$PINS" 2>/dev/null)"
current="$(cd "$BINDIR" && sha256sum install.sh start.sh stop.sh uninstall.sh update.sh lib/preflight.sh 2>/dev/null)"
if [[ -n "$sealed" && -n "$current" && "$current" == "$sealed" ]]; then
  echo "state=ok"
else
  echo "state=stale"
fi
echo "source=$(cat "$RECORDED" 2>/dev/null)"
