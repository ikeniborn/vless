#!/bin/bash

# Quick test of cleanup function

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load libraries
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/network.sh"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

print_header "Testing NAT Cleanup Function"

# Get external interface
EXTERNAL_IF=$(get_external_interface 2>/dev/null)
echo "External interface: $EXTERNAL_IF"
echo ""

# Test grep pattern
print_step "Testing grep pattern to find conflicting rules..."
FOUND_RULES=$(iptables -t nat -L POSTROUTING -n -v --line-numbers 2>/dev/null | \
    grep -E "MASQUERADE.*\*[[:space:]]+${EXTERNAL_IF}[[:space:]]+172\.[0-9]+\.0\.0/1[0-9]" || true)

if [ -n "$FOUND_RULES" ]; then
    RULE_COUNT=$(echo "$FOUND_RULES" | wc -l)
    print_success "Found $RULE_COUNT conflicting rules!"
    echo ""
    echo "Rules found:"
    echo "$FOUND_RULES"
    echo ""
else
    print_warning "No rules found with pattern"
fi

# Now run the cleanup function
print_header "Running clean_conflicting_nat_rules()"
clean_conflicting_nat_rules
