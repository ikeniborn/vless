#!/bin/bash
################################################################################
# VLESS Reality VPN - Fail2ban Setup Module
#
# Description:
#   Installs and configures fail2ban to protect SOCKS5 and HTTP proxy ports
#   from brute-force authentication attacks.
#
# Requirements:
#   - Ubuntu 20.04+ or Debian 10+
#   - Root privileges
#   - Xray error logs at /opt/vless/logs/xray/error.log
#
# Features:
#   - Auto-install fail2ban if missing
#   - Create custom filter for Xray authentication failures
#   - Configure jails for SOCKS5 (1080) and HTTP (8118)
#   - Ban after 5 failed attempts for 1 hour
#
# Version: 3.2
# Date: 2025-10-04
################################################################################

set -euo pipefail

# Import colors (if available)
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/colors.sh" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'
fi

# =============================================================================
# FUNCTION: check_fail2ban_installed
# =============================================================================
# Description: Check if fail2ban is installed
# Returns: 0 if installed, 1 if not installed
# =============================================================================
check_fail2ban_installed() {
    if command -v fail2ban-server &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# FUNCTION: install_fail2ban
# =============================================================================
# Description: Install fail2ban package
# Returns: 0 on success, 1 on failure
# =============================================================================
install_fail2ban() {
    echo -e "${CYAN}Installing fail2ban...${NC}"

    # Update package list
    if ! apt-get update -qq; then
        echo -e "${RED}Failed to update package list${NC}" >&2
        return 1
    fi

    # Install fail2ban
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -qq fail2ban; then
        echo -e "${RED}Failed to install fail2ban${NC}" >&2
        return 1
    fi

    # Enable and start service
    systemctl enable fail2ban &>/dev/null || true
    systemctl start fail2ban || true

    echo -e "${GREEN}✓ Fail2ban installed${NC}"
    return 0
}

# =============================================================================
# FUNCTION: create_vless_proxy_filter
# =============================================================================
# Description: Create custom fail2ban filter for Xray proxy authentication
# Returns: 0 on success, 1 on failure
# =============================================================================
create_vless_proxy_filter() {
    echo -e "${CYAN}Creating fail2ban filter for VLESS proxy...${NC}"

    local filter_file="/etc/fail2ban/filter.d/vless-proxy.conf"

    cat > "$filter_file" <<'EOF'
# Fail2ban filter for VLESS Reality Proxy (SOCKS5 + HTTP)
#
# Matches Xray authentication failure patterns in error logs
#
# Author: VLESS Reality VPN v3.2
# Date: 2025-10-04

[Definition]

# Match authentication failures in Xray logs
failregex = ^.* rejected .* from <HOST>.*$
            ^.* authentication failed .* from <HOST>.*$
            ^.* invalid credentials .* from <HOST>.*$
            ^.* proxy: failed to .* from <HOST>.*$

# Ignore successful connections
ignoreregex = ^.* accepted .* from .*$
              ^.* established .* from .*$
EOF

    if [[ ! -f "$filter_file" ]]; then
        echo -e "${RED}Failed to create filter file${NC}" >&2
        return 1
    fi

    chmod 644 "$filter_file"
    echo -e "${GREEN}✓ Filter created: $filter_file${NC}"
    return 0
}

# =============================================================================
# FUNCTION: create_vless_proxy_jails
# =============================================================================
# Description: Create fail2ban jails for SOCKS5 and HTTP proxy
# Returns: 0 on success, 1 on failure
# =============================================================================
create_vless_proxy_jails() {
    echo -e "${CYAN}Creating fail2ban jails for proxy ports...${NC}"

    local jail_file="/etc/fail2ban/jail.d/vless-proxy.conf"

    cat > "$jail_file" <<'EOF'
# Fail2ban jails for VLESS Reality Proxy
#
# Protects SOCKS5 (1080) and HTTP (8118) proxy ports from brute-force attacks
#
# Configuration:
#   - maxretry: 5 failed attempts
#   - bantime: 3600 seconds (1 hour)
#   - findtime: 600 seconds (10 minutes)
#
# Author: VLESS Reality VPN v3.2
# Date: 2025-10-04

[vless-socks5]
enabled  = true
port     = 1080
protocol = tcp
filter   = vless-proxy
logpath  = /opt/vless/logs/xray/error.log
maxretry = 5
bantime  = 3600
findtime = 600
action   = iptables-multiport[name=vless-socks5, port="1080", protocol=tcp]

[vless-http]
enabled  = true
port     = 8118
protocol = tcp
filter   = vless-proxy
logpath  = /opt/vless/logs/xray/error.log
maxretry = 5
bantime  = 3600
findtime = 600
action   = iptables-multiport[name=vless-http, port="8118", protocol=tcp]
EOF

    if [[ ! -f "$jail_file" ]]; then
        echo -e "${RED}Failed to create jail file${NC}" >&2
        return 1
    fi

    chmod 644 "$jail_file"
    echo -e "${GREEN}✓ Jails created: $jail_file${NC}"
    return 0
}

# =============================================================================
# FUNCTION: reload_fail2ban
# =============================================================================
# Description: Reload fail2ban to apply new configuration
# Returns: 0 on success, 1 on failure
# =============================================================================
reload_fail2ban() {
    echo -e "${CYAN}Reloading fail2ban...${NC}"

    if ! systemctl reload fail2ban; then
        echo -e "${YELLOW}Reload failed, trying restart...${NC}"
        if ! systemctl restart fail2ban; then
            echo -e "${RED}Failed to restart fail2ban${NC}" >&2
            return 1
        fi
    fi

    # Wait for service to stabilize
    sleep 2

    echo -e "${GREEN}✓ Fail2ban reloaded${NC}"
    return 0
}

# =============================================================================
# FUNCTION: verify_fail2ban_jails
# =============================================================================
# Description: Verify that VLESS proxy jails are active
# Returns: 0 if both jails active, 1 if any jail inactive
# =============================================================================
verify_fail2ban_jails() {
    echo -e "${CYAN}Verifying fail2ban jails...${NC}"

    local socks5_status
    local http_status

    socks5_status=$(fail2ban-client status vless-socks5 2>/dev/null || echo "FAIL")
    http_status=$(fail2ban-client status vless-http 2>/dev/null || echo "FAIL")

    if [[ "$socks5_status" == "FAIL" ]]; then
        echo -e "${RED}✗ SOCKS5 jail not active${NC}"
        return 1
    fi

    if [[ "$http_status" == "FAIL" ]]; then
        echo -e "${RED}✗ HTTP jail not active${NC}"
        return 1
    fi

    echo -e "${GREEN}✓ Both jails active (vless-socks5, vless-http)${NC}"
    return 0
}

# =============================================================================
# FUNCTION: setup_fail2ban_for_proxy
# =============================================================================
# Description: Main entry point - complete fail2ban setup for VLESS proxy
# Returns: 0 on success, 1 on failure
# =============================================================================
setup_fail2ban_for_proxy() {
    echo ""
    echo "═════════════════════════════════════════════════════"
    echo "  FAIL2BAN SETUP (v3.2 - Public Proxy Protection)"
    echo "═════════════════════════════════════════════════════"
    echo ""

    # Check if fail2ban is installed
    if ! check_fail2ban_installed; then
        echo -e "${YELLOW}Fail2ban not found, installing...${NC}"
        if ! install_fail2ban; then
            echo -e "${RED}Failed to install fail2ban${NC}" >&2
            return 1
        fi
    else
        echo -e "${GREEN}✓ Fail2ban already installed${NC}"
    fi

    # Create filter
    if ! create_vless_proxy_filter; then
        return 1
    fi

    # Create jails
    if ! create_vless_proxy_jails; then
        return 1
    fi

    # Reload fail2ban
    if ! reload_fail2ban; then
        return 1
    fi

    # Verify jails
    if ! verify_fail2ban_jails; then
        echo -e "${YELLOW}Warning: Jails verification failed${NC}"
        echo -e "${YELLOW}Check fail2ban logs: journalctl -u fail2ban -n 50${NC}"
    fi

    echo ""
    echo -e "${GREEN}✓ Fail2ban setup complete${NC}"
    echo ""
    echo "Configuration:"
    echo "  - SOCKS5 jail active (port 1080)"
    echo "  - HTTP jail active (port 8118)"
    echo "  - Max retries: 5"
    echo "  - Ban time: 3600 seconds (1 hour)"
    echo "  - Find time: 600 seconds (10 minutes)"
    echo ""
    echo "Monitor banned IPs:"
    echo "  sudo fail2ban-client status vless-socks5"
    echo "  sudo fail2ban-client status vless-http"
    echo "═════════════════════════════════════════════════════"
    echo ""

    return 0
}

# Export functions for use in other modules
export -f check_fail2ban_installed
export -f install_fail2ban
export -f create_vless_proxy_filter
export -f create_vless_proxy_jails
export -f reload_fail2ban
export -f verify_fail2ban_jails
export -f setup_fail2ban_for_proxy
