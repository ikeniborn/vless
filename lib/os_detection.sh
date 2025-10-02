#!/bin/bash
#
# OS Detection and Validation Module
# Part of VLESS+Reality VPN Deployment System
#
# Purpose: Detect and validate operating system for installation compatibility
# Supports: Ubuntu 20.04+, Debian 10+
# Usage: source this file from install.sh
#

set -euo pipefail

# =============================================================================
# GLOBAL VARIABLES (exported for use by other modules)
# =============================================================================

export OS_NAME=""
export OS_VERSION=""
export OS_VERSION_CODENAME=""
export OS_ID=""
export PKG_MANAGER=""

# Color codes for output (optional but improves readability)
# Only define if not already set (to avoid conflicts when sourced after install.sh)
[[ -z "${RED:-}" ]] && RED='\033[0;31m'
[[ -z "${GREEN:-}" ]] && GREEN='\033[0;32m'
[[ -z "${YELLOW:-}" ]] && YELLOW='\033[1;33m'
[[ -z "${BLUE:-}" ]] && BLUE='\033[0;34m'
[[ -z "${NC:-}" ]] && NC='\033[0m' # No Color

# =============================================================================
# FUNCTION: detect_os
# =============================================================================
# Description: Parse /etc/os-release to extract operating system information
# Sets global variables: OS_NAME, OS_VERSION, OS_VERSION_CODENAME, OS_ID
# Returns: 0 on success, 1 on failure
# =============================================================================
detect_os() {
    local os_release_file="/etc/os-release"

    # Check if /etc/os-release exists
    if [[ ! -f "${os_release_file}" ]]; then
        echo -e "${RED}ERROR: ${os_release_file} not found${NC}" >&2
        echo -e "${RED}Cannot detect operating system${NC}" >&2
        return 1
    fi

    # Check if file is readable
    if [[ ! -r "${os_release_file}" ]]; then
        echo -e "${RED}ERROR: ${os_release_file} is not readable${NC}" >&2
        return 1
    fi

    # Source the os-release file to get variables
    # Use a subshell to avoid polluting current environment
    local os_info
    os_info=$(source "${os_release_file}" 2>/dev/null && echo "${NAME}|${VERSION_ID}|${VERSION_CODENAME}|${ID}")

    # Check if we got valid output
    if [[ -z "${os_info}" ]]; then
        echo -e "${RED}ERROR: Failed to parse ${os_release_file}${NC}" >&2
        echo -e "${RED}File may be malformed or empty${NC}" >&2
        return 1
    fi

    # Split the output into variables
    IFS='|' read -r OS_NAME OS_VERSION OS_VERSION_CODENAME OS_ID <<< "${os_info}"

    # Validate that we got all required fields
    if [[ -z "${OS_NAME}" ]] || [[ -z "${OS_VERSION}" ]] || [[ -z "${OS_ID}" ]]; then
        echo -e "${RED}ERROR: Incomplete OS information detected${NC}" >&2
        echo -e "${RED}NAME: ${OS_NAME:-missing}${NC}" >&2
        echo -e "${RED}VERSION_ID: ${OS_VERSION:-missing}${NC}" >&2
        echo -e "${RED}ID: ${OS_ID:-missing}${NC}" >&2
        return 1
    fi

    # Handle cases where VERSION_CODENAME might be empty
    # Some minimal distributions might not set this
    if [[ -z "${OS_VERSION_CODENAME}" ]]; then
        OS_VERSION_CODENAME="unknown"
    fi

    # Export variables for use by other modules
    export OS_NAME
    export OS_VERSION
    export OS_VERSION_CODENAME
    export OS_ID

    return 0
}

# =============================================================================
# FUNCTION: validate_os
# =============================================================================
# Description: Validate that detected OS is supported by this installation
# Supported versions:
#   - Ubuntu: 20.04 (focal), 22.04 (jammy), 24.04 (noble)
#   - Debian: 10 (buster), 11 (bullseye), 12 (bookworm)
# Returns: 0 if supported, 1 if unsupported
# =============================================================================
validate_os() {
    # Ensure detect_os has been run first
    if [[ -z "${OS_ID}" ]] || [[ -z "${OS_VERSION}" ]]; then
        echo -e "${RED}ERROR: OS detection must be run before validation${NC}" >&2
        echo -e "${RED}Call detect_os() first${NC}" >&2
        return 1
    fi

    local supported=0

    case "${OS_ID}" in
        ubuntu)
            case "${OS_VERSION}" in
                20.04)
                    if [[ "${OS_VERSION_CODENAME}" != "focal" ]]; then
                        echo -e "${YELLOW}WARNING: Expected codename 'focal' for Ubuntu 20.04, got '${OS_VERSION_CODENAME}'${NC}" >&2
                    fi
                    supported=1
                    ;;
                22.04)
                    if [[ "${OS_VERSION_CODENAME}" != "jammy" ]]; then
                        echo -e "${YELLOW}WARNING: Expected codename 'jammy' for Ubuntu 22.04, got '${OS_VERSION_CODENAME}'${NC}" >&2
                    fi
                    supported=1
                    ;;
                24.04)
                    if [[ "${OS_VERSION_CODENAME}" != "noble" ]]; then
                        echo -e "${YELLOW}WARNING: Expected codename 'noble' for Ubuntu 24.04, got '${OS_VERSION_CODENAME}'${NC}" >&2
                    fi
                    supported=1
                    ;;
                *)
                    supported=0
                    ;;
            esac
            ;;
        debian)
            case "${OS_VERSION}" in
                10)
                    if [[ "${OS_VERSION_CODENAME}" != "buster" ]]; then
                        echo -e "${YELLOW}WARNING: Expected codename 'buster' for Debian 10, got '${OS_VERSION_CODENAME}'${NC}" >&2
                    fi
                    supported=1
                    ;;
                11)
                    if [[ "${OS_VERSION_CODENAME}" != "bullseye" ]]; then
                        echo -e "${YELLOW}WARNING: Expected codename 'bullseye' for Debian 11, got '${OS_VERSION_CODENAME}'${NC}" >&2
                    fi
                    supported=1
                    ;;
                12)
                    if [[ "${OS_VERSION_CODENAME}" != "bookworm" ]]; then
                        echo -e "${YELLOW}WARNING: Expected codename 'bookworm' for Debian 12, got '${OS_VERSION_CODENAME}'${NC}" >&2
                    fi
                    supported=1
                    ;;
                *)
                    supported=0
                    ;;
            esac
            ;;
        *)
            supported=0
            ;;
    esac

    if [[ ${supported} -eq 0 ]]; then
        echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}" >&2
        echo -e "${RED}║           UNSUPPORTED OPERATING SYSTEM DETECTED               ║${NC}" >&2
        echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}" >&2
        echo -e "" >&2
        echo -e "${RED}Detected OS: ${OS_NAME} ${OS_VERSION} (${OS_VERSION_CODENAME})${NC}" >&2
        echo -e "${RED}OS ID: ${OS_ID}${NC}" >&2
        echo -e "" >&2
        echo -e "${YELLOW}Supported operating systems:${NC}" >&2
        echo -e "${GREEN}  Ubuntu:${NC}" >&2
        echo -e "    - 20.04 (Focal Fossa)" >&2
        echo -e "    - 22.04 (Jammy Jellyfish)" >&2
        echo -e "    - 24.04 (Noble Numbat)" >&2
        echo -e "${GREEN}  Debian:${NC}" >&2
        echo -e "    - 10 (Buster)" >&2
        echo -e "    - 11 (Bullseye)" >&2
        echo -e "    - 12 (Bookworm)" >&2
        echo -e "" >&2
        echo -e "${RED}Installation cannot continue on this system.${NC}" >&2
        return 1
    fi

    return 0
}

# =============================================================================
# FUNCTION: get_package_manager
# =============================================================================
# Description: Determine which package manager to use (apt or apt-get)
# Sets global variable: PKG_MANAGER
# Prefers 'apt' if available (Ubuntu 20.04+, Debian 10+)
# Falls back to 'apt-get' if 'apt' not found
# Returns: 0 on success, 1 on failure
# =============================================================================
get_package_manager() {
    # Check for 'apt' first (preferred on modern systems)
    if command -v apt &> /dev/null; then
        PKG_MANAGER="apt"
        export PKG_MANAGER
        return 0
    fi

    # Fallback to 'apt-get'
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt-get"
        export PKG_MANAGER
        return 0
    fi

    # Neither found - this should never happen on Debian/Ubuntu
    echo -e "${RED}ERROR: No package manager found (apt or apt-get)${NC}" >&2
    echo -e "${RED}This script requires a Debian-based system${NC}" >&2
    return 1
}

# =============================================================================
# FUNCTION: print_os_info
# =============================================================================
# Description: Display detected OS information in user-friendly format
# Shows: OS name, version, codename, package manager
# Returns: 0 on success
# =============================================================================
print_os_info() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              DETECTED OPERATING SYSTEM                        ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo -e ""
    echo -e "${GREEN}OS Name:${NC}      ${OS_NAME}"
    echo -e "${GREEN}Version:${NC}      ${OS_VERSION}"
    echo -e "${GREEN}Codename:${NC}     ${OS_VERSION_CODENAME}"
    echo -e "${GREEN}OS ID:${NC}        ${OS_ID}"
    echo -e "${GREEN}Pkg Manager:${NC}  ${PKG_MANAGER}"
    echo -e ""

    return 0
}

# =============================================================================
# MAIN EXECUTION (when sourced, this section doesn't run)
# =============================================================================
# If this script is executed directly (for testing), run all functions
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Running OS detection module in test mode..."
    echo ""

    # Run detection
    if ! detect_os; then
        echo "OS detection failed!"
        exit 1
    fi

    # Run validation
    if ! validate_os; then
        echo "OS validation failed!"
        exit 1
    fi

    # Get package manager
    if ! get_package_manager; then
        echo "Package manager detection failed!"
        exit 1
    fi

    # Print info
    print_os_info

    echo ""
    echo -e "${GREEN}All checks passed successfully!${NC}"
    exit 0
fi
