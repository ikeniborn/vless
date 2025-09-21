#!/bin/bash

# Simple Phase 4 Test Script
set -euo pipefail

echo "Starting Phase 4 Simple Tests"

# Test 1: Check all modules exist
echo "Test 1: Checking module files..."
modules=(
    "/home/ikeniborn/Documents/Project/vless/modules/ufw_config.sh"
    "/home/ikeniborn/Documents/Project/vless/modules/security_hardening.sh"
    "/home/ikeniborn/Documents/Project/vless/modules/cert_management.sh"
    "/home/ikeniborn/Documents/Project/vless/modules/monitoring.sh"
    "/home/ikeniborn/Documents/Project/vless/modules/phase4_integration.sh"
)

for module in "${modules[@]}"; do
    if [[ -f "$module" ]]; then
        echo "✓ Found: $(basename "$module")"
    else
        echo "✗ Missing: $(basename "$module")"
    fi
done

# Test 2: Check syntax
echo -e "\nTest 2: Checking syntax..."
for module in "${modules[@]}"; do
    if [[ -f "$module" ]]; then
        if bash -n "$module"; then
            echo "✓ Syntax OK: $(basename "$module")"
        else
            echo "✗ Syntax Error: $(basename "$module")"
        fi
    fi
done

# Test 3: Check help commands
echo -e "\nTest 3: Checking help commands..."
for module in "${modules[@]}"; do
    if [[ -f "$module" && -x "$module" ]]; then
        module_name=$(basename "$module")
        echo "Testing help for: $module_name"
        if timeout 10 "$module" help >/dev/null 2>&1; then
            echo "✓ Help OK: $module_name"
        else
            echo "✗ Help Failed: $module_name"
        fi
    fi
done

echo -e "\nPhase 4 Simple Tests Completed"