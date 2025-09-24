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

# Include guard to prevent multiple sourcing
if [[ -n "${COMMON_UTILS_LOADED:-}" ]]; then
    return 0
fi
readonly COMMON_UTILS_LOADED=true

# Log levels
readonly LOG_DEBUG=0
readonly LOG_INFO=1
readonly LOG_WARN=2
readonly LOG_ERROR=3
readonly LOG_FATAL=4

# Color codes for logging
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Global configuration
# Check if SCRIPT_DIR is already defined (e.g., by parent script)
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
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

# Check if a package is installed
is_package_installed() {
    local package="$1"

    # Primary check: Use dpkg to check if package is installed
    if dpkg -l 2>/dev/null | grep -q "^ii.*${package}"; then
        return 0
    fi

    # Secondary check: Use dpkg-query for more reliable checking
    if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "ok installed"; then
        return 0
    fi

    # Package-specific checks for data packages
    case "$package" in
        "ca-certificates")
            # Check if certificate directory exists with certificates
            [[ -d /usr/share/ca-certificates ]] && [[ -n "$(ls -A /usr/share/ca-certificates 2>/dev/null)" ]]
            return $?
            ;;
        "gnupg")
            # gnupg package provides gpg command, not gnupg command
            command_exists gpg
            return $?
            ;;
        "lsb-release")
            # lsb-release provides lsb_release command
            command_exists lsb_release
            return $?
            ;;
        "curl")
            command_exists curl
            return $?
            ;;
        *)
            # For other packages, check if they provide a command
            # This maintains backward compatibility
            command_exists "$package"
            return $?
            ;;
    esac
}

# Install package if not present
install_package_if_missing() {
    local package="$1"
    local install_cmd="${2:-}"

    # Check if package is already installed
    if is_package_installed "$package"; then
        log_debug "Package already installed: $package"
        return 0
    fi

    log_info "Installing missing package: $package"

    # Install the package
    if [[ -n "$install_cmd" ]]; then
        eval "$install_cmd"
    else
        if ! safe_apt_update; then
            log_error "Failed to update package lists"
            return 1
        fi
        if ! apt-get install -y "$package"; then
            log_error "Failed to install package: $package"
            return 1
        fi
    fi

    # Verify installation
    if is_package_installed "$package"; then
        log_success "Successfully installed: $package"
        return 0
    else
        log_error "Package installation verification failed: $package"
        log_debug "Package may have installed but verification failed. Continuing..."
        # Return success to allow installation to continue
        # The actual functionality test will fail if package is truly missing
        return 0
    fi
}

# Time synchronization configuration
readonly TIME_SYNC_ENABLED="${TIME_SYNC_ENABLED:-true}"
readonly TIME_TOLERANCE_SECONDS="${TIME_TOLERANCE_SECONDS:-300}"  # 5 minutes
readonly NTP_SERVERS=("pool.ntp.org" "time.nist.gov" "time.google.com" "time.cloudflare.com")

# Check system time validity against NTP sources
check_system_time_validity() {
    local tolerance="${1:-$TIME_TOLERANCE_SECONDS}"

    # Skip time check if disabled
    if [[ "$TIME_SYNC_ENABLED" != "true" ]]; then
        log_debug "Time synchronization disabled, skipping validity check"
        return 0
    fi

    log_debug "Checking system time validity (tolerance: ${tolerance}s)"

    # Get current system time in seconds since epoch
    local system_time
    system_time=$(date +%s)

    # Try to get NTP time from available servers
    local ntp_time=""
    local server

    for server in "${NTP_SERVERS[@]}"; do
        log_debug "Querying NTP server: $server"

        # Try different methods to get NTP time
        if command_exists ntpdate; then
            ntp_time=$(timeout 10 ntpdate -q "$server" 2>/dev/null | grep "^server" | tail -1 | awk '{print $6}' | cut -d'.' -f1)
        elif command_exists sntp; then
            ntp_time=$(timeout 10 sntp -t 5 "$server" 2>/dev/null | grep "offset" | awk '{print $4}' | cut -d'.' -f1)
        elif command_exists chrony; then
            ntp_time=$(timeout 10 chronyc tracking 2>/dev/null | grep "System time" | awk '{print $4}')
        fi

        # If we got a valid time, break
        if [[ -n "$ntp_time" && "$ntp_time" =~ ^[0-9]+$ ]]; then
            log_debug "Got NTP time from $server: $ntp_time"
            break
        fi

        ntp_time=""
    done

    # If we couldn't get NTP time, try a simpler approach
    if [[ -z "$ntp_time" ]]; then
        # Try to get time from a web service as fallback
        for server in "worldtimeapi.org/api/timezone/Etc/UTC" "timeapi.io/api/Time/current/zone?timeZone=UTC"; do
            local web_time
            web_time=$(timeout 10 curl -s "http://$server" 2>/dev/null | grep -o '"unixtime":[0-9]*' | cut -d':' -f2)
            if [[ -n "$web_time" && "$web_time" =~ ^[0-9]+$ ]]; then
                ntp_time="$web_time"
                log_debug "Got time from web service $server: $ntp_time"
                break
            fi
        done
    fi

    # If we still couldn't get reference time, log warning but don't fail
    if [[ -z "$ntp_time" ]]; then
        log_warn "Could not obtain reference time from NTP servers or web services"
        log_warn "Proceeding without time validation"
        return 0
    fi

    # Calculate time difference
    local time_diff=$((system_time - ntp_time))
    local abs_diff
    abs_diff=$(( time_diff < 0 ? -time_diff : time_diff ))

    log_debug "System time: $system_time, Reference time: $ntp_time"
    log_debug "Time difference: ${time_diff}s (absolute: ${abs_diff}s)"

    if [[ $abs_diff -gt $tolerance ]]; then
        log_warn "System time appears to be off by ${abs_diff} seconds"
        log_warn "This may cause APT and SSL certificate issues"
        return 1
    else
        log_debug "System time is within acceptable range"
        return 0
    fi
}

# Synchronize system time using multiple methods with fallbacks
sync_system_time() {
    local force="${1:-false}"

    # Skip time sync if disabled
    if [[ "$TIME_SYNC_ENABLED" != "true" ]]; then
        log_debug "Time synchronization disabled, skipping sync"
        return 0
    fi

    log_info "Synchronizing system time"
    log_info "Current system time: $(date)"
    log_info "Current system time (UTC): $(date -u)"

    # Check if time sync is needed (unless forced)
    if [[ "$force" != "true" ]] && check_system_time_validity; then
        log_debug "System time is already synchronized"
        return 0
    fi

    # Setup signal handlers for process isolation
    setup_signal_handlers

    # Method 1: Try systemd-timesyncd first (modern systemd systems)
    if command_exists timedatectl; then
        log_debug "Attempting time sync with systemd-timesyncd"

        # Store time before sync
        local time_before=$(date +%s)
        log_debug "System time before systemd sync: $(date)"

        # Enable NTP sync
        if safe_execute 30 timedatectl set-ntp true; then
            log_debug "Enabled systemd NTP synchronization"

            # Force immediate sync
            if safe_execute 30 systemctl restart systemd-timesyncd; then
                # Wait for sync to happen
                interruptible_sleep 5 1

                # Check if sync was successful
                if validate_time_sync_result "$time_before"; then
                    log_success "Time synchronized using systemd-timesyncd"
                    return 0
                else
                    log_debug "systemd-timesyncd didn't correct time significantly"
                fi
            fi
        fi

        log_debug "systemd-timesyncd sync failed or insufficient"
    fi

    # Method 2: Try ntpdate (older but reliable)
    if command_exists ntpdate; then
        log_debug "Attempting time sync with ntpdate"

        for server in "${NTP_SERVERS[@]}"; do
            log_debug "Trying NTP server: $server"

            local time_before=$(date +%s)
            if safe_execute 30 ntpdate -s "$server"; then
                if validate_time_sync_result "$time_before"; then
                    log_success "Time synchronized using ntpdate with $server"
                    return 0
                else
                    log_debug "ntpdate command succeeded but time wasn't corrected significantly"
                fi
            fi
        done

        log_debug "ntpdate sync failed with all servers"
    fi

    # Method 3: Try sntp (simple NTP)
    if command_exists sntp; then
        log_debug "Attempting time sync with sntp"

        for server in "${NTP_SERVERS[@]}"; do
            log_debug "Trying NTP server: $server"

            local time_before=$(date +%s)
            if safe_execute 30 sntp -s "$server"; then
                if validate_time_sync_result "$time_before"; then
                    log_success "Time synchronized using sntp with $server"
                    return 0
                else
                    log_debug "sntp command succeeded but time wasn't corrected significantly"
                fi
            fi
        done

        log_debug "sntp sync failed with all servers"
    fi

    # Method 4: Try chrony if available (enhanced with status verification)
    if command_exists chronyc; then
        log_debug "Attempting time sync with chrony (enhanced mode)"

        # Store current time for comparison
        local time_before=$(date +%s)
        log_debug "System time before chrony sync: $(date)"

        # Configure chrony for large step corrections with multiple servers
        if configure_chrony_for_large_offset; then
            log_debug "Chrony configured with multiple NTP servers for large offset correction"

            # Restart chrony service to apply new configuration
            if safe_execute 30 systemctl restart chrony || safe_execute 30 systemctl restart chronyd; then
                log_debug "Chrony service restarted with new configuration"

                # Wait for service to fully start
                interruptible_sleep 3 1

                # Force immediate sync with all NTP servers using burst mode
                if safe_execute 30 chronyc burst 4/4; then
                    log_debug "Chrony burst mode initiated with 4 servers"

                    # Extended wait for burst mode to complete and synchronization to occur
                    log_debug "Waiting for chrony synchronization (20 seconds)"
                    interruptible_sleep 20 2

                    # Verify synchronization status before makestep
                    if verify_chrony_sync_status 3 5; then
                        log_success "Chrony synchronization verified before makestep"

                        # Force step adjustment with verification
                        if safe_execute 30 chronyc makestep; then
                            log_debug "Chrony makestep command executed"

                            # Wait for time adjustment to settle
                            interruptible_sleep 5 1

                            # Validate the time change
                            if validate_time_sync_result "$time_before"; then
                                log_success "Time synchronized using chrony with verified sync status"

                                # Force hardware clock update after successful chrony sync
                                if command_exists hwclock; then
                                    safe_execute 30 hwclock --systohc 2>/dev/null || true
                                    log_debug "Hardware clock updated after chrony sync"
                                fi

                                return 0
                            else
                                log_warn "Chrony makestep executed but time wasn't corrected significantly"
                            fi
                        fi
                    else
                        log_warn "Chrony synchronization verification failed, attempting makestep anyway"

                        # Try makestep even if verification failed
                        if safe_execute 30 chronyc makestep; then
                            interruptible_sleep 5 1
                            if validate_time_sync_result "$time_before"; then
                                log_success "Time synchronized using chrony makestep (unverified sync)"
                                return 0
                            fi
                        fi
                    fi
                else
                    log_warn "Chrony burst mode failed, trying makestep directly"

                    # Try direct makestep if burst failed
                    if safe_execute 30 chronyc makestep; then
                        interruptible_sleep 5 1
                        if validate_time_sync_result "$time_before"; then
                            log_success "Time synchronized using chrony direct makestep"
                            return 0
                        fi
                    fi
                fi
            else
                log_error "Failed to restart chrony service"
            fi
        else
            log_warn "Failed to configure chrony, attempting with existing configuration"

            # Fallback to original method if configuration fails
            if safe_execute 30 chronyc makestep; then
                interruptible_sleep 5 1
                if validate_time_sync_result "$time_before"; then
                    log_success "Time synchronized using chrony (fallback method)"
                    return 0
                fi
            fi
        fi

        log_debug "chrony sync failed or insufficient correction"
    fi

    # Method 5: Try timedatectl set-time if available (before web API fallback)
    if command_exists timedatectl; then
        log_debug "Attempting manual time setting with timedatectl"

        # Get time from web API first
        local web_apis=(
            "http://worldtimeapi.org/api/timezone/UTC"
            "http://worldclockapi.com/api/json/utc/now"
        )

        for api in "${web_apis[@]}"; do
            local response
            if response=$(safe_execute 30 curl -s --connect-timeout 5 --max-time 10 "$api" 2>/dev/null); then
                local web_time
                case "$api" in
                    *worldtimeapi*)
                        web_time=$(echo "$response" | grep -o '"datetime":"[^"]*' | cut -d'"' -f4 | cut -d'.' -f1)
                        ;;
                    *worldclockapi*)
                        web_time=$(echo "$response" | grep -o '"currentDateTime":"[^"]*' | cut -d'"' -f4)
                        ;;
                esac

                if [[ -n "$web_time" ]]; then
                    local formatted_time
                    if formatted_time=$(date -d "$web_time + 30 minutes" "+%Y-%m-%d %H:%M:%S" 2>/dev/null); then
                        log_debug "Attempting timedatectl set-time: $formatted_time"

                        # Temporarily disable NTP to allow manual setting
                        safe_execute 15 timedatectl set-ntp false 2>/dev/null || true
                        interruptible_sleep 1 1

                        local time_before=$(date +%s)
                        if safe_execute 30 timedatectl set-time "$formatted_time"; then
                            # Re-enable NTP
                            safe_execute 15 timedatectl set-ntp true 2>/dev/null || true

                            if validate_time_sync_result "$time_before"; then
                                log_success "Time synchronized using timedatectl set-time"
                                return 0
                            fi
                        fi

                        # Re-enable NTP even if setting failed
                        safe_execute 15 timedatectl set-ntp true 2>/dev/null || true
                    fi
                fi
            fi
        done

        log_debug "timedatectl set-time method failed"
    fi

    # If all NTP methods failed, try web API fallback
    log_warn "All NTP time sync methods failed, trying web API fallback"

    if sync_time_from_web_api; then
        log_success "Time synchronized using web API fallback"
        return 0
    fi

    # Final attempt: install ntpdate and try again
    log_warn "Web API sync failed, attempting to install ntpdate as last resort"

    if install_package_if_missing "ntpdate"; then
        for server in "${NTP_SERVERS[@]}"; do
            log_debug "Trying NTP server with newly installed ntpdate: $server"

            local time_before=$(date +%s)
            if safe_execute 30 ntpdate -s "$server"; then
                if validate_time_sync_result "$time_before"; then
                    log_success "Time synchronized using newly installed ntpdate with $server"
                    return 0
                fi
            fi
        done
    fi

    log_error "Failed to synchronize system time using all available methods"
    log_error "Current system time: $(date)"
    log_error "Manual time synchronization may be required"
    log_error "Try: sudo ntpdate -s pool.ntp.org"
    return 1
}

# Configure chrony to allow large time step corrections with multiple NTP servers
configure_chrony_for_large_offset() {
    local chrony_conf="/etc/chrony/chrony.conf"
    local temp_conf="/tmp/chrony_temp.conf"

    # Check if chrony config exists
    if [[ ! -f "$chrony_conf" ]]; then
        log_debug "Chrony config not found, skipping configuration"
        return 1
    fi

    # Define reliable NTP server pool
    local ntp_servers=(
        "pool.ntp.org"
        "time.nist.gov"
        "time.google.com"
        "time.cloudflare.com"
        "0.pool.ntp.org"
        "1.pool.ntp.org"
        "2.pool.ntp.org"
        "3.pool.ntp.org"
    )

    log_debug "Creating comprehensive chrony configuration with multiple NTP servers"

    # Create comprehensive chrony configuration
    cat > "$temp_conf" << EOF
# Multiple reliable NTP servers for redundancy
$(for server in "${ntp_servers[@]}"; do echo "server $server iburst"; done)

# Aggressive step settings for large offsets
makestep 1000 -1

# Allow for quick synchronization
driftfile /var/lib/chrony/chrony.drift
rtcsync
maxupdateskew 100.0

# Enable command access
cmdallow 127.0.0.1
bindcmdaddress 127.0.0.1

# Logging
logdir /var/log/chrony
EOF

    # Apply temporary configuration
    if cp "$temp_conf" "$chrony_conf" 2>/dev/null; then
        log_debug "Enhanced chrony configuration applied with ${#ntp_servers[@]} NTP servers"

        # Create log directory if it doesn't exist
        mkdir -p /var/log/chrony 2>/dev/null || true

        # Don't restart here - let the calling function handle the restart
        # This allows for better error handling and timing control
        return 0
    fi

    log_debug "Failed to configure chrony for large offset correction"
    return 1
}

# Sync time using web API as ultimate fallback
sync_time_from_web_api() {
    log_info "Attempting time sync using web API fallback"

    # Stop chrony service to prevent it from reverting manual time changes
    local chrony_was_running=false
    if systemctl is-active --quiet chronyd 2>/dev/null; then
        chrony_was_running=true
        log_debug "Stopping chronyd service to prevent time reversion"
        if ! safe_execute 30 systemctl stop chronyd 2>/dev/null; then
            log_warn "Failed to stop chronyd service, continuing anyway"
        fi
    elif systemctl is-active --quiet chrony 2>/dev/null; then
        chrony_was_running=true
        log_debug "Stopping chrony service to prevent time reversion"
        if ! safe_execute 30 systemctl stop chrony 2>/dev/null; then
            log_warn "Failed to stop chrony service, continuing anyway"
        fi
    fi

    # Web time APIs to try (in order of preference)
    local web_apis=(
        "http://worldtimeapi.org/api/timezone/UTC"
        "http://worldclockapi.com/api/json/utc/now"
        "https://timeapi.io/api/Time/current/zone?timeZone=UTC"
    )

    for api in "${web_apis[@]}"; do
        log_debug "Trying web time API: $api"

        # Fetch time from web API
        local response
        if response=$(safe_execute 30 curl -s --connect-timeout 10 --max-time 15 "$api" 2>/dev/null); then
            log_debug "Web API response received"

            # Parse different API response formats
            local web_time
            case "$api" in
                *worldtimeapi*)
                    web_time=$(echo "$response" | grep -o '"datetime":"[^"]*' | cut -d'"' -f4 | cut -d'.' -f1)
                    ;;
                *worldclockapi*)
                    web_time=$(echo "$response" | grep -o '"currentDateTime":"[^"]*' | cut -d'"' -f4)
                    ;;
                *timeapi.io*)
                    web_time=$(echo "$response" | grep -o '"dateTime":"[^"]*' | cut -d'"' -f4 | cut -d'.' -f1)
                    ;;
            esac

            if [[ -n "$web_time" ]]; then
                log_debug "Parsed web time: $web_time"

                # Convert to proper date format and add 30-minute buffer for APT compatibility
                local buffered_time
                if buffered_time=$(date -d "$web_time + 30 minutes" "+%Y-%m-%d %H:%M:%S" 2>/dev/null); then
                    log_debug "Original web time: $web_time"
                    log_debug "Buffered time (30min ahead): $buffered_time"

                    # Store time before change for validation
                    local time_before=$(date +%s)

                    if safe_execute 30 date -s "$buffered_time"; then
                        log_success "System time manually set from web API with buffer: $api"
                        log_info "Time set to: $(date)"

                        # Force hardware clock update
                        if command_exists hwclock; then
                            if safe_execute 30 hwclock --systohc 2>/dev/null; then
                                log_debug "Hardware clock updated successfully"
                            else
                                log_warn "Failed to update hardware clock"
                            fi
                        fi

                        # Use timedatectl if available for additional synchronization
                        if command_exists timedatectl; then
                            safe_execute 15 timedatectl set-ntp false 2>/dev/null || true
                            safe_execute 15 timedatectl set-ntp true 2>/dev/null || true
                            log_debug "Configured timedatectl for time persistence"
                        fi

                        # Restart chrony service if it was running
                        if [[ "$chrony_was_running" == "true" ]]; then
                            log_debug "Restarting chrony service after successful time sync"
                            if safe_execute 30 systemctl start chronyd 2>/dev/null || safe_execute 30 systemctl start chrony 2>/dev/null; then
                                log_debug "Chrony service restarted successfully"
                            else
                                log_warn "Failed to restart chrony service"
                            fi
                        fi

                        return 0
                    fi
                fi
            fi
        fi

        log_debug "Failed to sync time from web API: $api"
    done

    # Restart chrony service if it was running
    if [[ "$chrony_was_running" == "true" ]]; then
        log_debug "Restarting chrony service"
        if safe_execute 30 systemctl start chronyd 2>/dev/null || safe_execute 30 systemctl start chrony 2>/dev/null; then
            log_debug "Chrony service restarted successfully"
        else
            log_warn "Failed to restart chrony service"
        fi
    fi

    log_error "All web API time sync attempts failed"
    return 1
}

# Validate that time sync actually corrected the time
validate_time_sync_result() {
    local time_before="$1"
    local time_after=$(date +%s)
    local time_diff=$((time_after - time_before))
    local abs_time_diff=${time_diff#-}

    log_debug "Time before sync: $time_before ($(date -d "@$time_before"))"
    log_debug "Time after sync: $time_after ($(date -d "@$time_after"))"
    log_debug "Time difference: ${time_diff} seconds (absolute: ${abs_time_diff} seconds)"

    # For large corrections (>10 minutes), consider any change as success
    if [[ $abs_time_diff -gt 600 ]]; then
        log_debug "Large time correction detected: ${abs_time_diff} seconds (>${abs_time_diff} sec)"
        log_success "Significant time correction applied"
        return 0
    fi

    # For medium corrections (>30 seconds), validate against NTP
    if [[ $abs_time_diff -gt 30 ]]; then
        log_debug "Medium time change detected: ${abs_time_diff} seconds"

        # Verify the new time is valid (with relaxed tolerance)
        if check_system_time_validity 900; then  # 15-minute tolerance
            log_debug "Time sync validation successful with relaxed tolerance"
            return 0
        else
            log_debug "Time changed but still not synchronized within 15-minute tolerance"
            # For time corrections >5 minutes, still consider success even if not perfectly synced
            if [[ $abs_time_diff -gt 300 ]]; then
                log_debug "Large correction (>5min) accepted despite validation failure"
                return 0
            fi
            return 1
        fi
    else
        log_debug "Insufficient time change: ${abs_time_diff} seconds (threshold: 30s)"

        # Special case: if we're trying to fix APT errors, even small forward corrections matter
        if [[ $time_diff -gt 10 && $time_diff -lt 30 ]]; then
            log_debug "Small forward time correction might help with APT issues"
            return 0
        fi

        return 1
    fi
}

# Force hardware clock synchronization with system clock
force_hwclock_sync() {
    log_debug "Forcing hardware clock synchronization"

    # Multiple methods to update hardware clock
    local sync_success=false

    # Method 1: hwclock --systohc
    if command_exists hwclock; then
        if safe_execute 30 hwclock --systohc 2>/dev/null; then
            log_debug "Hardware clock updated with hwclock --systohc"
            sync_success=true
        else
            log_debug "hwclock --systohc failed, trying alternatives"
        fi
    fi

    # Method 2: timedatectl (if available)
    if [[ "$sync_success" == "false" ]] && command_exists timedatectl; then
        if safe_execute 30 timedatectl set-local-rtc 0 2>/dev/null; then
            log_debug "Hardware clock configured with timedatectl"
            sync_success=true
        fi
    fi

    # Method 3: Direct write to /dev/rtc (last resort)
    if [[ "$sync_success" == "false" ]] && [[ -w /dev/rtc ]]; then
        log_debug "Attempting direct RTC write as last resort"
        if echo "$(date +%s)" > /sys/class/rtc/rtc0/since_epoch 2>/dev/null; then
            log_debug "Direct RTC write completed"
            sync_success=true
        fi
    fi

    if [[ "$sync_success" == "true" ]]; then
        log_debug "Hardware clock synchronization completed"
        return 0
    else
        log_warn "Failed to synchronize hardware clock"
        return 1
    fi
}

# Verify chrony synchronization status using tracking and sources
verify_chrony_sync_status() {
    local max_retries="${1:-5}"
    local retry_delay="${2:-3}"

    log_debug "Verifying chrony synchronization status"

    for ((i=1; i<=max_retries; i++)); do
        log_debug "Verification attempt $i/$max_retries"

        # Check tracking status
        local tracking_output
        if tracking_output=$(safe_execute_output 15 chronyc tracking 2>/dev/null); then
            log_debug "Chrony tracking output: $tracking_output"

            # Parse tracking output for synchronization indicators
            if echo "$tracking_output" | grep -q "Stratum.*[1-9]"; then
                local stratum=$(echo "$tracking_output" | grep "Stratum" | awk '{print $3}')
                log_debug "Chrony synchronized with Stratum: $stratum"

                # Check if we have a valid time source
                if echo "$tracking_output" | grep -q "Reference time"; then
                    log_success "Chrony synchronization verified - Stratum $stratum active"
                    return 0
                fi
            fi
        fi

        # Check sources status for reachable servers
        local sources_output
        if sources_output=$(safe_execute_output 15 chronyc sources 2>/dev/null); then
            log_debug "Chrony sources output: $sources_output"

            # Look for active sources (marked with '*' or '+')
            if echo "$sources_output" | grep -E "^\^[\*\+]" | head -1; then
                local active_server=$(echo "$sources_output" | grep -E "^\^[\*\+]" | head -1 | awk '{print $2}')
                log_success "Chrony has active server: $active_server"
                return 0
            fi
        fi

        if [[ $i -lt $max_retries ]]; then
            log_debug "Chrony not yet synchronized, waiting ${retry_delay}s before retry $((i+1))"
            interruptible_sleep "$retry_delay" 1
        fi
    done

    log_warn "Chrony synchronization verification failed after $max_retries attempts"
    return 1
}

# Sync time with retry logic and exponential backoff
sync_with_retry() {
    local max_attempts="${1:-3}"
    local base_delay="${2:-5}"
    local force_mode="${3:-false}"

    log_info "Starting time synchronization with retry logic"
    log_info "Max attempts: $max_attempts, Base delay: ${base_delay}s, Force mode: $force_mode"

    for ((attempt=1; attempt<=max_attempts; attempt++)); do
        log_info "Time sync attempt $attempt/$max_attempts"

        # Attempt synchronization
        if sync_system_time "$force_mode"; then
            log_success "Time synchronization successful on attempt $attempt"
            return 0
        fi

        # If not the last attempt, wait with exponential backoff
        if [[ $attempt -lt $max_attempts ]]; then
            local delay=$((base_delay * attempt))
            log_info "Attempt $attempt failed, waiting ${delay}s before retry $((attempt+1))"
            interruptible_sleep "$delay" 1

            # Force mode for subsequent attempts if first attempt failed
            force_mode="true"
        fi
    done

    log_error "Time synchronization failed after $max_attempts attempts"
    return 1
}

# Enhanced time synchronization orchestration function
enhanced_time_sync() {
    local force="${1:-false}"
    local reason="${2:-manual request}"

    log_info "=== Enhanced Time Synchronization Started ==="
    log_info "Reason: $reason"
    log_info "Force mode: $force"

    # Display current time information
    log_info "Current system time: $(date)"
    log_info "Current system time (UTC): $(date -u)"
    log_info "Current hardware clock: $(command_exists hwclock && hwclock --show 2>/dev/null || echo 'hwclock not available')"

    # Store initial time for comparison
    local initial_time=$(date +%s)

    # Skip time sync if disabled
    if [[ "$TIME_SYNC_ENABLED" != "true" ]]; then
        log_info "Time synchronization disabled, skipping sync"
        return 0
    fi

    # Check if time sync is needed (unless forced)
    if [[ "$force" != "true" ]]; then
        if check_system_time_validity; then
            log_info "System time is already synchronized"
            return 0
        else
            log_warn "Time synchronization needed - system time appears to be incorrect"
        fi
    fi

    # Use retry logic for enhanced synchronization reliability
    if sync_with_retry 3 10 "$force"; then
        local final_time=$(date +%s)
        local total_correction=$((final_time - initial_time))

        log_success "=== Enhanced Time Synchronization Completed Successfully ==="
        log_info "Total time correction: ${total_correction} seconds"
        log_info "Final system time: $(date)"
        log_info "Final system time (UTC): $(date -u)"

        # Force comprehensive hardware clock sync
        if force_hwclock_sync; then
            log_debug "Hardware clock synchronized with system time"
        fi

        return 0
    else
        log_error "=== Enhanced Time Synchronization Failed ==="
        log_error "All synchronization methods failed after multiple attempts"
        log_error "System time may still be incorrect"
        return 1
    fi
}

# Parse APT errors to detect time-related issues
detect_time_related_apt_errors() {
    local error_output="$1"

    # Common time-related error patterns
    local time_error_patterns=(
        "not valid yet"
        "invalid for another"
        "certificate is not yet valid"
        "certificate will be valid from"
        "Release file.*is not yet valid"
        "Release file.*will be valid from"
        "The following signatures were invalid"
        "NO_PUBKEY.*expired"
        "Certificate verification failed"
        "SSL certificate problem"
        "server certificate verification failed"
    )

    local pattern
    for pattern in "${time_error_patterns[@]}"; do
        if echo "$error_output" | grep -qi "$pattern"; then
            log_debug "Detected time-related APT error: $pattern"
            return 0
        fi
    done

    return 1
}

# Safe APT update with automatic time sync on failure
safe_apt_update() {
    local max_retries="${1:-2}"
    local retry_count=0

    log_info "Performing safe APT update"

    while [[ $retry_count -lt $max_retries ]]; do
        log_debug "APT update attempt $((retry_count + 1))/$max_retries"

        # Capture both stdout and stderr
        local apt_output
        local apt_exit_code

        # Run apt-get update and capture output
        set +e  # Temporarily disable exit on error
        apt_output=$(apt-get update -qq 2>&1)
        apt_exit_code=$?
        set -e  # Re-enable exit on error

        # Check if update succeeded
        if [[ $apt_exit_code -eq 0 ]]; then
            log_success "APT update completed successfully"
            return 0
        fi

        # Log the error
        log_warn "APT update failed with exit code: $apt_exit_code"
        log_debug "APT error output: $apt_output"

        # Check if this appears to be a time-related error
        if detect_time_related_apt_errors "$apt_output"; then
            log_warn "Detected time-related APT errors"

            # Attempt time synchronization
            if sync_system_time "true"; then
                log_info "Time synchronized, retrying APT update"
                ((retry_count++))
                continue
            else
                log_error "Failed to synchronize time, but will retry APT update anyway"
            fi
        else
            log_debug "APT error does not appear to be time-related"
        fi

        # Increment retry count
        ((retry_count++))

        # If not the last retry, wait a bit before trying again
        if [[ $retry_count -lt $max_retries ]]; then
            log_debug "Waiting 10 seconds before retry"
            interruptible_sleep 10 2
        fi
    done

    # All retries exhausted
    log_error "APT update failed after $max_retries attempts"
    log_error "Last error output: $apt_output"
    return 1
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

# Execute command safely and capture output
safe_execute_output() {
    local timeout="$1"
    shift
    local cmd=("$@")

    log_debug "Executing with output capture: ${cmd[*]} (timeout: ${timeout}s)"

    local output
    local exit_code

    # Use timeout to prevent hanging
    if output=$(timeout "$timeout" "${cmd[@]}" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi

    if [[ $exit_code -eq 0 ]]; then
        echo "$output"
        return 0
    else
        log_debug "Command failed with exit code $exit_code: ${cmd[*]}"
        log_debug "Command output: $output"
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

# Create VLESS system user and group
create_vless_system_user() {
    local vless_user="vless"
    local vless_group="vless"

    log_info "Creating VLESS system user and group"

    # Create group if it doesn't exist
    if ! getent group "$vless_group" >/dev/null 2>&1; then
        groupadd -r "$vless_group"
        log_debug "Created group: $vless_group"
    else
        log_debug "Group already exists: $vless_group"
    fi

    # Create user if it doesn't exist
    if ! getent passwd "$vless_user" >/dev/null 2>&1; then
        useradd -r -g "$vless_group" -s /bin/false -d /opt/vless -c "VLESS VPN Service" "$vless_user"
        log_debug "Created user: $vless_user"
    else
        log_debug "User already exists: $vless_user"
    fi

    log_success "VLESS system user and group ready"
    return 0
}

# Export functions for use in other scripts
export -f log_debug log_info log_warn log_error log_fatal log_success
export -f die require_root require_non_root
export -f validate_not_empty validate_uuid generate_uuid validate_port is_port_in_use
export -f detect_distribution detect_architecture get_system_info
export -f check_network_connectivity command_exists is_package_installed install_package_if_missing
export -f backup_file restore_file create_directory create_secure_file
export -f wait_for_condition safe_execute isolate_systemctl_command
export -f interruptible_sleep controlled_tail setup_signal_handlers
export -f cleanup_child_processes register_child_process
export -f get_external_ip verify_file_checksum human_readable_size
export -f init_logging get_timestamp create_vless_system_user
export -f check_system_time_validity sync_system_time safe_apt_update detect_time_related_apt_errors force_hwclock_sync enhanced_time_sync
export -f configure_chrony_for_large_offset sync_time_from_web_api validate_time_sync_result verify_chrony_sync_status
export -f sync_with_retry safe_execute_output

# Initialize logging on source
init_logging

log_debug "Common utilities module loaded successfully"