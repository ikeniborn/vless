#!/bin/bash
# lib/security_hardening.sh - Security hardening for VLESS Reality VPN
# EPIC-9: Security & Hardening
#
# Provides functions for:
# - TASK-9.1: File permissions (2h)
# - TASK-9.2: Docker security options (2h)
# - TASK-9.3: UFW hardening (2h)
# - TASK-9.4: Security audit (2h)
#
# Author: VPN Deployment System
# Version: 1.0.0

set -euo pipefail

# Color codes for output (only define if not already set)
[[ -z "${RED:-}" ]] && RED='\033[0;31m'
[[ -z "${GREEN:-}" ]] && GREEN='\033[0;32m'
[[ -z "${YELLOW:-}" ]] && YELLOW='\033[1;33m'
[[ -z "${BLUE:-}" ]] && BLUE='\033[0;34m'
[[ -z "${NC:-}" ]] && NC='\033[0m' # No Color

# Logging Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $*" >&2
}

log_warn() {
    log_warning "$@"
}

log_error() {
    echo -e "${RED}[✗]${NC} $*" >&2
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $*" >&2
}

# Configuration paths
# Note: CONFIG_DIR, DATA_DIR, KEYS_DIR, LOGS_DIR are defined as readonly in orchestrator.sh
# We only define paths not available from orchestrator
INSTALL_DIR="/opt/familytraffic"
BACKUP_DIR="${INSTALL_DIR}/backups"

# Security configuration
readonly SECURE_PERMS_DIR="750"
readonly SECURE_PERMS_FILE="640"
readonly SECURE_PERMS_SECRET="600"
readonly SECURE_PERMS_EXEC="750"

#######################################
# TASK-9.1: File Permissions Hardening
#######################################

#######################################
# Apply secure file permissions to installation directory
# Follows principle of least privilege
# Globals:
#   INSTALL_DIR, CONFIG_DIR, DATA_DIR, KEYS_DIR
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
harden_file_permissions() {
    log_info "Applying secure file permissions..."

    if [[ ! -d "$INSTALL_DIR" ]]; then
        log_error "Installation directory not found: $INSTALL_DIR"
        return 1
    fi

    # Main installation directory
    chmod "$SECURE_PERMS_DIR" "$INSTALL_DIR" || {
        log_error "Failed to set permissions on $INSTALL_DIR"
        return 1
    }

    # Configuration directory (sensitive)
    if [[ -d "$CONFIG_DIR" ]]; then
        chmod "$SECURE_PERMS_DIR" "$CONFIG_DIR"
        find "$CONFIG_DIR" -type f -exec chmod "$SECURE_PERMS_FILE" {} \; || {
            log_error "Failed to set config file permissions"
            return 1
        }
    fi

    # Keys directory (highly sensitive)
    if [[ -d "$KEYS_DIR" ]]; then
        chmod 700 "$KEYS_DIR"
        find "$KEYS_DIR" -type f -exec chmod "$SECURE_PERMS_SECRET" {} \; || {
            log_error "Failed to set key file permissions"
            return 1
        }
    fi

    # Data directory (user data)
    if [[ -d "$DATA_DIR" ]]; then
        chmod "$SECURE_PERMS_DIR" "$DATA_DIR"

        # users.json is sensitive
        if [[ -f "${DATA_DIR}/users.json" ]]; then
            chmod "$SECURE_PERMS_SECRET" "${DATA_DIR}/users.json"
        fi

        # Client directories
        if [[ -d "${DATA_DIR}/clients" ]]; then
            find "${DATA_DIR}/clients" -type d -exec chmod "$SECURE_PERMS_DIR" {} \;
            find "${DATA_DIR}/clients" -type f -exec chmod "$SECURE_PERMS_FILE" {} \;
        fi
    fi

    # Logs directory
    if [[ -d "$LOGS_DIR" ]]; then
        chmod "$SECURE_PERMS_DIR" "$LOGS_DIR"
        find "$LOGS_DIR" -type f -exec chmod "$SECURE_PERMS_FILE" {} \; 2>/dev/null || true
    fi

    # Backups directory
    if [[ -d "$BACKUP_DIR" ]]; then
        chmod 700 "$BACKUP_DIR"
        find "$BACKUP_DIR" -type d -exec chmod 700 {} \;
        find "$BACKUP_DIR" -type f -exec chmod "$SECURE_PERMS_SECRET" {} \;
    fi

    # Executable scripts
    local scripts_to_secure=(
        "${INSTALL_DIR}/vless"
        "${INSTALL_DIR}/install.sh"
    )

    for script in "${scripts_to_secure[@]}"; do
        if [[ -f "$script" ]]; then
            chmod "$SECURE_PERMS_EXEC" "$script"
        fi
    done

    # Ensure all files are owned by root
    chown -R root:root "$INSTALL_DIR" || {
        log_error "Failed to set ownership on $INSTALL_DIR"
        return 1
    }

    log_success "File permissions hardened successfully"
    return 0
}

#######################################
# Verify file permissions are secure
# Globals:
#   INSTALL_DIR
# Arguments:
#   None
# Returns:
#   0 if secure, 1 if issues found
#######################################
audit_file_permissions() {
    log_info "Auditing file permissions..."

    local issues=0

    # Check ownership (all files should be root:root)
    local non_root_files
    non_root_files=$(find "$INSTALL_DIR" ! -user root -o ! -group root 2>/dev/null | wc -l)

    if [[ $non_root_files -gt 0 ]]; then
        log_warn "Found $non_root_files files not owned by root:root"
        ((issues++))
    fi

    # Check for world-readable sensitive files
    local world_readable
    world_readable=$(find "$INSTALL_DIR" -type f -perm /o+r 2>/dev/null | wc -l)

    if [[ $world_readable -gt 0 ]]; then
        log_warn "Found $world_readable world-readable files"
        ((issues++))
    fi

    # Check for world-writable files (critical security issue)
    local world_writable
    world_writable=$(find "$INSTALL_DIR" -type f -perm /o+w 2>/dev/null | wc -l)

    if [[ $world_writable -gt 0 ]]; then
        log_error "Found $world_writable world-writable files (CRITICAL)"
        ((issues++))
    fi

    # Check keys directory permissions (must be 700)
    if [[ -d "$KEYS_DIR" ]]; then
        local keys_perms
        keys_perms=$(stat -c '%a' "$KEYS_DIR")

        if [[ "$keys_perms" != "700" ]]; then
            log_error "Keys directory has insecure permissions: $keys_perms (expected: 700)"
            ((issues++))
        fi
    fi

    if [[ $issues -eq 0 ]]; then
        log_success "File permissions are secure"
        return 0
    else
        log_error "Found $issues security issues with file permissions"
        return 1
    fi
}

#######################################
# TASK-9.2: Docker Security Options
#######################################

#######################################
# Verify Docker security configuration
# Checks for required security options in docker-compose.yml
# Globals:
#   INSTALL_DIR
# Arguments:
#   None
# Returns:
#   0 if secure, 1 if issues found
#######################################
verify_docker_security() {
    log_info "Verifying Docker security configuration..."

    local compose_file="${INSTALL_DIR}/docker-compose.yml"

    if [[ ! -f "$compose_file" ]]; then
        log_error "Docker Compose file not found: $compose_file"
        return 1
    fi

    local issues=0

    # Check for cap_drop: ALL
    if ! grep -q "cap_drop:" "$compose_file" || ! grep -q "- ALL" "$compose_file"; then
        log_warn "Missing 'cap_drop: ALL' in docker-compose.yml"
        ((issues++))
    fi

    # Check for no-new-privileges
    if ! grep -q "no-new-privileges:true" "$compose_file"; then
        log_warn "Missing 'no-new-privileges:true' in docker-compose.yml"
        ((issues++))
    fi

    # Check for read_only root filesystem
    if ! grep -q "read_only: true" "$compose_file"; then
        log_warn "Missing 'read_only: true' in docker-compose.yml"
        ((issues++))
    fi

    # Check that containers are not running as root
    if grep -q "user: \"0:0\"" "$compose_file" || grep -q "user: root" "$compose_file"; then
        log_error "Containers running as root (security risk)"
        ((issues++))
    fi

    # Check for host network mode (security risk)
    if grep -q "network_mode: host" "$compose_file"; then
        log_error "Host network mode detected (security risk)"
        ((issues++))
    fi

    # Check for privileged mode (critical security risk)
    if grep -q "privileged: true" "$compose_file"; then
        log_error "Privileged mode detected (CRITICAL security risk)"
        ((issues++))
    fi

    if [[ $issues -eq 0 ]]; then
        log_success "Docker security configuration is secure"
        return 0
    else
        log_error "Found $issues security issues with Docker configuration"
        return 1
    fi
}

#######################################
# Verify running container security
# Checks actual running containers for security issues
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   0 if secure, 1 if issues found
#######################################
verify_container_security() {
    log_info "Verifying running container security..."

    local issues=0

    # Get list of VLESS containers
    local containers
    containers=$(docker ps --filter "name=vless" --format "{{.Names}}" 2>/dev/null)

    if [[ -z "$containers" ]]; then
        log_warn "No running VLESS containers found"
        return 0
    fi

    while IFS= read -r container; do
        log_debug "Checking container: $container"

        # Check if running as root
        local user
        user=$(docker inspect -f '{{.Config.User}}' "$container" 2>/dev/null)

        if [[ -z "$user" ]] || [[ "$user" == "0" ]] || [[ "$user" == "root" ]]; then
            log_warn "Container $container running as root"
            ((issues++))
        fi

        # Check if privileged
        local privileged
        privileged=$(docker inspect -f '{{.HostConfig.Privileged}}' "$container" 2>/dev/null)

        if [[ "$privileged" == "true" ]]; then
            log_error "Container $container running in privileged mode (CRITICAL)"
            ((issues++))
        fi

        # Check capabilities
        local caps
        caps=$(docker inspect -f '{{.HostConfig.CapDrop}}' "$container" 2>/dev/null)

        if [[ "$caps" != "[ALL]" ]]; then
            log_warn "Container $container not dropping all capabilities"
            ((issues++))
        fi

    done <<< "$containers"

    if [[ $issues -eq 0 ]]; then
        log_success "Container security is adequate"
        return 0
    else
        log_error "Found $issues security issues with running containers"
        return 1
    fi
}

#######################################
# TASK-9.3: UFW Hardening
#######################################

#######################################
# Apply UFW hardening rules
# Implements defense-in-depth firewall rules
# Globals:
#   None
# Arguments:
#   $1 - VLESS port
# Returns:
#   0 on success, 1 on failure
#######################################
harden_ufw() {
    local vless_port="${1:-443}"

    log_info "Applying UFW hardening rules..."

    # Ensure UFW is installed
    if ! command -v ufw &>/dev/null; then
        log_error "UFW is not installed"
        return 1
    fi

    # Set default policies (deny incoming, allow outgoing)
    ufw --force default deny incoming || {
        log_error "Failed to set default deny incoming"
        return 1
    }

    ufw --force default allow outgoing || {
        log_error "Failed to set default allow outgoing"
        return 1
    }

    # Allow SSH (essential, prevent lockout)
    ufw allow 22/tcp comment 'SSH' || {
        log_error "Failed to allow SSH"
        return 1
    }

    # Allow VLESS port
    ufw allow "$vless_port"/tcp comment 'VLESS Reality' || {
        log_error "Failed to allow VLESS port"
        return 1
    }

    # Rate limiting on SSH to prevent brute force
    ufw limit 22/tcp comment 'SSH rate limit' 2>/dev/null || {
        log_warn "Failed to apply SSH rate limiting (may already exist)"
    }

    # Deny all other inbound by default (already set, but explicit)
    ufw --force default deny incoming

    # Enable UFW if not already enabled
    if ! ufw status | grep -q "Status: active"; then
        ufw --force enable || {
            log_error "Failed to enable UFW"
            return 1
        }
    fi

    log_success "UFW hardening applied successfully"
    return 0
}

#######################################
# Verify UFW configuration
# Checks firewall rules for security issues
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   0 if secure, 1 if issues found
#######################################
verify_ufw_config() {
    log_info "Verifying UFW configuration..."

    local issues=0

    # Check if UFW is active
    if ! ufw status | grep -q "Status: active"; then
        log_error "UFW is not active (CRITICAL)"
        ((issues++))
        return 1
    fi

    # Check default policies
    local default_incoming
    default_incoming=$(ufw status verbose | grep "Default:" | grep "deny (incoming)" | wc -l)

    if [[ $default_incoming -eq 0 ]]; then
        log_error "Default incoming policy is not deny"
        ((issues++))
    fi

    # Check for overly permissive rules
    if ufw status | grep -q "Anywhere.*ALLOW.*Anywhere"; then
        log_warn "Found potentially overly permissive rules (allow from anywhere)"
        ((issues++))
    fi

    # Check that SSH is allowed (prevent lockout)
    if ! ufw status | grep -q "22/tcp.*ALLOW"; then
        log_error "SSH is not allowed (risk of lockout)"
        ((issues++))
    fi

    # Check for rate limiting on SSH
    if ! ufw status | grep -q "22/tcp.*LIMIT"; then
        log_warn "SSH rate limiting not configured (recommended)"
        ((issues++))
    fi

    if [[ $issues -eq 0 ]]; then
        log_success "UFW configuration is secure"
        return 0
    else
        log_error "Found $issues security issues with UFW configuration"
        return 1
    fi
}

#######################################
# Display UFW status
# Shows current firewall rules
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
display_ufw_status() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  UFW Firewall Status"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    ufw status verbose

    echo ""
    echo "═══════════════════════════════════════════════════════════"
}

#######################################
# TASK-9.4: Security Audit
#######################################

#######################################
# Perform comprehensive security audit
# Runs all security checks and generates report
# Globals:
#   INSTALL_DIR
# Arguments:
#   None
# Returns:
#   0 if all checks pass, 1 if issues found
#######################################
security_audit() {
    log_info "Starting comprehensive security audit..."

    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  VLESS Reality VPN - Security Audit Report"
    echo "  $(date -Iseconds)"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    local total_issues=0

    # Section 1: File Permissions
    echo "┌─ File Permissions ───────────────────────────────────────┐"
    if audit_file_permissions; then
        echo -e "  Status: \033[32m✓ PASS\033[0m"
    else
        echo -e "  Status: \033[31m✗ FAIL\033[0m"
        ((total_issues++))
    fi
    echo "└──────────────────────────────────────────────────────────┘"
    echo ""

    # Section 2: Docker Security
    echo "┌─ Docker Configuration ───────────────────────────────────┐"
    if verify_docker_security; then
        echo -e "  Status: \033[32m✓ PASS\033[0m"
    else
        echo -e "  Status: \033[31m✗ FAIL\033[0m"
        ((total_issues++))
    fi
    echo "└──────────────────────────────────────────────────────────┘"
    echo ""

    # Section 3: Container Runtime Security
    echo "┌─ Container Runtime ──────────────────────────────────────┐"
    if verify_container_security; then
        echo -e "  Status: \033[32m✓ PASS\033[0m"
    else
        echo -e "  Status: \033[31m✗ FAIL\033[0m"
        ((total_issues++))
    fi
    echo "└──────────────────────────────────────────────────────────┘"
    echo ""

    # Section 4: Firewall Configuration
    echo "┌─ Firewall (UFW) ─────────────────────────────────────────┐"
    if verify_ufw_config; then
        echo -e "  Status: \033[32m✓ PASS\033[0m"
    else
        echo -e "  Status: \033[31m✗ FAIL\033[0m"
        ((total_issues++))
    fi
    echo "└──────────────────────────────────────────────────────────┘"
    echo ""

    # Section 5: Network Security
    echo "┌─ Network Security ───────────────────────────────────────┐"
    if audit_network_security; then
        echo -e "  Status: \033[32m✓ PASS\033[0m"
    else
        echo -e "  Status: \033[33m⚠ WARN\033[0m"
    fi
    echo "└──────────────────────────────────────────────────────────┘"
    echo ""

    # Section 6: Sensitive Data
    echo "┌─ Sensitive Data Protection ─────────────────────────────┐"
    if audit_sensitive_data; then
        echo -e "  Status: \033[32m✓ PASS\033[0m"
    else
        echo -e "  Status: \033[31m✗ FAIL\033[0m"
        ((total_issues++))
    fi
    echo "└──────────────────────────────────────────────────────────┘"
    echo ""

    # Summary
    echo "═══════════════════════════════════════════════════════════"
    if [[ $total_issues -eq 0 ]]; then
        echo -e "  Overall Status: \033[32m✓ SECURE\033[0m"
        echo "  All security checks passed"
    else
        echo -e "  Overall Status: \033[31m✗ ISSUES FOUND\033[0m"
        echo "  Found $total_issues critical security issues"
        echo "  Run 'vless security fix' to automatically fix issues"
    fi
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    return $total_issues
}

#######################################
# Audit network security
# Checks for exposed ports and network issues
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   0 if secure, 1 if issues found
#######################################
audit_network_security() {
    log_debug "Auditing network security..."

    local issues=0

    # Check for exposed Docker ports
    local exposed_ports
    exposed_ports=$(docker ps --format "{{.Ports}}" 2>/dev/null | grep -E "0\.0\.0\.0" | wc -l)

    if [[ $exposed_ports -gt 0 ]]; then
        log_warn "Found $exposed_ports containers with ports exposed to 0.0.0.0"
    fi

    # Check for containers on host network
    local host_network
    host_network=$(docker ps --format "{{.Networks}}" 2>/dev/null | grep -w "host" | wc -l)

    if [[ $host_network -gt 0 ]]; then
        log_error "Found $host_network containers using host network (security risk)"
        ((issues++))
    fi

    # Check if IP forwarding is enabled (required for Docker)
    if [[ -f /proc/sys/net/ipv4/ip_forward ]]; then
        local ip_forward
        ip_forward=$(cat /proc/sys/net/ipv4/ip_forward)

        if [[ "$ip_forward" != "1" ]]; then
            log_warn "IP forwarding is disabled (Docker may not work)"
            ((issues++))
        fi
    fi

    return $issues
}

#######################################
# Audit sensitive data protection
# Checks for exposed secrets and sensitive files
# Globals:
#   INSTALL_DIR, KEYS_DIR
# Arguments:
#   None
# Returns:
#   0 if secure, 1 if issues found
#######################################
audit_sensitive_data() {
    log_debug "Auditing sensitive data protection..."

    local issues=0

    # Check for world-readable key files
    if [[ -d "$KEYS_DIR" ]]; then
        local readable_keys
        readable_keys=$(find "$KEYS_DIR" -type f -perm /o+r 2>/dev/null | wc -l)

        if [[ $readable_keys -gt 0 ]]; then
            log_error "Found $readable_keys world-readable key files (CRITICAL)"
            ((issues++))
        fi
    fi

    # Check for plaintext passwords in config files
    if [[ -d "$CONFIG_DIR" ]]; then
        if grep -r "password" "$CONFIG_DIR" 2>/dev/null | grep -v "^Binary" | grep -qv "#"; then
            log_warn "Found potential plaintext passwords in config files"
            ((issues++))
        fi
    fi

    # Check for .env file permissions
    if [[ -f "${INSTALL_DIR}/.env" ]]; then
        local env_perms
        env_perms=$(stat -c '%a' "${INSTALL_DIR}/.env")

        if [[ "$env_perms" != "600" ]] && [[ "$env_perms" != "640" ]]; then
            log_warn ".env file has insecure permissions: $env_perms"
            ((issues++))
        fi
    fi

    # Check users.json permissions
    if [[ -f "${DATA_DIR}/users.json" ]]; then
        local users_perms
        users_perms=$(stat -c '%a' "${DATA_DIR}/users.json")

        if [[ "$users_perms" != "600" ]] && [[ "$users_perms" != "640" ]]; then
            log_warn "users.json has insecure permissions: $users_perms"
            ((issues++))
        fi
    fi

    return $issues
}

#######################################
# Automated security fix
# Attempts to automatically fix common security issues
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
security_fix() {
    log_info "Attempting to automatically fix security issues..."

    local fixes_applied=0

    # Fix file permissions
    if harden_file_permissions; then
        log_success "File permissions fixed"
        ((fixes_applied++))
    else
        log_error "Failed to fix file permissions"
    fi

    # Read VLESS port from config
    local vless_port
    if [[ -f "${CONFIG_DIR}/xray_config.json" ]]; then
        vless_port=$(jq -r '.inbounds[0].port' "${CONFIG_DIR}/xray_config.json" 2>/dev/null || echo "443")
    else
        vless_port="443"
    fi

    # Fix UFW configuration
    if harden_ufw "$vless_port"; then
        log_success "UFW configuration fixed"
        ((fixes_applied++))
    else
        log_error "Failed to fix UFW configuration"
    fi

    log_success "Applied $fixes_applied security fixes"

    # Run audit again to verify
    echo ""
    log_info "Running security audit to verify fixes..."
    security_audit

    return 0
}

#######################################
# Generate security report to file
# Creates detailed security report
# Globals:
#   INSTALL_DIR
# Arguments:
#   $1 - Output file path (optional)
# Returns:
#   0 on success, 1 on failure
#######################################
generate_security_report() {
    local output_file="${1:-${INSTALL_DIR}/security_report_$(date +%Y%m%d_%H%M%S).txt}"

    log_info "Generating security report: $output_file"

    {
        echo "VLESS Reality VPN - Security Audit Report"
        echo "=========================================="
        echo "Generated: $(date -Iseconds)"
        echo "Hostname: $(hostname)"
        echo "Installation: $INSTALL_DIR"
        echo ""

        security_audit

    } > "$output_file" 2>&1

    if [[ -f "$output_file" ]]; then
        chmod 600 "$output_file"
        log_success "Security report saved: $output_file"
        return 0
    else
        log_error "Failed to generate security report"
        return 1
    fi
}

#######################################
# TASK-1.3: Port 80 Management for ACME
# (NEW in v3.3 for Let's Encrypt)
#######################################

#######################################
# Open port 80 for ACME HTTP-01 challenge
# Temporarily allows HTTP traffic for Let's Encrypt validation
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
open_port_80_for_acme() {
    log_info "Opening port 80 for ACME HTTP-01 challenge..."

    # Check if UFW is active
    if ! ufw status | grep -q "Status: active"; then
        log_error "UFW is not active. Enable UFW first: sudo ufw enable"
        return 1
    fi

    # Check if port 80 is already open
    if ufw status numbered | grep -q "80/tcp.*ALLOW"; then
        log_warn "Port 80 is already open (existing UFW rule)"
        return 0
    fi

    # Check if port 80 is occupied by another service
    if ss -tulnp | grep -q ":80 "; then
        local process_info=$(lsof -i :80 2>/dev/null | tail -n +2 | head -1 || echo "Unknown process")
        log_warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_warn "WARNING: Port 80 is currently occupied"
        log_warn "Process: $process_info"
        log_warn ""
        log_warn "ACME HTTP-01 challenge requires port 80 to be available."
        log_warn "The challenge may fail if the port cannot be freed."
        log_warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        read -p "Continue anyway and try to open port 80? (yes/no): " confirm

        if [[ "$confirm" != "yes" ]]; then
            log_info "Aborted by user"
            return 1
        fi
    fi

    # Open port 80 with UFW
    if ufw allow 80/tcp comment 'ACME HTTP-01 challenge (temporary)'; then
        ufw reload >/dev/null 2>&1
        log_success "Port 80 opened for ACME challenge"
        return 0
    else
        log_error "Failed to open port 80"
        return 1
    fi
}

#######################################
# Close port 80 after ACME challenge
# Removes temporary HTTP access after certificate acquisition
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure (non-critical)
#######################################
close_port_80_after_acme() {
    log_info "Closing port 80 after ACME challenge..."

    # Check if UFW rule exists
    if ! ufw status numbered | grep -q "80/tcp.*ACME"; then
        log_warn "Port 80 ACME rule not found (already closed?)"
        return 0
    fi

    # Delete UFW rule for port 80
    if ufw delete allow 80/tcp >/dev/null 2>&1; then
        ufw reload >/dev/null 2>&1
        log_success "Port 80 closed"
        return 0
    else
        log_warn "Failed to close port 80 automatically"
        log_warn "Manual cleanup: sudo ufw delete allow 80/tcp"
        return 1
    fi
}

#######################################
# Main execution check
#######################################

# If script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    log_error "This script should be sourced, not executed directly"
    exit 1
fi

log_debug "Security hardening module loaded (v3.3 with ACME port management)"
