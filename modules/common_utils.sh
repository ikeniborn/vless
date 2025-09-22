#!/bin/bash

# VLESS+Reality VPN Management System - Common Utilities
# Version: 1.0.0
# Description: Core logging, error handling, and utility functions
#
# This module provides:
# - Colored logging with timestamp and log levels
# - Error handling with exit codes
# - Input validation functions
# - System information detection
# - Network connectivity checks
# - Process isolation for EPERM prevention

set -euo pipefail

# Color codes for logging
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Log levels
readonly LOG_DEBUG=0
readonly LOG_INFO=1
readonly LOG_WARN=2
readonly LOG_ERROR=3
readonly LOG_FATAL=4

# Global configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_LEVEL=${LOG_LEVEL:-$LOG_INFO}
LOG_FILE="${LOG_FILE:-/var/log/vless-vpn.log}"

# Process isolation variables
declare -a CHILD_PROCESSES=()
CLEANUP_REGISTERED=false

# Setup signal handlers for process isolation
setup_signal_handlers() {
    if [[ "${CLEANUP_REGISTERED}" == "false" ]]; then
        trap 'cleanup_child_processes; exit 130' INT
        trap 'cleanup_child_processes; exit 143' TERM
        trap 'cleanup_child_processes' EXIT
        CLEANUP_REGISTERED=true
    fi
}

# Clean up child processes to prevent EPERM errors
cleanup_child_processes() {
    local pid
    for pid in "${CHILD_PROCESSES[@]}"; do
        if kill -0 "${pid}" 2>/dev/null; then
            log_debug "Cleaning up child process: ${pid}"
            kill -TERM "${pid}" 2>/dev/null || true
            sleep 1
            if kill -0 "${pid}" 2>/dev/null; then
                kill -KILL "${pid}" 2>/dev/null || true
            fi
        fi
    done
    CHILD_PROCESSES=()
}

# Register a child process for cleanup
register_child_process() {
    local pid=$1
    CHILD_PROCESSES+=("${pid}")
}

# Get current timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Get log level name
get_log_level_name() {
    local level=$1
    case $level in
        $LOG_DEBUG) echo "DEBUG" ;;
        $LOG_INFO)  echo "INFO"  ;;
        $LOG_WARN)  echo "WARN"  ;;
        $LOG_ERROR) echo "ERROR" ;;
        $LOG_FATAL) echo "FATAL" ;;
        *)          echo "UNKNOWN" ;;
    esac
}

# Base logging function
log_message() {
    local level=$1
    local color=$2
    shift 2
    local message="$*"

    [[ $level -lt $LOG_LEVEL ]] && return 0

    local timestamp
    timestamp=$(get_timestamp)
    local level_name
    level_name=$(get_log_level_name "$level")

    # Console output with color
    echo -e "${color}[${timestamp}] [${level_name}] ${message}${NC}" >&2

    # File output without color (if log file is writable)
    if [[ -w "$(dirname "$LOG_FILE")" ]] 2>/dev/null; then
        echo "[${timestamp}] [${level_name}] ${message}" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# Specific log level functions
log_debug() { log_message $LOG_DEBUG "$CYAN" "$@"; }
log_info()  { log_message $LOG_INFO "$WHITE" "$@"; }
log_warn()  { log_message $LOG_WARN "$YELLOW" "$@"; }
log_error() { log_message $LOG_ERROR "$RED" "$@"; }
log_fatal() { log_message $LOG_FATAL "$PURPLE" "$@"; }

# Success logging
log_success() { log_message $LOG_INFO "$GREEN" "$@"; }

# Error handling with exit codes
die() {
    local exit_code=${2:-1}
    log_fatal "$1"
    cleanup_child_processes
    exit "$exit_code"
}

# Check if running as root
require_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root. Please use sudo." 2
    fi
}

# Check if NOT running as root
require_non_root() {
    if [[ $EUID -eq 0 ]]; then
        die "This script should not be run as root." 3
    fi
}

# Validate input parameters
validate_not_empty() {
    local value="$1"
    local name="$2"

    if [[ -z "$value" ]]; then
        die "Parameter '$name' cannot be empty" 4
    fi
}

# Validate UUID format
validate_uuid() {
    local uuid="$1"
    local uuid_pattern='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

    if [[ ! $uuid =~ $uuid_pattern ]]; then
        return 1
    fi
    return 0
}

# Generate UUID v4
generate_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        # Fallback UUID generation
        python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
        die "UUID generation failed. Please install uuidgen or python3."
    fi
}

# Validate port number
validate_port() {
    local port="$1"

    if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
        return 1
    fi
    return 0
}

# Check if port is in use
is_port_in_use() {
    local port="$1"
    netstat -tuln 2>/dev/null | grep -q ":${port} " || \
    ss -tuln 2>/dev/null | grep -q ":${port} " || \
    return 1
}

# Detect system distribution
detect_distribution() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "${ID,,}"
    elif command -v lsb_release >/dev/null 2>&1; then
        lsb_release -si | tr '[:upper:]' '[:lower:]'
    else
        echo "unknown"
    fi
}

# Detect system architecture
detect_architecture() {
    case "$(uname -m)" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l)  echo "armhf" ;;
        *)       echo "$(uname -m)" ;;
    esac
}

# Get system information
get_system_info() {
    local distribution
    local architecture
    local kernel

    distribution=$(detect_distribution)
    architecture=$(detect_architecture)
    kernel=$(uname -r)

    cat << EOF
Distribution: $distribution
Architecture: $architecture
Kernel: $kernel
EOF
}

# Check network connectivity
check_network_connectivity() {
    local test_hosts=("8.8.8.8" "1.1.1.1" "google.com")
    local host

    for host in "${test_hosts[@]}"; do
        if ping -c 1 -W 3 "$host" >/dev/null 2>&1; then
            log_debug "Network connectivity confirmed via $host"
            return 0
        fi
    done

    log_error "No network connectivity detected"
    return 1
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install package if not present
install_package_if_missing() {
    local package="$1"
    local install_cmd="${2:-}"

    if ! command_exists "$package" && ! dpkg -l | grep -q "^ii.*${package}"; then
        log_info "Installing missing package: $package"

        if [[ -n "$install_cmd" ]]; then
            eval "$install_cmd"
        else
            apt-get update -qq && apt-get install -y "$package"
        fi

        if ! command_exists "$package"; then
            die "Failed to install package: $package" 5
        fi

        log_success "Successfully installed: $package"
    fi
}

# Safe file backup
backup_file() {
    local file="$1"
    local backup_suffix="${2:-.backup.$(date +%Y%m%d_%H%M%S)}"

    if [[ -f "$file" ]]; then
        local backup_file="${file}${backup_suffix}"
        cp "$file" "$backup_file"
        log_debug "Backed up $file to $backup_file"
        echo "$backup_file"
    fi
}

# Restore file from backup
restore_file() {
    local backup_file="$1"
    local original_file="${backup_file%%.backup.*}"

    if [[ -f "$backup_file" ]]; then
        cp "$backup_file" "$original_file"
        log_info "Restored $original_file from backup"
        return 0
    else
        log_error "Backup file not found: $backup_file"
        return 1
    fi
}

# Create directory with proper permissions
create_directory() {
    local dir="$1"
    local permissions="${2:-755}"
    local owner="${3:-}"

    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        chmod "$permissions" "$dir"

        if [[ -n "$owner" ]]; then
            chown "$owner" "$dir"
        fi

        log_debug "Created directory: $dir (permissions: $permissions)"
    fi
}

# Secure file creation
create_secure_file() {
    local file="$1"
    local content="$2"
    local permissions="${3:-600}"
    local owner="${4:-}"

    echo "$content" > "$file"
    chmod "$permissions" "$file"

    if [[ -n "$owner" ]]; then
        chown "$owner" "$file"
    fi

    log_debug "Created secure file: $file (permissions: $permissions)"
}

# Wait for condition with timeout
wait_for_condition() {
    local condition_cmd="$1"
    local timeout="${2:-30}"
    local interval="${3:-1}"
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        if eval "$condition_cmd"; then
            return 0
        fi
        sleep "$interval"
        ((elapsed += interval))
    done

    log_error "Timeout waiting for condition: $condition_cmd"
    return 1
}

# Process isolation functions to prevent EPERM errors

# Safe execute with timeout and cleanup
safe_execute() {
    local timeout="$1"
    shift
    local cmd=("$@")

    setup_signal_handlers

    log_debug "Executing with timeout ${timeout}s: ${cmd[*]}"

    timeout "${timeout}" "${cmd[@]}" &
    local pid=$!
    register_child_process "$pid"

    if wait "$pid"; then
        log_debug "Command completed successfully: ${cmd[*]}"
        return 0
    else
        local exit_code=$?
        log_error "Command failed with exit code $exit_code: ${cmd[*]}"
        return $exit_code
    fi
}

# Isolated systemctl command
isolate_systemctl_command() {
    local action="$1"
    local service="$2"
    local timeout="${3:-30}"

    setup_signal_handlers
    log_debug "Executing systemctl $action $service with timeout ${timeout}s"

    case "$action" in
        start|stop|restart|reload)
            safe_execute "$timeout" systemctl "$action" "$service"
            ;;
        enable|disable)
            safe_execute "$timeout" systemctl "$action" "$service"
            ;;
        status)
            safe_execute "$timeout" systemctl "$action" "$service" --no-pager
            ;;
        *)
            log_error "Unsupported systemctl action: $action"
            return 1
            ;;
    esac
}

# Interruptible sleep
interruptible_sleep() {
    local duration="$1"
    local check_interval="${2:-5}"
    local elapsed=0

    setup_signal_handlers

    while [[ $elapsed -lt $duration ]]; do
        local sleep_time=$check_interval
        if [[ $((elapsed + check_interval)) -gt $duration ]]; then
            sleep_time=$((duration - elapsed))
        fi

        sleep "$sleep_time" &
        local pid=$!
        register_child_process "$pid"

        if ! wait "$pid"; then
            log_debug "Sleep interrupted"
            return 130
        fi

        elapsed=$((elapsed + sleep_time))
    done
}

# Controlled tail with auto-stop
controlled_tail() {
    local file="$1"
    local timeout="${2:-60}"
    local max_lines="${3:-100}"

    setup_signal_handlers
    log_debug "Tailing $file for ${timeout}s (max ${max_lines} lines)"

    timeout "$timeout" tail -n "$max_lines" -f "$file" &
    local pid=$!
    register_child_process "$pid"

    wait "$pid" 2>/dev/null || true
}

# Get external IP address
get_external_ip() {
    local ip_services=("ifconfig.me" "ipinfo.io/ip" "icanhazip.com")
    local service

    for service in "${ip_services[@]}"; do
        if ip=$(curl -s --connect-timeout 10 "$service" 2>/dev/null); then
            if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                echo "$ip"
                return 0
            fi
        fi
    done

    log_warn "Failed to detect external IP address"
    return 1
}

# Verify file integrity with checksum
verify_file_checksum() {
    local file="$1"
    local expected_checksum="$2"
    local algorithm="${3:-sha256}"

    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi

    local actual_checksum
    case "$algorithm" in
        md5)    actual_checksum=$(md5sum "$file" | cut -d' ' -f1) ;;
        sha1)   actual_checksum=$(sha1sum "$file" | cut -d' ' -f1) ;;
        sha256) actual_checksum=$(sha256sum "$file" | cut -d' ' -f1) ;;
        *)      log_error "Unsupported checksum algorithm: $algorithm"; return 1 ;;
    esac

    if [[ "$actual_checksum" == "$expected_checksum" ]]; then
        log_debug "File checksum verified: $file"
        return 0
    else
        log_error "File checksum mismatch: $file"
        log_error "Expected: $expected_checksum"
        log_error "Actual: $actual_checksum"
        return 1
    fi
}

# Human readable file size
human_readable_size() {
    local size="$1"
    local units=("B" "KB" "MB" "GB" "TB")
    local unit_index=0

    while [[ $size -gt 1024 && $unit_index -lt ${#units[@]} ]]; do
        size=$((size / 1024))
        ((unit_index++))
    done

    echo "${size}${units[$unit_index]}"
}

# Initialize logging
init_logging() {
    local log_dir
    log_dir=$(dirname "$LOG_FILE")

    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null || true
    fi

    if [[ -w "$log_dir" ]]; then
        touch "$LOG_FILE" 2>/dev/null || true
        if [[ -f "$LOG_FILE" ]]; then
            log_debug "Logging initialized: $LOG_FILE"
        fi
    else
        log_warn "Cannot write to log file: $LOG_FILE"
        log_warn "Logging to console only"
    fi
}

# Export functions for use in other scripts
export -f log_debug log_info log_warn log_error log_fatal log_success
export -f die require_root require_non_root
export -f validate_not_empty validate_uuid generate_uuid validate_port is_port_in_use
export -f detect_distribution detect_architecture get_system_info
export -f check_network_connectivity command_exists install_package_if_missing
export -f backup_file restore_file create_directory create_secure_file
export -f wait_for_condition safe_execute isolate_systemctl_command
export -f interruptible_sleep controlled_tail setup_signal_handlers
export -f cleanup_child_processes register_child_process
export -f get_external_ip verify_file_checksum human_readable_size
export -f init_logging get_timestamp

# Initialize logging on source
init_logging

log_debug "Common utilities module loaded successfully"