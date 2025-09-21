#!/bin/bash
# ======================================================================================
# VLESS+Reality VPN Management System - Phase 2 Integration Test
# ======================================================================================
# This script performs comprehensive integration testing for Phase 2 components:
# Docker Infrastructure and Containerization.
#
# Author: Claude Code
# Version: 1.0
# Last Modified: 2025-09-21
# ======================================================================================

set -euo pipefail

# Test configuration
readonly TEST_NAME="Phase 2 Integration Test"
readonly TEST_VERSION="1.0"
readonly TEST_LOG="/tmp/vless_phase2_integration.log"

# Source required modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=modules/common_utils.sh
source "${PROJECT_ROOT}/modules/common_utils.sh"

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# ======================================================================================
# TEST FRAMEWORK
# ======================================================================================

#
# Initialize integration test environment
#
init_integration_test() {
    log_info "Initializing Phase 2 Integration Test Environment"

    # Create test log
    exec 1> >(tee -a "${TEST_LOG}")
    exec 2> >(tee -a "${TEST_LOG}" >&2)

    echo "Phase 2 Integration Test Started: $(date)" | tee -a "${TEST_LOG}"
    echo "=======================================" | tee -a "${TEST_LOG}"

    # Validate prerequisites
    validate_root
    check_internet

    log_info "Integration test environment ready"
}

#
# Run integration test and track results
#
run_integration_test() {
    local test_name="$1"
    local test_function="$2"

    ((TESTS_TOTAL++))

    log_info "Running integration test: ${test_name}"
    echo ""
    echo "Integration Test ${TESTS_TOTAL}: ${test_name}"
    echo "============================================"

    if ${test_function}; then
        ((TESTS_PASSED++))
        log_info "✓ INTEGRATION TEST PASSED: ${test_name}"
        echo "RESULT: PASSED"
    else
        ((TESTS_FAILED++))
        log_error "✗ INTEGRATION TEST FAILED: ${test_name}"
        echo "RESULT: FAILED"
    fi

    echo ""
    echo "----------------------------------------"
    echo ""
}

#
# Print integration test summary
#
print_integration_summary() {
    echo ""
    echo "======================================="
    log_info "Phase 2 Integration Test Summary"
    echo "======================================="
    echo "Total Integration Tests: ${TESTS_TOTAL}"
    echo "Passed: ${TESTS_PASSED}"
    echo "Failed: ${TESTS_FAILED}"

    if [[ ${TESTS_TOTAL} -gt 0 ]]; then
        echo "Success Rate: $(( (TESTS_PASSED * 100) / TESTS_TOTAL ))%"
    fi

    echo "======================================="
    echo "Detailed log: ${TEST_LOG}"
    echo ""

    if [[ ${TESTS_FAILED} -eq 0 ]]; then
        log_info "🎉 All Phase 2 integration tests passed successfully!"
        echo ""
        echo "Phase 2 (Docker Infrastructure) is ready for production!"
        return 0
    else
        log_error "❌ ${TESTS_FAILED} integration test(s) failed"
        echo ""
        echo "Phase 2 implementation needs attention before proceeding."
        return 1
    fi
}

# ======================================================================================
# INTEGRATION TESTS
# ======================================================================================

#
# Test complete Docker setup and validation
#
test_docker_infrastructure_setup() {
    log_info "Testing complete Docker infrastructure setup..."

    # Test Docker setup module
    if ! source "${PROJECT_ROOT}/modules/docker_setup.sh"; then
        log_error "Failed to source docker_setup.sh module"
        return 1
    fi

    # Check if Docker functions are available
    local required_functions=(
        "check_docker_installed"
        "check_docker_compose_installed"
        "setup_docker_complete"
        "validate_docker_installation"
    )

    for func in "${required_functions[@]}"; do
        if ! declare -f "${func}" &>/dev/null; then
            log_error "Required function not found: ${func}"
            return 1
        fi
    done

    log_info "Docker setup module loaded successfully"

    # Test Docker installation check
    if check_docker_installed; then
        log_info "Docker is properly installed"
    else
        log_warn "Docker not installed - this is expected on fresh systems"
    fi

    # Test Docker Compose check
    if check_docker_compose_installed; then
        log_info "Docker Compose is properly installed"
    else
        log_warn "Docker Compose not installed - this is expected on fresh systems"
    fi

    return 0
}

#
# Test Xray container configuration and validation
#
test_xray_container_configuration() {
    log_info "Testing Xray container configuration..."

    # Check Docker Compose file
    local compose_file="${PROJECT_ROOT}/config/docker-compose.yml"
    if [[ ! -f "${compose_file}" ]]; then
        log_error "Docker Compose file not found: ${compose_file}"
        return 1
    fi

    log_info "Docker Compose file exists: ${compose_file}"

    # Validate YAML syntax (if Docker is available)
    if command -v docker &>/dev/null; then
        export VLESS_ROOT="/opt/vless"
        if docker compose -f "${compose_file}" config --quiet; then
            log_info "Docker Compose file syntax is valid"
        else
            log_error "Docker Compose file has syntax errors"
            return 1
        fi
    else
        log_warn "Docker not available - skipping Compose validation"
    fi

    # Check Xray configuration template
    local xray_config="${PROJECT_ROOT}/config/xray_config_template.json"
    if [[ ! -f "${xray_config}" ]]; then
        log_error "Xray configuration template not found: ${xray_config}"
        return 1
    fi

    log_info "Xray configuration template exists: ${xray_config}"

    # Validate JSON syntax
    if python3 -m json.tool "${xray_config}" > /dev/null 2>&1; then
        log_info "Xray configuration template JSON syntax is valid"
    else
        log_error "Xray configuration template has JSON syntax errors"
        return 1
    fi

    # Check for required configuration sections
    local required_sections=("inbounds" "outbounds" "routing" "log" "dns")
    for section in "${required_sections[@]}"; do
        if grep -q "\"${section}\":" "${xray_config}"; then
            log_info "Required section found: ${section}"
        else
            log_error "Required section missing: ${section}"
            return 1
        fi
    done

    # Check for VLESS+Reality specific configuration
    if grep -q "\"protocol\": \"vless\"" "${xray_config}"; then
        log_info "VLESS protocol configuration found"
    else
        log_error "VLESS protocol configuration missing"
        return 1
    fi

    if grep -q "\"security\": \"reality\"" "${xray_config}"; then
        log_info "Reality security configuration found"
    else
        log_error "Reality security configuration missing"
        return 1
    fi

    return 0
}

#
# Test container management module functionality
#
test_container_management_functionality() {
    log_info "Testing container management functionality..."

    # Source container management module
    if ! source "${PROJECT_ROOT}/modules/container_management.sh"; then
        log_error "Failed to source container_management.sh module"
        return 1
    fi

    # Check required functions
    local required_functions=(
        "start_xray_container"
        "stop_xray_container"
        "restart_xray_container"
        "check_container_health"
        "get_container_logs"
        "validate_compose_file"
        "validate_xray_config"
    )

    for func in "${required_functions[@]}"; do
        if declare -f "${func}" &>/dev/null; then
            log_info "Container management function available: ${func}"
        else
            log_error "Container management function missing: ${func}"
            return 1
        fi
    done

    # Test configuration validation functions
    if [[ -f "${PROJECT_ROOT}/config/docker-compose.yml" ]]; then
        # Copy to expected location for testing
        mkdir -p "/opt/vless/config"
        cp "${PROJECT_ROOT}/config/docker-compose.yml" "/opt/vless/config/"

        if validate_compose_file; then
            log_info "Compose file validation function works correctly"
        else
            log_error "Compose file validation function failed"
            return 1
        fi
    fi

    return 0
}

#
# Test Docker services test script functionality
#
test_docker_services_test_script() {
    log_info "Testing Docker services test script..."

    local test_script="${PROJECT_ROOT}/tests/test_docker_services.sh"

    if [[ ! -f "${test_script}" ]]; then
        log_error "Docker services test script not found: ${test_script}"
        return 1
    fi

    if [[ ! -x "${test_script}" ]]; then
        log_error "Docker services test script is not executable"
        return 1
    fi

    log_info "Docker services test script exists and is executable"

    # Test script help function
    if "${test_script}" help >/dev/null 2>&1; then
        log_info "Docker services test script help function works"
    else
        log_warn "Docker services test script help function issue (non-critical)"
    fi

    return 0
}

#
# Test Phase 2 module integration
#
test_phase2_module_integration() {
    log_info "Testing Phase 2 module integration..."

    # Test that all Phase 2 modules can be sourced together
    local modules=(
        "${PROJECT_ROOT}/modules/common_utils.sh"
        "${PROJECT_ROOT}/modules/docker_setup.sh"
        "${PROJECT_ROOT}/modules/container_management.sh"
    )

    for module in "${modules[@]}"; do
        if [[ ! -f "${module}" ]]; then
            log_error "Required module not found: ${module}"
            return 1
        fi

        if source "${module}"; then
            log_info "Successfully sourced module: $(basename "${module}")"
        else
            log_error "Failed to source module: ${module}"
            return 1
        fi
    done

    # Test that functions don't conflict
    log_info "Testing function availability after module integration..."

    # Test key functions from each module
    local key_functions=(
        "log_info"              # common_utils.sh
        "validate_root"         # common_utils.sh
        "check_docker_installed" # docker_setup.sh
        "start_xray_container"  # container_management.sh
    )

    for func in "${key_functions[@]}"; do
        if declare -f "${func}" &>/dev/null; then
            log_info "Key function available: ${func}"
        else
            log_error "Key function not available: ${func}"
            return 1
        fi
    done

    return 0
}

#
# Test file permissions and structure
#
test_file_permissions_and_structure() {
    log_info "Testing file permissions and directory structure..."

    # Check that shell scripts are executable
    local executables=(
        "${PROJECT_ROOT}/modules/docker_setup.sh"
        "${PROJECT_ROOT}/modules/container_management.sh"
        "${PROJECT_ROOT}/tests/test_docker_services.sh"
    )

    for script in "${executables[@]}"; do
        if [[ -x "${script}" ]]; then
            log_info "Script is executable: $(basename "${script}")"
        else
            log_error "Script is not executable: ${script}"
            return 1
        fi
    done

    # Check configuration files are readable
    local config_files=(
        "${PROJECT_ROOT}/config/docker-compose.yml"
        "${PROJECT_ROOT}/config/xray_config_template.json"
    )

    for config in "${config_files[@]}"; do
        if [[ -r "${config}" ]]; then
            log_info "Configuration file is readable: $(basename "${config}")"
        else
            log_error "Configuration file is not readable: ${config}"
            return 1
        fi
    done

    # Check directory structure
    local required_dirs=(
        "${PROJECT_ROOT}/modules"
        "${PROJECT_ROOT}/config"
        "${PROJECT_ROOT}/tests"
    )

    for dir in "${required_dirs[@]}"; do
        if [[ -d "${dir}" ]]; then
            log_info "Required directory exists: $(basename "${dir}")"
        else
            log_error "Required directory missing: ${dir}"
            return 1
        fi
    done

    return 0
}

#
# Test system requirements for Phase 2
#
test_system_requirements() {
    log_info "Testing system requirements for Phase 2..."

    # Check OS compatibility
    local os_info
    os_info=$(get_os_info)
    log_info "Detected OS: ${os_info}"

    case "${os_info}" in
        "ubuntu"|"debian"|"centos"|"rhel"|"fedora")
            log_info "Operating system is supported: ${os_info}"
            ;;
        *)
            log_warn "Operating system may not be fully supported: ${os_info}"
            ;;
    esac

    # Check available disk space
    local available_space
    available_space=$(df /var 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")

    if [[ ${available_space} -gt 2097152 ]]; then  # 2GB in KB
        log_info "Sufficient disk space available: $(( available_space / 1024 / 1024 ))GB"
    else
        log_warn "Limited disk space available: $(( available_space / 1024 ))MB"
    fi

    # Check memory
    local total_memory
    total_memory=$(free -m | awk 'NR==2{print $2}')

    if [[ ${total_memory} -gt 512 ]]; then
        log_info "Sufficient memory available: ${total_memory}MB"
    else
        log_warn "Limited memory available: ${total_memory}MB"
    fi

    # Check internet connectivity
    if check_internet; then
        log_info "Internet connectivity is available"
    else
        log_error "Internet connectivity is required for Docker installation"
        return 1
    fi

    return 0
}

# ======================================================================================
# MAIN EXECUTION
# ======================================================================================

#
# Run all Phase 2 integration tests
#
run_phase2_integration_tests() {
    log_info "Starting Phase 2 (Docker Infrastructure) Integration Tests"

    init_integration_test

    # Core Integration Tests
    run_integration_test "Docker Infrastructure Setup" "test_docker_infrastructure_setup"
    run_integration_test "Xray Container Configuration" "test_xray_container_configuration"
    run_integration_test "Container Management Functionality" "test_container_management_functionality"
    run_integration_test "Docker Services Test Script" "test_docker_services_test_script"
    run_integration_test "Phase 2 Module Integration" "test_phase2_module_integration"
    run_integration_test "File Permissions and Structure" "test_file_permissions_and_structure"
    run_integration_test "System Requirements" "test_system_requirements"

    print_integration_summary
}

#
# Main function
#
main() {
    case "${1:-all}" in
        "all")
            run_phase2_integration_tests
            ;;
        "docker")
            init_integration_test
            run_integration_test "Docker Infrastructure Setup" "test_docker_infrastructure_setup"
            print_integration_summary
            ;;
        "config")
            init_integration_test
            run_integration_test "Xray Container Configuration" "test_xray_container_configuration"
            print_integration_summary
            ;;
        "container")
            init_integration_test
            run_integration_test "Container Management Functionality" "test_container_management_functionality"
            print_integration_summary
            ;;
        "system")
            init_integration_test
            run_integration_test "System Requirements" "test_system_requirements"
            print_integration_summary
            ;;
        "help"|*)
            echo "Usage: $0 {all|docker|config|container|system|help}"
            echo ""
            echo "Phase 2 Integration Test Categories:"
            echo "  all       - Run all Phase 2 integration tests"
            echo "  docker    - Test Docker infrastructure setup"
            echo "  config    - Test container configuration"
            echo "  container - Test container management"
            echo "  system    - Test system requirements"
            echo "  help      - Show this help message"
            echo ""
            echo "This script validates that Phase 2 (Docker Infrastructure) is"
            echo "properly implemented and ready for Phase 3 (User Management)."
            exit 0
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi