# shellcheck shell=bash

# omanomad shared preflight library (sourced, never executed directly)
#
# Pre-flight checks, LAN discovery, and messaging shared by the lifecycle
# scripts in bin/ (install.sh, update.sh). Source it from a lifecycle script:
#
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/preflight.sh"
#
# Keep this module dependency-free (bash builtins plus standard tools only):
# it runs before any ensure_dependencies_installed check.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "preflight.sh is a shared library: source it from a lifecycle script instead of executing it." >&2
  exit 1
fi

RESET='\033[0m'
YELLOW='\033[1;33m'
# shellcheck disable=SC2034 # consumed by sourcing lifecycle scripts (success_message)
WHITE_R='\033[39m' # Light gray; readable on terminals with white background.
RED='\033[1;31m' # Light Red.
GREEN='\033[1;32m' # Light Green.

# shellcheck disable=SC2034 # consumed by sourcing lifecycle scripts (compose paths)
NOMAD_DIR="/opt/project-nomad"
script_option_debug='true'
local_ip_address=''

header_red() {
  if [[ "${script_option_debug}" != 'true' ]]; then clear; clear; fi
  echo -e "${RED}#########################################################################${RESET}\\n"
}

check_has_sudo() {
  if sudo -n true 2>/dev/null; then
    echo -e "${GREEN}#${RESET} User has sudo permissions.\\n"
  else
    echo "User does not have sudo permissions"
    header_red
    echo -e "${RED}#${RESET} This script requires sudo permissions to run. Please run the script with sudo.\\n"
    echo -e "${RED}#${RESET} For example: sudo bash $(basename "$0")"
    exit 1
  fi
}

check_is_bash() {
  if [[ -z "$BASH_VERSION" ]]; then
    header_red
    echo -e "${RED}#${RESET} This script requires bash to run. Please run the script using bash.\\n"
    echo -e "${RED}#${RESET} For example: bash $(basename "$0")"
    exit 1
  fi
    echo -e "${GREEN}#${RESET} This script is running in bash.\\n"
}

check_is_arch() {
  if [[ ! -f /etc/arch-release ]]; then
    header_red
    echo -e "${RED}#${RESET} This script is designed to run on Arch-based systems only.\\n"
    echo -e "${RED}#${RESET} Please run this script on an Arch-based system (e.g. Omarchy) and try again."
    exit 1
  fi
    echo -e "${GREEN}#${RESET} This script is running on an Arch-based system.\\n"
}

check_docker_compose() {
  # Check if 'docker compose' (v2 plugin) is available
  if ! docker compose version &>/dev/null; then
    echo -e "${RED}#${RESET} Docker Compose v2 is not installed or not available as a Docker plugin."
    echo -e "${YELLOW}#${RESET} This script requires 'docker compose' (v2), not 'docker-compose' (v1)."
    echo -e "${YELLOW}#${RESET} Please read the Docker documentation at https://docs.docker.com/compose/install/ for instructions on how to install Docker Compose v2."
    exit 1
  fi
}

get_local_ip() {
  # Arch's hostname (inetutils) has no -I flag, so derive the LAN source IP
  # from the routing table instead (lookup only, no traffic is sent).
  if command -v ip &> /dev/null; then
    local_ip_address=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") { print $(i+1); exit } }')
  fi
  # Fallback for systems whose hostname does understand -I.
  if [[ -z "$local_ip_address" ]]; then
    local_ip_address=$(hostname -I 2>/dev/null | awk '{print $1}')
  fi
  if [[ -z "$local_ip_address" ]]; then
    echo -e "${RED}#${RESET} Unable to determine local IP address. Please check your network configuration."
    exit 1
  fi
}
