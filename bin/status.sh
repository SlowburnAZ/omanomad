#!/bin/bash
# omanomad: print the Project NOMAD state for the panel to poll.
# Prints exactly one of: not-installed | stopped | running (exit 0).
# Anything else is an observation failure: the reason goes to stderr and
# the exit code is 2, so the panel can tell "cannot observe" apart from
# "observed stopped". Unprivileged by design — no privilege escalation
# anywhere, so the panel can poll without auth prompts.
COMPOSE_FILE="/opt/project-nomad/compose.yml"
HEALTH_URL="http://localhost:8080/api/health"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "not-installed"
  exit 0
fi

# Without curl there is no way to observe a healthy Command Center.
if ! command -v curl &> /dev/null; then
  echo "curl is required to observe the Command Center state but was not found." >&2
  exit 2
fi

health_code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$HEALTH_URL")"
curl_status=$?
if [[ $curl_status -ne 0 ]]; then
  echo "Command Center health check unreachable at ${HEALTH_URL} (curl exit ${curl_status})." >&2
  exit 2
fi

if [[ "$health_code" =~ ^2 ]]; then
  echo "running"
else
  echo "stopped"
fi
exit 0
