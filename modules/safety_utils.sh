#!/bin/bash

# VLESS+Reality VPN Management System - Safety Utilities
# Version: 1.0.0
# Description: Safety checks and confirmation utilities for critical operations

set -euo pipefail

# Check if this file has already been sourced
if [[ "${SAFETY_UTILS_LOADED:-false}" == "true" ]]; then
    return 0
fi
readonly SAFETY_UTILS_LOADED=true

# Import common utilities
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SOURCE_DIR}/common_utils.sh"

# Enhanced confirmation with timeout
confirm_action() {
    local message="$1"
    local default="${2:-y}"
    local timeout="${3:-30}"

    # Skip confirmations in quick mode
    if [[ "${QUICK_MODE:-false}" == "true" ]]; then
        log_debug "Skipping confirmation in quick mode: $message"
        [[ "$default" == "y" ]] && return 0 || return 1
    fi

    local prompt
    if [[ "$default" == "y" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    echo -e "\n${YELLOW}${message}${NC}"
    echo -n "Confirm ${prompt} (timeout: ${timeout}s): "

    local response
    if read -t "$timeout" -r response; then
        response=${response,,}  # Convert to lowercase
        case "$response" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            "") [[ "$default" == "y" ]] && return 0 || return 1 ;;
            *) return 1 ;;
        esac
    else
        echo -e "\n${RED}Timeout reached. Using default: $default${NC}"
        [[ "$default" == "y" ]] && return 0 || return 1
    fi
}

# Check for existing firewall services
check_existing_firewall() {
    local verbose="${1:-}"
    local found_firewalls=()

    # Check for common firewall services
    if systemctl is-active --quiet iptables 2>/dev/null; then
        found_firewalls+=("iptables")
    fi

    if systemctl is-active --quiet firewalld 2>/dev/null; then
        found_firewalls+=("firewalld")
    fi

    if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
        found_firewalls+=("ufw")
    fi

    if [[ ${#found_firewalls[@]} -gt 0 ]]; then
        if [[ "$verbose" == "--verbose" ]]; then
            printf '%s\n' "${found_firewalls[@]}"
        fi
        return 0
    else
        return 1
    fi
}

# Show current SSH connections
show_current_ssh_connections() {
    echo -e "\n${CYAN}Current SSH connections:${NC}"
    if command -v ss >/dev/null; then
        ss -tuln | grep :22 || echo "No SSH connections found"
    elif command -v netstat >/dev/null; then
        netstat -tuln | grep :22 || echo "No SSH connections found"
    else
        echo "Cannot check SSH connections (ss/netstat not available)"
    fi
}

# Show planned firewall rules
show_planned_firewall_rules() {
    cat << EOF
  - Allow SSH (port 22)
  - Allow VLESS (port ${VLESS_PORT:-443})
  - Allow HTTP (port 80) for certificate validation
  - Allow HTTPS (port 443) for Reality
  - Deny all other incoming connections
EOF
}

# Backup current firewall rules
backup_current_firewall_rules() {
    local backup_dir="/opt/vless/backup/firewall"
    local timestamp=$(date +%Y%m%d_%H%M%S)

    create_directory "$backup_dir" "700" "root"

    # Backup iptables if available
    if command -v iptables-save >/dev/null; then
        iptables-save > "${backup_dir}/iptables_${timestamp}.rules"
        log_debug "Backed up iptables rules"
    fi

    # Backup UFW if active
    if command -v ufw >/dev/null; then
        cp -r /etc/ufw "${backup_dir}/ufw_${timestamp}/" 2>/dev/null || true
        log_debug "Backed up UFW configuration"
    fi
}

# Test SSH connectivity before applying changes
test_ssh_connectivity() {
    local test_port="${1:-22}"

    log_info "Testing SSH connectivity on port $test_port"

    # Simple connectivity test
    if timeout 5 bash -c "</dev/tcp/localhost/$test_port" 2>/dev/null; then
        log_success "SSH port $test_port is accessible"
        return 0
    else
        log_error "SSH port $test_port is not accessible"
        return 1
    fi
}

# Rollback safety - create restore point
create_restore_point() {
    local description="$1"
    local restore_dir="/opt/vless/restore_points"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local restore_point="${restore_dir}/${timestamp}_${description// /_}"

    create_directory "$restore_point" "700" "root"

    # Backup critical configurations
    local critical_files=(
        "/etc/ssh/sshd_config"
        "/etc/sysctl.conf"
        "/etc/ufw"
        "/opt/vless/config"
    )

    for file in "${critical_files[@]}"; do
        if [[ -e "$file" ]]; then
            cp -r "$file" "$restore_point/" 2>/dev/null || true
        fi
    done

    # Create restore script
    cat > "${restore_point}/restore.sh" << EOF
#!/bin/bash
# Restore point created: $(date)
# Description: $description

echo "Restoring configuration from: $restore_point"

# Restore SSH configuration
if [[ -f "${restore_point}/sshd_config" ]]; then
    cp "${restore_point}/sshd_config" /etc/ssh/sshd_config
    systemctl restart sshd
fi

# Restore sysctl configuration
if [[ -f "${restore_point}/sysctl.conf" ]]; then
    cp "${restore_point}/sysctl.conf" /etc/sysctl.conf
    sysctl -p
fi

# Restore UFW configuration
if [[ -d "${restore_point}/ufw" ]]; then
    cp -r "${restore_point}/ufw" /etc/
    ufw --force reload
fi

echo "Restore completed"
EOF

    chmod +x "${restore_point}/restore.sh"

    log_info "Restore point created: $restore_point"
    echo "To restore: sudo ${restore_point}/restore.sh"
}

# Check SSH key availability for current user
check_ssh_keys() {
    local current_user="${SUDO_USER:-$(whoami)}"
    local ssh_key_exists=false

    if [[ -f "/home/${current_user}/.ssh/authorized_keys" ]] && [[ -s "/home/${current_user}/.ssh/authorized_keys" ]]; then
        ssh_key_exists=true
    fi

    if [[ "$ssh_key_exists" == "true" ]]; then
        log_success "SSH keys found for user: $current_user"
        return 0
    else
        log_warn "No SSH keys found for user: $current_user"
        return 1
    fi
}

# Selective SSH hardening function
apply_selective_ssh_hardening() {
    local settings=("$@")
    local ssh_config="/etc/ssh/sshd_config"
    local ssh_backup="/tmp/sshd_config_backup_$(date +%Y%m%d_%H%M%S)"

    # Backup current configuration
    cp "$ssh_config" "$ssh_backup"
    log_info "SSH configuration backed up to: $ssh_backup"

    # Apply selected settings
    for setting in "${settings[@]}"; do
        local key="${setting%% *}"
        local value="${setting#* }"

        # Remove existing setting and add new one
        sed -i "/^#\?${key}/d" "$ssh_config"
        echo "$setting" >> "$ssh_config"

        log_debug "Applied SSH setting: $setting"
    done

    # Test configuration
    if sshd -t; then
        log_success "SSH configuration is valid"

        # Restart SSH service
        if isolate_systemctl_command "restart" "sshd" 30 || isolate_systemctl_command "restart" "ssh" 30; then
            log_success "SSH service restarted successfully"
            return 0
        else
            log_error "Failed to restart SSH service, restoring backup"
            cp "$ssh_backup" "$ssh_config"
            return 1
        fi
    else
        log_error "Invalid SSH configuration, restoring backup"
        cp "$ssh_backup" "$ssh_config"
        return 1
    fi
}

# Safe service restart with user confirmation
safe_service_restart() {
    local service_name="$1"
    local timeout="${2:-30}"
    local force="${3:-false}"

    if [[ "$force" != "true" ]]; then
        if ! confirm_action "Restart service '$service_name'? This may interrupt active connections." "n" 15; then
            log_info "Service restart cancelled by user"
            return 0
        fi
    fi

    log_info "Restarting service: $service_name"

    if isolate_systemctl_command "restart" "$service_name" "$timeout"; then
        log_success "Service restarted successfully: $service_name"
        return 0
    else
        log_error "Failed to restart service: $service_name"
        return 1
    fi
}

# Installation profile configuration
configure_installation_profile() {
    local profile="${INSTALLATION_MODE:-balanced}"

    case "$profile" in
        "minimal")
            export SKIP_SSH_HARDENING=true
            export SKIP_MONITORING_TOOLS=true
            export BACKUP_PROFILE=minimal
            export LOG_PROFILE=minimal
            export MONITORING_PROFILE=minimal
            export MAINTENANCE_MODE=conservative
            ;;
        "balanced")
            export SELECTIVE_SSH_HARDENING=true
            export INSTALL_MONITORING_TOOLS=false
            export BACKUP_PROFILE=essential
            export LOG_PROFILE=standard
            export MONITORING_PROFILE=balanced
            export MAINTENANCE_MODE=conservative
            ;;
        "full")
            export INTERACTIVE_MODE=true
            export INSTALL_MONITORING_TOOLS=prompt
            export BACKUP_PROFILE=prompt
            export LOG_PROFILE=prompt
            export MONITORING_PROFILE=prompt
            export MAINTENANCE_MODE=prompt
            ;;
    esac

    log_info "Installation profile configured: $profile"
}

# Validate system state before critical operations
validate_system_state() {
    local operation="$1"
    local issues=()

    case "$operation" in
        "ssh_hardening")
            # Check SSH connectivity
            if ! test_ssh_connectivity; then
                issues+=("SSH port not accessible")
            fi

            # Check if user has SSH keys (if hardening password auth)
            if [[ "${DISABLE_PASSWORD_AUTH:-false}" == "true" ]]; then
                if ! check_ssh_keys; then
                    issues+=("No SSH keys configured - password auth disable will cause lockout")
                fi
            fi
            ;;
        "firewall_config")
            # Check for existing firewalls
            if check_existing_firewall; then
                issues+=("Existing firewall detected - may cause conflicts")
            fi
            ;;
        "service_restart")
            # Check if critical services are running
            if ! systemctl is-active --quiet ssh && ! systemctl is-active --quiet sshd; then
                issues+=("SSH service not running")
            fi
            ;;
    esac

    if [[ ${#issues[@]} -gt 0 ]]; then
        log_warn "System validation found potential issues for operation '$operation':"
        printf "  %s\n" "${issues[@]}"
        return 1
    else
        log_success "System validation passed for operation: $operation"
        return 0
    fi
}

# Export functions
export -f confirm_action
export -f check_existing_firewall
export -f show_current_ssh_connections
export -f show_planned_firewall_rules
export -f backup_current_firewall_rules
export -f test_ssh_connectivity
export -f create_restore_point
export -f check_ssh_keys
export -f apply_selective_ssh_hardening
export -f safe_service_restart
export -f configure_installation_profile
export -f validate_system_state

log_debug "Safety utilities module loaded successfully"