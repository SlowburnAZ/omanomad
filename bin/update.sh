#!/bin/bash

# omanomad Stack Update Script (Arch/Omarchy port)
#
# Arch port of Project NOMAD's Update Script v1.0.1 by Crosstalk
# Solutions, LLC (https://crosstalksolutions.com), adapted for
# Arch-based systems (Omarchy). Function-by-function port: control flow,
# prompts, docker ensure + start, compose checks, image pull, container
# recreation, LAN discovery, and the success message intentionally mirror
# upstream.
#
# Run with elevated privileges; the omanomad panel launches this via
# `pkexec bash bin/update.sh` in a floating terminal (pkexec, not sudo,
# because there is no terminal for a password prompt otherwise). The
# terminal owns the y/n confirmation prompt — the panel shows no
# ConfirmDialog for stack updates.
#
# This performs a stack update (latest images + force-recreate), not a
# plugin update: no data loss is expected.


# Script                | omanomad Stack Update Script (Arch port of Project NOMAD Update Script 1.0.1)
# Author                | Crosstalk Solutions, LLC (upstream); Omarchy port: omanomad contributors
# Website               | https://crosstalksolutions.com

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Color Codes                                                                                           #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################
RESET='\033[0m'
YELLOW='\033[1;33m'
WHITE_R='\033[39m' # Light gray; readable on terminals with white background.
RED='\033[1;31m' # Light Red.
GREEN='\033[1;32m' # Light Green.

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                  Constants & Variables                                                                                          #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

NOMAD_DIR="/opt/project-nomad"
script_option_debug='true'
local_ip_address=''

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Functions                                                                                             #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

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

ensure_dependencies_installed() {
  # A stack update pulls images and recreates containers; the only local
  # dependency it needs is `ip` (Arch package: iproute2) for LAN discovery.
  if ! command -v ip &> /dev/null; then
    echo -e "${YELLOW}#${RESET} Installing required dependencies: iproute2...\\n"
    sudo pacman -S --needed --noconfirm iproute2

    # Verify installation
    if ! command -v ip &> /dev/null; then
      echo -e "${RED}#${RESET} Failed to install ip. Please install it manually and try again."
      exit 1
    fi
    echo -e "${GREEN}#${RESET} Dependencies installed successfully.\\n"
  else
    echo -e "${GREEN}#${RESET} All required dependencies are already installed.\\n"
  fi
}

get_update_confirmation(){
  read -p "This script will update Project NOMAD and its dependencies on your machine. No data loss is expected, but you should always back up your data before proceeding. Are you sure you want to continue? (y/n): " choice
  case "$choice" in
    y|Y )
      echo -e "${GREEN}#${RESET} User chose to continue with the update."
      ;;
    n|N )
      echo -e "${RED}#${RESET} User chose not to continue with the update."
      exit 0
      ;;
    * )
      echo "Invalid Response"
      echo "User chose not to continue with the update."
      exit 0
      ;;
  esac
}

ensure_docker_installed_and_running() {
  if ! command -v docker &> /dev/null; then
    echo -e "${RED}#${RESET} Docker is not installed. This is unexpected, as Project NOMAD requires Docker to run. Did you mean to use the install script instead of the update script?"
    exit 1
  fi

  if ! systemctl is-active --quiet docker; then
    echo -e "${RED}#${RESET} Docker is not running. Attempting to start Docker..."
    sudo systemctl start docker
    if ! systemctl is-active --quiet docker; then
      echo -e "${RED}#${RESET} Failed to start Docker. Please start Docker and try again."
      exit 1
    fi
  fi
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

ensure_docker_compose_file_exists() {
  if [[ ! -f "${NOMAD_DIR}/compose.yml" ]]; then
    echo -e "${RED}#${RESET} compose.yml file not found. Please ensure it exists at ${NOMAD_DIR}/compose.yml."
    exit 1
  fi
}

force_recreate() {
  echo -e "${YELLOW}#${RESET} Pulling the latest Docker images..."
  if ! sudo docker compose -p project-nomad -f "${NOMAD_DIR}/compose.yml" pull; then
    echo -e "${RED}#${RESET} Failed to pull the latest Docker images. Please check your network connection and the Docker registry status, then try again."
    exit 1
  fi

  echo -e "${YELLOW}#${RESET} Forcing recreation of containers..."
  if ! sudo docker compose -p project-nomad -f "${NOMAD_DIR}/compose.yml" up -d --force-recreate; then
    echo -e "${RED}#${RESET} Failed to recreate containers. Please check the Docker logs for more details."
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

success_message() {
  echo -e "${GREEN}#${RESET} Project NOMAD update completed successfully!\\n"
  echo -e "${GREEN}#${RESET} Installation files are located at /opt/project-nomad\\n\n"
  echo -e "${GREEN}#${RESET} Project NOMAD's Command Center should automatically start whenever your device reboots. However, if you need to start it manually, you can always do so by running: ${WHITE_R}${NOMAD_DIR}/start_nomad.sh${RESET}\\n"
  echo -e "${GREEN}#${RESET} You can now access the management interface at http://localhost:8080 or http://${local_ip_address}:8080\\n"
  echo -e "${GREEN}#${RESET} Thank you for supporting Project NOMAD!\\n"
}

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Main Script                                                                                           #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

# Pre-flight checks
check_is_arch
check_is_bash
check_has_sudo
ensure_dependencies_installed

# Main update
get_update_confirmation
ensure_docker_installed_and_running
check_docker_compose
ensure_docker_compose_file_exists
force_recreate
get_local_ip
success_message
