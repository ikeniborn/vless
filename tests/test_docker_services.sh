#!/bin/bash
# ======================================================================================
# VLESS+Reality VPN Management System - Docker Services Test Script
# ======================================================================================
# This script tests Docker installation, container management, and Xray functionality.
# It validates Phase 2 implementation components.
#
# Author: Claude Code
# Version: 1.0
# Last Modified: 2025-09-21
# ======================================================================================

set -euo pipefail

# Test configuration
readonly TEST_NAME="Docker Services Test"
readonly TEST_VERSION="1.0"
readonly TEST_LOG="/tmp/vless_docker_test.log"

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=modules/common_utils.sh
source "${PROJECT_ROOT}/modules/common_utils.sh"
# shellcheck source=modules/docker_setup.sh
source "${PROJECT_ROOT}/modules/docker_setup.sh"
# shellcheck source=modules/container_management.sh
source "${PROJECT_ROOT}/modules/container_management.sh"

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# ======================================================================================
# TEST FRAMEWORK FUNCTIONS
# ======================================================================================

#
# Initialize test environment
#
init_test_environment() {
    log_info "Initializing test environment for ${TEST_NAME}"

    # Create test log
    touch "${TEST_LOG}"

    # Ensure test directories exist
    mkdir -p "${VLESS_ROOT}/config"
    mkdir -p "${VLESS_ROOT}/logs"
    mkdir -p "${VLESS_ROOT}/data"

    # Copy test configurations if needed
    if [[ -f "${PROJECT_ROOT}/config/docker-compose.yml" ]]; then
        cp "${PROJECT_ROOT}/config/docker-compose.yml" "${VLESS_ROOT}/config/"
    fi

    if [[ -f "${PROJECT_ROOT}/config/xray_config_template.json" ]]; then
        cp "${PROJECT_ROOT}/config/xray_config_template.json" "${VLESS_ROOT}/config/"
    fi

    log_info "Test environment initialized"
}

#
# Run a test and track results
#
# Arguments:
#   $1 - Test name
#   $2 - Test function
#
run_test() {
    local test_name="$1"
    local test_function="$2"

    ((TESTS_TOTAL++))

    log_info "Running test: ${test_name}"
    echo "Test ${TESTS_TOTAL}: ${test_name}" >> "${TEST_LOG}"

    if ${test_function} >> "${TEST_LOG}" 2>&1; then
        ((TESTS_PASSED++))
        log_info "✓ PASSED: ${test_name}"
        echo "RESULT: PASSED" >> "${TEST_LOG}"
    else
        ((TESTS_FAILED++))
        log_error "✗ FAILED: ${test_name}"
        echo "RESULT: FAILED" >> "${TEST_LOG}"
    fi

    echo "----------------------------------------" >> "${TEST_LOG}"
}

#
# Print test summary
#
print_test_summary() {
    echo ""
    log_info "Test Summary for ${TEST_NAME}"
    echo "======================================"
    echo "Total Tests: ${TESTS_TOTAL}"
    echo "Passed: ${TESTS_PASSED}"
    echo "Failed: ${TESTS_FAILED}"
    echo "Success Rate: $(( (TESTS_PASSED * 100) / TESTS_TOTAL ))%"
    echo "======================================"
    echo "Detailed log: ${TEST_LOG}"
    echo ""

    if [[ ${TESTS_FAILED} -eq 0 ]]; then
        log_info "All tests passed successfully!"
        return 0
    else
        log_error "${TESTS_FAILED} test(s) failed"
        return 1
    fi
}

# ======================================================================================
# DOCKER INSTALLATION TESTS
# ======================================================================================

#
# Test Docker installation detection
#
test_docker_installation_check() {
    echo "Testing Docker installation detection..."

    # Test check function
    if check_docker_installed; then
        echo "Docker installation check: PASSED"
        return 0
    else
        echo "Docker installation check: Docker not found or insufficient version"
        return 1
    fi
}

#
# Test Docker Compose installation detection
#
test_docker_compose_check() {
    echo "Testing Docker Compose installation detection..."

    if check_docker_compose_installed; then
        echo "Docker Compose installation check: PASSED"
        return 0
    else
        echo "Docker Compose installation check: FAILED"
        return 1
    fi
}

#
# Test Docker daemon configuration
#
test_docker_daemon_config() {
    echo "Testing Docker daemon configuration..."

    # Check if Docker daemon is running
    if systemctl is-active docker &>/dev/null; then
        echo "Docker daemon is running: PASSED"
    else
        echo "Docker daemon is not running: FAILED"
        return 1
    fi

    # Test Docker info command
    if docker info &>/dev/null; then
        echo "Docker daemon communication: PASSED"
    else
        echo "Docker daemon communication: FAILED"
        return 1
    fi

    return 0
}

# ======================================================================================
# DOCKER COMPOSE CONFIGURATION TESTS
# ======================================================================================

#
# Test Docker Compose file validation
#
test_compose_file_validation() {
    echo "Testing Docker Compose file validation..."

    local compose_file="${VLESS_ROOT}/config/docker-compose.yml"

    if [[ ! -f "${compose_file}" ]]; then
        echo "Docker Compose file not found: ${compose_file}"
        return 1
    fi

    # Validate YAML syntax
    export VLESS_ROOT
    if docker compose -f "${compose_file}" config --quiet; then
        echo "Docker Compose file syntax: PASSED"
    else
        echo "Docker Compose file syntax: FAILED"
        return 1
    fi

    # Check required services
    if docker compose -f "${compose_file}" config | grep -q "xray:"; then
        echo "Xray service definition: PASSED"
    else
        echo "Xray service definition: MISSING"
        return 1
    fi

    return 0
}

#
# Test Xray configuration template
#
test_xray_config_template() {
    echo "Testing Xray configuration template..."

    local config_file="${VLESS_ROOT}/config/xray_config_template.json"

    if [[ ! -f "${config_file}" ]]; then
        echo "Xray configuration template not found: ${config_file}"
        return 1
    fi

    # Validate JSON syntax
    if python3 -m json.tool "${config_file}" > /dev/null 2>&1; then
        echo "Xray configuration JSON syntax: PASSED"
    else
        echo "Xray configuration JSON syntax: FAILED"
        return 1
    fi

    # Check for required sections
    local required_sections=("inbounds" "outbounds" "routing" "log")

    for section in "${required_sections[@]}"; do
        if grep -q "\"${section}\":" "${config_file}"; then
            echo "Required section '${section}': FOUND"
        else
            echo "Required section '${section}': MISSING"
            return 1
        fi
    done

    return 0
}

# ======================================================================================
# CONTAINER MANAGEMENT TESTS
# ======================================================================================

#
# Test container management module loading
#
test_container_management_module() {
    echo "Testing container management module..."

    # Test if functions are available
    local required_functions=(
        "start_xray_container"
        "stop_xray_container"
        "restart_xray_container"
        "check_container_health"
        "get_container_logs"
    )

    for func in "${required_functions[@]}"; do
        if declare -f "${func}" &>/dev/null; then
            echo "Function '${func}': AVAILABLE"
        else
            echo "Function '${func}': MISSING"
            return 1
        fi
    done

    return 0
}

#
# Test Docker network functionality
#
test_docker_network() {
    echo "Testing Docker network functionality..."

    # Test basic Docker networking
    if docker network ls &>/dev/null; then
        echo "Docker network command: PASSED"
    else
        echo "Docker network command: FAILED"
        return 1
    fi

    # Check if default bridge network exists
    if docker network ls | grep -q "bridge"; then
        echo "Default bridge network: EXISTS"
    else
        echo "Default bridge network: MISSING"
        return 1
    fi

    return 0
}

#
# Test Docker volume functionality
#
test_docker_volumes() {
    echo "Testing Docker volume functionality..."

    # Test volume command
    if docker volume ls &>/dev/null; then
        echo "Docker volume command: PASSED"
    else
        echo "Docker volume command: FAILED"
        return 1
    fi

    # Test creating temporary volume
    local test_volume="vless_test_volume_$$"

    if docker volume create "${test_volume}" &>/dev/null; then
        echo "Volume creation: PASSED"

        # Clean up test volume
        docker volume rm "${test_volume}" &>/dev/null || true
    else
        echo "Volume creation: FAILED"
        return 1
    fi

    return 0
}

# ======================================================================================
# INTEGRATION TESTS
# ======================================================================================

#
# Test container configuration validation
#
test_container_config_validation() {
    echo "Testing container configuration validation..."

    # Test validation functions
    if validate_compose_file; then
        echo "Compose file validation function: PASSED"
    else
        echo "Compose file validation function: FAILED"
        return 1
    fi

    return 0
}

#
# Test dry-run container operations
#
test_dry_run_container_operations() {
    echo "Testing dry-run container operations..."

    # Test Docker Compose config generation
    export VLESS_ROOT
    local compose_file="${VLESS_ROOT}/config/docker-compose.yml"

    if docker compose -f "${compose_file}" config &>/dev/null; then
        echo "Docker Compose config generation: PASSED"
    else
        echo "Docker Compose config generation: FAILED"
        return 1
    fi

    return 0
}

#
# Test system requirements for containers
#
test_system_requirements() {
    echo "Testing system requirements for containers..."

    # Check available disk space
    local available_space
    available_space=$(df /var/lib/docker 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")

    if [[ ${available_space} -gt 1048576 ]]; then  # 1GB in KB
        echo "Available disk space: SUFFICIENT ($(( available_space / 1024 / 1024 ))GB)"
    else
        echo "Available disk space: INSUFFICIENT"
        return 1
    fi

    # Check memory
    local available_memory
    available_memory=$(free -m | awk 'NR==2{print $7}')

    if [[ ${available_memory} -gt 256 ]]; then
        echo "Available memory: SUFFICIENT (${available_memory}MB)"
    else
        echo "Available memory: INSUFFICIENT"
        return 1
    fi

    return 0
}

# ======================================================================================
# SECURITY TESTS
# ======================================================================================

#
# Test Docker security configuration
#
test_docker_security() {
    echo "Testing Docker security configuration..."

    # Check if Docker daemon is running as root
    local docker_user
    docker_user=$(ps -eo user,comm | grep dockerd | awk '{print $1}' | head -1)

    if [[ "${docker_user}" == "root" ]]; then
        echo "Docker daemon user: CORRECT (root)"
    else
        echo "Docker daemon user: INCORRECT (${docker_user})"
        return 1
    fi

    # Check Docker socket permissions
    if [[ -S /var/run/docker.sock ]]; then
        local socket_perms
        socket_perms=$(stat -c %a /var/run/docker.sock)
        echo "Docker socket permissions: ${socket_perms}"
    fi

    return 0
}

# ======================================================================================
# PERFORMANCE TESTS
# ======================================================================================

#
# Test Docker performance
#
test_docker_performance() {
    echo "Testing Docker performance..."

    # Test image pull performance
    local start_time
    start_time=$(date +%s)

    if docker pull alpine:latest &>/dev/null; then
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))

        echo "Image pull performance: ${duration} seconds"

        # Clean up test image
        docker rmi alpine:latest &>/dev/null || true

        return 0
    else
        echo "Image pull test: FAILED"
        return 1
    fi
}

# ======================================================================================
# MAIN TEST EXECUTION
# ======================================================================================

#
# Run all Docker service tests
#
run_all_tests() {
    log_info "Starting ${TEST_NAME} v${TEST_VERSION}"

    init_test_environment

    # Docker Installation Tests
    run_test "Docker Installation Check" "test_docker_installation_check"
    run_test "Docker Compose Check" "test_docker_compose_check"
    run_test "Docker Daemon Configuration" "test_docker_daemon_config"

    # Configuration Tests
    run_test "Docker Compose File Validation" "test_compose_file_validation"
    run_test "Xray Configuration Template" "test_xray_config_template"

    # Container Management Tests
    run_test "Container Management Module" "test_container_management_module"
    run_test "Docker Network Functionality" "test_docker_network"
    run_test "Docker Volume Functionality" "test_docker_volumes"

    # Integration Tests
    run_test "Container Configuration Validation" "test_container_config_validation"
    run_test "Dry-run Container Operations" "test_dry_run_container_operations"
    run_test "System Requirements" "test_system_requirements"

    # Security Tests
    run_test "Docker Security Configuration" "test_docker_security"

    # Performance Tests
    run_test "Docker Performance" "test_docker_performance"

    print_test_summary
}

#
# Main execution function
#
main() {
    case "${1:-all}" in
        "all")
            run_all_tests
            ;;
        "docker")
            init_test_environment
            run_test "Docker Installation Check" "test_docker_installation_check"
            run_test "Docker Compose Check" "test_docker_compose_check"
            run_test "Docker Daemon Configuration" "test_docker_daemon_config"
            print_test_summary
            ;;
        "config")
            init_test_environment
            run_test "Docker Compose File Validation" "test_compose_file_validation"
            run_test "Xray Configuration Template" "test_xray_config_template"
            print_test_summary
            ;;
        "container")
            init_test_environment
            run_test "Container Management Module" "test_container_management_module"
            run_test "Docker Network Functionality" "test_docker_network"
            run_test "Docker Volume Functionality" "test_docker_volumes"
            print_test_summary
            ;;
        "security")
            init_test_environment
            run_test "Docker Security Configuration" "test_docker_security"
            print_test_summary
            ;;
        "help"|*)
            echo "Usage: $0 {all|docker|config|container|security|help}"
            echo ""
            echo "Test Categories:"
            echo "  all       - Run all Docker service tests"
            echo "  docker    - Test Docker installation and daemon"
            echo "  config    - Test configuration files"
            echo "  container - Test container management"
            echo "  security  - Test security configuration"
            echo "  help      - Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 all      # Run complete test suite"
            echo "  $0 docker   # Test only Docker installation"
            echo "  $0 config   # Test only configuration files"
            exit 0
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Ensure running as root for some tests
    if [[ ${EUID} -ne 0 ]]; then
        echo "Warning: Some tests require root privileges for accurate results"
        echo "Consider running with: sudo $0 $*"
        echo ""
    fi

    main "$@"
fi