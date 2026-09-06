#!/bin/bash
# omanomad: uninstall Project NOMAD.
# Non-interactive — the panel UI owns confirmation (runs via pkexec).
# Default keeps data (storage/, mysql/, redis/, nomad-update-shared volume);
# --purge-data removes /opt/project-nomad entirely plus the shared volume.
# Storage is NEVER deleted without the flag.
NOMAD_DIR="/opt/project-nomad"
COMPOSE_FILE="${NOMAD_DIR}/compose.yml"
SHARED_VOLUME="project-nomad_nomad-update-shared"

PURGE=false
if [[ "${1:-}" == "--purge-data" ]]; then
  PURGE=true
elif [[ $# -gt 0 ]]; then
  echo "Usage: $(basename "$0") [--purge-data]" >&2
  exit 1
fi

if [[ -f "$COMPOSE_FILE" ]]; then
  echo "Stopping and removing Project NOMAD containers..."
  if ! sudo docker compose -p project-nomad -f "$COMPOSE_FILE" down; then
    echo "Failed to remove Project NOMAD containers. Please check the logs and try again." >&2
    exit 1
  fi
else
  echo "No compose file at ${COMPOSE_FILE}; skipping container removal."
fi

# Removing the compose file returns status.sh to not-installed, so the
# panel offers Install again; a reinstall regenerates it with fresh secrets.
echo "Removing helper scripts and compose file..."
sudo rm -f "${NOMAD_DIR}/start_nomad.sh" "${NOMAD_DIR}/stop_nomad.sh" "${NOMAD_DIR}/update_nomad.sh" "$COMPOSE_FILE"

if $PURGE; then
  echo "Purging all Project NOMAD data..."
  sudo rm -rf "$NOMAD_DIR"
  # Best effort: the volume may already be gone.
  sudo docker volume rm -f "$SHARED_VOLUME" 2>/dev/null || true
else
  echo "Kept data: storage/, mysql/, redis/ and the ${SHARED_VOLUME} volume."
fi

echo "Project NOMAD uninstalled successfully."
