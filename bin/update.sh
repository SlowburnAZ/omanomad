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

# Shared pre-flight checks and messaging (sourced library, never executed directly).
# shellcheck source=bin/lib/preflight.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/preflight.sh"

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Functions                                                                                             #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

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
