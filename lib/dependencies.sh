#!/bin/bash
#
# Dependency Auto-Installation Module
# Part of VLESS+Reality VPN Deployment System
#
# Purpose: Check and auto-install all required dependencies with extended Docker diagnostics
# Supports: Ubuntu 20.04+, Debian 10+
# Usage: source this file from install.sh (after os_detection.sh)
#
# Dependencies from os_detection.sh:
#   - OS_NAME: Operating system name
#   - OS_VERSION: OS version number
#   - OS_ID: OS identifier (ubuntu/debian)
#   - PKG_MANAGER: Package manager (apt/apt-get)
#
# Exit codes:
#   0 = success
#   1 = general error
#   3 = dependency error
#

# Only set strict mode if not already set (to avoid issues when sourced)
[[ ! -o pipefail ]] && set -euo pipefail || true

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

# Required packages for VLESS+Reality system
REQUIRED_PACKAGES=(
    "docker.io"
    "docker-compose-plugin"
    "ufw"
    "jq"
    "qrencode"
    "curl"
    "openssl"
)

# Optional packages (non-critical, system works without them)
# v3.2: netcat for healthchecks, fail2ban for public proxy protection
# v3.3: certbot for Let's Encrypt TLS certificates (public proxy only)
OPTIONAL_PACKAGES=(
    "netcat-openbsd"  # For Docker healthchecks (fallback: netcat-traditional, ncat)
    "fail2ban"        # Brute-force protection for public proxy
    "certbot"         # Let's Encrypt client for TLS certificates (v3.3 public proxy)
    "dnsutils"        # DNS tools (dig) for certificate validation
)

# Ensure it's properly declared as array for export
declare -ga REQUIRED_PACKAGES
declare -ga OPTIONAL_PACKAGES

# Minimum version requirements
readonly DOCKER_MIN_VERSION="20.10"
readonly DOCKER_COMPOSE_MIN_VERSION="1.29"
readonly JQ_MIN_VERSION="1.5"

# Color codes (inherited from os_detection.sh but redefined for standalone use if needed)
# Only define if not already set (to avoid conflicts when sourced after os_detection.sh)
# Note: Using non-readonly to avoid conflicts with os_detection.sh readonly declarations
[[ -z "${RED:-}" ]] && RED='\033[0;31m'
[[ -z "${GREEN:-}" ]] && GREEN='\033[0;32m'
[[ -z "${YELLOW:-}" ]] && YELLOW='\033[1;33m'
[[ -z "${BLUE:-}" ]] && BLUE='\033[0;34m'
[[ -z "${NC:-}" ]] && NC='\033[0m' # No Color
[[ -z "${CYAN:-}" ]] && CYAN='\033[0;36m'

# Progress symbols (non-readonly to avoid conflicts)
CHECK_MARK='\u2713'  # ✓
CROSS_MARK='\u2717'  # ✗
WARNING_MARK='\u26A0' # ⚠

# =============================================================================
# HELPER FUNCTION: version_compare
# =============================================================================
# Description: Compare two version strings (semantic versioning)
# Parameters:
#   $1: version1
#   $2: version2
# Returns: 0 if version1 >= version2, 1 otherwise
# Example: version_compare "20.10.5" "20.10" returns 0
# =============================================================================
version_compare() {
    local version1="$1"
    local version2="$2"

    # Remove leading 'v' if present
    version1="${version1#v}"
    version2="${version2#v}"

    # Split versions into arrays
    IFS='.' read -ra v1_parts <<< "$version1"
    IFS='.' read -ra v2_parts <<< "$version2"

    # Compare each part
    local max_parts=${#v1_parts[@]}
    [[ ${#v2_parts[@]} -gt $max_parts ]] && max_parts=${#v2_parts[@]}

    for ((i=0; i<max_parts; i++)); do
        local part1=${v1_parts[i]:-0}
        local part2=${v2_parts[i]:-0}

        # Remove non-numeric suffixes (e.g., "20.10.5-ce" -> "20.10.5")
        part1=$(echo "$part1" | grep -oE '^[0-9]+')
        part2=$(echo "$part2" | grep -oE '^[0-9]+')

        if [[ $part1 -gt $part2 ]]; then
            return 0
        elif [[ $part1 -lt $part2 ]]; then
            return 1
        fi
    done

    return 0  # Versions are equal
}

# =============================================================================
# FUNCTION: check_package_version
# =============================================================================
# Description: Check if installed package meets minimum version requirement
# Parameters:
#   $1: package_name
#   $2: min_version
# Returns: 0 if version OK or no version check needed, 1 if too old or not found
# =============================================================================
check_package_version() {
    local package_name="$1"
    local min_version="$2"

    case "$package_name" in
        docker.io|docker)
            # Get Docker version
            if ! command -v docker &>/dev/null; then
                return 1
            fi

            local docker_version
            docker_version=$(docker --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -n1)

            if [[ -z "$docker_version" ]]; then
                echo -e "${YELLOW}WARNING: Cannot determine Docker version${NC}" >&2
                return 1
            fi

            if ! version_compare "$docker_version" "$min_version"; then
                echo -e "${RED}ERROR: Docker version $docker_version is below minimum $min_version${NC}" >&2
                return 1
            fi
            ;;

        docker-compose-plugin)
            # Get docker compose version (v2 uses "docker compose" command)
            if ! docker compose version &>/dev/null 2>&1; then
                return 1
            fi

            local compose_version
            compose_version=$(docker compose version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -n1)

            if [[ -z "$compose_version" ]]; then
                echo -e "${YELLOW}WARNING: Cannot determine docker compose version${NC}" >&2
                return 1
            fi

            if ! version_compare "$compose_version" "$min_version"; then
                echo -e "${RED}ERROR: docker compose version $compose_version is below minimum $min_version${NC}" >&2
                return 1
            fi
            ;;

        jq)
            # Get jq version
            if ! command -v jq &>/dev/null; then
                return 1
            fi

            local jq_version
            jq_version=$(jq --version 2>/dev/null | grep -oP '\d+\.\d+' | head -n1)

            if [[ -z "$jq_version" ]]; then
                echo -e "${YELLOW}WARNING: Cannot determine jq version${NC}" >&2
                return 1
            fi

            if ! version_compare "$jq_version" "$min_version"; then
                echo -e "${RED}ERROR: jq version $jq_version is below minimum $min_version${NC}" >&2
                return 1
            fi
            ;;

        *)
            # For other packages, just check if command exists
            if ! command -v "$package_name" &>/dev/null; then
                return 1
            fi
            ;;
    esac

    return 0
}

# =============================================================================
# FUNCTION: install_package
# =============================================================================
# Description: Install a single package using detected package manager
# Parameters:
#   $1: package_name
# Returns: 0 on success, 1 on failure
# Suppresses all apt prompts (DEBIAN_FRONTEND=noninteractive)
# =============================================================================
install_package() {
    local package_name="$1"

    # Ensure PKG_MANAGER is set
    if [[ -z "${PKG_MANAGER:-}" ]]; then
        echo -e "${RED}ERROR: PKG_MANAGER not set. Run get_package_manager() first${NC}" >&2
        return 1
    fi

    # Install with noninteractive mode
    export DEBIAN_FRONTEND=noninteractive

    if ! ${PKG_MANAGER} install -y -qq "$package_name" &>/dev/null; then
        echo -e "${RED}${CROSS_MARK} Failed to install $package_name${NC}" >&2
        return 1
    fi

    return 0
}

# =============================================================================
# FUNCTION: check_dependencies
# =============================================================================
# Description: Check if ALL required dependencies are installed
# Checks command existence and version requirements
# Returns: 0 if all present and meet version requirements, 1 if any missing
# =============================================================================
check_dependencies() {
    echo -e "${BLUE}Checking dependencies...${NC}"
    echo ""

    local missing_count=0
    local version_fail_count=0
    declare -a missing_packages=()
    declare -a version_failed_packages=()

    for package in "${REQUIRED_PACKAGES[@]}"; do
        # Check if command exists
        local cmd_name="$package"
        [[ "$package" == "docker.io" ]] && cmd_name="docker"

        # Special check for docker-compose-plugin (uses "docker compose" command)
        if [[ "$package" == "docker-compose-plugin" ]]; then
            if ! docker compose version &>/dev/null 2>&1; then
                echo -e "  ${CROSS_MARK} ${package} - ${RED}NOT INSTALLED${NC}"
                missing_packages+=("$package")
                ((missing_count++)) || true
                continue
            fi
        elif ! command -v "$cmd_name" &>/dev/null; then
            echo -e "  ${CROSS_MARK} ${package} - ${RED}NOT INSTALLED${NC}"
            missing_packages+=("$package")
            ((missing_count++)) || true
            continue
        fi

        # Check version for specific packages
        local version_ok=1
        case "$package" in
            docker.io)
                if ! check_package_version "docker.io" "$DOCKER_MIN_VERSION"; then
                    version_failed_packages+=("$package (minimum: $DOCKER_MIN_VERSION)")
                    ((version_fail_count++)) || true
                    version_ok=0
                else
                    local docker_version
                    docker_version=$(docker --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -n1)
                    echo -e "  ${CHECK_MARK} ${package} - ${GREEN}installed${NC} (version: $docker_version)"
                fi
                ;;

            docker-compose-plugin)
                if ! check_package_version "docker-compose-plugin" "$DOCKER_COMPOSE_MIN_VERSION"; then
                    version_failed_packages+=("$package (minimum: $DOCKER_COMPOSE_MIN_VERSION)")
                    ((version_fail_count++)) || true
                    version_ok=0
                else
                    local compose_version
                    compose_version=$(docker compose version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -n1)
                    echo -e "  ${CHECK_MARK} ${package} - ${GREEN}installed${NC} (version: $compose_version)"
                fi
                ;;

            jq)
                if ! check_package_version "jq" "$JQ_MIN_VERSION"; then
                    version_failed_packages+=("$package (minimum: $JQ_MIN_VERSION)")
                    ((version_fail_count++)) || true
                    version_ok=0
                else
                    local jq_version
                    jq_version=$(jq --version 2>/dev/null | grep -oP '\d+\.\d+' | head -n1)
                    echo -e "  ${CHECK_MARK} ${package} - ${GREEN}installed${NC} (version: $jq_version)"
                fi
                ;;

            *)
                echo -e "  ${CHECK_MARK} ${package} - ${GREEN}installed${NC}"
                ;;
        esac

        if [[ $version_ok -eq 0 ]]; then
            echo -e "  ${CROSS_MARK} ${package} - ${RED}VERSION TOO OLD${NC}"
        fi
    done

    echo ""

    # Summary
    if [[ $missing_count -eq 0 ]] && [[ $version_fail_count -eq 0 ]]; then
        echo -e "${GREEN}${CHECK_MARK} All dependencies are installed and meet version requirements${NC}"
        return 0
    else
        echo -e "${YELLOW}${WARNING_MARK} Dependency check found issues:${NC}"
        echo ""

        if [[ $missing_count -gt 0 ]]; then
            echo -e "${YELLOW}  Missing packages ($missing_count):${NC}"
            for pkg in "${missing_packages[@]}"; do
                echo -e "${YELLOW}    - $pkg${NC}"
            done
            echo ""
        fi

        if [[ $version_fail_count -gt 0 ]]; then
            echo -e "${YELLOW}  Version requirements not met ($version_fail_count):${NC}"
            for pkg in "${version_failed_packages[@]}"; do
                echo -e "${YELLOW}    - $pkg${NC}"
            done
            echo ""
        fi

        # Interactive prompt to install missing packages
        echo -e "${CYAN}These packages will be installed automatically in the next step.${NC}"

        # Check for non-interactive mode via environment variable
        if [[ "${VLESS_AUTO_INSTALL_DEPS:-}" == "yes" ]]; then
            echo -e "${CYAN}Non-interactive mode: Auto-proceeding to installation${NC}"
            echo ""
            return 0
        fi

        echo -e "${YELLOW}Do you want to continue with automatic installation?${NC}"
        echo -e "${CYAN}  [Y/n] (30s timeout, default=yes): ${NC}"

        local user_response
        if ! read -t 30 -r user_response; then
            user_response="y"
            echo ""
            echo -e "${CYAN}Timeout reached, proceeding with installation${NC}"
        fi

        # Default to yes if empty
        [[ -z "$user_response" ]] && user_response="y"

        case "${user_response,,}" in
            n|no)
                echo -e "${RED}${CROSS_MARK} Installation cancelled by user${NC}"
                echo -e "${YELLOW}To install dependencies manually, run:${NC}"
                echo -e "${YELLOW}  sudo apt update && sudo apt install -y ${missing_packages[*]} ${version_failed_packages[*]}${NC}"
                echo ""
                return 1
                ;;
            *)
                echo -e "${GREEN}Proceeding to automatic installation...${NC}"
                echo ""
                return 0
                ;;
        esac
    fi
}

# =============================================================================
# FUNCTION: install_dependencies
# =============================================================================
# Description: Auto-install ALL missing dependencies
# Uses apt update before installation
# Installs dependencies one by one with progress indicators
# Validates each installation after completion
# No user prompts (fully automated as per Q-001)
# Returns: 0 on success, 1 on failure
# =============================================================================
install_dependencies() {
    echo -e "${BLUE}Installing missing dependencies...${NC}"
    echo ""

    # Ensure PKG_MANAGER is set
    if [[ -z "${PKG_MANAGER:-}" ]]; then
        echo -e "${RED}ERROR: PKG_MANAGER not set. Run get_package_manager() first${NC}" >&2
        return 1
    fi

    # Update package lists
    echo -e "${CYAN}Updating package lists...${NC}"
    export DEBIAN_FRONTEND=noninteractive
    if ! ${PKG_MANAGER} update -qq &>/dev/null; then
        echo -e "${RED}${CROSS_MARK} Failed to update package lists${NC}" >&2
        echo -e "${YELLOW}Suggestion: Check internet connection and run 'sudo ${PKG_MANAGER} update' manually${NC}" >&2
        return 1
    fi
    echo -e "${GREEN}${CHECK_MARK} Package lists updated${NC}"
    echo ""

    # Get total package count (using ${#array[@]:-} would be invalid for arrays)
    # Ensure REQUIRED_PACKAGES is accessible from global scope
    local total_packages=${#REQUIRED_PACKAGES[@]}
    local installed_count=0
    local failed_count=0
    local -a failed_packages=()

    for i in "${!REQUIRED_PACKAGES[@]}"; do
        local package="${REQUIRED_PACKAGES[$i]}"
        local current_num=$((i + 1))

        # Check if already installed
        local cmd_name="$package"
        [[ "$package" == "docker.io" ]] && cmd_name="docker"
        [[ "$package" == "netcat-openbsd" ]] && cmd_name="nc"

        # Special check for docker-compose-plugin
        local is_installed=false
        if [[ "$package" == "docker-compose-plugin" ]]; then
            if docker compose version &>/dev/null 2>&1; then
                is_installed=true
            fi
        elif command -v "$cmd_name" &>/dev/null; then
            is_installed=true
        fi

        if [[ "$is_installed" == "true" ]]; then
            # Check version for specific packages
            case "$package" in
                docker.io)
                    if check_package_version "docker.io" "$DOCKER_MIN_VERSION"; then
                        echo -e "[$current_num/$total_packages] ${CHECK_MARK} $package - ${GREEN}already installed${NC}"
                        ((installed_count++)) || true
                        continue
                    fi
                    ;;
                docker-compose-plugin)
                    if check_package_version "docker-compose-plugin" "$DOCKER_COMPOSE_MIN_VERSION"; then
                        echo -e "[$current_num/$total_packages] ${CHECK_MARK} $package - ${GREEN}already installed${NC}"
                        ((installed_count++)) || true
                        continue
                    fi
                    ;;
                jq)
                    if check_package_version "jq" "$JQ_MIN_VERSION"; then
                        echo -e "[$current_num/$total_packages] ${CHECK_MARK} $package - ${GREEN}already installed${NC}"
                        ((installed_count++)) || true
                        continue
                    fi
                    ;;
                *)
                    echo -e "[$current_num/$total_packages] ${CHECK_MARK} $package - ${GREEN}already installed${NC}"
                    ((installed_count++)) || true
                    continue
                    ;;
            esac
        fi

        # Install package
        echo -e "[$current_num/$total_packages] Installing $package..."

        if install_package "$package"; then
            # Validate installation
            if command -v "$cmd_name" &>/dev/null; then
                echo -e "[$current_num/$total_packages] ${CHECK_MARK} $package - ${GREEN}installed successfully${NC}"
                ((installed_count++)) || true

                # Special handling for Docker
                if [[ "$package" == "docker.io" ]]; then
                    echo -e "  ${CYAN}Enabling and starting Docker service...${NC}"
                    if start_docker_service; then
                        echo -e "  ${GREEN}${CHECK_MARK} Docker service started${NC}"
                    else
                        echo -e "  ${YELLOW}${WARNING_MARK} Docker service may need manual start${NC}"
                    fi
                fi
            else
                echo -e "[$current_num/$total_packages] ${CROSS_MARK} $package - ${RED}installation verification failed${NC}"
                failed_packages+=("$package")
                ((failed_count++)) || true
            fi
        else
            echo -e "[$current_num/$total_packages] ${CROSS_MARK} $package - ${RED}installation failed${NC}"
            failed_packages+=("$package")
            ((failed_count++)) || true
        fi
    done

    # Install optional packages (v3.2)
    echo ""
    echo -e "${CYAN}Installing optional packages...${NC}"

    for package in "${OPTIONAL_PACKAGES[@]}"; do
        # Skip fail2ban if public proxy not enabled
        if [[ "$package" == "fail2ban" && "${ENABLE_PUBLIC_PROXY:-false}" != "true" ]]; then
            echo -e "  ${YELLOW}⊗${NC} $package - skipped (public proxy not enabled)"
            continue
        fi

        # Map package name to command name
        local opt_cmd="$package"
        [[ "$package" == "netcat-openbsd" ]] && opt_cmd="nc"
        [[ "$package" == "fail2ban" ]] && opt_cmd="fail2ban-server"

        # Check if already installed
        if command -v "$opt_cmd" &>/dev/null 2>&1; then
            echo -e "  ${CHECK_MARK} $package - ${GREEN}already installed${NC}"
            continue
        fi

        # Try to install
        echo -e "  Installing $package..."
        if install_package "$package"; then
            if command -v "$opt_cmd" &>/dev/null 2>&1; then
                echo -e "  ${CHECK_MARK} $package - ${GREEN}installed successfully${NC}"
            else
                echo -e "  ${YELLOW}${WARNING_MARK} $package - installed but command not found${NC}"
            fi
        else
            # Handle fallbacks for specific packages
            if [[ "$package" == "netcat-openbsd" ]]; then
                echo -e "  ${YELLOW}${WARNING_MARK} netcat-openbsd not available, trying alternatives...${NC}"

                # Try netcat-traditional
                if install_package "netcat-traditional" 2>/dev/null; then
                    echo -e "  ${CHECK_MARK} netcat-traditional - ${GREEN}installed as fallback${NC}"
                # Try ncat (from nmap package)
                elif command -v ncat &>/dev/null 2>&1; then
                    echo -e "  ${CHECK_MARK} ncat - ${GREEN}already available${NC}"
                else
                    echo -e "  ${YELLOW}${WARNING_MARK} No netcat variant available (healthchecks will be disabled)${NC}"
                fi
            elif [[ "$package" == "fail2ban" ]]; then
                echo -e "  ${YELLOW}${WARNING_MARK} $package - installation failed (will be handled by fail2ban_setup.sh)${NC}"
            else
                echo -e "  ${YELLOW}${WARNING_MARK} $package - installation failed (non-critical)${NC}"
            fi
        fi
    done

    echo ""
    echo -e "${BLUE}Installation Summary:${NC}"
    echo -e "  Total packages: $total_packages"
    echo -e "  Successfully installed: $installed_count"
    echo -e "  Failed: $failed_count"

    if [[ $failed_count -gt 0 ]]; then
        echo ""
        echo -e "${RED}${CROSS_MARK} Failed to install the following packages:${NC}"
        for pkg in "${failed_packages[@]}"; do
            echo -e "${RED}  - $pkg${NC}"
        done
        echo ""
        echo -e "${YELLOW}Suggestion: Try installing manually with:${NC}"
        echo -e "${YELLOW}  sudo ${PKG_MANAGER} install ${failed_packages[*]}${NC}"
        return 1
    fi

    echo ""
    echo -e "${GREEN}${CHECK_MARK} All dependencies installed successfully${NC}"
    return 0
}

# =============================================================================
# FUNCTION: start_docker_service
# =============================================================================
# Description: Enable and start Docker service
# Waits for Docker to be fully ready
# Returns: 0 on success, 1 on failure
# =============================================================================
start_docker_service() {
    # Check if systemctl is available
    if ! command -v systemctl &>/dev/null; then
        echo -e "${YELLOW}WARNING: systemctl not found, cannot manage Docker service${NC}" >&2
        return 1
    fi

    # Enable Docker service (persist across reboots)
    if ! systemctl enable docker &>/dev/null; then
        echo -e "${YELLOW}WARNING: Failed to enable Docker service${NC}" >&2
    fi

    # Start Docker service
    if ! systemctl start docker &>/dev/null; then
        echo -e "${RED}ERROR: Failed to start Docker service${NC}" >&2
        echo -e "${YELLOW}Suggestion: Check Docker installation with 'systemctl status docker'${NC}" >&2
        return 1
    fi

    # Wait for Docker to be ready (max 30 seconds)
    local max_wait=30
    local waited=0

    while ! docker ps &>/dev/null; do
        if [[ $waited -ge $max_wait ]]; then
            echo -e "${RED}ERROR: Docker did not become ready within ${max_wait}s${NC}" >&2
            return 1
        fi
        sleep 1
        ((waited++)) || true
    done

    return 0
}

# =============================================================================
# FUNCTION: validate_docker - EXTENDED DIAGNOSTICS (Q-A3)
# =============================================================================
# Description: Comprehensive Docker validation with extended diagnostics
# Checks:
#   1. Docker version >= 20.10
#   2. /var/run/docker.sock exists and is accessible
#   3. Current user in docker group (if not root)
#   4. Docker daemon is running
#   5. Can run simple test container (docker run hello-world)
#   6. docker-compose version >= 1.29
# Returns: 0 if all checks pass, 1 if any fail
# =============================================================================
validate_docker() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           EXTENDED DOCKER DIAGNOSTICS                         ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local check_count=0
    local failed_count=0
    declare -a failed_checks=()

    # -------------------------------------------------------------------------
    # CHECK 1: Docker Version >= 20.10
    # -------------------------------------------------------------------------
    echo -e "${CYAN}[1/6] Checking Docker version...${NC}"

    if ! command -v docker &>/dev/null; then
        echo -e "${RED}  ${CROSS_MARK} Docker command not found${NC}"
        failed_checks+=("Docker not installed")
        ((failed_count++)) || true
    else
        local docker_version
        docker_version=$(docker --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -n1)

        if [[ -z "$docker_version" ]]; then
            echo -e "${RED}  ${CROSS_MARK} Cannot determine Docker version${NC}"
            failed_checks+=("Docker version unknown")
            ((failed_count++)) || true
        elif ! version_compare "$docker_version" "$DOCKER_MIN_VERSION"; then
            echo -e "${RED}  ${CROSS_MARK} Docker version $docker_version is below minimum $DOCKER_MIN_VERSION${NC}"
            echo -e "${YELLOW}  Suggestion: Upgrade Docker with 'sudo apt-get install --only-upgrade docker.io'${NC}"
            failed_checks+=("Docker version too old: $docker_version")
            ((failed_count++)) || true
        else
            echo -e "${GREEN}  ${CHECK_MARK} Docker version: $docker_version (meets minimum $DOCKER_MIN_VERSION)${NC}"
        fi
    fi
    ((check_count++)) || true
    echo ""

    # -------------------------------------------------------------------------
    # CHECK 2: Docker Socket Exists and Accessible
    # -------------------------------------------------------------------------
    echo -e "${CYAN}[2/6] Checking Docker socket...${NC}"

    local socket_path="/var/run/docker.sock"

    if [[ ! -S "$socket_path" ]]; then
        echo -e "${RED}  ${CROSS_MARK} Docker socket not found at $socket_path${NC}"
        echo -e "${YELLOW}  Suggestion: Start Docker service with 'sudo systemctl start docker'${NC}"
        failed_checks+=("Docker socket missing")
        ((failed_count++)) || true
    elif [[ ! -r "$socket_path" ]]; then
        echo -e "${RED}  ${CROSS_MARK} Docker socket exists but is not readable${NC}"
        echo -e "${YELLOW}  Suggestion: Add current user to docker group or run as root${NC}"
        failed_checks+=("Docker socket not readable")
        ((failed_count++)) || true
    elif [[ ! -w "$socket_path" ]]; then
        echo -e "${YELLOW}  ${WARNING_MARK} Docker socket is read-only (may need sudo)${NC}"
        echo -e "${GREEN}  ${CHECK_MARK} Socket exists at $socket_path${NC}"
    else
        echo -e "${GREEN}  ${CHECK_MARK} Docker socket accessible at $socket_path${NC}"

        # Show socket permissions
        local socket_perms
        socket_perms=$(ls -l "$socket_path" | awk '{print $1, $3, $4}')
        echo -e "${CYAN}  Permissions: $socket_perms${NC}"
    fi
    ((check_count++)) || true
    echo ""

    # -------------------------------------------------------------------------
    # CHECK 3: User in Docker Group (if not root)
    # -------------------------------------------------------------------------
    echo -e "${CYAN}[3/6] Checking Docker group membership...${NC}"

    if [[ $EUID -eq 0 ]]; then
        echo -e "${GREEN}  ${CHECK_MARK} Running as root (Docker group check skipped)${NC}"
    else
        local current_user
        current_user=$(whoami)

        if groups "$current_user" | grep -q '\bdocker\b'; then
            echo -e "${GREEN}  ${CHECK_MARK} User '$current_user' is in docker group${NC}"
        else
            echo -e "${YELLOW}  ${WARNING_MARK} User '$current_user' is NOT in docker group${NC}"
            echo -e "${YELLOW}  Current groups: $(groups "$current_user")${NC}"
            echo ""
            echo -e "${CYAN}  To add user to docker group:${NC}"
            echo -e "${CYAN}    sudo usermod -aG docker $current_user${NC}"
            echo -e "${CYAN}    newgrp docker  # Or logout and login again${NC}"
            echo ""
            echo -e "${YELLOW}  ${WARNING_MARK} You may need to re-login for group changes to take effect${NC}"
            # This is a warning, not a failure
        fi
    fi
    ((check_count++)) || true
    echo ""

    # -------------------------------------------------------------------------
    # CHECK 4: Docker Daemon Running
    # -------------------------------------------------------------------------
    echo -e "${CYAN}[4/6] Checking Docker daemon status...${NC}"

    if ! systemctl is-active --quiet docker 2>/dev/null; then
        echo -e "${RED}  ${CROSS_MARK} Docker daemon is not running${NC}"
        echo -e "${YELLOW}  Suggestion: Start Docker with 'sudo systemctl start docker'${NC}"

        # Try to show systemctl status
        if command -v systemctl &>/dev/null; then
            echo -e "${CYAN}  Docker service status:${NC}"
            systemctl status docker --no-pager -l | head -n 10 | sed 's/^/    /'
        fi

        failed_checks+=("Docker daemon not running")
        ((failed_count++)) || true
    else
        echo -e "${GREEN}  ${CHECK_MARK} Docker daemon is running${NC}"

        # Show uptime
        local docker_uptime
        docker_uptime=$(systemctl show docker --property=ActiveEnterTimestamp --value 2>/dev/null)
        if [[ -n "$docker_uptime" ]]; then
            echo -e "${CYAN}  Started: $docker_uptime${NC}"
        fi
    fi
    ((check_count++)) || true
    echo ""

    # -------------------------------------------------------------------------
    # CHECK 5: Test Container Run
    # -------------------------------------------------------------------------
    echo -e "${CYAN}[5/6] Testing Docker with hello-world container...${NC}"

    # Clean up any previous hello-world containers
    docker rm -f hello-world-test &>/dev/null || true

    # Run test container
    local test_output
    if test_output=$(docker run --rm --name hello-world-test hello-world 2>&1); then
        echo -e "${GREEN}  ${CHECK_MARK} Successfully ran test container${NC}"
        echo -e "${CYAN}  Container output (first 3 lines):${NC}"
        echo "$test_output" | head -n 3 | sed 's/^/    /'
    else
        echo -e "${RED}  ${CROSS_MARK} Failed to run test container${NC}"
        echo -e "${CYAN}  Error output:${NC}"
        echo "$test_output" | head -n 5 | sed 's/^/    /'

        failed_checks+=("Docker test container failed")
        ((failed_count++)) || true
    fi
    ((check_count++)) || true
    echo ""

    # -------------------------------------------------------------------------
    # CHECK 6: docker-compose Version >= 1.29
    # -------------------------------------------------------------------------
    echo -e "${CYAN}[6/6] Checking docker-compose version...${NC}"

    if ! command -v docker-compose &>/dev/null; then
        echo -e "${RED}  ${CROSS_MARK} docker-compose command not found${NC}"
        failed_checks+=("docker-compose not installed")
        ((failed_count++)) || true
    else
        local compose_version
        compose_version=$(docker-compose --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -n1)

        if [[ -z "$compose_version" ]]; then
            echo -e "${RED}  ${CROSS_MARK} Cannot determine docker-compose version${NC}"
            failed_checks+=("docker-compose version unknown")
            ((failed_count++)) || true
        elif ! version_compare "$compose_version" "$DOCKER_COMPOSE_MIN_VERSION"; then
            echo -e "${RED}  ${CROSS_MARK} docker-compose version $compose_version is below minimum $DOCKER_COMPOSE_MIN_VERSION${NC}"
            echo -e "${YELLOW}  Suggestion: Upgrade docker-compose with 'sudo apt-get install --only-upgrade docker-compose'${NC}"
            failed_checks+=("docker-compose version too old: $compose_version")
            ((failed_count++)) || true
        else
            echo -e "${GREEN}  ${CHECK_MARK} docker-compose version: $compose_version (meets minimum $DOCKER_COMPOSE_MIN_VERSION)${NC}"
        fi
    fi
    ((check_count++)) || true
    echo ""

    # -------------------------------------------------------------------------
    # SUMMARY
    # -------------------------------------------------------------------------
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           DOCKER VALIDATION SUMMARY                           ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Total checks: $check_count"
    echo -e "  Passed: $((check_count - failed_count))"
    echo -e "  Failed: $failed_count"
    echo ""

    if [[ $failed_count -eq 0 ]]; then
        echo -e "${GREEN}${CHECK_MARK} All Docker validation checks passed${NC}"
        echo ""
        return 0
    else
        echo -e "${RED}${CROSS_MARK} Docker validation failed with $failed_count error(s):${NC}"
        for check in "${failed_checks[@]}"; do
            echo -e "${RED}  - $check${NC}"
        done
        echo ""

        # Provide comprehensive troubleshooting
        echo -e "${CYAN}Troubleshooting Steps:${NC}"
        echo -e "${CYAN}  1. Ensure Docker is installed: sudo apt-get install docker.io${NC}"
        echo -e "${CYAN}  2. Start Docker service: sudo systemctl start docker${NC}"
        echo -e "${CYAN}  3. Enable Docker on boot: sudo systemctl enable docker${NC}"
        echo -e "${CYAN}  4. Add user to docker group: sudo usermod -aG docker \$(whoami)${NC}"
        echo -e "${CYAN}  5. Re-login or run: newgrp docker${NC}"
        echo -e "${CYAN}  6. Test manually: docker run hello-world${NC}"
        echo ""

        return 1
    fi
}

# =============================================================================
# MAIN EXECUTION (when sourced, this section doesn't run)
# =============================================================================
# If this script is executed directly (for testing), run all functions
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Running dependency module in test mode..."
    echo ""

    # Source os_detection.sh if available
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "${SCRIPT_DIR}/os_detection.sh" ]]; then
        echo "Sourcing os_detection.sh..."
        source "${SCRIPT_DIR}/os_detection.sh"

        # Run OS detection
        detect_os || exit 1
        validate_os || exit 1
        get_package_manager || exit 1
        print_os_info
        echo ""
    else
        echo "WARNING: os_detection.sh not found, using defaults..."
        export PKG_MANAGER="apt"
    fi

    # Check dependencies
    if ! check_dependencies; then
        echo ""
        echo "Missing dependencies detected. Install them? (y/n)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            install_dependencies || exit 3
        fi
    fi

    echo ""

    # Validate Docker
    validate_docker || exit 3

    echo ""
    echo -e "${GREEN}All tests passed successfully!${NC}"
    exit 0
fi
