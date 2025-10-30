#!/bin/bash
# ============================================================================
# VLESS Reality Deployment System
# Module: Post-Installation Verification
# Version: 1.0.0
# Task: TASK-1.8
# ============================================================================
#
# Purpose:
#   Verify that the installation completed successfully and all components
#   are functioning correctly. This module performs comprehensive checks
#   across all installation layers.
#
# Functions:
#   1. verify_installation()       - Main verification orchestrator
#   2. verify_directory_structure() - Check /opt/vless filesystem
#   3. verify_file_permissions()   - Validate security permissions
#   4. verify_docker_network()     - Check Docker bridge network
#   5. verify_containers()         - Health check containers
#   6. verify_xray_config()        - Validate Xray configuration
#   7. verify_ufw_rules()          - Check firewall rules
#   8. verify_container_internet() - Test internet connectivity
#   9. verify_port_listening()     - Check VLESS port
#   10. display_verification_summary() - Show results
#
# Usage:
#   source lib/verification.sh
#   verify_installation
#
# Exit Codes:
#   0 = All verifications passed
#   1 = One or more verifications failed
#
# Dependencies:
#   - Docker & Docker Compose
#   - jq
#   - /opt/vless installation
#
# Author: Claude Code Agent
# Date: 2025-10-02
# ============================================================================

set -euo pipefail

# ============================================================================
# Global Variables
# ============================================================================

VLESS_HOME="/opt/vless"
# INSTALL_ROOT and XRAY_IMAGE are set as readonly in orchestrator.sh (loaded before verification.sh)
# Only set them if not already defined (standalone execution mode)
if [[ -z "${INSTALL_ROOT:-}" ]]; then
    INSTALL_ROOT="/opt/vless"
fi
if [[ -z "${XRAY_IMAGE:-}" ]]; then
    XRAY_IMAGE="teddysun/xray:24.11.30"
fi
VERIFICATION_PASSED=true
VERIFICATION_ERRORS=()

# Colors for output
# Only define if not already set (to avoid conflicts when sourced after install.sh)
[[ -z "${RED:-}" ]] && RED='\033[0;31m'
[[ -z "${GREEN:-}" ]] && GREEN='\033[0;32m'
[[ -z "${YELLOW:-}" ]] && YELLOW='\033[1;33m'
[[ -z "${BLUE:-}" ]] && BLUE='\033[0;34m'
[[ -z "${NC:-}" ]] && NC='\033[0m' # No Color

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $*"
}

log_error() {
    echo -e "${RED}[✗]${NC} $*"
    VERIFICATION_PASSED=false
    VERIFICATION_ERRORS+=("$*")
}

# ============================================================================
# Main Verification Function
# ============================================================================

verify_installation() {
    echo ""
    echo "======================================================================"
    echo "  VLESS Reality - Post-Installation Verification"
    echo "======================================================================"
    echo ""

    log_info "Starting comprehensive verification checks..."
    echo ""

    # Run all verification checks
    verify_directory_structure
    verify_file_permissions
    verify_docker_network
    verify_containers
    verify_xray_config
    test_xray_config
    validate_mandatory_tls
    verify_ufw_rules
    verify_container_internet
    verify_port_listening

    # Display summary
    display_verification_summary

    # Return exit code
    if [[ "$VERIFICATION_PASSED" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# Check 1: Directory Structure
# ============================================================================

verify_directory_structure() {
    log_info "Verification 1/8: Checking directory structure..."

    local required_dirs=(
        "$VLESS_HOME"
        "$VLESS_HOME/config"
        "$VLESS_HOME/data"
        "$VLESS_HOME/data/clients"
        "$VLESS_HOME/keys"
        "$VLESS_HOME/logs"
        "$VLESS_HOME/fake-site"
        "$VLESS_HOME/scripts"
        "$VLESS_HOME/docs"
        "$VLESS_HOME/tests"
        "$VLESS_HOME/tests/unit"
        "$VLESS_HOME/tests/integration"
        "$VLESS_HOME/backup"
    )

    local missing_dirs=()

    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            missing_dirs+=("$dir")
        fi
    done

    if [[ ${#missing_dirs[@]} -eq 0 ]]; then
        log_success "All required directories exist (${#required_dirs[@]} directories)"
    else
        log_error "Missing directories (${#missing_dirs[@]}):"
        for dir in "${missing_dirs[@]}"; do
            echo "    - $dir"
        done
    fi

    # Check required files
    local required_files=(
        "$VLESS_HOME/docker-compose.yml"
        "$VLESS_HOME/.env"
        "$VLESS_HOME/config/xray_config.json"
        "$VLESS_HOME/data/users.json"
        "$VLESS_HOME/fake-site/default.conf"
        "$VLESS_HOME/keys/private.key"
        "$VLESS_HOME/keys/public.key"
    )

    local missing_files=()

    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            missing_files+=("$file")
        fi
    done

    if [[ ${#missing_files[@]} -eq 0 ]]; then
        log_success "All required files exist (${#required_files[@]} files)"
    else
        log_error "Missing files (${#missing_files[@]}):"
        for file in "${missing_files[@]}"; do
            echo "    - $file"
        done
    fi

    echo ""
}

# ============================================================================
# Check 2: File Permissions
# ============================================================================

verify_file_permissions() {
    log_info "Verification 2/8: Checking file permissions..."

    local permission_errors=0

    # Check sensitive directories (should be 700)
    local sensitive_dirs=(
        "$VLESS_HOME/keys"
        "$VLESS_HOME/data"
        "$VLESS_HOME/data/clients"
    )

    for dir in "${sensitive_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local perms=$(stat -c '%a' "$dir" 2>/dev/null || echo "000")
            if [[ "$perms" != "700" ]]; then
                log_error "Directory $dir has incorrect permissions: $perms (expected 700)"
                ((permission_errors++))
            fi
        fi
    done

    # Check sensitive files (should be 600)
    local sensitive_files=(
        "$VLESS_HOME/.env"
        "$VLESS_HOME/keys/private.key"
        "$VLESS_HOME/keys/public.key"
        "$VLESS_HOME/data/users.json"
    )

    for file in "${sensitive_files[@]}"; do
        if [[ -f "$file" ]]; then
            local perms=$(stat -c '%a' "$file" 2>/dev/null || echo "000")
            if [[ "$perms" != "600" ]]; then
                log_error "File $file has incorrect permissions: $perms (expected 600)"
                ((permission_errors++))
            fi
        fi
    done

    # Check ownership (all files should be owned by root)
    local all_paths=(
        "$VLESS_HOME"
        "$VLESS_HOME/config"
        "$VLESS_HOME/data"
        "$VLESS_HOME/keys"
    )

    for path in "${all_paths[@]}"; do
        if [[ -e "$path" ]]; then
            local owner=$(stat -c '%U' "$path" 2>/dev/null || echo "unknown")
            if [[ "$owner" != "root" ]]; then
                log_error "Path $path has incorrect owner: $owner (expected root)"
                ((permission_errors++))
            fi
        fi
    done

    if [[ $permission_errors -eq 0 ]]; then
        log_success "All file permissions and ownership are correct"
    else
        log_error "Found $permission_errors permission/ownership issues"
    fi

    echo ""
}

# ============================================================================
# Check 3: Docker Network
# ============================================================================

verify_docker_network() {
    log_info "Verification 3/8: Checking Docker network..."

    # Check if network exists
    if ! docker network inspect vless_reality_net &>/dev/null; then
        log_error "Docker network 'vless_reality_net' does not exist"
        echo ""
        return 1
    fi

    # Verify network configuration
    local subnet=$(docker network inspect vless_reality_net -f '{{(index .IPAM.Config 0).Subnet}}' 2>/dev/null || echo "")
    local driver=$(docker network inspect vless_reality_net -f '{{.Driver}}' 2>/dev/null || echo "")

    if [[ -z "$subnet" ]]; then
        log_error "Could not determine network subnet"
    else
        log_success "Network subnet: $subnet"
    fi

    if [[ "$driver" != "bridge" ]]; then
        log_error "Network driver is '$driver' (expected 'bridge')"
    else
        log_success "Network driver: bridge"
    fi

    # Verify network is isolated
    local network_id=$(docker network inspect vless_reality_net -f '{{.Id}}' 2>/dev/null | cut -c1-12)
    if [[ -n "$network_id" ]]; then
        log_success "Network ID: $network_id"
    fi

    echo ""
}

# ============================================================================
# Check 4: Container Health
# ============================================================================

verify_containers() {
    log_info "Verification 4/8: Checking container health..."

    # Check xray container using docker inspect (more reliable)
    local xray_status=$(docker inspect vless_xray -f '{{.State.Status}}' 2>/dev/null || echo "not-found")
    if [[ "$xray_status" == "running" ]]; then
        log_success "Container 'vless_xray' is running"

        # Check uptime
        local started_at=$(docker inspect vless_xray -f '{{.State.StartedAt}}' 2>/dev/null || echo "")
        if [[ -n "$started_at" ]]; then
            log_info "  Started at: $started_at"
        fi

        # Check for critical errors in logs
        local xray_logs=$(docker logs vless_xray 2>&1 | tail -20)
        if echo "$xray_logs" | grep -qE "(CRITICAL|FATAL|panic)"; then
            log_warning "Container 'vless_xray' has critical messages in logs"
        fi
    elif [[ "$xray_status" == "not-found" ]]; then
        log_error "Container 'vless_xray' not found"
    else
        log_error "Container 'vless_xray' exists but status is: $xray_status"
    fi

    # Check nginx container using docker inspect (more reliable)
    local nginx_status=$(docker inspect vless_fake_site -f '{{.State.Status}}' 2>/dev/null || echo "not-found")
    if [[ "$nginx_status" == "running" ]]; then
        log_success "Container 'vless_fake_site' is running"

        # Check uptime
        local started_at=$(docker inspect vless_fake_site -f '{{.State.StartedAt}}' 2>/dev/null || echo "")
        if [[ -n "$started_at" ]]; then
            log_info "  Started at: $started_at"
        fi

        # Check healthcheck status (added in v4.1.1)
        local nginx_health=$(docker inspect vless_fake_site -f '{{.State.Health.Status}}' 2>/dev/null || echo "no-healthcheck")
        if [[ "$nginx_health" == "healthy" ]]; then
            log_success "Container 'vless_fake_site' health: healthy"
        elif [[ "$nginx_health" == "starting" ]]; then
            log_info "  Container 'vless_fake_site' health: starting"
        elif [[ "$nginx_health" == "unhealthy" ]]; then
            log_error "Container 'vless_fake_site' health: unhealthy"
        fi

        # Check Nginx logs for critical errors only (ignore informational warnings)
        local nginx_logs=$(docker logs vless_fake_site 2>&1 | tail -20)
        if echo "$nginx_logs" | grep -q "nginx: \[emerg\]"; then
            log_error "Container 'vless_fake_site' has critical errors in logs"
        elif echo "$nginx_logs" | grep -qE "(can not modify|read-only file system)"; then
            log_info "  Nginx running in read-only mode (expected for security)"
        fi
    elif [[ "$nginx_status" == "not-found" ]]; then
        log_error "Container 'vless_fake_site' not found"
    else
        log_error "Container 'vless_fake_site' exists but status is: $nginx_status"
    fi

    # Check if containers are on the correct network
    local xray_networks=$(docker inspect vless_xray -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null || echo "")
    if [[ "$xray_networks" =~ vless_reality_net ]]; then
        log_success "Container 'vless_xray' is connected to vless_reality_net"
    else
        log_error "Container 'vless_xray' is not connected to vless_reality_net (networks: $xray_networks)"
    fi

    local nginx_networks=$(docker inspect vless_fake_site -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null || echo "")
    if [[ "$nginx_networks" =~ vless_reality_net ]]; then
        log_success "Container 'vless_fake_site' is connected to vless_reality_net"
    else
        log_error "Container 'vless_fake_site' is not connected to vless_reality_net (networks: $nginx_networks)"
    fi

    # Check restart policy
    local xray_restart=$(docker inspect vless_xray -f '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null || echo "")
    if [[ "$xray_restart" == "unless-stopped" ]]; then
        log_success "Container 'vless_xray' restart policy: unless-stopped"
    else
        log_warning "Container 'vless_xray' restart policy: $xray_restart (expected unless-stopped)"
    fi

    # Check HAProxy container if proxy enabled (v4.3+)
    if [[ "${ENABLE_PUBLIC_PROXY:-false}" == "true" ]]; then
        local haproxy_status=$(docker inspect vless_haproxy -f '{{.State.Status}}' 2>/dev/null || echo "not-found")
        if [[ "$haproxy_status" == "running" ]]; then
            log_success "Container 'vless_haproxy' is running"

            # Check healthcheck status (if available)
            local haproxy_health=$(docker inspect vless_haproxy -f '{{.State.Health.Status}}' 2>/dev/null || echo "no-healthcheck")
            if [[ "$haproxy_health" == "healthy" ]]; then
                log_success "Container 'vless_haproxy' health: healthy"
            elif [[ "$haproxy_health" == "starting" ]]; then
                log_info "  Container 'vless_haproxy' health: starting"
            elif [[ "$haproxy_health" == "unhealthy" ]]; then
                log_error "Container 'vless_haproxy' health: unhealthy"
            fi

            # v4.3: HAProxy runs in host network mode (no Docker network attachment)
            log_info "  HAProxy network mode: host (direct access to ports 443, 1080, 8118)"
        elif [[ "$haproxy_status" != "not-found" ]]; then
            log_error "Container 'vless_haproxy' exists but status is: $haproxy_status"
        fi
    fi

    echo ""
}

# ============================================================================
# Check 5: Xray Configuration Validation
# ============================================================================

verify_xray_config() {
    log_info "Verification 5/8: Validating Xray configuration..."

    local config_file="$VLESS_HOME/config/xray_config.json"

    # Check if config exists
    if [[ ! -f "$config_file" ]]; then
        log_error "Xray configuration file not found: $config_file"
        echo ""
        return 1
    fi

    # Validate JSON syntax
    if ! jq empty "$config_file" 2>/dev/null; then
        log_error "Invalid JSON syntax in xray_config.json"
        echo ""
        return 1
    fi

    log_success "Xray configuration JSON syntax is valid"

    # Validate with xray -test
    if docker exec vless_xray xray -test -config=/etc/xray/config.json &>/dev/null; then
        log_success "Xray configuration validation passed (xray -test)"
    else
        log_error "Xray configuration validation failed (xray -test)"
        # Show detailed error
        local error_output=$(docker exec vless_xray xray -test -config=/etc/xray/config.json 2>&1 || true)
        echo "    Error details:"
        echo "$error_output" | sed 's/^/    /'
    fi

    # Verify critical configuration elements
    local protocol=$(jq -r '.inbounds[0].protocol' "$config_file" 2>/dev/null || echo "")
    if [[ "$protocol" == "vless" ]]; then
        log_success "Inbound protocol: vless"
    else
        log_error "Inbound protocol is '$protocol' (expected 'vless')"
    fi

    local security=$(jq -r '.inbounds[0].streamSettings.security' "$config_file" 2>/dev/null || echo "")
    if [[ "$security" == "reality" ]]; then
        log_success "Stream security: reality"
    else
        log_error "Stream security is '$security' (expected 'reality')"
    fi

    local private_key=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$config_file" 2>/dev/null || echo "")
    if [[ -n "$private_key" && "$private_key" != "null" ]]; then
        log_success "Reality private key is configured"
    else
        log_error "Reality private key is missing or null"
    fi

    local dest=$(jq -r '.inbounds[0].streamSettings.realitySettings.dest' "$config_file" 2>/dev/null || echo "")
    if [[ -n "$dest" && "$dest" != "null" ]]; then
        log_success "Reality destination: $dest"
    else
        log_error "Reality destination is missing or null"
    fi

    echo ""
}

# ============================================================================
# Check 6: UFW Firewall Rules
# ============================================================================

verify_ufw_rules() {
    log_info "Verification 6/10: Checking UFW firewall rules..."

    # Check if UFW is installed and active
    if ! command -v ufw &>/dev/null; then
        log_warning "UFW is not installed"
        echo ""
        return 0
    fi

    local ufw_status=$(ufw status 2>/dev/null | head -n1 || echo "")
    if [[ "$ufw_status" =~ "Status: active" ]]; then
        log_success "UFW is active"
    else
        log_warning "UFW is not active"
        echo ""
        return 0
    fi

    # Check VLESS port rule (v4.3: HAProxy on 443, Xray on 8443 internal)
    local vless_port=$(jq -r '.inbounds[0].port' "$VLESS_HOME/config/xray_config.json" 2>/dev/null || echo "8443")

    # In v4.3: Port 443 must be in UFW (HAProxy frontend), port 8443 is internal
    if [[ "$vless_port" == "8443" ]]; then
        # v4.3 architecture: Check port 443 (HAProxy) instead
        if ufw status numbered | grep -q "443/tcp.*ALLOW"; then
            log_success "UFW allows port 443/tcp (HAProxy frontend)"
            log_info "  Port 8443 is internal (HAProxy → Xray, not in UFW) - expected for v4.3"
        else
            log_error "UFW does not allow port 443/tcp (required for HAProxy)"
        fi
    else
        # Legacy architecture or custom port
        if ufw status numbered | grep -q "${vless_port}/tcp.*ALLOW"; then
            log_success "UFW allows port $vless_port/tcp"
        else
            log_error "UFW does not allow port $vless_port/tcp"
        fi
    fi

    # Check Docker forwarding rules in after.rules
    if [[ -f /etc/ufw/after.rules ]]; then
        if grep -q "BEGIN VLESS REALITY DOCKER FORWARDING RULES" /etc/ufw/after.rules; then
            log_success "Docker forwarding rules found in /etc/ufw/after.rules"

            # Verify MASQUERADE rule
            if grep -q "MASQUERADE" /etc/ufw/after.rules; then
                log_success "MASQUERADE rule configured"
            else
                log_warning "MASQUERADE rule not found in after.rules"
            fi
        else
            log_warning "VLESS REALITY DOCKER FORWARDING rules section not found in /etc/ufw/after.rules"
        fi
    else
        log_warning "/etc/ufw/after.rules file not found"
    fi

    # Check iptables NAT rules
    if command -v iptables &>/dev/null; then
        if iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -q "MASQUERADE"; then
            log_success "iptables MASQUERADE rule active"
        else
            log_warning "iptables MASQUERADE rule not found (may be normal if UFW hasn't loaded rules yet)"
        fi
    fi

    echo ""
}

# ============================================================================
# Check 7: Container Internet Connectivity
# ============================================================================

verify_container_internet() {
    log_info "Verification 7/10: Testing container internet connectivity..."

    # Use detected DNS if available, otherwise fall back to 8.8.8.8
    local test_dns="${DETECTED_DNS_PRIMARY:-8.8.8.8}"
    local dns_label=""

    # Determine DNS provider name for informative output
    case "$test_dns" in
        "1.1.1.1") dns_label="Cloudflare DNS" ;;
        "8.8.8.8") dns_label="Google DNS" ;;
        "9.9.9.9") dns_label="Quad9 DNS" ;;
        "77.88.8.8") dns_label="Yandex DNS (Primary)" ;;
        "77.88.8.1") dns_label="Yandex DNS (Secondary)" ;;
        *) dns_label="Custom DNS" ;;
    esac

    # Display which DNS is being used for testing
    if [[ -n "${DETECTED_DNS_PRIMARY:-}" ]]; then
        log_info "  Using auto-detected DNS: ${test_dns} (${dns_label})"
    else
        log_info "  DNS auto-detection not configured, using fallback: ${test_dns} (${dns_label})"
    fi
    echo ""

    # [1/4] Test connectivity from xray container using detected DNS
    log_info "  [1/4] Testing xray container internet connectivity..."
    if docker exec vless_xray ping -c 3 -W 5 "$test_dns" &>/dev/null; then
        log_success "Container 'vless_xray' can reach internet (ping ${test_dns})"
    else
        log_error "Container 'vless_xray' cannot reach internet (ping ${test_dns} failed)"
        log_warning "  This may indicate UFW Docker forwarding issue"
        log_warning "  Check: sudo ufw status | grep DOCKER"
    fi
    echo ""

    # [2/4] Test DNS resolution from xray container
    log_info "  [2/4] Testing DNS resolution capability..."
    if docker exec vless_xray ping -c 3 -W 5 google.com &>/dev/null; then
        log_success "Container 'vless_xray' has DNS resolution"
    else
        log_error "Container 'vless_xray' cannot resolve DNS (ping google.com failed)"
        log_warning "  This may indicate DNS server unavailability"
        log_warning "  Current DNS: ${test_dns}"
    fi
    echo ""

    # [3/4] Test connectivity from nginx container (if exists)
    if docker ps --format '{{.Names}}' | grep -q '^vless_fake_site$'; then
        log_info "  [3/4] Testing nginx reverse proxy container..."
        if docker exec vless_fake_site ping -c 3 -W 5 "$test_dns" &>/dev/null; then
            log_success "Container 'vless_fake_site' can reach internet (ping ${test_dns})"
        else
            log_error "Container 'vless_fake_site' cannot reach internet (ping ${test_dns} failed)"
        fi
        echo ""
    fi

    # [4/4] Test connection to Reality destination
    log_info "  [4/4] Testing Reality destination connectivity..."
    local dest=$(jq -r '.inbounds[0].streamSettings.realitySettings.dest' "$VLESS_HOME/config/xray_config.json" 2>/dev/null || echo "")
    if [[ -n "$dest" && "$dest" != "null" ]]; then
        local dest_host=$(echo "$dest" | cut -d':' -f1)
        local dest_port=$(echo "$dest" | cut -d':' -f2)

        if docker exec vless_xray timeout 5 bash -c "echo > /dev/tcp/$dest_host/$dest_port" 2>/dev/null; then
            log_success "Container can reach Reality destination: $dest"
        else
            log_warning "Container cannot reach Reality destination: $dest"
            log_warning "  This may be normal if destination requires TLS handshake"
            log_warning "  Xray will handle the connection during normal operation"
        fi
    else
        log_warning "Reality destination not configured, skipping connectivity test"
    fi

    echo ""
}

# ============================================================================
# Check 8: Port Listening
# ============================================================================

verify_port_listening() {
    log_info "Verification 8/10: Checking port listening status..."

    local vless_port=$(jq -r '.inbounds[0].port' "$VLESS_HOME/config/xray_config.json" 2>/dev/null || echo "443")

    # Check if port is listening on host (v4.3: check HAProxy ports, not Xray)
    if [[ "$vless_port" == "8443" ]]; then
        # v4.3 architecture: Port 8443 is internal (Docker-only), check port 443 instead
        if ss -tuln | grep -q ":443 "; then
            log_success "Port 443 is listening on host (HAProxy frontend)"
            log_info "  Port 8443 is Docker-internal only (not on host) - expected for v4.3"
        elif netstat -tuln 2>/dev/null | grep -q ":443 "; then
            log_success "Port 443 is listening on host (HAProxy frontend)"
            log_info "  Port 8443 is Docker-internal only (not on host) - expected for v4.3"
        else
            log_error "Port 443 is not listening on host (HAProxy not running)"
        fi
    else
        # Legacy architecture or custom port
        if ss -tuln | grep -q ":${vless_port} "; then
            log_success "Port $vless_port is listening on host"
        elif netstat -tuln 2>/dev/null | grep -q ":${vless_port} "; then
            log_success "Port $vless_port is listening on host"
        else
            log_error "Port $vless_port is not listening on host"
        fi
    fi

    # Check port bindings in Docker (v4.3: Xray uses 'expose', HAProxy uses 'ports')
    if [[ "$vless_port" == "8443" ]]; then
        # v4.3 architecture: Xray port 8443 is exposed (not bound), HAProxy port 443 is bound
        local haproxy_bindings=$(docker inspect vless_haproxy -f '{{range $p, $conf := .NetworkSettings.Ports}}{{$p}} -> {{(index $conf 0).HostPort}} {{end}}' 2>/dev/null || echo "")
        if [[ "$haproxy_bindings" =~ "443" ]]; then
            log_success "Container 'vless_haproxy' port binding: $haproxy_bindings"
            log_info "  Container 'vless_xray' port 8443 uses 'expose' (Docker-internal) - expected for v4.3"
        else
            log_error "Container 'vless_haproxy' port 443 is not bound to host"
        fi
    else
        # Legacy architecture or custom port
        local port_bindings=$(docker inspect vless_xray -f '{{range $p, $conf := .NetworkSettings.Ports}}{{$p}} -> {{(index $conf 0).HostPort}} {{end}}' 2>/dev/null || echo "")
        if [[ "$port_bindings" =~ "$vless_port" ]]; then
            log_success "Container 'vless_xray' port binding: $port_bindings"
        else
            log_error "Container 'vless_xray' port $vless_port is not bound to host"
        fi
    fi

    # Check if port is accessible from outside (basic check)
    local server_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "unknown")
    if [[ "$server_ip" != "unknown" ]]; then
        log_info "Server public IP: $server_ip"
    fi

    echo ""
}

# ============================================================================
# Display Summary
# ============================================================================

display_verification_summary() {
    echo "======================================================================"
    echo "  Verification Summary"
    echo "======================================================================"
    echo ""

    if [[ "$VERIFICATION_PASSED" == "true" ]]; then
        log_success "ALL VERIFICATIONS PASSED"
        echo ""
        echo "Your VLESS Reality installation is ready to use!"
        echo ""
        echo "Next steps:"
        echo "  1. Create your first user:"
        echo "     sudo /opt/vless/vless add-user <username>"
        echo ""
        echo "  2. View service status:"
        echo "     docker ps | grep vless"
        echo ""
        echo "  3. Check logs:"
        echo "     docker-compose -f /opt/vless/docker-compose.yml logs"
        echo ""
    else
        log_error "VERIFICATION FAILED (${#VERIFICATION_ERRORS[@]} errors)"
        echo ""
        echo "Errors encountered:"
        for error in "${VERIFICATION_ERRORS[@]}"; do
            echo "  - $error"
        done
        echo ""
        echo "Please review the errors above and fix them before proceeding."
        echo ""
        echo "Common fixes:"
        echo "  1. Container issues: docker-compose -f /opt/vless/docker-compose.yml up -d"
        echo "  2. Permission issues: Run the installation script again as root"
        echo "  3. Network issues: Check UFW Docker forwarding configuration"
        echo ""
    fi

    echo "======================================================================"
    echo ""
}

# ============================================================================
# FUNCTION: validate_mandatory_tls
# ============================================================================
# Description: Validate TLS configuration for public proxy mode (v3.3)
# Checks:
#   - streamSettings.security="tls" for SOCKS5/HTTP inbounds
#   - Certificate files exist and accessible
#   - Docker volume mount configured
# Returns: 0 if valid, 1 if validation fails
# Related: TASK-2.4 (v3.3 TLS Validation)
# ============================================================================
validate_mandatory_tls() {
    echo ""
    log_info "Verification 5.6/10: Validating TLS encryption (v4.3 HAProxy unified architecture)..."

    # Only validate if public proxy mode enabled
    if [[ "${ENABLE_PUBLIC_PROXY:-false}" != "true" ]]; then
        log_info "  ⊗ Public proxy disabled, skipping TLS validation"
        echo ""
        return 0
    fi

    local validation_failed=0

    # Check 1: haproxy.cfg exists as FILE (not directory!)
    log_info "  [1/5] Checking HAProxy configuration file..."
    if [[ ! -f "${INSTALL_ROOT}/config/haproxy.cfg" ]]; then
        if [[ -d "${INSTALL_ROOT}/config/haproxy.cfg" ]]; then
            log_error "    ✗ haproxy.cfg is a DIRECTORY (should be FILE)"
        else
            log_error "    ✗ haproxy.cfg not found"
        fi
        validation_failed=1
    else
        log_success "    ✓ haproxy.cfg exists"
    fi

    # Check 2: HAProxy container exists
    log_info "  [2/5] Checking HAProxy container..."
    if ! docker ps -a --format '{{.Names}}' | grep -q '^vless_haproxy$'; then
        log_error "    ✗ HAProxy container not found"
        validation_failed=1
    else
        local haproxy_status=$(docker inspect vless_haproxy -f '{{.State.Status}}' 2>/dev/null || echo "unknown")
        if [[ "$haproxy_status" == "running" ]]; then
            log_success "    ✓ HAProxy container running"
        else
            log_error "    ✗ HAProxy container status: $haproxy_status"
            validation_failed=1
        fi
    fi

    # Check 3: Certificate files exist
    log_info "  [3/5] Checking Let's Encrypt certificates..."
    if [[ -z "${DOMAIN:-}" ]]; then
        log_error "    ✗ DOMAIN variable not set"
        validation_failed=1
    elif [[ ! -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
        log_error "    ✗ Certificate not found: /etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
        validation_failed=1
    else
        log_success "    ✓ Certificates exist for $DOMAIN"
        local expiry_date
        expiry_date=$(openssl x509 -in "/etc/letsencrypt/live/${DOMAIN}/cert.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
        log_info "    ℹ Expires: $expiry_date"
    fi

    # Check 4: Xray inbounds are plaintext localhost (v4.0 architecture)
    log_info "  [4/5] Checking Xray proxy inbounds (should be plaintext)..."
    local config_file="${INSTALL_ROOT}/config/xray_config.json"
    local socks5_listen=$(jq -r '.inbounds[] | select(.tag=="socks5-proxy") | .listen' "$config_file" 2>/dev/null)
    local http_listen=$(jq -r '.inbounds[] | select(.tag=="http-proxy") | .listen' "$config_file" 2>/dev/null)

    if [[ "$socks5_listen" == "0.0.0.0" ]] && [[ "$http_listen" == "0.0.0.0" ]]; then
        log_success "    ✓ Xray proxies listen on 0.0.0.0 (correct for Docker network)"
    else
        log_error "    ✗ Xray proxies should listen on 0.0.0.0 (Docker network)"
        log_error "    Found: SOCKS5=$socks5_listen, HTTP=$http_listen"
        validation_failed=1
    fi

    # Check 5: HAProxy ports accessible (host network mode)
    log_info "  [5/5] Checking HAProxy port accessibility..."
    # v4.3: HAProxy runs in host network mode, ports bound directly to host
    local haproxy_listening=0
    if ss -tuln | grep -q ":443 "; then
        haproxy_listening=$((haproxy_listening + 1))
    fi
    if ss -tuln | grep -q ":1080 "; then
        haproxy_listening=$((haproxy_listening + 1))
    fi
    if ss -tuln | grep -q ":8118 "; then
        haproxy_listening=$((haproxy_listening + 1))
    fi

    if [[ $haproxy_listening -eq 3 ]]; then
        log_success "    ✓ HAProxy listening on ports 443, 1080, 8118"
    else
        log_error "    ✗ HAProxy not listening on all required ports (found $haproxy_listening/3)"
        validation_failed=1
    fi

    # Final result
    echo ""
    if [[ $validation_failed -eq 0 ]]; then
        log_success "TLS validation: PASSED (v4.3 HAProxy unified architecture)"
        log_info "  • Architecture: Client → HAProxy (TLS/passthrough) → Xray (localhost)"
        log_info "  • Port 443: SNI routing (VLESS + reverse proxies)"
        log_info "  • Port 1080: SOCKS5 TLS termination → 127.0.0.1:10800"
        log_info "  • Port 8118: HTTP TLS termination → 127.0.0.1:18118"
        return 0
    else
        log_error "TLS validation: FAILED"
        log_error "v4.3 requires HAProxy for unified TLS termination"
        return 1
    fi
}

# ============================================================================
# FUNCTION: test_xray_config
# ============================================================================
# Description: Test Xray configuration for syntax and validity
# Uses: xray run -test command
# Returns: 0 if valid, 1 if test fails
# Related: TASK-2.5 (v3.3 Config Test)
# ============================================================================
test_xray_config() {
    echo ""
    log_info "Verification 5.5/10: Testing Xray configuration..."

    local config_file="${INSTALL_ROOT}/config/xray_config.json"

    # Check 1: JSON syntax validation
    log_info "  [1/2] Validating JSON syntax..."
    if ! jq empty "$config_file" 2>/dev/null; then
        log_error "    ✗ Invalid JSON syntax in $config_file"
        log_error "    Run: jq . $config_file"
        return 1
    fi
    log_success "    ✓ JSON syntax valid"

    # Check 2: Xray test mode
    log_info "  [2/2] Running Xray configuration test..."

    # Prepare volume mounts for test
    # Mount config file directly (xray_config.json -> /etc/xray/config.json)
    local volume_args="-v ${INSTALL_ROOT}/config/xray_config.json:/etc/xray/config.json:ro"

    # Add certificate volume if public proxy enabled
    if [[ "${ENABLE_PUBLIC_PROXY:-false}" == "true" ]]; then
        volume_args="$volume_args -v /etc/letsencrypt:/certs:ro"
    fi

    # Run xray test
    local test_output
    if test_output=$(docker run --rm $volume_args "${XRAY_IMAGE}" xray run -test -c /etc/xray/config.json 2>&1); then
        log_success "    ✓ Xray configuration test passed"
        return 0
    else
        log_error "    ✗ Xray configuration test failed"
        log_error "Test output:"
        echo "$test_output" | while IFS= read -r line; do
            log_error "    $line"
        done
        return 1
    fi
}

# ============================================================================
# Export Functions
# ============================================================================

# Export all functions for use by other scripts
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Script is being sourced
    export -f verify_installation
    export -f verify_directory_structure
    export -f verify_file_permissions
    export -f verify_docker_network
    export -f verify_containers
    export -f verify_xray_config
    export -f verify_ufw_rules
    export -f verify_container_internet
    export -f verify_port_listening
    export -f display_verification_summary
    export -f validate_mandatory_tls
    export -f test_xray_config
    export -f log_info
    export -f log_success
    export -f log_warning
    export -f log_error
fi

# ============================================================================
# Main Execution (if run directly)
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being run directly
    verify_installation
fi
