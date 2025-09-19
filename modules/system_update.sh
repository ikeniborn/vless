#!/bin/bash
# System Update Module for VLESS VPN Project
# Provides safe system update functionality with rollback capabilities
# Compatible with Ubuntu 20.04+ and Debian 11+
# Author: Claude Code
# Version: 1.0

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(dirname "$SCRIPT_DIR")"

# Import process isolation module
source "${SCRIPT_DIR}/process_isolation/process_safe.sh" 2>/dev/null || {
    echo "ERROR: Cannot load process isolation module" >&2
    exit 1
}

# Setup signal handlers
setup_signal_handlers

# Configuration
readonly LOG_DIR="/opt/vless/logs"
readonly LOG_FILE="${LOG_DIR}/system_update.log"
readonly BACKUP_DIR="/opt/vless/backups"
readonly UPDATE_TIMEOUT=1800  # 30 minutes
readonly SECURITY_TIMEOUT=900 # 15 minutes

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Logging functions
log_to_file() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$LOG_FILE"
}

log_info() {
    local message="$1"
    echo -e "${GREEN}[INFO]${NC} $message"
    log_to_file "INFO: $message"
}

log_warning() {
    local message="$1"
    echo -e "${YELLOW}[WARNING]${NC} $message"
    log_to_file "WARNING: $message"
}

log_error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC} $message"
    log_to_file "ERROR: $message"
}

log_debug() {
    local message="$1"
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $message"
    fi
    log_to_file "DEBUG: $message"
}

# Initialize logging
init_logging() {
    if [[ ! -d "$LOG_DIR" ]]; then
        sudo mkdir -p "$LOG_DIR"
        sudo chown "$USER:$USER" "$LOG_DIR"
        sudo chmod 755 "$LOG_DIR"
    fi

    if [[ ! -f "$LOG_FILE" ]]; then
        touch "$LOG_FILE"
        chmod 644 "$LOG_FILE"
    fi

    log_info "System update module initialized"
}

# Check if running as root (when needed)
check_root_privileges() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This function requires root privileges. Please run with sudo."
        return 1
    fi
}

# Detect OS distribution
detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "$ID"
    else
        log_error "Cannot detect OS distribution"
        return 1
    fi
}

# Check OS compatibility
check_os_compatibility() {
    local os_id
    os_id=$(detect_os)

    case "$os_id" in
        ubuntu)
            local version=$(lsb_release -rs 2>/dev/null || echo "unknown")
            if dpkg --compare-versions "$version" ge "20.04"; then
                log_info "Ubuntu $version detected - compatible"
                return 0
            else
                log_error "Ubuntu $version is not supported. Minimum version: 20.04"
                return 1
            fi
            ;;
        debian)
            local version=$(lsb_release -rs 2>/dev/null || echo "unknown")
            if dpkg --compare-versions "$version" ge "11"; then
                log_info "Debian $version detected - compatible"
                return 0
            else
                log_error "Debian $version is not supported. Minimum version: 11"
                return 1
            fi
            ;;
        *)
            log_error "Unsupported OS: $os_id. Only Ubuntu 20.04+ and Debian 11+ are supported."
            return 1
            ;;
    esac
}

# Create system backup before updates
create_system_backup() {
    log_info "Creating system backup before updates..."

    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${BACKUP_DIR}/system_backup_${backup_timestamp}.tar.gz"

    if [[ ! -d "$BACKUP_DIR" ]]; then
        sudo mkdir -p "$BACKUP_DIR"
        sudo chown "$USER:$USER" "$BACKUP_DIR"
    fi

    # Backup critical system files
    local backup_paths=(
        "/etc/apt/sources.list"
        "/etc/apt/sources.list.d/"
        "/etc/systemd/system/"
        "/etc/ufw/"
        "/etc/ssh/sshd_config"
        "/etc/fail2ban/"
    )

    local backup_cmd="tar -czf '$backup_file'"
    for path in "${backup_paths[@]}"; do
        if [[ -e "$path" ]]; then
            backup_cmd+=" '$path'"
        fi
    done

    if safe_execute "$backup_cmd" 300 "System backup creation"; then
        log_info "System backup created: $backup_file"
        echo "$backup_file"
        return 0
    else
        log_error "Failed to create system backup"
        return 1
    fi
}

# Update package lists
update_package_lists() {
    log_info "Updating package lists..."

    local update_cmd="apt-get update"
    if isolated_sudo_command "$update_cmd" 300 "Package list update"; then
        log_info "Package lists updated successfully"
        return 0
    else
        log_error "Failed to update package lists"
        return 1
    fi
}

# Check for available updates
check_available_updates() {
    log_info "Checking for available updates..."

    local check_cmd="apt list --upgradable 2>/dev/null | grep -c '^[^/]'"
    local upgrade_count

    if upgrade_count=$(eval "$check_cmd" 2>/dev/null || echo "0"); then
        if [[ "$upgrade_count" -gt 0 ]]; then
            log_info "$upgrade_count packages available for upgrade"
            return 0
        else
            log_info "No packages available for upgrade"
            return 1
        fi
    else
        log_warning "Could not determine available updates"
        return 1
    fi
}

# Install security updates only
install_security_updates() {
    log_info "Installing security updates..."

    local security_cmd="DEBIAN_FRONTEND=noninteractive apt-get -y upgrade -o APT::Update::Error-Mode=abort"

    if isolated_sudo_command "$security_cmd" "$SECURITY_TIMEOUT" "Security updates installation"; then
        log_info "Security updates installed successfully"
        return 0
    else
        log_error "Failed to install security updates"
        return 1
    fi
}

# Perform full system upgrade
perform_full_upgrade() {
    log_info "Performing full system upgrade..."

    # First, try safe upgrade
    local safe_upgrade_cmd="DEBIAN_FRONTEND=noninteractive apt-get -y upgrade -o APT::Update::Error-Mode=abort"

    if isolated_sudo_command "$safe_upgrade_cmd" "$UPDATE_TIMEOUT" "Safe system upgrade"; then
        log_info "Safe upgrade completed successfully"

        # Then check if dist-upgrade is needed
        local dist_check_cmd="apt list --upgradable 2>/dev/null | grep -q '^[^/]'"
        if eval "$dist_check_cmd" 2>/dev/null; then
            log_info "Additional packages available for dist-upgrade"

            local dist_upgrade_cmd="DEBIAN_FRONTEND=noninteractive apt-get -y dist-upgrade -o APT::Update::Error-Mode=abort"
            if isolated_sudo_command "$dist_upgrade_cmd" "$UPDATE_TIMEOUT" "Distribution upgrade"; then
                log_info "Distribution upgrade completed successfully"
            else
                log_warning "Distribution upgrade failed, but safe upgrade was successful"
            fi
        fi
        return 0
    else
        log_error "System upgrade failed"
        return 1
    fi
}

# Clean up after updates
cleanup_after_updates() {
    log_info "Cleaning up after updates..."

    local cleanup_commands=(
        "apt-get -y autoremove --purge"
        "apt-get -y autoclean"
        "apt-get -y clean"
    )

    for cmd in "${cleanup_commands[@]}"; do
        if isolated_sudo_command "$cmd" 120 "Package cleanup: $cmd"; then
            log_debug "Cleanup command succeeded: $cmd"
        else
            log_warning "Cleanup command failed: $cmd"
        fi
    done

    log_info "Cleanup completed"
}

# Check if reboot is required
check_reboot_required() {
    if [[ -f /var/run/reboot-required ]]; then
        log_warning "System reboot is required to complete updates"
        if [[ -f /var/run/reboot-required.pkgs ]]; then
            log_info "Packages requiring reboot:"
            cat /var/run/reboot-required.pkgs | while read -r pkg; do
                log_info "  - $pkg"
            done
        fi
        return 0
    else
        log_info "No reboot required"
        return 1
    fi
}

# Check system integrity after updates
check_system_integrity() {
    log_info "Checking system integrity after updates..."

    local integrity_checks=(
        "dpkg --configure -a"
        "apt-get -f install"
    )

    for check in "${integrity_checks[@]}"; do
        if isolated_sudo_command "$check" 300 "System integrity check: $check"; then
            log_debug "Integrity check passed: $check"
        else
            log_error "Integrity check failed: $check"
            return 1
        fi
    done

    log_info "System integrity check completed successfully"
    return 0
}

# Restore from backup (rollback function)
restore_from_backup() {
    local backup_file="$1"

    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi

    log_warning "Restoring system from backup: $backup_file"

    local restore_cmd="tar -xzf '$backup_file' -C /"
    if isolated_sudo_command "$restore_cmd" 300 "System restore from backup"; then
        log_info "System restored from backup successfully"
        return 0
    else
        log_error "Failed to restore from backup"
        return 1
    fi
}

# Main update function
update_system() {
    local update_type="${1:-security}"  # security, full
    local auto_cleanup="${2:-true}"
    local create_backup="${3:-true}"

    log_info "Starting system update (type: $update_type)"

    # Initialize logging
    init_logging

    # Check OS compatibility
    if ! check_os_compatibility; then
        return 1
    fi

    # Create backup if requested
    local backup_file=""
    if [[ "$create_backup" == "true" ]]; then
        if ! backup_file=$(create_system_backup); then
            log_error "Backup creation failed. Update aborted for safety."
            return 1
        fi
    fi

    # Update package lists
    if ! update_package_lists; then
        log_error "Failed to update package lists"
        return 1
    fi

    # Check for available updates
    if ! check_available_updates; then
        log_info "No updates available"
        return 0
    fi

    # Perform updates based on type
    local update_success=false
    case "$update_type" in
        "security")
            if install_security_updates; then
                update_success=true
            fi
            ;;
        "full")
            if perform_full_upgrade; then
                update_success=true
            fi
            ;;
        *)
            log_error "Unknown update type: $update_type"
            return 1
            ;;
    esac

    # Handle update failure
    if [[ "$update_success" != "true" ]]; then
        log_error "System update failed"

        # Offer rollback if backup exists
        if [[ -n "$backup_file" ]] && [[ -f "$backup_file" ]]; then
            read -p "Do you want to restore from backup? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                restore_from_backup "$backup_file"
            fi
        fi
        return 1
    fi

    # Check system integrity
    if ! check_system_integrity; then
        log_error "System integrity check failed after updates"
        return 1
    fi

    # Cleanup if requested
    if [[ "$auto_cleanup" == "true" ]]; then
        cleanup_after_updates
    fi

    # Check if reboot is required
    check_reboot_required

    log_info "System update completed successfully"
    return 0
}

# Quick security update function
quick_security_update() {
    log_info "Performing quick security update..."
    update_system "security" "true" "false"
}

# Full system update with backup
full_system_update() {
    log_info "Performing full system update with backup..."
    update_system "full" "true" "true"
}

# Interactive update function
interactive_update() {
    echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        System Update Manager         ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
    echo

    # Check OS compatibility first
    if ! check_os_compatibility; then
        log_error "OS compatibility check failed"
        return 1
    fi

    # Check for updates
    update_package_lists
    if ! check_available_updates; then
        log_info "Your system is up to date!"
        return 0
    fi

    echo "Available update options:"
    echo "1) Security updates only (recommended)"
    echo "2) Full system upgrade"
    echo "3) Check what would be updated"
    echo "4) Exit"
    echo

    while true; do
        read -p "Please select an option (1-4): " choice

        case $choice in
            1)
                echo -e "\n${GREEN}Performing security updates...${NC}"
                update_system "security" "true" "true"
                break
                ;;
            2)
                echo -e "\n${YELLOW}WARNING: Full upgrade may take longer and require reboot${NC}"
                read -p "Are you sure? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    echo -e "\n${GREEN}Performing full system upgrade...${NC}"
                    update_system "full" "true" "true"
                fi
                break
                ;;
            3)
                echo -e "\n${CYAN}Packages that would be upgraded:${NC}"
                apt list --upgradable 2>/dev/null | grep -v "WARNING" || echo "No upgradable packages found"
                echo
                ;;
            4)
                echo "Exiting without updates."
                break
                ;;
            *)
                echo -e "${RED}Invalid option. Please select 1-4.${NC}"
                ;;
        esac
    done
}

# Export functions for use by other modules
export -f update_system
export -f quick_security_update
export -f full_system_update
export -f interactive_update
export -f check_os_compatibility
export -f check_reboot_required

# If script is run directly, start interactive mode
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Parse command line arguments
    case "${1:-interactive}" in
        "security")
            quick_security_update
            ;;
        "full")
            full_system_update
            ;;
        "interactive"|"")
            interactive_update
            ;;
        "check")
            init_logging
            check_os_compatibility
            update_package_lists
            check_available_updates
            ;;
        *)
            echo "Usage: $0 [security|full|interactive|check]"
            echo "  security    - Install security updates only"
            echo "  full       - Perform full system upgrade"
            echo "  interactive - Interactive update menu (default)"
            echo "  check      - Check for available updates"
            exit 1
            ;;
    esac
fi