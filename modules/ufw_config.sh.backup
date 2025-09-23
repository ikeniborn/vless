#!/bin/bash

# VLESS+Reality VPN Management System - UFW Firewall Configuration
# Version: 1.0.0
# Description: Automated firewall setup with minimal attack surface
#
# Features:
# - Default deny all incoming traffic
# - Allow SSH (port 22) with rate limiting
# - Allow VLESS (port 443)
# - Allow HTTP fallback (port 80) if needed
# - Existing rule conflict detection
# - Firewall rule backup and restore
# - Process isolation for EPERM prevention

set -euo pipefail

# Import common utilities
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SOURCE_DIR}/common_utils.sh"

# Setup signal handlers
setup_signal_handlers

# Configuration
readonly UFW_BACKUP_DIR="/opt/vless/backup/ufw"
readonly UFW_RULES_BACKUP="${UFW_BACKUP_DIR}/ufw_rules_$(date +%Y%m%d_%H%M%S).backup"

# Initialize UFW configuration module
init_ufw_config() {
    log_info "Initializing UFW firewall configuration module"

    # Create backup directory
    create_directory "$UFW_BACKUP_DIR" "700" "root"

    # Install UFW if not present
    install_package_if_missing "ufw"

    log_success "UFW configuration module initialized"
}

# Backup current UFW rules
backup_ufw_rules() {
    log_info "Backing up current UFW rules"

    if command_exists ufw; then
        # Create comprehensive backup
        {
            echo "# UFW Rules Backup - $(get_timestamp)"
            echo "# Current UFW status"
            ufw status verbose 2>/dev/null || echo "UFW status: unknown"
            echo ""
            echo "# UFW rules (numbered)"
            ufw status numbered 2>/dev/null || echo "No numbered rules available"
            echo ""
            echo "# Raw UFW rules"
            if [[ -f /etc/ufw/user.rules ]]; then
                echo "## /etc/ufw/user.rules"
                cat /etc/ufw/user.rules
            fi
            if [[ -f /etc/ufw/user6.rules ]]; then
                echo "## /etc/ufw/user6.rules"
                cat /etc/ufw/user6.rules
            fi
        } > "$UFW_RULES_BACKUP"

        chmod 600 "$UFW_RULES_BACKUP"
        log_success "UFW rules backed up to: $UFW_RULES_BACKUP"
        echo "$UFW_RULES_BACKUP"
    else
        log_warn "UFW not installed, no backup needed"
        return 1
    fi
}

# Check for conflicting firewall rules
check_firewall_conflicts() {
    log_info "Checking for conflicting firewall configurations"

    local conflicts_found=false

    # Check for iptables rules
    if command_exists iptables; then
        local iptables_rules
        iptables_rules=$(iptables -L 2>/dev/null | wc -l)
        if [[ $iptables_rules -gt 10 ]]; then
            log_warn "Existing iptables rules detected ($iptables_rules lines)"
            conflicts_found=true
        fi
    fi

    # Check for other firewall services
    local firewall_services=("firewalld" "iptables-persistent" "netfilter-persistent")
    local service

    for service in "${firewall_services[@]}"; do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            log_warn "Active firewall service detected: $service"
            conflicts_found=true
        fi
    done

    if [[ "$conflicts_found" == "true" ]]; then
        log_warn "Firewall conflicts detected. Manual review recommended."
        return 1
    else
        log_success "No firewall conflicts detected"
        return 0
    fi
}

# Reset UFW to default state
reset_ufw_rules() {
    log_info "Resetting UFW to default state"

    # Reset UFW rules
    safe_execute 30 ufw --force reset

    log_success "UFW rules reset to default state"
}

# Configure basic UFW policies
configure_ufw_policies() {
    log_info "Configuring UFW default policies"

    # Set default policies
    safe_execute 30 ufw default deny incoming
    safe_execute 30 ufw default allow outgoing
    safe_execute 30 ufw default deny forward

    log_success "UFW default policies configured"
}

# Configure SSH access with rate limiting
configure_ssh_access() {
    local ssh_port="${1:-22}"

    log_info "Configuring SSH access on port $ssh_port"

    # Allow SSH with rate limiting
    safe_execute 30 ufw limit "$ssh_port/tcp" comment "SSH with rate limiting"

    log_success "SSH access configured on port $ssh_port with rate limiting"
}

# Configure VLESS port access
configure_vless_access() {
    local vless_port="${1:-443}"

    log_info "Configuring VLESS access on port $vless_port"

    # Allow VLESS port
    safe_execute 30 ufw allow "$vless_port/tcp" comment "VLESS VPN"

    log_success "VLESS access configured on port $vless_port"
}

# Configure HTTP fallback if needed
configure_http_fallback() {
    local http_port="${1:-80}"
    local enable_http="${2:-false}"

    if [[ "$enable_http" == "true" ]]; then
        log_info "Configuring HTTP fallback on port $http_port"

        # Allow HTTP port
        safe_execute 30 ufw allow "$http_port/tcp" comment "HTTP fallback"

        log_success "HTTP fallback configured on port $http_port"
    else
        log_debug "HTTP fallback disabled"
    fi
}

# Configure logging
configure_ufw_logging() {
    local log_level="${1:-low}"

    log_info "Configuring UFW logging level: $log_level"

    # Set logging level
    safe_execute 30 ufw logging "$log_level"

    log_success "UFW logging configured: $log_level"
}

# Add custom rule
add_ufw_rule() {
    local rule="$1"
    local comment="${2:-Custom rule}"

    log_info "Adding UFW rule: $rule"

    # Add the rule
    safe_execute 30 ufw "$rule" comment "$comment"

    log_success "UFW rule added: $rule"
}

# Remove UFW rule by number
remove_ufw_rule() {
    local rule_number="$1"

    log_info "Removing UFW rule number: $rule_number"

    # Remove the rule
    safe_execute 30 ufw --force delete "$rule_number"

    log_success "UFW rule removed: $rule_number"
}

# Enable UFW firewall
enable_ufw() {
    log_info "Enabling UFW firewall"

    # Enable UFW
    safe_execute 30 ufw --force enable

    # Ensure UFW starts on boot
    isolate_systemctl_command "enable" "ufw" 30

    log_success "UFW firewall enabled and set to start on boot"
}

# Disable UFW firewall
disable_ufw() {
    log_info "Disabling UFW firewall"

    # Disable UFW
    safe_execute 30 ufw --force disable

    log_success "UFW firewall disabled"
}

# Get UFW status
get_ufw_status() {
    log_info "Getting UFW status"

    if command_exists ufw; then
        ufw status verbose
    else
        log_error "UFW not installed"
        return 1
    fi
}

# List UFW rules with numbers
list_ufw_rules() {
    log_info "Listing UFW rules"

    if command_exists ufw; then
        ufw status numbered
    else
        log_error "UFW not installed"
        return 1
    fi
}

# Validate UFW configuration
validate_ufw_config() {
    log_info "Validating UFW configuration"

    local validation_errors=0

    # Check if UFW is installed
    if ! command_exists ufw; then
        log_error "UFW is not installed"
        ((validation_errors++))
    fi

    # Check if UFW is enabled
    if ! ufw status | grep -q "Status: active"; then
        log_warn "UFW is not active"
        ((validation_errors++))
    fi

    # Check default policies
    local status_output
    status_output=$(ufw status verbose)

    if ! echo "$status_output" | grep -q "Default: deny (incoming)"; then
        log_error "Default incoming policy is not deny"
        ((validation_errors++))
    fi

    if ! echo "$status_output" | grep -q "Default: allow (outgoing)"; then
        log_error "Default outgoing policy is not allow"
        ((validation_errors++))
    fi

    # Check essential rules
    if ! ufw status | grep -q "22/tcp"; then
        log_warn "SSH rule (port 22) not found"
    fi

    if ! ufw status | grep -q "443/tcp"; then
        log_warn "VLESS rule (port 443) not found"
    fi

    if [[ $validation_errors -eq 0 ]]; then
        log_success "UFW configuration validation passed"
        return 0
    else
        log_error "UFW configuration validation failed with $validation_errors errors"
        return 1
    fi
}

# Complete UFW setup for VLESS VPN
setup_vless_firewall() {
    local ssh_port="${1:-22}"
    local vless_port="${2:-443}"
    local enable_http="${3:-false}"
    local http_port="${4:-80}"

    log_info "Setting up UFW firewall for VLESS VPN"
    log_info "SSH: $ssh_port, VLESS: $vless_port, HTTP: $enable_http ($http_port)"

    # Initialize
    init_ufw_config

    # Backup existing rules
    local backup_file
    backup_file=$(backup_ufw_rules) || true

    # Check for conflicts
    if ! check_firewall_conflicts; then
        log_warn "Firewall conflicts detected. Proceeding with caution."
    fi

    # Reset and configure UFW
    reset_ufw_rules
    configure_ufw_policies

    # Configure access rules
    configure_ssh_access "$ssh_port"
    configure_vless_access "$vless_port"
    configure_http_fallback "$http_port" "$enable_http"

    # Configure logging
    configure_ufw_logging "low"

    # Enable firewall
    enable_ufw

    # Validate configuration
    if validate_ufw_config; then
        log_success "UFW firewall setup completed successfully"
        log_info "Backup file: ${backup_file:-none}"

        # Show final status
        echo ""
        log_info "Final UFW status:"
        get_ufw_status
    else
        log_error "UFW setup validation failed"
        return 1
    fi
}

# Restore UFW from backup
restore_ufw_from_backup() {
    local backup_file="$1"

    log_info "Restoring UFW from backup: $backup_file"

    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi

    # Disable UFW first
    disable_ufw

    # Reset rules
    reset_ufw_rules

    log_warn "Manual restoration required. Backup file: $backup_file"
    log_info "Review the backup file and manually recreate rules as needed"

    return 0
}

# Monitor UFW logs
monitor_ufw_logs() {
    local duration="${1:-60}"
    local max_lines="${2:-50}"

    log_info "Monitoring UFW logs for ${duration}s"

    local ufw_log="/var/log/ufw.log"
    if [[ -f "$ufw_log" ]]; then
        controlled_tail "$ufw_log" "$duration" "$max_lines"
    else
        log_warn "UFW log file not found: $ufw_log"
        log_info "Checking kernel logs for UFW entries"
        controlled_tail "/var/log/kern.log" "$duration" "$max_lines" | grep -i ufw || true
    fi
}

# Get firewall statistics
get_firewall_stats() {
    log_info "Getting firewall statistics"

    if command_exists ufw; then
        echo "=== UFW Status ==="
        ufw status verbose
        echo ""

        echo "=== UFW Application Profiles ==="
        ufw app list 2>/dev/null || echo "No application profiles available"
        echo ""

        if [[ -f /proc/net/netfilter/nfnetlink_queue ]]; then
            echo "=== Netfilter Queue Stats ==="
            cat /proc/net/netfilter/nfnetlink_queue
            echo ""
        fi

        echo "=== Recent UFW Log Entries ==="
        if [[ -f /var/log/ufw.log ]]; then
            tail -10 /var/log/ufw.log 2>/dev/null || echo "No recent UFW log entries"
        else
            grep -i ufw /var/log/kern.log 2>/dev/null | tail -10 || echo "No UFW entries in kernel log"
        fi
    else
        log_error "UFW not installed"
        return 1
    fi
}

# Export functions
export -f init_ufw_config backup_ufw_rules check_firewall_conflicts
export -f reset_ufw_rules configure_ufw_policies configure_ssh_access
export -f configure_vless_access configure_http_fallback configure_ufw_logging
export -f add_ufw_rule remove_ufw_rule enable_ufw disable_ufw
export -f get_ufw_status list_ufw_rules validate_ufw_config
export -f setup_vless_firewall restore_ufw_from_backup monitor_ufw_logs
export -f get_firewall_stats

log_debug "UFW configuration module loaded successfully"