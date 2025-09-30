#!/bin/bash

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load libraries
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/network.sh"

# Configuration
VLESS_HOME="${VLESS_HOME:-/opt/vless}"

print_header "VLESS Network Cleanup Tool"
print_info "This script will clean up legacy network rules and configurations"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

# Load current configuration
if [ -f "$VLESS_HOME/.env" ]; then
    source "$VLESS_HOME/.env"
    print_success "Loaded configuration from $VLESS_HOME/.env"
    echo "Current Docker subnet: $DOCKER_SUBNET"
    echo ""
else
    print_error "Configuration file not found: $VLESS_HOME/.env"
    print_info "VLESS service may not be installed"
    exit 1
fi

# Get external interface
EXTERNAL_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
if [ -z "$EXTERNAL_INTERFACE" ]; then
    print_error "Could not detect external network interface"
    exit 1
fi
print_info "External interface: $EXTERNAL_INTERFACE"
echo ""

# Show current iptables rules
print_header "Current iptables NAT Rules"
iptables -t nat -L POSTROUTING -n -v --line-numbers | grep "172\." || echo "No 172.x rules found"
echo ""

print_header "Current iptables FORWARD Rules"
iptables -t filter -L FORWARD -n -v --line-numbers | grep "172\." || echo "No 172.x rules found"
echo ""

# Confirm cleanup
if ! confirm_action "Do you want to clean up legacy network rules?" "n"; then
    print_warning "Cleanup cancelled"
    exit 0
fi

# Clean up iptables rules
print_header "Cleaning up iptables rules"
remove_legacy_iptables_rules "$DOCKER_SUBNET" "$EXTERNAL_INTERFACE"

# Clean up UFW rules
if command_exists "ufw"; then
    if ufw status 2>/dev/null | head -1 | grep -q "active"; then
        print_header "Cleaning up UFW NAT rules"
        remove_legacy_ufw_nat_rules "$DOCKER_SUBNET"

        # Reload UFW
        print_step "Reloading UFW..."
        ufw reload
        print_success "UFW reloaded"
    fi
fi

# Verify cleanup
echo ""
print_header "Verification"
print_step "Checking remaining rules..."

echo ""
print_info "iptables NAT rules after cleanup:"
iptables -t nat -L POSTROUTING -n -v --line-numbers | grep "172\." || echo "  No 172.x rules found"

echo ""
print_info "iptables FORWARD rules after cleanup:"
iptables -t filter -L FORWARD -n -v --line-numbers | grep "172\." || echo "  No 172.x rules found"

# Save rules
echo ""
print_step "Saving iptables rules..."
if command_exists "netfilter-persistent"; then
    netfilter-persistent save
    print_success "iptables rules saved with netfilter-persistent"
elif command_exists "iptables-save"; then
    if [ -d "/etc/iptables" ]; then
        iptables-save > /etc/iptables/rules.v4
        print_success "iptables rules saved to /etc/iptables/rules.v4"
    else
        iptables-save > /etc/iptables.rules
        print_success "iptables rules saved to /etc/iptables.rules"
    fi
fi

echo ""
print_success "Network cleanup completed successfully"
print_info "Current subnet $DOCKER_SUBNET rules are preserved"
