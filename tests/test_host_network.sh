#!/usr/bin/env bash

# Test script for host network mode and UFW configuration
# Run this to validate the changes work correctly

set -euo pipefail

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

source "$PROJECT_DIR/scripts/lib/colors.sh"
source "$PROJECT_DIR/scripts/lib/utils.sh"
source "$PROJECT_DIR/scripts/lib/config.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test function wrapper
run_test() {
    local test_name="$1"
    local test_function="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo ""
    print_step "Running test: $test_name"

    if $test_function; then
        print_success "✓ $test_name passed"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        print_error "✗ $test_name failed"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Test 1: Verify docker-compose template has host network mode
test_docker_compose_template() {
    local template="$PROJECT_DIR/templates/docker-compose.yml.tpl"

    if [ ! -f "$template" ]; then
        print_error "Template file not found: $template"
        return 1
    fi

    # Check for network_mode: host
    if grep -q "network_mode: host" "$template"; then
        print_info "Found network_mode: host in template"
    else
        print_error "network_mode: host not found in template"
        return 1
    fi

    # Check that ports mapping is removed
    if grep -q "ports:" "$template"; then
        print_error "Ports mapping still present in template"
        return 1
    else
        print_info "Ports mapping correctly removed"
    fi

    # Check that networks section is removed
    if grep -q "networks:" "$template"; then
        print_error "Networks section still present in template"
        return 1
    else
        print_info "Networks section correctly removed"
    fi

    return 0
}

# Test 2: Verify UFW functions exist
test_ufw_functions_exist() {
    # Check if functions are defined
    if ! declare -f check_ufw_status > /dev/null; then
        print_error "check_ufw_status function not found"
        return 1
    fi

    if ! declare -f ensure_ufw_rule > /dev/null; then
        print_error "ensure_ufw_rule function not found"
        return 1
    fi

    if ! declare -f configure_firewall_for_vless > /dev/null; then
        print_error "configure_firewall_for_vless function not found"
        return 1
    fi

    print_info "All UFW functions are defined"
    return 0
}

# Test 3: Test UFW status check (dry run)
test_ufw_status_check() {
    print_info "Testing UFW status check..."

    # This will check UFW status without making changes
    local result
    check_ufw_status
    result=$?

    case $result in
        0)
            print_info "UFW is active"
            ;;
        1)
            print_info "UFW is inactive"
            ;;
        2)
            print_info "UFW is not installed"
            ;;
        *)
            print_error "Unexpected result from check_ufw_status: $result"
            return 1
            ;;
    esac

    return 0
}

# Test 4: Verify install script has firewall configuration
test_install_script_firewall() {
    local install_script="$PROJECT_DIR/scripts/install.sh"

    if [ ! -f "$install_script" ]; then
        print_error "Install script not found"
        return 1
    fi

    # Check for firewall configuration call
    if grep -q "configure_firewall_for_vless" "$install_script"; then
        print_info "Firewall configuration found in install script"
    else
        print_error "Firewall configuration not found in install script"
        return 1
    fi

    # Check that SERVER_PORT is not passed to docker-compose template
    if grep -A2 "docker-compose.yml.tpl" "$install_script" | grep -q "SERVER_PORT="; then
        print_error "SERVER_PORT still being passed to docker-compose template"
        return 1
    else
        print_info "SERVER_PORT correctly removed from template parameters"
    fi

    return 0
}

# Test 5: Template generation test
test_template_generation() {
    print_info "Testing template generation..."

    # Create temporary directory for test
    local temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT

    # Test applying the template
    if apply_template \
        "$PROJECT_DIR/templates/docker-compose.yml.tpl" \
        "$temp_dir/docker-compose.yml" \
        "RESTART_POLICY=unless-stopped" \
        "TZ=UTC"; then

        print_info "Template applied successfully"

        # Verify generated file has host network mode
        if grep -q "network_mode: host" "$temp_dir/docker-compose.yml"; then
            print_info "Generated file has network_mode: host"
        else
            print_error "Generated file missing network_mode: host"
            return 1
        fi

    else
        print_error "Template application failed"
        return 1
    fi

    return 0
}

# Test 6: Syntax check all modified scripts
test_script_syntax() {
    local scripts=(
        "$PROJECT_DIR/scripts/install.sh"
        "$PROJECT_DIR/scripts/lib/utils.sh"
        "$PROJECT_DIR/scripts/lib/config.sh"
    )

    for script in "${scripts[@]}"; do
        if [ -f "$script" ]; then
            if bash -n "$script" 2>/dev/null; then
                print_info "Syntax OK: $(basename $script)"
            else
                print_error "Syntax error in: $(basename $script)"
                return 1
            fi
        else
            print_error "Script not found: $script"
            return 1
        fi
    done

    return 0
}

# Main test execution
print_header "VLESS Host Network Mode Validation Tests"

run_test "Docker Compose Template" test_docker_compose_template
run_test "UFW Functions Exist" test_ufw_functions_exist
run_test "UFW Status Check" test_ufw_status_check
run_test "Install Script Firewall" test_install_script_firewall
run_test "Template Generation" test_template_generation
run_test "Script Syntax Check" test_script_syntax

# Print summary
echo ""
print_header "Test Summary"
echo "Tests run: $TESTS_RUN"
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"

if [ $TESTS_FAILED -eq 0 ]; then
    print_success "All tests passed!"
    exit 0
else
    print_error "Some tests failed"
    exit 1
fi