#!/bin/bash
# ======================================================================================
# VLESS+Reality VPN Management System - Common Utilities Module
# ======================================================================================
# This module provides core utility functions for logging, validation, and system operations.
# All scripts in the VLESS VPN system depend on these utilities.
#
# Author: Claude Code
# Version: 1.0
# Last Modified: 2025-09-21
# ======================================================================================

set -euo pipefail

# Global Variables
# Set variables if not already defined
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [[ -z "${VLESS_ROOT:-}" ]]; then
    readonly VLESS_ROOT="/opt/vless"
fi
if [[ -z "${LOG_DIR:-}" ]]; then
    readonly LOG_DIR="${VLESS_ROOT}/logs"
fi
if [[ -z "${CONFIG_DIR:-}" ]]; then
    readonly CONFIG_DIR="${VLESS_ROOT}/config"
fi
if [[ -z "${BACKUP_DIR:-}" ]]; then
    readonly BACKUP_DIR="${VLESS_ROOT}/backups"
fi
if [[ -z "${CERT_DIR:-}" ]]; then
    readonly CERT_DIR="${VLESS_ROOT}/certs"
fi
if [[ -z "${USER_DIR:-}" ]]; then
    readonly USER_DIR="${VLESS_ROOT}/users"
fi

# Color codes for output formatting
if [[ -z "${RED:-}" ]]; then readonly RED='\033[0;31m'; fi
if [[ -z "${GREEN:-}" ]]; then readonly GREEN='\033[0;32m'; fi
if [[ -z "${YELLOW:-}" ]]; then readonly YELLOW='\033[1;33m'; fi
if [[ -z "${BLUE:-}" ]]; then readonly BLUE='\033[0;34m'; fi
if [[ -z "${PURPLE:-}" ]]; then readonly PURPLE='\033[0;35m'; fi
if [[ -z "${CYAN:-}" ]]; then readonly CYAN='\033[0;36m'; fi
if [[ -z "${WHITE:-}" ]]; then readonly WHITE='\033[1;37m'; fi
if [[ -z "${NC:-}" ]]; then readonly NC='\033[0m'; fi # No Color

# Log levels
if [[ -z "${LOG_LEVEL_DEBUG:-}" ]]; then readonly LOG_LEVEL_DEBUG=0; fi
if [[ -z "${LOG_LEVEL_INFO:-}" ]]; then readonly LOG_LEVEL_INFO=1; fi
if [[ -z "${LOG_LEVEL_WARN:-}" ]]; then readonly LOG_LEVEL_WARN=2; fi
if [[ -z "${LOG_LEVEL_ERROR:-}" ]]; then readonly LOG_LEVEL_ERROR=3; fi

# Current log level (can be overridden by environment variable)
CURRENT_LOG_LEVEL=${VLESS_LOG_LEVEL:-$LOG_LEVEL_INFO}

# ======================================================================================
# LOGGING FUNCTIONS
# ======================================================================================

# Function: get_timestamp
# Description: Generate formatted timestamp for logging
# Returns: Current timestamp in YYYY-MM-DD HH:MM:SS format
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Function: log_to_file
# Description: Write log message to file with rotation support
# Parameters: $1 - log level, $2 - message
log_to_file() {
    local level="$1"
    local message="$2"
    local log_file="${LOG_DIR}/vless.log"

    # Create log directory if it doesn't exist
    [[ ! -d "$LOG_DIR" ]] && mkdir -p "$LOG_DIR"

    # Write to log file
    echo "[$(get_timestamp)] [$level] $message" >> "$log_file"

    # Rotate log if it gets too large (>10MB)
    if [[ -f "$log_file" ]] && [[ $(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null || echo 0) -gt 10485760 ]]; then
        mv "$log_file" "${log_file}.$(date +%Y%m%d_%H%M%S)"
        touch "$log_file"
    fi
}

# Function: log_debug
# Description: Log debug message (gray color, only shown when debug enabled)
# Parameters: $* - message to log
log_debug() {
    [[ $CURRENT_LOG_LEVEL -gt $LOG_LEVEL_DEBUG ]] && return
    local message="$*"
    echo -e "${WHITE}[DEBUG]${NC} $message" >&2
    log_to_file "DEBUG" "$message"
}

# Function: log_info
# Description: Log informational message (blue color)
# Parameters: $* - message to log
log_info() {
    [[ $CURRENT_LOG_LEVEL -gt $LOG_LEVEL_INFO ]] && return
    local message="$*"
    echo -e "${BLUE}[INFO]${NC} $message"
    log_to_file "INFO" "$message"
}

# Function: log_warn
# Description: Log warning message (yellow color)
# Parameters: $* - message to log
log_warn() {
    [[ $CURRENT_LOG_LEVEL -gt $LOG_LEVEL_WARN ]] && return
    local message="$*"
    echo -e "${YELLOW}[WARN]${NC} $message" >&2
    log_to_file "WARN" "$message"
}

# Function: log_error
# Description: Log error message (red color)
# Parameters: $* - message to log
log_error() {
    local message="$*"
    echo -e "${RED}[ERROR]${NC} $message" >&2
    log_to_file "ERROR" "$message"
}

# Function: log_success
# Description: Log success message (green color)
# Parameters: $* - message to log
log_success() {
    local message="$*"
    echo -e "${GREEN}[SUCCESS]${NC} $message"
    log_to_file "SUCCESS" "$message"
}

# ======================================================================================
# VALIDATION FUNCTIONS
# ======================================================================================

# Function: validate_root
# Description: Ensure script is running with root privileges
# Returns: 0 if root, exits with error if not
validate_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root. Please use sudo."
        exit 1
    fi
    log_debug "Root privileges validated"
}

# Function: validate_system
# Description: Check if the system is a supported Linux distribution
# Returns: 0 if supported, 1 if not
validate_system() {
    local supported_distros=("ubuntu" "debian")
    local distro=""

    if [[ -f /etc/os-release ]]; then
        distro=$(grep "^ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"')
    else
        log_error "Cannot determine Linux distribution"
        return 1
    fi

    for supported in "${supported_distros[@]}"; do
        if [[ "$distro" == "$supported" ]]; then
            log_info "System validated: $distro"
            return 0
        fi
    done

    log_error "Unsupported distribution: $distro. Supported: ${supported_distros[*]}"
    return 1
}

# Function: check_internet
# Description: Verify internet connectivity
# Returns: 0 if connected, 1 if not
check_internet() {
    local test_hosts=("8.8.8.8" "1.1.1.1" "google.com")

    for host in "${test_hosts[@]}"; do
        if ping -c 1 -W 5 "$host" &>/dev/null; then
            log_debug "Internet connectivity verified via $host"
            return 0
        fi
    done

    log_error "No internet connectivity detected"
    return 1
}

# Function: validate_port
# Description: Validate if port number is in valid range and available
# Parameters: $1 - port number
# Returns: 0 if valid and available, 1 if not
validate_port() {
    local port="$1"

    # Check if port is a number
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        log_error "Invalid port: $port (not a number)"
        return 1
    fi

    # Check port range
    if [[ $port -lt 1 || $port -gt 65535 ]]; then
        log_error "Invalid port: $port (must be 1-65535)"
        return 1
    fi

    # Check if port is available
    if ss -tulpn | grep -q ":$port "; then
        log_error "Port $port is already in use"
        return 1
    fi

    log_debug "Port $port is valid and available"
    return 0
}

# ======================================================================================
# SYSTEM UTILITY FUNCTIONS
# ======================================================================================

# Function: backup_file
# Description: Create a timestamped backup of a file
# Parameters: $1 - file path
# Returns: 0 on success, 1 on failure
backup_file() {
    local file_path="$1"
    local backup_suffix=$(date +%Y%m%d_%H%M%S)
    local backup_path="${file_path}.backup.${backup_suffix}"

    if [[ ! -f "$file_path" ]]; then
        log_warn "File does not exist: $file_path"
        return 1
    fi

    if cp "$file_path" "$backup_path"; then
        log_info "File backed up: $file_path -> $backup_path"
        return 0
    else
        log_error "Failed to backup file: $file_path"
        return 1
    fi
}

# Function: generate_uuid
# Description: Generate a UUID v4 for user identification
# Returns: UUID string
generate_uuid() {
    # Try different methods to generate UUID
    if command -v uuidgen &>/dev/null; then
        uuidgen
    elif [[ -f /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    else
        # Fallback: generate pseudo-random UUID
        python3 -c "import uuid; print(str(uuid.uuid4()))" 2>/dev/null || \
        perl -e 'use UUID; UUID::generate($uuid); UUID::unparse($uuid, $uuid_string); print $uuid_string' 2>/dev/null || \
        echo "$(date +%s)-$(shuf -i 1000-9999 -n 1)-$(shuf -i 1000-9999 -n 1)-$(shuf -i 1000-9999 -n 1)"
    fi
}

# Function: is_service_running
# Description: Check if a systemd service is running
# Parameters: $1 - service name
# Returns: 0 if running, 1 if not
is_service_running() {
    local service_name="$1"

    if systemctl is-active --quiet "$service_name"; then
        log_debug "Service $service_name is running"
        return 0
    else
        log_debug "Service $service_name is not running"
        return 1
    fi
}

# Function: wait_for_service
# Description: Wait for a service to start with timeout
# Parameters: $1 - service name, $2 - timeout in seconds (default: 30)
# Returns: 0 if service starts, 1 if timeout
wait_for_service() {
    local service_name="$1"
    local timeout="${2:-30}"
    local elapsed=0

    log_info "Waiting for service $service_name to start (timeout: ${timeout}s)..."

    while [[ $elapsed -lt $timeout ]]; do
        if is_service_running "$service_name"; then
            log_success "Service $service_name started successfully"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    log_error "Timeout waiting for service $service_name to start"
    return 1
}

# ======================================================================================
# FILE AND DIRECTORY FUNCTIONS
# ======================================================================================

# Function: create_directory
# Description: Create directory with proper permissions
# Parameters: $1 - directory path, $2 - permissions (default: 755), $3 - owner (default: root:root)
create_directory() {
    local dir_path="$1"
    local permissions="${2:-755}"
    local owner="${3:-root:root}"

    if [[ -d "$dir_path" ]]; then
        log_debug "Directory already exists: $dir_path"
        return 0
    fi

    if mkdir -p "$dir_path"; then
        chmod "$permissions" "$dir_path"
        chown "$owner" "$dir_path"
        log_info "Created directory: $dir_path (permissions: $permissions, owner: $owner)"
        return 0
    else
        log_error "Failed to create directory: $dir_path"
        return 1
    fi
}

# Function: ensure_file_exists
# Description: Ensure a file exists, create if it doesn't
# Parameters: $1 - file path, $2 - permissions (default: 644), $3 - owner (default: root:root)
ensure_file_exists() {
    local file_path="$1"
    local permissions="${2:-644}"
    local owner="${3:-root:root}"

    if [[ ! -f "$file_path" ]]; then
        touch "$file_path"
        chmod "$permissions" "$file_path"
        chown "$owner" "$file_path"
        log_info "Created file: $file_path"
    fi
}

# ======================================================================================
# NETWORK UTILITY FUNCTIONS
# ======================================================================================

# Function: get_public_ip
# Description: Get the public IP address of the server
# Returns: Public IP address
get_public_ip() {
    local ip=""
    local services=("https://ifconfig.me/ip" "https://icanhazip.com" "https://ipecho.net/plain")

    for service in "${services[@]}"; do
        ip=$(curl -s --max-time 10 "$service" 2>/dev/null | tr -d '\n\r')
        if [[ -n "$ip" && "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "$ip"
            return 0
        fi
    done

    log_error "Failed to determine public IP address"
    return 1
}

# Function: validate_ip
# Description: Validate IP address format
# Parameters: $1 - IP address
# Returns: 0 if valid, 1 if not
validate_ip() {
    local ip="$1"
    local ip_regex='^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'

    if [[ $ip =~ $ip_regex ]]; then
        # Check each octet is 0-255
        IFS='.' read -r -a octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if [[ $octet -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# ======================================================================================
# PACKAGE MANAGEMENT FUNCTIONS
# ======================================================================================

# Function: update_package_cache
# Description: Update package manager cache
update_package_cache() {
    log_info "Updating package cache..."
    if apt-get update -qq; then
        log_success "Package cache updated"
        return 0
    else
        log_error "Failed to update package cache"
        return 1
    fi
}

# Function: install_package
# Description: Install a package with error handling
# Parameters: $1 - package name
# Returns: 0 on success, 1 on failure
install_package() {
    local package="$1"

    log_info "Installing package: $package"
    if apt-get install -y "$package" &>/dev/null; then
        log_success "Package installed: $package"
        return 0
    else
        log_error "Failed to install package: $package"
        return 1
    fi
}

# Function: is_package_installed
# Description: Check if a package is installed
# Parameters: $1 - package name
# Returns: 0 if installed, 1 if not
is_package_installed() {
    local package="$1"

    if dpkg -l | grep -q "^ii  $package "; then
        log_debug "Package $package is installed"
        return 0
    else
        log_debug "Package $package is not installed"
        return 1
    fi
}

# ======================================================================================
# ERROR HANDLING AND CLEANUP
# ======================================================================================

# Function: cleanup_on_exit
# Description: Cleanup function to be called on script exit
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script exited with error code: $exit_code"
    fi
}

# Function: setup_error_handling
# Description: Setup error handling and cleanup
setup_error_handling() {
    set -euo pipefail
    trap cleanup_on_exit EXIT
}

# ======================================================================================
# INITIALIZATION
# ======================================================================================

# Function: init_common_utils
# Description: Initialize common utilities
init_common_utils() {
    # Create necessary directories
    create_directory "$VLESS_ROOT" "755" "root:root"
    create_directory "$LOG_DIR" "755" "root:root"
    create_directory "$CONFIG_DIR" "700" "root:root"
    create_directory "$BACKUP_DIR" "700" "root:root"
    create_directory "$CERT_DIR" "700" "root:root"
    create_directory "$USER_DIR" "700" "root:root"

    log_info "Common utilities initialized"
}

# Auto-initialize if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    validate_root
    init_common_utils
    log_success "Common utilities module loaded successfully"
fi