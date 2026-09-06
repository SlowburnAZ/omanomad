#!/bin/bash
# omanomad: stop the running Project NOMAD containers.
# Upstream stop_nomad.sh logic (messages kept), sudo-prefixed.
# Non-interactive — the panel UI owns confirmation (runs via pkexec).

echo "Finding running Docker containers for Project NOMAD.."

containers=$(sudo docker ps --filter "name=^nomad_" --format "{{.Names}}")

if [ -z "$containers" ]; then
    echo "No running containers found for Project NOMAD"
    exit 0
fi

echo "Found the following running containers:"
echo "$containers"
echo ""

for container in $containers; do
    echo "Gracefully stopping container: $container"
    if sudo docker stop "$container"; then
        echo "✓ Successfully stopped $container"
    else
        echo "✗ Failed to stop $container"
    fi
    echo ""
done

echo "Finished initiating graceful shutdown of all Project NOMAD containers."
