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

# The management compose only covers admin/mysql/redis/support containers.
# Child components (Information Library, AI Assistant, ...) are spawned by
# the admin through docker.sock, so `compose up` leaves them exited. The
# panel's Stop also stopped them (nomad_* prefix), so restart every
# installed, non-running component once the admin API is back up.
HEALTH_URL="http://localhost:8080/api/health"
for _ in $(seq 1 30); do
  curl -sf --max-time 2 "$HEALTH_URL" > /dev/null && break
  sleep 1
done

command -v jq &> /dev/null || exit 0
services="$(curl -sf --max-time 3 http://localhost:8080/api/system/services 2> /dev/null \
  | jq -r '.[] | select(.installed == 1 and .status != "running") | .service_name')" || exit 0
for svc in $services; do
  echo "Starting component: ${svc}"
  curl -sf --max-time 5 -X POST -H "Content-Type: application/json" \
    -d "{\"service_name\": \"${svc}\", \"action\": \"start\"}" \
    http://localhost:8080/api/system/services/affect > /dev/null \
    || echo "Failed to start ${svc} (it can be started from the Command Center)." >&2
done
