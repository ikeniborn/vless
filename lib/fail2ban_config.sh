#!/bin/bash
# lib/fail2ban_config.sh
#
# fail2ban Configuration for VLESS (v4.3 with HAProxy Protection)
# Provides brute-force protection for reverse proxy and HAProxy endpoints
#
# Features:
# - Nginx reverse proxy protection (9443-9452)
# - HAProxy protection (443, 1080, 8118) - NEW in v4.3
# - Auth failure detection (HTTP Basic Auth)
# - Invalid SNI / TLS handshake failure detection
# - Rate limit violation detection
# - UFW ban action (1 hour default)
# - Dynamic port management
#
# Version: 4.3.0
# Author: VLESS Development Team
# Date: 2025-10-18

set -euo pipefail

# Configuration
FAIL2BAN_JAIL_DIR="/etc/fail2ban/jail.d"
FAIL2BAN_FILTER_DIR="/etc/fail2ban/filter.d"
NGINX_ERROR_LOG="/opt/vless/logs/nginx/reverse-proxy-error.log"
HAPROXY_LOG="/opt/vless/logs/haproxy/haproxy.log"  # v4.3 NEW

# fail2ban settings
JAIL_NAME="vless-reverseproxy"
HAPROXY_JAIL_NAME="vless-haproxy"  # v4.3 NEW
MAXRETRY=5
BANTIME=3600  # 1 hour
FINDTIME=600   # 10 minutes

# Logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [fail2ban-config] $*" >&2
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [fail2ban-config] ERROR: $*" >&2
}

# ============================================================================
# Function: install_fail2ban
# Description: Installs fail2ban if not present
#
# Returns:
#   0 on success, 1 on failure
# ============================================================================
install_fail2ban() {
    if command -v fail2ban-server &> /dev/null; then
        log "fail2ban is already installed"
        return 0
    fi

    log "Installing fail2ban..."

    if sudo apt-get update && sudo apt-get install -y fail2ban; then
        log "✅ fail2ban installed successfully"
        return 0
    else
        log_error "Failed to install fail2ban"
        return 1
    fi
}

# ============================================================================
# Function: create_reverseproxy_filter
# Description: Creates fail2ban filter for reverse proxy auth failures
#
# Returns:
#   0 on success, 1 on failure
# ============================================================================
create_reverseproxy_filter() {
    local filter_file="${FAIL2BAN_FILTER_DIR}/vless-reverseproxy.conf"

    log "Creating fail2ban filter: $filter_file"

    sudo tee "$filter_file" > /dev/null <<'EOF'
# fail2ban filter for VLESS Reverse Proxy
# Detects HTTP Basic Auth failures and rate limit violations
#
# Author: VLESS Development Team
# Version: 4.2.0

[Definition]

# Auth failure patterns
failregex = ^ .* user .* was not found in ".*", client: <HOST>, server: .*$
            ^ .* user .* password mismatch, client: <HOST>, server: .*$
            ^ .* no user/password was provided for basic authentication, client: <HOST>, server: .*$

# Ignore patterns (optional)
ignoreregex =

# Date pattern (nginx default)
datepattern = {^LN-BEG}
EOF

    if [ $? -eq 0 ]; then
        log "✅ Filter created: $filter_file"
        return 0
    else
        log_error "Failed to create filter"
        return 1
    fi
}

# ============================================================================
# Function: create_ratelimit_filter
# Description: Creates fail2ban filter for rate limit violations
#
# Returns:
#   0 on success, 1 on failure
# ============================================================================
create_ratelimit_filter() {
    local filter_file="${FAIL2BAN_FILTER_DIR}/vless-reverseproxy-ratelimit.conf"

    log "Creating rate limit filter: $filter_file"

    sudo tee "$filter_file" > /dev/null <<'EOF'
# fail2ban filter for VLESS Reverse Proxy Rate Limit Violations
#
# Author: VLESS Development Team
# Version: 4.2.0

[Definition]

# Rate limit patterns (nginx limit_req and limit_conn)
failregex = ^ .* limiting requests, excess: .* by zone ".*", client: <HOST>.*$
            ^ .* limiting connections by zone ".*", client: <HOST>.*$

ignoreregex =

datepattern = {^LN-BEG}
EOF

    if [ $? -eq 0 ]; then
        log "✅ Rate limit filter created: $filter_file"
        return 0
    else
        log_error "Failed to create rate limit filter"
        return 1
    fi
}

# ============================================================================
# Function: setup_reverseproxy_jail
# Description: Creates and configures fail2ban jail for reverse proxy
#
# Parameters:
#   $1 - ports: Comma-separated list of ports (e.g., "9443,9444,9445", v4.3 range: 9443-9452)
#
# Returns:
#   0 on success, 1 on failure
# ============================================================================
setup_reverseproxy_jail() {
    local ports="${1:-9443}"

    local jail_file="${FAIL2BAN_JAIL_DIR}/vless-reverseproxy.conf"

    log "Creating fail2ban jail: $jail_file"
    log "Protected ports: $ports"

    sudo tee "$jail_file" > /dev/null <<EOF
# fail2ban jail for VLESS Reverse Proxy
# Protects against brute-force attacks on HTTP Basic Auth
#
# Author: VLESS Development Team
# Version: 4.2.0

[vless-reverseproxy]
enabled = true
port = ${ports}
filter = vless-reverseproxy
logpath = ${NGINX_ERROR_LOG}
maxretry = ${MAXRETRY}
bantime = ${BANTIME}
findtime = ${FINDTIME}
action = ufw

[vless-reverseproxy-ratelimit]
enabled = true
port = ${ports}
filter = vless-reverseproxy-ratelimit
logpath = ${NGINX_ERROR_LOG}
maxretry = 10
bantime = ${BANTIME}
findtime = 60
action = ufw
EOF

    if [ $? -eq 0 ]; then
        log "✅ Jail created: $jail_file"
        log "   maxretry: $MAXRETRY failures"
        log "   bantime: $BANTIME seconds ($(($BANTIME / 60)) minutes)"
        log "   findtime: $FINDTIME seconds ($(($FINDTIME / 60)) minutes)"
        return 0
    else
        log_error "Failed to create jail"
        return 1
    fi
}

# ============================================================================
# Function: add_port_to_jail
# Description: Adds port to existing jail configuration
#
# Parameters:
#   $1 - port: Port number to add
#
# Returns:
#   0 on success, 1 on failure
# ============================================================================
add_port_to_jail() {
    local new_port="$1"

    if [[ -z "$new_port" ]]; then
        log_error "Missing port parameter"
        return 1
    fi

    local jail_file="${FAIL2BAN_JAIL_DIR}/vless-reverseproxy.conf"

    if [ ! -f "$jail_file" ]; then
        log_error "Jail file not found: $jail_file"
        return 1
    fi

    # Get current ports
    local current_ports
    current_ports=$(sudo grep "^port = " "$jail_file" | head -1 | cut -d= -f2 | xargs)

    # Check if port already exists
    if echo "$current_ports" | grep -qw "$new_port"; then
        log "Port $new_port already in jail configuration"
        return 0
    fi

    log "Adding port $new_port to jail (current: $current_ports)"

    # Add port (handle empty list - first proxy after removal)
    local new_ports
    if [[ -z "$current_ports" ]]; then
        new_ports="$new_port"
        log "ℹ️ First reverse proxy, re-enabling fail2ban jail"
        # Re-enable jail if it was disabled
        sudo sed -i 's/^enabled  = false/enabled  = true/' "$jail_file"
    else
        new_ports="${current_ports},${new_port}"
    fi

    # Update both jail sections
    sudo sed -i "s/^port = .*/port = ${new_ports}/" "$jail_file"

    log "✅ Port $new_port added to jail"

    return 0
}

# ============================================================================
# Function: remove_port_from_jail
# Description: Removes port from jail configuration
#
# Parameters:
#   $1 - port: Port number to remove
#
# Returns:
#   0 on success, 1 on failure
# ============================================================================
remove_port_from_jail() {
    local port_to_remove="$1"

    if [[ -z "$port_to_remove" ]]; then
        log_error "Missing port parameter"
        return 1
    fi

    local jail_file="${FAIL2BAN_JAIL_DIR}/vless-reverseproxy.conf"

    if [ ! -f "$jail_file" ]; then
        log_error "Jail file not found: $jail_file"
        return 1
    fi

    # Get current ports
    local current_ports
    current_ports=$(sudo grep "^port = " "$jail_file" | head -1 | cut -d= -f2 | xargs)

    # Remove port from list
    local new_ports
    new_ports=$(echo "$current_ports" | tr ',' '\n' | grep -v "^${port_to_remove}$" | paste -sd, -)

    log "Removing port $port_to_remove from jail (current: $current_ports)"

    if [[ -z "$new_ports" ]]; then
        log "ℹ️ No ports left after removal, disabling fail2ban jail"
        # Disable jail instead of adding dummy port
        sudo sed -i 's/^enabled  = true/enabled  = false/' "$jail_file"
        # Clear port line (set to empty or placeholder)
        sudo sed -i 's/^port = .*/port = /' "$jail_file"
        log "✅ fail2ban jail disabled (no active reverse proxies)"
        return 0
    fi

    # Update both jail sections
    sudo sed -i "s/^port = .*/port = ${new_ports}/" "$jail_file"

    log "✅ Port $port_to_remove removed from jail (new: $new_ports)"

    return 0
}

# ============================================================================
# Function: reload_fail2ban
# Description: Reloads fail2ban configuration
#
# Returns:
#   0 on success, 1 on failure
# ============================================================================
reload_fail2ban() {
    log "Reloading fail2ban..."

    if sudo fail2ban-client reload 2>&1; then
        log "✅ fail2ban reloaded successfully"
        return 0
    else
        log_error "Failed to reload fail2ban"
        return 1
    fi
}

# ============================================================================
# Function: check_jail_status
# Description: Checks status of reverse proxy jail
#
# Returns:
#   Jail status information
# ============================================================================
check_jail_status() {
    log "Checking jail status: $JAIL_NAME"

    if sudo fail2ban-client status "$JAIL_NAME" 2>/dev/null; then
        return 0
    else
        log_error "Jail not found or fail2ban not running"
        return 1
    fi
}

# ============================================================================
# Function: unban_ip
# Description: Unbans IP address
#
# Parameters:
#   $1 - ip: IP address to unban
#
# Returns:
#   0 on success, 1 on failure
# ============================================================================
unban_ip() {
    local ip="$1"

    if [[ -z "$ip" ]]; then
        log_error "Missing IP parameter"
        return 1
    fi

    log "Unbanning IP: $ip"

    if sudo fail2ban-client unban "$ip" 2>&1; then
        log "✅ IP unbanned: $ip"
        return 0
    else
        log_error "Failed to unban IP: $ip"
        return 1
    fi
}

# ============================================================================
# Function: create_haproxy_filter
# Description: Creates fail2ban filter for HAProxy SNI abuse detection (v4.3)
#
# Returns:
#   0 on success, 1 on failure
# ============================================================================
create_haproxy_filter() {
    local filter_file="${FAIL2BAN_FILTER_DIR}/haproxy-sni.conf"

    log "Creating HAProxy fail2ban filter: $filter_file"

    sudo tee "$filter_file" > /dev/null <<'EOF'
# fail2ban filter for VLESS HAProxy SNI Abuse Detection
# Detects invalid SNI requests, TLS handshake failures, and connection abuse
#
# Author: VLESS Development Team
# Version: 4.3.0

[Definition]

# Invalid SNI patterns (SNI mismatch, unknown domains)
failregex = ^.*<HOST>.*SSL handshake failure.*$
            ^.*<HOST>.*SNI:.*backend not found.*$
            ^.*<HOST>.*no server available.*$
            ^.*<HOST>.*connection refused.*$

# Ignore patterns (optional)
ignoreregex =

# Date pattern (HAProxy syslog format)
datepattern = {^LN-BEG}
EOF

    if [ $? -eq 0 ]; then
        log "✅ HAProxy filter created: $filter_file"
        return 0
    else
        log_error "Failed to create HAProxy filter"
        return 1
    fi
}

# ============================================================================
# Function: setup_haproxy_jail
# Description: Creates and configures fail2ban jail for HAProxy (v4.3)
#
# Returns:
#   0 on success, 1 on failure
# ============================================================================
setup_haproxy_jail() {
    local jail_file="${FAIL2BAN_JAIL_DIR}/vless-haproxy.conf"

    log "Creating HAProxy fail2ban jail: $jail_file"

    sudo tee "$jail_file" > /dev/null <<EOF
# fail2ban jail for VLESS HAProxy v4.3
# Protects against SNI abuse and TLS handshake attacks
#
# Author: VLESS Development Team
# Version: 4.3.0

[vless-haproxy]
enabled = true
port = 443,1080,8118
filter = haproxy-sni
logpath = ${HAPROXY_LOG}
maxretry = ${MAXRETRY}
bantime = ${BANTIME}
findtime = ${FINDTIME}
action = ufw
EOF

    if [ $? -eq 0 ]; then
        log "✅ HAProxy jail created: $jail_file"
        log "   Protected ports: 443 (VLESS), 1080 (SOCKS5), 8118 (HTTP)"
        log "   maxretry: $MAXRETRY failures"
        log "   bantime: $BANTIME seconds ($(($BANTIME / 60)) minutes)"
        log "   findtime: $FINDTIME seconds ($(($FINDTIME / 60)) minutes)"
        return 0
    else
        log_error "Failed to create HAProxy jail"
        return 1
    fi
}

# ============================================================================
# Function: check_haproxy_jail_status
# Description: Checks status of HAProxy jail (v4.3)
#
# Returns:
#   Jail status information
# ============================================================================
check_haproxy_jail_status() {
    log "Checking HAProxy jail status: $HAPROXY_JAIL_NAME"

    if sudo fail2ban-client status "$HAPROXY_JAIL_NAME" 2>/dev/null; then
        return 0
    else
        log_error "HAProxy jail not found or fail2ban not running"
        return 1
    fi
}

# ============================================================================
# Function: setup_haproxy_fail2ban
# Description: Complete setup of fail2ban for HAProxy (v4.3)
#
# Returns:
#   0 on success, 1 on failure
# ============================================================================
setup_haproxy_fail2ban() {
    log "Setting up fail2ban for HAProxy v4.3..."

    # Install fail2ban if needed
    if ! install_fail2ban; then
        return 1
    fi

    # Create HAProxy filter
    if ! create_haproxy_filter; then
        return 1
    fi

    # Create HAProxy jail
    if ! setup_haproxy_jail; then
        return 1
    fi

    # Reload fail2ban
    if ! reload_fail2ban; then
        return 1
    fi

    # Check jail status
    sleep 2  # Give fail2ban time to load jail
    check_haproxy_jail_status

    log "✅ fail2ban setup completed for HAProxy"
    log "   Protected services: VLESS Reality (443), SOCKS5 (1080), HTTP (8118)"
    log "   Ban policy: $MAXRETRY failures in $FINDTIME seconds → ban for $BANTIME seconds"

    return 0
}

# ============================================================================
# Function: setup_reverseproxy_fail2ban
# Description: Complete setup of fail2ban for reverse proxy
#
# Parameters:
#   $1 - ports: Comma-separated list of ports (optional, default: 9443)
#
# Returns:
#   0 on success, 1 on failure
# ============================================================================
setup_reverseproxy_fail2ban() {
    local ports="${1:-9443}"

    log "Setting up fail2ban for reverse proxy..."

    # Install fail2ban if needed
    if ! install_fail2ban; then
        return 1
    fi

    # Create filters
    if ! create_reverseproxy_filter; then
        return 1
    fi

    if ! create_ratelimit_filter; then
        return 1
    fi

    # Create jail
    if ! setup_reverseproxy_jail "$ports"; then
        return 1
    fi

    # Reload fail2ban
    if ! reload_fail2ban; then
        return 1
    fi

    # Check jail status
    sleep 2  # Give fail2ban time to load jail
    check_jail_status

    log "✅ fail2ban setup completed for reverse proxy"
    log "   Protected ports: $ports"
    log "   Ban policy: $MAXRETRY failures in $FINDTIME seconds → ban for $BANTIME seconds"

    return 0
}

# ============================================================================
# Main execution (for testing)
# ============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly (not sourced)

    if [ $# -lt 1 ]; then
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  setup [ports]           - Complete setup for reverse proxy (default: 9443)"
        echo "  setup-haproxy           - Complete setup for HAProxy v4.3"
        echo "  add-port <port>         - Add port to reverse proxy jail"
        echo "  remove-port <port>      - Remove port from reverse proxy jail"
        echo "  reload                  - Reload fail2ban"
        echo "  status                  - Check reverse proxy jail status"
        echo "  status-haproxy          - Check HAProxy jail status"
        echo "  unban <ip>              - Unban IP address"
        exit 1
    fi

    command="$1"
    shift

    case "$command" in
        setup)
            setup_reverseproxy_fail2ban "$@"
            ;;
        setup-haproxy)
            setup_haproxy_fail2ban
            ;;
        add-port)
            add_port_to_jail "$@" && reload_fail2ban
            ;;
        remove-port)
            remove_port_from_jail "$@" && reload_fail2ban
            ;;
        reload)
            reload_fail2ban
            ;;
        status)
            check_jail_status
            ;;
        status-haproxy)
            check_haproxy_jail_status
            ;;
        unban)
            unban_ip "$@"
            ;;
        *)
            log_error "Unknown command: $command"
            exit 1
            ;;
    esac
fi
