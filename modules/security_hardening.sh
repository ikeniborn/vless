#!/bin/bash

# VLESS+Reality VPN Management System - Security Hardening
# Version: 1.0.0
# Description: Implement security best practices and system hardening
#
# Features:
# - SSH configuration hardening
# - Disable unnecessary services
# - File permission auditing
# - System user security
# - Network security parameters
# - Log file security
# - Process isolation for EPERM prevention

set -euo pipefail

# Import common utilities
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SOURCE_DIR}/common_utils.sh"
source "${SOURCE_DIR}/safety_utils.sh"

# Setup signal handlers
setup_signal_handlers

# Configuration
readonly SECURITY_BACKUP_DIR="/opt/vless/backup/security"
readonly SSH_CONFIG_BACKUP="${SECURITY_BACKUP_DIR}/sshd_config_$(date +%Y%m%d_%H%M%S).backup"
readonly SYSCTL_CONFIG_BACKUP="${SECURITY_BACKUP_DIR}/sysctl_$(date +%Y%m%d_%H%M%S).backup"
readonly SECURITY_AUDIT_LOG="/opt/vless/logs/security_audit.log"

# Security hardening configuration
readonly VLESS_USER="vless"
readonly VLESS_GROUP="vless"

# Initialize security hardening module
init_security_hardening() {
    log_info "Initializing security hardening module"

    # Create backup and log directories
    create_directory "$SECURITY_BACKUP_DIR" "700" "root"
    create_directory "$(dirname "$SECURITY_AUDIT_LOG")" "750" "root"

    log_success "Security hardening module initialized"
}

# Backup security-related configuration files
backup_security_configs() {
    log_info "Backing up security configuration files"

    local backup_files=()

    # Backup SSH configuration
    if [[ -f /etc/ssh/sshd_config ]]; then
        cp /etc/ssh/sshd_config "$SSH_CONFIG_BACKUP"
        backup_files+=("$SSH_CONFIG_BACKUP")
        log_debug "SSH config backed up to: $SSH_CONFIG_BACKUP"
    fi

    # Backup sysctl configuration
    if [[ -f /etc/sysctl.conf ]]; then
        cp /etc/sysctl.conf "$SYSCTL_CONFIG_BACKUP"
        backup_files+=("$SYSCTL_CONFIG_BACKUP")
        log_debug "Sysctl config backed up to: $SYSCTL_CONFIG_BACKUP"
    fi

    # Create comprehensive backup manifest
    {
        echo "# Security Configuration Backup - $(get_timestamp)"
        echo "# Backup files:"
        printf '%s\n' "${backup_files[@]}"
        echo ""
        echo "# System information:"
        get_system_info
    } > "${SECURITY_BACKUP_DIR}/backup_manifest.txt"

    log_success "Security configuration files backed up"
}

# Selective SSH hardening with user choices
selective_ssh_hardening() {
    log_info "Selective SSH hardening configuration"

    local ssh_options=(
        "PermitRootLogin no:Disable root SSH login"
        "PasswordAuthentication no:Disable password authentication"
        "MaxAuthTries 3:Limit authentication attempts to 3"
        "X11Forwarding no:Disable X11 forwarding"
        "LogLevel VERBOSE:Enable verbose SSH logging"
        "ClientAliveInterval 300:Set client alive interval"
        "AllowTcpForwarding no:Disable TCP forwarding"
    )

    echo -e "\n${CYAN}Select SSH hardening options:${NC}"

    local selected_options=()
    for option in "${ssh_options[@]}"; do
        IFS=':' read -r setting description <<< "$option"

        if confirm_action "Enable: $description" "y"; then
            selected_options+=("$setting")
        fi
    done

    if [[ ${#selected_options[@]} -gt 0 ]]; then
        apply_selective_ssh_hardening "${selected_options[@]}"
    else
        log_info "No SSH hardening options selected"
    fi
}

# Harden SSH configuration with safety checks
harden_ssh_config() {
    log_info "SSH hardening options available"

    # Check if we're in quick mode or interactive mode
    if [[ "${QUICK_MODE:-false}" == "true" ]]; then
        log_warn "Skipping SSH hardening in quick mode (can be enabled later)"
        return 0
    fi

    # Warn about potential lockout risks
    echo -e "\n${YELLOW}WARNING: SSH Hardening Configuration${NC}"
    echo "The following changes will be applied to SSH:"
    echo "  - Disable root login (PermitRootLogin no)"
    echo "  - Disable password authentication (PasswordAuthentication no)"
    echo "  - Require SSH keys for authentication"
    echo ""
    echo "${RED}IMPORTANT: Ensure you have SSH key access before proceeding!${NC}"
    echo "If you get locked out, you'll need console access to recover."
    echo ""

    # Interactive confirmation
    if ! confirm_action "Apply SSH hardening configuration? (Requires SSH key access)" "n"; then
        log_info "SSH hardening skipped by user choice"
        return 0
    fi

    # Additional safety check - verify SSH key exists
    local current_user="${SUDO_USER:-$(whoami)}"
    local ssh_key_exists=false

    if [[ -f "/home/${current_user}/.ssh/authorized_keys" ]] && [[ -s "/home/${current_user}/.ssh/authorized_keys" ]]; then
        ssh_key_exists=true
    fi

    if [[ "$ssh_key_exists" == "false" ]]; then
        echo -e "\n${RED}ERROR: No SSH keys found for user ${current_user}${NC}"
        echo "SSH hardening requires SSH key authentication."
        echo "Please set up SSH keys before enabling hardening."

        if ! confirm_action "Continue anyway? (HIGH RISK OF LOCKOUT)" "n"; then
            log_warn "SSH hardening aborted - no SSH keys configured"
            return 0
        fi
    fi

    log_info "Applying SSH hardening configuration"

    local ssh_config="/etc/ssh/sshd_config"
    local ssh_config_temp="/tmp/sshd_config.tmp"

    if [[ ! -f "$ssh_config" ]]; then
        log_error "SSH configuration file not found: $ssh_config"
        return 1
    fi

    # Create restore point before changes
    create_restore_point "ssh_hardening"

    # Create hardened SSH configuration
    cat > "$ssh_config_temp" << 'EOF'
# VLESS VPN - Hardened SSH Configuration
# Generated by security hardening module

# Protocol and Encryption
Protocol 2
Port 22

# Authentication
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Connection Settings
MaxAuthTries 3
MaxSessions 10
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 60

# Disable dangerous features
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
GatewayPorts no
PermitTunnel no
AllowStreamLocalForwarding no

# Logging
SyslogFacility AUTHPRIV
LogLevel VERBOSE

# Host-based authentication
IgnoreRhosts yes
HostbasedAuthentication no

# Disable unused authentication methods
KerberosAuthentication no
GSSAPIAuthentication no

# Banner and Messages
Banner /etc/ssh/ssh_banner
PrintMotd no
PrintLastLog yes

# TCP keep alive
TCPKeepAlive yes

# Strict host key checking
StrictModes yes

# Privilege separation
UsePrivilegeSeparation sandbox

# Compression
Compression no

# Only allow specific users (uncomment and modify as needed)
# AllowUsers vless

# IP restrictions (uncomment and modify as needed)
# AllowUsers *@10.0.0.0/8 *@192.168.0.0/16 *@172.16.0.0/12

EOF

    # Apply SSH configuration
    if mv "$ssh_config_temp" "$ssh_config"; then
        chmod 644 "$ssh_config"
        log_success "SSH configuration hardened"

        # Create SSH banner
        create_ssh_banner

        # Test SSH configuration
        if sshd -t; then
            log_success "SSH configuration syntax is valid"

            # Restart SSH service safely
            isolate_systemctl_command "restart" "ssh" 30 || \
            isolate_systemctl_command "restart" "sshd" 30

            log_success "SSH service restarted with hardened configuration"
        else
            log_error "SSH configuration syntax error. Restoring backup."
            cp "$SSH_CONFIG_BACKUP" "$ssh_config"
            return 1
        fi
    else
        log_error "Failed to apply SSH configuration"
        return 1
    fi
}

# Create SSH banner
create_ssh_banner() {
    local banner_file="/etc/ssh/ssh_banner"

    cat > "$banner_file" << 'EOF'
***************************************************************************
                        AUTHORIZED ACCESS ONLY
***************************************************************************

This is a private system. Unauthorized access is prohibited.
All activities on this system are logged and monitored.

By accessing this system, you consent to monitoring and recording
of your activities. Disconnect immediately if you are not authorized.

***************************************************************************
EOF

    chmod 644 "$banner_file"
    log_debug "SSH banner created: $banner_file"
}

# Configure kernel security parameters
configure_kernel_security() {
    log_info "Configuring kernel security parameters"

    local sysctl_config="/etc/sysctl.d/99-vless-security.conf"

    cat > "$sysctl_config" << 'EOF'
# VLESS VPN - Kernel Security Parameters
# Generated by security hardening module

# Network Security
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.icmp_echo_ignore_all = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1

# TCP/IP stack hardening
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_probes = 7
net.ipv4.tcp_keepalive_intvl = 30

# IPv6 security (if enabled)
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0

# Memory and process security
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.printk = 3 4 1 3
kernel.core_uses_pid = 1
kernel.core_pattern = |/bin/false
fs.suid_dumpable = 0

# Address space layout randomization
kernel.randomize_va_space = 2

# Shared memory security
kernel.shm_rmid_forced = 1

# ptrace restrictions
kernel.yama.ptrace_scope = 1

# File system security
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2

# Network buffer sizes
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.core.netdev_max_backlog = 5000

EOF

    chmod 644 "$sysctl_config"

    # Apply sysctl settings
    if sysctl -p "$sysctl_config"; then
        log_success "Kernel security parameters configured"
    else
        log_error "Failed to apply kernel security parameters"
        return 1
    fi
}

# Configure VLESS directory security
configure_vless_security() {
    log_info "Configuring VLESS directory security"

    # Verify VLESS user and group exist (should be created in Phase 1)
    if ! getent group "$VLESS_GROUP" >/dev/null 2>&1; then
        log_error "VLESS group '$VLESS_GROUP' not found - should be created in Phase 1"
        return 1
    fi

    if ! getent passwd "$VLESS_USER" >/dev/null 2>&1; then
        log_error "VLESS user '$VLESS_USER' not found - should be created in Phase 1"
        return 1
    fi

    # Set secure ownership and permissions for VLESS directories
    local vless_dirs=(
        "/opt/vless"
        "/opt/vless/config"
        "/opt/vless/logs"
        "/opt/vless/backup"
        "/opt/vless/users"
        "/opt/vless/certs"
    )

    local dir
    for dir in "${vless_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            chown -R "$VLESS_USER:$VLESS_GROUP" "$dir"
            chmod 750 "$dir"
            log_debug "Set secure ownership for: $dir"
        fi
    done

    log_success "VLESS directory security configured"
}

# Secure file permissions
secure_file_permissions() {
    log_info "Securing file permissions"

    # Critical system files
    local critical_files=(
        "/etc/passwd:644"
        "/etc/shadow:600"
        "/etc/group:644"
        "/etc/gshadow:600"
        "/etc/ssh/sshd_config:644"
        "/etc/crontab:600"
        "/etc/sudoers:440"
    )

    local file_perm
    local file
    local perm

    for file_perm in "${critical_files[@]}"; do
        file="${file_perm%:*}"
        perm="${file_perm#*:}"

        if [[ -f "$file" ]]; then
            chmod "$perm" "$file"
            log_debug "Set permissions $perm for: $file"
        fi
    done

    # VLESS configuration files
    local vless_files=(
        "/opt/vless/config:750"
        "/opt/vless/logs:750"
        "/opt/vless/backup:700"
    )

    for file_perm in "${vless_files[@]}"; do
        file="${file_perm%:*}"
        perm="${file_perm#*:}"

        if [[ -d "$file" ]]; then
            chmod "$perm" "$file"
            log_debug "Set permissions $perm for: $file"
        fi
    done

    log_success "File permissions secured"
}

# Disable unnecessary services
disable_unnecessary_services() {
    log_info "Disabling unnecessary services"

    # Services to disable (adjust based on your needs)
    local unnecessary_services=(
        "avahi-daemon"
        "cups"
        "bluetooth"
        "whoopsie"
        "apport"
        "snapd"
        "accounts-daemon"
        "speech-dispatcher"
        "brltty"
        "ModemManager"
    )

    local service
    local disabled_count=0

    for service in "${unnecessary_services[@]}"; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            isolate_systemctl_command "disable" "$service" 30
            isolate_systemctl_command "stop" "$service" 30
            log_debug "Disabled service: $service"
            ((disabled_count++))
        fi
    done

    log_success "Disabled $disabled_count unnecessary services"
}

# Configure fail2ban for additional protection
configure_fail2ban() {
    log_info "Configuring fail2ban for additional protection"

    # Install fail2ban if not present
    install_package_if_missing "fail2ban"

    local fail2ban_config="/etc/fail2ban/jail.local"

    cat > "$fail2ban_config" << 'EOF'
# VLESS VPN - Fail2ban Configuration
# Generated by security hardening module

[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = auto
destemail = root@localhost
action = %(action_mw)s

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[sshd-ddos]
enabled = true
port = ssh
filter = sshd-ddos
logpath = /var/log/auth.log
maxretry = 2
bantime = 3600

EOF

    chmod 644 "$fail2ban_config"

    # Enable and start fail2ban
    isolate_systemctl_command "enable" "fail2ban" 30
    isolate_systemctl_command "restart" "fail2ban" 30

    log_success "Fail2ban configured and enabled"
}

# Audit system security
audit_system_security() {
    log_info "Performing system security audit"

    local audit_output
    audit_output=$(mktemp)

    {
        echo "# System Security Audit Report - $(get_timestamp)"
        echo "# Generated by VLESS VPN Security Hardening Module"
        echo ""

        echo "=== System Information ==="
        get_system_info
        echo ""

        echo "=== User Accounts ==="
        echo "Root login status:"
        grep "^root:" /etc/passwd || echo "Root account not found"
        echo ""
        echo "Users with UID 0:"
        awk -F: '$3 == 0 {print $1}' /etc/passwd
        echo ""
        echo "Users with empty passwords:"
        awk -F: '($2 == "" || $2 == "!") {print $1}' /etc/shadow
        echo ""

        echo "=== SSH Configuration ==="
        echo "SSH root login:"
        grep -i "^PermitRootLogin\|^#PermitRootLogin" /etc/ssh/sshd_config || echo "Not configured"
        echo "SSH password authentication:"
        grep -i "^PasswordAuthentication\|^#PasswordAuthentication" /etc/ssh/sshd_config || echo "Not configured"
        echo ""

        echo "=== Network Security ==="
        echo "IP forwarding:"
        sysctl net.ipv4.ip_forward
        echo "SYN cookies:"
        sysctl net.ipv4.tcp_syncookies
        echo "ICMP redirects:"
        sysctl net.ipv4.conf.all.accept_redirects
        echo ""

        echo "=== Firewall Status ==="
        if command_exists ufw; then
            ufw status verbose
        else
            echo "UFW not installed"
        fi
        echo ""

        echo "=== File Permissions ==="
        echo "Checking critical file permissions:"
        ls -la /etc/passwd /etc/shadow /etc/group /etc/gshadow 2>/dev/null || echo "Some files not found"
        echo ""

        echo "=== Running Services ==="
        systemctl list-units --type=service --state=running --no-pager
        echo ""

        echo "=== Network Connections ==="
        ss -tulpn | head -20
        echo ""

        echo "=== Security Updates ==="
        if command_exists apt; then
            apt list --upgradable 2>/dev/null | grep -i security | wc -l | xargs echo "Security updates available:"
        fi
        echo ""

        echo "=== Failed Login Attempts ==="
        grep "Failed password" /var/log/auth.log 2>/dev/null | tail -10 || echo "No recent failed login attempts"
        echo ""

    } > "$audit_output"

    # Save audit report
    cp "$audit_output" "$SECURITY_AUDIT_LOG"
    chmod 640 "$SECURITY_AUDIT_LOG"

    # Display summary
    cat "$audit_output"

    rm -f "$audit_output"

    log_success "Security audit completed. Report saved to: $SECURITY_AUDIT_LOG"
}

# Configure automatic security updates
configure_automatic_updates() {
    log_info "Configuring automatic security updates"

    # Install unattended-upgrades
    install_package_if_missing "unattended-upgrades"

    local unattended_config="/etc/apt/apt.conf.d/50unattended-upgrades"
    local auto_upgrade_config="/etc/apt/apt.conf.d/20auto-upgrades"

    # Configure unattended upgrades
    cat > "$unattended_config" << 'EOF'
// VLESS VPN - Automatic Updates Configuration
// Generated by security hardening module

Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

Unattended-Upgrade::Package-Blacklist {
    // "vim";
    // "libc6-dev";
};

Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::InstallOnShutdown "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";

Unattended-Upgrade::SyslogEnable "true";
Unattended-Upgrade::SyslogFacility "daemon";

EOF

    # Configure auto upgrades
    cat > "$auto_upgrade_config" << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

    # Enable and start unattended-upgrades
    isolate_systemctl_command "enable" "unattended-upgrades" 30

    log_success "Automatic security updates configured"
}

# Complete security hardening setup
setup_security_hardening() {
    log_info "Starting complete security hardening setup"

    # Initialize
    init_security_hardening

    # Backup configurations
    backup_security_configs

    # Create VLESS user
    configure_vless_security

    # SSH hardening based on configuration
    if [[ "${SELECTIVE_SSH_HARDENING:-false}" == "true" ]]; then
        selective_ssh_hardening
    elif [[ "${SKIP_SSH_HARDENING:-false}" != "true" ]]; then
        harden_ssh_config
    else
        log_info "SSH hardening skipped by configuration"
    fi

    # Configure kernel security
    configure_kernel_security

    # Secure file permissions
    secure_file_permissions

    # Disable unnecessary services
    disable_unnecessary_services

    # Configure fail2ban
    configure_fail2ban

    # Configure automatic updates
    configure_automatic_updates

    # Perform security audit
    audit_system_security

    log_success "Security hardening setup completed successfully"
    log_info "Security audit report: $SECURITY_AUDIT_LOG"
    log_info "Configuration backups: $SECURITY_BACKUP_DIR"
}

# Revert security hardening
revert_security_hardening() {
    log_info "Reverting security hardening changes"

    # Restore SSH configuration
    if [[ -f "$SSH_CONFIG_BACKUP" ]]; then
        cp "$SSH_CONFIG_BACKUP" /etc/ssh/sshd_config
        isolate_systemctl_command "restart" "ssh" 30 || isolate_systemctl_command "restart" "sshd" 30
        log_info "SSH configuration restored"
    fi

    # Restore sysctl configuration
    if [[ -f "$SYSCTL_CONFIG_BACKUP" ]]; then
        cp "$SYSCTL_CONFIG_BACKUP" /etc/sysctl.conf
        sysctl -p
        log_info "Sysctl configuration restored"
    fi

    # Remove VLESS-specific configurations
    rm -f /etc/sysctl.d/99-vless-security.conf
    rm -f /etc/fail2ban/jail.local
    rm -f /etc/ssh/ssh_banner

    log_success "Security hardening changes reverted"
}

# Export functions
export -f init_security_hardening backup_security_configs harden_ssh_config
export -f create_ssh_banner configure_kernel_security configure_vless_security
export -f secure_file_permissions disable_unnecessary_services configure_fail2ban
export -f audit_system_security configure_automatic_updates setup_security_hardening
export -f revert_security_hardening

log_debug "Security hardening module loaded successfully"