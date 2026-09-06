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

page="$(curl -sf --max-time 5 "$DEPOT_URL")" || { echo "Command Center supply-depot page unreachable." >&2; exit 2; }
[[ -n "$page" ]] || { echo "Command Center supply-depot page returned nothing." >&2; exit 2; }

# Unescape the data-page attribute, then let jq project the fields.
catalog="$(printf '%s' "$page" \
  | sed -n 's/.*data-page="\([^"]*\)".*/\1/p' \
  | sed 's/&quot;/"/g; s/&#039;/'"'"'/g; s/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g')"
[[ -n "$catalog" ]] || { echo "No data-page payload found on supply-depot page." >&2; exit 2; }

jq -r '.props.system.services[] | [.friendly_name, .installed, .status] | @tsv' <<< "$catalog" \
  | tr '\t' '|' || { echo "Unexpected supply-depot payload shape." >&2; exit 2; }
exit 0
