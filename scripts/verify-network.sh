#!/bin/bash
#
# verify-network.sh - Network Configuration Verification Script
#
# Проверяет корректность сетевой конфигурации для VLESS VPN сервиса:
# - IP forwarding
# - NAT rules в iptables
# - NAT rules в UFW before.rules
# - FORWARD chain rules
# - Docker network конфигурация
#
# Usage:
#   sudo ./verify-network.sh
#   sudo bash verify-network.sh
#

set -e

# Определение рабочего каталога
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VLESS_HOME="${VLESS_HOME:-/opt/vless}"

# Load library functions
if [ -f "$SCRIPT_DIR/lib/colors.sh" ]; then
    source "$SCRIPT_DIR/lib/colors.sh"
elif [ -f "$VLESS_HOME/scripts/lib/colors.sh" ]; then
    source "$VLESS_HOME/scripts/lib/colors.sh"
else
    # Fallback: define basic color functions
    print_header() { echo "=== $1 ==="; }
    print_step() { echo "→ $1"; }
    print_success() { echo "✓ $1"; }
    print_error() { echo "✗ $1"; }
    print_warning() { echo "⚠ $1"; }
    print_info() { echo "ℹ $1"; }
fi

if [ -f "$SCRIPT_DIR/lib/utils.sh" ]; then
    source "$SCRIPT_DIR/lib/utils.sh"
elif [ -f "$VLESS_HOME/scripts/lib/utils.sh" ]; then
    source "$VLESS_HOME/scripts/lib/utils.sh"
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root"
    echo "Usage: sudo $0"
    exit 1
fi

# Global variables for tracking issues
ISSUES_FOUND=0
WARNINGS_FOUND=0

# Load environment variables if available
if [ -f "$VLESS_HOME/.env" ]; then
    set -a
    source "$VLESS_HOME/.env"
    set +a
fi

# Get Docker subnet from env or use default
DOCKER_SUBNET="${DOCKER_SUBNET:-172.19.0.0/16}"
SERVER_PORT="${SERVER_PORT:-443}"

print_header "VLESS VPN Network Configuration Verification"
echo ""

# ============================================================================
# 1. Check IP Forwarding
# ============================================================================
print_step "Checking IP forwarding..."
IP_FORWARD=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")

if [ "$IP_FORWARD" = "1" ]; then
    print_success "IP forwarding is enabled (net.ipv4.ip_forward = 1)"
else
    print_error "IP forwarding is DISABLED (net.ipv4.ip_forward = $IP_FORWARD)"
    print_info "Run: sudo sysctl -w net.ipv4.ip_forward=1"
    print_info "To persist: echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Check if IP forwarding is persistent
if grep -q "^net.ipv4.ip_forward\s*=\s*1" /etc/sysctl.conf 2>/dev/null; then
    print_success "IP forwarding is persistent in /etc/sysctl.conf"
else
    print_warning "IP forwarding may not be persistent after reboot"
    print_info "Add to /etc/sysctl.conf: net.ipv4.ip_forward = 1"
    WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
fi

echo ""

# ============================================================================
# 2. Check NAT rules in iptables
# ============================================================================
print_step "Checking NAT MASQUERADE rules in iptables..."

# Extract network part from CIDR for grep
SUBNET_PATTERN=$(echo "$DOCKER_SUBNET" | sed 's/\./\\./g')

if iptables -t nat -L POSTROUTING -n | grep -q "MASQUERADE.*${SUBNET_PATTERN}"; then
    NAT_COUNT=$(iptables -t nat -L POSTROUTING -n | grep -c "MASQUERADE.*${SUBNET_PATTERN}" || echo "0")
    print_success "NAT MASQUERADE rule found for $DOCKER_SUBNET ($NAT_COUNT rule(s))"

    # Show the rules
    print_info "NAT rules for Docker subnet:"
    iptables -t nat -L POSTROUTING -n -v | grep "$DOCKER_SUBNET" | while read line; do
        echo "  $line"
    done
else
    print_error "NAT MASQUERADE rule NOT found for $DOCKER_SUBNET"
    print_info "Run: sudo iptables -t nat -A POSTROUTING -s $DOCKER_SUBNET -o \$(ip route | grep default | awk '{print \$5}') -j MASQUERADE"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

echo ""

# ============================================================================
# 3. Check FORWARD chain rules
# ============================================================================
print_step "Checking FORWARD chain rules..."

if iptables -L FORWARD -n | grep -q "$DOCKER_SUBNET"; then
    FORWARD_COUNT=$(iptables -L FORWARD -n | grep -c "$DOCKER_SUBNET" || echo "0")
    print_success "FORWARD rules found for $DOCKER_SUBNET ($FORWARD_COUNT rule(s))"
else
    print_warning "FORWARD rules NOT found for $DOCKER_SUBNET"
    print_info "This may be handled by Docker automatically"
    WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
fi

echo ""

# ============================================================================
# 4. Check UFW configuration
# ============================================================================
print_step "Checking UFW firewall configuration..."

if command -v ufw >/dev/null 2>&1; then
    UFW_STATUS=$(ufw status 2>/dev/null | head -1)

    if echo "$UFW_STATUS" | grep -q "inactive"; then
        print_info "UFW is installed but inactive"
    elif echo "$UFW_STATUS" | grep -q "active"; then
        print_success "UFW is active"

        # Check DEFAULT_FORWARD_POLICY
        if [ -f "/etc/default/ufw" ]; then
            FORWARD_POLICY=$(grep "^DEFAULT_FORWARD_POLICY=" /etc/default/ufw | cut -d'"' -f2)

            if [ "$FORWARD_POLICY" = "ACCEPT" ]; then
                print_success "UFW DEFAULT_FORWARD_POLICY is set to ACCEPT"
            else
                print_error "UFW DEFAULT_FORWARD_POLICY is set to $FORWARD_POLICY (should be ACCEPT)"
                print_info "Edit /etc/default/ufw and set: DEFAULT_FORWARD_POLICY=\"ACCEPT\""
                ISSUES_FOUND=$((ISSUES_FOUND + 1))
            fi
        fi

        # Check NAT rules in before.rules
        if [ -f "/etc/ufw/before.rules" ]; then
            if grep -q "# NAT table rules for Docker" /etc/ufw/before.rules; then
                print_success "NAT rules found in /etc/ufw/before.rules"

                # Verify the specific subnet is in the rules
                if grep -q "$DOCKER_SUBNET" /etc/ufw/before.rules; then
                    print_success "Docker subnet $DOCKER_SUBNET found in UFW NAT rules"
                else
                    print_warning "Docker subnet $DOCKER_SUBNET NOT found in UFW NAT rules"
                    print_info "UFW NAT rules may be for a different subnet"
                    WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
                fi
            else
                print_error "NAT rules NOT found in /etc/ufw/before.rules"
                print_info "UFW is blocking Docker traffic forwarding"
                print_info "Run: sudo bash -c 'source $SCRIPT_DIR/lib/colors.sh $SCRIPT_DIR/lib/utils.sh $SCRIPT_DIR/lib/network.sh && configure_ufw_for_docker \"$DOCKER_SUBNET\" \"$SERVER_PORT\"'"
                ISSUES_FOUND=$((ISSUES_FOUND + 1))
            fi
        fi

        # Check UFW rule for server port
        if ufw status numbered | grep -q "$SERVER_PORT/tcp"; then
            print_success "UFW rule found for port $SERVER_PORT/tcp"
        else
            print_warning "UFW rule NOT found for port $SERVER_PORT/tcp"
            print_info "Run: sudo ufw allow $SERVER_PORT/tcp comment 'VLESS VPN Service'"
            WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
        fi
    fi
else
    print_info "UFW is not installed (using iptables only)"
fi

echo ""

# ============================================================================
# 5. Check Docker network configuration
# ============================================================================
print_step "Checking Docker network configuration..."

if command -v docker >/dev/null 2>&1; then
    # Check if vless network exists
    if docker network ls | grep -q "vless-reality_vless-network"; then
        print_success "Docker network 'vless-reality_vless-network' exists"

        # Get network details
        NETWORK_SUBNET=$(docker network inspect vless-reality_vless-network 2>/dev/null | grep -A 2 "Subnet" | grep -oP '"\K[0-9./]+' || echo "unknown")

        if [ "$NETWORK_SUBNET" != "unknown" ]; then
            if [ "$NETWORK_SUBNET" = "$DOCKER_SUBNET" ]; then
                print_success "Docker network subnet matches configuration: $NETWORK_SUBNET"
            else
                print_warning "Docker network subnet ($NETWORK_SUBNET) differs from .env ($DOCKER_SUBNET)"
                print_info "This may indicate a mismatch between Docker and configuration"
                WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
            fi

            # Show containers in the network
            CONTAINER_COUNT=$(docker network inspect vless-reality_vless-network 2>/dev/null | grep -c '"Name":' || echo "0")
            print_info "Containers in network: $CONTAINER_COUNT"
        fi
    else
        print_error "Docker network 'vless-reality_vless-network' NOT found"
        print_info "The Docker Compose stack may not be running"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi

    # Check if xray-server container is running
    if docker ps | grep -q "xray-server"; then
        print_success "xray-server container is running"

        # Check container health
        CONTAINER_STATUS=$(docker inspect xray-server 2>/dev/null | grep -A 5 "Health" | grep "Status" | cut -d'"' -f4 || echo "unknown")
        if [ "$CONTAINER_STATUS" = "healthy" ]; then
            print_success "xray-server health status: healthy"
        elif [ "$CONTAINER_STATUS" = "unknown" ]; then
            print_info "xray-server health check not configured"
        else
            print_warning "xray-server health status: $CONTAINER_STATUS"
            WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
        fi
    else
        print_error "xray-server container is NOT running"
        print_info "Run: cd $VLESS_HOME && sudo docker-compose up -d"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
else
    print_error "Docker is not installed or not in PATH"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

echo ""

# ============================================================================
# 6. Check external network interface
# ============================================================================
print_step "Checking external network interface..."

EXTERNAL_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)

if [ -n "$EXTERNAL_IFACE" ]; then
    print_success "External network interface: $EXTERNAL_IFACE"

    # Check if interface is up
    if ip link show "$EXTERNAL_IFACE" | grep -q "state UP"; then
        print_success "Interface $EXTERNAL_IFACE is UP"
    else
        print_error "Interface $EXTERNAL_IFACE is DOWN"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi

    # Get external IP if possible
    EXTERNAL_IP=$(ip addr show "$EXTERNAL_IFACE" | grep "inet " | awk '{print $2}' | cut -d'/' -f1 | head -1)
    if [ -n "$EXTERNAL_IP" ]; then
        print_info "Interface IP: $EXTERNAL_IP"

        # Compare with SERVER_IP from .env
        if [ -n "$SERVER_IP" ]; then
            if [ "$EXTERNAL_IP" = "$SERVER_IP" ]; then
                print_success "Interface IP matches SERVER_IP from .env"
            else
                print_warning "Interface IP ($EXTERNAL_IP) differs from SERVER_IP ($SERVER_IP)"
                print_info "Server may be behind NAT or using a different public IP"
                WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
            fi
        fi
    fi
else
    print_error "Could not determine external network interface"
    print_info "Check: ip route"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

echo ""

# ============================================================================
# 7. Summary
# ============================================================================
print_header "Verification Summary"
echo ""

if [ $ISSUES_FOUND -eq 0 ] && [ $WARNINGS_FOUND -eq 0 ]; then
    print_success "All checks passed! Network configuration is correct."
    echo ""
    print_info "Your VLESS VPN service should be working properly."
    echo ""
    exit 0
elif [ $ISSUES_FOUND -eq 0 ]; then
    print_warning "Verification completed with $WARNINGS_FOUND warning(s)"
    echo ""
    print_info "The system should work, but review warnings above for potential issues."
    echo ""
    exit 0
else
    print_error "Verification found $ISSUES_FOUND critical issue(s) and $WARNINGS_FOUND warning(s)"
    echo ""
    print_info "Please fix the issues above before using the VPN service."
    echo ""

    # Suggest fix-network.sh if available
    if [ -f "$SCRIPT_DIR/fix-network.sh" ]; then
        print_info "You can try running: sudo $SCRIPT_DIR/fix-network.sh"
    else
        print_info "To fix network configuration, run:"
        echo "  cd $SCRIPT_DIR"
        echo "  sudo bash -c 'source lib/colors.sh lib/utils.sh lib/network.sh && configure_network_for_vless \"$DOCKER_SUBNET\" \"$SERVER_PORT\"'"
    fi
    echo ""
    exit 1
fi