#!/bin/bash
# Security Hardening Module for VLESS VPN Project
# Enhanced security configuration and hardening measures
# Author: Claude Code
# Version: 1.0

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load common utilities
source "${SCRIPT_DIR}/common_utils.sh"

# Configuration
readonly SECURITY_CONFIG_DIR="/etc/vless-security"
readonly FAIL2BAN_CONFIG_DIR="/etc/fail2ban"
readonly SYSCTL_CONFIG="/etc/sysctl.d/99-vless-security.conf"
readonly AUDIT_LOG_DIR="/var/log/vless-audit"
readonly SECURITY_LOG="/var/log/vless-security.log"

# Function to log security events
log_security_event() {
    local level="$1"
    local message="$2"
    local timestamp=$(get_timestamp)

    echo "[$timestamp] [$level] $message" | sudo tee -a "$SECURITY_LOG" >/dev/null

    case "$level" in
        "ERROR"|"CRITICAL")
            print_error "$message"
            ;;
        "WARNING")
            print_warning "$message"
            ;;
        "INFO")
            print_info "$message"
            ;;
        *)
            echo "$message"
            ;;
    esac
}

# Install fail2ban
install_fail2ban() {
    print_section "Installing Fail2ban"

    if command -v fail2ban-server >/dev/null 2>&1; then
        log_security_event "INFO" "Fail2ban already installed"
        return 0
    fi

    # Update package list
    log_security_event "INFO" "Updating package list for fail2ban installation"
    sudo apt update -qq

    # Install fail2ban
    log_security_event "INFO" "Installing fail2ban package"
    sudo apt install -y fail2ban

    # Enable and start fail2ban
    sudo systemctl enable fail2ban
    sudo systemctl start fail2ban

    log_security_event "INFO" "Fail2ban installed and started successfully"
    print_success "Fail2ban installed and configured"
}

# Configure fail2ban for SSH protection
configure_fail2ban_ssh() {
    print_section "Configuring Fail2ban for SSH Protection"

    local jail_local="$FAIL2BAN_CONFIG_DIR/jail.local"

    log_security_event "INFO" "Creating fail2ban SSH jail configuration"

    sudo tee "$jail_local" > /dev/null << 'EOF'
[DEFAULT]
# Ban hosts for 24 hours
bantime = 86400

# Check for attempts within 10 minutes
findtime = 600

# Ban after 3 failed attempts
maxretry = 3

# Default action: ban IP with iptables and send email notification
action = %(action_mwl)s

# Email configuration (if available)
destemail = root@localhost
sender = fail2ban@localhost

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 86400
findtime = 600

[sshd-ddos]
enabled = true
port = ssh
filter = sshd-ddos
logpath = /var/log/auth.log
maxretry = 2
bantime = 86400
findtime = 600

[recidive]
enabled = true
filter = recidive
logpath = /var/log/fail2ban.log
action = %(action_mwl)s
bantime = 604800  ; 1 week
findtime = 86400   ; 1 day
maxretry = 5
EOF

    # Create custom filter for VLESS-specific protection
    sudo tee "$FAIL2BAN_CONFIG_DIR/filter.d/vless-auth.conf" > /dev/null << 'EOF'
[Definition]
# Fail2ban filter for VLESS authentication failures
failregex = ^.*VLESS.*authentication failed.*from <HOST>.*$
            ^.*VLESS.*invalid user.*from <HOST>.*$
            ^.*VLESS.*connection rejected.*from <HOST>.*$

ignoreregex =
EOF

    # Add VLESS jail
    sudo tee -a "$jail_local" > /dev/null << 'EOF'

[vless-auth]
enabled = true
port = 443,80
filter = vless-auth
logpath = /var/log/xray/access.log
maxretry = 5
bantime = 3600
findtime = 300
EOF

    # Restart fail2ban to apply configuration
    sudo systemctl restart fail2ban

    log_security_event "INFO" "Fail2ban SSH protection configured and activated"
    print_success "Fail2ban configured for SSH and VLESS protection"
}

# Disable unnecessary services
disable_unnecessary_services() {
    print_section "Disabling Unnecessary Services"

    local services_to_disable=(
        "avahi-daemon"
        "cups"
        "bluetooth"
        "ModemManager"
        "whoopsie"
        "apport"
    )

    for service in "${services_to_disable[@]}"; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            log_security_event "INFO" "Disabling unnecessary service: $service"
            sudo systemctl disable "$service" >/dev/null 2>&1 || true
            sudo systemctl stop "$service" >/dev/null 2>&1 || true
            print_success "Disabled service: $service"
        else
            log_security_event "INFO" "Service $service not found or already disabled"
        fi
    done
}

# Configure kernel parameters for security
configure_kernel_security() {
    print_section "Configuring Kernel Security Parameters"

    log_security_event "INFO" "Applying kernel security parameters"

    sudo tee "$SYSCTL_CONFIG" > /dev/null << 'EOF'
# VLESS VPN Security Configuration
# Network security
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# IP Spoofing protection
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Ignore ICMP redirects
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Ignore ping requests
net.ipv4.icmp_echo_ignore_all = 0

# Disable source packet routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# TCP security
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# Memory protection
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2

# Process security
kernel.yama.ptrace_scope = 1

# File system security
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.suid_dumpable = 0

# Network performance and security
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_congestion_control = bbr
EOF

    # Apply the configuration
    sudo sysctl -p "$SYSCTL_CONFIG"

    log_security_event "INFO" "Kernel security parameters applied successfully"
    print_success "Kernel security parameters configured"
}

# Configure file system permissions
secure_file_permissions() {
    print_section "Securing File System Permissions"

    local files_to_secure=(
        "/etc/passwd:644"
        "/etc/group:644"
        "/etc/shadow:600"
        "/etc/gshadow:600"
        "/etc/ssh/sshd_config:600"
        "/boot/grub/grub.cfg:600"
    )

    for item in "${files_to_secure[@]}"; do
        local file_path="${item%:*}"
        local permissions="${item#*:}"

        if [[ -f "$file_path" ]]; then
            log_security_event "INFO" "Securing permissions for: $file_path"
            sudo chmod "$permissions" "$file_path"
            print_success "Secured: $file_path ($permissions)"
        fi
    done

    # Secure VLESS directories
    if [[ -d "$VLESS_DIR" ]]; then
        log_security_event "INFO" "Securing VLESS directory permissions"
        sudo find "$VLESS_DIR" -type d -exec chmod 750 {} \;
        sudo find "$VLESS_DIR" -type f -name "*.key" -exec chmod 600 {} \;
        sudo find "$VLESS_DIR" -type f -name "*.crt" -exec chmod 644 {} \;
        sudo find "$VLESS_DIR" -type f -name "*.json" -exec chmod 640 {} \;
        print_success "VLESS directory permissions secured"
    fi
}

# Setup automatic security updates
setup_automatic_updates() {
    print_section "Setting up Automatic Security Updates"

    # Install unattended-upgrades
    sudo apt update -qq
    sudo apt install -y unattended-upgrades apt-listchanges

    # Configure automatic updates
    sudo tee "/etc/apt/apt.conf.d/50unattended-upgrades" > /dev/null << 'EOF'
// Automatically upgrade packages from these origins
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

// List of packages to not update
Unattended-Upgrade::Package-Blacklist {
    // "vim";
    // "libc6-dev";
};

// Automatically reboot system if required
Unattended-Upgrade::Automatic-Reboot "false";

// Reboot time
Unattended-Upgrade::Automatic-Reboot-Time "02:00";

// Remove unused automatically installed packages
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";

// Enable logging
Unattended-Upgrade::Debug "false";
Unattended-Upgrade::Mail "root";
Unattended-Upgrade::MailOnlyOnError "true";
EOF

    # Enable automatic updates
    sudo tee "/etc/apt/apt.conf.d/20auto-upgrades" > /dev/null << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

    # Enable and start the service
    sudo systemctl enable unattended-upgrades
    sudo systemctl start unattended-upgrades

    log_security_event "INFO" "Automatic security updates configured and enabled"
    print_success "Automatic security updates configured"
}

# Setup file integrity monitoring
setup_file_integrity_monitoring() {
    print_section "Setting up File Integrity Monitoring"

    # Install AIDE (Advanced Intrusion Detection Environment)
    sudo apt update -qq
    sudo apt install -y aide aide-common

    # Configure AIDE
    sudo tee "/etc/aide/aide.conf.d/99-vless-monitoring" > /dev/null << 'EOF'
# VLESS VPN File Integrity Monitoring

# Monitor VLESS configuration files
/opt/vless p+i+n+u+g+s+b+m+c+md5+sha256
/etc/vless-security p+i+n+u+g+s+b+m+c+md5+sha256

# Monitor system configuration
/etc/ssh/sshd_config p+i+n+u+g+s+b+m+c+md5+sha256
/etc/fail2ban p+i+n+u+g+s+b+m+c+md5+sha256
/etc/sysctl.d p+i+n+u+g+s+b+m+c+md5+sha256

# Monitor critical system files
/etc/passwd p+i+n+u+g+s+b+m+c+md5+sha256
/etc/group p+i+n+u+g+s+b+m+c+md5+sha256
/etc/shadow p+i+n+u+g+s+b+m+c+md5+sha256
/etc/sudoers p+i+n+u+g+s+b+m+c+md5+sha256

# Monitor Docker configuration
/etc/docker p+i+n+u+g+s+b+m+c+md5+sha256
EOF

    # Initialize AIDE database
    log_security_event "INFO" "Initializing AIDE database - this may take several minutes"
    sudo aideinit

    # Create daily check script
    sudo tee "/etc/cron.daily/aide-check" > /dev/null << 'EOF'
#!/bin/bash
# Daily AIDE integrity check

AIDE_LOG="/var/log/aide.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$TIMESTAMP] Starting AIDE integrity check" >> "$AIDE_LOG"

if aide --check > /tmp/aide-report 2>&1; then
    echo "[$TIMESTAMP] AIDE check completed - no changes detected" >> "$AIDE_LOG"
else
    echo "[$TIMESTAMP] AIDE check detected changes:" >> "$AIDE_LOG"
    cat /tmp/aide-report >> "$AIDE_LOG"

    # Send alert if Telegram bot is configured
    if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]] && [[ -n "${ADMIN_TELEGRAM_ID:-}" ]]; then
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${ADMIN_TELEGRAM_ID}" \
            -d "text=🔒 AIDE Alert: File integrity changes detected on $(hostname). Check /var/log/aide.log for details." \
            >/dev/null 2>&1 || true
    fi
fi

rm -f /tmp/aide-report
EOF

    sudo chmod +x "/etc/cron.daily/aide-check"

    log_security_event "INFO" "File integrity monitoring configured and enabled"
    print_success "File integrity monitoring setup completed"
}

# Configure audit logging
setup_audit_logging() {
    print_section "Setting up Security Audit Logging"

    # Install auditd
    sudo apt update -qq
    sudo apt install -y auditd audispd-plugins

    # Create audit log directory
    ensure_directory "$AUDIT_LOG_DIR" "750" "root"

    # Configure audit rules
    sudo tee "/etc/audit/rules.d/99-vless-audit.rules" > /dev/null << 'EOF'
# VLESS VPN Security Audit Rules

# Monitor file access to VLESS configuration
-w /opt/vless -p wa -k vless_config_access
-w /etc/vless-security -p wa -k vless_security_access

# Monitor SSH configuration changes
-w /etc/ssh/sshd_config -p wa -k ssh_config_change

# Monitor authentication events
-w /var/log/auth.log -p wa -k auth_log_access

# Monitor privilege escalation
-w /bin/su -p x -k privilege_escalation
-w /usr/bin/sudo -p x -k privilege_escalation

# Monitor network configuration changes
-w /etc/network/ -p wa -k network_config_change
-w /etc/hosts -p wa -k network_config_change
-w /etc/hostname -p wa -k network_config_change

# Monitor system calls for security events
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time_change
-a always,exit -F arch=b32 -S adjtimex -S settimeofday -S stime -k time_change
-a always,exit -F arch=b64 -S clock_settime -k time_change
-a always,exit -F arch=b32 -S clock_settime -k time_change

# Monitor file permission changes
-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b64 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod
EOF

    # Enable and start auditd
    sudo systemctl enable auditd
    sudo systemctl restart auditd

    log_security_event "INFO" "Security audit logging configured and enabled"
    print_success "Security audit logging setup completed"
}

# Main security hardening function
apply_security_hardening() {
    print_header "VLESS VPN Security Hardening"

    log_security_event "INFO" "Starting security hardening process"

    # Ensure security configuration directory exists
    ensure_directory "$SECURITY_CONFIG_DIR" "750" "root"

    # Create security log file
    sudo touch "$SECURITY_LOG"
    sudo chmod 640 "$SECURITY_LOG"

    # Apply security measures
    install_fail2ban
    configure_fail2ban_ssh
    disable_unnecessary_services
    configure_kernel_security
    secure_file_permissions
    setup_automatic_updates
    setup_file_integrity_monitoring
    setup_audit_logging

    log_security_event "INFO" "Security hardening process completed successfully"
    print_success "Security hardening completed successfully"

    # Display security status
    show_security_status
}

# Show security status
show_security_status() {
    print_header "Security Status Report"

    echo "Security Services Status:"
    printf "%-25s " "Fail2ban:"
    if systemctl is-active --quiet fail2ban; then
        echo -e "${GREEN}Active${NC}"
    else
        echo -e "${RED}Inactive${NC}"
    fi

    printf "%-25s " "Unattended Upgrades:"
    if systemctl is-active --quiet unattended-upgrades; then
        echo -e "${GREEN}Active${NC}"
    else
        echo -e "${RED}Inactive${NC}"
    fi

    printf "%-25s " "Auditd:"
    if systemctl is-active --quiet auditd; then
        echo -e "${GREEN}Active${NC}"
    else
        echo -e "${RED}Inactive${NC}"
    fi

    echo
    echo "Security Configuration Files:"
    printf "%-35s " "Fail2ban jail config:"
    if [[ -f "$FAIL2BAN_CONFIG_DIR/jail.local" ]]; then
        echo -e "${GREEN}Configured${NC}"
    else
        echo -e "${RED}Missing${NC}"
    fi

    printf "%-35s " "Kernel security parameters:"
    if [[ -f "$SYSCTL_CONFIG" ]]; then
        echo -e "${GREEN}Configured${NC}"
    else
        echo -e "${RED}Missing${NC}"
    fi

    printf "%-35s " "AIDE configuration:"
    if [[ -f "/etc/aide/aide.conf.d/99-vless-monitoring" ]]; then
        echo -e "${GREEN}Configured${NC}"
    else
        echo -e "${RED}Missing${NC}"
    fi

    echo
    print_info "Security logs location: $SECURITY_LOG"
    print_info "Audit logs location: $AUDIT_LOG_DIR"

    # Show recent security events
    if [[ -f "$SECURITY_LOG" ]]; then
        echo
        print_section "Recent Security Events (last 10)"
        sudo tail -n 10 "$SECURITY_LOG" 2>/dev/null || echo "No recent events"
    fi
}

# Remove security hardening (for testing/rollback)
remove_security_hardening() {
    print_header "Removing Security Hardening"

    log_security_event "WARNING" "Security hardening removal requested"

    if ! prompt_yes_no "Are you sure you want to remove security hardening? This will reduce system security." "n"; then
        print_info "Security hardening removal cancelled"
        return 0
    fi

    # Stop and disable services
    sudo systemctl stop fail2ban unattended-upgrades auditd 2>/dev/null || true
    sudo systemctl disable fail2ban unattended-upgrades auditd 2>/dev/null || true

    # Remove configuration files
    sudo rm -f "$FAIL2BAN_CONFIG_DIR/jail.local"
    sudo rm -f "$FAIL2BAN_CONFIG_DIR/filter.d/vless-auth.conf"
    sudo rm -f "$SYSCTL_CONFIG"
    sudo rm -f "/etc/aide/aide.conf.d/99-vless-monitoring"
    sudo rm -f "/etc/audit/rules.d/99-vless-audit.rules"
    sudo rm -f "/etc/cron.daily/aide-check"
    sudo rm -f "/etc/apt/apt.conf.d/50unattended-upgrades"
    sudo rm -f "/etc/apt/apt.conf.d/20auto-upgrades"

    # Remove directories
    sudo rm -rf "$SECURITY_CONFIG_DIR"

    log_security_event "WARNING" "Security hardening removed - system security reduced"
    print_warning "Security hardening removed. System is now less secure."
}

# Export functions
export -f apply_security_hardening show_security_status remove_security_hardening
export -f log_security_event install_fail2ban configure_fail2ban_ssh
export -f disable_unnecessary_services configure_kernel_security secure_file_permissions
export -f setup_automatic_updates setup_file_integrity_monitoring setup_audit_logging

# Main execution if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-apply}" in
        "apply"|"install"|"setup")
            apply_security_hardening
            ;;
        "status"|"show")
            show_security_status
            ;;
        "remove"|"uninstall")
            remove_security_hardening
            ;;
        *)
            echo "Usage: $0 {apply|status|remove}"
            echo "  apply   - Apply security hardening measures"
            echo "  status  - Show current security status"
            echo "  remove  - Remove security hardening (not recommended)"
            exit 1
            ;;
    esac
fi