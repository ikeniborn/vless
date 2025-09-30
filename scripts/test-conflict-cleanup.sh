#!/bin/bash

# Test script for VPN conflict cleanup functionality
# This script demonstrates the conflict detection and cleanup process

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load libraries
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/network.sh"

print_header "VPN Conflict Cleanup Test"

echo "This test script demonstrates the conflict detection and cleanup functionality."
echo ""

# Test 1: Check if running as root
print_step "Test 1: Checking privileges..."
if [ "$EUID" -ne 0 ]; then
    print_error "This test script must be run as root"
    print_info "Run: sudo bash $0"
    exit 1
else
    print_success "Running as root"
fi

# Test 2: Detect external interface
print_step "Test 2: Detecting external network interface..."
EXTERNAL_IF=$(get_external_interface 2>/dev/null)
if [ -n "$EXTERNAL_IF" ]; then
    print_success "External interface: $EXTERNAL_IF"
else
    print_error "Could not detect external interface"
    exit 1
fi

# Test 3: Check for conflicting rules
print_step "Test 3: Checking for conflicting NAT rules..."
MANUAL_RULES=$(iptables -t nat -L POSTROUTING -n -v --line-numbers 2>/dev/null | \
    grep -E "MASQUERADE.*${EXTERNAL_IF}" | \
    grep -E "172\.[0-9]+\.0\.0/1[0-9]")

if [ -n "$MANUAL_RULES" ]; then
    CONFLICT_COUNT=$(echo "$MANUAL_RULES" | wc -l)
    print_warning "Found $CONFLICT_COUNT potentially conflicting manual rule(s)"
    echo ""
    echo "Conflicting rules:"
    echo "$MANUAL_RULES" | awk '{print "  Rule #"$1": "$0}'
    echo ""
else
    print_success "No conflicting manual rules detected"
fi

# Test 4: Show Docker-managed rules
print_step "Test 4: Checking Docker-managed rules..."
DOCKER_RULES=$(iptables -t nat -L POSTROUTING -n -v 2>/dev/null | \
    grep -E "!br-[a-f0-9]+" | \
    grep "MASQUERADE" || true)

if [ -n "$DOCKER_RULES" ]; then
    print_success "Found Docker-managed rules (good)"
    echo "Docker rules:"
    echo "$DOCKER_RULES" | awk '{print "  "$0}'
    echo ""
else
    print_info "No Docker-managed rules found (containers may not be running)"
fi

# Test 5: Demonstrate cleanup function availability
print_step "Test 5: Verifying cleanup function..."
if type clean_conflicting_nat_rules &>/dev/null; then
    print_success "clean_conflicting_nat_rules() function is available"
    echo ""
    print_info "To run the cleanup, execute:"
    echo "  source $SCRIPT_DIR/lib/colors.sh"
    echo "  source $SCRIPT_DIR/lib/utils.sh"
    echo "  source $SCRIPT_DIR/lib/network.sh"
    echo "  clean_conflicting_nat_rules"
else
    print_error "clean_conflicting_nat_rules() function not found"
    exit 1
fi

echo ""
print_header "Test Complete"

if [ -n "$MANUAL_RULES" ]; then
    echo ""
    print_warning "Action Required: Conflicting rules detected"
    echo ""
    echo "Options:"
    echo "  1. Run diagnostic tool: sudo $SCRIPT_DIR/diagnose-vpn-conflicts.sh"
    echo "  2. Run cleanup manually: (see commands above)"
    echo "  3. Run during installation: sudo bash $SCRIPT_DIR/install.sh"
else
    print_success "No conflicts detected - system is ready"
fi

echo ""
