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

####################################################################################################################################
#                                                                                                                                  #
#           Shared installer assets: pinned upstream sources, image digests, checksum-verified fetcher, digest pinning            #
#                                                                                                                                  #
####################################################################################################################################

# Upstream assets are pinned to the upstream v1.34.1 release commit and
# verified against the checksums below before use: a mutable-branch fetch
# or a tampered/failed download aborts instead of running. The image
# digests are the manifest digests Docker verified for the currently
# deployed, tested images; bumping any of them is a plugin release (new
# marketplace validation), never a runtime fetch of "whatever the tag
# holds now". install.sh uses these for a fresh install; update.sh uses
# them to heal a pre-digest compose file in place (secrets and data
# preserved). The network-facing functions below are only CALLED after
# ensure_dependencies_installed has run.
UPSTREAM_COMMIT="f8e40fbd01f4ce0e6bc4cc3e37167b4bf4065028"
# shellcheck disable=SC2034  # consumed by the sourcing lifecycle scripts (install.sh/update.sh)
MANAGEMENT_COMPOSE_FILE_URL="https://raw.githubusercontent.com/Crosstalk-Solutions/project-nomad/${UPSTREAM_COMMIT}/install/management_compose.yaml"
# shellcheck disable=SC2034  # consumed by the sourcing lifecycle scripts (install.sh/update.sh)
START_SCRIPT_URL="https://raw.githubusercontent.com/Crosstalk-Solutions/project-nomad/${UPSTREAM_COMMIT}/install/start_nomad.sh"
# shellcheck disable=SC2034  # consumed by the sourcing lifecycle scripts (install.sh/update.sh)
STOP_SCRIPT_URL="https://raw.githubusercontent.com/Crosstalk-Solutions/project-nomad/${UPSTREAM_COMMIT}/install/stop_nomad.sh"
# shellcheck disable=SC2034  # consumed by the sourcing lifecycle scripts (install.sh/update.sh)
UPDATE_SCRIPT_URL="https://raw.githubusercontent.com/Crosstalk-Solutions/project-nomad/${UPSTREAM_COMMIT}/install/update_nomad.sh"

# shellcheck disable=SC2034  # consumed by the sourcing lifecycle scripts (install.sh/update.sh)
MANAGEMENT_COMPOSE_FILE_SHA256="ca6200454d1302ef674699f7a32febce080e620c7063cbcce89916f85a692058"
# shellcheck disable=SC2034  # consumed by the sourcing lifecycle scripts (install.sh/update.sh)
START_SCRIPT_SHA256="1d27546a0e580021699ea6a4a60f5203361e4915089e0a2dd4996b2aaffc0825"
# shellcheck disable=SC2034  # consumed by the sourcing lifecycle scripts (install.sh/update.sh)
STOP_SCRIPT_SHA256="637be60d16a255e96cc9c9765ccebccab5d772a1324d983d46fb47690dc2fcd0"
# shellcheck disable=SC2034  # consumed by the sourcing lifecycle scripts (install.sh/update.sh)
UPDATE_SCRIPT_SHA256="b6887d065f247f9e4be12f7670efae5d0e793e7ce0ad9683bf10dce9651a5a8e"

# Container images are pinned by immutable digest: an upstream tag change
# cannot swap the executed images underneath an approved install.
ADMIN_IMAGE="ghcr.io/crosstalk-solutions/project-nomad@sha256:62b547248dc8b626e21e89d1b1a069cecded759b01a7f3eb046426181caa4c76"
DOZZLE_IMAGE="amir20/dozzle@sha256:d383abf0fee72a8037d6ec6474424e56d752a52208e0ed70f4805e9d86a77830"
MYSQL_IMAGE="mysql@sha256:7dcddc01f13bab2f15cde676d44d01f61fc9f99fe7785e86196dfc07d358ae2b"
REDIS_IMAGE="redis@sha256:ff02b58f971e7d7d156a1267e283fcbbeee91773b6aa36c49dac28ecfe28eadf"
UPDATER_IMAGE="ghcr.io/crosstalk-solutions/project-nomad-sidecar-updater@sha256:5e3f09b1b056a5c1e96ff2a47a25d9137c5975010691686728174e04545da6c7"
DISK_COLLECTOR_IMAGE="ghcr.io/crosstalk-solutions/project-nomad-disk-collector@sha256:154a5549fb13b7b3858838fca7ed87d5385c1c7cf9d72d65e6dd59e76952fd8c"

fetch_verified() {
  # fetch_verified <url> <expected sha256> <destination> <mode>
  # Downloads with bounded time/size into a root-created private staging
  # directory, verifies the pinned checksum THERE, then installs into the
  # root-owned destination. A symlink or non-regular file planted at the
  # destination (e.g. from an era when the directory was user-writable) is
  # refused, never followed; the verified bytes are then placed as a fresh
  # regular file. Any mismatch deletes the staging dir and fails so the
  # caller aborts.
  local url="$1" expected="$2" dest="$3" mode="$4"
  local stage staged
  stage="$(mktemp -d /tmp/omanomad-fetch.XXXXXXXX)"
  chmod 700 "$stage"
  staged="${stage}/payload"
  if ! curl -fsSL --retry 5 --retry-delay 3 --connect-timeout 15 --max-time 120 --max-filesize 5242880 "$url" -o "$staged"; then
    rm -rf "$stage"
    return 1
  fi
  if ! echo "${expected}  ${staged}" | sha256sum --check --status; then
    rm -rf "$stage"
    return 1
  fi
  if [[ -L "$dest" || ( -e "$dest" && ! -f "$dest" ) ]]; then
    echo "fetch_verified: refusing non-regular destination: ${dest}" >&2
    rm -rf "$stage"
    return 1
  fi
  rm -f "$dest"
  install -m "${mode}" "$staged" "$dest"
  local rc=$?
  rm -rf "$stage"
  return $rc
}

# Rewrite upstream's mutable image tags to the digest pins. Runs on the
# freshly downloaded, checksum-verified compose file before it is used;
# any line that did not match a known tag aborts, so an unexpected
# upstream change can never reach `docker compose up`.
pin_image_digests() {
  local compose_file="$1"
  echo -e "${YELLOW}#${RESET} Pinning container images by digest...\\n"
  sed -i \
    -e "s|image: ghcr.io/crosstalk-solutions/project-nomad:latest|image: ${ADMIN_IMAGE}|" \
    -e "s|image: amir20/dozzle:v10.0|image: ${DOZZLE_IMAGE}|" \
    -e "s|image: mysql:8.0|image: ${MYSQL_IMAGE}|" \
    -e "s|image: redis:7-alpine|image: ${REDIS_IMAGE}|" \
    -e "s|image: ghcr.io/crosstalk-solutions/project-nomad-sidecar-updater:latest|image: ${UPDATER_IMAGE}|" \
    -e "s|image: ghcr.io/crosstalk-solutions/project-nomad-disk-collector:latest|image: ${DISK_COLLECTOR_IMAGE}|" \
    "$compose_file"
  if grep -E '^[[:space:]]*image:' "$compose_file" | grep -v '@' | grep -q .; then
    echo -e "${RED}#${RESET} Compose file contains an unexpected or mutable image reference. Aborting."
    exit 1
  fi
  echo -e "${GREEN}#${RESET} All container images pinned by digest.\\n"
}

####################################################################################################################################
#                                                                                                                                  #
#                 Compose trust boundary: reclaim the install directory and the compose file before root uses either               #
#                                                                                                                                  #
####################################################################################################################################

# Digest pins authenticate the images, but only a root-owned compose
# definition pins the services, mounts, and capabilities themselves.
# Root feeds ${NOMAD_DIR}/compose.yml to `docker compose` on start,
# update, and uninstall; installs from before the directory reclaim
# (plugin < v0.3.5) left /opt/project-nomad user-owned, so on such a
# legacy layout a compromised user session could swap the compose file —
# keeping digest-looking image references — and add privileged containers
# or host-root mounts that root would run on the next authorized
# Start/Update. The boundary below migrates that layout in place before
# every privileged compose use: the directory is reclaimed
# non-dereferencing and non-recursively, and a compose file that is not
# provably root-owned is not trusted — it is reconstructed from the
# pinned, checksum-verified upstream definition (images digest-pinned,
# stack secrets carried over verbatim so the existing MySQL data stays
# valid) and installed atomically, 600 root-owned. Every refusal aborts
# before docker ever sees the file.

# Refuse a compose file that is not a regular file (a planted symlink or
# FIFO must never be read, followed, or replaced by root).
ensure_compose_regular() {
  if [[ -L "${NOMAD_DIR}/compose.yml" || ( -e "${NOMAD_DIR}/compose.yml" && ! -f "${NOMAD_DIR}/compose.yml" ) ]]; then
    echo -e "${RED}#${RESET} ${NOMAD_DIR}/compose.yml is not a regular file. Aborting."
    exit 1
  fi
}

# Reclaim the top level of the install directory. Never recursive —
# container data underneath keeps its owners. chown -h never dereferences;
# after this the directory is root-owned 755, so a same-UID process can no
# longer create or swap anything inside it, which makes the compose-file
# checks below race-free. Refuses a symlinked or missing directory.
reclaim_nomad_directory() {
  if [[ -L "$NOMAD_DIR" ]]; then
    echo -e "${RED}#${RESET} ${NOMAD_DIR} is a symlink. Aborting."
    exit 1
  fi
  if [[ ! -d "$NOMAD_DIR" ]]; then
    echo -e "${RED}#${RESET} ${NOMAD_DIR} does not exist. Project NOMAD is not installed."
    exit 1
  fi
  if ! sudo chown -h root:root "$NOMAD_DIR"; then
    echo -e "${RED}#${RESET} Could not reclaim ownership of ${NOMAD_DIR}. Aborting."
    exit 1
  fi
  if ! sudo chmod 755 "$NOMAD_DIR"; then
    echo -e "${RED}#${RESET} Could not reclaim permissions of ${NOMAD_DIR}. Aborting."
    exit 1
  fi
}

# True iff the install directory and compose.yml are both regular,
# root-owned, and not group/other-writable — the boundary root may trust.
compose_boundary_trusted() {
  local f owner perms
  [[ -d "$NOMAD_DIR" && ! -L "$NOMAD_DIR" ]] || return 1
  read -r owner perms <<<"$(stat -c '%u %a' "$NOMAD_DIR" 2>/dev/null)" || return 1
  [[ "$owner" == 0 ]] || return 1
  (( (8#$perms & 8#022) == 0 )) || return 1
  f="${NOMAD_DIR}/compose.yml"
  [[ -f "$f" && ! -L "$f" ]] || return 1
  read -r owner perms <<<"$(stat -c '%u %a' "$f" 2>/dev/null)" || return 1
  [[ "$owner" == 0 ]] || return 1
  (( (8#$perms & 8#022) == 0 ))
}

# Rebuild compose.yml from the pinned upstream definition: fetch it
# checksum-verified, pin the images by digest, carry the stack's existing
# secrets over verbatim (the MySQL data directory stays valid and is never
# touched), refresh the self-URL, validate, and install atomically as a
# root-owned 600 regular file. Every refusal leaves compose.yml
# byte-identical. Returns nonzero on refusal; the caller decides whether
# that is fatal. Callers run as root with dependencies ensured.
heal_compose_in_place() {
  echo -e "${YELLOW}#${RESET} compose.yml is not trusted (user-writable boundary or pre-digest image references). Rebuilding it from the pinned upstream definition in place (stack secrets and data preserved)...\\n"

  # Carry over the stack's existing secrets verbatim; the MySQL data
  # directory stays valid and untouched. If any secret is missing this is
  # not a state we can heal: refuse without modifying the file.
  local app_key db_root_password db_user_password
  app_key="$(grep -m1 -o 'APP_KEY=[^[:space:]]*' "${NOMAD_DIR}/compose.yml" | head -1 | cut -d= -f2-)"
  db_root_password="$(grep -m1 -o 'MYSQL_ROOT_PASSWORD=[^[:space:]]*' "${NOMAD_DIR}/compose.yml" | head -1 | cut -d= -f2-)"
  db_user_password="$(grep -m1 -o 'MYSQL_PASSWORD=[^[:space:]]*' "${NOMAD_DIR}/compose.yml" | head -1 | cut -d= -f2-)"
  if [[ -z "$app_key" || -z "$db_root_password" || -z "$db_user_password" ]]; then
    echo -e "${RED}#${RESET} compose.yml is not trusted and its secrets cannot be carried over. Reinstall Project NOMAD to regenerate the stack definition."
    return 1
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
    return 1
  fi

  pin_image_digests "$staged"

  # Same substitutions install.sh performs on a fresh install; the
  # secrets come from the old compose instead of the generator, so MySQL
  # accepts the existing data directory. The self-URL is refreshed to the
  # current LAN address, matching what a fresh install would write.
  if [[ -z "$local_ip_address" ]]; then
    get_local_ip
  fi
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
    return 1
  fi

  ensure_compose_regular
  mv -fT "$staged" "${NOMAD_DIR}/compose.yml"
  trap - EXIT
  echo -e "${GREEN}#${RESET} compose.yml rebuilt root-owned with all images pinned by digest; stack secrets and data preserved.\\n"
}

# Full boundary check for scripts that feed compose.yml to root docker:
# reclaim the directory (making the checks below race-free), refuse
# non-regular compose files, and reconstruct the definition whenever it is
# not provably root-owned or still carries mutable image references. On
# success compose.yml is a root-owned 600 regular file with every image
# digest-pinned.
ensure_trusted_compose_file() {
  reclaim_nomad_directory
  if [[ ! -f "${NOMAD_DIR}/compose.yml" ]]; then
    echo -e "${RED}#${RESET} compose.yml file not found. Please ensure it exists at ${NOMAD_DIR}/compose.yml."
    exit 1
  fi
  ensure_compose_regular
  if ! compose_boundary_trusted \
    || grep -E '^[[:space:]]*image:' "${NOMAD_DIR}/compose.yml" | grep -v '@' | grep -q .; then
    heal_compose_in_place || exit 1
  else
    # Boundary and content are trusted; tighten a legacy 644/640 mode to
    # the canonical 600 (the file carries stack secrets). Bytes untouched.
    sudo chmod 600 "${NOMAD_DIR}/compose.yml"
  fi
}
