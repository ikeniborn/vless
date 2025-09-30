#!/bin/bash

# Diagnostic script for VPN conflicts
# Detects and resolves NAT rule conflicts from multiple VPN services

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load libraries
if [ -f "$SCRIPT_DIR/lib/colors.sh" ]; then
    source "$SCRIPT_DIR/lib/colors.sh"
    source "$SCRIPT_DIR/lib/utils.sh"
    source "$SCRIPT_DIR/lib/network.sh"
else
    # Fallback for when running from repo
    REPO_DIR="$(dirname "$SCRIPT_DIR")"
    source "$REPO_DIR/scripts/lib/colors.sh"
    source "$REPO_DIR/scripts/lib/utils.sh"
    source "$REPO_DIR/scripts/lib/network.sh"
fi

# Check if running as root
check_root

print_header "VPN Network Conflicts Diagnostic Tool"

echo "This tool diagnoses and resolves network conflicts caused by:"
echo "  • Multiple VPN services on the same server"
echo "  • Manual NAT rules interfering with Docker"
echo "  • Duplicate MASQUERADE rules"
echo ""

# Step 1: Check system configuration
print_header "Step 1: System Configuration Check"

print_step "Checking IP forwarding..."
if [ "$(sysctl -n net.ipv4.ip_forward)" = "1" ]; then
    print_success "IP forwarding is enabled"
else
    print_error "IP forwarding is disabled"
    print_info "Run: sudo sysctl -w net.ipv4.ip_forward=1"
fi

print_step "Checking br_netfilter module..."
if lsmod | grep -q "^br_netfilter"; then
    print_success "br_netfilter module is loaded"
else
    print_error "br_netfilter module is not loaded"
    print_info "Run: sudo modprobe br_netfilter"
fi

print_step "Checking bridge netfilter settings..."
if [ "$(cat /proc/sys/net/bridge/bridge-nf-call-iptables 2>/dev/null || echo 0)" = "1" ]; then
    print_success "bridge-nf-call-iptables is enabled"
else
    print_error "bridge-nf-call-iptables is disabled (CRITICAL)"
    print_info "Run: sudo sysctl -w net.bridge.bridge-nf-call-iptables=1"
fi

echo ""

# Step 2: Detect external interface
print_header "Step 2: Network Interface Detection"

EXTERNAL_IF=$(get_external_interface 2>/dev/null)
if [ -n "$EXTERNAL_IF" ]; then
    print_success "External interface: $EXTERNAL_IF"
else
    print_error "Could not detect external interface"
    exit 1
fi

echo ""

# Step 3: Analyze Docker networks
print_header "Step 3: Docker Networks Analysis"

print_step "Listing Docker networks with 172.x subnets..."
docker network inspect $(docker network ls -q) 2>/dev/null | \
    jq -r '.[] | select(.IPAM.Config[0].Subnet // "" | startswith("172.")) |
    "  \(.Name) (\(.Driver)) - \(.IPAM.Config[0].Subnet // "N/A")"'

echo ""

# Step 4: Analyze NAT rules
print_header "Step 4: NAT Rules Analysis"

print_step "Analyzing POSTROUTING chain..."
echo ""
echo "Current NAT POSTROUTING rules:"
echo "----------------------------------------"
iptables -t nat -L POSTROUTING -n -v --line-numbers | head -2
echo ""

# Docker-managed rules (good)
print_info "[Docker-managed rules (automatic)]"
DOCKER_RULES=$(iptables -t nat -L POSTROUTING -n -v --line-numbers 2>/dev/null | \
    grep -E "br-[a-f0-9]+" || true)
if [ -n "$DOCKER_RULES" ]; then
    echo "$DOCKER_RULES" | awk '{print "  "$1": "$0}'
else
    echo "  None found"
fi
echo ""

# Manual rules via external interface (potentially conflicting)
print_info "[Manual rules via external interface (may conflict)]"
MANUAL_RULES=$(iptables -t nat -L POSTROUTING -n -v --line-numbers 2>/dev/null | \
    grep -E "MASQUERADE.*${EXTERNAL_IF}" | \
    grep -E "172\.[0-9]+\.0\.0/1[0-9]" || true)

if [ -n "$MANUAL_RULES" ]; then
    echo "$MANUAL_RULES" | awk '{print "  "$1": "$0}'
    CONFLICT_COUNT=$(echo "$MANUAL_RULES" | wc -l)
    echo ""
    print_warning "Found $CONFLICT_COUNT potentially conflicting manual rule(s)"
else
    echo "  None found"
    print_success "No conflicting manual rules detected"
fi

echo ""

# Docker default bridge rules
print_info "[Default Docker bridge rules]"
DOCKER0_RULES=$(iptables -t nat -L POSTROUTING -n -v --line-numbers 2>/dev/null | \
    grep -E "docker0" || true)
if [ -n "$DOCKER0_RULES" ]; then
    echo "$DOCKER0_RULES" | awk '{print "  "$1": "$0}'
else
    echo "  None found"
fi

echo ""

# Step 5: Check for duplicate rules
print_header "Step 5: Duplicate Rules Detection"

print_step "Checking for duplicate MASQUERADE rules..."
echo ""

# Group rules by source subnet and count
DUPLICATES=$(iptables -t nat -L POSTROUTING -n 2>/dev/null | \
    grep -E "MASQUERADE.*172\.[0-9]+\.0\.0/1[0-9]" | \
    awk '{print $4}' | sort | uniq -c | awk '$1 > 2 {print}' || true)

if [ -n "$DUPLICATES" ]; then
    print_warning "Found duplicate rules:"
    echo "$DUPLICATES" | while read count subnet; do
        echo "  Subnet $subnet appears $count times"
    done
    echo ""
    print_info "This usually indicates rules from multiple VPN services"
else
    print_success "No significant duplication detected"
fi

echo ""

# Step 6: Test connectivity from Docker
print_header "Step 6: Docker Container Connectivity Test"

print_step "Checking if xray-server container is running..."
if docker ps --format '{{.Names}}' | grep -q "xray-server"; then
    print_success "xray-server container is running"
    echo ""

    print_step "Testing DNS resolution from container..."
    if docker exec xray-server nslookup google.com 8.8.8.8 >/dev/null 2>&1; then
        print_success "DNS resolution: OK"
    else
        print_error "DNS resolution: FAILED"
    fi

    print_step "Testing internet connectivity from container..."
    if docker exec xray-server ping -c 2 8.8.8.8 >/dev/null 2>&1; then
        print_success "Internet connectivity: OK"
    else
        print_error "Internet connectivity: FAILED"
        print_warning "This indicates NAT routing issues"
    fi
else
    print_info "xray-server container is not running"
    print_info "Start it with: cd /opt/vless && docker-compose up -d"
fi

echo ""

# Step 7: Recommendations
print_header "Step 7: Recommendations"

if [ -n "$MANUAL_RULES" ] && [ "$CONFLICT_COUNT" -gt 0 ]; then
    print_warning "Action Required: Remove conflicting manual NAT rules"
    echo ""
    echo "These manual rules may have been added by:"
    echo "  • Another VPN service (OpenVPN, WireGuard, Outline, etc.)"
    echo "  • Previous VLESS installation"
    echo "  • Manual iptables configuration"
    echo ""
    echo "To fix this issue, you have two options:"
    echo ""
    print_info "Option 1: Automated cleanup (recommended)"
    echo "  Run the network cleanup function from network.sh:"
    echo "  source /opt/vless/scripts/lib/colors.sh"
    echo "  source /opt/vless/scripts/lib/utils.sh"
    echo "  source /opt/vless/scripts/lib/network.sh"
    echo "  clean_conflicting_nat_rules"
    echo ""
    print_info "Option 2: Manual cleanup"
    echo "  Remove rules one by one (in reverse order):"
    echo ""
    echo "$MANUAL_RULES" | sort -rn | awk '{print "  sudo iptables -t nat -D POSTROUTING "$1}'
    echo ""
    print_info "After cleanup, restart Docker: sudo systemctl restart docker"
    print_info "Then restart VLESS: cd /opt/vless && docker-compose restart"
else
    print_success "Network configuration looks good!"
    echo ""
    echo "No conflicting rules detected. If you still have connectivity issues:"
    echo "  1. Verify br_netfilter module: lsmod | grep br_netfilter"
    echo "  2. Check sysctl settings:"
    echo "     sysctl net.ipv4.ip_forward"
    echo "     sysctl net.bridge.bridge-nf-call-iptables"
    echo "  3. Restart Docker: sudo systemctl restart docker"
    echo "  4. Restart VLESS: cd /opt/vless && docker-compose restart"
fi

echo ""
print_header "Diagnostic Complete"
