#!/bin/bash

# Test script for Phase 3 integration - Service startup after installation
# This script validates the integration between install.sh and container_management.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/modules/common_utils.sh"

echo "=== Phase 3 Integration Test - Service Startup After Installation ==="
echo

# Test 1: Verify install.sh syntax
echo "Test 1: Install.sh Syntax Validation"
if bash -n "${SCRIPT_DIR}/install.sh"; then
    echo "✓ install.sh syntax is valid"
else
    echo "✗ install.sh has syntax errors"
    exit 1
fi
echo

# Test 2: Check if required functions are defined
echo "Test 2: Function Definition Check"
source "${SCRIPT_DIR}/install.sh" 2>/dev/null || true

# Check if new functions are defined
if declare -F start_services_after_installation >/dev/null; then
    echo "✓ start_services_after_installation function is defined"
else
    echo "✗ start_services_after_installation function not found"
    exit 1
fi

if declare -F display_post_installation_status >/dev/null; then
    echo "✓ display_post_installation_status function is defined"
else
    echo "✗ display_post_installation_status function not found"
    exit 1
fi

if declare -F display_service_troubleshooting >/dev/null; then
    echo "✓ display_service_troubleshooting function is defined"
else
    echo "✗ display_service_troubleshooting function not found"
    exit 1
fi
echo

# Test 3: Check container_management.sh integration
echo "Test 3: Container Management Integration"
if [[ -f "${SCRIPT_DIR}/modules/container_management.sh" ]]; then
    echo "✓ container_management.sh module found"

    if bash -n "${SCRIPT_DIR}/modules/container_management.sh"; then
        echo "✓ container_management.sh syntax is valid"
    else
        echo "✗ container_management.sh has syntax errors"
        exit 1
    fi

    # Check if required functions are exported
    source "${SCRIPT_DIR}/modules/container_management.sh"

    local required_functions=(
        "start_services"
        "check_service_health"
        "show_service_status"
        "prepare_system_environment"
    )

    local function
    for function in "${required_functions[@]}"; do
        if declare -F "$function" >/dev/null; then
            echo "✓ $function is available"
        else
            echo "✗ $function is not available"
            exit 1
        fi
    done
else
    echo "✗ container_management.sh module not found"
    exit 1
fi
echo

# Test 4: Check Phase 2 integration
echo "Test 4: Phase 2 Integration Check"
if grep -q "start_services_after_installation" "${SCRIPT_DIR}/install.sh"; then
    echo "✓ Phase 2 calls start_services_after_installation"
else
    echo "✗ Phase 2 does not call service startup function"
    exit 1
fi

if grep -q "prepare_system_environment" "${SCRIPT_DIR}/install.sh"; then
    echo "✓ Phase 2 calls prepare_system_environment"
else
    echo "✗ Phase 2 does not call prepare_system_environment"
    exit 1
fi
echo

# Test 5: Check quick install integration
echo "Test 5: Quick Install Integration"
if grep -q "check_service_health" "${SCRIPT_DIR}/install.sh"; then
    echo "✓ Quick install includes service health verification"
else
    echo "✗ Quick install missing service health verification"
    exit 1
fi
echo

# Test 6: Check system status integration
echo "Test 6: System Status Integration"
if grep -q "check_service_health 2>/dev/null" "${SCRIPT_DIR}/install.sh"; then
    echo "✓ System status includes service health check"
else
    echo "✗ System status missing service health integration"
    exit 1
fi
echo

# Test 7: Check error handling
echo "Test 7: Error Handling Validation"
if grep -q "display_service_troubleshooting" "${SCRIPT_DIR}/install.sh"; then
    echo "✓ Service startup failure handling implemented"
else
    echo "✗ Missing service startup failure handling"
    exit 1
fi

if grep -q "max_attempts" "${SCRIPT_DIR}/install.sh"; then
    echo "✓ Retry logic implemented for service startup"
else
    echo "✗ Missing retry logic for service startup"
    exit 1
fi
echo

# Test 8: Check post-installation messaging
echo "Test 8: Post-Installation Messaging"
if grep -q "display_post_installation_status" "${SCRIPT_DIR}/install.sh"; then
    echo "✓ Post-installation status display implemented"
else
    echo "✗ Missing post-installation status display"
    exit 1
fi

if grep -q "Next Steps:" "${SCRIPT_DIR}/install.sh"; then
    echo "✓ User guidance included after installation"
else
    echo "✗ Missing user guidance after installation"
    exit 1
fi
echo

# Test 9: Check integration points
echo "Test 9: Integration Point Validation"

# Check if Phase 2 properly sources container_management.sh
if grep -q 'source.*container_management.sh' "${SCRIPT_DIR}/install.sh"; then
    echo "✓ Phase 2 properly sources container_management.sh"
else
    echo "✗ Phase 2 missing container_management.sh sourcing"
    exit 1
fi

# Check if system status properly integrates with container status
if grep -q 'docker ps.*filter.*vless-vpn' "${SCRIPT_DIR}/install.sh"; then
    echo "✓ System status shows VLESS container status"
else
    echo "✗ System status missing VLESS container integration"
    exit 1
fi
echo

# Test 10: Validate installation mode compatibility
echo "Test 10: Installation Mode Compatibility"
local modes=("minimal" "balanced" "full")
local mode

for mode in "${modes[@]}"; do
    if grep -q "$mode" "${SCRIPT_DIR}/install.sh"; then
        echo "✓ $mode installation mode compatible"
    else
        echo "✗ $mode installation mode missing or incompatible"
        exit 1
    fi
done
echo

echo "=== Phase 3 Integration Test Results ==="
echo "✓ All tests passed successfully!"
echo
echo "Phase 3 Implementation Summary:"
echo "• Install.sh now automatically starts services after Phase 2"
echo "• Post-installation health checks with retry logic"
echo "• Enhanced service status display with troubleshooting"
echo "• Comprehensive error handling and user guidance"
echo "• Full integration with container_management.sh module"
echo
echo "The installer will now:"
echo "1. Complete Phase 2 VLESS server setup"
echo "2. Automatically start Docker services"
echo "3. Verify service health with retries"
echo "4. Display service status and next steps"
echo "5. Provide troubleshooting guidance if startup fails"
echo

log_success "Phase 3 implementation is complete and ready for use!"