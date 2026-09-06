#!/bin/bash
# omanomad: start the Project NOMAD stack.
# Non-interactive — the panel UI owns confirmation (runs via pkexec).
NOMAD_DIR="/opt/project-nomad"
COMPOSE_FILE="${NOMAD_DIR}/compose.yml"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "Project NOMAD is not installed (no ${COMPOSE_FILE}). Install it first." >&2
  exit 1
fi

if ! systemctl is-active --quiet docker; then
  echo "Docker is not running. Attempting to start Docker..."
  sudo systemctl start docker
  if ! systemctl is-active --quiet docker; then
    echo "Failed to start Docker. Please check the Docker service status and try again." >&2
    exit 1
  fi
fi

sudo docker compose -p project-nomad -f "$COMPOSE_FILE" up -d
