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

SCRIPT_VERSION="0.1.18"
SCRIPT_CODENAME="Rosie"

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
  LIGHT_BLUE=$'\033[38;5;117m' # Light blue brand accent
  CYAN=$'\033[36m'    # Cyan (info)
  WHITE=$'\033[37m'   # White
else
  NC=""
  BOLD=""
  DIM=""
  RED=""
  GREEN=""
  YELLOW=""
  LIGHT_BLUE=""
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
declare -A DEP_MIN_VERSION=(
  [php]="8.5.0"
  [composer]="2.7.0"
  [laravel]="5.0.0"
  [node]="20.0.0"
  [npm]="10.0.0"
)
declare -a DEPS_WITH_UPDATES=()                                # List of deps with available updates
declare -A DEP_UPDATE_CURRENT=()                               # Maps dep name -> current version
declare -A DEP_UPDATE_TARGET=()                                # Maps dep name -> target version

# Flags for script behavior
BASH_NON_INTERACTIVE=0      # Set to 1 to skip all prompts (--non-interactive)
BASH_APPLY_DEP_UPDATES=0   # Set to 1 to auto-apply dependency updates (--deps-update)
BASH_PRINT_PLAN=0           # Set to 1 to print the resolved installation/update plan (--dry-run/--print-plan)
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
  local title line_width line
  title="${1^^}"
  line_width=$(( 68 - ${#title} - 4 ))
  if (( line_width < 10 )); then
    line_width=10
  fi
  line="$(printf '%*s' "${line_width}" '' | tr ' ' '─')"
  printf '\n%b\n' "$(paint "${BOLD}${LIGHT_BLUE}" "╭─ ${title} ${line}")"
}

# The framed large logo needs at least 80 columns to render without wrapping.
INSTALAR_LOGO_MIN_WIDTH=80
INSTALAR_LOGO_CONTENT_WIDTH=71
INSTALAR_LOGO_FRAME_WIDTH=73
declare -a INSTALAR_LOGO_LINES=(
  "  ██╗ ███╗   ██╗ ███████╗ ████████╗  █████╗  ██╗       █████╗  ██████╗ "
  "  ██║ ████╗  ██║ ██╔════╝ ╚══██╔══╝ ██╔══██╗ ██║      ██╔══██╗ ██╔══██╗"
  "  ██║ ██╔██╗ ██║ ███████╗    ██║    ███████║ ██║      ███████║ ██████╔╝"
  "  ██║ ██║╚██╗██║ ╚════██║    ██║    ██╔══██║ ██║      ██╔══██║ ██╔══██╗"
  "  ██║ ██║ ╚████║ ███████║    ██║    ██║  ██║ ███████╗ ██║  ██║ ██║  ██║"
  "  ╚═╝ ╚═╝  ╚═══╝ ╚══════╝    ╚═╝    ╚═╝  ╚═╝ ╚══════╝ ╚═╝  ╚═╝ ╚═╝  ╚═╝"
)

# Returns the current terminal width when it can be detected reliably.
get_terminal_width() {
  if [[ "${COLUMNS:-}" =~ ^[0-9]+$ ]] && (( COLUMNS > 0 )); then
    printf '%s\n' "${COLUMNS}"
    return 0
  fi

  if command -v tput >/dev/null 2>&1; then
    local width=""
    width="$(tput cols 2>/dev/null || true)"
    if [[ "${width}" =~ ^[0-9]+$ ]] && (( width > 0 )); then
      printf '%s\n' "${width}"
      return 0
    fi
  fi

  return 1
}

# Prints the compact brand header used when the terminal is too narrow for the large logo.
print_compact_brand_header() {
  printf '%b\n' "$(paint "${BOLD}${LIGHT_BLUE}" "INSTALAR v${SCRIPT_VERSION} (${SCRIPT_CODENAME})")"
  printf '%b\n' "$(paint "${LIGHT_BLUE}" "Laravel setup toolkit")"
}

# Prints a single framed header row with consistent inner padding.
print_brand_frame_line() {
  printf '%b\n' "$(paint "${BOLD}${LIGHT_BLUE}" "$(printf '│ %-*s │' "${INSTALAR_LOGO_CONTENT_WIDTH}" "$1")")"
}

# Prints the approved large INSTALAR logo for wide terminals.
print_large_brand_header() {
  local logo_line horizontal_border
  horizontal_border="$(printf '%*s' "${INSTALAR_LOGO_FRAME_WIDTH}" '')"
  horizontal_border="${horizontal_border// /─}"

  printf '%b\n' "$(paint "${BOLD}${LIGHT_BLUE}" "┌${horizontal_border}┐")"
  for logo_line in "${INSTALAR_LOGO_LINES[@]}"; do
    printf '%b\n' "$(paint "${BOLD}${LIGHT_BLUE}" "│ ${logo_line} │")"
  done

  printf '%b\n' "$(paint "${BOLD}${LIGHT_BLUE}" "$(printf '│ %*s │' "${INSTALAR_LOGO_CONTENT_WIDTH}" '')")"
  print_brand_frame_line "                Laravel setup toolkit"
  printf '%b\n' "$(paint "${DIM}${LIGHT_BLUE}" "$(printf '│ %-*s │' "${INSTALAR_LOGO_CONTENT_WIDTH}" "                v${SCRIPT_VERSION} (${SCRIPT_CODENAME})")")"
  printf '%b\n' "$(paint "${BOLD}${LIGHT_BLUE}" "└${horizontal_border}┘")"
}

# Prints the best-fitting brand header for the current terminal width.
print_brand_header() {
  local width=""

  if width="$(get_terminal_width)"; then
    if (( width < INSTALAR_LOGO_MIN_WIDTH )); then
      print_compact_brand_header
      return 0
    fi
  fi

  print_large_brand_header
}

# Prints the INSTALAR startup banner.
banner() {
  clear 2>/dev/null || true
  print_brand_header
  printf '%b\n' "$(paint "${DIM}" "Modern terminal setup, update, and diagnostics for Laravel + Filament")"
  printf '%b\n' "$(paint "${DIM}" "Choose a mode, review the plan, then let INSTALAR handle the heavy lifting.")"
  printf '%b\n' "$(paint "${DIM}" "Dependency checks run first, then INSTALAR hands over to the guided runtime.")"
}

# =============================================================================
# Help & Usage
# =============================================================================

# Prints the command-line help text
print_usage() {
  print_brand_header
  cat <<EOF
Modern terminal setup, update, and diagnostics for Laravel + Filament.
Pick the mode that matches the job, review the plan, then run with confidence.

Usage:
  ./instalar.sh
  ./instalar.sh --help
  ./instalar.sh --non-interactive --config instalar.json

Start here:
  manual                  Recommended for first runs and custom stacks
  auto                    Fastest path to a ready project
  update                  Refresh the current Laravel project
  doctor                  Inspect the current Laravel project safely

Modes:
  auto                    Create a new Laravel + Filament project with opinionated defaults
  manual                  Guided step-by-step project setup
  update                  Update the Laravel project in the current directory
  doctor                  Diagnose the Laravel project in the current directory

Run controls:
  --mode <auto|manual|update|doctor>
  --config <file>         Path to JSON configuration (Node phase)
  --dry-run               Resolve input, print the plan, and exit without modifying files
  --print-plan            Legacy alias for --dry-run
  --log-file <path>       Write installer output to a plain-text log file
  --display-command-output
                          Show command stdout/stderr while installer steps run
  --display-info          Alias for --display-command-output
  --preset <name>         Package preset: minimal, standard, or full
  --upgrade-dependencies  Use composer update in update mode
  --skip-boost-install    Skip interactive boost:install step
  --backup                Backup existing target directory before replacing
  --start-server          Automatically run composer run dev at the end
  --verbose               Enable verbose output
  --debug                 Enable debug mode (shows all commands)

Automation:
  --non-interactive       No prompts, use defaults/config
  --admin-generate        Generate admin password instead of "password"
  --continue-on-health-check-failure
                          Continue unattended runs even when final health checks fail
  --deps-update           Apply dependency updates in Bash phase

Safety:
  --allow-delete-existing Replace existing target directories in non-interactive mode
  --allow-delete-any-existing
                          Also allow replacing generic or git-managed directories

Examples:
  ./instalar.sh --mode manual
  ./instalar.sh --mode auto --non-interactive --config ./instalar.json
  ./instalar.sh --mode doctor --log-file ./doctor.log
  ./instalar.sh --mode update --dry-run
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
      y|yes)
        return 0
        ;;
      n|no)
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
    raw="unknown version"
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
  value="$(extract_semver "${value}")"
  printf '%s' "${value}"
}

# Extracts the first semantic version-like token from arbitrary version output.
# Args:
#   $1 - Raw version string
# Returns: Normalized x.y.z version string or empty output if no version is found
extract_semver() {
  local value="$1"
  local version=""

  version="$(printf '%s\n' "${value}" | grep -Eo '[0-9]+(\.[0-9]+){1,2}' | head -n 1 || true)"
  if [[ -z "${version}" ]]; then
    return 0
  fi

  local first="" second="" third=""
  IFS='.' read -r first second third <<< "${version}"
  second="${second:-0}"
  third="${third:-0}"
  printf '%s.%s.%s' "${first}" "${second}" "${third}"
}

# Returns success when the current version is greater than or equal to the minimum version.
# Args:
#   $1 - Current version
#   $2 - Minimum required version
version_at_least() {
  local current="$1"
  local minimum="$2"

  if [[ -z "${current}" || -z "${minimum}" ]]; then
    return 1
  fi

  [[ "$(printf '%s\n%s\n' "${minimum}" "${current}" | sort -V | head -n 1)" == "${minimum}" ]]
}

# Validates detected dependency versions against the installer's minimum requirements.
check_minimum_dependency_versions() {
  local dep
  local failures=0

  for dep in "${DEPS[@]}"; do
    if (( DEP_AVAILABLE["${dep}"] == 0 )); then
      continue
    fi

    local minimum_version="${DEP_MIN_VERSION[$dep]:-}"
    if [[ -z "${minimum_version}" ]]; then
      continue
    fi

    local current_version=""
    current_version="$(extract_semver "${DEP_VERSION[$dep]}")"

    if version_at_least "${current_version}" "${minimum_version}"; then
      continue
    fi

    fail "Dependency version too old: ${dep} ${current_version:-unknown} found, need >= ${minimum_version}."
    failures=1
  done

  return "${failures}"
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
  # shellcheck disable=SC2016
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
  # shellcheck disable=SC2016
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

  printf '\n  %b\n' "$(paint "${BOLD}${WHITE}" "Available Updates")"
  printf '  %b %b|%b %b %b|%b %b\n' \
    "$(paint "${CYAN}" "$(printf "%-${dep_width}s" "Dependency")")" \
    "${DIM}" "${NC}" \
    "$(paint "${WHITE}" "$(printf "%-${current_width}s" "Current")")" \
    "${DIM}" "${NC}" \
    "$(paint "${GREEN}" "Target")"

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
      ok "Updated: ${dep} (${DEP_UPDATE_CURRENT[$dep]} -> ${DEP_UPDATE_TARGET[$dep]})"
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

  if (( BASH_PRINT_PLAN == 1 )); then
    if (( DEP_AVAILABLE["node"] == 0 )); then
      fail "Plan preview requires node to be installed."
      exit 1
    fi

    for dep in "${DEPS[@]}"; do
      if [[ "${dep}" == "node" ]]; then
        continue
      fi

      if (( DEP_AVAILABLE["${dep}"] == 0 )); then
        warn "Plan preview: dependency installation skipped for ${dep}."
      fi
    done

    if ! check_minimum_dependency_versions; then
      exit 1
    fi

    ok "Dependency inspection complete. Continuing with plan preview."
    return 0
  fi

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

  if ! check_minimum_dependency_versions; then
    exit 1
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
      --dry-run|--print-plan)
        BASH_PRINT_PLAN=1
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

  if (( BASH_VERBOSE == 1 )); then
    info "Verbose Bash output enabled."
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
# shellcheck disable=SC2317
cleanup_node_tmp() {
  rm -f "${NODE_TMP}"
}
trap cleanup_node_tmp EXIT

# Write the embedded Node.js script to temp file and execute it
cat > "${NODE_TMP}" <<'NODE'
"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const crypto = require("node:crypto");
const { spawn } = require("node:child_process");
const readline = require("node:readline/promises");
const readlineCore = require("node:readline");
const SCRIPT_VERSION = process.env.INSTALAR_SCRIPT_VERSION || "0.0.0";
const SCRIPT_CODENAME = process.env.INSTALAR_SCRIPT_CODENAME || "Unknown";

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
  {
    id: "fortify",
    title: "Fortify Auth Backend",
    category: "Auth",
    summary: "Headless login, reset, 2FA, and auth flows.",
    normal: ["laravel/fortify"],
  },
  {
    id: "ai",
    title: "Laravel AI SDK",
    category: "AI",
    summary: "Chat, completions, tools, and model providers.",
    normal: ["laravel/ai"],
  },
  {
    id: "horizon",
    title: "Horizon Queue Dashboard",
    category: "Ops",
    summary: "Queue monitoring and worker visibility.",
    normal: ["laravel/horizon"],
  },
  {
    id: "pulse",
    title: "Pulse Monitoring",
    category: "Ops",
    summary: "Application metrics and performance dashboards.",
    normal: ["laravel/pulse"],
  },
  {
    id: "socialite",
    title: "Socialite OAuth",
    category: "Auth",
    summary: "OAuth logins for GitHub, Google, and others.",
    normal: ["laravel/socialite"],
  },
  {
    id: "flux",
    title: "Livewire Flux UI",
    category: "UI",
    summary: "Flux component library for Livewire interfaces.",
    normal: ["livewire/flux"],
  },
  {
    id: "telescope",
    title: "Telescope Debug Assistant",
    category: "Dev",
    summary: "Request, job, exception, and query inspection.",
    normal: ["laravel/telescope"],
  },
  {
    id: "pail",
    title: "Pail Log Tail",
    category: "Dev",
    summary: "Developer-friendly Laravel log tailing.",
    normal: ["laravel/pail"],
  },
  {
    id: "sanctum",
    title: "Sanctum API Tokens",
    category: "Auth",
    summary: "API token and SPA authentication support.",
    normal: ["laravel/sanctum"],
  },
  {
    id: "passport",
    title: "Passport OAuth2 Server",
    category: "Auth",
    summary: "Full OAuth2 authorization server.",
    normal: ["laravel/passport"],
  },
  {
    id: "pennant",
    title: "Pennant Feature Flags",
    category: "Ops",
    summary: "Feature flagging and rollout controls.",
    normal: ["laravel/pennant"],
  },
  {
    id: "reverb",
    title: "Reverb WebSockets",
    category: "Realtime",
    summary: "First-party WebSocket server for broadcasting.",
    normal: ["laravel/reverb"],
  },
  {
    id: "spatie_permission",
    title: "Spatie Permission",
    category: "Auth",
    summary: "Roles and permissions management.",
    normal: ["spatie/laravel-permission"],
  },
  {
    id: "spatie_activitylog",
    title: "Spatie Activitylog",
    category: "Ops",
    summary: "Track who changed what in your app.",
    normal: ["spatie/laravel-activitylog"],
  },
  {
    id: "spatie_medialibrary",
    title: "Spatie Medialibrary",
    category: "Files",
    summary: "Attach, transform, and manage media files.",
    normal: ["spatie/laravel-medialibrary"],
  },
  {
    id: "spatie_health",
    title: "Spatie Health",
    category: "Ops",
    summary: "Health checks and status reporting.",
    normal: ["spatie/laravel-health"],
  },
  {
    id: "modules_bundle",
    title: "Modules Bundle (nwidart + coolsam)",
    category: "Architecture",
    summary: "Modular monolith tooling and module helpers.",
    normal: ["nwidart/laravel-modules", "coolsam/modules"],
  },
  {
    id: "dusk",
    title: "Dusk (dev)",
    category: "Testing",
    summary: "Browser automation for end-to-end tests.",
    dev: ["laravel/dusk"],
  },
  {
    id: "debugbar",
    title: "Debugbar (dev)",
    category: "Dev",
    summary: "Debug toolbar for requests and queries.",
    dev: ["barryvdh/laravel-debugbar"],
  },
  {
    id: "excel",
    title: "Laravel Excel",
    category: "Data",
    summary: "Excel and CSV import/export tooling.",
    normal: ["maatwebsite/excel"],
  },
  {
    id: "ide_helper",
    title: "Laravel IDE Helper",
    category: "Dev",
    summary: "Generate IDE metadata and helper files.",
    dev: ["barryvdh/laravel-ide-helper"],
  },
  {
    id: "migration_generator",
    title: "Migration Generator",
    category: "Dev",
    summary: "Generate migrations from existing database schemas.",
    dev: ["kitloong/laravel-migrations-generator"],
  },
  {
    id: "model_types",
    title: "Spatie Model Types",
    category: "Domain",
    summary: "Model state classes and transitions.",
    normal: ["spatie/laravel-model-states"],
  },
  {
    id: "laravel_breadcrumbs",
    title: "Breadcrumbs",
    category: "UI",
    summary: "Breadcrumb generation for navigation trails.",
    normal: ["davejamesmiller/laravel-breadcrumbs"],
  },
  {
    id: "flare",
    title: "Flare Error Tracking",
    category: "Ops",
    summary: "Improved local exception pages and reporting helpers.",
    normal: ["spatie/laravel-ignition"],
  },
];

const PACKAGE_PRESETS = [
  {
    id: "minimal",
    title: "Minimal",
    description: "Lean starter with Filament and Boost only.",
    optionalPackageIds: [],
  },
  {
    id: "standard",
    title: "Standard",
    description: "Recommended starter with authentication and AI tooling.",
    optionalPackageIds: ["fortify", "ai"],
  },
  {
    id: "full",
    title: "Full",
    description: "Broader stack with auth, monitoring, API, and DX helpers.",
    optionalPackageIds: [
      "fortify",
      "ai",
      "flux",
      "horizon",
      "pulse",
      "telescope",
      "pail",
      "sanctum",
      "spatie_permission",
      "spatie_activitylog",
      "debugbar",
    ],
  },
];

// Shared runtime state for warnings, generated admin credentials, and resolved options.
const state = {
  warnings: [],
  finalWarnings: [],
  createdAdmin: null,
  boostInstallSkipped: false,
  runtime: {
    nonInteractive: false,
    printPlan: false,
    preset: "standard",
    backup: false,
    adminGenerate: false,
    allowDeleteExisting: false,
    allowDeleteAnyExisting: false,
    upgradeDependencies: false,
    displayCommandOutput: false,
    logFile: null,
    logFileWriteFailed: false,
    skipBoostInstall: false,
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

function stripAnsi(value) {
  return String(value).replace(/\x1B\[[0-9;?]*[ -/]*[@-~]/g, "");
}

function terminalStringWidth(value) {
  return [...stripAnsi(value)].length;
}

function countRenderedTerminalRows(lines, columns = 80) {
  const safeColumns = Number.isInteger(columns) && columns > 0 ? columns : 80;

  return lines.reduce((total, line) => {
    const width = terminalStringWidth(line);
    return total + Math.max(1, Math.ceil(width / safeColumns));
  }, 0);
}

function countRenderedCursorRows(lines, columns = 80) {
  return Math.max(0, countRenderedTerminalRows(lines, columns) - 1);
}

function appendToRuntimeLog(text) {
  if (!state.runtime.logFile) {
    return;
  }

  try {
    fs.appendFileSync(state.runtime.logFile, stripAnsi(text), "utf8");
  } catch (error) {
    if (!state.runtime.logFileWriteFailed) {
      state.runtime.logFileWriteFailed = true;
      process.stderr.write(
        `  [WARN] Failed to write installer log file ${state.runtime.logFile}: ${error.message}\n`,
      );
    }
  }
}

function initializeRuntimeLog() {
  if (!state.runtime.logFile) {
    return;
  }

  state.runtime.logFileWriteFailed = false;
  fs.mkdirSync(path.dirname(state.runtime.logFile), { recursive: true });
  fs.writeFileSync(
    state.runtime.logFile,
    [
      `INSTALAR ${SCRIPT_VERSION} (${SCRIPT_CODENAME})`,
      `Started: ${new Date().toISOString()}`,
      `Working directory: ${process.cwd()}`,
      "",
    ].join("\n"),
    "utf8",
  );
}

// Prints an informational message.
function info(message) {
  console.log(`  ${color("[INFO]", C.cyan)} ${message}`);
  appendToRuntimeLog(`  [INFO] ${message}\n`);
}

// Prints a success message.
function ok(message) {
  console.log(`  ${color("[ OK ]", C.green)} ${message}`);
  appendToRuntimeLog(`  [ OK ] ${message}\n`);
}

// Prints a warning message and keeps it in the transient warning log.
function warn(message) {
  state.warnings.push(message);
  console.log(`  ${color("[WARN]", C.yellow)} ${message}`);
  appendToRuntimeLog(`  [WARN] ${message}\n`);
}

// Records a warning for the final completion summary without printing it again.
function recordFinalWarning(message) {
  if (!state.finalWarnings.includes(message)) {
    state.finalWarnings.push(message);
  }
}

// Prints a warning message and records it for the final completion summary.
function warnFinal(message) {
  warn(message);
  recordFinalWarning(message);
}

// Prints an error message.
function fail(message) {
  console.log(`  ${color("[ERR ]", C.red)} ${message}`);
  appendToRuntimeLog(`  [ERR ] ${message}\n`);
}

// Prints a verbose message when --verbose flag is set.
function verbose(message) {
  if (state.runtime.verbose || state.runtime.debug) {
    console.log(color(`  [VERBOSE] ${message}`, C.dim));
    appendToRuntimeLog(`  [VERBOSE] ${message}\n`);
  }
}

// Prints a debug message when --debug flag is set.
function debug(message) {
  if (state.runtime.debug) {
    console.log(color(`  [DEBUG] ${message}`, C.gray));
    appendToRuntimeLog(`  [DEBUG] ${message}\n`);
  }
}

function resetRunState() {
  state.warnings = [];
  state.finalWarnings = [];
  state.createdAdmin = null;
  state.boostInstallSkipped = false;
}

function buildProgressMeter(current, total, width = 18) {
  const safeTotal = Math.max(1, Number(total) || 1);
  const safeCurrent = Math.min(safeTotal, Math.max(0, Number(current) || 0));
  const safeWidth = Math.max(6, Number(width) || 18);
  const filled = Math.round((safeCurrent / safeTotal) * safeWidth);
  return `${"█".repeat(filled)}${"░".repeat(Math.max(0, safeWidth - filled))}`;
}

// Prints a visual section heading.
function section(title) {
  const label = String(title).toUpperCase();
  const line = "─".repeat(Math.max(10, 64 - label.length - 4));
  console.log("");
  console.log(color(`  ╭─ ${label} ${line}`, C.bold + C.cyan));
  appendToRuntimeLog(`\n${title}\n`);
}

// Prints a compact subsection heading used inside plans and summaries.
function subsection(title) {
  console.log("");
  console.log(`  ${color("├─", C.dim + C.cyan)} ${color(title, C.bold + C.white)}`);
  appendToRuntimeLog(`\n  ${title}\n`);
}

// Writes a plain detail line without the heavier [INFO] prefix.
function detail(message = "") {
  const prefix = color("│", C.dim + C.cyan);
  if (message === "") {
    console.log(`  ${prefix}`);
  } else {
    console.log(`  ${prefix} ${message}`);
  }
  appendToRuntimeLog(`  ${stripAnsi(message)}\n`);
}

// Writes a compact key/value row for grouped plan and summary output.
function printKeyValueRow(label, value, options = {}) {
  const { labelWidth = 22 } = options;
  const normalizedValue =
    value === undefined || value === null || value === "" ? "-" : String(value);
  detail(`${`${label}:`.padEnd(labelWidth)} ${normalizedValue}`);
}

// Prints a grouped review section from a list of [label, value] pairs.
function printReviewSection(title, entries = []) {
  subsection(title);
  entries.forEach(([label, value]) => printKeyValueRow(label, value));
}

// Prints a compact list with a heading for plans, summaries, and doctor output.
function printBulletSection(title, items = [], emptyLabel = "-") {
  subsection(title);
  if (!Array.isArray(items) || items.length === 0) {
    detail(emptyLabel);
    return;
  }

  items.forEach((item) => detail(`- ${item}`));
}

function uniqueList(values = []) {
  return [...new Set(values.filter((value) => value !== undefined && value !== null && value !== ""))];
}

function artisanCommandLabel(args = []) {
  if (!Array.isArray(args) || args[0] !== "artisan") {
    return "";
  }

  return args
    .slice(1)
    .filter((arg) => typeof arg === "string" && !arg.startsWith("-"))
    .join(" ")
    .trim();
}

function buildCommandFailureSummary(command, args, options = {}) {
  const cwd = options.cwd || process.cwd();
  const exitCode = options.exitCode || 1;
  const displayCommand =
    options.displayCommand || formatCommandForDisplay(command, args, options.redactedValues || []);
  const summary = {
    title: "Command Failure",
    details: [
      ["Failed step", "External command"],
      ["Command", displayCommand],
      ["Working directory", cwd],
      ["Exit code", String(exitCode)],
    ],
    nextSteps: uniqueList([`cd ${cwd}`, displayCommand]),
  };

  if (command === "composer") {
    const composerAction = args[0] || "command";
    summary.title = "Composer Failure";
    summary.details[0] = [
      "Failed step",
      composerAction === "require"
        ? "Composer package install"
        : composerAction === "update"
          ? "Composer dependency update"
          : composerAction === "dump-autoload"
            ? "Composer autoload refresh"
            : "Composer command",
    ];
    summary.nextSteps = uniqueList([
      ...summary.nextSteps,
      "composer validate",
      composerAction === "require" || composerAction === "update" || composerAction === "install"
        ? "composer diagnose"
        : "",
    ]);
    return summary;
  }

  if (command === "npm") {
    const npmAction = args[0] || "command";
    summary.title = "npm Failure";
    summary.details[0] = [
      "Failed step",
      npmAction === "install"
        ? "Frontend dependency install"
        : npmAction === "run" && args[1] === "build"
          ? "Frontend asset build"
          : "npm command",
    ];
    summary.nextSteps = uniqueList([
      ...summary.nextSteps,
      npmAction === "install" ? "npm install" : "",
      npmAction === "run" && args[1] === "build" ? "npm install" : "",
      npmAction === "run" && args[1] === "build" ? "npm run build" : "",
    ]);
    return summary;
  }

  if (command === "php" && Array.isArray(args) && args[0] === "artisan") {
    const artisanLabel = artisanCommandLabel(args) || "artisan command";
    summary.title = "Artisan Failure";
    summary.details[0] = ["Failed step", `Artisan ${artisanLabel}`];
    summary.nextSteps = uniqueList([
      ...summary.nextSteps,
      `php artisan ${artisanLabel}`,
      artisanLabel === "optimize" || artisanLabel === "optimize:clear"
        ? ""
        : "php artisan optimize:clear && php artisan optimize",
    ]);
    return summary;
  }

  return summary;
}

function buildPermissionFailureSummary(projectPath, permissionReport) {
  const failedChecks = Array.isArray(permissionReport?.failedChecks)
    ? permissionReport.failedChecks
    : [];

  return {
    title: "Permission Attention Needed",
    details: [
      ["Project", projectPath],
      ["Failed checks", failedChecks.join(", ") || "-"],
    ],
    nextSteps: uniqueList([
      `cd ${projectPath}`,
      failedChecks.includes("storage") || failedChecks.includes("bootstrap/cache")
        ? "chmod -R ug+rw storage bootstrap/cache"
        : "",
      failedChecks.includes(".env") ? "chmod ug+rw .env" : "",
      "Verify project ownership and group permissions.",
    ]),
  };
}

function resolveUpdateDependencyStrategy(runtimeOptions = state.runtime) {
  if (runtimeOptions.upgradeDependencies) {
    return {
      label: "update (--upgrade-dependencies)",
      command: "composer",
      args: ["update", "--no-interaction"],
    };
  }

  return {
    label: "install (lockfile-safe)",
    command: "composer",
    args: ["install", "--no-interaction"],
  };
}

function printFailureSummary(summary) {
  if (!summary) {
    return;
  }

  subsection(summary.title);
  (summary.details || []).forEach(([label, value]) => printKeyValueRow(label, value));

  if (Array.isArray(summary.nextSteps) && summary.nextSteps.length > 0) {
    detail("Next steps:");
    summary.nextSteps.forEach((step) => detail(`- ${step}`));
  }
}

function getModeDefinition(modeId) {
  return INSTALLER_MODE_DEFINITIONS.find((mode) => mode.id === modeId) || null;
}

function printModeIntro(modeId) {
  const definition = getModeDefinition(modeId);
  if (!definition) {
    return;
  }

  section(definition.heading);
  detail(definition.introLead);
  detail(definition.introHint);
}

// Prints the current guided step in manual mode.
function printStepCard(step, total, title, description = "") {
  section(`Step ${step}/${total} | ${title}`);
  if (description) {
    detail(description);
  }
  detail(`Progress: ${buildProgressMeter(step, total)} ${step}/${total}`);
}

const INSTALLER_MODE_DEFINITIONS = [
  {
    id: "auto",
    description: "Create a new Laravel + Filament project with opinionated defaults",
    startHere: "Fastest path to a ready project",
    heading: "Auto Mode",
    introLead: "Fastest route to a ready Laravel + Filament project.",
    introHint: "Choose a project name, confirm a preset, and review the run before files change.",
  },
  {
    id: "manual",
    description: "Guided step-by-step project setup",
    startHere: "Recommended for first runs and custom stacks",
    heading: "Manual Mode",
    introLead: "Full-control setup with guided decisions at every stage.",
    introHint: "Work through the steps, review the final run, and start only when everything looks right.",
  },
  {
    id: "update",
    description: "Update the Laravel project in the current directory",
    startHere: "Refresh the current Laravel project",
    heading: "Update Mode",
    introLead: "Refresh the current project with a clear run summary before anything executes.",
    introHint: "Dependency, migration, optimization, and frontend steps are all previewed first.",
  },
  {
    id: "doctor",
    description: "Diagnose the Laravel project in the current directory",
    startHere: "Inspect the current Laravel project safely",
    heading: "Doctor Mode",
    introLead: "Safe diagnostics for the current Laravel project.",
    introHint: "Doctor mode reports health and permission issues first, then offers only narrow interactive repairs.",
  },
];

const RUNTIME_OPTION_DEFINITIONS = [
  {
    key: "help",
    kind: "boolean",
    defaultValue: false,
    cliFlags: ["-h", "--help"],
  },
  {
    key: "nonInteractive",
    kind: "boolean",
    defaultValue: false,
    cliFlags: ["--non-interactive", "-y", "--yes"],
    configKey: "nonInteractive",
    helpGroup: "automation",
    helpLines: [["--non-interactive", "No prompts, uses defaults/config"]],
  },
  {
    key: "printPlan",
    kind: "boolean",
    defaultValue: false,
    cliFlags: ["--dry-run", "--print-plan"],
    configKey: "printPlan",
    configAliases: ["dryRun"],
    helpGroup: "common",
    helpLines: [
      ["--dry-run", "Resolve input, print the resolved plan, and exit"],
      ["--print-plan", "Legacy alias for --dry-run"],
    ],
  },
  {
    key: "configPath",
    kind: "value",
    defaultValue: null,
    cliFlags: ["--config"],
    valueLabel: "<file>",
    helpGroup: "common",
    helpLines: [["--config <file>", "JSON configuration file (default: ./instalar.json)"]],
  },
  {
    key: "logFile",
    kind: "value",
    defaultValue: null,
    cliFlags: ["--log-file"],
    valueLabel: "<path>",
    configKey: "logFile",
    disallowOptionLikeValue: true,
    emptyValueWarning: "Ignoring empty --log-file value.",
    missingValueWarning: "--log-file requires a path.",
    helpGroup: "common",
    helpLines: [["--log-file <path>", "Write installer output to a plain-text log file"]],
  },
  {
    key: "displayCommandOutput",
    kind: "boolean",
    defaultValue: false,
    cliFlags: ["--display-command-output", "--display-info"],
    configKey: "displayCommandOutput",
    helpGroup: "common",
    helpLines: [
      ["--display-command-output", "Show command stdout/stderr while installer steps run"],
      ["--display-info", "Alias for --display-command-output"],
    ],
  },
  {
    key: "preset",
    kind: "value",
    defaultValue: null,
    cliFlags: ["--preset"],
    valueLabel: "<name>",
    configKey: "preset",
    normalizeValue: "lowercase",
    doctorIgnoredCli: true,
    helpGroup: "common",
    helpLines: [["--preset <name>", "Package preset: minimal, standard, or full"]],
  },
  {
    key: "upgradeDependencies",
    kind: "boolean",
    defaultValue: false,
    cliFlags: ["--upgrade-dependencies"],
    configKey: "upgradeDependencies",
    doctorIgnoredCli: true,
    helpGroup: "common",
    helpLines: [["--upgrade-dependencies", "Use composer update in update mode"]],
  },
  {
    key: "mode",
    kind: "value",
    defaultValue: null,
    cliFlags: ["--mode"],
    valueLabel: "<auto|manual|update|doctor>",
    configKey: "mode",
    normalizeValue: "lowercase",
    validateCli: true,
    validValues: () => INSTALLER_MODE_DEFINITIONS.map((mode) => mode.id),
    invalidCliMessage: (value) =>
      `Invalid --mode value: ${value}. Use auto, manual, update, or doctor.`,
    helpGroup: "common",
    helpLines: [["--mode <auto|manual|update|doctor>", ""]],
  },
  {
    key: "skipBoostInstall",
    kind: "boolean",
    defaultValue: false,
    cliFlags: ["--skip-boost-install"],
    configKey: "skipBoostInstall",
    doctorIgnoredCli: true,
    helpGroup: "common",
    helpLines: [["--skip-boost-install", "Skip interactive boost:install"]],
  },
  {
    key: "backup",
    kind: "boolean",
    defaultValue: false,
    cliFlags: ["--backup"],
    configKey: "backup",
    doctorIgnoredCli: true,
    helpGroup: "common",
    helpLines: [["--backup", "Backup existing target directory before replacing"]],
  },
  {
    key: "startServer",
    kind: "boolean",
    defaultValue: false,
    cliFlags: ["--start-server"],
    configKey: "startServer",
    doctorIgnoredCli: true,
    helpGroup: "common",
    helpLines: [["--start-server", "Automatically run composer run dev at the end"]],
  },
  {
    key: "verbose",
    kind: "boolean",
    defaultValue: false,
    cliFlags: ["--verbose"],
    configKey: "verbose",
    helpGroup: "common",
    helpLines: [["--verbose", "Enable verbose output"]],
  },
  {
    key: "debug",
    kind: "boolean",
    defaultValue: false,
    cliFlags: ["--debug"],
    configKey: "debug",
    helpGroup: "common",
    helpLines: [["--debug", "Enable debug mode (shows all commands)"]],
  },
  {
    key: "adminGenerate",
    kind: "boolean",
    defaultValue: false,
    cliFlags: ["--admin-generate"],
    configKey: "adminGenerate",
    doctorIgnoredCli: true,
    helpGroup: "automation",
    helpLines: [["--admin-generate", "Generate admin password"]],
  },
  {
    key: "continueOnHealthCheckFailure",
    kind: "boolean",
    defaultValue: false,
    cliFlags: ["--continue-on-health-check-failure"],
    configKey: "continueOnHealthCheckFailure",
    doctorIgnoredCli: true,
    helpGroup: "automation",
    helpLines: [
      [
        "--continue-on-health-check-failure",
        "Continue unattended runs despite failed health checks",
      ],
    ],
  },
  {
    key: "allowDeleteExisting",
    kind: "boolean",
    defaultValue: false,
    cliFlags: ["--allow-delete-existing"],
    configKey: "allowDeleteExisting",
    doctorIgnoredCli: true,
    helpGroup: "safety",
    helpLines: [["--allow-delete-existing", "Allow replacing in non-interactive mode"]],
  },
  {
    key: "allowDeleteAnyExisting",
    kind: "boolean",
    defaultValue: false,
    cliFlags: ["--allow-delete-any-existing"],
    configKey: "allowDeleteAnyExisting",
    doctorIgnoredCli: true,
    helpGroup: "safety",
    helpLines: [
      [
        "--allow-delete-any-existing",
        "Also allow replacing generic or git-managed directories",
      ],
    ],
  },
];

const CONFIG_FIELD_DEFINITIONS = {
  mode: {
    kind: "enumString",
    values: () => INSTALLER_MODE_DEFINITIONS.map((mode) => mode.id),
    invalidMessage: "must be auto, manual, update, or doctor.",
    allowModeOverride: false,
  },
  projectName: { kind: "string", doctorIgnoredConfig: true },
  appName: { kind: "string", doctorIgnoredConfig: true },
  projectPath: { kind: "string", doctorIgnoredConfig: true },
  preset: {
    kind: "enumString",
    values: () => PACKAGE_PRESETS.map((preset) => preset.id),
    invalidMessage: "must be minimal, standard, or full.",
    doctorIgnoredConfig: true,
  },
  allowDeleteExisting: { kind: "boolean", doctorIgnoredConfig: true },
  allowDeleteAnyExisting: { kind: "boolean", doctorIgnoredConfig: true },
  backup: { kind: "boolean", doctorIgnoredConfig: true },
  adminGenerate: { kind: "boolean", doctorIgnoredConfig: true },
  continueOnHealthCheckFailure: { kind: "boolean", doctorIgnoredConfig: true },
  upgradeDependencies: { kind: "boolean", doctorIgnoredConfig: true },
  dryRun: { kind: "boolean" },
  printPlan: { kind: "boolean" },
  logFile: { kind: "string", nonEmpty: true },
  displayCommandOutput: { kind: "boolean" },
  skipBoostInstall: { kind: "boolean", doctorIgnoredConfig: true },
  startServer: { kind: "boolean", doctorIgnoredConfig: true },
  nonInteractive: { kind: "boolean" },
  verbose: { kind: "boolean" },
  debug: { kind: "boolean" },
  database: {
    kind: "object",
    doctorIgnoredConfig: true,
    fields: {
      connection: {
        kind: "enumString",
        values: ["sqlite", "mysql", "pgsql"],
        invalidMessage: "must be sqlite, mysql, or pgsql.",
      },
      host: { kind: "string" },
      port: { kind: "string" },
      database: { kind: "string" },
      username: { kind: "string" },
      password: { kind: "string" },
    },
  },
  laravelFlags: { kind: "stringArray", doctorIgnoredConfig: true },
  laravelNewFlags: { kind: "stringArray", doctorIgnoredConfig: true },
  optionalPackageIds: { kind: "stringArray", doctorIgnoredConfig: true },
  customNormalPackages: { kind: "stringArray", doctorIgnoredConfig: true },
  customDevPackages: { kind: "stringArray", doctorIgnoredConfig: true },
  normalPackages: { kind: "stringArray", doctorIgnoredConfig: true },
  devPackages: { kind: "stringArray", doctorIgnoredConfig: true },
  createAdmin: { kind: "boolean", doctorIgnoredConfig: true },
  gitInit: { kind: "boolean", doctorIgnoredConfig: true },
  admin: {
    kind: "object",
    doctorIgnoredConfig: true,
    fields: {
      name: { kind: "string" },
      email: { kind: "string" },
      password: { kind: "string" },
    },
  },
  testSuite: {
    kind: "enumString",
    values: ["pest", "phpunit"],
    invalidMessage: "must be pest or phpunit.",
    doctorIgnoredConfig: true,
  },
};

const MODE_OVERRIDE_SECTION_KEYS = ["auto", "manual", "update"];
const HELP_GROUP_TITLES = {
  common: "Run controls",
  automation: "Automation",
  safety: "Safety",
};
const NODE_USAGE_EXAMPLES = [
  "./instalar.sh --mode manual",
  "./instalar.sh --mode auto --non-interactive --config ./instalar.json",
  "./instalar.sh --mode doctor --log-file ./doctor.log",
  "./instalar.sh --mode update --dry-run",
];

function createRuntimeCliDefaults() {
  return RUNTIME_OPTION_DEFINITIONS.reduce((defaults, definition) => {
    defaults[definition.key] = definition.defaultValue;
    return defaults;
  }, {});
}

function getRuntimeOptionDefinition(key) {
  return RUNTIME_OPTION_DEFINITIONS.find((definition) => definition.key === key) || null;
}

function getRuntimeConfigOptionValue(key, fileConfig = {}) {
  const definition = getRuntimeOptionDefinition(key);
  if (!definition || !definition.configKey) {
    return undefined;
  }

  if (fileConfig?.[definition.configKey] !== undefined) {
    return fileConfig[definition.configKey];
  }

  for (const alias of definition.configAliases || []) {
    if (fileConfig?.[alias] !== undefined) {
      return fileConfig[alias];
    }
  }

  return undefined;
}

function normalizeCliValue(definition, value) {
  const normalized = String(value ?? "").trim();
  if (definition.normalizeValue === "lowercase") {
    return normalized.toLowerCase();
  }

  return normalized;
}

function assignCliValueOption(options, definition, rawValue) {
  const normalizedValue = normalizeCliValue(definition, rawValue);
  if (normalizedValue.length === 0) {
    if (definition.emptyValueWarning) {
      warn(definition.emptyValueWarning);
    }
    return;
  }

  options[definition.key] = normalizedValue;
}

function getDefinitionValues(definition) {
  const values = definition.values ?? definition.validValues;
  return typeof values === "function" ? values() : values;
}

function getAllowedConfigKeys(allowModeOverrides = true) {
  const keys = Object.entries(CONFIG_FIELD_DEFINITIONS)
    .filter(([, definition]) => allowModeOverrides || definition.allowModeOverride !== false)
    .map(([key]) => key);

  if (allowModeOverrides) {
    keys.push(...MODE_OVERRIDE_SECTION_KEYS);
  }

  return new Set(keys);
}

function validateConfigField(value, definition, label) {
  switch (definition.kind) {
    case "boolean":
      validateBooleanConfig(value, label);
      return value;
    case "string":
      validateStringConfig(value, label);
      if (definition.nonEmpty && value.trim() === "") {
        throw new Error(`${label} must not be empty.`);
      }
      return value;
    case "stringArray":
      validateStringArrayConfig(value, label);
      return value;
    case "enumString": {
      validateStringConfig(value, label);
      const normalizedValue = value.trim().toLowerCase();
      if (!getDefinitionValues(definition).includes(normalizedValue)) {
        throw new Error(`${label} ${definition.invalidMessage}`);
      }
      return normalizedValue;
    }
    case "object": {
      validatePlainObjectConfig(value, label);
      const allowedKeys = new Set(Object.keys(definition.fields));
      for (const key of Object.keys(value)) {
        if (!allowedKeys.has(key)) {
          throw new Error(`Unknown configuration key: ${label}.${key}`);
        }
      }

      for (const [key, nestedDefinition] of Object.entries(definition.fields)) {
        if (value[key] !== undefined) {
          value[key] = validateConfigField(value[key], nestedDefinition, `${label}.${key}`);
        }
      }
      return value;
    }
    default:
      return value;
  }
}

// Parses Node-phase CLI arguments and normalizes known flags.
function parseCliArgs(args) {
  const options = createRuntimeCliDefaults();
  const booleanFlags = new Map();
  const valueFlags = new Map();

  RUNTIME_OPTION_DEFINITIONS.forEach((definition) => {
    if (definition.kind === "boolean") {
      definition.cliFlags.forEach((flag) => booleanFlags.set(flag, definition));
      return;
    }

    if (definition.kind === "value") {
      valueFlags.set(definition.cliFlags[0], definition);
    }
  });

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];

    const booleanDefinition = booleanFlags.get(arg);
    if (booleanDefinition) {
      options[booleanDefinition.key] = true;
      continue;
    }

    let matchedAssignment = false;
    for (const definition of RUNTIME_OPTION_DEFINITIONS) {
      if (definition.kind !== "value") {
        continue;
      }

      const assignmentPrefix = `${definition.cliFlags[0]}=`;
      if (arg.startsWith(assignmentPrefix)) {
        assignCliValueOption(options, definition, arg.slice(assignmentPrefix.length));
        matchedAssignment = true;
        break;
      }
    }

    if (matchedAssignment) {
      continue;
    }

    const valueDefinition = valueFlags.get(arg);
    if (valueDefinition) {
      const next = args[index + 1];
      if (next && (!valueDefinition.disallowOptionLikeValue || !next.startsWith("--"))) {
        assignCliValueOption(options, valueDefinition, next);
        index += 1;
      } else if (valueDefinition.missingValueWarning) {
        warn(valueDefinition.missingValueWarning);
      }
    }
  }

  RUNTIME_OPTION_DEFINITIONS.forEach((definition) => {
    if (!definition.validateCli || options[definition.key] === null) {
      return;
    }

    if (!getDefinitionValues(definition).includes(options[definition.key])) {
      warn(definition.invalidCliMessage(options[definition.key]));
      options[definition.key] = definition.defaultValue;
    }
  });

  return options;
}

function validateBooleanConfig(value, label) {
  if (typeof value !== "boolean") {
    throw new Error(`${label} must be a boolean.`);
  }
}

function validateStringConfig(value, label) {
  if (typeof value !== "string") {
    throw new Error(`${label} must be a string.`);
  }
}

function validateStringArrayConfig(value, label) {
  if (!Array.isArray(value) || value.some((entry) => typeof entry !== "string")) {
    throw new Error(`${label} must be an array of strings.`);
  }
}

function validatePlainObjectConfig(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} must be an object.`);
  }
}

function validateInstallerConfig(config, label = "config", allowModeOverrides = true) {
  validatePlainObjectConfig(config, label);

  const allowedKeys = getAllowedConfigKeys(allowModeOverrides);
  for (const key of Object.keys(config)) {
    if (!allowedKeys.has(key)) {
      throw new Error(`Unknown configuration key: ${label}.${key}`);
    }
  }

  for (const [key, value] of Object.entries(config)) {
    if (MODE_OVERRIDE_SECTION_KEYS.includes(key)) {
      validateInstallerConfig(value, `${label}.${key}`, false);
      continue;
    }

    const definition = CONFIG_FIELD_DEFINITIONS[key];
    if (!definition || value === undefined) {
      continue;
    }

    config[key] = validateConfigField(value, definition, `${label}.${key}`);
  }
}

// =============================================================================
// Config Parsing and Runtime Resolution
// =============================================================================
// Loads installer JSON config from disk and validates top-level shape.
function loadInstallerConfig(configPath) {
  const resolvedPath = path.resolve(process.cwd(), configPath);
  if (!fs.existsSync(resolvedPath)) {
    return { path: resolvedPath, config: null };
  }

  try {
    const parsed = JSON.parse(fs.readFileSync(resolvedPath, "utf8"));
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error(`Configuration file is not a JSON object: ${resolvedPath}`);
    }
    validateInstallerConfig(parsed, `config(${resolvedPath})`);
    return { path: resolvedPath, config: parsed };
  } catch (error) {
    throw new Error(`Unable to read configuration file: ${resolvedPath} (${error.message})`);
  }
}

// Resolves runtime settings by merging CLI options with JSON config values.
function resolveRuntime(cliOptions, fileConfig, configPath) {
  // CLI values always win, but config can still provide defaults for unattended runs.
  // dryRun is treated as a backwards-compatible alias for printPlan.
  const resolvedMode =
    (cliOptions.mode || getRuntimeConfigOptionValue("mode", fileConfig) || "").toLowerCase() ||
    null;
  const requestedPreset =
    cliOptions.preset || getRuntimeConfigOptionValue("preset", fileConfig) || "standard";
  const resolvedPreset = resolvePackagePresetName(requestedPreset);
  const nonInteractive = Boolean(
    cliOptions.nonInteractive || getRuntimeConfigOptionValue("nonInteractive", fileConfig) === true,
  );
  const logFile = resolveLogFilePath(
    cliOptions.logFile,
    getRuntimeConfigOptionValue("logFile", fileConfig),
    configPath,
  );
  const printPlan = Boolean(
    cliOptions.printPlan || getRuntimeConfigOptionValue("printPlan", fileConfig) === true,
  );

  return {
    nonInteractive,
    printPlan,
    preset: resolvedPreset,
    continueOnHealthCheckFailure: Boolean(
      cliOptions.continueOnHealthCheckFailure ||
        getRuntimeConfigOptionValue("continueOnHealthCheckFailure", fileConfig) === true,
    ),
    backup: Boolean(cliOptions.backup || getRuntimeConfigOptionValue("backup", fileConfig) === true),
    adminGenerate: Boolean(
      cliOptions.adminGenerate || getRuntimeConfigOptionValue("adminGenerate", fileConfig) === true,
    ),
    allowDeleteExisting: Boolean(
      cliOptions.allowDeleteExisting ||
        getRuntimeConfigOptionValue("allowDeleteExisting", fileConfig) === true,
    ),
    allowDeleteAnyExisting: Boolean(
      cliOptions.allowDeleteAnyExisting ||
        getRuntimeConfigOptionValue("allowDeleteAnyExisting", fileConfig) === true,
    ),
    upgradeDependencies: Boolean(
      cliOptions.upgradeDependencies ||
        getRuntimeConfigOptionValue("upgradeDependencies", fileConfig) === true,
    ),
    displayCommandOutput: Boolean(
      cliOptions.displayCommandOutput ||
        getRuntimeConfigOptionValue("displayCommandOutput", fileConfig) === true,
    ),
    logFile,
    skipBoostInstall: Boolean(
      cliOptions.skipBoostInstall ||
        getRuntimeConfigOptionValue("skipBoostInstall", fileConfig) === true ||
        nonInteractive,
    ),
    startServer: Boolean(
      cliOptions.startServer || getRuntimeConfigOptionValue("startServer", fileConfig) === true,
    ),
    mode: getDefinitionValues(CONFIG_FIELD_DEFINITIONS.mode).includes(resolvedMode) ? resolvedMode : null,
    configPath,
    config: fileConfig || {},
    verbose: Boolean(cliOptions.verbose || getRuntimeConfigOptionValue("verbose", fileConfig) === true),
    debug: Boolean(cliOptions.debug || getRuntimeConfigOptionValue("debug", fileConfig) === true),
  };
}

function resolveLogFilePath(cliValue, configValue, configPath) {
  // A CLI path is resolved from the current shell directory. A config path is
  // resolved from the config file location so checked-in examples stay portable.
  const normalize = (value) => {
    if (typeof value !== "string") {
      return null;
    }

    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  };

  const cliPath = normalize(cliValue);
  if (cliPath) {
    return path.resolve(process.cwd(), cliPath);
  }

  const configPathValue = normalize(configValue);
  if (!configPathValue) {
    return null;
  }

  const baseDirectory = configPath ? path.dirname(configPath) : process.cwd();
  return path.resolve(baseDirectory, configPathValue);
}

function warnDoctorModeIgnoredOptions(cliOptions = {}, fileConfig = {}) {
  const ignoredCliOptions = RUNTIME_OPTION_DEFINITIONS
    .filter((definition) => definition.doctorIgnoredCli === true)
    .filter((definition) =>
      definition.kind === "boolean"
        ? cliOptions[definition.key] === true
        : cliOptions[definition.key] !== definition.defaultValue,
    )
    .map((definition) => definition.cliFlags[0]);

  const ignoredConfigKeys = [
    ...Object.entries(CONFIG_FIELD_DEFINITIONS)
      .filter(([, definition]) => definition.doctorIgnoredConfig === true)
      .map(([key]) => key),
    ...MODE_OVERRIDE_SECTION_KEYS,
  ].filter((key) => Object.prototype.hasOwnProperty.call(fileConfig, key));

  if (ignoredCliOptions.length > 0) {
    warn(`Doctor mode ignores install-only CLI options: ${ignoredCliOptions.join(", ")}.`);
  }

  if (ignoredConfigKeys.length > 0) {
    warn(`Doctor mode ignores install-only config keys: ${ignoredConfigKeys.join(", ")}.`);
  }
}

// Mode presets inherit root config and then layer mode-specific overrides on top.
// Builds a mode-specific preset by merging root config with mode overrides.
function getModePreset(mode) {
  const rootConfig = state.runtime.config || {};
  const modeConfig =
    rootConfig[mode] && typeof rootConfig[mode] === "object" && !Array.isArray(rootConfig[mode])
      ? rootConfig[mode]
      : {};

  return { ...rootConfig, ...modeConfig };
}

function resolvePackagePresetName(value) {
  const requested = String(value || "standard").toLowerCase();
  const validPresets = PACKAGE_PRESETS.map((preset) => preset.id);

  if (validPresets.includes(requested)) {
    return requested;
  }

  warn(`Invalid package preset: ${value}. Falling back to standard.`);
  return "standard";
}

function getPackagePresetById(presetId) {
  return PACKAGE_PRESETS.find((preset) => preset.id === presetId) || PACKAGE_PRESETS[1];
}

function formatPackagePresetLabel(preset) {
  return `${preset.title} - ${preset.description}`;
}

function formatPackageChoiceLabel(choice) {
  return `${choice.title} [${choice.category}] - ${choice.summary}`;
}

function collectPackageSpecsFromChoiceIds(choiceIds = []) {
  const normal = [];
  const dev = [];

  choiceIds.forEach((choiceId) => {
    // Unknown IDs should not abort the whole install because they can come from
    // stale local config files after the optional package catalog changes.
    const choice = OPTIONAL_PACKAGE_CHOICES.find((item) => item.id === choiceId);
    if (!choice) {
      warn(`Unknown optional package id in preset/config: ${choiceId}`);
      return;
    }

    if (choice.normal) {
      normal.push(...choice.normal);
    }

    if (choice.dev) {
      dev.push(...choice.dev);
    }
  });

  return {
    normal,
    dev,
  };
}

// =============================================================================
// Prompt Helpers
// =============================================================================
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

// Prompts for a sensitive value and never echoes or logs the plaintext secret.
async function askSecret(question, defaultValue = "") {
  if (state.runtime.nonInteractive) {
    info(`[non-interactive] ${question}: ${(defaultValue ?? "") === "" ? "(empty)" : "(hidden)"}`);
    return String(defaultValue ?? "");
  }

  if (!process.stdin.isTTY || typeof process.stdin.setRawMode !== "function") {
    // This fallback keeps the installer usable in limited terminals, but it is
    // intentionally noisy because the secret will be visible as plain text.
    warn(`Secret prompt fallback is visible for: ${question}`);
    return ask(question, defaultValue);
  }

  return new Promise((resolve, reject) => {
    const buffer = [];
    const suffix = defaultValue ? color(" [hidden default]", C.dim) : "";
    process.stdout.write(`${color("?", C.cyan)} ${question}${suffix}: `);

    const onKeypress = (str, key) => {
      if (!key) {
        return;
      }

      if (key.ctrl && key.name === "c") {
        cleanup();
        reject(new Error("Cancelled by user."));
        return;
      }

      if (key.name === "return" || key.name === "enter") {
        cleanup();
        process.stdout.write("\n");
        resolve(buffer.length > 0 ? buffer.join("") : String(defaultValue ?? ""));
        return;
      }

      if (key.name === "backspace") {
        if (buffer.length > 0) {
          buffer.pop();
          process.stdout.write("\b \b");
        }
        return;
      }

      if (typeof str === "string" && str.length > 0 && !key.ctrl && !key.meta) {
        buffer.push(str);
        process.stdout.write("*");
      }
    };

    const cleanup = () => {
      process.stdin.off("keypress", onKeypress);
      process.stdin.setRawMode(false);
      process.stdin.pause();
    };

    readlineCore.emitKeypressEvents(process.stdin);
    process.stdin.setRawMode(true);
    process.stdin.resume();
    process.stdin.on("keypress", onKeypress);
  });
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

// Prompts for a yes/no answer using English-only aliases.
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
    if (["y", "yes"].includes(answer)) {
      return true;
    }
    if (["n", "no"].includes(answer)) {
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
  detail("Choose one option and press Enter.");
  options.forEach((option, index) => {
    const mark = index === defaultIndex ? color(" (default)", C.dim) : "";
    console.log(`  ${color(String(index + 1), C.cyan)}) ${option}${mark}`);
  });

  while (true) {
    const raw = await ask("Choice number", String(defaultIndex + 1));
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
  detail("Select one or more options. Press Enter to keep the default selection.");
  options.forEach((option, index) => {
    const mark = defaultIndexes.includes(index) ? color(" [x]", C.green) : "";
    console.log(`  ${color(String(index + 1), C.cyan)}) ${option}${mark}`);
  });
  detail("Tip: Separate multiple values with comma or space.");

  const defaultValue = defaultIndexes.map((index) => String(index + 1)).join(",");

  while (true) {
    const raw = await ask("Choice numbers", defaultValue);
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
  let renderedRows = 0;

  const render = () => {
    const columns =
      Number.isInteger(process.stdout.columns) && process.stdout.columns > 0
        ? process.stdout.columns
        : 80;
    const lines = [
      color(question, C.bold + C.white),
      `  ${color("Selected:", C.dim)} ${selected.size}/${options.length}`,
      ...options.map((option, index) => {
        const pointer = index === cursor ? color("›", C.cyan) : " ";
        const mark = selected.has(index) ? color("[x]", C.green) : "[ ]";
        return `  ${pointer} ${mark} ${option}`;
      }),
      `  ${color("Controls:", C.dim)} ${color("↑/↓", C.cyan)} move, ${color("Space", C.cyan)} toggle, ${color("Enter", C.cyan)} confirm`,
      "",
    ];

    if (renderedRows > 0) {
      process.stdout.write(`\x1b[${renderedRows}A`);
    }

    process.stdout.write("\x1b[0J");
    process.stdout.write(lines.join("\n"));
    renderedRows = countRenderedCursorRows(lines, columns);
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

// =============================================================================
// Package and Flag Normalization
// =============================================================================
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
  // Startup flags and test-suite flags follow different rules: the installer
  // keeps every unique startup flag but collapses the test suite to exactly one.
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

  if (ids.includes("all") || ids.includes("*")) {
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

// =============================================================================
// Command Execution and Logging
// =============================================================================
// Executes a subprocess and resolves/rejects based on exit code.
function appendOutputTail(current, chunk, limit = 12000) {
  const combined = `${current}${chunk}`;
  return combined.length > limit ? combined.slice(-limit) : combined;
}

function truncateTextMiddle(value, maxLength = 44) {
  const text = String(value ?? "");
  if (text.length <= maxLength) {
    return text;
  }

  const safeLength = Math.max(12, maxLength);
  const visible = safeLength - 1;
  const head = Math.ceil(visible / 2);
  const tail = Math.floor(visible / 2);
  return `${text.slice(0, head)}…${text.slice(-tail)}`;
}

function summarizeCommandForActivity(command, args = []) {
  if (command === "php" && Array.isArray(args) && args[0] === "artisan") {
    return `artisan ${artisanCommandLabel(args) || "command"}`;
  }

  if (command === "npm") {
    return `npm ${args.slice(0, 2).join(" ").trim() || "command"}`.trim();
  }

  if (command === "composer") {
    return `composer ${args[0] || "command"}`.trim();
  }

  if (command === "laravel") {
    return `laravel ${args[0] || "command"}`.trim();
  }

  return `${command} ${args[0] || ""}`.trim();
}

function buildActivityBarFrame(label, tick = 0, width = 16) {
  const safeWidth = Math.max(8, Number(width) || 16);
  const travel = Math.max(0, safeWidth - 4);
  const period = Math.max(1, travel * 2);
  const offset = Number(tick) % period;
  const position = offset <= travel ? offset : period - offset;
  const bar = `${"░".repeat(position)}${"████"}${"░".repeat(Math.max(0, travel - position))}`;
  return `  ${color("│", C.dim + C.cyan)} ${color("Working", C.dim + C.cyan)} ${truncateTextMiddle(label, 34)} ${color(`[${bar}]`, C.bold + C.cyan)}`;
}

function shouldAnimateCommandActivity(options = {}, runtimeOptions = state.runtime) {
  return Boolean(
    process.stdout?.isTTY &&
      !shouldDisplayCommandOutput(options, runtimeOptions) &&
      !runtimeOptions.debug,
  );
}

function createCommandActivityIndicator(label, options = {}, runtimeOptions = state.runtime) {
  const enabled = shouldAnimateCommandActivity(options, runtimeOptions);
  let tick = 0;
  let interval = null;
  let lastWidth = 0;

  const render = () => {
    const frame = buildActivityBarFrame(label, tick);
    tick += 1;
    lastWidth = terminalStringWidth(frame);
    process.stdout.write(`\r${frame}`);
  };

  return {
    enabled,
    start() {
      if (!enabled || interval) {
        return;
      }

      render();
      interval = setInterval(render, 90);
    },
    stop() {
      if (!enabled) {
        return;
      }

      if (interval) {
        clearInterval(interval);
        interval = null;
      }

      process.stdout.write(`\r${" ".repeat(lastWidth)}\r`);
    },
  };
}

function formatOutputSnippet(output, label) {
  const sanitized = stripAnsi(output || "").trim();
  if (!sanitized) {
    return "";
  }

  const lines = sanitized.split(/\r?\n/);
  const lastLines = lines.slice(-8).join("\n");
  return `${label}:\n${lastLines}`;
}

function buildCommandFailureSnippet(error) {
  const stdoutSnippet = formatOutputSnippet(error.stdout, "Last stdout");
  const stderrSnippet = formatOutputSnippet(error.stderr, "Last stderr");
  return [stdoutSnippet, stderrSnippet].filter(Boolean).join("\n\n");
}

function printCommandFailureSnippet(snippet) {
  if (!snippet) {
    return;
  }

  console.log("");
  console.log(color("Recent command output:", C.bold + C.yellow));
  console.log(snippet);
  appendToRuntimeLog(`\nRecent command output:\n${snippet}\n`);
}

function runProcess(command, args, options = {}) {
  const {
    cwd = process.cwd(),
    stdio = "inherit",
    env = process.env,
    interactive = false,
    captureOutput = false,
    streamOutput = false,
  } = options;
  // Output capture is only safe when the command uses inherited stdio and does
  // not need interactive control of the terminal.
  const shouldCapture = captureOutput && stdio === "inherit" && !interactive;

  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd,
      env,
      stdio: shouldCapture ? ["inherit", "pipe", "pipe"] : stdio,
    });
    let stdout = "";
    let stderr = "";

    if (shouldCapture) {
      if (child.stdout) {
        child.stdout.on("data", (chunk) => {
          // Mirror captured output back to the terminal so live progress stays
          // visible when explicitly enabled while still retaining the tail for
          // failure reporting and runtime log capture.
          const text = chunk.toString();
          stdout = appendOutputTail(stdout, text);
          if (streamOutput) {
            process.stdout.write(chunk);
          }
          appendToRuntimeLog(text);
        });
      }

      if (child.stderr) {
        child.stderr.on("data", (chunk) => {
          const text = chunk.toString();
          stderr = appendOutputTail(stderr, text);
          if (streamOutput) {
            process.stderr.write(chunk);
          }
          appendToRuntimeLog(text);
        });
      }
    }

    child.on("error", (error) => {
      error.stdout = stdout;
      error.stderr = stderr;
      reject(error);
    });
    child.on("close", (code, signal) => {
      if (code === 0) {
        resolve({ stdout, stderr });
        return;
      }

      const error = new Error(`Command failed: ${command} ${args.join(" ")}`);
      error.exitCode = code;
      error.signal = signal;
      error.stdout = stdout;
      error.stderr = stderr;
      reject(error);
    });
  });
}

function redactText(text, redactedValues = []) {
  return redactedValues
    .filter((value) => value !== undefined && value !== null && String(value).length > 0)
    .reduce((output, value) => output.split(String(value)).join("[REDACTED]"), String(text));
}

function formatCommandForDisplay(command, args, redactedValues = []) {
  return redactText(`${command} ${args.join(" ")}`.trim(), redactedValues);
}

function shouldDisplayCommandOutput(options = {}, runtimeOptions = state.runtime) {
  if (options.interactive) {
    return true;
  }

  return Boolean(
    options.displayCommandOutput ||
      runtimeOptions.displayCommandOutput ||
      runtimeOptions.verbose ||
      runtimeOptions.debug,
  );
}

// Executes a command with standard installer logging and optional failure behavior.
async function runCommand(command, args, options = {}) {
  const {
    cwd = process.cwd(),
    required = true,
    warnOnFailure = true,
    env = process.env,
    stdio = "inherit",
    interactive = false,
    captureOutput = stdio === "inherit" && !interactive,
    displayCommandOutput = false,
    redactedValues = [],
    successLabel = null,
  } = options;
  const cmdStr = formatCommandForDisplay(command, args, redactedValues);
  const streamCommandOutput = shouldDisplayCommandOutput(
    { interactive, displayCommandOutput },
    state.runtime,
  );
  const activityIndicator = createCommandActivityIndicator(
    summarizeCommandForActivity(command, args),
    { interactive, displayCommandOutput },
    state.runtime,
  );

  // Use verbose() if verbose or debug is enabled
  if (state.runtime.verbose || state.runtime.debug) {
    verbose(`Executing: ${cmdStr}`);
  } else {
    info(`Run: ${cmdStr}`);
  }

  try {
    activityIndicator.start();
    await runProcess(command, args, {
      cwd,
      env,
      stdio,
      interactive,
      captureOutput,
      streamOutput: streamCommandOutput,
    });
    activityIndicator.stop();
    ok(successLabel || `${command} ${args[0] ?? ""}`.trim());
    return { exitCode: 0, success: true };
  } catch (error) {
    activityIndicator.stop();
    const exitCode = error.exitCode || 1;
    const failureMessage = `Command failed (exit ${exitCode}): ${cmdStr}`;
    const failureSnippet = buildCommandFailureSnippet(error);
    const failureSummary = buildCommandFailureSummary(command, args, {
      cwd,
      exitCode,
      displayCommand: cmdStr,
      redactedValues,
    });

    if (required) {
      // Required failures bubble up with an attached snippet so the top-level
      // error handler can print actionable context without re-running anything.
      error.message = failureMessage;
      error.outputSnippet = failureSnippet;
      error.failureSummary = failureSummary;
      throw error;
    }
    if (warnOnFailure) {
      warn(`Command failed and will be skipped: ${cmdStr}`);
    } else {
      info(`Command failed and will be skipped: ${cmdStr}`);
    }
    printCommandFailureSnippet(failureSnippet);
    return { exitCode, success: false };
  }
}

// =============================================================================
// Path Safety and Filesystem Helpers
// =============================================================================
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
  const {
    warnOnFailure = true,
    interactive = false,
    captureOutput = undefined,
    displayCommandOutput = false,
    required = false,
  } = options;

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
    required,
    warnOnFailure,
    interactive,
    captureOutput,
    displayCommandOutput,
  });
}

async function runPotentiallyInteractiveArtisanCommand(
  projectDir,
  commandName,
  args = [],
  messageIfMissing = "",
  options = {},
) {
  const {
    skipMessage = `Skipping ${commandName} in non-interactive mode. Run 'php artisan ${commandName}' manually.`,
    interactiveNotice = `${commandName} may ask interactive questions.`,
    warnOnFailure = false,
    required = false,
  } = options;

  if (state.runtime.nonInteractive) {
    warnFinal(skipMessage);
    return false;
  }

  info(interactiveNotice);
  return runArtisanIfAvailable(projectDir, commandName, args, messageIfMissing, {
    warnOnFailure,
    required,
    interactive: true,
    captureOutput: false,
    displayCommandOutput: true,
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

function isGitRepository(directory) {
  return fs.existsSync(path.join(directory, ".git"));
}

function classifyExistingPath(targetPath) {
  if (!fs.existsSync(targetPath)) {
    return "missing";
  }

  try {
    const stats = fs.lstatSync(targetPath);
    if (!stats.isDirectory()) {
      return "generic-nonempty";
    }
  } catch {
    return "generic-nonempty";
  }

  if (directoryIsEmpty(targetPath)) {
    return "empty";
  }

  if (isLaravelProject(targetPath)) {
    return "laravel-project";
  }

  if (isGitRepository(targetPath)) {
    return "git-repo";
  }

  return "generic-nonempty";
}

// Human-readable labels keep plan output and error messages aligned with the
// internal path-safety classifier used by install and update flows.
function describePathClassification(classification) {
  switch (classification) {
    case "missing":
      return "missing";
    case "empty":
      return "empty directory";
    case "laravel-project":
      return "Laravel project";
    case "git-repo":
      return "Git-managed directory";
    default:
      return "generic non-empty path";
  }
}

function canDeleteExistingPathNonInteractive(classification, runtimeOptions = state.runtime) {
  if (classification === "missing") {
    return true;
  }

  if (classification === "empty" || classification === "laravel-project") {
    return Boolean(runtimeOptions.allowDeleteExisting || runtimeOptions.allowDeleteAnyExisting);
  }

  return Boolean(runtimeOptions.allowDeleteAnyExisting);
}

function getProtectedPathReason(targetPath) {
  const resolvedTarget = path.resolve(targetPath);
  const resolvedCwd = path.resolve(process.cwd());
  const rootPath = path.parse(resolvedTarget).root;
  const homeDirectory = path.resolve(os.homedir());

  if (resolvedTarget === rootPath) {
    return "target path must not be the root directory.";
  }

  if (resolvedTarget === resolvedCwd) {
    return "target path is the current working directory.";
  }

  if (resolvedTarget === homeDirectory) {
    return "target path must not be the home directory.";
  }

  return null;
}

function ensureSafeProjectTarget(targetPath) {
  const protectedPathReason = getProtectedPathReason(targetPath);
  if (protectedPathReason) {
    throw new Error(`Safety abort: ${protectedPathReason}`);
  }
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

// =============================================================================
// Environment and Project Metadata Helpers
// =============================================================================
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
    // Laravel expects a real sqlite file even when the database path is stored
    // as a relative value inside .env.
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

// Parses PHP use-statements so auth config entries like User::class can be
// resolved back to fully-qualified class names before the bootstrap script runs.
function parseImportedClasses(source) {
  const imports = new Map();
  const pattern = /^use\s+([^;]+?)(?:\s+as\s+([A-Za-z_][A-Za-z0-9_]*))?\s*;/gm;
  let match = null;

  while ((match = pattern.exec(source)) !== null) {
    const importedClass = match[1].trim();
    const alias = match[2]?.trim() || importedClass.split("\\").pop();
    imports.set(alias, importedClass);
  }

  return imports;
}

function resolveAuthUserModel(projectDir) {
  const authConfigPath = path.join(projectDir, "config", "auth.php");
  if (!fs.existsSync(authConfigPath)) {
    return "App\\Models\\User";
  }

  const authConfig = fs.readFileSync(authConfigPath, "utf8");
  const importedClasses = parseImportedClasses(authConfig);
  const patterns = [
    /'model'\s*=>\s*env\(\s*'AUTH_MODEL'\s*,\s*([A-Za-z0-9_\\]+)::class\s*\)/,
    /'model'\s*=>\s*([A-Za-z0-9_\\]+)::class/,
  ];

  for (const pattern of patterns) {
    const match = authConfig.match(pattern);
    if (match) {
      const modelClass = match[1].trim();
      if (modelClass.includes("\\")) {
        return modelClass;
      }

      // Imported aliases are common in modern auth configs, so the installer
      // must expand them before passing the model into the temporary PHP runner.
      return importedClasses.get(modelClass) || `App\\Models\\${modelClass}`;
    }
  }

  return "App\\Models\\User";
}

// Reads package names from require and require-dev sections of composer.json.
function readComposerPackages(projectDir) {
  const composerPath = path.join(projectDir, "composer.json");
  if (!fs.existsSync(composerPath)) {
    return new Set();
  }

  const json = JSON.parse(fs.readFileSync(composerPath, "utf8"));
  const names = new Set();
  const addPackages = (entries) => {
    Object.keys(entries || {}).forEach((key) => {
      if (key.includes("/")) {
        names.add(key);
      }
    });
  };

  addPackages(json.require);
  addPackages(json["require-dev"]);

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

// =============================================================================
// Interactive Config Collection
// =============================================================================
// Collects auto-mode installation config from prompts and presets.
async function collectAutoConfig(preset = {}) {
  printModeIntro("auto");

  const appNameDefault = preset.projectName || preset.appName || "Laravel Filament App";
  const appName = await askRequired("Project name", appNameDefault);
  const slug = slugify(appName) || "laravel-filament-app";
  const projectPath = path.resolve(process.cwd(), preset.projectPath || slug);
  const presetOptions = PACKAGE_PRESETS.map((item) => formatPackagePresetLabel(item));
  const defaultPresetIndex = PACKAGE_PRESETS.findIndex(
    (item) => item.id === resolvePackagePresetName(preset.preset || state.runtime.preset),
  );
  const selectedPresetIndex = await askChoice(
    "Package preset",
    presetOptions,
    defaultPresetIndex >= 0 ? defaultPresetIndex : 1,
  );
  const selectedPreset = PACKAGE_PRESETS[selectedPresetIndex];
  const presetPackages = collectPackageSpecsFromChoiceIds(selectedPreset.optionalPackageIds);

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

  // Auto mode keeps the experience intentionally opinionated: database defaults,
  // preset-driven packages, and optional generated credentials if requested.
  const createAdmin = preset.createAdmin !== undefined ? Boolean(preset.createAdmin) : true;
  const admin = resolveAdminCredentials(preset, createAdmin);

  return {
    mode: "auto",
    presetId: selectedPreset.id,
    appName,
    projectPath,
    database,
    laravelNewFlags,
    normalPackages: mergePackageSpecs([
      "filament/filament:^5.0",
      ...presetPackages.normal,
      ...(Array.isArray(preset.normalPackages) ? preset.normalPackages : []),
    ]),
    devPackages: mergePackageSpecs([
      ...presetPackages.dev,
      ...(Array.isArray(preset.devPackages) ? preset.devPackages : []),
    ]),
    createAdmin,
    admin,
    gitInit: Boolean(preset.gitInit),
  };
}

// Collects manual-mode installation config with full interactive choices.
async function collectManualConfig(preset = {}) {
  const totalSteps = 6;
  printModeIntro("manual");

  printStepCard(1, totalSteps, "Project Basics", "Name the app and choose where it should be created.");
  const appNameDefault = preset.projectName || preset.appName || "Laravel Filament App";
  const appName = await askRequired("Project name", appNameDefault);
  const defaultDir = `./${slugify(appName) || "laravel-filament-app"}`;
  const defaultProjectPath = preset.projectPath || defaultDir;
  const projectPath = path.resolve(process.cwd(), await askRequired("Project directory", defaultProjectPath));

  printStepCard(2, totalSteps, "Database", "Choose a local SQLite file or provide a server database connection.");
  const defaultDbChoice =
    preset?.database?.connection === "mysql"
      ? 1
      : preset?.database?.connection === "pgsql"
        ? 2
        : 0;

  const dbChoice = await askChoice(
    "Database engine",
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
      password: await askSecret("DB Password", preset?.database?.password || ""),
    };
  }
  if (dbChoice === 2) {
    database = {
      connection: "pgsql",
      host: await ask("DB Host", preset?.database?.host || "127.0.0.1"),
      port: await ask("DB Port", preset?.database?.port || "5432"),
      database: await askRequired("DB Name", preset?.database?.database || "app"),
      username: await askRequired("DB User", preset?.database?.username || "postgres"),
      password: await askSecret("DB Password", preset?.database?.password || ""),
    };
  }

  printStepCard(3, totalSteps, "Laravel Starter", "Pick the starter flags that should be passed to laravel new.");
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
    "Starter features",
    laravelFlagOptions,
    defaultLaravelFlagIndexes,
  );
  const selectedStartupFlags = selectedLaravelFlagIndexes.map(
    (index) => laravelFlagOptions[index],
  );

  const defaultTestSuiteIndex = resolvedLaravelFlags.includes("--phpunit") ? 1 : 0;
  const testSuiteChoice = await askChoice(
    "Default test suite",
    ["Pest", "PHPUnit"],
    defaultTestSuiteIndex,
  );
  const testSuiteFlag = testSuiteChoice === 1 ? "--phpunit" : "--pest";
  const laravelNewFlags = [...selectedStartupFlags, testSuiteFlag];

  printStepCard(4, totalSteps, "Packages", "Choose a preset first, then refine the optional package stack.");
  const presetOptions = PACKAGE_PRESETS.map((item) => formatPackagePresetLabel(item));
  const defaultPresetIndex = PACKAGE_PRESETS.findIndex(
    (item) => item.id === resolvePackagePresetName(preset.preset || state.runtime.preset),
  );
  const selectedPresetIndex = await askChoice(
    "Package preset",
    presetOptions,
    defaultPresetIndex >= 0 ? defaultPresetIndex : 1,
  );
  const selectedPreset = PACKAGE_PRESETS[selectedPresetIndex];
  const optionalLabels = OPTIONAL_PACKAGE_CHOICES.map((choice) => formatPackageChoiceLabel(choice));
  const defaultOptionalIndexes = getOptionIndexesByIds(
    preset.optionalPackageIds,
    getOptionIndexesByIds(selectedPreset.optionalPackageIds),
  );
  const selected = await askMultiChoiceWithAll(
    "Optional packages",
    optionalLabels,
    defaultOptionalIndexes,
  );

  // Boost is always installed in manual mode because later setup and plan output
  // assume it is part of the baseline toolchain alongside Filament.
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
    await ask("Additional Composer packages", customNormalDefault),
  );
  const customDev = splitPackageInput(
    await ask("Additional dev Composer packages", customDevDefault),
  );

  printStepCard(5, totalSteps, "Admin and Git", "Decide whether to create an admin user and initialize Git.");
  const defaultCreateAdmin =
    preset.createAdmin !== undefined ? Boolean(preset.createAdmin) : true;
  const createAdmin = await askYesNo("Create a Filament admin user", defaultCreateAdmin);
  const admin = resolveAdminCredentials(preset, createAdmin);

  const gitInit = await askYesNo(
    "Initialize a Git repository",
    preset.gitInit !== undefined ? Boolean(preset.gitInit) : false,
  );

  return {
    mode: "manual",
    presetId: selectedPreset.id,
    appName,
    projectPath,
    database,
    laravelNewFlags,
    normalPackages: mergePackageSpecs([...normalPackages, ...customNormal]),
    devPackages: mergePackageSpecs([...devPackages, ...customDev]),
    createAdmin,
    admin,
    gitInit,
  };
}

// Resolves how admin credentials should be sourced without exposing configured
// secrets in the plan or final summary output.
function resolveAdminCredentials(preset = {}, createAdmin = true) {
  const configuredPassword =
    typeof preset?.admin?.password === "string" ? preset.admin.password : "";
  const admin = {
    name: preset?.admin?.name || "Admin",
    email: preset?.admin?.email || "admin@example.com",
    password: "",
    passwordSource: "none",
    revealPassword: false,
  };

  if (!createAdmin) {
    return admin;
  }

  if (configuredPassword) {
    info("Admin password will be loaded from configuration.");
    return {
      ...admin,
      password: configuredPassword,
      passwordSource: "config",
      revealPassword: false,
    };
  }

  if (state.runtime.adminGenerate) {
    info("Admin password will be generated automatically (--admin-generate).");
    return {
      ...admin,
      password: generateAdminPassword(20),
      passwordSource: "generated",
      revealPassword: true,
    };
  }

  warnFinal(
    "Using the default admin password. Prefer --admin-generate or admin.password in config.",
  );
  return {
    ...admin,
    password: "password",
    passwordSource: "default",
    revealPassword: false,
  };
}

// =============================================================================
// Plan Rendering
// =============================================================================
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

function formatList(items) {
  return Array.isArray(items) && items.length > 0 ? items.join(", ") : "-";
}

function configUsesSensitiveValues(config) {
  return Boolean(
    (config.database &&
      typeof config.database.password === "string" &&
      config.database.password.length > 0) ||
      (config.admin &&
        config.admin.passwordSource === "config" &&
        typeof config.admin.password === "string" &&
        config.admin.password.length > 0),
  );
}

function describeAdminPasswordStrategy(config) {
  if (!config.createAdmin) {
    return "not created";
  }

  switch (config.admin?.passwordSource) {
    case "generated":
      return "generated";
    case "config":
      return "provided via config (hidden)";
    case "default":
      return "default password (hidden)";
    default:
      return "hidden";
  }
}

function describeExistingPathStrategy(targetPath, runtimeOptions = state.runtime) {
  const classification = classifyExistingPath(targetPath);
  if (classification === "missing") {
    return "Create new directory";
  }

  if (runtimeOptions.nonInteractive) {
    if (!canDeleteExistingPathNonInteractive(classification, runtimeOptions)) {
      if (classification === "git-repo" || classification === "generic-nonempty") {
        return "Abort unless --allow-delete-any-existing is set";
      }

      return "Abort unless --allow-delete-existing is set";
    }

    return runtimeOptions.backup
      ? "Replace existing path after backup"
      : "Replace existing path";
  }

  if (classification === "git-repo" || classification === "generic-nonempty") {
    return "Prompt before replacing a risky existing path";
  }

  return classification === "empty"
    ? "Prompt before reusing the empty directory"
    : "Prompt before replacing the existing Laravel project";
}

function buildDatabasePlanEntries(database) {
  const entries = [["Connection", database.connection]];

  if (database.connection === "sqlite") {
    entries.push(["Database file", "database/database.sqlite"]);
    return entries;
  }

  entries.push(["Host", database.host]);
  entries.push(["Port", database.port]);
  entries.push(["Database", database.database]);
  entries.push(["User", database.username]);
  entries.push(["Password", database.password ? "(hidden)" : "(empty)"]);
  return entries;
}

function printInstallPlan(config, runtimeOptions = state.runtime) {
  const packageSet = packageSetFromConfig(config);
  const preset = getPackagePresetById(config.presetId || runtimeOptions.preset);
  const pathClassification = classifyExistingPath(config.projectPath);

  section("Installation Review");
  detail("Nothing is created or replaced until this run is approved.");
  printReviewSection("Run Profile", [
    ["Mode", config.mode],
    ["Name", config.appName],
    ["Path", config.projectPath],
    ["Path type", describePathClassification(pathClassification)],
    ["Path strategy", describeExistingPathStrategy(config.projectPath, runtimeOptions)],
  ]);
  printReviewSection("Database Profile", buildDatabasePlanEntries(config.database));
  printReviewSection("Starter Stack", [
    ["Laravel flags", formatList(config.laravelNewFlags)],
    ["Boost install", runtimeOptions.skipBoostInstall ? "skip" : "run interactively"],
  ]);
  printReviewSection("Package Stack", [
    ["Preset", preset.title],
    ["Normal packages", `${config.normalPackages.length} selected`],
    ["Dev packages", `${config.devPackages.length} selected`],
  ]);
  printBulletSection("Normal Packages", config.normalPackages, "No extra normal packages.");
  printBulletSection("Dev Packages", config.devPackages, "No dev packages.");
  printReviewSection("Identity and Git", [
    ["Create admin", config.createAdmin ? "yes" : "no"],
    ["Admin password", describeAdminPasswordStrategy(config)],
    ["Configured secrets", configUsesSensitiveValues(config) ? "yes" : "no"],
    ["Git init", config.gitInit ? "yes" : "no"],
  ]);
  printReviewSection("Run Controls", [
    ["Dry run", runtimeOptions.printPlan ? "yes" : "no"],
    ["Log file", runtimeOptions.logFile || "-"],
    [
      "Health-check failures",
      runtimeOptions.continueOnHealthCheckFailure ? "continue" : "abort",
    ],
  ]);

  if (runtimeOptions.printPlan) {
    ok("Preview only. No project files will be modified.");
  } else if (runtimeOptions.nonInteractive) {
    info("[non-interactive] Installation will start automatically after this review.");
  }

  return packageSet;
}

function printUpdatePlan(projectDir, packages, runtimeOptions = state.runtime) {
  const dependencyStrategy = resolveUpdateDependencyStrategy(runtimeOptions);
  section("Update Review");
  detail("Inspect the current project state before dependencies, migrations, and builds run.");
  printReviewSection("Project Snapshot", [
    ["Project", projectDir],
    ["Path type", describePathClassification(classifyExistingPath(projectDir))],
  ]);
  printReviewSection("Run Controls", [
    ["Dry run", runtimeOptions.printPlan ? "yes" : "no"],
    ["Log file", runtimeOptions.logFile || "-"],
    ["Composer dependencies", dependencyStrategy.label],
    ["Boost install", runtimeOptions.skipBoostInstall ? "skip" : "run interactively"],
    [
      "Health-check failures",
      runtimeOptions.continueOnHealthCheckFailure ? "continue" : "abort",
    ],
  ]);
  printBulletSection("Detected Stack", [...packages].sort(), "No Composer packages detected.");

  if (runtimeOptions.printPlan) {
    ok("Preview only. No project files will be modified.");
  } else if (runtimeOptions.nonInteractive) {
    info("[non-interactive] Update will start automatically after this review.");
  }
}

// =============================================================================
// Source Rewriting Helpers
// =============================================================================
// Extracts an object property block (e.g. server: { ... }) from source text.
function extractObjectPropertyBlock(source, propertyName) {
  // This is a narrow brace matcher, not a general JavaScript parser. It only
  // targets simple vite.config.js shapes that the installer knows how to rewrite.
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

function readImportLines(source) {
  return String(source)
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.startsWith("import "));
}

function hasOnlySupportedNwidartViteImports(source) {
  const imports = readImportLines(source);
  const allowedImports = new Set([
    "import { defineConfig } from 'vite';",
    'import { defineConfig } from "vite";',
    "import laravel from 'laravel-vite-plugin';",
    'import laravel from "laravel-vite-plugin";',
    "import tailwindcss from '@tailwindcss/vite';",
    'import tailwindcss from "@tailwindcss/vite";',
  ]);

  return imports.length >= 2 && imports.every((line) => allowedImports.has(line));
}

function hasUnsupportedNwidartViteSettings(source) {
  return [
    /\bresolve\s*:/,
    /\bbuild\s*:/,
    /\bcss\s*:/,
    /\bdefine\s*:/,
    /\bpreview\s*:/,
    /\bssr\s*:/,
    /\boptimizeDeps\s*:/,
    /\bworker\s*:/,
    /\bassetsInclude\s*:/,
    /\bbase\s*:/,
    /\btest\s*:/,
  ].some((pattern) => pattern.test(source));
}

function canSafelyRewriteNwidartViteConfig(source) {
  if (!hasOnlySupportedNwidartViteImports(source)) {
    return false;
  }

  if (!source.includes("export default defineConfig({")) {
    return false;
  }

  if (hasUnsupportedNwidartViteSettings(source)) {
    return false;
  }

  return true;
}

// =============================================================================
// Nwidart / Modules Automation
// =============================================================================
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

    // Composer config can be absent or malformed in freshly generated projects,
    // so each container is rebuilt defensively before the plugin flag is set.
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
    warnFinal("Could not read composer.json. Skipping Nwidart autoload adjustments.");
    return false;
  }

  let changed = false;
  let removedLegacyModulesAutoload = false;
  let addedMergePluginInclude = false;

  // Older setups may still autoload the top-level Modules namespace directly.
  // The merge-plugin layout replaces that with per-module composer files.
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
    warnFinal("vite.config.js is missing. Skipping Nwidart Vite configuration.");
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

  if (
    !hasLaravelPlugin ||
    !hasDefaultInputs ||
    !canSafelyRewriteNwidartViteConfig(currentConfig)
  ) {
    warnFinal("vite.config.js looks customized. Skipping automatic Nwidart Vite rewrite.");
    info("Please follow Nwidart docs to switch manually to collectModuleAssetsPaths.");
    return false;
  }

  const useTailwindPlugin =
    currentConfig.includes("@tailwindcss/vite") || currentConfig.includes("tailwindcss(");
  const serverBlock = extractObjectPropertyBlock(currentConfig, "server");

  // The replacement keeps the common server block and optional Tailwind plugin,
  // but swaps the fixed asset list for the Nwidart-aware collector.
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

  await runPotentiallyInteractiveArtisanCommand(
    projectDir,
    "module:filament:install",
    ["CoreModule"],
    "module:filament:install not available, skipping.",
    {
      warnOnFailure: false,
      skipMessage:
        "Skipping module:filament:install in non-interactive mode. Run 'php artisan module:filament:install CoreModule' manually.",
      interactiveNotice: "module:filament:install may ask interactive questions.",
    },
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
      // Keep defaults; the summary should report missing invariants instead of crashing.
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
    ok("Nwidart setup complete (plugins + merge + vite)");
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

  warnFinal(`Nwidart setup incomplete: ${missing.join(", ")}`);
}

// Generates a temporary PHP bootstrap script so the installer can create the
// Filament admin user without exposing the password in process arguments.
function buildFilamentAdminBootstrapScript() {
  return [
    "<?php",
    "declare(strict_types=1);",
    "",
    "use Illuminate\\Contracts\\Console\\Kernel;",
    "use Illuminate\\Support\\Facades\\Hash;",
    "use Illuminate\\Support\\Facades\\Schema;",
    "",
    "require getcwd() . '/vendor/autoload.php';",
    "$app = require getcwd() . '/bootstrap/app.php';",
    "$kernel = $app->make(Kernel::class);",
    "$kernel->bootstrap();",
    "",
    "$modelClass = getenv('INSTALAR_ADMIN_MODEL') ?: 'App\\\\Models\\\\User';",
    "$name = getenv('INSTALAR_ADMIN_NAME') ?: '';",
    "$email = getenv('INSTALAR_ADMIN_EMAIL') ?: '';",
    "$password = getenv('INSTALAR_ADMIN_PASSWORD') ?: '';",
    "",
    "if (!class_exists($modelClass)) {",
    "    fwrite(STDERR, \"Admin model not found: {$modelClass}\\n\");",
    "    exit(1);",
    "}",
    "",
    "$model = new $modelClass();",
    "$attributes = [",
    "    'name' => $name,",
    "    'email' => $email,",
    "    'password' => Hash::make($password),",
    "];",
    "",
    "if (method_exists($model, 'getTable') && Schema::hasColumn($model->getTable(), 'email_verified_at')) {",
    "    $attributes['email_verified_at'] = date('Y-m-d H:i:s');",
    "}",
    "",
    "$user = $modelClass::query()->firstOrNew(['email' => $email]);",
    "$user->forceFill($attributes);",
    "$user->save();",
    "",
    "fwrite(STDOUT, \"Filament admin user ready.\\n\");",
    "",
  ].join("\n");
}

async function createFilamentAdminUser(projectDir, config) {
  const tempRunnerPath = path.join(
    os.tmpdir(),
    `instalar-filament-admin-${crypto.randomUUID()}.php`,
  );
  const adminModel = resolveAuthUserModel(projectDir);

  fs.writeFileSync(tempRunnerPath, buildFilamentAdminBootstrapScript(), "utf8");

  try {
    // Secrets travel through environment variables here so they can still be
    // redacted from command logs while remaining available to the PHP script.
    const result = await runCommand("php", [tempRunnerPath], {
      cwd: projectDir,
      required: false,
      env: {
        ...process.env,
        INSTALAR_ADMIN_MODEL: adminModel,
        INSTALAR_ADMIN_NAME: config.admin.name,
        INSTALAR_ADMIN_EMAIL: config.admin.email,
        INSTALAR_ADMIN_PASSWORD: config.admin.password,
      },
      redactedValues: [config.admin.password],
      successLabel: "Filament admin user ready",
    });

    if (result.success) {
      state.createdAdmin = {
        name: config.admin.name,
        email: config.admin.email,
        password: config.admin.revealPassword ? config.admin.password : null,
        passwordSource: config.admin.passwordSource,
        revealPassword: Boolean(config.admin.revealPassword),
      };
    }

    return result.success;
  } finally {
    fs.rmSync(tempRunnerPath, { force: true });
  }
}

// =============================================================================
// Install and Update Flows
// =============================================================================
// Runs package-specific setup commands, migrations, and optional admin creation.
async function runSetupCommands(projectDir, packages, config) {
  section("Setup Commands");

  // Key generation is safe to attempt on every run because Laravel will simply
  // rewrite the key in the current .env when the command succeeds.
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
      await runPotentiallyInteractiveArtisanCommand(
        projectDir,
        "reverb:install",
        [],
        "reverb:install not available, skipping.",
        {
          warnOnFailure: false,
          skipMessage:
            "Skipping reverb:install in non-interactive mode. Run 'php artisan reverb:install' manually.",
          interactiveNotice: "Reverb install may ask interactive questions.",
        },
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
    await runPotentiallyInteractiveArtisanCommand(
      projectDir,
      "modules:install",
      [],
      "modules:install not available, skipping.",
      {
        warnOnFailure: false,
        skipMessage:
          "Skipping modules:install in non-interactive mode. Run 'php artisan modules:install' manually.",
        interactiveNotice: "modules:install may ask interactive questions.",
      },
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
    const created = await createFilamentAdminUser(projectDir, config);
    if (!created) {
      warnFinal("Could not create the Filament admin user automatically.");
    }
  }
}

// Lets guided manual mode confirm the grouped review before execution starts.
async function reviewManualConfig(config, runtimeOptions = state.runtime) {
  const totalSteps = 6;

  while (true) {
    printStepCard(
      totalSteps,
      totalSteps,
      "Review",
      "Final checkpoint before INSTALAR creates, replaces, or updates anything.",
    );
    printInstallPlan(config, runtimeOptions);

    const action = await askChoice(
      "Review action",
      ["Start installation", "Revise answers", "Cancel run"],
      0,
    );

    if (action === 0) {
      return "start";
    }

    if (action === 1) {
      return "retry";
    }

    throw new Error("Cancelled by user.");
  }
}

// Runs full installation workflow for new projects.
async function runInstallFlow(config, runtimeOptions = state.runtime, flowOptions = {}) {
  const { skipPlanPrint = false, skipConfirmPrompt = false } = flowOptions;
  // The printed plan doubles as the source of truth for unattended runs, so the
  // workflow always resolves the package set from the same config object first.
  const packageSet = skipPlanPrint
    ? packageSetFromConfig(config)
    : printInstallPlan(config, runtimeOptions);

  if (!runtimeOptions.nonInteractive && !skipConfirmPrompt) {
    const proceed = await askYesNo("Start installation with this plan", true);
    if (!proceed) {
      throw new Error("Cancelled by user.");
    }
  }

  section("Create Project");

  const resolvedProjectPath = path.resolve(config.projectPath);
  ensureSafeProjectTarget(resolvedProjectPath);

  if (fs.existsSync(config.projectPath)) {
    const pathClassification = classifyExistingPath(config.projectPath);
    let shouldDelete = false;

    if (runtimeOptions.nonInteractive) {
      shouldDelete = canDeleteExistingPathNonInteractive(pathClassification, runtimeOptions);
      if (!shouldDelete) {
        if (pathClassification === "git-repo" || pathClassification === "generic-nonempty") {
          throw new Error(
            `Non-interactive replacement blocked for ${describePathClassification(
              pathClassification,
            )}. Use --allow-delete-any-existing to continue.`,
          );
        }

        throw new Error(
          `Non-interactive replacement blocked for ${describePathClassification(
            pathClassification,
          )}. Use --allow-delete-existing to continue.`,
        );
      }

      info(
        `[non-interactive] Existing path (${describePathClassification(
          pathClassification,
        )}) will be replaced: ${config.projectPath}`,
      );
    } else {
      shouldDelete = await askYesNo(
        `Path already exists (${describePathClassification(
          pathClassification,
        )}). Delete and recreate it? (${config.projectPath})`,
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
    // Composer needs a refresh when module-level composer.json files were wired
    // in after the initial require step.
    await runCommand("composer", ["dump-autoload", "--no-interaction"], {
      cwd: config.projectPath,
      required: false,
    });
  }

  await runSetupCommands(config.projectPath, packageSet, config);
  printNwidartSetupSummary(config.projectPath, packageSet);

  state.boostInstallSkipped = false;
  if (packageSet.has("laravel/boost")) {
    if (runtimeOptions.skipBoostInstall) {
      state.boostInstallSkipped = true;
      warnFinal("Skipping boost:install. Run 'php artisan boost:install' manually when ready.");
    } else {
      section("Install Boost");
      info("boost:install is interactive. Please confirm settings now.");
      await runCommand("php", ["artisan", "boost:install"], {
        cwd: config.projectPath,
        required: true,
        interactive: true,
        captureOutput: false,
      });
    }
  }

  section("Optimize");
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
  const packages = readComposerPackages(projectDir);
  const dependencyStrategy = resolveUpdateDependencyStrategy(state.runtime);
  printUpdatePlan(projectDir, packages, state.runtime);

  if (!state.runtime.nonInteractive) {
    const proceed = await askYesNo("Start update with this plan", true);
    if (!proceed) {
      throw new Error("Cancelled by user.");
    }
  }

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

  section("Composer Dependencies");
  await runCommand(dependencyStrategy.command, dependencyStrategy.args, {
    cwd: projectDir,
    required: true,
  });
  await runCommand("php", ["artisan", "migrate", "--force", "--no-interaction"], {
    cwd: projectDir,
    required: true,
  });

  if (packages.has("laravel/boost")) {
    state.boostInstallSkipped = false;
    if (state.runtime.skipBoostInstall) {
      state.boostInstallSkipped = true;
      warnFinal("Skipping boost:install. Run 'php artisan boost:install' manually when ready.");
    } else {
      section("Install Boost");
      info("boost:install is interactive.");
      await runCommand("php", ["artisan", "boost:install"], {
        cwd: projectDir,
        required: true,
        interactive: true,
        captureOutput: false,
      });
    }
  } else {
    warn("laravel/boost is not installed. Skipping boost:install.");
  }

  section("Optimize");
  await runCommand("php", ["artisan", "optimize", "--no-interaction"], {
    cwd: projectDir,
    required: false,
  });

  section("Frontend Build");
  await runCommand("npm", ["install"], { cwd: projectDir, required: true });
  await runCommand("npm", ["run", "build"], { cwd: projectDir, required: true });
}

// =============================================================================
// Final Checks and Entrypoint
// =============================================================================
// Prints final success output including admin credentials and accumulated warnings.
function printFinalNotes(projectPath, runtimeOptions = state.runtime) {
  section("Run Complete");
  ok("INSTALAR finished successfully.");
  printReviewSection("Project Ready", [
    ["Project path", projectPath],
    ["Log file", runtimeOptions.logFile || "-"],
  ]);

  const nextSteps = [`cd ${projectPath}`, "php artisan serve"];
  if (!runtimeOptions.startServer) {
    nextSteps.push("composer run dev");
  }
  if (state.boostInstallSkipped) {
    nextSteps.push("php artisan boost:install");
  }
  printBulletSection("Run Next", nextSteps);

  if (state.createdAdmin) {
    const adminEntries = [
      ["Name", state.createdAdmin.name],
      ["Email", state.createdAdmin.email],
      [
        "Password",
        state.createdAdmin.revealPassword ? state.createdAdmin.password : "(hidden)",
      ],
    ];

    if (!state.createdAdmin.revealPassword && state.createdAdmin.passwordSource === "default") {
      adminEntries.push(["Note", "Rotate the default password immediately."]);
    }

    printReviewSection("Admin Access", adminEntries);
  }

  if (state.finalWarnings.length > 0) {
    printBulletSection("Open Warnings", state.finalWarnings);
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

function summarizeCheckResults(results) {
  const failedChecks = [];
  let passedCount = 0;
  let repairedCount = 0;

  for (const result of results) {
    if (result.repaired) {
      repairedCount += 1;
    }

    if (result.ok) {
      passedCount += 1;
      continue;
    }

    for (const label of result.failures) {
      if (!failedChecks.includes(label)) {
        failedChecks.push(label);
      }
    }
  }

  return {
    results,
    passedCount,
    failedCount: results.length - passedCount,
    repairedCount,
    totalCount: results.length,
    failedChecks,
  };
}

function doctorRepairAllowed(runtimeOptions, repairMode = "none") {
  return (
    repairMode === "doctor" &&
    !runtimeOptions.nonInteractive &&
    !runtimeOptions.printPlan
  );
}

async function restoreEnvFromExample(projectPath, runtimeOptions, repairMode = "none") {
  const envPath = path.join(projectPath, ".env");
  const envExamplePath = path.join(projectPath, ".env.example");

  if (fs.existsSync(envPath)) {
    return false;
  }

  if (!fs.existsSync(envExamplePath)) {
    warn(".env.example not found - cannot restore .env automatically");
    return false;
  }

  if (!doctorRepairAllowed(runtimeOptions, repairMode)) {
    return false;
  }

  const shouldRestore = await askYesNo("Restore .env from .env.example now?", true);
  if (!shouldRestore) {
    return false;
  }

  try {
    fs.copyFileSync(envExamplePath, envPath);
    ok(".env restored from .env.example");
    return true;
  } catch {
    warn(".env restore failed - copy .env.example manually");
    return false;
  }
}

async function runDoctorCacheRepair(projectPath, runtimeOptions, healthChecks, results, repairMode = "none") {
  if (!doctorRepairAllowed(runtimeOptions, repairMode)) {
    return results;
  }

  const repairableIndexes = healthChecks
    .map((healthCheck, index) =>
      healthCheck.doctorRepair === "cache-reset" && !results[index].ok ? index : -1,
    )
    .filter((index) => index >= 0);

  if (repairableIndexes.length === 0) {
    return results;
  }

  const shouldRepair = await askYesNo("Clear and rebuild Laravel caches now?", true);
  if (!shouldRepair) {
    return results;
  }

  const clearResult = await runCommand("php", ["artisan", "optimize:clear", "--no-interaction"], {
    cwd: projectPath,
    required: false,
    warnOnFailure: false,
  });
  const optimizeResult = await runCommand("php", ["artisan", "optimize", "--no-interaction"], {
    cwd: projectPath,
    required: false,
    warnOnFailure: false,
  });

  if (!clearResult.success || !optimizeResult.success) {
    warn("Cache repair failed - run 'php artisan optimize:clear && php artisan optimize' manually");
    return results;
  }

  ok("Laravel caches cleared and rebuilt successfully");

  let repairRecorded = false;
  for (const index of repairableIndexes) {
    const rerunResult = await healthChecks[index].run();
    if (rerunResult.ok) {
      rerunResult.repaired = !repairRecorded;
      repairRecorded = true;
    }
    results[index] = rerunResult;
  }

  return results;
}

async function runStorageLinkHealthCheck(projectPath, runtimeOptions, repairMode = "none") {
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
    return {
      name: "Storage link",
      ok: true,
      repaired: false,
      failures: [],
    };
  }

  if (repairMode === "finalize") {
    warn("Storage link missing - attempting to create");
    const linkResult = await runCommand("php", ["artisan", "storage:link", "--no-interaction"], {
      cwd: projectPath,
      required: false,
      warnOnFailure: false,
    });

    if (linkResult.success) {
      ok("Storage link created successfully");
      return {
        name: "Storage link",
        ok: true,
        repaired: true,
        failures: [],
      };
    }

    warn("Failed to create storage link - you can run 'php artisan storage:link' manually");
    if (runtimeOptions.nonInteractive) {
      return {
        name: "Storage link",
        ok: false,
        repaired: false,
        failures: ["Storage link"],
      };
    }

    const retry = await askYesNo("Try again?", false);
    if (!retry) {
      return {
        name: "Storage link",
        ok: false,
        repaired: false,
        failures: ["Storage link"],
      };
    }

    const retryResult = await runCommand("php", ["artisan", "storage:link", "--no-interaction"], {
      cwd: projectPath,
      required: false,
      warnOnFailure: false,
    });

    if (retryResult.success) {
      ok("Storage link created successfully");
      return {
        name: "Storage link",
        ok: true,
        repaired: true,
        failures: [],
      };
    }

    return {
      name: "Storage link",
      ok: false,
      repaired: false,
      failures: ["Storage link"],
    };
  }

  warn("Storage link missing");

  if (doctorRepairAllowed(runtimeOptions, repairMode)) {
    const shouldRepair = await askYesNo("Create storage link now?", true);
    if (!shouldRepair) {
      return {
        name: "Storage link",
        ok: false,
        repaired: false,
        failures: ["Storage link"],
      };
    }

    const repairResult = await runCommand("php", ["artisan", "storage:link", "--no-interaction"], {
      cwd: projectPath,
      required: false,
      warnOnFailure: false,
    });

    if (repairResult.success) {
      ok("Storage link created successfully");
      return {
        name: "Storage link",
        ok: true,
        repaired: true,
        failures: [],
      };
    }

    warn("Storage link repair failed - run 'php artisan storage:link' manually");
  }

  return {
    name: "Storage link",
    ok: false,
    repaired: false,
    failures: ["Storage link"],
  };
}

async function runHealthCheckSuite(projectPath, runtimeOptions = state.runtime, options = {}) {
  section(options.sectionTitle || "Health Check");

  const envPath = path.join(projectPath, ".env");
  const manifestPath = path.join(projectPath, "public", "build", "manifest.json");
  const healthChecks = [
    {
      name: "APP_KEY",
      run: async () => {
        let envRestored = false;
        if (!fs.existsSync(envPath)) {
          warn(".env file not found");

          envRestored = await restoreEnvFromExample(
            projectPath,
            runtimeOptions,
            options.repairMode || "none",
          );
        }

        if (!fs.existsSync(envPath)) {
          return {
            name: "APP_KEY",
            ok: false,
            repaired: envRestored,
            failures: [".env"],
          };
        }

        const envContent = fs.readFileSync(envPath, "utf8");
        const appKeyMatch = envContent.match(/^APP_KEY=base64:[A-Za-z0-9+\/=]+$/m);
        if (appKeyMatch) {
          ok("APP_KEY is set");
          return { name: "APP_KEY", ok: true, repaired: envRestored, failures: [] };
        }

        warn("APP_KEY is missing - run 'php artisan key:generate'");
        return {
          name: "APP_KEY",
          ok: false,
          repaired: envRestored,
          failures: ["APP_KEY"],
        };
      },
    },
    {
      name: "Database",
      run: async () => {
        const dbCheck = await runCommand("php", ["artisan", "db:show", "--no-interaction"], {
          cwd: projectPath,
          required: false,
          warnOnFailure: false,
        });

        if (dbCheck.exitCode === 0) {
          ok("Database connection check passed");
          return { name: "Database", ok: true, repaired: false, failures: [] };
        }

        warn("Database connection check failed");
        return {
          name: "Database",
          ok: false,
          repaired: false,
          failures: ["Database"],
        };
      },
    },
    {
      name: "Storage link",
      run: async () =>
        runStorageLinkHealthCheck(projectPath, runtimeOptions, options.repairMode || "none"),
    },
    {
      name: "Composer validate",
      run: async () => {
        const composerValidate = await runCommand("composer", ["validate", "--no-interaction"], {
          cwd: projectPath,
          required: false,
          warnOnFailure: false,
        });

        if (composerValidate.exitCode === 0) {
          ok("Composer.json is valid");
          return {
            name: "Composer validate",
            ok: true,
            repaired: false,
            failures: [],
          };
        }

        warn("Composer.json validation failed");
        return {
          name: "Composer validate",
          ok: false,
          repaired: false,
          failures: ["Composer"],
        };
      },
    },
    {
      name: "Artisan about",
      doctorRepair: "cache-reset",
      run: async () => {
        const result = await runCommand("php", ["artisan", "about", "--no-interaction"], {
          cwd: projectPath,
          required: false,
          warnOnFailure: false,
        });

        if (result.exitCode === 0) {
          ok("Artisan about check passed");
          return {
            name: "Artisan about",
            ok: true,
            repaired: false,
            failures: [],
          };
        }

        warn("Artisan about check failed");
        return {
          name: "Artisan about",
          ok: false,
          repaired: false,
          failures: ["php artisan about"],
        };
      },
    },
    {
      name: "Migration status",
      doctorRepair: "cache-reset",
      run: async () => {
        const result = await runCommand("php", ["artisan", "migrate:status", "--no-interaction"], {
          cwd: projectPath,
          required: false,
          warnOnFailure: false,
        });

        if (result.exitCode === 0) {
          ok("Migration status check passed");
          return {
            name: "Migration status",
            ok: true,
            repaired: false,
            failures: [],
          };
        }

        warn("Migration status check failed");
        return {
          name: "Migration status",
          ok: false,
          repaired: false,
          failures: ["php artisan migrate:status"],
        };
      },
    },
    {
      name: "Route list",
      doctorRepair: "cache-reset",
      run: async () => {
        const result = await runCommand("php", ["artisan", "route:list", "--no-interaction"], {
          cwd: projectPath,
          required: false,
          warnOnFailure: false,
        });

        if (result.exitCode === 0) {
          ok("Route list check passed");
          return {
            name: "Route list",
            ok: true,
            repaired: false,
            failures: [],
          };
        }

        warn("Route list check failed");
        return {
          name: "Route list",
          ok: false,
          repaired: false,
          failures: ["php artisan route:list"],
        };
      },
    },
    {
      name: "Vite manifest",
      run: async () => {
        if (fs.existsSync(manifestPath)) {
          ok("Vite manifest found (public/build/manifest.json)");
          return {
            name: "Vite manifest",
            ok: true,
            repaired: false,
            failures: [],
          };
        }

        warn("Vite manifest missing: public/build/manifest.json");
        return {
          name: "Vite manifest",
          ok: false,
          repaired: false,
          failures: ["Vite manifest"],
        };
      },
    },
  ];

  const results = [];
  for (const healthCheck of healthChecks) {
    results.push(await healthCheck.run());
  }

  await runDoctorCacheRepair(
    projectPath,
    runtimeOptions,
    healthChecks,
    results,
    options.repairMode || "none",
  );
  return summarizeCheckResults(results);
}

// Runs post-install health checks for key artisan commands and frontend manifest.
async function runHealthChecks(projectPath, runtimeOptions = state.runtime) {
  const report = await runHealthCheckSuite(projectPath, runtimeOptions, {
    sectionTitle: "Health Check",
    repairMode: "finalize",
  });

  if (report.failedChecks.length > 0) {
    console.log("");
    const failedList = report.failedChecks.join(", ");
    fail(`Health check failed for: ${failedList}`);
    console.log("");

    if (runtimeOptions.nonInteractive) {
      if (runtimeOptions.continueOnHealthCheckFailure) {
        recordFinalWarning(`Health checks still failing: ${failedList}`);
        warn("Continuing because health-check override is enabled for non-interactive mode.");
        return report;
      }

      fail("Installation aborted because health checks failed in non-interactive mode.");
      process.exit(1);
    }

    const shouldContinue = await askYesNo("Do you want to continue anyway?", false);
    if (!shouldContinue) {
      fail("Installation aborted by user due to failed health checks.");
      process.exit(1);
    }
    recordFinalWarning(`Health checks still failing: ${failedList}`);
    info("Continuing despite health check failures...");
  }

  return report;
}

function runPermissionChecks(projectPath, options = {}) {
  section(options.sectionTitle || "Permissions");

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

  const results = [];
  let hasPermissionIssues = false;

  for (const check of checks) {
    if (!fs.existsSync(check.targetPath)) {
      hasPermissionIssues = true;
      warn(`${check.label} missing: ${check.targetPath}`);
      results.push({
        name: check.label,
        ok: false,
        repaired: false,
        failures: [check.label],
      });
      continue;
    }

    if (checkAccess(check.targetPath, check.mode)) {
      ok(`${check.label} ok (${check.hint})`);
      results.push({
        name: check.label,
        ok: true,
        repaired: false,
        failures: [],
      });
      continue;
    }

    hasPermissionIssues = true;
    warn(`${check.label} has insufficient permissions (${check.hint})`);
    results.push({
      name: check.label,
      ok: false,
      repaired: false,
      failures: [check.label],
    });
  }

  if (hasPermissionIssues) {
    warn("Tip: check permissions, e.g. chmod -R ug+rw storage bootstrap/cache");
  }

  return summarizeCheckResults(results);
}

function collectDoctorSuggestions(healthReport, permissionReport) {
  const failedChecks = new Set([...healthReport.failedChecks, ...permissionReport.failedChecks]);
  const suggestions = [];
  const addSuggestion = (condition, suggestion) => {
    if (condition && !suggestions.includes(suggestion)) {
      suggestions.push(suggestion);
    }
  };

  addSuggestion(failedChecks.has("APP_KEY"), "Run `php artisan key:generate`.");
  addSuggestion(failedChecks.has("Database"), "Review DB settings and run `php artisan db:show`.");
  addSuggestion(failedChecks.has("Storage link"), "Run `php artisan storage:link`.");
  addSuggestion(failedChecks.has("Composer"), "Run `composer validate` and fix composer.json errors.");
  addSuggestion(
    failedChecks.has("php artisan about") ||
      failedChecks.has("php artisan migrate:status") ||
      failedChecks.has("php artisan route:list"),
    "Run `php artisan optimize:clear && php artisan optimize`.",
  );
  addSuggestion(
    failedChecks.has("php artisan about"),
    "Run `php artisan about` and fix the reported Laravel boot error.",
  );
  addSuggestion(
    failedChecks.has("php artisan migrate:status"),
    "Run `php artisan migrate:status` and resolve pending migration issues.",
  );
  addSuggestion(
    failedChecks.has("php artisan route:list"),
    "Run `php artisan route:list` and fix the reported route or container error.",
  );
  addSuggestion(failedChecks.has("Vite manifest"), "Run `npm install && npm run build`.");
  addSuggestion(
    failedChecks.has("project directory"),
    "Verify project ownership and directory permissions.",
  );
  addSuggestion(
    failedChecks.has("storage") || failedChecks.has("bootstrap/cache"),
    "Run `chmod -R ug+rw storage bootstrap/cache` and verify ownership.",
  );
  addSuggestion(failedChecks.has(".env"), "Create or restore `.env` and make it writable.");

  return suggestions;
}

function printDoctorSummary(projectPath, healthReport, permissionReport) {
  section("Doctor Report");
  printReviewSection("Diagnosis", [
    ["Project", projectPath],
    ["Health checks", `${healthReport.passedCount}/${healthReport.totalCount} passed`],
    ["Permission checks", `${permissionReport.passedCount}/${permissionReport.totalCount} passed`],
    ["Repairs applied", healthReport.repairedCount > 0 ? String(healthReport.repairedCount) : "0"],
  ]);

  const unresolvedIssues = [...new Set([
    ...healthReport.failedChecks,
    ...permissionReport.failedChecks,
  ])];

  if (unresolvedIssues.length === 0) {
    ok("Doctor found no remaining issues.");
    return true;
  }

  fail(`Doctor found unresolved issues: ${unresolvedIssues.join(", ")}`);
  printBulletSection("Needs Attention", unresolvedIssues);

  const suggestions = collectDoctorSuggestions(healthReport, permissionReport);
  if (suggestions.length > 0) {
    printBulletSection("Recommended Fixes", suggestions);
  }

  return false;
}

// Verifies essential filesystem permissions and optionally starts the dev server.
async function runFinalPermissionAndServerStep(projectPath, runtimeOptions = state.runtime) {
  const permissionReport = runPermissionChecks(projectPath, { sectionTitle: "Permissions" });
  if (permissionReport.failedChecks.length > 0) {
    recordFinalWarning(
      `Permission checks need attention: ${permissionReport.failedChecks.join(", ")}`,
    );
    printFailureSummary(buildPermissionFailureSummary(projectPath, permissionReport));
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
  await runCommand("composer", ["run", "dev"], {
    cwd: projectPath,
    required: false,
    interactive: true,
    captureOutput: false,
  });
}

async function runDoctorFlow(projectPath, runtimeOptions = state.runtime) {
  if (!isLaravelProject(projectPath)) {
    throw new Error("Doctor mode requires a Laravel project in the current directory.");
  }

  const packages = readComposerPackages(projectPath);

  printModeIntro("doctor");
  printReviewSection("Project Snapshot", [
    ["Project", projectPath],
    ["Path type", describePathClassification(classifyExistingPath(projectPath))],
  ]);
  printReviewSection("Run Controls", [
    ["Dry run", runtimeOptions.printPlan ? "yes" : "no"],
    ["Log file", runtimeOptions.logFile || "-"],
    [
      "Repair prompts",
      runtimeOptions.nonInteractive || runtimeOptions.printPlan
        ? "disabled"
        : "enabled for safe fixes",
    ],
  ]);
  printBulletSection("Detected Stack", [...packages].sort(), "No Composer packages detected.");

  const healthReport = await runHealthCheckSuite(projectPath, runtimeOptions, {
    sectionTitle: "Health Check",
    repairMode: runtimeOptions.nonInteractive || runtimeOptions.printPlan ? "none" : "doctor",
  });
  const permissionReport = runPermissionChecks(projectPath, {
    sectionTitle: "Permissions",
  });

  if (packages.has("nwidart/laravel-modules")) {
    section("Nwidart Status");
    printNwidartSetupSummary(projectPath, packages);
  }

  return printDoctorSummary(projectPath, healthReport, permissionReport);
}

// Executes all final post-install steps in order.
async function finalizeProject(projectPath, runtimeOptions = state.runtime) {
  await runHealthChecks(projectPath, runtimeOptions);
  await runFinalPermissionAndServerStep(projectPath, runtimeOptions);
  printFinalNotes(projectPath, runtimeOptions);
}

async function runUpdateMode(projectDir, runtimeOptions = state.runtime) {
  if (!isLaravelProject(projectDir)) {
    throw new Error("Update mode requires a Laravel project in the current directory.");
  }

  resetRunState();

  if (runtimeOptions.printPlan) {
    printUpdatePlan(projectDir, readComposerPackages(projectDir), runtimeOptions);
    return;
  }

  await runUpdateFlow(projectDir);
  await finalizeProject(projectDir, runtimeOptions);
}

async function runDoctorMode(projectDir, runtimeOptions = state.runtime) {
  resetRunState();

  const doctorSucceeded = await runDoctorFlow(projectDir, runtimeOptions);
  if (!doctorSucceeded) {
    process.exitCode = 1;
  }
}

async function runAutoMode(runtimeOptions = state.runtime) {
  resetRunState();
  const config = await collectAutoConfig(getModePreset("auto"));

  if (runtimeOptions.printPlan) {
    printInstallPlan(config, runtimeOptions);
    return;
  }

  await runInstallFlow(config, runtimeOptions);
  await finalizeProject(config.projectPath, runtimeOptions);
}

async function runManualMode(runtimeOptions = state.runtime) {
  while (true) {
    resetRunState();
    const config = await collectManualConfig(getModePreset("manual"));

    if (runtimeOptions.printPlan) {
      printInstallPlan(config, runtimeOptions);
      return;
    }

    const action = await reviewManualConfig(config, runtimeOptions);
    if (action === "retry") {
      continue;
    }

    await runInstallFlow(config, runtimeOptions, {
      skipPlanPrint: true,
      skipConfirmPrompt: true,
    });
    await finalizeProject(config.projectPath, runtimeOptions);
    return;
  }
}

async function runDetectedProjectFlow(projectDir, runtimeOptions = state.runtime) {
  const action = await askChoice(
    "A Laravel project was detected in the current directory",
    ["Update the current project", "Create a new project (Automatic)", "Create a new project (Manual)"],
    0,
  );

  if (action === 0) {
    await runUpdateMode(projectDir, runtimeOptions);
    return;
  }

  if (action === 1) {
    await runAutoMode(runtimeOptions);
    return;
  }

  await runManualMode(runtimeOptions);
}

async function runInteractiveDefaultFlow(projectDir, runtimeOptions = state.runtime) {
  if (isLaravelProject(projectDir)) {
    await runDetectedProjectFlow(projectDir, runtimeOptions);
    return;
  }

  const modeChoice = await askChoice(
    "What do you want to do?",
    ["Automatic setup", "Guided manual setup"],
    0,
  );

  if (modeChoice === 0) {
    await runAutoMode(runtimeOptions);
    return;
  }

  await runManualMode(runtimeOptions);
}

function formatNodeUsageLine(label, description = "") {
  return description ? `  ${label.padEnd(26)} ${description}` : `  ${label}`;
}

// Prints Node-phase usage help.
function printNodeUsage() {
  console.log(`INSTALAR v${SCRIPT_VERSION} (${SCRIPT_CODENAME})`);
  console.log("Modern terminal setup, update, and diagnostics for Laravel + Filament.");
  console.log("Pick the mode that matches the job, review the plan, then run with confidence.");
  console.log("");
  console.log("Usage:");
  console.log("  ./instalar.sh");
  console.log("  ./instalar.sh --help");
  console.log("  ./instalar.sh --non-interactive --config instalar.json");
  console.log("");
  console.log("Start here:");
  INSTALLER_MODE_DEFINITIONS.forEach((mode) => {
    console.log(formatNodeUsageLine(mode.id, mode.startHere));
  });
  console.log("");
  console.log("Modes:");
  INSTALLER_MODE_DEFINITIONS.forEach((mode) => {
    console.log(formatNodeUsageLine(mode.id, mode.description));
  });
  console.log("");
  Object.entries(HELP_GROUP_TITLES).forEach(([groupKey, title]) => {
    console.log(`${title}:`);
    RUNTIME_OPTION_DEFINITIONS
      .filter((definition) => definition.helpGroup === groupKey)
      .forEach((definition) => {
        (definition.helpLines || []).forEach(([label, description]) => {
          console.log(formatNodeUsageLine(label, description));
        });
      });
    console.log("");
  });
  console.log("Examples:");
  NODE_USAGE_EXAMPLES.forEach((example) => {
    console.log(`  ${example}`);
  });
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
  } else {
    const defaultConfigPath = path.resolve(process.cwd(), "instalar.json");
    if (fs.existsSync(defaultConfigPath)) {
      const loaded = loadInstallerConfig(defaultConfigPath);
      loadedConfig = loaded.config || {};
      resolvedConfigPath = loaded.path;
    }
  }

  state.runtime = resolveRuntime(cliOptions, loadedConfig, resolvedConfigPath);
  initializeRuntimeLog();

  if (state.runtime.logFile) {
    info(`Writing installer log to: ${state.runtime.logFile}`);
  }

  if (resolvedConfigPath) {
    info(`Loaded configuration: ${resolvedConfigPath}`);
  }

  if (state.runtime.mode === "doctor") {
    warnDoctorModeIgnoredOptions(cliOptions, loadedConfig);
  }

  if (!state.runtime.nonInteractive && !process.stdin.isTTY) {
    throw new Error(
      "No interactive terminal detected. Use --non-interactive for unattended runs.",
    );
  }

  const cwd = process.cwd();
  const hasLaravelProject = isLaravelProject(cwd);
  let mode = state.runtime.mode;

  // Unattended runs must never stall waiting for a mode choice, so the current
  // working directory decides between update and auto-install when mode is unset.
  if (!mode && state.runtime.nonInteractive) {
    mode = hasLaravelProject ? "update" : "auto";
    info(`[non-interactive] No mode set, using: ${mode}`);
  }

  if (mode === "update") {
    await runUpdateMode(cwd, state.runtime);
    return;
  }

  if (mode === "doctor") {
    await runDoctorMode(cwd, state.runtime);
    return;
  }

  if (mode === "auto") {
    await runAutoMode(state.runtime);
    return;
  }

  if (mode === "manual") {
    await runManualMode(state.runtime);
    return;
  }

  await runInteractiveDefaultFlow(cwd, state.runtime);
}

// Global top-level error handler for the Node phase.
main().catch((error) => {
  section("Run Stopped");
  fail(error.message || String(error));
  if (error.failureSummary) {
    printFailureSummary(error.failureSummary);
  }
  if (error.outputSnippet) {
    printCommandFailureSnippet(error.outputSnippet);
  }
  process.exitCode = 1;
});
NODE

# Route Node stdin to /dev/tty when available so prompts still work after curl|bash piping.
NODE_STDIN="/dev/stdin"
if (( BASH_HAS_TTY == 1 )); then
  NODE_STDIN="/dev/tty"
fi

# Execute embedded Node phase with original CLI args.
if INSTALAR_SCRIPT_VERSION="${SCRIPT_VERSION}" INSTALAR_SCRIPT_CODENAME="${SCRIPT_CODENAME}" \
  node "${NODE_TMP}" "$@" < "${NODE_STDIN}"; then
  exit 0
else
  exit $?
fi
