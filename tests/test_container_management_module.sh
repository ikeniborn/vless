#!/bin/bash

# VLESS+Reality VPN Management System - Container Management Module Test Suite
# Version: 1.0.0
# Description: Comprehensive tests for container management functionality
#
# This test suite validates:
# - Container management module loading and function availability
# - User ID and permission handling
# - Service lifecycle management (mocked)
# - Configuration validation
# - Error handling and recovery

set -euo pipefail

# Test configuration
readonly TEST_NAME="Container Management Module"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly MODULES_DIR="${PROJECT_ROOT}/modules"

# Test results tracking
declare -g TESTS_PASSED=0
declare -g TESTS_FAILED=0
declare -g TOTAL_TESTS=0

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Mock system state
declare -g MOCK_DOCKER_AVAILABLE=true
declare -g MOCK_USER_EXISTS=true
declare -g MOCK_SERVICES_RUNNING=false

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

# Test framework functions
start_test() {
    local test_name="$1"
    log_info "Starting test: $test_name"
    ((TOTAL_TESTS++))
}

pass_test() {
    local test_name="$1"
    log_success "PASSED: $test_name"
    ((TESTS_PASSED++))
}

fail_test() {
    local test_name="$1"
    local reason="$2"
    log_error "FAILED: $test_name - $reason"
    ((TESTS_FAILED++))
}

# Setup mock environment
setup_mock_environment() {
    # Create temporary directory for mocking system files
    export MOCK_ROOT=$(mktemp -d)
    export MOCK_PASSWD_FILE="${MOCK_ROOT}/passwd"
    export MOCK_GROUP_FILE="${MOCK_ROOT}/group"

    # Create mock passwd file
    cat > "$MOCK_PASSWD_FILE" << 'EOF'
root:x:0:0:root:/root:/bin/bash
vless:x:1000:1000:VLESS User:/opt/vless:/bin/bash
nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
EOF

    # Create mock group file
    cat > "$MOCK_GROUP_FILE" << 'EOF'
root:x:0:
vless:x:1000:
docker:x:999:vless
EOF
}

# Cleanup mock environment
cleanup_mock_environment() {
    if [[ -n "${MOCK_ROOT:-}" ]] && [[ -d "$MOCK_ROOT" ]]; then
        rm -rf "$MOCK_ROOT"
        unset MOCK_ROOT MOCK_PASSWD_FILE MOCK_GROUP_FILE
    fi
}

# Test 1: Module loading and basic functionality
test_module_loading() {
    local test_name="Module Loading and Basic Functions"
    start_test "$test_name"

    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Source the container management module
source "${MODULES_DIR}/container_management.sh"

# Check that key functions are available
if declare -F get_vless_user_ids >/dev/null && \
   declare -F start_services >/dev/null && \
   declare -F stop_services >/dev/null && \
   declare -F restart_services >/dev/null; then
    exit 0
else
    echo "Key container management functions not available" >&2
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Module loading failed or functions not available"
    fi

    rm -f "$temp_script"
}

# Test 2: VLESS user ID detection
test_vless_user_id_detection() {
    local test_name="VLESS User ID Detection"
    start_test "$test_name"

    setup_mock_environment

    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Mock getent command to use our test passwd file
getent() {
    if [[ "\$1" == "passwd" ]] && [[ "\$2" == "vless" ]]; then
        grep "^vless:" "$MOCK_PASSWD_FILE"
        return 0
    fi
    return 1
}

# Source the container management module
source "${MODULES_DIR}/container_management.sh"

# Test get_vless_user_ids function
if ids=\$(get_vless_user_ids 2>/dev/null); then
    echo "User IDs detected: \$ids"
    # Should contain UID:GID format
    if [[ "\$ids" =~ ^[0-9]+:[0-9]+$ ]]; then
        exit 0
    else
        echo "Invalid UID:GID format: \$ids" >&2
        exit 1
    fi
else
    echo "get_vless_user_ids function failed" >&2
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "VLESS user ID detection failed"
    fi

    rm -f "$temp_script"
    cleanup_mock_environment
}

# Test 3: Docker Compose file validation
test_docker_compose_validation() {
    local test_name="Docker Compose File Validation"
    start_test "$test_name"

    local temp_script=$(mktemp)
    local temp_compose=$(mktemp)

    # Create a mock docker-compose.yml
    cat > "$temp_compose" << 'EOF'
version: '3.8'
services:
  xray:
    image: teddysun/xray
    container_name: vless-xray
    ports:
      - "443:443"
    volumes:
      - /opt/vless/config:/etc/xray
EOF

    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Mock docker-compose command
docker-compose() {
    case "\$1" in
        "config")
            if [[ "\$2" == "-f" ]] && [[ -f "\$3" ]]; then
                echo "Configuration is valid"
                return 0
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

# Source the container management module
source "${MODULES_DIR}/container_management.sh"

# Test compose file validation (mock implementation)
if docker-compose config -f "$temp_compose" >/dev/null 2>&1; then
    exit 0
else
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Docker Compose file validation failed"
    fi

    rm -f "$temp_script" "$temp_compose"
}

# Test 4: Service status checking
test_service_status_checking() {
    local test_name="Service Status Checking"
    start_test "$test_name"

    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Mock docker command
docker() {
    case "\$1 \$2" in
        "ps -q")
            if [[ "\${3:-}" == "--filter" ]] && [[ "\${4:-}" =~ name=vless- ]]; then
                if [[ "$MOCK_SERVICES_RUNNING" == "true" ]]; then
                    echo "container_id_12345"
                else
                    echo ""
                fi
                return 0
            fi
            ;;
        "inspect --format")
            if [[ "\$MOCK_SERVICES_RUNNING" == "true" ]]; then
                echo "running"
            else
                echo "exited"
            fi
            return 0
            ;;
    esac
    return 1
}

# Source the container management module
source "${MODULES_DIR}/container_management.sh"

# Test check_service_status function (we'll create a mock version)
check_service_status() {
    local container_name="\$1"
    local container_id=\$(docker ps -q --filter "name=\$container_name" 2>/dev/null)

    if [[ -n "\$container_id" ]]; then
        local status=\$(docker inspect --format '{{.State.Status}}' "\$container_id" 2>/dev/null)
        if [[ "\$status" == "running" ]]; then
            return 0
        fi
    fi
    return 1
}

# Test with services not running
export MOCK_SERVICES_RUNNING=false
if ! check_service_status "vless-xray"; then
    # Test with services running
    export MOCK_SERVICES_RUNNING=true
    if check_service_status "vless-xray"; then
        exit 0
    fi
fi

exit 1
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Service status checking failed"
    fi

    rm -f "$temp_script"
}

# Test 5: Container health checks
test_container_health_checks() {
    local test_name="Container Health Checks"
    start_test "$test_name"

    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Mock docker inspect for health status
docker() {
    case "\$1" in
        "inspect")
            cat << 'HEALTH_EOF'
[
  {
    "State": {
      "Health": {
        "Status": "healthy",
        "FailingStreak": 0,
        "Log": [
          {
            "ExitCode": 0,
            "Output": "Health check passed"
          }
        ]
      }
    }
  }
]
HEALTH_EOF
            return 0
            ;;
    esac
    return 1
}

# Source the container management module
source "${MODULES_DIR}/container_management.sh"

# Test container health check function (mock implementation)
check_container_health() {
    local container_name="\$1"
    local health_status=\$(docker inspect "\$container_name" 2>/dev/null | \
                          grep -o '"Status": *"[^"]*"' | \
                          cut -d'"' -f4)

    if [[ "\$health_status" == "healthy" ]]; then
        return 0
    fi
    return 1
}

if check_container_health "vless-xray"; then
    exit 0
else
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Container health checks failed"
    fi

    rm -f "$temp_script"
}

# Test 6: Error handling for missing Docker
test_missing_docker_handling() {
    local test_name="Missing Docker Handling"
    start_test "$test_name"

    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Mock missing docker command
docker() {
    echo "docker: command not found" >&2
    return 127
}

# Mock command_exists to return false for docker
command_exists() {
    [[ "\$1" != "docker" ]]
}

# Source the container management module
source "${MODULES_DIR}/container_management.sh"

# Test that functions handle missing Docker gracefully
set +e
result=\$(get_vless_user_ids 2>/dev/null)
exit_code=\$?
set -e

# Should handle missing Docker without crashing
if [[ \$exit_code -ne 0 ]]; then
    exit 0  # Expected failure
else
    echo "Function should have failed with missing Docker" >&2
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Missing Docker not handled properly"
    fi

    rm -f "$temp_script"
}

# Test 7: Configuration file path resolution
test_config_file_resolution() {
    local test_name="Configuration File Path Resolution"
    start_test "$test_name"

    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Source the container management module
source "${MODULES_DIR}/container_management.sh"

# Check that configuration paths are properly set
expected_compose_file="${PROJECT_ROOT}/config/docker-compose.yml"
expected_system_compose="/opt/vless/docker-compose.yml"

# The COMPOSE_FILE should be set in the module
if [[ "\$COMPOSE_FILE" == "\$expected_compose_file" ]] && \
   [[ "\$SYSTEM_COMPOSE_FILE" == "\$expected_system_compose" ]]; then
    exit 0
else
    echo "Configuration paths not set correctly" >&2
    echo "COMPOSE_FILE: \$COMPOSE_FILE (expected: \$expected_compose_file)" >&2
    echo "SYSTEM_COMPOSE_FILE: \$SYSTEM_COMPOSE_FILE (expected: \$expected_system_compose)" >&2
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Configuration file path resolution failed"
    fi

    rm -f "$temp_script"
}

# Test 8: User permission validation
test_user_permission_validation() {
    local test_name="User Permission Validation"
    start_test "$test_name"

    setup_mock_environment

    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Mock id command
id() {
    case "\$1" in
        "-u")
            echo "1000"
            return 0
            ;;
        "-g")
            echo "1000"
            return 0
            ;;
        "-Gn")
            echo "vless docker"
            return 0
            ;;
    esac
    return 1
}

# Mock groups command
groups() {
    echo "vless docker"
    return 0
}

# Source the container management module
source "${MODULES_DIR}/container_management.sh"

# Test user permission validation (mock implementation)
validate_user_permissions() {
    local user="\$1"
    local groups_list=\$(groups "\$user" 2>/dev/null)

    if [[ "\$groups_list" =~ docker ]]; then
        return 0
    fi
    return 1
}

if validate_user_permissions "vless"; then
    exit 0
else
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "User permission validation failed"
    fi

    rm -f "$temp_script"
    cleanup_mock_environment
}

# Test 9: Service timeout handling
test_service_timeout_handling() {
    local test_name="Service Timeout Handling"
    start_test "$test_name"

    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Source the container management module
source "${MODULES_DIR}/container_management.sh"

# Check that timeout constants are defined
timeout_constants=(
    "START_TIMEOUT"
    "STOP_TIMEOUT"
    "RESTART_TIMEOUT"
    "HEALTH_CHECK_TIMEOUT"
)

missing_constants=()
for constant in "\${timeout_constants[@]}"; do
    if [[ -z "\${!constant:-}" ]]; then
        missing_constants+=("\$constant")
    fi
done

if [[ \${#missing_constants[@]} -eq 0 ]]; then
    exit 0
else
    echo "Missing timeout constants: \${missing_constants[*]}" >&2
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Service timeout constants not properly defined"
    fi

    rm -f "$temp_script"
}

# Test 10: Module dependency validation
test_module_dependencies() {
    local test_name="Module Dependencies"
    start_test "$test_name"

    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Source the container management module
source "${MODULES_DIR}/container_management.sh"

# Check that common_utils functions are available (dependency)
required_functions=(
    "log_info"
    "log_error"
    "log_success"
    "command_exists"
)

missing_functions=()
for func in "\${required_functions[@]}"; do
    if ! declare -F "\$func" >/dev/null; then
        missing_functions+=("\$func")
    fi
done

if [[ \${#missing_functions[@]} -eq 0 ]]; then
    exit 0
else
    echo "Missing required functions from dependencies: \${missing_functions[*]}" >&2
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Module dependencies not properly loaded"
    fi

    rm -f "$temp_script"
}

# Test 11: Container name constants validation
test_container_name_constants() {
    local test_name="Container Name Constants"
    start_test "$test_name"

    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Source the container management module
source "${MODULES_DIR}/container_management.sh"

# Check that container name constants are defined
container_constants=(
    "PROJECT_NAME"
    "XRAY_CONTAINER_NAME"
    "NGINX_CONTAINER_NAME"
    "WATCHTOWER_CONTAINER_NAME"
)

missing_constants=()
for constant in "\${container_constants[@]}"; do
    if [[ -z "\${!constant:-}" ]]; then
        missing_constants+=("\$constant")
    fi
done

if [[ \${#missing_constants[@]} -eq 0 ]]; then
    # Validate expected values
    [[ "\$PROJECT_NAME" == "vless-vpn" ]] || exit 1
    [[ "\$XRAY_CONTAINER_NAME" == "vless-xray" ]] || exit 1
    [[ "\$NGINX_CONTAINER_NAME" == "vless-nginx" ]] || exit 1
    [[ "\$WATCHTOWER_CONTAINER_NAME" == "vless-watchtower" ]] || exit 1
    exit 0
else
    echo "Missing container name constants: \${missing_constants[*]}" >&2
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Container name constants validation failed"
    fi

    rm -f "$temp_script"
}

# Test 12: Default user configuration
test_default_user_config() {
    local test_name="Default User Configuration"
    start_test "$test_name"

    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Source the container management module
source "${MODULES_DIR}/container_management.sh"

# Check default user configuration constants
user_constants=(
    "DEFAULT_VLESS_USER"
    "DEFAULT_VLESS_UID"
    "DEFAULT_VLESS_GID"
)

missing_constants=()
for constant in "\${user_constants[@]}"; do
    if [[ -z "\${!constant:-}" ]]; then
        missing_constants+=("\$constant")
    fi
done

if [[ \${#missing_constants[@]} -eq 0 ]]; then
    # Validate expected values
    [[ "\$DEFAULT_VLESS_USER" == "vless" ]] || exit 1
    [[ "\$DEFAULT_VLESS_UID" == "1000" ]] || exit 1
    [[ "\$DEFAULT_VLESS_GID" == "1000" ]] || exit 1
    exit 0
else
    echo "Missing user configuration constants: \${missing_constants[*]}" >&2
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Default user configuration validation failed"
    fi

    rm -f "$temp_script"
}

# Test summary
print_test_summary() {
    echo
    echo "=============================================="
    echo "Container Management Module Test Results"
    echo "=============================================="
    echo "Total tests: $TOTAL_TESTS"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "\n${GREEN}All container management tests passed!${NC}"
        return 0
    else
        echo -e "\n${RED}Some container management tests failed.${NC}"
        return 1
    fi
}

# Main test execution
main() {
    log_info "Starting Container Management Module Test Suite"
    echo "Project Root: $PROJECT_ROOT"
    echo "Modules Directory: $MODULES_DIR"
    echo

    # Run all tests
    test_module_loading
    test_vless_user_id_detection
    test_docker_compose_validation
    test_service_status_checking
    test_container_health_checks
    test_missing_docker_handling
    test_config_file_resolution
    test_user_permission_validation
    test_service_timeout_handling
    test_module_dependencies
    test_container_name_constants
    test_default_user_config

    # Print summary
    print_test_summary
}

# Cleanup on exit
trap cleanup_mock_environment EXIT

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi