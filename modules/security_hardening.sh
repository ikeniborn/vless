#!/bin/bash

# Security Hardening Module for VLESS+Reality VPN
# This module implements comprehensive security measures including SSH hardening,
# fail2ban setup, and system security baseline configuration
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
readonly SECURITY_BACKUP_DIR="/opt/vless/backups/security"
readonly SSH_CONFIG_BACKUP="${SECURITY_BACKUP_DIR}/sshd_config_$(date +%Y%m%d_%H%M%S).backup"
readonly FAIL2BAN_CONFIG_DIR="/etc/fail2ban"
readonly SECURITY_LOG="/opt/vless/logs/security.log"

# Create security backup directory
create_security_backup_dir() {
    log_info "Creating security backup directory"
    mkdir -p "${SECURITY_BACKUP_DIR}"
    chmod 700 "${SECURITY_BACKUP_DIR}"
}

# Backup SSH configuration
backup_ssh_config() {
    log_info "Backing up SSH configuration"

    create_security_backup_dir

    if [[ -f /etc/ssh/sshd_config ]]; then
        cp /etc/ssh/sshd_config "${SSH_CONFIG_BACKUP}"
        log_info "SSH config backed up to: ${SSH_CONFIG_BACKUP}"
    else
        log_warn "SSH config file not found at /etc/ssh/sshd_config"
    fi
}

# Install security packages
install_security_packages() {
    log_info "Installing security packages"

    local packages=(
        "fail2ban"
        "ufw"
        "unattended-upgrades"
        "apt-listchanges"
        "logwatch"
        "rkhunter"
        "chkrootkit"
    )

    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        for package in "${packages[@]}"; do
            if ! dpkg -l | grep -q "^ii  $package "; then
                log_info "Installing $package"
                apt-get install -y "$package" || log_warn "Failed to install $package"
            else
                log_info "$package is already installed"
            fi
        done
    else
        log_warn "APT package manager not found, skipping package installation"
    fi
}

# Configure SSH hardening
configure_ssh_hardening() {
    log_info "Configuring SSH hardening"

    if [[ ! -f /etc/ssh/sshd_config ]]; then
        log_error "SSH config file not found"
        return 1
    fi

    # Backup first
    backup_ssh_config

    # Create hardened SSH configuration
    local ssh_config_additions="
# VLESS VPN Security Hardening - Added $(date)

# Disable root login
PermitRootLogin no

# Use protocol 2 only
Protocol 2

# Disable password authentication (enable only after setting up keys)
# PasswordAuthentication no
# PubkeyAuthentication yes

# Disable empty passwords
PermitEmptyPasswords no

# Disable X11 forwarding
X11Forwarding no

# Disable user environment processing
PermitUserEnvironment no

# Use stronger ciphers and MACs
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,hmac-sha2-256,hmac-sha2-512

# Key exchange algorithms
KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512

# Limit authentication attempts
MaxAuthTries 3
MaxStartups 10:30:60

# Set login grace time
LoginGraceTime 30

# Disable host-based authentication
HostbasedAuthentication no
IgnoreRhosts yes

# Disable unnecessary features
AllowAgentForwarding no
AllowTcpForwarding no
GatewayPorts no

# Log more information
LogLevel VERBOSE

# Disable GSSAPI
GSSAPIAuthentication no
"

    # Apply SSH hardening gradually to avoid lockout
    log_info "Applying SSH security settings (keeping password auth enabled for now)"

    # First, apply non-breaking changes
    {
        echo "$ssh_config_additions"
    } >> /etc/ssh/sshd_config

    # Test SSH configuration
    if sshd -t 2>/dev/null; then
        log_info "SSH configuration test passed"

        # Restart SSH service safely
        if command -v systemctl >/dev/null 2>&1; then
            if [[ $(type -t isolate_systemctl_command) == function ]]; then
                isolate_systemctl_command "restart" "ssh" 30 || isolate_systemctl_command "restart" "sshd" 30
            else
                systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || log_warn "Could not restart SSH service"
            fi
        fi

        log_info "SSH hardening applied successfully"
        log_warn "Password authentication is still enabled. Disable it manually after setting up SSH keys."
    else
        log_error "SSH configuration test failed, reverting changes"
        if [[ -f "${SSH_CONFIG_BACKUP}" ]]; then
            cp "${SSH_CONFIG_BACKUP}" /etc/ssh/sshd_config
            log_info "SSH configuration reverted"
        fi
        return 1
    fi
}

# Setup SSH key authentication helper
setup_ssh_keys() {
    local username="$1"
    local public_key="${2:-}"

    log_info "Setting up SSH key authentication for user: $username"

    # Create user if doesn't exist
    if ! id "$username" >/dev/null 2>&1; then
        log_info "Creating user: $username"
        useradd -m -s /bin/bash "$username"
        usermod -aG sudo "$username"
    fi

    local user_home
    user_home=$(getent passwd "$username" | cut -d: -f6)
    local ssh_dir="${user_home}/.ssh"

    # Create SSH directory
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    chown "$username:$username" "$ssh_dir"

    # Add public key if provided
    if [[ -n "$public_key" ]]; then
        echo "$public_key" >> "${ssh_dir}/authorized_keys"
        chmod 600 "${ssh_dir}/authorized_keys"
        chown "$username:$username" "${ssh_dir}/authorized_keys"
        log_info "SSH public key added for user: $username"
    else
        log_info "SSH directory created for user: $username"
        log_info "Add your public key to: ${ssh_dir}/authorized_keys"
    fi
}

# Disable password authentication (use after SSH keys are set up)
disable_password_auth() {
    log_warn "Disabling SSH password authentication"

    if [[ ! -f /etc/ssh/sshd_config ]]; then
        log_error "SSH config file not found"
        return 1
    fi

    # Backup configuration
    backup_ssh_config

    # Disable password authentication
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

    # Test configuration
    if sshd -t 2>/dev/null; then
        log_info "SSH configuration test passed"

        # Restart SSH service
        if command -v systemctl >/dev/null 2>&1; then
            if [[ $(type -t isolate_systemctl_command) == function ]]; then
                isolate_systemctl_command "restart" "ssh" 30 || isolate_systemctl_command "restart" "sshd" 30
            else
                systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
            fi
        fi

        log_info "Password authentication disabled successfully"
        log_warn "Ensure SSH key authentication is working before closing this session!"
    else
        log_error "SSH configuration test failed, reverting changes"
        if [[ -f "${SSH_CONFIG_BACKUP}" ]]; then
            cp "${SSH_CONFIG_BACKUP}" /etc/ssh/sshd_config
        fi
        return 1
    fi
}

# Configure fail2ban
setup_fail2ban() {
    log_info "Configuring fail2ban"

    if ! command -v fail2ban-server >/dev/null 2>&1; then
        log_error "fail2ban is not installed"
        return 1
    fi

    # Create custom fail2ban configuration
    cat > "${FAIL2BAN_CONFIG_DIR}/jail.local" << 'EOF'
[DEFAULT]
# Ban settings
bantime = 3600
findtime = 600
maxretry = 3

# Ignore local addresses
ignoreip = 127.0.0.1/8 ::1

# Email notifications (configure if needed)
# destemail = admin@example.com
# sender = fail2ban@example.com

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[apache-auth]
enabled = false

[apache-badbots]
enabled = false

[apache-noscript]
enabled = false

[apache-overflows]
enabled = false

[apache-nohome]
enabled = false

[nginx-http-auth]
enabled = false

[nginx-noscript]
enabled = false

[nginx-badbots]
enabled = false

[nginx-botsearch]
enabled = false
EOF

    # Create UFW action for fail2ban if UFW is available
    if command -v ufw >/dev/null 2>&1; then
        cat > "${FAIL2BAN_CONFIG_DIR}/action.d/ufw.conf" << 'EOF'
[Definition]
actionstart =
actionstop =
actioncheck =
actionban = ufw insert 1 deny from <ip> to any comment "fail2ban-<name>"
actionunban = ufw delete deny from <ip> to any
EOF
    fi

    # Start and enable fail2ban
    if command -v systemctl >/dev/null 2>&1; then
        if [[ $(type -t isolate_systemctl_command) == function ]]; then
            isolate_systemctl_command "enable" "fail2ban" 30
            isolate_systemctl_command "start" "fail2ban" 30
        else
            systemctl enable fail2ban 2>/dev/null || log_warn "Could not enable fail2ban"
            systemctl start fail2ban 2>/dev/null || log_warn "Could not start fail2ban"
        fi
    fi

    log_info "fail2ban configured and started"
}

# Configure automatic security updates
setup_automatic_updates() {
    log_info "Configuring automatic security updates"

    if [[ ! -f /etc/apt/apt.conf.d/50unattended-upgrades ]]; then
        log_warn "unattended-upgrades not found, skipping automatic updates"
        return 0
    fi

    # Configure unattended upgrades for security updates only
    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

    # Configure which packages to auto-upgrade
    sed -i 's|//\s*"${distro_id}:${distro_codename}-security";|        "${distro_id}:${distro_codename}-security";|' \
        /etc/apt/apt.conf.d/50unattended-upgrades

    # Enable automatic reboot for kernel updates if needed
    sed -i 's|//Unattended-Upgrade::Automatic-Reboot "false";|Unattended-Upgrade::Automatic-Reboot "false";|' \
        /etc/apt/apt.conf.d/50unattended-upgrades

    log_info "Automatic security updates configured"
}

# Setup system security monitoring
setup_security_monitoring() {
    log_info "Setting up security monitoring"

    # Create security monitoring script
    cat > /usr/local/bin/vless-security-monitor << 'EOF'
#!/bin/bash
# VLESS VPN Security Monitoring Script

SECURITY_LOG="/opt/vless/logs/security.log"
mkdir -p "$(dirname "$SECURITY_LOG")"

log_security() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$SECURITY_LOG"
}

# Check for failed login attempts
failed_logins=$(grep "Failed password" /var/log/auth.log 2>/dev/null | tail -10 | wc -l)
if [[ $failed_logins -gt 5 ]]; then
    log_security "WARNING: $failed_logins failed login attempts detected"
fi

# Check for new users
new_users=$(find /home -type d -mtime -1 2>/dev/null | wc -l)
if [[ $new_users -gt 0 ]]; then
    log_security "INFO: $new_users new user directories created"
fi

# Check system load
load_avg=$(uptime | awk '{print $10}' | sed 's/,//')
if (( $(echo "$load_avg > 2.0" | bc -l) )); then
    log_security "WARNING: High system load detected: $load_avg"
fi

# Check disk usage
disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [[ $disk_usage -gt 90 ]]; then
    log_security "WARNING: High disk usage: ${disk_usage}%"
fi

# Check for rootkit signatures (basic)
if command -v rkhunter >/dev/null 2>&1; then
    if rkhunter --check --sk 2>/dev/null | grep -q "Warning"; then
        log_security "WARNING: rkhunter detected potential issues"
    fi
fi
EOF

    chmod +x /usr/local/bin/vless-security-monitor

    # Create cron job for security monitoring
    cat > /etc/cron.d/vless-security << 'EOF'
# VLESS VPN Security Monitoring
*/15 * * * * root /usr/local/bin/vless-security-monitor
EOF

    log_info "Security monitoring configured"
}

# Configure system kernel hardening
configure_kernel_hardening() {
    log_info "Configuring kernel security parameters"

    # Create sysctl security configuration
    cat > /etc/sysctl.d/99-vless-security.conf << 'EOF'
# VLESS VPN Security Hardening

# IP Spoofing protection
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.rp_filter = 1

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Ignore send redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Disable source packet routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Log Martians
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Ignore ICMP ping requests
net.ipv4.icmp_echo_ignore_all = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignore Directed pings
net.ipv4.icmp_ignore_bogus_error_responses = 1

# SYN flood protection
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# Control buffer overflow attacks
kernel.exec-shield = 1
kernel.randomize_va_space = 2

# Hide kernel pointers
kernel.kptr_restrict = 1

# Restrict dmesg
kernel.dmesg_restrict = 1

# Restrict perf events
kernel.perf_event_paranoid = 2
EOF

    # Apply sysctl settings
    sysctl -p /etc/sysctl.d/99-vless-security.conf 2>/dev/null || log_warn "Some sysctl settings could not be applied"

    log_info "Kernel security parameters configured"
}

# Configure file permissions and security
configure_file_security() {
    log_info "Configuring file and directory security"

    # Secure /tmp directory
    if ! mount | grep -q "tmpfs on /tmp"; then
        log_info "Setting secure permissions on /tmp"
        chmod 1777 /tmp
    fi

    # Secure important system files
    chmod 600 /etc/ssh/sshd_config 2>/dev/null || true
    chmod 600 /etc/shadow 2>/dev/null || true
    chmod 640 /etc/gshadow 2>/dev/null || true

    # Disable unused network protocols
    cat > /etc/modprobe.d/blacklist-rare-network.conf << 'EOF'
# Disable rare network protocols for security
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true
EOF

    log_info "File security configured"
}

# Generate security report
generate_security_report() {
    local report_file="/opt/vless/logs/security_report_$(date +%Y%m%d_%H%M%S).txt"

    log_info "Generating security report: $report_file"

    {
        echo "VLESS VPN Security Report - $(date)"
        echo "================================================"
        echo ""

        echo "SSH Configuration Status:"
        echo "------------------------"
        if grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config 2>/dev/null; then
            echo "✓ Password authentication disabled"
        else
            echo "⚠ Password authentication enabled"
        fi

        if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config 2>/dev/null; then
            echo "✓ Root login disabled"
        else
            echo "⚠ Root login may be enabled"
        fi

        echo ""
        echo "Firewall Status:"
        echo "---------------"
        if command -v ufw >/dev/null 2>&1; then
            ufw status | head -10
        else
            echo "UFW not installed"
        fi

        echo ""
        echo "Fail2ban Status:"
        echo "---------------"
        if command -v fail2ban-client >/dev/null 2>&1; then
            fail2ban-client status 2>/dev/null || echo "fail2ban not running"
        else
            echo "fail2ban not installed"
        fi

        echo ""
        echo "System Updates:"
        echo "--------------"
        if command -v apt >/dev/null 2>&1; then
            apt list --upgradable 2>/dev/null | wc -l | sed 's/^/Available updates: /'
        fi

        echo ""
        echo "Security Monitoring:"
        echo "------------------"
        if [[ -f "$SECURITY_LOG" ]]; then
            echo "Recent security events:"
            tail -5 "$SECURITY_LOG" 2>/dev/null || echo "No recent events"
        else
            echo "Security monitoring not configured"
        fi

        echo ""
        echo "Open Ports:"
        echo "----------"
        ss -tuln | grep LISTEN | head -10

    } > "$report_file"

    log_info "Security report generated: $report_file"

    # Also log to main security log
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Security report generated: $report_file" >> "$SECURITY_LOG"
}

# Validate security configuration
validate_security_config() {
    log_info "Validating security configuration"

    local issues=0

    # Check SSH configuration
    if ! sshd -t 2>/dev/null; then
        log_error "SSH configuration has errors"
        ((issues++))
    fi

    # Check fail2ban status
    if command -v fail2ban-client >/dev/null 2>&1; then
        if ! fail2ban-client ping 2>/dev/null | grep -q "pong"; then
            log_warn "fail2ban is not responding"
            ((issues++))
        fi
    fi

    # Check UFW status
    if command -v ufw >/dev/null 2>&1; then
        if ! ufw status | grep -q "Status: active"; then
            log_warn "UFW firewall is not active"
            ((issues++))
        fi
    fi

    # Check for security monitoring
    if [[ ! -f /usr/local/bin/vless-security-monitor ]]; then
        log_warn "Security monitoring script not found"
        ((issues++))
    fi

    if [[ $issues -eq 0 ]]; then
        log_info "Security validation passed"
    else
        log_warn "Security validation found $issues issues"
    fi

    return $issues
}

# Main security hardening function
harden_system_security() {
    log_info "Starting system security hardening"

    # Ensure running as root
    if ! validate_root; then
        log_error "Security hardening requires root privileges"
        return 1
    fi

    # Install security packages
    install_security_packages

    # Configure SSH hardening
    configure_ssh_hardening

    # Setup fail2ban
    setup_fail2ban

    # Configure automatic updates
    setup_automatic_updates

    # Setup security monitoring
    setup_security_monitoring

    # Configure kernel hardening
    configure_kernel_hardening

    # Configure file security
    configure_file_security

    # Generate initial security report
    generate_security_report

    # Validate configuration
    if validate_security_config; then
        log_info "Security hardening completed successfully"
    else
        log_warn "Security hardening completed with warnings"
    fi

    log_info "Security hardening complete"
    log_warn "Remember to:"
    log_warn "1. Set up SSH keys before disabling password authentication"
    log_warn "2. Test SSH access from another session"
    log_warn "3. Review security report regularly"
}

# Interactive SSH key setup
interactive_ssh_setup() {
    echo "SSH Key Setup Wizard"
    echo "==================="

    read -p "Enter username for SSH key setup: " username
    if [[ -z "$username" ]]; then
        log_error "Username is required"
        return 1
    fi

    echo "Please paste your SSH public key (or press Enter to skip):"
    read -r public_key

    setup_ssh_keys "$username" "$public_key"

    if [[ -n "$public_key" ]]; then
        read -p "Do you want to disable password authentication now? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            disable_password_auth
        else
            log_info "Password authentication remains enabled"
            log_info "Run '$0 disable-password-auth' when ready"
        fi
    fi
}

# Main script execution
main() {
    case "${1:-}" in
        "harden"|"")
            harden_system_security
            ;;
        "ssh-setup")
            interactive_ssh_setup
            ;;
        "disable-password-auth")
            disable_password_auth
            ;;
        "report")
            generate_security_report
            ;;
        "validate")
            validate_security_config
            ;;
        "fail2ban")
            setup_fail2ban
            ;;
        "monitoring")
            setup_security_monitoring
            ;;
        "help"|"-h"|"--help")
            cat << EOF
Security Hardening Module for VLESS+Reality VPN

Usage: $0 [command] [options]

Commands:
    harden                Complete security hardening (default)
    ssh-setup            Interactive SSH key setup wizard
    disable-password-auth Disable SSH password authentication
    report               Generate security report
    validate             Validate security configuration
    fail2ban             Setup fail2ban only
    monitoring           Setup security monitoring only
    help                 Show this help message

Examples:
    $0 harden              # Complete system hardening
    $0 ssh-setup           # Setup SSH keys interactively
    $0 report              # Generate security report
    $0 validate            # Check security configuration

This module implements comprehensive security hardening including
SSH configuration, fail2ban, automatic updates, and monitoring.
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