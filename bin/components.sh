#!/bin/bash
# omanomad: list the Command Center's child components (Information
# Library, AI Assistant, ...) with their install/running state.
# Source of truth: the admin API the Command Center UI itself uses.
# Prints one pipe-separated line per component:
#   friendly_name|installed(0|1)|status|ui_location
# Fails silently (exit 2, reason to stderr): the panel treats component
# info as best-effort garnish, never as state.
HEALTH_URL="http://localhost:8080/api/system/services"

command -v curl &> /dev/null || { echo "curl not found" >&2; exit 2; }
command -v jq &> /dev/null || { echo "jq not found" >&2; exit 2; }

response="$(curl -sf --max-time 3 "$HEALTH_URL")" || { echo "Command Center services endpoint unreachable." >&2; exit 2; }
[[ -n "$response" ]] || { echo "Command Center services endpoint returned nothing." >&2; exit 2; }

jq -r '.[] | [.friendly_name, .installed, .status, (.ui_location // "-")] | @tsv' <<< "$response" | tr '\t' '|'
exit 0
