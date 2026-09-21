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
  # A stack update pulls images and recreates containers. It needs `ip`
  # (Arch package: iproute2) for LAN discovery and `curl` to fetch and
  # verify the pinned upstream compose when a pre-digest compose file
  # needs healing.
  local missing_pkgs=()
  if ! command -v ip &> /dev/null; then
    missing_pkgs+=("iproute2")
  fi
  if ! command -v curl &> /dev/null; then
    missing_pkgs+=("curl")
  fi
  if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
    echo -e "${YELLOW}#${RESET} Installing required dependencies: ${missing_pkgs[*]}...\\n"
    sudo pacman -S --needed --noconfirm "${missing_pkgs[@]}"

    for cmd in ip curl; do
      if ! command -v "$cmd" &> /dev/null; then
        echo -e "${RED}#${RESET} Failed to install $cmd. Please install it manually and try again."
        exit 1
      fi
    done
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
  # A stack update must never pull "whatever a tag holds now": every image
  # line must carry the digest pinned by the validated plugin release. A
  # compose file from before digest pinning existed (plugin < v0.3.0) is
  # healed in place below instead of forcing a reinstall: a reinstall
  # regenerates the stack secrets and resets the MySQL data directory,
  # which would wipe the admin's database. The heal rewrites only the
  # image references and the self-URL; secrets and data are preserved.
  if ! grep -E '^[[:space:]]*image:' "${NOMAD_DIR}/compose.yml" | grep -v '@' | grep -q .; then
    return
  fi
  heal_legacy_compose
}

heal_legacy_compose() {
  echo -e "${YELLOW}#${RESET} compose.yml predates digest pinning. Re-pinning images by digest in place (stack secrets and data preserved)...\\n"

  # Carry over the stack's existing secrets verbatim; the MySQL data
  # directory stays valid and untouched. If any secret is missing this is
  # not a state we can heal: refuse without modifying the file.
  local app_key db_root_password db_user_password
  app_key="$(grep -m1 -o 'APP_KEY=[^[:space:]]*' "${NOMAD_DIR}/compose.yml" | head -1 | cut -d= -f2-)"
  db_root_password="$(grep -m1 -o 'MYSQL_ROOT_PASSWORD=[^[:space:]]*' "${NOMAD_DIR}/compose.yml" | head -1 | cut -d= -f2-)"
  db_user_password="$(grep -m1 -o 'MYSQL_PASSWORD=[^[:space:]]*' "${NOMAD_DIR}/compose.yml" | head -1 | cut -d= -f2-)"
  if [[ -z "$app_key" || -z "$db_root_password" || -z "$db_user_password" ]]; then
    echo -e "${RED}#${RESET} compose.yml contains mutable image references and its secrets cannot be carried over. Reinstall Project NOMAD to re-pin images by digest."
    exit 1
  fi

  # Fetch the pinned upstream compose into a private staged file in the
  # root-owned install directory, rewrite it there, and install it
  # atomically. The EXIT trap cleans the stage on any refusal; compose.yml
  # is only ever replaced by a rename of fully validated bytes.
  local staged
  staged="$(mktemp "${NOMAD_DIR}/.compose-heal.XXXXXXXX")"
  trap 'rm -f "$staged"' EXIT
  if ! fetch_verified "$MANAGEMENT_COMPOSE_FILE_URL" "$MANAGEMENT_COMPOSE_FILE_SHA256" "$staged" 600; then
    echo -e "${RED}#${RESET} Failed to download the docker compose file or it failed verification. Please try again."
    exit 1
  fi

  pin_image_digests "$staged"

  # Same substitutions install.sh performs on a fresh install; the
  # secrets come from the old compose instead of the generator, so MySQL
  # accepts the existing data directory. The self-URL is refreshed to the
  # current LAN address, matching what a fresh install would write.
  sed -i "s|URL=replaceme|URL=http://${local_ip_address}:8080|g" "$staged"
  sed -i "s|APP_KEY=replaceme|APP_KEY=${app_key}|g" "$staged"
  sed -i "s|DB_PASSWORD=replaceme|DB_PASSWORD=${db_user_password}|g" "$staged"
  sed -i "s|MYSQL_ROOT_PASSWORD=replaceme|MYSQL_ROOT_PASSWORD=${db_root_password}|g" "$staged"
  sed -i "s|MYSQL_PASSWORD=replaceme|MYSQL_PASSWORD=${db_user_password}|g" "$staged"

  # Validate the healed file before it replaces the working one: every
  # placeholder consumed (KEY=replaceme form — upstream's own prose also
  # mentions the word, so match the assignment shape), every carried
  # secret present, URL refreshed.
  if grep -qE '[A-Z_]+=replaceme' "$staged" \
    || ! grep -Fq "URL=http://${local_ip_address}:8080" "$staged" \
    || ! grep -Fq "APP_KEY=${app_key}" "$staged" \
    || ! grep -Fq "MYSQL_ROOT_PASSWORD=${db_root_password}" "$staged" \
    || ! grep -Fq "MYSQL_PASSWORD=${db_user_password}" "$staged"; then
    echo -e "${RED}#${RESET} Healed compose file failed validation. Aborting without changes."
    exit 1
  fi

  if [[ -L "${NOMAD_DIR}/compose.yml" || ( -e "${NOMAD_DIR}/compose.yml" && ! -f "${NOMAD_DIR}/compose.yml" ) ]]; then
    echo -e "${RED}#${RESET} ${NOMAD_DIR}/compose.yml is not a regular file. Aborting."
    exit 1
  fi
  mv -fT "$staged" "${NOMAD_DIR}/compose.yml"
  trap - EXIT
  echo -e "${GREEN}#${RESET} compose.yml re-pinned by digest; stack secrets and data preserved.\\n"
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
# LAN discovery before the compose check: the legacy-compose heal writes
# the current self-URL into the healed file, matching a fresh install.
get_local_ip
ensure_docker_compose_file_exists
force_recreate
success_message
