#!/bin/bash
# omanomad: list the Command Center's known components (Information
# Library, AI Assistant, Supply Depot catalog, ...) with install/run state.
# The /api/system/services endpoint only reports installed services; the
# full catalog (including not-installed ones) comes from the Command
# Center's supply-depot page payload (Inertia `data-page` JSON).
# Prints one pipe-separated line per component:
#   friendly_name|installed(0|1)|status
# Fails silently (exit 2, reason to stderr): the panel treats component
# info as best-effort garnish, never as state.
DEPOT_URL="http://localhost:8080/supply-depot"

command -v curl &> /dev/null || { echo "curl not found" >&2; exit 2; }
command -v jq &> /dev/null || { echo "jq not found" >&2; exit 2; }

page="$(curl -sf --max-time 5 "$DEPOT_URL" | head -c $((256 * 1024 + 1)))"
# The response is capped before it is captured or parsed: head -c keeps at
# most 256 KiB+1 bytes in memory (a stalled or hostile Command Center cannot
# exhaust the host through this path), and a capture longer than the cap
# means an oversized or truncated-at-cap response — refused, never parsed.
# Truncated-but-small JSON is rejected by jq's parse below.
[[ -n "$page" ]] || { echo "Command Center supply-depot page unreachable or returned nothing." >&2; exit 2; }
if (( ${#page} > 256 * 1024 )); then
  echo "Command Center supply-depot response exceeds the 256 KiB cap; refusing." >&2
  exit 2
fi

# Unescape the data-page attribute, then let jq project the fields. The
# unescape only shrinks (each entity is longer than the character it
# replaces), so the catalog stays within the capped page's size.
catalog="$(printf '%s' "$page" \
  | sed -n 's/.*data-page="\([^"]*\)".*/\1/p' \
  | sed 's/&quot;/"/g; s/&#039;/'"'"'/g; s/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g')"
[[ -n "$catalog" ]] || { echo "No data-page payload found on supply-depot page." >&2; exit 2; }

projection="$(printf '%s' "$catalog" \
  | jq -r '.props.system.services[] | [.friendly_name, .installed, .status, (.ui_location // "-")] | @tsv')" \
  || { echo "Unexpected supply-depot payload shape." >&2; exit 2; }
if [[ -n "$projection" ]]; then
  printf '%s\n' "$projection" | tr '\t' '|'
fi
