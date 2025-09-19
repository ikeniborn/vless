#!/bin/bash
# UFW Configuration Module for VLESS VPN Project
# Secure firewall setup with safe rule management
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
readonly LOG_FILE="${LOG_DIR}/ufw_config.log"
readonly BACKUP_DIR="/opt/vless/backups"
readonly UFW_TIMEOUT=60   # 1 minute for UFW operations
readonly DEFAULT_SSH_PORT="22"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly PURPLE='\033[0;35m'
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

log_success() {
    local message="$1"
    echo -e "${GREEN}✓${NC} $message"
    log_to_file "SUCCESS: $message"
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

    log_info "UFW configuration module initialized"
}

# Check if UFW is installed
check_ufw_installed() {
    if command -v ufw >/dev/null 2>&1; then
        local ufw_version=$(ufw --version 2>/dev/null | head -n1 || echo "unknown")
        log_info "UFW is installed: $ufw_version"
        return 0
    else
        log_info "UFW is not installed"
        return 1
    fi
}

# Install UFW if not present
install_ufw() {
    log_info "Installing UFW..."

    # Update package lists first
    local update_cmd="apt-get update"
    if ! isolated_sudo_command "$update_cmd" 300 "Update package lists"; then
        log_error "Failed to update package lists"
        return 1
    fi

    # Install UFW
    local install_cmd="DEBIAN_FRONTEND=noninteractive apt-get install -y ufw"
    if isolated_sudo_command "$install_cmd" 300 "Install UFW"; then
        log_success "UFW installed successfully"
        return 0
    else
        log_error "Failed to install UFW"
        return 1
    fi
}

# Check current UFW status
check_ufw_status() {
    log_info "Checking UFW status..."

    local status_cmd="ufw status verbose"
    if safe_execute "$status_cmd" 30 "UFW status check"; then
        return 0
    else
        log_warning "Could not check UFW status"
        return 1
    fi
}

# Detect current SSH port
detect_ssh_port() {
    local ssh_port="$DEFAULT_SSH_PORT"

    # Check sshd_config for custom port
    if [[ -f /etc/ssh/sshd_config ]]; then
        local custom_port=$(grep -E "^Port\s+" /etc/ssh/sshd_config | awk '{print $2}' || echo "")
        if [[ -n "$custom_port" ]] && [[ "$custom_port" =~ ^[0-9]+$ ]]; then
            ssh_port="$custom_port"
        fi
    fi

    # Verify port is in use
    if ss -tlnp | grep -q ":${ssh_port}\s"; then
        log_info "Detected SSH port: $ssh_port"
        echo "$ssh_port"
    else
        log_warning "SSH port $ssh_port not found in listening ports, using default"
        echo "$DEFAULT_SSH_PORT"
    fi
}

# Backup current UFW configuration
backup_ufw_config() {
    log_info "Creating UFW configuration backup..."

    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${BACKUP_DIR}/ufw_backup_${backup_timestamp}.tar.gz"

    if [[ ! -d "$BACKUP_DIR" ]]; then
        sudo mkdir -p "$BACKUP_DIR"
        sudo chown "$USER:$USER" "$BACKUP_DIR"
    fi

    # Backup UFW configuration files
    local backup_paths=(
        "/etc/ufw/"
        "/lib/ufw/"
        "/etc/default/ufw"
    )

    local backup_cmd="tar -czf '$backup_file'"
    for path in "${backup_paths[@]}"; do
        if [[ -e "$path" ]]; then
            backup_cmd+=" '$path'"
        fi
    done

    # Add current UFW status to backup
    local status_file="${BACKUP_DIR}/ufw_status_${backup_timestamp}.txt"
    ufw status verbose > "$status_file" 2>/dev/null || echo "UFW status unavailable" > "$status_file"
    backup_cmd+=" '$status_file'"

    if safe_execute "$backup_cmd" 300 "UFW configuration backup"; then
        log_success "UFW configuration backed up: $backup_file"
        echo "$backup_file"
        return 0
    else
        log_error "Failed to backup UFW configuration"
        return 1
    fi
}

# Reset UFW to defaults
reset_ufw() {
    log_info "Resetting UFW to default configuration..."

    local reset_cmd="ufw --force reset"
    if isolated_sudo_command "$reset_cmd" "$UFW_TIMEOUT" "UFW reset"; then
        log_success "UFW reset to defaults"
        return 0
    else
        log_error "Failed to reset UFW"
        return 1
    fi
}

# Configure UFW default policies
set_ufw_defaults() {
    log_info "Setting UFW default policies..."

    local default_commands=(
        "ufw default deny incoming"
        "ufw default allow outgoing"
        "ufw default deny forward"
    )

    for cmd in "${default_commands[@]}"; do
        if isolated_sudo_command "$cmd" "$UFW_TIMEOUT" "UFW default policy: $cmd"; then
            log_debug "Default policy set: $cmd"
        else
            log_error "Failed to set default policy: $cmd"
            return 1
        fi
    done

    log_success "UFW default policies configured"
    return 0
}

# Allow SSH access
allow_ssh_access() {
    local ssh_port="${1:-$(detect_ssh_port)}"
    local comment="${2:-SSH Access}"

    log_info "Allowing SSH access on port $ssh_port..."

    # Validate port number
    if ! [[ "$ssh_port" =~ ^[0-9]+$ ]] || [[ "$ssh_port" -lt 1 ]] || [[ "$ssh_port" -gt 65535 ]]; then
        log_error "Invalid SSH port: $ssh_port"
        return 1
    fi

    local ssh_cmd="ufw allow $ssh_port/tcp comment '$comment'"
    if isolated_sudo_command "$ssh_cmd" "$UFW_TIMEOUT" "Allow SSH port $ssh_port"; then
        log_success "SSH access allowed on port $ssh_port"
        return 0
    else
        log_error "Failed to allow SSH access"
        return 1
    fi
}

# Allow HTTP/HTTPS access
allow_web_access() {
    log_info "Allowing HTTP and HTTPS access..."

    local web_commands=(
        "ufw allow 80/tcp comment 'HTTP'"
        "ufw allow 443/tcp comment 'HTTPS'"
    )

    for cmd in "${web_commands[@]}"; do
        if isolated_sudo_command "$cmd" "$UFW_TIMEOUT" "Web access: $cmd"; then
            log_debug "Web access rule added: $cmd"
        else
            log_error "Failed to add web access rule: $cmd"
            return 1
        fi
    done

    log_success "HTTP and HTTPS access allowed"
    return 0
}

# Allow custom port
allow_custom_port() {
    local port="$1"
    local protocol="${2:-tcp}"
    local comment="${3:-Custom Port}"
    local source="${4:-any}"

    log_info "Allowing access to port $port/$protocol..."

    # Validate port number
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        log_error "Invalid port number: $port"
        return 1
    fi

    # Validate protocol
    if [[ "$protocol" != "tcp" ]] && [[ "$protocol" != "udp" ]]; then
        log_error "Invalid protocol: $protocol. Must be tcp or udp"
        return 1
    fi

    # Build UFW command
    local ufw_cmd="ufw allow"
    if [[ "$source" != "any" ]]; then
        ufw_cmd+=" from $source"
    fi
    ufw_cmd+=" to any port $port proto $protocol comment '$comment'"

    if isolated_sudo_command "$ufw_cmd" "$UFW_TIMEOUT" "Allow port $port/$protocol"; then
        log_success "Access allowed to port $port/$protocol"
        return 0
    else
        log_error "Failed to allow port $port/$protocol"
        return 1
    fi
}

# Block specific IP or network
block_ip() {
    local ip="$1"
    local comment="${2:-Blocked IP}"

    log_info "Blocking IP/network: $ip..."

    # Basic IP validation
    if [[ ! "$ip" =~ ^[0-9./]+$ ]]; then
        log_error "Invalid IP address format: $ip"
        return 1
    fi

    local block_cmd="ufw deny from $ip comment '$comment'"
    if isolated_sudo_command "$block_cmd" "$UFW_TIMEOUT" "Block IP $ip"; then
        log_success "IP/network blocked: $ip"
        return 0
    else
        log_error "Failed to block IP: $ip"
        return 1
    fi
}

# Enable UFW
enable_ufw() {
    log_info "Enabling UFW..."

    # Double-check that SSH is allowed before enabling
    local ssh_port=$(detect_ssh_port)
    if ! ufw status | grep -q "$ssh_port/tcp"; then
        log_warning "SSH port $ssh_port not found in UFW rules. Adding it now..."
        allow_ssh_access "$ssh_port"
    fi

    local enable_cmd="ufw --force enable"
    if isolated_sudo_command "$enable_cmd" "$UFW_TIMEOUT" "Enable UFW"; then
        log_success "UFW enabled successfully"
        return 0
    else
        log_error "Failed to enable UFW"
        return 1
    fi
}

# Disable UFW
disable_ufw() {
    log_info "Disabling UFW..."

    local disable_cmd="ufw disable"
    if isolated_sudo_command "$disable_cmd" "$UFW_TIMEOUT" "Disable UFW"; then
        log_success "UFW disabled"
        return 0
    else
        log_error "Failed to disable UFW"
        return 1
    fi
}

# Configure UFW logging
configure_ufw_logging() {
    local log_level="${1:-low}"  # off, low, medium, high, full

    log_info "Setting UFW logging level to: $log_level"

    local logging_cmd="ufw logging $log_level"
    if isolated_sudo_command "$logging_cmd" "$UFW_TIMEOUT" "UFW logging configuration"; then
        log_success "UFW logging set to: $log_level"
        return 0
    else
        log_error "Failed to configure UFW logging"
        return 1
    fi
}

# Show UFW status with detailed information
show_ufw_status() {
    log_info "UFW Status Report:"
    echo -e "${BLUE}════════════════════════════════════════${NC}"

    # Basic status
    if command -v ufw >/dev/null 2>&1; then
        echo -e "${GREEN}UFW Installation:${NC} ✓ Installed"

        # Detailed status
        local status_output=$(ufw status verbose 2>/dev/null || echo "Status unavailable")
        echo -e "${CYAN}Current Status:${NC}"
        echo "$status_output" | sed 's/^/  /'

        # Rules count
        local rules_count=$(ufw status numbered 2>/dev/null | grep -c '^\[' || echo "0")
        echo -e "${CYAN}Active Rules:${NC} $rules_count"

        # Logging status
        local log_status=$(echo "$status_output" | grep "Logging:" | cut -d' ' -f2 || echo "unknown")
        echo -e "${CYAN}Logging Level:${NC} $log_status"

    else
        echo -e "${RED}UFW Installation:${NC} ✗ Not installed"
    fi

    echo -e "${BLUE}════════════════════════════════════════${NC}"
}

# Restore UFW configuration from backup
restore_ufw_config() {
    local backup_file="$1"

    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi

    log_warning "Restoring UFW configuration from backup: $backup_file"

    # Disable UFW first
    disable_ufw

    # Extract backup
    local restore_cmd="tar -xzf '$backup_file' -C /"
    if isolated_sudo_command "$restore_cmd" 300 "UFW configuration restore"; then
        log_success "UFW configuration restored from backup"

        # Reload UFW
        local reload_cmd="ufw reload"
        if isolated_sudo_command "$reload_cmd" "$UFW_TIMEOUT" "UFW reload after restore"; then
            log_success "UFW reloaded successfully"
            return 0
        else
            log_error "Failed to reload UFW after restore"
            return 1
        fi
    else
        log_error "Failed to restore UFW configuration"
        return 1
    fi
}

# Main UFW configuration function
configure_ufw() {
    local ssh_port="${1:-$(detect_ssh_port)}"
    local enable_web="${2:-true}"
    local log_level="${3:-low}"
    local create_backup="${4:-true}"

    log_info "Starting UFW configuration"

    # Initialize logging
    init_logging

    # Install UFW if not present
    if ! check_ufw_installed; then
        if ! install_ufw; then
            log_error "Failed to install UFW"
            return 1
        fi
    fi

    # Create backup if requested
    local backup_file=""
    if [[ "$create_backup" == "true" ]]; then
        if ! backup_file=$(backup_ufw_config); then
            log_warning "Backup creation failed, continuing without backup"
        fi
    fi

    # Reset UFW to defaults
    if ! reset_ufw; then
        log_error "Failed to reset UFW"
        return 1
    fi

    # Set default policies
    if ! set_ufw_defaults; then
        log_error "Failed to set UFW defaults"
        return 1
    fi

    # Allow SSH access
    if ! allow_ssh_access "$ssh_port"; then
        log_error "Failed to allow SSH access"

        # Restore backup if available
        if [[ -n "$backup_file" ]] && [[ -f "$backup_file" ]]; then
            read -p "Do you want to restore from backup? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                restore_ufw_config "$backup_file"
            fi
        fi
        return 1
    fi

    # Allow web access if requested
    if [[ "$enable_web" == "true" ]]; then
        if ! allow_web_access; then
            log_error "Failed to allow web access"
            return 1
        fi
    fi

    # Configure logging
    if ! configure_ufw_logging "$log_level"; then
        log_warning "Failed to configure UFW logging"
    fi

    # Enable UFW
    if ! enable_ufw; then
        log_error "Failed to enable UFW"
        return 1
    fi

    # Show final status
    show_ufw_status

    log_success "UFW configuration completed successfully"
    return 0
}

# Quick UFW setup for VPN server
setup_vpn_firewall() {
    log_info "Setting up firewall for VPN server..."

    # Configure basic UFW
    if ! configure_ufw "$(detect_ssh_port)" "true" "low" "true"; then
        log_error "Failed to configure basic firewall"
        return 1
    fi

    # Add VPN-specific rules if needed
    # These would be added based on specific VPN requirements
    log_info "Basic VPN firewall setup completed"
    return 0
}

# Interactive UFW configuration
interactive_ufw_config() {
    echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       UFW Firewall Manager           ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
    echo

    # Show current status
    show_ufw_status
    echo

    echo "Available options:"
    echo "1) Configure UFW for VPN server (recommended)"
    echo "2) Custom UFW configuration"
    echo "3) Add custom port rule"
    echo "4) Block IP address"
    echo "5) Show current status"
    echo "6) Reset UFW configuration"
    echo "7) Disable UFW"
    echo "8) Exit"
    echo

    while true; do
        read -p "Please select an option (1-8): " choice

        case $choice in
            1)
                echo -e "\n${GREEN}Configuring UFW for VPN server...${NC}"
                setup_vpn_firewall
                break
                ;;
            2)
                echo -e "\n${CYAN}Custom UFW Configuration${NC}"
                read -p "SSH port (default: $(detect_ssh_port)): " custom_ssh_port
                custom_ssh_port=${custom_ssh_port:-$(detect_ssh_port)}

                read -p "Allow HTTP/HTTPS? (Y/n): " -n 1 -r allow_web
                echo
                [[ ! $allow_web =~ ^[Nn]$ ]] && allow_web="true" || allow_web="false"

                echo "Log levels: off, low, medium, high, full"
                read -p "Log level (default: low): " log_level
                log_level=${log_level:-low}

                configure_ufw "$custom_ssh_port" "$allow_web" "$log_level" "true"
                break
                ;;
            3)
                echo -e "\n${CYAN}Add Custom Port Rule${NC}"
                read -p "Port number: " port
                read -p "Protocol (tcp/udp, default: tcp): " protocol
                protocol=${protocol:-tcp}
                read -p "Comment: " comment
                comment=${comment:-"Custom Port"}

                if [[ -n "$port" ]]; then
                    allow_custom_port "$port" "$protocol" "$comment"
                fi
                echo
                ;;
            4)
                echo -e "\n${CYAN}Block IP Address${NC}"
                read -p "IP address or network: " ip_address
                read -p "Comment: " comment
                comment=${comment:-"Blocked IP"}

                if [[ -n "$ip_address" ]]; then
                    block_ip "$ip_address" "$comment"
                fi
                echo
                ;;
            5)
                echo -e "\n${CYAN}Current UFW Status:${NC}"
                show_ufw_status
                echo
                ;;
            6)
                echo -e "\n${YELLOW}WARNING: This will reset all UFW rules${NC}"
                read -p "Are you sure? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    reset_ufw
                    echo "UFW has been reset. You may want to reconfigure it."
                fi
                echo
                ;;
            7)
                echo -e "\n${YELLOW}WARNING: This will disable the firewall${NC}"
                read -p "Are you sure? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    disable_ufw
                fi
                echo
                ;;
            8)
                echo "Exiting UFW configuration."
                break
                ;;
            *)
                echo -e "${RED}Invalid option. Please select 1-8.${NC}"
                ;;
        esac
    done
}

# Export functions for use by other modules
export -f configure_ufw
export -f setup_vpn_firewall
export -f check_ufw_installed
export -f allow_custom_port
export -f block_ip
export -f show_ufw_status
export -f interactive_ufw_config

# If script is run directly, start interactive mode
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Parse command line arguments
    case "${1:-interactive}" in
        "configure")
            configure_ufw "${2:-$(detect_ssh_port)}" "${3:-true}" "${4:-low}" "${5:-true}"
            ;;
        "vpn")
            setup_vpn_firewall
            ;;
        "status")
            show_ufw_status
            ;;
        "reset")
            reset_ufw
            ;;
        "disable")
            disable_ufw
            ;;
        "interactive"|"")
            interactive_ufw_config
            ;;
        *)
            echo "Usage: $0 [configure|vpn|status|reset|disable|interactive]"
            echo "  configure [ssh_port] [allow_web] [log_level] [backup] - Configure UFW"
            echo "  vpn                                                   - Setup VPN firewall"
            echo "  status                                               - Show UFW status"
            echo "  reset                                                - Reset UFW to defaults"
            echo "  disable                                              - Disable UFW"
            echo "  interactive                                          - Interactive menu (default)"
            exit 1
            ;;
    esac
fi