#!/bin/bash

# UFW Firewall Configuration Module for VLESS+Reality VPN
# This module safely configures UFW with proper rules for VPN while preserving existing rules
# Version: 1.0

set -euo pipefail

# Import common utilities and process isolation
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_utils.sh" 2>/dev/null || {
    echo "Error: Cannot find common_utils.sh"
    exit 1
}

# Import process isolation module
source "${SCRIPT_DIR}/process_isolation/process_safe.sh" 2>/dev/null || {
    log_warn "Process isolation module not found, using standard execution"
}

# Setup signal handlers if process isolation is available
if command -v setup_signal_handlers >/dev/null 2>&1; then
    setup_signal_handlers
fi

# Configuration
readonly UFW_BACKUP_DIR="/opt/vless/backups/ufw"
readonly UFW_RULES_BACKUP="${UFW_BACKUP_DIR}/ufw_rules_$(date +%Y%m%d_%H%M%S).backup"
readonly VLESS_PORTS=(443)  # HTTPS/Reality port
readonly SSH_PORTS=(22 2222)  # Default and alternative SSH ports

# Create backup directory
create_backup_directory() {
    log_info "Creating UFW backup directory"
    mkdir -p "${UFW_BACKUP_DIR}"
    chmod 700 "${UFW_BACKUP_DIR}"
}

# Backup existing UFW rules
backup_existing_ufw_rules() {
    log_info "Backing up existing UFW configuration"

    if ! command -v ufw >/dev/null 2>&1; then
        log_info "UFW not installed, skipping backup"
        return 0
    fi

    create_backup_directory

    # Backup UFW status and rules
    {
        echo "# UFW Status and Rules Backup - $(date)"
        echo "# UFW Status:"
        ufw status verbose 2>/dev/null || echo "UFW status unavailable"
        echo ""
        echo "# UFW Rules:"
        ufw show added 2>/dev/null || echo "UFW rules unavailable"
        echo ""
        echo "# UFW Application List:"
        ufw app list 2>/dev/null || echo "UFW app list unavailable"
    } > "${UFW_RULES_BACKUP}"

    # Backup UFW configuration files
    if [[ -d /etc/ufw ]]; then
        tar -czf "${UFW_BACKUP_DIR}/ufw_config_$(date +%Y%m%d_%H%M%S).tar.gz" \
            -C /etc ufw/ 2>/dev/null || log_warn "Could not backup UFW config files"
    fi

    log_info "UFW backup saved to: ${UFW_RULES_BACKUP}"
}

# Install UFW if not present
install_ufw() {
    if command -v ufw >/dev/null 2>&1; then
        log_info "UFW already installed"
        return 0
    fi

    log_info "Installing UFW firewall"

    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y ufw
    elif command -v yum >/dev/null 2>&1; then
        yum install -y ufw
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y ufw
    else
        log_error "Cannot install UFW: unsupported package manager"
        return 1
    fi

    log_info "UFW installed successfully"
}

# Analyze existing UFW rules
analyze_existing_rules() {
    log_info "Analyzing existing UFW rules"

    if ! ufw status >/dev/null 2>&1; then
        log_info "UFW not active or not installed"
        return 0
    fi

    local status_output
    status_output=$(ufw status verbose 2>/dev/null || echo "")

    if [[ -n "$status_output" ]]; then
        log_info "Current UFW status:"
        echo "$status_output" | while IFS= read -r line; do
            log_info "  $line"
        done

        # Check for potential conflicts
        local has_conflicts=false

        # Check if VLESS ports are already in use
        for port in "${VLESS_PORTS[@]}"; do
            if echo "$status_output" | grep -q "$port"; then
                log_warn "Port $port already has UFW rules configured"
                has_conflicts=true
            fi
        done

        if $has_conflicts; then
            log_warn "Potential port conflicts detected. Review existing rules carefully."
        fi
    fi
}

# Configure UFW default policies
configure_default_policies() {
    log_info "Configuring UFW default policies"

    # Set secure defaults
    ufw --force default deny incoming
    ufw --force default allow outgoing
    ufw --force default deny forward

    log_info "Default UFW policies configured"
}

# Add SSH rules to prevent lockout
add_ssh_rules() {
    log_info "Adding SSH access rules to prevent lockout"

    # Get current SSH port from config
    local ssh_port
    ssh_port=$(grep -E "^#?Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1)
    ssh_port=${ssh_port:-22}

    # Add SSH rule for current port
    ufw allow "$ssh_port/tcp" comment "SSH access"

    # Add common SSH ports if different
    for port in "${SSH_PORTS[@]}"; do
        if [[ "$port" != "$ssh_port" ]]; then
            ufw allow "$port/tcp" comment "Alternative SSH port"
        fi
    done

    log_info "SSH access rules added for ports: $ssh_port ${SSH_PORTS[*]}"
}

# Add VLESS/Reality VPN rules
add_vless_rules() {
    log_info "Adding VLESS+Reality VPN firewall rules"

    # Add HTTPS/Reality port (443)
    for port in "${VLESS_PORTS[@]}"; do
        ufw allow "$port/tcp" comment "VLESS+Reality VPN"
        log_info "Added rule for VLESS port: $port/tcp"
    done

    # Add rate limiting to prevent abuse
    ufw limit ssh comment "SSH rate limiting"

    log_info "VLESS VPN firewall rules added"
}

# Add additional security rules
add_security_rules() {
    log_info "Adding additional security rules"

    # Block common attack vectors
    ufw deny 1433/tcp comment "Block MSSQL"
    ufw deny 3306/tcp comment "Block MySQL"
    ufw deny 5432/tcp comment "Block PostgreSQL"

    # Allow loopback
    ufw allow in on lo
    ufw allow out on lo

    # Allow established connections
    ufw allow in on any to any port 53 comment "DNS"

    log_info "Additional security rules added"
}

# Validate UFW configuration
validate_ufw_config() {
    log_info "Validating UFW configuration"

    # Check UFW status
    local ufw_status
    ufw_status=$(ufw status 2>/dev/null || echo "inactive")

    if [[ "$ufw_status" == "inactive" ]]; then
        log_error "UFW is not active"
        return 1
    fi

    # Verify essential rules exist
    local rules_output
    rules_output=$(ufw status numbered 2>/dev/null || echo "")

    # Check SSH access
    if ! echo "$rules_output" | grep -q "22\|ssh"; then
        log_error "No SSH access rule found - potential lockout risk!"
        return 1
    fi

    # Check VLESS ports
    local vless_rules_found=0
    for port in "${VLESS_PORTS[@]}"; do
        if echo "$rules_output" | grep -q "$port"; then
            ((vless_rules_found++))
        fi
    done

    if [[ $vless_rules_found -eq 0 ]]; then
        log_error "No VLESS VPN rules found"
        return 1
    fi

    log_info "UFW configuration validation passed"

    # Display final status
    log_info "Final UFW status:"
    ufw status verbose | while IFS= read -r line; do
        log_info "  $line"
    done
}

# Enable UFW firewall
enable_ufw() {
    log_info "Enabling UFW firewall"

    # Enable UFW with force to avoid interactive prompt
    ufw --force enable

    # Verify UFW is running
    if ufw status | grep -q "Status: active"; then
        log_info "UFW firewall enabled successfully"
    else
        log_error "Failed to enable UFW firewall"
        return 1
    fi
}

# Rollback UFW changes in case of emergency
rollback_ufw_changes() {
    log_warn "Rolling back UFW changes"

    # Disable UFW first
    ufw --force disable

    # Reset UFW to defaults
    ufw --force reset

    log_warn "UFW has been reset to defaults. Manual reconfiguration required."
    log_info "Backup available at: ${UFW_RULES_BACKUP}"
}

# Setup UFW logging
setup_ufw_logging() {
    log_info "Configuring UFW logging"

    # Enable UFW logging at medium level
    ufw logging medium

    # Configure log rotation if rsyslog is available
    if command -v rsyslogd >/dev/null 2>&1; then
        cat > /etc/rsyslog.d/20-ufw.conf << 'EOF'
# UFW logging configuration
:msg,contains,"[UFW " /var/log/ufw.log
& stop
EOF

        # Create logrotate configuration for UFW logs
        cat > /etc/logrotate.d/ufw << 'EOF'
/var/log/ufw.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 640 root adm
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate
    endscript
}
EOF

        # Restart rsyslog if safe to do so
        if command -v systemctl >/dev/null 2>&1; then
            if [[ $(type -t isolate_systemctl_command) == function ]]; then
                isolate_systemctl_command "restart" "rsyslog" 30
            else
                systemctl restart rsyslog 2>/dev/null || log_warn "Could not restart rsyslog"
            fi
        fi

        log_info "UFW logging configured with rotation"
    fi
}

# Main UFW configuration function
configure_ufw_firewall() {
    log_info "Starting UFW firewall configuration"

    # Ensure running as root
    if ! validate_root; then
        log_error "UFW configuration requires root privileges"
        return 1
    fi

    # Backup existing configuration
    backup_existing_ufw_rules

    # Install UFW if needed
    install_ufw

    # Analyze existing rules
    analyze_existing_rules

    # Configure UFW step by step
    configure_default_policies
    add_ssh_rules
    add_vless_rules
    add_security_rules
    setup_ufw_logging

    # Enable UFW
    enable_ufw

    # Validate configuration
    if ! validate_ufw_config; then
        log_error "UFW configuration validation failed"
        read -p "Do you want to rollback changes? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rollback_ufw_changes
        fi
        return 1
    fi

    log_info "UFW firewall configuration completed successfully"
    log_info "Backup saved to: ${UFW_RULES_BACKUP}"
}

# Display current UFW status
show_ufw_status() {
    log_info "Current UFW status:"

    if command -v ufw >/dev/null 2>&1; then
        ufw status verbose
    else
        log_error "UFW is not installed"
    fi
}

# Add custom rule
add_custom_rule() {
    local rule="$1"
    local comment="${2:-Custom rule}"

    log_info "Adding custom UFW rule: $rule"

    if ufw "$rule" comment "$comment"; then
        log_info "Custom rule added successfully"
    else
        log_error "Failed to add custom rule: $rule"
        return 1
    fi
}

# Remove rule by number
remove_rule_by_number() {
    local rule_number="$1"

    log_info "Removing UFW rule number: $rule_number"

    if ufw --force delete "$rule_number"; then
        log_info "Rule removed successfully"
    else
        log_error "Failed to remove rule number: $rule_number"
        return 1
    fi
}

# Main script execution
main() {
    case "${1:-}" in
        "configure"|"")
            configure_ufw_firewall
            ;;
        "status")
            show_ufw_status
            ;;
        "backup")
            backup_existing_ufw_rules
            ;;
        "rollback")
            rollback_ufw_changes
            ;;
        "add")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 add <rule> [comment]"
                exit 1
            fi
            add_custom_rule "$2" "${3:-}"
            ;;
        "remove")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 remove <rule_number>"
                exit 1
            fi
            remove_rule_by_number "$2"
            ;;
        "help"|"-h"|"--help")
            cat << EOF
UFW Configuration Module for VLESS+Reality VPN

Usage: $0 [command] [options]

Commands:
    configure     Configure UFW with VLESS VPN rules (default)
    status        Show current UFW status
    backup        Backup current UFW configuration
    rollback      Reset UFW to defaults (emergency use)
    add <rule>    Add custom UFW rule
    remove <num>  Remove rule by number
    help          Show this help message

Examples:
    $0 configure              # Full UFW configuration
    $0 status                 # Show UFW status
    $0 add "allow 8080/tcp"   # Add custom rule
    $0 remove 5               # Remove rule number 5

This module safely configures UFW firewall with proper rules for
VLESS+Reality VPN while preserving existing firewall rules.
EOF
            ;;
        *)
            log_error "Unknown command: $1"
            log_info "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi