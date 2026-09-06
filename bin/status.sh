#!/bin/bash
# omanomad: print the Project NOMAD state for the panel to poll.
# Exactly one of: not-installed | stopped | running
# Unprivileged by design — no privilege escalation anywhere, so the panel
# can poll without auth prompts. Never fails (exit 0 always).
COMPOSE_FILE="/opt/project-nomad/compose.yml"
HEALTH_URL="http://localhost:8080/api/health"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "not-installed"
  exit 0
fi

# Without curl there is no way to observe a healthy Command Center,
# so report stopped (the safe, restartable state).
if command -v curl &> /dev/null && curl -sf --max-time 3 "$HEALTH_URL" &> /dev/null; then
  echo "running"
else
  echo "stopped"
fi
exit 0
