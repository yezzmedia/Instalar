#!/usr/bin/env bash
#
# INSTALAR - Laravel + Filament Installer
# ========================================
#
# A single-file installer script that:
#   1. Checks/installs system dependencies (php, composer, laravel, node, npm)
#   2. Creates new Laravel 12 projects or updates existing ones
#   3. Installs Filament, Fortify, Boost, and optional packages
#   4. Runs build/optimize steps and health checks
#
# Usage:
#   ./instalar.sh                          # Interactive mode
#   ./instalar.sh --help                  # Show help
#   ./instalar.sh --non-interactive       # Non-interactive with defaults
#   ./instalar.sh --config instalar.json  # With JSON config
#   ./instalar.sh --mode auto|manual|update
#
# Examples:
#   # Standard interactive run
#   ./instalar.sh
#
#   # Non-interactive with config file
#   ./instalar.sh --non-interactive --config ./instalar.json
#
#   # Auto mode with admin password generation
#   ./instalar.sh --non-interactive --mode auto --admin-generate
#
#   # Update existing Laravel project
#   ./instalar.sh --mode update
#
# Environment:
#   BASH_NON_INTERACTIVE=1   - Skip all prompts
#   BASH_APPLY_DEP_UPDATES=1 - Apply dependency updates automatically

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_VERSION="0.1.4"

# =============================================================================
# Terminal Color Codes
# =============================================================================
# These ANSI escape codes are used to colorize output in the terminal.
# If stdout is not a TTY (e.g., piped output), empty strings are used instead.

if [[ -t 1 ]]; then
  NC=$'\033[0m'       # Reset/Normal
  BOLD=$'\033[1m'     # Bold
  DIM=$'\033[2m'      # Dim
  RED=$'\033[31m'     # Red (errors)
  GREEN=$'\033[32m'   # Green (success)
  YELLOW=$'\033[33m'  # Yellow (warnings)
  BLUE=$'\033[34m'    # Blue
  MAGENTA=$'\033[35m' # Magenta
  CYAN=$'\033[36m'    # Cyan (info)
  WHITE=$'\033[37m'   # White
else
  NC=""
  BOLD=""
  DIM=""
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  MAGENTA=""
  CYAN=""
  WHITE=""
fi

# =============================================================================
# Global Variables
# =============================================================================

PKG_MANAGER=""                    # Detected package manager (apt, dnf, yum, pacman, apk, brew)
PKG_INDEX_REFRESHED=0             # Flag to prevent multiple package index refreshes

# Dependency tracking arrays and associative maps
declare -a DEPS=(php composer laravel node npm)                 # Required dependencies
declare -A DEP_AVAILABLE=()                                    # Maps dep name -> 1 if available
declare -A DEP_VERSION=()                                      # Maps dep name -> version string
declare -a DEPS_WITH_UPDATES=()                                # List of deps with available updates
declare -A DEP_UPDATE_CURRENT=()                               # Maps dep name -> current version
declare -A DEP_UPDATE_TARGET=()                                # Maps dep name -> target version

# Flags for script behavior
BASH_NON_INTERACTIVE=0      # Set to 1 to skip all prompts (--non-interactive)
BASH_APPLY_DEP_UPDATES=0   # Set to 1 to auto-apply dependency updates (--deps-update)
BASH_VERBOSE=0              # Set to 1 to enable verbose output (--verbose)
BASH_DEBUG=0                # Set to 1 to enable debug mode (--debug)
BASH_HAS_TTY=0             # Set to 1 if /dev/tty is available for interactive input
BASH_TTY_FD=""             # File descriptor number for /dev/tty (used for interactive prompts)

# =============================================================================
# Terminal UI Functions
# =============================================================================

# Applies ANSI color codes to text
# Args:
#   $1 - ANSI color code (e.g., "${RED}")
#   $2 - Text to colorize
paint() {
  printf '%b%s%b' "$1" "$2" "${NC}"
}

# Prints an informational message to stderr
# Args:
#   $1 - Message text
info() {
  printf '  %b %s\n' "$(paint "${CYAN}" "[INFO]")" "$1"
}

# Prints a success message to stderr
# Args:
#   $1 - Message text
ok() {
  printf '  %b %s\n' "$(paint "${GREEN}" "[ OK ]")" "$1"
}

# Prints a warning message to stderr
# Args:
#   $1 - Message text
warn() {
  printf '  %b %s\n' "$(paint "${YELLOW}" "[WARN]")" "$1"
}

# Prints an error message to stderr
# Args:
#   $1 - Message text
fail() {
  printf '  %b %s\n' "$(paint "${RED}" "[ERR ]")" "$1"
}

# Prints a section header with horizontal lines
# Args:
#   $1 - Section title
section() {
  local line
  line="$(printf '%*s' 72 '' | tr ' ' '-')"
  printf '\n%b\n' "$(paint "${DIM}" "${line}")"
  printf '%b\n' "$(paint "${BOLD}${WHITE}" "$1")"
  printf '%b\n' "$(paint "${DIM}" "${line}")"
}

# Prints the INSTALAR ASCII art banner
banner() {
  clear 2>/dev/null || true
  printf '%b\n' "$(paint "${MAGENTA}" "#######################################################")"
  printf '%b\n' "$(paint "${MAGENTA}" "####     # ### #     #     ##   ## ######   ##    #####")"
  printf '%b\n' "$(paint "${BLUE}" "###### ###  ## # ####### ### ### # ##### ### # ### ####")"
  printf '%b\n' "$(paint "${BLUE}" "###### ### # # # ####### ### ### # ##### ### # ### ####")"
  printf '%b\n' "$(paint "${CYAN}" "###### ### ##  ##   #### ###     # #####     #    #####")"
  printf '%b\n' "$(paint "${CYAN}" "###### ### ### ##### ### ### ### # ##### ### # # ######")"
  printf '%b\n' "$(paint "${GREEN}" "###### ### ### ##### ### ### ### # ##### ### # ## #####")"
  printf '%b\n' "$(paint "${GREEN}" "####     # ### #     ### ### ### #     # ### # ### ####")"
  printf '%b\n' "$(paint "${MAGENTA}" "#######################################################")"
  printf '%b\n' "$(paint "${BOLD}${YELLOW}" "=================[  INSTALAR  ]=================")"
  printf '%b\n' "$(paint "${DIM}" "       Dependency Check + Installation")"
}

# =============================================================================
# Help & Usage
# =============================================================================

# Prints the command-line help text
print_usage() {
  cat <<EOF
INSTALAR v${SCRIPT_VERSION}

Usage:
  ./instalar.sh
  ./instalar.sh --help
  ./instalar.sh --non-interactive --config instalar.json

Options:
  --config <file>         Path to JSON configuration (Node phase)
  --non-interactive       No prompts, use defaults/config
  --backup                Backup existing target directory before replacing
  --admin-generate        Generate admin password instead of "password"
  --mode <auto|manual|update>
  --allow-delete-existing Replace existing target directories in non-interactive mode
  --start-server          Automatically run composer run dev at the end
  --deps-update           Apply dependency updates in Bash phase
  --verbose               Enable verbose output
  --debug                 Enable debug mode (shows all commands)

Flow:
  1) Bash checks/installs/updates dependencies
  2) Then installation continues automatically
EOF
}

# =============================================================================
# TTY Detection & Interactive Mode Handling
# =============================================================================

# Detects whether /dev/tty is available for interactive input
# This is used to determine if prompts can be shown to the user
# Sets global variables:
#   BASH_HAS_TTY - 1 if TTY is available, 0 otherwise
#   BASH_TTY_FD - File descriptor number for /dev/tty if available
detect_bash_tty() {
  if { exec {BASH_TTY_FD}<>/dev/tty; } 2>/dev/null; then
    BASH_HAS_TTY=1
  else
    BASH_HAS_TTY=0
    BASH_TTY_FD=""
  fi
}

# Requires a TTY for interactive mode, aborts if not available
# This prevents prompts from being silently skipped when running via curl|bash
# Returns 0 if interactive mode is allowed, exits with error otherwise
require_bash_tty_for_interactive() {
  if (( BASH_NON_INTERACTIVE == 1 )); then
    return 0
  fi

  if (( BASH_HAS_TTY == 1 )); then
    return 0
  fi

  fail "No interactive terminal detected."
  fail "Use --non-interactive for unattended runs."
  fail "Example: curl -fsSL <url>/instalar.sh | bash -s -- --non-interactive"
  exit 1
}

# =============================================================================
# Interactive Prompt Functions
# =============================================================================

# Prompts the user with a yes/no question
# Args:
#   $1 - Prompt text (question to ask)
#   $2 - Default choice (1 for yes, 0 for no)
# Returns:
#   0 - User answered yes
#   1 - User answered no
#   2 - Input failed (non-interactive without TTY)
ask_yes_no() {
  local prompt="$1"
  local default_yes="$2"
  local hint="y/N"
  local default="n"
  local prompt_fd="2"
  local read_fd=""

  if [[ "${default_yes}" == "1" ]]; then
    hint="Y/n"
    default="y"
  fi

  if (( BASH_HAS_TTY == 1 )); then
    prompt_fd="${BASH_TTY_FD}"
    read_fd="${BASH_TTY_FD}"
  fi

  while true; do
    local answer=""
    printf '%b %s %b[%s]%b: ' "$(paint "${CYAN}" "?")" "${prompt}" "${DIM}" "${hint}" "${NC}" >&${prompt_fd}

    if [[ -n "${read_fd}" ]]; then
      if ! IFS= read -r -u "${read_fd}" answer; then
        fail "Interactive input failed. Use --non-interactive for unattended runs."
        return 2
      fi
    else
      if ! IFS= read -r answer; then
        fail "Interactive input failed. Use --non-interactive for unattended runs."
        return 2
      fi
    fi

    answer="${answer,,}"
    if [[ -z "${answer}" ]]; then
      answer="${default}"
    fi

    case "${answer}" in
      j|ja|y|yes)
        return 0
        ;;
      n|nein|no)
        return 1
        ;;
      *)
        warn "Please answer with y or n."
        ;;
    esac
  done
}

# =============================================================================
# System & Package Management
# =============================================================================

# Executes a command with sudo, handling different privilege scenarios
# Args:
#   $@ - Command and arguments to execute
# Returns: Command exit code, or 1 if sudo is not available
run_sudo() {
  if (( EUID == 0 )); then
    "$@"
    return
  fi
  if command -v sudo >/dev/null 2>&1; then
    sudo "$@"
    return
  fi
  fail "sudo not found. Run as root or install sudo."
  return 1
}

# Ensures composer global bin directory is in PATH
# Checks common locations: ~/.config/composer/vendor/bin and ~/.composer/vendor/bin
ensure_composer_global_bin() {
  local candidates=(
    "${HOME}/.config/composer/vendor/bin"
    "${HOME}/.composer/vendor/bin"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -d "${c}" ]] && [[ ":${PATH}:" != *":${c}:"* ]]; then
      export PATH="${c}:${PATH}"
    fi
  done
}

# Detects the available system package manager
# Sets global variable PKG_MANAGER to one of: apt, dnf, yum, pacman, apk, brew
detect_package_manager() {
  if command -v apt-get >/dev/null 2>&1; then PKG_MANAGER="apt"; return; fi
  if command -v dnf >/dev/null 2>&1; then PKG_MANAGER="dnf"; return; fi
  if command -v yum >/dev/null 2>&1; then PKG_MANAGER="yum"; return; fi
  if command -v pacman >/dev/null 2>&1; then PKG_MANAGER="pacman"; return; fi
  if command -v zypper >/dev/null 2>&1; then PKG_MANAGER="zypper"; return; fi
  if command -v apk >/dev/null 2>&1; then PKG_MANAGER="apk"; return; fi
  if command -v brew >/dev/null 2>&1; then PKG_MANAGER="brew"; return; fi
  PKG_MANAGER=""
}

# Refreshes the package manager's package index
# Only refreshes once per execution (uses PKG_INDEX_REFRESHED flag)
refresh_package_index() {
  if (( PKG_INDEX_REFRESHED == 1 )); then
    return 0
  fi

  case "${PKG_MANAGER}" in
    apt)
      run_sudo apt-get update || return 1
      ;;
    dnf)
      run_sudo dnf makecache || return 1
      ;;
    yum)
      run_sudo yum makecache || return 1
      ;;
    pacman)
      run_sudo pacman -Sy --noconfirm || return 1
      ;;
    zypper)
      run_sudo zypper --non-interactive refresh || return 1
      ;;
    apk)
      run_sudo apk update || return 1
      ;;
    brew)
      brew update || return 1
      ;;
    *)
      return 1
      ;;
  esac

  PKG_INDEX_REFRESHED=1
  return 0
}

# =============================================================================
# Dependency Detection & Version Management
# =============================================================================

# Checks if a required dependency is available in PATH
# Args:
#   $1 - Dependency name (php, composer, node, npm, laravel)
# Returns: 0 if exists, 1 otherwise
dep_exists() {
  local dep="$1"
  case "${dep}" in
    php|composer|node|npm|laravel)
      command -v "${dep}" >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

# Gets the version string of a dependency
# Args:
#   $1 - Dependency name
# Returns: Version string on stdout
dep_version() {
  local dep="$1"
  local raw=""

  case "${dep}" in
    php)
      raw="$(php -v 2>&1 || true)"
      ;;
    composer)
      raw="$(composer --version 2>&1 || true)"
      ;;
    laravel)
      raw="$(laravel --version 2>&1 || true)"
      ;;
    node)
      raw="$(node -v 2>&1 || true)"
      ;;
    npm)
      raw="$(npm -v 2>&1 || true)"
      ;;
  esac

  raw="${raw%%$'\n'*}"
  if [[ -z "${raw}" ]]; then
    raw="Version unbekannt"
  fi
  printf '%s' "${raw}"
}

# Refreshes the state of all dependencies
# Updates global arrays: DEP_AVAILABLE and DEP_VERSION
refresh_dep_state() {
  ensure_composer_global_bin

  local dep
  for dep in "${DEPS[@]}"; do
    if dep_exists "${dep}"; then
      DEP_AVAILABLE["${dep}"]=1
      DEP_VERSION["${dep}"]="$(dep_version "${dep}")"
    else
      DEP_AVAILABLE["${dep}"]=0
      DEP_VERSION["${dep}"]="not installed"
    fi
  done
}

# Prints a formatted table of dependencies with their versions
print_dep_table() {
  local width=0
  local dep
  for dep in "${DEPS[@]}"; do
    if (( ${#dep} > width )); then
      width=${#dep}
    fi
  done

  printf '\n  %b\n' "$(paint "${BOLD}${WHITE}" "Dependencies")"
  for dep in "${DEPS[@]}"; do
    local label
    local version
    label="$(printf "%-${width}s" "${dep}")"
    if (( DEP_AVAILABLE["${dep}"] == 1 )); then
      version="$(paint "${WHITE}" "${DEP_VERSION[$dep]}")"
    else
      version="$(paint "${RED}" "${DEP_VERSION[$dep]}")"
    fi
    printf '  %b %b|%b %b\n' "$(paint "${CYAN}" "${label}")" "${DIM}" "${NC}" "${version}"
  done
}

# Normalizes a version string by removing prefix 'v' and taking first token
# Args:
#   $1 - Version string (e.g., "v8.5.0" or "8.5.0 (cli)")
# Returns: Normalized version on stdout (e.g., "8.5.0")
normalize_version() {
  local value="$1"
  value="${value#v}"
  value="${value%% *}"
  printf '%s' "${value}"
}

# =============================================================================
# Update Detection Functions
# =============================================================================

# Registers an available update for a dependency
# Args:
#   $1 - Dependency name
#   $2 - Current version
#   $3 - Target (new) version
# Side effects: Updates global arrays DEPS_WITH_UPDATES, DEP_UPDATE_CURRENT, DEP_UPDATE_TARGET
register_dep_update() {
  local dep="$1"
  local current="$2"
  local target="$3"

  if [[ -z "${target}" ]]; then
    return
  fi

  if [[ -z "${current}" ]]; then
    current="${DEP_VERSION[$dep]}"
  fi

  local current_norm
  local target_norm
  current_norm="$(normalize_version "${current}")"
  target_norm="$(normalize_version "${target}")"

  if [[ -n "${current_norm}" && "${current_norm}" == "${target_norm}" ]]; then
    return
  fi

  if [[ -z "${DEP_UPDATE_TARGET[$dep]+x}" ]]; then
    DEPS_WITH_UPDATES+=("${dep}")
  fi

  DEP_UPDATE_CURRENT["${dep}"]="${current}"
  DEP_UPDATE_TARGET["${dep}"]="${target}"
}

# Resets all tracked dependency updates
# Clears global arrays DEPS_WITH_UPDATES, DEP_UPDATE_CURRENT, DEP_UPDATE_TARGET
reset_dep_updates() {
  DEPS_WITH_UPDATES=()
  unset DEP_UPDATE_CURRENT
  unset DEP_UPDATE_TARGET
  declare -gA DEP_UPDATE_CURRENT=()
  declare -gA DEP_UPDATE_TARGET=()
}

# Detects available updates for a package using the system package manager
# Args:
#   $1 - Dependency name (e.g., "php", "node")
#   $2 - Package name (e.g., "php", "nodejs")
# Calls: register_dep_update if an update is available
detect_pm_update() {
  local dep="$1"
  local pkg="$2"
  local current=""
  local target=""
  local output=""
  local line=""

  case "${PKG_MANAGER}" in
    apt)
      output="$(apt-cache policy "${pkg}" 2>/dev/null || true)"
      current="$(printf '%s\n' "${output}" | awk '/Installed:/ {print $2; exit}')"
      target="$(printf '%s\n' "${output}" | awk '/Candidate:/ {print $2; exit}')"
      if [[ "${target}" == "(none)" || -z "${target}" || "${current}" == "${target}" ]]; then
        return
      fi
      ;;
    dnf)
      current="$(rpm -q --qf '%{VERSION}-%{RELEASE}\n' "${pkg}" 2>/dev/null || true)"
      output="$(dnf --quiet check-update "${pkg}" 2>/dev/null || true)"
      line="$(printf '%s\n' "${output}" | awk -v p="${pkg}" '$1 ~ "^" p "(\\.|$)" {print; exit}')"
      target="$(printf '%s\n' "${line}" | awk '{print $2}')"
      if [[ -z "${target}" ]]; then
        return
      fi
      ;;
    yum)
      current="$(rpm -q --qf '%{VERSION}-%{RELEASE}\n' "${pkg}" 2>/dev/null || true)"
      output="$(yum check-update "${pkg}" 2>/dev/null || true)"
      line="$(printf '%s\n' "${output}" | awk -v p="${pkg}" '$1 ~ "^" p "(\\.|$)" {print; exit}')"
      target="$(printf '%s\n' "${line}" | awk '{print $2}')"
      if [[ -z "${target}" ]]; then
        return
      fi
      ;;
    pacman)
      while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        current="$(printf '%s\n' "${line}" | awk '{print $2}')"
        target="$(printf '%s\n' "${line}" | awk '{print $4}')"
        break
      done < <(pacman -Qu "${pkg}" 2>/dev/null || true)
      if [[ -z "${target}" ]]; then
        return
      fi
      ;;
    zypper)
      output="$(zypper --non-interactive list-updates "${pkg}" 2>/dev/null || true)"
      line="$(printf '%s\n' "${output}" | awk -F'|' -v p="${pkg}" '
        {
          for (i = 1; i <= NF; i++) {
            gsub(/^[ \t]+|[ \t]+$/, "", $i)
          }
          if ($3 == p) {
            print $4 "|" $5
            exit
          }
        }
      ')"
      current="${line%%|*}"
      target="${line#*|}"
      if [[ -z "${line}" || -z "${target}" || "${current}" == "${target}" ]]; then
        return
      fi
      ;;
    apk)
      line="$(apk list -u "${pkg}" 2>/dev/null | awk 'NR==1 {print; exit}')"
      if [[ -z "${line}" ]]; then
        return
      fi
      target="$(printf '%s\n' "${line}" | sed -E "s/^${pkg}-([^[:space:]]+).*/\\1/")"
      current="$(printf '%s\n' "${line}" | sed -E "s/.*upgradable from: ${pkg}-([^]]+).*/\\1/")"
      if [[ -z "${target}" || "${target}" == "${line}" ]]; then
        return
      fi
      ;;
    brew)
      line="$(brew outdated --verbose "${pkg}" 2>/dev/null | awk 'NR==1 {print; exit}')"
      if [[ -z "${line}" ]]; then
        return
      fi
      current="$(printf '%s\n' "${line}" | sed -E 's/.*\(([^)]*)\).*/\1/')"
      target="$(printf '%s\n' "${line}" | sed -E 's/.*< ([^[:space:]]+).*/\1/')"
      if [[ -z "${target}" || "${current}" == "${target}" ]]; then
        return
      fi
      ;;
    *)
      return
      ;;
  esac

  register_dep_update "${dep}" "${current}" "${target}"
}

# Detects available updates for Composer itself
# Queries packagist API for the latest stable version
# Calls: register_dep_update if an update is available
detect_composer_update() {
  local current
  local latest

  current="$(composer --version 2>/dev/null | sed -E 's/.* ([0-9]+\.[0-9]+\.[0-9]+).*/\1/' || true)"
  latest="$(composer show composer/composer --all --format=json 2>/dev/null | php -r '
    $data = json_decode(stream_get_contents(STDIN), true);
    if (! is_array($data)) {
      exit(0);
    }
    foreach (($data["versions"] ?? []) as $version) {
      if (preg_match("/^[0-9]+\\.[0-9]+\\.[0-9]+$/", $version)) {
        echo $version;
        exit(0);
      }
    }
  ' || true)"

  if [[ -n "${current}" && -n "${latest}" && "$(normalize_version "${current}")" != "$(normalize_version "${latest}")" ]]; then
    register_dep_update "composer" "${current}" "${latest}"
  fi
}

# Detects available updates for the Laravel installer
# Uses composer global outdated to check for updates
# Calls: register_dep_update if an update is available
detect_laravel_installer_update() {
  local pair
  pair="$(composer global outdated laravel/installer --direct --format=json 2>/dev/null | php -r '
    $data = json_decode(stream_get_contents(STDIN), true);
    if (! is_array($data)) {
      exit(0);
    }

    $current = "";
    if (isset($data["versions"][0])) {
      $current = ltrim((string) $data["versions"][0], "v");
    }

    $latest = ltrim((string) ($data["latest"] ?? ""), "v");

    if ($current !== "" && $latest !== "" && $current !== $latest) {
      echo $current . "|" . $latest;
    }
  ' || true)"

  if [[ -n "${pair}" ]]; then
    register_dep_update "laravel" "${pair%%|*}" "${pair#*|}"
  fi
}

# Detects available updates for npm itself
# Queries npm registry for the latest version
# Calls: register_dep_update if an update is available
detect_npm_update() {
  local current
  local latest

  current="$(npm -v 2>/dev/null || true)"
  latest="$(npm view npm version 2>/dev/null || true)"

  if [[ -n "${current}" && -n "${latest}" && "$(normalize_version "${current}")" != "$(normalize_version "${latest}")" ]]; then
    register_dep_update "npm" "${current}" "${latest}"
  fi
}

# Detects available updates for all required dependencies
# Refreshes package index if needed, then checks each dependency
# Calls: detect_pm_update, detect_composer_update, detect_laravel_installer_update, detect_npm_update
detect_available_updates() {
  reset_dep_updates

  if (( EUID == 0 )); then
    refresh_package_index >/dev/null 2>&1 || true
  elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    refresh_package_index >/dev/null 2>&1 || true
  fi

  detect_pm_update "php" "php"

  if [[ "${PKG_MANAGER}" == "brew" ]]; then
    detect_pm_update "node" "node"
  else
    detect_pm_update "node" "nodejs"
  fi

  detect_composer_update
  detect_laravel_installer_update
  detect_npm_update
}

# Prints a formatted table of available dependency updates
print_available_updates() {
  local dep_width=0
  local current_width=7
  local dep

  for dep in "${DEPS_WITH_UPDATES[@]}"; do
    if (( ${#dep} > dep_width )); then
      dep_width=${#dep}
    fi
    if (( ${#DEP_UPDATE_CURRENT[$dep]} > current_width )); then
      current_width=${#DEP_UPDATE_CURRENT[$dep]}
    fi
  done

  printf '\n  %b\n' "$(paint "${BOLD}${WHITE}" "Verfuegbare Updates")"
  printf '  %b %b|%b %b %b|%b %b\n' \
    "$(paint "${CYAN}" "$(printf "%-${dep_width}s" "Dependency")")" \
    "${DIM}" "${NC}" \
    "$(paint "${WHITE}" "$(printf "%-${current_width}s" "Aktuell")")" \
    "${DIM}" "${NC}" \
    "$(paint "${GREEN}" "Ziel")"

  for dep in "${DEPS_WITH_UPDATES[@]}"; do
    printf '  %b %b|%b %b %b|%b %b\n' \
      "$(paint "${CYAN}" "$(printf "%-${dep_width}s" "${dep}")")" \
      "${DIM}" "${NC}" \
      "$(paint "${WHITE}" "$(printf "%-${current_width}s" "${DEP_UPDATE_CURRENT[$dep]}")")" \
      "${DIM}" "${NC}" \
      "$(paint "${GREEN}" "${DEP_UPDATE_TARGET[$dep]}")"
  done
}

# =============================================================================
# Installation & Update Functions
# =============================================================================

# Applies all detected dependency updates
# Iterates through DEPS_WITH_UPDATES and calls update_dep for each
# Skips duplicate updates (e.g., node and npm both handled by node_npm)
apply_available_updates() {
  local -A applied_actions=()
  local dep

  for dep in "${DEPS_WITH_UPDATES[@]}"; do
    local action
    action="${dep}"
    if [[ "${dep}" == "node" || "${dep}" == "npm" ]]; then
      action="node_npm"
    fi

    if [[ -n "${applied_actions[$action]+x}" ]]; then
      continue
    fi
    applied_actions[$action]=1

    if update_dep "${dep}"; then
      ok "Aktualisiert: ${dep} (${DEP_UPDATE_CURRENT[$dep]} -> ${DEP_UPDATE_TARGET[$dep]})"
    else
      warn "Update failed: ${dep}"
    fi
  done
}

# Installs PHP and required PHP extensions
# Uses the detected package manager to install php, php-cli, and extensions
install_php() {
  refresh_package_index
  case "${PKG_MANAGER}" in
    apt) run_sudo apt-get install -y php php-cli php-mbstring php-xml php-curl php-zip unzip git sqlite3 ;;
    dnf) run_sudo dnf install -y php php-cli php-mbstring php-xml php-curl php-zip unzip git sqlite ;;
    yum) run_sudo yum install -y php php-cli php-mbstring php-xml php-curl php-zip unzip git sqlite ;;
    pacman) run_sudo pacman -S --noconfirm php unzip git sqlite ;;
    zypper) run_sudo zypper --non-interactive install php php-cli ;;
    apk) run_sudo apk add php php-cli php-phar php-mbstring php-xml php-openssl php-session php-ctype php-tokenizer php-fileinfo php-zip php-pdo php-pdo_sqlite php-sqlite3 unzip git ;;
    brew) brew install php ;;
    *) return 1 ;;
  esac
}

# Fallback method to install Composer when no package manager is available
# Downloads and runs the official Composer installer
install_composer_fallback() {
  mkdir -p "${HOME}/.local/bin"
  local tmp
  tmp="$(mktemp -d)"
  (
    cd "${tmp}"
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    php composer-setup.php "--install-dir=${HOME}/.local/bin" --filename=composer
  )
  rm -rf "${tmp}"
  export PATH="${HOME}/.local/bin:${PATH}"
}

# Installs Composer using the system package manager
# Falls back to install_composer_fallback if package not available
install_composer() {
  refresh_package_index
  case "${PKG_MANAGER}" in
    apt) run_sudo apt-get install -y composer ;;
    dnf) run_sudo dnf install -y composer ;;
    yum) run_sudo yum install -y composer ;;
    pacman) run_sudo pacman -S --noconfirm composer ;;
    zypper) run_sudo zypper --non-interactive install composer ;;
    apk) run_sudo apk add composer ;;
    brew) brew install composer ;;
    *) install_composer_fallback ;;
  esac
}

# Installs Node.js and npm using the system package manager
install_node_npm() {
  refresh_package_index
  case "${PKG_MANAGER}" in
    apt) run_sudo apt-get install -y nodejs npm ;;
    dnf) run_sudo dnf install -y nodejs npm ;;
    yum) run_sudo yum install -y nodejs npm ;;
    pacman) run_sudo pacman -S --noconfirm nodejs npm ;;
    zypper) run_sudo zypper --non-interactive install nodejs npm ;;
    apk) run_sudo apk add nodejs npm ;;
    brew) brew install node ;;
    *) return 1 ;;
  esac
}

# Installs the Laravel installer via Composer global require
install_laravel_installer() {
  ensure_composer_global_bin
  composer global require laravel/installer --no-interaction
  ensure_composer_global_bin
}

# Installs a dependency by name
# Dispatches to the appropriate install function based on dependency name
# Args:
#   $1 - Dependency name (php, composer, laravel, node, npm)
install_dep() {
  local dep="$1"
  case "${dep}" in
    php) install_php ;;
    composer) install_composer ;;
    laravel) install_laravel_installer ;;
    node|npm) install_node_npm ;;
    *) return 1 ;;
  esac
}

# Updates PHP to the latest version available in the package manager
update_php() {
  if ! refresh_package_index; then
    warn "Could not refresh package index for php update."
  fi
  case "${PKG_MANAGER}" in
    apt) run_sudo apt-get install --only-upgrade -y php php-cli || true ;;
    dnf) run_sudo dnf upgrade -y php php-cli || true ;;
    yum) run_sudo yum update -y php php-cli || true ;;
    pacman) run_sudo pacman -S --noconfirm php || true ;;
    zypper) run_sudo zypper --non-interactive update php || true ;;
    apk) run_sudo apk upgrade php || true ;;
    brew) brew upgrade php || true ;;
    *) return 1 ;;
  esac
}

# Updates Composer to the latest version
# Tries self-update first, then package manager update
update_composer() {
  if command -v composer >/dev/null 2>&1; then
    composer self-update || true
  fi

  if ! refresh_package_index; then
    warn "Could not refresh package index for composer update."
  fi
  case "${PKG_MANAGER}" in
    apt) run_sudo apt-get install --only-upgrade -y composer || true ;;
    dnf) run_sudo dnf upgrade -y composer || true ;;
    yum) run_sudo yum update -y composer || true ;;
    pacman) run_sudo pacman -S --noconfirm composer || true ;;
    zypper) run_sudo zypper --non-interactive update composer || true ;;
    apk) run_sudo apk upgrade composer || true ;;
    brew) brew upgrade composer || true ;;
    *) ;;
  esac
}

# Updates Node.js and npm to the latest versions
# Also runs npm install -g npm@latest to ensure npm is up to date
update_node_npm() {
  if ! refresh_package_index; then
    warn "Could not refresh package index for node/npm update."
  fi
  case "${PKG_MANAGER}" in
    apt) run_sudo apt-get install --only-upgrade -y nodejs npm || true ;;
    dnf) run_sudo dnf upgrade -y nodejs npm || true ;;
    yum) run_sudo yum update -y nodejs npm || true ;;
    pacman) run_sudo pacman -S --noconfirm nodejs npm || true ;;
    zypper) run_sudo zypper --non-interactive update nodejs npm || true ;;
    apk) run_sudo apk upgrade nodejs npm || true ;;
    brew) brew upgrade node || true ;;
    *) ;;
  esac

  if command -v npm >/dev/null 2>&1; then
    npm install -g npm@latest || true
  fi
}

# Updates the Laravel installer via Composer global update
update_laravel_installer() {
  ensure_composer_global_bin
  composer global update laravel/installer --no-interaction || true
  ensure_composer_global_bin
}

# Updates a dependency by name
# Dispatches to the appropriate update function based on dependency name
# Args:
#   $1 - Dependency name (php, composer, laravel, node, npm)
update_dep() {
  local dep="$1"
  case "${dep}" in
    php) update_php ;;
    composer) update_composer ;;
    laravel) update_laravel_installer ;;
    node|npm) update_node_npm ;;
    *) return 1 ;;
  esac
}

# =============================================================================
# Main Workflow Functions
# =============================================================================

# Main function that orchestrates the dependency check and preparation
# 1. Detects package manager
# 2. Checks for missing dependencies and prompts for installation
# 3. Detects and optionally applies available updates
check_and_prepare_dependencies() {
  section "Dependency Check (Bash)"

  detect_package_manager
  if [[ -n "${PKG_MANAGER}" ]]; then
    info "Detected package manager: ${PKG_MANAGER}"
  else
    warn "No supported package manager detected."
  fi

  refresh_dep_state
  print_dep_table

  local dep
  for dep in "${DEPS[@]}"; do
    if (( DEP_AVAILABLE["${dep}"] == 0 )); then
      warn "Missing: ${dep}"

      if (( BASH_NON_INTERACTIVE == 1 )); then
        info "Non-interactive: installing ${dep} automatically."
      else
        if ! ask_yes_no "Install ${dep} now" 1; then
          fail "Cannot continue without ${dep}."
          exit 1
        fi
      fi

      if ! install_dep "${dep}"; then
        fail "Installation failed: ${dep}"
        exit 1
      fi

      refresh_dep_state
      print_dep_table
    fi
  done

  refresh_dep_state
  for dep in "${DEPS[@]}"; do
    if (( DEP_AVAILABLE["${dep}"] == 0 )); then
      fail "Still unavailable: ${dep}"
      exit 1
    fi
  done

  detect_available_updates

  if (( ${#DEPS_WITH_UPDATES[@]} > 0 )); then
    print_available_updates

    if (( BASH_NON_INTERACTIVE == 1 )); then
      if (( BASH_APPLY_DEP_UPDATES == 1 )); then
        info "Non-interactive: applying available dependency updates automatically."
        apply_available_updates
        refresh_dep_state
        print_dep_table
      else
        info "Non-interactive: skipping dependency updates (use --deps-update to enable)."
      fi
    else
      if ask_yes_no "Install all available dependency updates now" 1; then
        apply_available_updates
        refresh_dep_state
        print_dep_table
      else
        warn "Updates were skipped."
      fi
    fi
  fi

  ok "Dependencies are ready. Continuing with installation."
}

parse_bash_args() {
  local arg
  for arg in "$@"; do
    case "${arg}" in
      --non-interactive|-y|--yes)
        BASH_NON_INTERACTIVE=1
        ;;
      --deps-update)
        BASH_APPLY_DEP_UPDATES=1
        ;;
      --verbose)
        BASH_VERBOSE=1
        ;;
      --debug)
        BASH_DEBUG=1
        ;;
    esac
  done
}

# =============================================================================
# Entry Point
# =============================================================================

# Main entry point for the Bash phase
# Parses CLI arguments, detects TTY, and runs dependency preparation
main_bash() {
  local arg
  for arg in "$@"; do
    if [[ "${arg}" == "-h" || "${arg}" == "--help" ]]; then
      print_usage
      exit 0
    fi
  done

  parse_bash_args "$@"

  # Enable debug mode if --debug flag is set
  if (( BASH_DEBUG == 1 )); then
    set -x
  fi

  detect_bash_tty
  require_bash_tty_for_interactive

  banner
  check_and_prepare_dependencies
}

# Execute the main Bash function with all CLI arguments
main_bash "$@"

# =============================================================================
# Node.js Installer Phase
# =============================================================================
# The following is an embedded Node.js script that handles:
#   - Configuration loading (CLI args + JSON config)
#   - Interactive prompts for manual mode
#   - Laravel project creation/update
#   - Package installation and setup
#   - Final health checks and server startup
# =============================================================================

# Create temporary file for embedded Node.js code
NODE_TMP="$(mktemp "${TMPDIR:-/tmp}/instalar-node-XXXXXX.cjs")"
cleanup_node_tmp() {
  rm -f "${NODE_TMP}"
}
trap cleanup_node_tmp EXIT

# Write the embedded Node.js script to temp file and execute it
cat > "${NODE_TMP}" <<'NODE'
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const { spawn } = require("node:child_process");
const readline = require("node:readline/promises");
const readlineCore = require("node:readline");

// =============================================================================
// Console Styling
// =============================================================================
// ANSI color helpers for consistent terminal output in the Node.js phase.
const C = {
  reset: "\x1b[0m",
  bold: "\x1b[1m",
  dim: "\x1b[2m",
  red: "\x1b[31m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  blue: "\x1b[34m",
  magenta: "\x1b[35m",
  cyan: "\x1b[36m",
  white: "\x1b[37m",
};

// =============================================================================
// Optional Package Catalog
// =============================================================================
// Defines selectable Composer packages for manual mode.
const OPTIONAL_PACKAGE_CHOICES = [
  { id: "fortify", title: "Fortify Auth Backend", normal: ["laravel/fortify"] },
  { id: "ai", title: "Laravel AI SDK", normal: ["laravel/ai"] },
  { id: "horizon", title: "Horizon Queue Dashboard", normal: ["laravel/horizon"] },
  { id: "pulse", title: "Pulse Monitoring", normal: ["laravel/pulse"] },
  { id: "socialite", title: "Socialite OAuth", normal: ["laravel/socialite"] },
  { id: "flux", title: "Livewire Flux UI", normal: ["livewire/flux"] },
  { id: "telescope", title: "Telescope Debug Assistant", normal: ["laravel/telescope"] },
  { id: "pail", title: "Pail Log Tail", normal: ["laravel/pail"] },
  { id: "sanctum", title: "Sanctum API Tokens", normal: ["laravel/sanctum"] },
  { id: "passport", title: "Passport OAuth2 Server", normal: ["laravel/passport"] },
  { id: "pennant", title: "Pennant Feature Flags", normal: ["laravel/pennant"] },
  { id: "reverb", title: "Reverb WebSockets", normal: ["laravel/reverb"] },
  { id: "spatie_permission", title: "Spatie Permission", normal: ["spatie/laravel-permission"] },
  { id: "spatie_activitylog", title: "Spatie Activitylog", normal: ["spatie/laravel-activitylog"] },
  { id: "spatie_medialibrary", title: "Spatie Medialibrary", normal: ["spatie/laravel-medialibrary"] },
  { id: "spatie_health", title: "Spatie Health", normal: ["spatie/laravel-health"] },
  {
    id: "modules_bundle",
    title: "Modules Bundle (nwidart + coolsam)",
    normal: ["nwidart/laravel-modules", "coolsam/modules"],
  },
  { id: "dusk", title: "Dusk (dev)", dev: ["laravel/dusk"] },
  { id: "debugbar", title: "Debugbar (dev)", dev: ["barryvdh/laravel-debugbar"] },
  { id: "excel", title: "Laravel Excel", normal: ["maatwebsite/excel"] },
  { id: "ide_helper", title: "Laravel IDE Helper", dev: ["barryvdh/laravel-ide-helper"] },
  { id: "migration_generator", title: "Migration Generator", dev: ["kitloong/laravel-migrations-generator"] },
  { id: "model_types", title: "Spatie Model Types", normal: ["spatie/laravel-model-states"] },
  { id: "laravel_breadcrumbs", title: "Breadcrumbs", normal: ["davejamesmiller/laravel-breadcrumbs"] },
  { id: "flare", title: "Flare Error Tracking", normal: ["spatie/laravel-ignition"] },
];

// Shared runtime state for warnings, generated admin credentials, and resolved options.
const state = {
  warnings: [],
  createdAdmin: null,
  runtime: {
    nonInteractive: false,
    backup: false,
    adminGenerate: false,
    allowDeleteExisting: false,
    startServer: false,
    mode: null,
    configPath: null,
    config: {},
    verbose: false,
    debug: false,
  },
};

// Wraps text with an ANSI color and reset code.
function color(text, code) {
  return `${code}${text}${C.reset}`;
}

// Prints an informational message.
function info(message) {
  console.log(`  ${color("[INFO]", C.cyan)} ${message}`);
}

// Prints a success message.
function ok(message) {
  console.log(`  ${color("[ OK ]", C.green)} ${message}`);
}

// Prints a warning message and stores it for the final summary.
function warn(message) {
  state.warnings.push(message);
  console.log(`  ${color("[WARN]", C.yellow)} ${message}`);
}

// Prints an error message.
function fail(message) {
  console.log(`  ${color("[ERR ]", C.red)} ${message}`);
}

// Prints a verbose message when --verbose flag is set.
function verbose(message) {
  if (state.runtime.verbose || state.runtime.debug) {
    console.log(color(`  [VERBOSE] ${message}`, C.dim));
  }
}

// Prints a debug message when --debug flag is set.
function debug(message) {
  if (state.runtime.debug) {
    console.log(color(`  [DEBUG] ${message}`, C.gray));
  }
}

// Prints a visual section heading.
function section(title) {
  const line = "-".repeat(72);
  console.log(`\n${color(line, C.dim)}`);
  console.log(color(title, C.bold + C.white));
  console.log(color(line, C.dim));
}

// Parses Node-phase CLI arguments and normalizes known flags.
function parseCliArgs(args) {
  const options = {
    help: false,
    nonInteractive: false,
    configPath: null,
    backup: false,
    adminGenerate: false,
    mode: null,
    allowDeleteExisting: false,
    startServer: false,
    verbose: false,
    debug: false,
  };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];

    if (arg === "-h" || arg === "--help") {
      options.help = true;
      continue;
    }

    if (arg === "--non-interactive" || arg === "-y" || arg === "--yes") {
      options.nonInteractive = true;
      continue;
    }

    if (arg === "--backup") {
      options.backup = true;
      continue;
    }

    if (arg === "--admin-generate") {
      options.adminGenerate = true;
      continue;
    }

    if (arg === "--allow-delete-existing") {
      options.allowDeleteExisting = true;
      continue;
    }

    if (arg === "--start-server") {
      options.startServer = true;
      continue;
    }

    if (arg === "--verbose") {
      options.verbose = true;
      continue;
    }

    if (arg === "--debug") {
      options.debug = true;
      continue;
    }

    if (arg.startsWith("--config=")) {
      options.configPath = arg.slice("--config=".length);
      continue;
    }

    if (arg === "--config") {
      const next = args[index + 1];
      if (next) {
        options.configPath = next;
        index += 1;
      }
      continue;
    }

    if (arg.startsWith("--mode=")) {
      options.mode = arg.slice("--mode=".length);
      continue;
    }

    if (arg === "--mode") {
      const next = args[index + 1];
      if (next) {
        options.mode = next;
        index += 1;
      }
    }
  }

  if (options.mode) {
    options.mode = options.mode.toLowerCase();
  }

  if (!["auto", "manual", "update", null].includes(options.mode)) {
    warn(`Invalid --mode value: ${options.mode}. Use auto, manual, or update.`);
    options.mode = null;
  }

  return options;
}

// Loads installer JSON config from disk and validates top-level shape.
function loadInstallerConfig(configPath) {
  const resolvedPath = path.resolve(process.cwd(), configPath);
  if (!fs.existsSync(resolvedPath)) {
    return { path: resolvedPath, config: null };
  }

  try {
    const parsed = JSON.parse(fs.readFileSync(resolvedPath, "utf8"));
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      warn(`Configuration file is not a JSON object: ${resolvedPath}`);
      return { path: resolvedPath, config: {} };
    }
    return { path: resolvedPath, config: parsed };
  } catch (error) {
    throw new Error(`Unable to read configuration file: ${resolvedPath} (${error.message})`);
  }
}

// Resolves runtime settings by merging CLI options with JSON config values.
function resolveRuntime(cliOptions, fileConfig, configPath) {
  const resolvedMode = (cliOptions.mode || fileConfig?.mode || "").toLowerCase() || null;
  return {
    nonInteractive: Boolean(cliOptions.nonInteractive || fileConfig?.nonInteractive === true),
    backup: Boolean(cliOptions.backup || fileConfig?.backup === true),
    adminGenerate: Boolean(cliOptions.adminGenerate || fileConfig?.adminGenerate === true),
    allowDeleteExisting: Boolean(
      cliOptions.allowDeleteExisting || fileConfig?.allowDeleteExisting === true,
    ),
    startServer: Boolean(cliOptions.startServer || fileConfig?.startServer === true),
    mode: ["auto", "manual", "update"].includes(resolvedMode) ? resolvedMode : null,
    configPath,
    config: fileConfig || {},
    verbose: Boolean(cliOptions.verbose || fileConfig?.verbose === true),
    debug: Boolean(cliOptions.debug || fileConfig?.debug === true),
  };
}

// Builds a mode-specific preset by merging root config with mode overrides.
function getModePreset(mode) {
  const rootConfig = state.runtime.config || {};
  const modeConfig =
    rootConfig[mode] && typeof rootConfig[mode] === "object" && !Array.isArray(rootConfig[mode])
      ? rootConfig[mode]
      : {};

  return { ...rootConfig, ...modeConfig };
}

// Creates a random alphanumeric password used for generated admin credentials.
function generateAdminPassword(length = 20) {
  return crypto
    .randomBytes(length)
    .toString("base64")
    .replace(/[^a-zA-Z0-9]/g, "")
    .slice(0, length);
}

// Prompts for a text input with optional default and non-interactive fallback.
async function ask(question, defaultValue = "") {
  if (state.runtime.nonInteractive) {
    const value = defaultValue ?? "";
    info(`[non-interactive] ${question}: ${value === "" ? "(empty)" : value}`);
    return String(value);
  }

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  try {
    const suffix = defaultValue ? color(` [${defaultValue}]`, C.dim) : "";
    const answer = (await rl.question(`${color("?", C.cyan)} ${question}${suffix}: `)).trim();
    return answer || defaultValue;
  } finally {
    rl.close();
  }
}

// Prompts until a non-empty value is provided.
async function askRequired(question, defaultValue = "") {
  while (true) {
    const answer = await ask(question, defaultValue);
    if (answer.trim().length > 0) {
      return answer.trim();
    }

    if (state.runtime.nonInteractive) {
      throw new Error(`Required value missing in non-interactive mode: ${question}`);
    }

    warn("Input cannot be empty.");
  }
}

// Prompts for a yes/no answer with localized aliases.
async function askYesNo(question, defaultYes = true) {
  if (state.runtime.nonInteractive) {
    info(`[non-interactive] ${question}: ${defaultYes ? "yes" : "no"}`);
    return defaultYes;
  }

  const hint = defaultYes ? "Y/n" : "y/N";
  while (true) {
    const answer = (await ask(`${question} (${hint})`, "")).toLowerCase();
    if (!answer) {
      return defaultYes;
    }
    if (["j", "ja", "y", "yes"].includes(answer)) {
      return true;
    }
    if (["n", "nein", "no"].includes(answer)) {
      return false;
    }
    warn("Please answer with y or n.");
  }
}

// Prompts for a single-choice selection and returns the chosen index.
async function askChoice(question, options, defaultIndex = 0) {
  if (state.runtime.nonInteractive) {
    const fallbackIndex = Math.min(Math.max(defaultIndex, 0), Math.max(options.length - 1, 0));
    info(`[non-interactive] ${question}: ${options[fallbackIndex] ?? ""}`);
    return fallbackIndex;
  }

  console.log(`\n${color(question, C.bold + C.white)}`);
  options.forEach((option, index) => {
    const mark = index === defaultIndex ? color(" (default)", C.dim) : "";
    console.log(`  ${color(String(index + 1), C.cyan)}) ${option}${mark}`);
  });

  while (true) {
    const raw = await ask("Selection", String(defaultIndex + 1));
    const num = Number.parseInt(raw, 10);
    if (Number.isInteger(num) && num >= 1 && num <= options.length) {
      return num - 1;
    }
    warn("Invalid selection.");
  }
}

// Prompts for multi-select values using interactive UI or text fallback.
async function askMultiChoice(question, options, defaultIndexes = []) {
  if (state.runtime.nonInteractive) {
    const filtered = defaultIndexes
      .filter((index) => Number.isInteger(index) && index >= 0 && index < options.length)
      .sort((a, b) => a - b);
    const labels = filtered.map((index) => options[index]);
    info(
      `[non-interactive] ${question}: ${labels.length > 0 ? labels.join(", ") : "none"}`,
    );
    return filtered;
  }

  const interactiveSelection = await askMultiChoiceInteractive(question, options, defaultIndexes);
  if (interactiveSelection) {
    return interactiveSelection;
  }

  console.log(`\n${color(question, C.bold + C.white)}`);
  options.forEach((option, index) => {
    const mark = defaultIndexes.includes(index) ? color(" [x]", C.green) : "";
    console.log(`  ${color(String(index + 1), C.cyan)}) ${option}${mark}`);
  });
  console.log(`  ${color("Tip", C.dim)}: Separate multiple values with comma or space`);

  const defaultValue = defaultIndexes.map((index) => String(index + 1)).join(",");

  while (true) {
    const raw = await ask("Selection", defaultValue);
    if (!raw.trim()) {
      return [...defaultIndexes];
    }

    const tokens = raw
      .split(/[\s,]+/g)
      .map((token) => token.trim())
      .filter(Boolean);

    const selected = new Set();
    let valid = true;

    for (const token of tokens) {
      const num = Number.parseInt(token, 10);
      if (!Number.isInteger(num) || num < 1 || num > options.length) {
        valid = false;
        break;
      }
      selected.add(num - 1);
    }

    if (valid) {
      return [...selected].sort((a, b) => a - b);
    }

    warn("Please enter only valid numbers.");
  }
}

// Adds a virtual "Select all" option on top of the multi-select prompt.
async function askMultiChoiceWithAll(question, options, defaultIndexes = []) {
  const optionsWithAll = ["Select all", ...options];
  const defaultWithAll =
    defaultIndexes.length === options.length && options.length > 0
      ? [0, ...defaultIndexes.map((index) => index + 1)]
      : defaultIndexes.map((index) => index + 1);

  const selected = await askMultiChoice(question, optionsWithAll, defaultWithAll);

  if (selected.includes(0)) {
    return options.map((_, index) => index);
  }

  return selected
    .filter((index) => index > 0)
    .map((index) => index - 1)
    .sort((a, b) => a - b);
}

// Interactive multi-select UI using raw terminal key events.
async function askMultiChoiceInteractive(question, options, defaultIndexes = []) {
  if (
    !process.stdin.isTTY ||
    !process.stdout.isTTY ||
    typeof process.stdin.setRawMode !== "function"
  ) {
    return null;
  }

  const selected = new Set(defaultIndexes);
  let cursor = 0;
  let firstRender = true;
  const rows = options.length + 3;

  const render = () => {
    if (!firstRender) {
      process.stdout.write(`\x1b[${rows}A`);
    }

    process.stdout.write("\x1b[0J");
    process.stdout.write(`${color(question, C.bold + C.white)}\n`);

    options.forEach((option, index) => {
      const pointer = index === cursor ? color("›", C.cyan) : " ";
      const mark = selected.has(index) ? color("[x]", C.green) : "[ ]";
      process.stdout.write(`  ${pointer} ${mark} ${option}\n`);
    });

    process.stdout.write(
      `  ${color("Controls:", C.dim)} ${color("↑/↓", C.cyan)} move, ${color("Space", C.cyan)} toggle, ${color("Enter", C.cyan)} confirm\n`,
    );
    process.stdout.write("\n");

    firstRender = false;
  };

  return new Promise((resolve, reject) => {
    const onKeypress = (_str, key) => {
      if (!key) {
        return;
      }

      if (key.ctrl && key.name === "c") {
        cleanup();
        reject(new Error("Cancelled by user."));
        return;
      }

      if (key.name === "up") {
        cursor = (cursor - 1 + options.length) % options.length;
        render();
        return;
      }

      if (key.name === "down") {
        cursor = (cursor + 1) % options.length;
        render();
        return;
      }

      if (key.name === "space") {
        if (selected.has(cursor)) {
          selected.delete(cursor);
        } else {
          selected.add(cursor);
        }
        render();
        return;
      }

      if (key.name === "return" || key.name === "enter") {
        cleanup();
        resolve([...selected].sort((a, b) => a - b));
      }
    };

    const cleanup = () => {
      process.stdin.off("keypress", onKeypress);
      if (process.stdin.isTTY && typeof process.stdin.setRawMode === "function") {
        process.stdin.setRawMode(false);
      }
      process.stdin.pause();
      process.stdout.write("\x1b[?25h");
    };

    readlineCore.emitKeypressEvents(process.stdin);
    process.stdin.setRawMode(true);
    process.stdin.resume();
    process.stdout.write("\x1b[?25l");
    process.stdout.write("\n");
    process.stdin.on("keypress", onKeypress);

    render();
  });
}

// Converts arbitrary app names to URL/path-safe slugs.
function slugify(value) {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .replace(/-{2,}/g, "-");
}

// Extracts the Composer package name from a package spec string.
function packageNameFromSpec(spec) {
  const trimmed = spec.trim();
  const index = trimmed.indexOf(":");
  return index === -1 ? trimmed : trimmed.slice(0, index).trim();
}

// Merges package specs by package name, keeping the last declaration.
function mergePackageSpecs(specs) {
  const map = new Map();
  for (const spec of specs) {
    if (!spec || !spec.trim()) {
      continue;
    }
    map.set(packageNameFromSpec(spec), spec.trim());
  }
  return [...map.values()];
}

// Splits comma/space-separated package input into normalized entries.
function splitPackageInput(raw) {
  return raw
    .split(/[\s,]+/g)
    .map((entry) => entry.trim())
    .filter(Boolean);
}

// Normalizes test-suite aliases to canonical Laravel flags.
function normalizeLaravelTestSuiteFlag(value) {
  if (typeof value !== "string") {
    return null;
  }

  const normalized = value.trim().toLowerCase();
  if (normalized === "--pest" || normalized === "pest") {
    return "--pest";
  }

  if (normalized === "--phpunit" || normalized === "phpunit") {
    return "--phpunit";
  }

  return null;
}

// Normalizes Laravel scaffold flags and enforces a single test suite flag.
function normalizeLaravelFlags(
  flags,
  fallback = ["--npm", "--livewire", "--boost", "--pest"],
  preferredTestSuite = null,
) {
  const validStartupFlags = new Set(["--npm", "--livewire", "--boost"]);
  const startupFlags = [];
  let testSuiteFlag = normalizeLaravelTestSuiteFlag(preferredTestSuite);

  if (Array.isArray(flags) && flags.length > 0) {
    for (const flag of flags) {
      if (validStartupFlags.has(flag) && !startupFlags.includes(flag)) {
        startupFlags.push(flag);
      }

      if (!testSuiteFlag) {
        const candidate = normalizeLaravelTestSuiteFlag(flag);
        if (candidate) {
          testSuiteFlag = candidate;
        }
      }
    }
  }

  if (startupFlags.length === 0 && Array.isArray(fallback)) {
    for (const flag of fallback) {
      if (validStartupFlags.has(flag) && !startupFlags.includes(flag)) {
        startupFlags.push(flag);
      }
    }
  }

  if (!testSuiteFlag && Array.isArray(fallback)) {
    for (const flag of fallback) {
      const candidate = normalizeLaravelTestSuiteFlag(flag);
      if (candidate) {
        testSuiteFlag = candidate;
        break;
      }
    }
  }

  return [...startupFlags, testSuiteFlag || "--pest"];
}

// Converts configured optional package IDs to option indexes.
function getOptionIndexesByIds(ids, fallback = []) {
  if (!Array.isArray(ids) || ids.length === 0) {
    return [...fallback];
  }

  if (ids.includes("all") || ids.includes("*") || ids.includes("Alles")) {
    return OPTIONAL_PACKAGE_CHOICES.map((_, index) => index);
  }

  const indexes = [];
  for (const id of ids) {
    const index = OPTIONAL_PACKAGE_CHOICES.findIndex((choice) => choice.id === id);
    if (index >= 0 && !indexes.includes(index)) {
      indexes.push(index);
    }
  }

  return indexes.length > 0 ? indexes : [...fallback];
}

// Executes a subprocess and resolves/rejects based on exit code.
function runProcess(command, args, options = {}) {
  const { cwd = process.cwd(), stdio = "inherit", env = process.env } = options;

  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd, stdio, env });

    child.on("error", (error) => reject(error));
    child.on("close", (code, signal) => {
      if (code === 0) {
        resolve();
        return;
      }

      const error = new Error(`Command failed: ${command} ${args.join(" ")}`);
      error.exitCode = code;
      error.signal = signal;
      reject(error);
    });
  });
}

// Executes a command with standard installer logging and optional failure behavior.
async function runCommand(command, args, options = {}) {
  const { cwd = process.cwd(), required = true, warnOnFailure = true } = options;
  const cmdStr = `${command} ${args.join(" ")}`.trim();

  // Use verbose() if verbose or debug is enabled
  if (state.runtime.verbose || state.runtime.debug) {
    verbose(`Executing: ${cmdStr}`);
  } else {
    info(`Run: ${cmdStr}`);
  }

  try {
    await runProcess(command, args, { cwd });
    ok(`${command} ${args[0] ?? ""}`.trim());
    return { exitCode: 0, success: true };
  } catch (error) {
    const exitCode = error.exitCode || 1;
    if (required) {
      throw error;
    }
    if (warnOnFailure) {
      warn(`Command failed and will be skipped: ${cmdStr}`);
    } else {
      info(`Command failed and will be skipped: ${cmdStr}`);
    }
    return { exitCode, success: false };
  }
}

// Checks if an Artisan command exists in the current project.
async function artisanCommandExists(projectDir, commandName) {
  try {
    await runProcess("php", ["artisan", commandName, "--help"], {
      cwd: projectDir,
      stdio: "ignore",
    });
    return true;
  } catch {
    return false;
  }
}

// Runs an Artisan command only if it exists; otherwise logs a skip message.
async function runArtisanIfAvailable(
  projectDir,
  commandName,
  args = [],
  messageIfMissing = "",
  options = {},
) {
  const { warnOnFailure = true } = options;

  const exists = await artisanCommandExists(projectDir, commandName);
  if (!exists) {
    if (messageIfMissing) {
      info(messageIfMissing);
    } else {
      info(`${commandName} not available, skipping.`);
    }
    return false;
  }

  return runCommand("php", ["artisan", commandName, ...args], {
    cwd: projectDir,
    required: false,
    warnOnFailure,
  });
}

// Detects whether a directory appears to be a Laravel project root.
function isLaravelProject(directory) {
  return (
    fs.existsSync(path.join(directory, "artisan")) &&
    fs.existsSync(path.join(directory, "bootstrap", "app.php")) &&
    fs.existsSync(path.join(directory, "composer.json"))
  );
}

// Returns true when the directory does not exist or has no entries.
function directoryIsEmpty(directory) {
  if (!fs.existsSync(directory)) {
    return true;
  }
  return fs.readdirSync(directory).length === 0;
}

// Builds a compact timestamp used for backup path suffixes.
function getTimestampLabel() {
  const now = new Date();
  const pad = (value) => String(value).padStart(2, "0");
  return `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}-${pad(
    now.getHours(),
  )}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
}

// Computes a unique backup path for an existing project directory.
function getBackupTargetPath(sourcePath) {
  const base = `${sourcePath}.backup-${getTimestampLabel()}`;
  if (!fs.existsSync(base)) {
    return base;
  }

  let count = 1;
  while (fs.existsSync(`${base}-${count}`)) {
    count += 1;
  }
  return `${base}-${count}`;
}

// Moves a path to backup target, falling back to copy+delete when rename fails.
function backupExistingPath(sourcePath) {
  const targetPath = getBackupTargetPath(sourcePath);

  try {
    fs.renameSync(sourcePath, targetPath);
    return targetPath;
  } catch {
    fs.cpSync(sourcePath, targetPath, { recursive: true });
    fs.rmSync(sourcePath, { recursive: true, force: true });
    return targetPath;
  }
}

// Escapes an environment value when quoting is required.
function envSafeValue(value) {
  const text = String(value);
  if (/^[A-Za-z0-9_./:@-]*$/.test(text)) {
    return text;
  }
  return `"${text.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

// Sets or appends a key/value pair in .env file content.
function setEnvValue(content, key, value) {
  const safe = envSafeValue(value);
  const regex = new RegExp(`^${key}=.*$`, "m");

  if (regex.test(content)) {
    return content.replace(regex, `${key}=${safe}`);
  }

  const separator = content.endsWith("\n") ? "" : "\n";
  return `${content}${separator}${key}=${safe}\n`;
}

// Applies database/app-related environment values to the project .env file.
function applyEnvConfig(projectDir, config) {
  const envPath = path.join(projectDir, ".env");
  const envExamplePath = path.join(projectDir, ".env.example");

  if (!fs.existsSync(envPath) && fs.existsSync(envExamplePath)) {
    fs.copyFileSync(envExamplePath, envPath);
  }

  if (!fs.existsSync(envPath)) {
    throw new Error(".env could not be found or created.");
  }

  let env = fs.readFileSync(envPath, "utf8");
  env = setEnvValue(env, "APP_NAME", config.appName);

  if (config.database.connection === "sqlite") {
    const sqliteFile = path.join(projectDir, "database", "database.sqlite");
    fs.mkdirSync(path.dirname(sqliteFile), { recursive: true });
    fs.closeSync(fs.openSync(sqliteFile, "a"));

    env = setEnvValue(env, "DB_CONNECTION", "sqlite");
    env = setEnvValue(env, "DB_DATABASE", "database/database.sqlite");
  }

  if (config.database.connection === "mysql" || config.database.connection === "pgsql") {
    env = setEnvValue(env, "DB_CONNECTION", config.database.connection);
    env = setEnvValue(env, "DB_HOST", config.database.host);
    env = setEnvValue(env, "DB_PORT", config.database.port);
    env = setEnvValue(env, "DB_DATABASE", config.database.database);
    env = setEnvValue(env, "DB_USERNAME", config.database.username);
    env = setEnvValue(env, "DB_PASSWORD", config.database.password);
  }

  fs.writeFileSync(envPath, env, "utf8");
}

// Reads package names from require and require-dev sections of composer.json.
function readComposerPackages(projectDir) {
  const composerPath = path.join(projectDir, "composer.json");
  if (!fs.existsSync(composerPath)) {
    return new Set();
  }

  const json = JSON.parse(fs.readFileSync(composerPath, "utf8"));
  const names = new Set();

  Object.keys(json.require || {}).forEach((key) => names.add(key));
  Object.keys(json["require-dev"] || {}).forEach((key) => names.add(key));

  return names;
}

// Detects whether two-factor migration columns already exist.
function hasTwoFactorMigration(projectDir) {
  const migrationsDir = path.join(projectDir, "database", "migrations");
  if (!fs.existsSync(migrationsDir)) {
    return false;
  }

  const files = fs.readdirSync(migrationsDir).filter((entry) => entry.endsWith(".php"));

  return files.some((file) => {
    if (file.toLowerCase().includes("two_factor")) {
      return true;
    }

    try {
      const content = fs.readFileSync(path.join(migrationsDir, file), "utf8");
      return (
        content.includes("two_factor_secret") ||
        content.includes("two_factor_recovery_codes")
      );
    } catch {
      return false;
    }
  });
}

// Removes duplicate two-factor migrations to avoid migrate conflicts.
function cleanupDuplicateTwoFactorMigrations(projectDir) {
  const migrationsDir = path.join(projectDir, "database", "migrations");
  if (!fs.existsSync(migrationsDir)) {
    return [];
  }

  const files = fs
    .readdirSync(migrationsDir)
    .filter((entry) => /add_two_factor_columns_to_users_table\.php$/i.test(entry))
    .sort();

  if (files.length <= 1) {
    return [];
  }

  const removable = files.slice(1);
  const removed = [];

  for (const file of removable) {
    const fullPath = path.join(migrationsDir, file);
    try {
      fs.unlinkSync(fullPath);
      removed.push(file);
    } catch {
      // ignore and continue; migrate step will report if still problematic
    }
  }

  return removed;
}

// Collects auto-mode installation config from prompts and presets.
async function collectAutoConfig(preset = {}) {
  section("Auto Mode");

  const appNameDefault = preset.projectName || preset.appName || "Laravel Filament App";
  const appName = await askRequired("Project name", appNameDefault);
  const slug = slugify(appName) || "laravel-filament-app";
  const projectPath = path.resolve(process.cwd(), preset.projectPath || slug);

  const databaseConnection = ["sqlite", "mysql", "pgsql"].includes(preset?.database?.connection)
    ? preset.database.connection
    : "sqlite";

  let database = { connection: "sqlite" };
  if (databaseConnection === "mysql" || databaseConnection === "pgsql") {
    database = {
      connection: databaseConnection,
      host: preset?.database?.host || "127.0.0.1",
      port:
        preset?.database?.port || (databaseConnection === "mysql" ? "3306" : "5432"),
      database: preset?.database?.database || "app",
      username: preset?.database?.username || (databaseConnection === "mysql" ? "root" : "postgres"),
      password: preset?.database?.password || "",
    };
  }

  const laravelNewFlags = normalizeLaravelFlags(
    preset.laravelNewFlags || preset.laravelFlags,
    ["--npm", "--livewire", "--boost", "--pest"],
    preset.testSuite,
  );

  const createAdmin = preset.createAdmin !== undefined ? Boolean(preset.createAdmin) : true;
  const adminPassword =
    createAdmin && state.runtime.adminGenerate && !preset?.admin?.password
      ? generateAdminPassword(20)
      : preset?.admin?.password || "password";

  if (createAdmin && state.runtime.adminGenerate) {
    info("Admin password will be generated automatically (--admin-generate).");
  }

  return {
    mode: "auto",
    appName,
    projectPath,
    database,
    laravelNewFlags,
    normalPackages: mergePackageSpecs([
      "filament/filament:^5.0",
      "laravel/fortify",
      "laravel/ai",
      ...(Array.isArray(preset.normalPackages) ? preset.normalPackages : []),
    ]),
    devPackages: mergePackageSpecs(Array.isArray(preset.devPackages) ? preset.devPackages : []),
    createAdmin,
    admin: {
      name: preset?.admin?.name || "Admin",
      email: preset?.admin?.email || "admin@example.com",
      password: adminPassword,
    },
    gitInit: Boolean(preset.gitInit),
  };
}

// Collects manual-mode installation config with full interactive choices.
async function collectManualConfig(preset = {}) {
  section("Manual Mode");

  const appNameDefault = preset.projectName || preset.appName || "Laravel Filament App";
  const appName = await askRequired("Project name", appNameDefault);
  const defaultDir = `./${slugify(appName) || "laravel-filament-app"}`;
  const defaultProjectPath = preset.projectPath || defaultDir;
  const projectPath = path.resolve(process.cwd(), await askRequired("Project directory", defaultProjectPath));

  const defaultDbChoice =
    preset?.database?.connection === "mysql"
      ? 1
      : preset?.database?.connection === "pgsql"
        ? 2
        : 0;

  const dbChoice = await askChoice(
    "Choose database",
    ["SQLite", "MySQL", "PostgreSQL"],
    defaultDbChoice,
  );

  let database = { connection: "sqlite" };
  if (dbChoice === 1) {
    database = {
      connection: "mysql",
      host: await ask("DB Host", preset?.database?.host || "127.0.0.1"),
      port: await ask("DB Port", preset?.database?.port || "3306"),
      database: await askRequired("DB Name", preset?.database?.database || "app"),
      username: await askRequired("DB User", preset?.database?.username || "root"),
      password: await ask("DB Password", preset?.database?.password || ""),
    };
  }
  if (dbChoice === 2) {
    database = {
      connection: "pgsql",
      host: await ask("DB Host", preset?.database?.host || "127.0.0.1"),
      port: await ask("DB Port", preset?.database?.port || "5432"),
      database: await askRequired("DB Name", preset?.database?.database || "app"),
      username: await askRequired("DB User", preset?.database?.username || "postgres"),
      password: await ask("DB Password", preset?.database?.password || ""),
    };
  }

  const laravelFlagOptions = ["--npm", "--livewire", "--boost"];
  const resolvedLaravelFlags = normalizeLaravelFlags(
    preset.laravelNewFlags || preset.laravelFlags,
    ["--npm", "--livewire", "--boost", "--pest"],
    preset.testSuite,
  );
  const defaultLaravelFlagIndexes = laravelFlagOptions
    .map((flag, index) => (resolvedLaravelFlags.includes(flag) ? index : -1))
    .filter((index) => index >= 0);
  const selectedLaravelFlagIndexes = await askMultiChoiceWithAll(
    "Choose Laravel startup flags",
    laravelFlagOptions,
    defaultLaravelFlagIndexes,
  );
  const selectedStartupFlags = selectedLaravelFlagIndexes.map(
    (index) => laravelFlagOptions[index],
  );

  const defaultTestSuiteIndex = resolvedLaravelFlags.includes("--phpunit") ? 1 : 0;
  const testSuiteChoice = await askChoice(
    "Choose Laravel test suite",
    ["Pest", "PHPUnit"],
    defaultTestSuiteIndex,
  );
  const testSuiteFlag = testSuiteChoice === 1 ? "--phpunit" : "--pest";
  const laravelNewFlags = [...selectedStartupFlags, testSuiteFlag];

  const optionalLabels = OPTIONAL_PACKAGE_CHOICES.map((choice) => choice.title);
  const defaultOptionalIndexes = getOptionIndexesByIds(preset.optionalPackageIds, [0, 1]);
  const selected = await askMultiChoiceWithAll(
    "Choose optional packages (Filament + Boost are always active)",
    optionalLabels,
    defaultOptionalIndexes,
  );

  const normalPackages = ["filament/filament:^5.0", "laravel/boost"];
  const devPackages = [];

  selected.forEach((index) => {
    const choice = OPTIONAL_PACKAGE_CHOICES[index];
    if (choice.normal) {
      normalPackages.push(...choice.normal);
    }
    if (choice.dev) {
      devPackages.push(...choice.dev);
    }
  });

  const customNormalDefault = Array.isArray(preset.customNormalPackages)
    ? preset.customNormalPackages.join(" ")
    : "";
  const customDevDefault = Array.isArray(preset.customDevPackages)
    ? preset.customDevPackages.join(" ")
    : "";

  const customNormal = splitPackageInput(
    await ask("Custom Composer packages (normal, optional)", customNormalDefault),
  );
  const customDev = splitPackageInput(
    await ask("Custom Composer packages (dev, optional)", customDevDefault),
  );

  const defaultCreateAdmin =
    preset.createAdmin !== undefined ? Boolean(preset.createAdmin) : true;
  const createAdmin = await askYesNo("Create Filament admin user", defaultCreateAdmin);

  const adminPassword =
    createAdmin && state.runtime.adminGenerate && !preset?.admin?.password
      ? generateAdminPassword(20)
      : preset?.admin?.password || "password";

  if (createAdmin) {
    if (state.runtime.adminGenerate) {
      info("Admin password will be generated automatically (--admin-generate).");
    } else {
      info("Default admin will be used: admin@example.com / password");
    }
  }

  const gitInit = await askYesNo(
    "Run git init",
    preset.gitInit !== undefined ? Boolean(preset.gitInit) : false,
  );

  return {
    mode: "manual",
    appName,
    projectPath,
    database,
    laravelNewFlags,
    normalPackages: mergePackageSpecs([...normalPackages, ...customNormal]),
    devPackages: mergePackageSpecs([...devPackages, ...customDev]),
    createAdmin,
    admin: {
      name: preset?.admin?.name || "Admin",
      email: preset?.admin?.email || "admin@example.com",
      password: adminPassword,
    },
    gitInit,
  };
}

// Converts normalized config package specs into a fast lookup Set.
function packageSetFromConfig(config) {
  const names = new Set();
  config.normalPackages.forEach((spec) => names.add(packageNameFromSpec(spec)));
  config.devPackages.forEach((spec) => names.add(packageNameFromSpec(spec)));

  if (Array.isArray(config.laravelNewFlags) && config.laravelNewFlags.includes("--boost")) {
    names.add("laravel/boost");
  }

  return names;
}

// Extracts an object property block (e.g. server: { ... }) from source text.
function extractObjectPropertyBlock(source, propertyName) {
  const propertyIndex = source.indexOf(`${propertyName}:`);
  if (propertyIndex === -1) {
    return "";
  }

  const braceStart = source.indexOf("{", propertyIndex);
  if (braceStart === -1) {
    return "";
  }

  let depth = 0;
  let braceEnd = -1;
  for (let index = braceStart; index < source.length; index += 1) {
    const char = source[index];
    if (char === "{") {
      depth += 1;
    }
    if (char === "}") {
      depth -= 1;
      if (depth === 0) {
        braceEnd = index;
        break;
      }
    }
  }

  if (braceEnd === -1) {
    return "";
  }

  let end = braceEnd + 1;
  while (end < source.length && /\s/.test(source[end])) {
    end += 1;
  }
  if (source[end] === ",") {
    end += 1;
  }

  return source.slice(propertyIndex, end).trimEnd();
}

// Indents every line of a multi-line string by a fixed number of spaces.
function indentLines(value, spaces) {
  const indentation = " ".repeat(spaces);
  return value
    .split("\n")
    .map((line) => `${indentation}${line}`)
    .join("\n");
}

// Ensures composer plugin allow-list contains wikimedia/composer-merge-plugin.
async function ensureComposerPluginAllowList(projectDir, packages) {
  const needsMergePlugin =
    packages.has("coolsam/modules") ||
    packages.has("nwidart/laravel-modules") ||
    packages.has("wikimedia/composer-merge-plugin");

  if (!needsMergePlugin) {
    return;
  }

  section("Composer Plugin Allow-List");
  info("Checking allow-plugins for wikimedia/composer-merge-plugin");

  await runCommand(
    "composer",
    [
      "config",
      "--no-plugins",
      "allow-plugins.wikimedia/composer-merge-plugin",
      "true",
      "--no-interaction",
    ],
    {
      cwd: projectDir,
      required: false,
      warnOnFailure: false,
    },
  );

  const composerPath = path.join(projectDir, "composer.json");
  if (!fs.existsSync(composerPath)) {
    return;
  }

  try {
    const composerJson = JSON.parse(fs.readFileSync(composerPath, "utf8"));
    let changed = false;

    if (
      !composerJson.config ||
      typeof composerJson.config !== "object" ||
      Array.isArray(composerJson.config)
    ) {
      composerJson.config = {};
      changed = true;
    }

    if (
      !composerJson.config["allow-plugins"] ||
      typeof composerJson.config["allow-plugins"] !== "object" ||
      Array.isArray(composerJson.config["allow-plugins"])
    ) {
      composerJson.config["allow-plugins"] = {};
      changed = true;
    }

    if (composerJson.config["allow-plugins"]["wikimedia/composer-merge-plugin"] !== true) {
      composerJson.config["allow-plugins"]["wikimedia/composer-merge-plugin"] = true;
      changed = true;
    }

    if (changed) {
      fs.writeFileSync(composerPath, `${JSON.stringify(composerJson, null, 4)}\n`, "utf8");
      ok("allow-plugins for wikimedia/composer-merge-plugin was set in composer.json.");
    } else {
      ok("allow-plugins for wikimedia/composer-merge-plugin is already set correctly.");
    }
  } catch {
    warn("Could not set allow-plugins directly in composer.json.");
  }
}

// Ensures nwidart merge-plugin/autoload composer settings are correctly configured.
async function ensureNwidartComposerMergeConfig(projectDir, packages) {
  if (!packages.has("nwidart/laravel-modules")) {
    return false;
  }

  section("Nwidart Composer Configuration");
  info("Checking Nwidart autoload and merge-plugin settings");

  const composerPath = path.join(projectDir, "composer.json");
  if (!fs.existsSync(composerPath)) {
    return false;
  }

  let composerJson;
  try {
    composerJson = JSON.parse(fs.readFileSync(composerPath, "utf8"));
  } catch {
    warn("Could not read composer.json. Skipping Nwidart autoload adjustments.");
    return false;
  }

  let changed = false;
  let removedLegacyModulesAutoload = false;
  let addedMergePluginInclude = false;

  if (
    composerJson.autoload &&
    composerJson.autoload["psr-4"] &&
    Object.prototype.hasOwnProperty.call(composerJson.autoload["psr-4"], "Modules\\")
  ) {
    delete composerJson.autoload["psr-4"]["Modules\\"];
    changed = true;
    removedLegacyModulesAutoload = true;
  }

  if (
    !composerJson.extra ||
    typeof composerJson.extra !== "object" ||
    Array.isArray(composerJson.extra)
  ) {
    composerJson.extra = {};
    changed = true;
  }

  if (
    !composerJson.extra["merge-plugin"] ||
    typeof composerJson.extra["merge-plugin"] !== "object" ||
    Array.isArray(composerJson.extra["merge-plugin"])
  ) {
    composerJson.extra["merge-plugin"] = { include: ["Modules/*/composer.json"] };
    changed = true;
    addedMergePluginInclude = true;
  } else {
    if (!Array.isArray(composerJson.extra["merge-plugin"].include)) {
      composerJson.extra["merge-plugin"].include = [];
      changed = true;
    }

    if (!composerJson.extra["merge-plugin"].include.includes("Modules/*/composer.json")) {
      composerJson.extra["merge-plugin"].include.push("Modules/*/composer.json");
      changed = true;
      addedMergePluginInclude = true;
    }
  }

  if (!changed) {
    ok("Nwidart Composer configuration is already correct.");
    return false;
  }

  fs.writeFileSync(composerPath, `${JSON.stringify(composerJson, null, 4)}\n`, "utf8");

  if (removedLegacyModulesAutoload) {
    ok('Removed legacy autoload mapping "Modules\\\\": "modules/".');
  }

  if (addedMergePluginInclude) {
    ok('Set merge-plugin.include with "Modules/*/composer.json".');
  }

  ok("Nwidart Composer configuration updated.");
  return true;
}

// Rewrites vite.config.js for nwidart module asset collection when possible.
async function ensureNwidartViteMainConfig(projectDir, packages) {
  if (!packages.has("nwidart/laravel-modules")) {
    return false;
  }

  const viteConfigPath = path.join(projectDir, "vite.config.js");
  if (!fs.existsSync(viteConfigPath)) {
    warn("vite.config.js is missing. Skipping Nwidart Vite configuration.");
    return false;
  }

  const currentConfig = fs.readFileSync(viteConfigPath, "utf8");
  if (currentConfig.includes("collectModuleAssetsPaths(")) {
    ok("vite.config.js is already prepared for Nwidart module assets.");
    return false;
  }

  const hasLaravelPlugin = currentConfig.includes("laravel-vite-plugin");
  const hasDefaultInputs = /input\s*:\s*\[[\s\S]*resources\/css\/app\.css[\s\S]*resources\/js\/app\.js[\s\S]*\]/.test(
    currentConfig,
  );

  if (!hasLaravelPlugin || !hasDefaultInputs) {
    warn("Could not automatically update vite.config.js for module assets.");
    info("Please follow Nwidart docs to switch manually to collectModuleAssetsPaths.");
    return false;
  }

  const useTailwindPlugin =
    currentConfig.includes("@tailwindcss/vite") || currentConfig.includes("tailwindcss(");
  const serverBlock = extractObjectPropertyBlock(currentConfig, "server");

  const nextConfig = [
    "import { defineConfig } from 'vite';",
    "import laravel from 'laravel-vite-plugin';",
    ...(useTailwindPlugin ? ["import tailwindcss from '@tailwindcss/vite';"] : []),
    "import collectModuleAssetsPaths from './vite-module-loader.js';",
    "",
    "async function getConfig() {",
    "    const allPaths = await collectModuleAssetsPaths(",
    "        [",
    "            'resources/css/app.css',",
    "            'resources/js/app.js',",
    "        ],",
    "        'Modules',",
    "    );",
    "",
    "    return defineConfig({",
    "        plugins: [",
    "            laravel({",
    "                input: allPaths,",
    "                refresh: true,",
    "            }),",
    ...(useTailwindPlugin ? ["            tailwindcss(),"] : []),
    "        ],",
    ...(serverBlock ? [indentLines(serverBlock, 8)] : []),
    "    });",
    "}",
    "",
    "export default getConfig();",
    "",
  ].join("\n");

  fs.writeFileSync(viteConfigPath, nextConfig, "utf8");
  ok("Updated vite.config.js for Nwidart module assets (collectModuleAssetsPaths).");
  return true;
}

// Creates modules_statuses.json based on current Modules directory contents.
async function ensureNwidartModuleStatusesFile(projectDir, packages) {
  if (!packages.has("nwidart/laravel-modules")) {
    return false;
  }

  const statusesPath = path.join(projectDir, "modules_statuses.json");
  if (fs.existsSync(statusesPath)) {
    ok("modules_statuses.json already exists.");
    return false;
  }

  const modulesDir = path.join(projectDir, "Modules");
  const statuses = {};

  if (fs.existsSync(modulesDir)) {
    const entries = fs.readdirSync(modulesDir, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.isDirectory() && !entry.name.startsWith(".")) {
        statuses[entry.name] = true;
      }
    }
  }

  fs.writeFileSync(statusesPath, `${JSON.stringify(statuses, null, 4)}\n`, "utf8");

  const moduleCount = Object.keys(statuses).length;
  if (moduleCount > 0) {
    ok(`Created modules_statuses.json (${moduleCount} modules enabled).`);
  } else {
    ok("Created modules_statuses.json (currently no modules).");
  }

  return true;
}

// Ensures the Modules directory exists for nwidart projects.
async function ensureNwidartModulesDirectory(projectDir, packages) {
  if (!packages.has("nwidart/laravel-modules")) {
    return false;
  }

  const modulesDir = path.join(projectDir, "Modules");
  if (fs.existsSync(modulesDir)) {
    ok("Modules directory already exists.");
    return false;
  }

  fs.mkdirSync(modulesDir, { recursive: true });
  ok("Created Modules directory.");
  return true;
}

// Ensures CoreModule exists and attempts Filament module integration.
async function ensureNwidartCoreModule(projectDir, packages) {
  if (!packages.has("nwidart/laravel-modules")) {
    return;
  }

  section("CoreModule Setup");

  const coreModulePath = path.join(projectDir, "Modules", "CoreModule");
  if (fs.existsSync(coreModulePath)) {
    ok("CoreModule already exists, skipping module:make CoreModule.");
  } else {
    await runArtisanIfAvailable(
      projectDir,
      "module:make",
      ["CoreModule"],
      "module:make not available, skipping.",
      { warnOnFailure: false },
    );
  }

  await runArtisanIfAvailable(
    projectDir,
    "module:filament:install",
    ["CoreModule"],
    "module:filament:install not available, skipping.",
    { warnOnFailure: false },
  );
}

// Returns a status snapshot of all nwidart setup invariants.
function getNwidartSetupStatus(projectDir) {
  const composerPath = path.join(projectDir, "composer.json");
  const viteConfigPath = path.join(projectDir, "vite.config.js");
  const statusesPath = path.join(projectDir, "modules_statuses.json");
  const modulesDir = path.join(projectDir, "Modules");

  let allowPluginEnabled = false;
  let mergeIncludeEnabled = false;
  let legacyModulesAutoloadRemoved = false;

  if (fs.existsSync(composerPath)) {
    try {
      const composerJson = JSON.parse(fs.readFileSync(composerPath, "utf8"));

      allowPluginEnabled =
        composerJson.config?.["allow-plugins"]?.["wikimedia/composer-merge-plugin"] === true;

      mergeIncludeEnabled =
        Array.isArray(composerJson.extra?.["merge-plugin"]?.include) &&
        composerJson.extra["merge-plugin"].include.includes("Modules/*/composer.json");

      legacyModulesAutoloadRemoved =
        !Object.prototype.hasOwnProperty.call(composerJson.autoload?.["psr-4"] ?? {}, "Modules\\");
    } catch {
      // keep defaults
    }
  }

  const viteConfigured =
    fs.existsSync(viteConfigPath) &&
    fs.readFileSync(viteConfigPath, "utf8").includes("collectModuleAssetsPaths(");
  const statusesFilePresent = fs.existsSync(statusesPath);
  const modulesDirectoryPresent = fs.existsSync(modulesDir);

  return {
    allowPluginEnabled,
    mergeIncludeEnabled,
    legacyModulesAutoloadRemoved,
    viteConfigured,
    statusesFilePresent,
    modulesDirectoryPresent,
  };
}

// Prints a compact nwidart setup summary and missing pieces.
function printNwidartSetupSummary(projectDir, packages) {
  if (!packages.has("nwidart/laravel-modules")) {
    return;
  }

  const status = getNwidartSetupStatus(projectDir);
  const ready =
    status.allowPluginEnabled &&
    status.mergeIncludeEnabled &&
    status.legacyModulesAutoloadRemoved &&
    status.viteConfigured &&
    status.statusesFilePresent &&
    status.modulesDirectoryPresent;

  if (ready) {
    ok("Nwidart Setup komplett (plugins + merge + vite)");
    return;
  }

  const missing = [];
  if (!status.allowPluginEnabled) {
    missing.push("allow-plugins");
  }
  if (!status.mergeIncludeEnabled) {
    missing.push("merge-plugin.include");
  }
  if (!status.legacyModulesAutoloadRemoved) {
    missing.push("autoload Modules\\");
  }
  if (!status.viteConfigured) {
    missing.push("vite collectModuleAssetsPaths");
  }
  if (!status.statusesFilePresent) {
    missing.push("modules_statuses.json");
  }
  if (!status.modulesDirectoryPresent) {
    missing.push("Modules directory");
  }

  warn(`Nwidart setup incomplete: ${missing.join(", ")}`);
}

// Runs package-specific setup commands, migrations, and optional admin creation.
async function runSetupCommands(projectDir, packages, config) {
  section("Setup Commands");

  await runCommand("php", ["artisan", "key:generate", "--force", "--no-interaction"], {
    cwd: projectDir,
    required: false,
  });

  if (packages.has("laravel/fortify")) {
    if (hasTwoFactorMigration(projectDir)) {
      info("Fortify install skipped: two-factor migration already exists.");
    } else {
      await runArtisanIfAvailable(projectDir, "fortify:install", ["--no-interaction"]);
    }
  }

  if (packages.has("filament/filament")) {
    await runCommand("php", ["artisan", "filament:install", "--panels", "--no-interaction"], {
      cwd: projectDir,
      required: true,
    });
  }

  if (packages.has("laravel/horizon")) {
    await runArtisanIfAvailable(projectDir, "horizon:install", ["--no-interaction"]);
  }

  if (packages.has("laravel/telescope")) {
    await runArtisanIfAvailable(projectDir, "telescope:install", ["--no-interaction"]);
  }

  if (packages.has("laravel/sanctum")) {
    const hasSanctumInstall = await artisanCommandExists(projectDir, "sanctum:install");
    if (hasSanctumInstall) {
      await runCommand("php", ["artisan", "sanctum:install", "--no-interaction"], {
        cwd: projectDir,
        required: false,
      });
    } else {
      await runArtisanIfAvailable(
        projectDir,
        "install:api",
        ["--no-interaction"],
        "sanctum:install not available, trying install:api.",
      );
    }
  }

  if (packages.has("laravel/passport")) {
    await runArtisanIfAvailable(projectDir, "passport:install", ["--force", "--no-interaction"]);
  }

  if (packages.has("laravel/pennant")) {
    info("Pennant installed (no separate install command required).");
  }

  if (packages.has("laravel/reverb")) {
    if (fs.existsSync(path.join(projectDir, "config", "reverb.php"))) {
      info("Reverb is already configured, skipping reverb:install.");
    } else {
      info("Reverb install may ask interactive questions.");
      await runArtisanIfAvailable(
        projectDir,
        "reverb:install",
        [],
        "reverb:install not available, skipping.",
        { warnOnFailure: false },
      );
    }
  }

  if (packages.has("laravel/pulse")) {
    await runCommand(
      "php",
      [
        "artisan",
        "vendor:publish",
        "--provider=Laravel\\Pulse\\PulseServiceProvider",
        "--force",
        "--no-interaction",
      ],
      { cwd: projectDir, required: false },
    );
  }

  if (packages.has("nwidart/laravel-modules") || packages.has("coolsam/modules")) {
    section("Modules Setup");
  }

  if (packages.has("coolsam/modules")) {
    info("Running modules:install");
    await runArtisanIfAvailable(
      projectDir,
      "modules:install",
      ["--no-interaction"],
      "modules:install not available, skipping.",
      { warnOnFailure: false },
    );

    info("Publishing modules-config");
    await runCommand(
      "php",
      ["artisan", "vendor:publish", "--tag=modules-config", "--no-interaction"],
      { cwd: projectDir, required: false, warnOnFailure: false },
    );
  }

  if (packages.has("nwidart/laravel-modules")) {
    info("Publishing Nwidart config + Vite loader");

    await runCommand(
      "php",
      [
        "artisan",
        "vendor:publish",
        "--provider=Nwidart\\Modules\\LaravelModulesServiceProvider",
        "--tag=config",
      ],
      { cwd: projectDir, required: false },
    );

    await runCommand(
      "php",
      [
        "artisan",
        "vendor:publish",
        "--provider=Nwidart\\Modules\\LaravelModulesServiceProvider",
        "--tag=vite",
      ],
      { cwd: projectDir, required: false },
    );

    await ensureNwidartModulesDirectory(projectDir, packages);
    await ensureNwidartViteMainConfig(projectDir, packages);
    await ensureNwidartModuleStatusesFile(projectDir, packages);
    await ensureNwidartCoreModule(projectDir, packages);
  }

  if (packages.has("laravel/dusk")) {
    await runArtisanIfAvailable(projectDir, "dusk:install", ["--no-interaction"]);
  }

  const removedTwoFactorMigrations = cleanupDuplicateTwoFactorMigrations(projectDir);
  if (removedTwoFactorMigrations.length > 0) {
    warn(
      `Removed duplicate two-factor migration: ${removedTwoFactorMigrations.join(", ")}`,
    );
  }

  await runCommand("php", ["artisan", "migrate", "--force", "--no-interaction"], {
    cwd: projectDir,
    required: true,
  });

  if (config.createAdmin && packages.has("filament/filament")) {
    const withPanel = await runCommand(
      "php",
      [
        "artisan",
        "make:filament-user",
        `--name=${config.admin.name}`,
        `--email=${config.admin.email}`,
        `--password=${config.admin.password}`,
        "--panel=admin",
        "--no-interaction",
      ],
      { cwd: projectDir, required: false },
    );

    if (withPanel) {
      state.createdAdmin = { ...config.admin };
    } else {
      const withoutPanel = await runCommand(
        "php",
        [
          "artisan",
          "make:filament-user",
          `--name=${config.admin.name}`,
          `--email=${config.admin.email}`,
          `--password=${config.admin.password}`,
          "--no-interaction",
        ],
        { cwd: projectDir, required: false },
      );

      if (withoutPanel) {
        state.createdAdmin = { ...config.admin };
      }
    }
  }
}

// Runs full installation workflow for new projects.
async function runInstallFlow(config, runtimeOptions = state.runtime) {
  section("Installation Plan");
  info(`Mode: ${config.mode}`);
  info(`Project: ${config.appName}`);
  info(`Path: ${config.projectPath}`);
  info(`Database: ${config.database.connection}`);
  info(`Normal packages: ${config.normalPackages.join(", ") || "-"}`);
  info(`Dev packages: ${config.devPackages.join(", ") || "-"}`);

  if (config.mode === "manual") {
    const proceed = await askYesNo("Start installation", true);
    if (!proceed) {
      throw new Error("Cancelled by user.");
    }
  }

  section("Create Project");

  const resolvedProjectPath = path.resolve(config.projectPath);
  const resolvedCwd = path.resolve(process.cwd());
  const rootPath = path.parse(resolvedProjectPath).root;

  if (resolvedProjectPath === resolvedCwd) {
    throw new Error("Safety abort: target path is the current working directory.");
  }

  if (resolvedProjectPath === rootPath) {
    throw new Error("Safety abort: target path must not be the root directory.");
  }

  if (fs.existsSync(config.projectPath)) {
    let shouldDelete = false;

    if (runtimeOptions.nonInteractive) {
      shouldDelete = Boolean(runtimeOptions.allowDeleteExisting);
      info(
        `[non-interactive] Existing path ${
          shouldDelete ? "will be replaced" : "will abort"
        }: ${config.projectPath}`,
      );
    } else {
      shouldDelete = await askYesNo(
        `Path already exists. Delete everything? (${config.projectPath})`,
        false,
      );
    }

    if (!shouldDelete) {
      throw new Error(`Cancelled: path already exists (${config.projectPath}).`);
    }

    if (runtimeOptions.backup) {
      const backupPath = backupExistingPath(config.projectPath);
      ok(`Existing path was backed up to: ${backupPath}`);
    } else {
      fs.rmSync(config.projectPath, { recursive: true, force: true });
      ok(`Deleted existing path: ${config.projectPath}`);
    }
  }

  const parentDir = path.dirname(config.projectPath);
  const projectName = path.basename(config.projectPath);
  fs.mkdirSync(parentDir, { recursive: true });

  const laravelArgs = [
    "new",
    projectName,
    `--database=${config.database.connection}`,
    "--force",
    "--no-interaction",
  ];

  if (Array.isArray(config.laravelNewFlags) && config.laravelNewFlags.length > 0) {
    laravelArgs.push(...config.laravelNewFlags);
  }

  await runCommand("laravel", laravelArgs, { cwd: parentDir, required: true });

  section("Configure .env");
  applyEnvConfig(config.projectPath, config);
  ok(".env updated");

  const packageSet = packageSetFromConfig(config);
  await ensureComposerPluginAllowList(config.projectPath, packageSet);

  section("Composer Dependencies");
  if (config.normalPackages.length > 0) {
    await runCommand("composer", ["require", ...config.normalPackages, "--no-interaction"], {
      cwd: config.projectPath,
      required: true,
    });
  }

  if (config.devPackages.length > 0) {
    await runCommand("composer", ["require", "--dev", ...config.devPackages, "--no-interaction"], {
      cwd: config.projectPath,
      required: true,
    });
  }

  if (await ensureNwidartComposerMergeConfig(config.projectPath, packageSet)) {
    await runCommand("composer", ["dump-autoload", "--no-interaction"], {
      cwd: config.projectPath,
      required: false,
    });
  }

  await runSetupCommands(config.projectPath, packageSet, config);
  printNwidartSetupSummary(config.projectPath, packageSet);

  section("Install Boost");
  info("boost:install is interactive. Please confirm settings now.");
  await runCommand("php", ["artisan", "boost:install"], { cwd: config.projectPath, required: true });

  section("Optimieren");
  await runCommand("php", ["artisan", "optimize", "--no-interaction"], {
    cwd: config.projectPath,
    required: false,
  });

  section("Frontend Build");
  await runCommand("npm", ["install"], { cwd: config.projectPath, required: true });
  await runCommand("npm", ["run", "build"], { cwd: config.projectPath, required: true });

  if (config.gitInit) {
    section("Git");
    await runCommand("git", ["init"], { cwd: config.projectPath, required: false });
  }
}

// Runs update workflow for an existing Laravel project.
async function runUpdateFlow(projectDir) {
  section("Update Mode");
  info(`Project: ${projectDir}`);

  const proceed = await askYesNo("Start update", true);
  if (!proceed) {
    throw new Error("Cancelled by user.");
  }

  const packages = readComposerPackages(projectDir);
  await ensureComposerPluginAllowList(projectDir, packages);

  if (await ensureNwidartComposerMergeConfig(projectDir, packages)) {
    await runCommand("composer", ["dump-autoload", "--no-interaction"], {
      cwd: projectDir,
      required: false,
    });
  }

  await ensureNwidartViteMainConfig(projectDir, packages);
  await ensureNwidartModulesDirectory(projectDir, packages);
  await ensureNwidartModuleStatusesFile(projectDir, packages);
  printNwidartSetupSummary(projectDir, packages);

  await runCommand("composer", ["update", "--no-interaction"], { cwd: projectDir, required: true });
  await runCommand("php", ["artisan", "migrate", "--force", "--no-interaction"], {
    cwd: projectDir,
    required: true,
  });

  if (packages.has("laravel/boost")) {
    section("Install Boost");
    info("boost:install is interactive.");
    await runCommand("php", ["artisan", "boost:install"], { cwd: projectDir, required: true });
  } else {
    warn("laravel/boost is not installed. Skipping boost:install.");
  }

  section("Optimieren");
  await runCommand("php", ["artisan", "optimize", "--no-interaction"], {
    cwd: projectDir,
    required: false,
  });

  section("Frontend Build");
  await runCommand("npm", ["install"], { cwd: projectDir, required: true });
  await runCommand("npm", ["run", "build"], { cwd: projectDir, required: true });
}

// Prints final success output including admin credentials and accumulated warnings.
function printFinalNotes(projectPath) {
  section("Done");
  ok("INSTALAR completed successfully.");
  console.log(`\n  ${color("Project path:", C.bold)} ${projectPath}`);
  console.log(`  ${color("Start:", C.bold)} ${color(`cd ${projectPath} && php artisan serve`, C.cyan)}`);

  if (state.createdAdmin) {
    console.log(`\n  ${color("Filament Admin:", C.bold + C.green)}`);
    console.log(`  Name:     ${state.createdAdmin.name}`);
    console.log(`  E-Mail:   ${state.createdAdmin.email}`);
    console.log(`  Password: ${state.createdAdmin.password}`);
  }

  if (state.warnings.length > 0) {
    console.log(`\n  ${color("Warnings:", C.bold + C.yellow)}`);
    state.warnings.forEach((entry) => console.log(`  - ${entry}`));
  }
}

// Wrapper for fs.accessSync that returns a boolean instead of throwing.
function checkAccess(targetPath, mode) {
  try {
    fs.accessSync(targetPath, mode);
    return true;
  } catch {
    return false;
  }
}

// Runs post-install health checks for key artisan commands and frontend manifest.
async function runHealthChecks(projectPath) {
  section("Health Check");

  let healthCheckFailed = false;
  const failedChecks = [];

  // Check APP_KEY is set
  const envPath = path.join(projectPath, ".env");
  if (fs.existsSync(envPath)) {
    const envContent = fs.readFileSync(envPath, "utf8");
    const appKeyMatch = envContent.match(/^APP_KEY=base64:[A-Za-z0-9+\/=]+$/m);
    if (appKeyMatch) {
      ok("APP_KEY is set");
    } else {
      warn("APP_KEY is missing - run 'php artisan key:generate'");
      healthCheckFailed = true;
      failedChecks.push("APP_KEY");
    }
  } else {
    warn(".env file not found");
    healthCheckFailed = true;
    failedChecks.push(".env");
  }

  // Check database connection
  const dbCheck = await runCommand("php", ["artisan", "db:show", "--no-interaction"], {
    cwd: projectPath,
    required: false,
    warnOnFailure: false,
  });
  if (dbCheck.exitCode !== 0) {
    warn("Database connection check failed");
    healthCheckFailed = true;
    failedChecks.push("Database");
  }

  // Check storage link
  const storageLinkPath = path.join(projectPath, "public", "storage");
  let storageLinkOk = false;
  try {
    const lstat = fs.lstatSync(storageLinkPath);
    storageLinkOk = lstat.isSymbolicLink();
  } catch {
    storageLinkOk = false;
  }
  if (storageLinkOk) {
    ok("Storage link exists");
  } else {
    warn("Storage link missing - run 'php artisan storage:link'");
    healthCheckFailed = true;
    failedChecks.push("Storage link");
  }

  // Run composer validate
  const composerValidate = await runCommand("composer", ["validate", "--no-interaction"], {
    cwd: projectPath,
    required: false,
    warnOnFailure: false,
  });
  if (composerValidate.exitCode === 0) {
    ok("Composer.json is valid");
  } else {
    warn("Composer.json validation failed");
    healthCheckFailed = true;
    failedChecks.push("Composer");
  }

  // Existing checks: about, migrate:status, route:list, Vite manifest
  await runCommand("php", ["artisan", "about", "--no-interaction"], {
    cwd: projectPath,
    required: false,
    warnOnFailure: false,
  });

  await runCommand("php", ["artisan", "migrate:status", "--no-interaction"], {
    cwd: projectPath,
    required: false,
    warnOnFailure: false,
  });

  await runCommand("php", ["artisan", "route:list", "--no-interaction"], {
    cwd: projectPath,
    required: false,
    warnOnFailure: false,
  });

  const manifestPath = path.join(projectPath, "public", "build", "manifest.json");
  if (fs.existsSync(manifestPath)) {
    ok("Vite manifest found (public/build/manifest.json)");
  } else {
    warn("Vite manifest missing: public/build/manifest.json");
    healthCheckFailed = true;
    failedChecks.push("Vite manifest");
  }

  // Ask user if they want to continue when health checks failed
  if (healthCheckFailed) {
    console.log("");
    const failedList = failedChecks.join(", ");
    fail(`Health check failed for: ${failedList}`);
    console.log("");

    const shouldContinue = await askYesNo("Do you want to continue anyway?", false);
    if (!shouldContinue) {
      fail("Installation aborted by user due to failed health checks.");
      process.exit(1);
    }
    info("Continuing despite health check failures...");
  }
}

// Verifies essential filesystem permissions and optionally starts the dev server.
async function runFinalPermissionAndServerStep(projectPath, runtimeOptions = state.runtime) {
  section("Permissions");

  const checks = [
    {
      label: "project directory",
      targetPath: projectPath,
      mode: fs.constants.R_OK | fs.constants.W_OK | fs.constants.X_OK,
      hint: "read/write/execute",
    },
    {
      label: "storage",
      targetPath: path.join(projectPath, "storage"),
      mode: fs.constants.R_OK | fs.constants.W_OK | fs.constants.X_OK,
      hint: "read/write/execute",
    },
    {
      label: "bootstrap/cache",
      targetPath: path.join(projectPath, "bootstrap", "cache"),
      mode: fs.constants.R_OK | fs.constants.W_OK | fs.constants.X_OK,
      hint: "read/write/execute",
    },
    {
      label: ".env",
      targetPath: path.join(projectPath, ".env"),
      mode: fs.constants.R_OK | fs.constants.W_OK,
      hint: "read/write",
    },
  ];

  let hasPermissionIssues = false;

  for (const check of checks) {
    if (!fs.existsSync(check.targetPath)) {
      hasPermissionIssues = true;
      warn(`${check.label} missing: ${check.targetPath}`);
      continue;
    }

    if (checkAccess(check.targetPath, check.mode)) {
      ok(`${check.label} ok (${check.hint})`);
    } else {
      hasPermissionIssues = true;
      warn(`${check.label} has insufficient permissions (${check.hint})`);
    }
  }

  if (hasPermissionIssues) {
    warn("Tip: check permissions, e.g. chmod -R ug+rw storage bootstrap/cache");
  }

  let startServer = false;
  if (runtimeOptions.nonInteractive) {
    startServer = Boolean(runtimeOptions.startServer);
    info(`[non-interactive] Start server: ${startServer ? "yes" : "no"}`);
  } else {
    startServer = await askYesNo("Start server now? (composer run dev)", false);
  }

  if (!startServer) {
    return;
  }

  section("Server Start");
  info(`Starting composer run dev in ${projectPath}`);
  await runCommand("composer", ["run", "dev"], { cwd: projectPath, required: false });
}

// Executes all final post-install steps in order.
async function finalizeProject(projectPath, runtimeOptions = state.runtime) {
  printFinalNotes(projectPath);
  await runHealthChecks(projectPath);
  await runFinalPermissionAndServerStep(projectPath, runtimeOptions);
}

// Prints Node-phase usage help.
function printNodeUsage() {
  console.log("INSTALAR Installer");
  console.log("");
  console.log("Usage:");
  console.log("  ./instalar.sh");
  console.log("  ./instalar.sh --help");
  console.log("  ./instalar.sh --non-interactive --config instalar.json");
  console.log("");
  console.log("Options:");
  console.log("  --config <file>         JSON configuration file (default: ./instalar.json)");
  console.log("  --non-interactive       No prompts, uses defaults/config");
  console.log("  --mode <auto|manual|update>");
  console.log("  --backup                Backup existing target directory before replacing");
  console.log("  --admin-generate        Generate admin password");
  console.log("  --allow-delete-existing Allow replacing in non-interactive mode");
  console.log("  --start-server          Automatically run composer run dev at the end");
}

// Node-phase main entrypoint.
// Resolves runtime mode, dispatches to install/update flow, then finalizes.
async function main() {
  const args = process.argv.slice(2);
  const cliOptions = parseCliArgs(args);

  if (cliOptions.help) {
    printNodeUsage();
    return;
  }

  let loadedConfig = {};
  let resolvedConfigPath = null;

  if (cliOptions.configPath) {
    const loaded = loadInstallerConfig(cliOptions.configPath);
    if (loaded.config === null) {
      throw new Error(`Configuration file not found: ${loaded.path}`);
    }

    loadedConfig = loaded.config;
    resolvedConfigPath = loaded.path;
    info(`Loaded configuration: ${resolvedConfigPath}`);
  } else {
    const defaultConfigPath = path.resolve(process.cwd(), "instalar.json");
    if (fs.existsSync(defaultConfigPath)) {
      const loaded = loadInstallerConfig(defaultConfigPath);
      loadedConfig = loaded.config || {};
      resolvedConfigPath = loaded.path;
      info(`Loaded configuration: ${resolvedConfigPath}`);
    }
  }

  state.runtime = resolveRuntime(cliOptions, loadedConfig, resolvedConfigPath);

  if (!state.runtime.nonInteractive && !process.stdin.isTTY) {
    throw new Error(
      "No interactive terminal detected. Use --non-interactive for unattended runs.",
    );
  }

  const cwd = process.cwd();
  const hasLaravelProject = isLaravelProject(cwd);
  let mode = state.runtime.mode;

  if (!mode && state.runtime.nonInteractive) {
    mode = hasLaravelProject ? "update" : "auto";
    info(`[non-interactive] No mode set, using: ${mode}`);
  }

  if (mode === "update") {
    if (!hasLaravelProject) {
      throw new Error("Update mode requires a Laravel project in the current directory.");
    }

    await runUpdateFlow(cwd);
    await finalizeProject(cwd, state.runtime);
    return;
  }

  if (mode === "auto") {
    const config = await collectAutoConfig(getModePreset("auto"));
    await runInstallFlow(config, state.runtime);
    await finalizeProject(config.projectPath, state.runtime);
    return;
  }

  if (mode === "manual") {
    const config = await collectManualConfig(getModePreset("manual"));
    await runInstallFlow(config, state.runtime);
    await finalizeProject(config.projectPath, state.runtime);
    return;
  }

  if (hasLaravelProject) {
    const action = await askChoice(
      "Laravel project detected in current directory",
      ["Update existing project", "New installation (Auto)", "New installation (Manual)"],
      0,
    );

    if (action === 0) {
      await runUpdateFlow(cwd);
      await finalizeProject(cwd, state.runtime);
      return;
    }

    if (action === 1) {
      const config = await collectAutoConfig(getModePreset("auto"));
      await runInstallFlow(config, state.runtime);
      await finalizeProject(config.projectPath, state.runtime);
      return;
    }

    const config = await collectManualConfig(getModePreset("manual"));
    await runInstallFlow(config, state.runtime);
    await finalizeProject(config.projectPath, state.runtime);
    return;
  }

  const modeChoice = await askChoice("Choose mode", ["Automatic", "Manual"], 0);
  if (modeChoice === 0) {
    const config = await collectAutoConfig(getModePreset("auto"));
    await runInstallFlow(config, state.runtime);
    await finalizeProject(config.projectPath, state.runtime);
    return;
  }

  const config = await collectManualConfig(getModePreset("manual"));
  await runInstallFlow(config, state.runtime);
  await finalizeProject(config.projectPath, state.runtime);
}

// Global top-level error handler for the Node phase.
main().catch((error) => {
  section("Error");
  fail(error.message || String(error));
  process.exitCode = 1;
});
NODE

# Route Node stdin to /dev/tty when available so prompts still work after curl|bash piping.
NODE_STDIN="/dev/stdin"
if (( BASH_HAS_TTY == 1 )); then
  NODE_STDIN="/dev/tty"
fi

# Execute embedded Node phase with original CLI args.
if node "${NODE_TMP}" "$@" < "${NODE_STDIN}"; then
  exit 0
else
  exit $?
fi
