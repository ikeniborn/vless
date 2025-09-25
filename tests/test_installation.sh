#!/bin/bash
set -euo pipefail

# VLESS+Reality VPN Service - Docker Installation Test Suite
# Version: 1.0.0
# Description: Comprehensive testing for Docker and Docker Compose installation
# Author: VLESS Testing Team

#######################################################################################
# TEST CONSTANTS AND CONFIGURATION
#######################################################################################

readonly TEST_SCRIPT_NAME="test_installation"
readonly TEST_VERSION="1.0.0"
readonly TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$TEST_ROOT")"
readonly VLESS_MANAGER="$PROJECT_ROOT/vless-manager.sh"

# Test results tracking
declare -i TOTAL_TESTS=0
declare -i PASSED_TESTS=0
declare -i FAILED_TESTS=0
declare -a FAILED_TEST_NAMES=()

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Test environment paths
readonly MOCK_DOCKER_VERSION="Docker version 20.10.17, build 100c701"
readonly MOCK_COMPOSE_VERSION="v2.12.2"

#######################################################################################
# TEST UTILITY FUNCTIONS
#######################################################################################

# Test logging function
test_log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%H:%M:%S')

    case "$level" in
        "INFO")
            echo -e "${BLUE}[INST-INFO]${NC} ${timestamp} - $message"
            ;;
        "PASS")
            echo -e "${GREEN}[INST-PASS]${NC} ${timestamp} - $message"
            ;;
        "FAIL")
            echo -e "${RED}[INST-FAIL]${NC} ${timestamp} - $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[INST-WARN]${NC} ${timestamp} - $message"
            ;;
    esac
}

# Test assertion functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="${3:-Assertion}"

    ((TOTAL_TESTS++))

    if [[ "$expected" == "$actual" ]]; then
        test_log "PASS" "$test_name: Expected '$expected', got '$actual'"
        ((PASSED_TESTS++))
        return 0
    else
        test_log "FAIL" "$test_name: Expected '$expected', got '$actual'"
        FAILED_TEST_NAMES+=("$test_name")
        ((FAILED_TESTS++))
        return 1
    fi
}

assert_return_code() {
    local expected_code="$1"
    local actual_code="$2"
    local test_name="${3:-Return Code}"

    ((TOTAL_TESTS++))

    if [[ "$expected_code" == "$actual_code" ]]; then
        test_log "PASS" "$test_name: Expected return code $expected_code"
        ((PASSED_TESTS++))
        return 0
    else
        test_log "FAIL" "$test_name: Expected return code $expected_code, got $actual_code"
        FAILED_TEST_NAMES+=("$test_name")
        ((FAILED_TESTS++))
        return 1
    fi
}

assert_output_contains() {
    local expected_text="$1"
    local actual_output="$2"
    local test_name="${3:-Output Contains}"

    ((TOTAL_TESTS++))

    if [[ "$actual_output" =~ $expected_text ]]; then
        test_log "PASS" "$test_name: Output contains '$expected_text'"
        ((PASSED_TESTS++))
        return 0
    else
        test_log "FAIL" "$test_name: Output does not contain '$expected_text'"
        FAILED_TEST_NAMES+=("$test_name")
        ((FAILED_TESTS++))
        return 1
    fi
}

assert_command_called() {
    local expected_command="$1"
    local log_file="$2"
    local test_name="${3:-Command Called}"

    ((TOTAL_TESTS++))

    if grep -q "$expected_command" "$log_file" 2>/dev/null; then
        test_log "PASS" "$test_name: Command '$expected_command' was called"
        ((PASSED_TESTS++))
        return 0
    else
        test_log "FAIL" "$test_name: Command '$expected_command' was not called"
        FAILED_TEST_NAMES+=("$test_name")
        ((FAILED_TESTS++))
        return 1
    fi
}

#######################################################################################
# MOCK SYSTEM FUNCTIONS
#######################################################################################

# Mock apt-get command
mock_apt_get() {
    local action="$1"
    shift
    local args="$@"

    echo "mock_apt_get: $action $args" >> "$MOCK_LOG_FILE"

    case "$action" in
        "update")
            echo "Reading package lists... Done"
            ;;
        "install")
            echo "Reading package lists... Done"
            echo "Building dependency tree"
            echo "Reading state information... Done"
            for package in $args; do
                if [[ "$package" != "-y" ]]; then
                    echo "Setting up $package..."
                fi
            done
            echo "Processing triggers..."
            ;;
        *)
            echo "Unknown apt-get action: $action"
            return 1
            ;;
    esac
}

# Mock docker command
mock_docker() {
    local command="$1"
    shift
    local args="$@"

    echo "mock_docker: $command $args" >> "$MOCK_LOG_FILE"

    case "$command" in
        "--version")
            echo "$MOCK_DOCKER_VERSION"
            ;;
        "info")
            echo "Docker daemon is running"
            echo "Server Version: 20.10.17"
            ;;
        "run")
            if [[ "$args" =~ "hello-world" ]]; then
                echo "Hello from Docker!"
                echo "This message shows that your installation appears to be working correctly."
            fi
            ;;
        "compose")
            case "$1" in
                "version")
                    if [[ "${2:-}" == "--short" ]]; then
                        echo "$MOCK_COMPOSE_VERSION"
                    else
                        echo "Docker Compose version $MOCK_COMPOSE_VERSION"
                    fi
                    ;;
                *)
                    echo "Docker Compose command: $1 $2"
                    ;;
            esac
            ;;
        *)
            echo "Unknown docker command: $command"
            return 1
            ;;
    esac
}

# Mock systemctl command
mock_systemctl() {
    local action="$1"
    local service="$2"

    echo "mock_systemctl: $action $service" >> "$MOCK_LOG_FILE"

    case "$action" in
        "start"|"enable"|"restart"|"stop")
            echo "Systemctl: $action $service"
            ;;
        "status")
            echo "● $service - Docker Application Container Engine"
            echo "   Loaded: loaded"
            echo "   Active: active (running)"
            ;;
        *)
            echo "Unknown systemctl action: $action"
            return 1
            ;;
    esac
}

# Mock curl command
mock_curl() {
    local url_or_args="$@"

    echo "mock_curl: $url_or_args" >> "$MOCK_LOG_FILE"

    if [[ "$url_or_args" =~ "download.docker.com" ]]; then
        # Simulate GPG key download
        echo "-----BEGIN PGP PUBLIC KEY BLOCK-----"
        echo "mQINBFit2ioBEADhWpZ8/wvZ6hUTiXOwQHXMAlaFHcPH9hAtr4F1y2+OYdbtMuth"
        echo "-----END PGP PUBLIC KEY BLOCK-----"
    elif [[ "$url_or_args" =~ "icanhazip.com" || "$url_or_args" =~ "ipify.org" ]]; then
        echo "203.0.113.1"
    else
        echo "Mocked curl response"
    fi
}

# Mock command existence check
mock_command() {
    local option="$1"
    local cmd="$2"

    if [[ "$option" == "-v" ]]; then
        case "$cmd" in
            "docker"|"apt-get"|"systemctl"|"curl"|"gpg"|"lsb_release"|"dpkg")
                echo "/usr/bin/$cmd"
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    fi

    # Execute original command for other options
    /usr/bin/command "$@"
}

# Mock other utilities
mock_lsb_release() {
    case "$1" in
        "-is")
            echo "Ubuntu"
            ;;
        "-cs")
            echo "focal"
            ;;
        *)
            echo "Ubuntu 20.04.4 LTS"
            ;;
    esac
}

mock_dpkg() {
    if [[ "$1" == "--print-architecture" ]]; then
        echo "amd64"
    fi
}

mock_gpg() {
    echo "mock_gpg: $@" >> "$MOCK_LOG_FILE"
    echo "GPG operation completed"
}

mock_tee() {
    local target_file="$1"
    echo "mock_tee: writing to $target_file" >> "$MOCK_LOG_FILE"
    cat > /dev/null  # Consume input
}

mock_usermod() {
    echo "mock_usermod: $@" >> "$MOCK_LOG_FILE"
    echo "User modification completed"
}

#######################################################################################
# DOCKER INSTALLATION TESTS
#######################################################################################

test_docker_already_installed() {
    test_log "INFO" "Testing Docker installation when Docker is already installed"

    local test_script="/tmp/test_docker_installed_$$"
    local log_file="/tmp/test_docker_log_$$"

    cat > "$test_script" << EOF
#!/bin/bash
export MOCK_LOG_FILE="$log_file"

# Mock functions
command() { mock_command "\$@"; }
docker() { mock_docker "\$@"; }
systemctl() { mock_systemctl "\$@"; }

export -f mock_command mock_docker mock_systemctl

source "$VLESS_MANAGER"
install_docker
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" 2>&1)
    return_code=$?

    assert_return_code "0" "$return_code" "Docker already installed check"
    assert_output_contains "Docker is already installed" "$output" "Already installed message"
    assert_output_contains "Docker is ready" "$output" "Docker ready message"

    rm -f "$test_script" "$log_file"
}

test_docker_fresh_installation() {
    test_log "INFO" "Testing fresh Docker installation"

    local test_script="/tmp/test_docker_fresh_$$"
    local log_file="/tmp/test_docker_fresh_log_$$"

    cat > "$test_script" << EOF
#!/bin/bash
export MOCK_LOG_FILE="$log_file"
export USER="testuser"
export EUID=1000

# Mock functions to simulate fresh installation
command() {
    if [[ "\$1" == "-v" && "\$2" == "docker" ]]; then
        return 1  # Docker not found
    fi
    mock_command "\$@"
}

docker() {
    # Only respond to version check after "installation"
    if [[ "\$1" == "run" && "\$2" == "--rm" && "\$3" == "hello-world" ]]; then
        mock_docker "\$@"
    else
        mock_docker "\$@"
    fi
}

apt-get() { mock_apt_get "\$@"; }
systemctl() { mock_systemctl "\$@"; }
curl() { mock_curl "\$@"; }
gpg() { mock_gpg "\$@"; }
lsb_release() { mock_lsb_release "\$@"; }
dpkg() { mock_dpkg "\$@"; }
tee() { mock_tee "\$@"; }
usermod() { mock_usermod "\$@"; }

export -f mock_command mock_docker mock_apt_get mock_systemctl mock_curl
export -f mock_gpg mock_lsb_release mock_dpkg mock_tee mock_usermod

source "$VLESS_MANAGER"
install_docker
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" 2>&1)
    return_code=$?

    assert_return_code "0" "$return_code" "Fresh Docker installation"
    assert_output_contains "Installing Docker..." "$output" "Installation start message"
    assert_output_contains "Docker installed and verified successfully" "$output" "Installation success message"

    # Check that required commands were called
    assert_command_called "mock_apt_get: update" "$log_file" "Apt update called"
    assert_command_called "apt-transport-https" "$log_file" "Prerequisites installed"
    assert_command_called "docker-ce" "$log_file" "Docker CE installed"

    rm -f "$test_script" "$log_file"
}

test_docker_installation_verification_failure() {
    test_log "INFO" "Testing Docker installation with verification failure"

    local test_script="/tmp/test_docker_verify_fail_$$"
    local log_file="/tmp/test_docker_verify_fail_log_$$"

    cat > "$test_script" << EOF
#!/bin/bash
export MOCK_LOG_FILE="$log_file"

# Mock functions where hello-world test fails
command() {
    if [[ "\$1" == "-v" && "\$2" == "docker" ]]; then
        return 1  # Docker not found initially
    fi
    mock_command "\$@"
}

docker() {
    if [[ "\$1" == "run" && "\$2" == "--rm" && "\$3" == "hello-world" ]]; then
        return 1  # Simulate verification failure
    else
        mock_docker "\$@"
    fi
}

apt-get() { mock_apt_get "\$@"; }
systemctl() { mock_systemctl "\$@"; }
curl() { mock_curl "\$@"; }
gpg() { mock_gpg "\$@"; }
lsb_release() { mock_lsb_release "\$@"; }
dpkg() { mock_dpkg "\$@"; }
tee() { mock_tee "\$@"; }
usermod() { mock_usermod "\$@"; }

export -f mock_command mock_docker mock_apt_get mock_systemctl mock_curl
export -f mock_gpg mock_lsb_release mock_dpkg mock_tee mock_usermod

source "$VLESS_MANAGER"
install_docker 2>&1
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" 2>&1 || true)
    return_code=$?

    assert_return_code "1" "$return_code" "Docker verification failure should return 1"
    assert_output_contains "Docker installation verification failed" "$output" "Verification failure message"

    rm -f "$test_script" "$log_file"
}

#######################################################################################
# DOCKER COMPOSE INSTALLATION TESTS
#######################################################################################

test_docker_compose_already_installed() {
    test_log "INFO" "Testing Docker Compose when already installed"

    local test_script="/tmp/test_compose_installed_$$"
    local log_file="/tmp/test_compose_log_$$"

    cat > "$test_script" << EOF
#!/bin/bash
export MOCK_LOG_FILE="$log_file"

# Mock docker compose command to simulate existing installation
docker() {
    if [[ "\$1" == "compose" && "\$2" == "version" ]]; then
        if [[ "\${3:-}" == "--short" ]]; then
            echo "$MOCK_COMPOSE_VERSION"
        else
            echo "Docker Compose version $MOCK_COMPOSE_VERSION"
        fi
        return 0
    fi
    mock_docker "\$@"
}

export -f mock_docker

source "$VLESS_MANAGER"
install_docker_compose
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" 2>&1)
    return_code=$?

    assert_return_code "0" "$return_code" "Docker Compose already installed"
    assert_output_contains "Docker Compose is already installed" "$output" "Already installed message"
    assert_output_contains "Docker Compose is ready" "$output" "Compose ready message"

    rm -f "$test_script" "$log_file"
}

test_docker_compose_fresh_installation() {
    test_log "INFO" "Testing fresh Docker Compose installation"

    local test_script="/tmp/test_compose_fresh_$$"
    local log_file="/tmp/test_compose_fresh_log_$$"

    cat > "$test_script" << EOF
#!/bin/bash
export MOCK_LOG_FILE="$log_file"
compose_installed=false

# Mock docker compose to simulate installation
docker() {
    if [[ "\$1" == "compose" && "\$2" == "version" ]]; then
        if [[ "\$compose_installed" == "false" ]]; then
            return 1  # Not installed initially
        else
            if [[ "\${3:-}" == "--short" ]]; then
                echo "$MOCK_COMPOSE_VERSION"
            else
                echo "Docker Compose version $MOCK_COMPOSE_VERSION"
            fi
            return 0
        fi
    fi
    mock_docker "\$@"
}

apt-get() {
    if [[ "\$2" == "docker-compose-plugin" ]]; then
        compose_installed=true
    fi
    mock_apt_get "\$@"
}

export -f mock_docker mock_apt_get
export compose_installed

source "$VLESS_MANAGER"
install_docker_compose
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" 2>&1)
    return_code=$?

    assert_return_code "0" "$return_code" "Fresh Docker Compose installation"
    assert_output_contains "Installing Docker Compose plugin..." "$output" "Installation message"
    assert_output_contains "Docker Compose installed successfully" "$output" "Success message"

    # Check that docker-compose-plugin was installed
    assert_command_called "docker-compose-plugin" "$log_file" "Docker Compose plugin installed"

    rm -f "$test_script" "$log_file"
}

test_docker_compose_verification_failure() {
    test_log "INFO" "Testing Docker Compose installation with verification failure"

    local test_script="/tmp/test_compose_verify_fail_$$"
    local log_file="/tmp/test_compose_verify_fail_log_$$"

    cat > "$test_script" << EOF
#!/bin/bash
export MOCK_LOG_FILE="$log_file"

# Mock docker compose to always fail verification
docker() {
    if [[ "\$1" == "compose" && "\$2" == "version" ]]; then
        return 1  # Always fail version check
    fi
    mock_docker "\$@"
}

apt-get() { mock_apt_get "\$@"; }

export -f mock_docker mock_apt_get

source "$VLESS_MANAGER"
install_docker_compose 2>&1
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" 2>&1 || true)
    return_code=$?

    assert_return_code "1" "$return_code" "Docker Compose verification failure"
    assert_output_contains "Docker Compose installation verification failed" "$output" "Verification failure message"

    rm -f "$test_script" "$log_file"
}

#######################################################################################
# INTEGRATION TESTS
#######################################################################################

test_complete_docker_installation_flow() {
    test_log "INFO" "Testing complete Docker installation flow"

    local test_script="/tmp/test_complete_docker_$$"
    local log_file="/tmp/test_complete_docker_log_$$"

    cat > "$test_script" << EOF
#!/bin/bash
export MOCK_LOG_FILE="$log_file"
export USER="testuser"
export EUID=1000
docker_installed=false
compose_installed=false

# Mock command availability
command() {
    if [[ "\$1" == "-v" ]]; then
        case "\$2" in
            "docker")
                [[ "\$docker_installed" == "true" ]] && return 0 || return 1
                ;;
            *)
                mock_command "\$@"
                ;;
        esac
    else
        mock_command "\$@"
    fi
}

# Mock Docker commands
docker() {
    if [[ "\$1" == "compose" && "\$2" == "version" ]]; then
        if [[ "\$compose_installed" == "true" ]]; then
            if [[ "\${3:-}" == "--short" ]]; then
                echo "$MOCK_COMPOSE_VERSION"
            else
                echo "Docker Compose version $MOCK_COMPOSE_VERSION"
            fi
            return 0
        else
            return 1
        fi
    else
        if [[ "\$docker_installed" == "true" ]]; then
            mock_docker "\$@"
        else
            return 1
        fi
    fi
}

# Mock apt-get to simulate installation
apt-get() {
    if [[ "\$2" == "docker-ce" ]]; then
        docker_installed=true
    elif [[ "\$2" == "docker-compose-plugin" ]]; then
        compose_installed=true
    fi
    mock_apt_get "\$@"
}

systemctl() { mock_systemctl "\$@"; }
curl() { mock_curl "\$@"; }
gpg() { mock_gpg "\$@"; }
lsb_release() { mock_lsb_release "\$@"; }
dpkg() { mock_dpkg "\$@"; }
tee() { mock_tee "\$@"; }
usermod() { mock_usermod "\$@"; }

export -f command docker apt-get systemctl curl gpg lsb_release dpkg tee usermod
export -f mock_command mock_docker mock_apt_get mock_systemctl mock_curl
export -f mock_gpg mock_lsb_release mock_dpkg mock_tee mock_usermod
export docker_installed compose_installed

source "$VLESS_MANAGER"
echo "=== Installing Docker ==="
install_docker
echo "=== Installing Docker Compose ==="
install_docker_compose
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" 2>&1)
    return_code=$?

    assert_return_code "0" "$return_code" "Complete Docker installation flow"
    assert_output_contains "Installing Docker..." "$output" "Docker installation started"
    assert_output_contains "Docker installed and verified successfully" "$output" "Docker installed"
    assert_output_contains "Installing Docker Compose plugin..." "$output" "Compose installation started"
    assert_output_contains "Docker Compose installed successfully" "$output" "Compose installed"

    # Verify installation sequence
    assert_command_called "docker-ce" "$log_file" "Docker CE package installed"
    assert_command_called "docker-compose-plugin" "$log_file" "Docker Compose plugin installed"
    assert_command_called "mock_systemctl: start docker" "$log_file" "Docker service started"
    assert_command_called "mock_systemctl: enable docker" "$log_file" "Docker service enabled"

    rm -f "$test_script" "$log_file"
}

test_docker_daemon_not_running() {
    test_log "INFO" "Testing Docker installation with daemon not running"

    local test_script="/tmp/test_docker_daemon_$$"
    local log_file="/tmp/test_docker_daemon_log_$$"

    cat > "$test_script" << EOF
#!/bin/bash
export MOCK_LOG_FILE="$log_file"
daemon_started=false

# Mock Docker commands
command() { mock_command "\$@"; }

docker() {
    case "\$1" in
        "--version")
            echo "$MOCK_DOCKER_VERSION"
            ;;
        "info")
            if [[ "\$daemon_started" == "false" ]]; then
                return 1  # Daemon not running initially
            else
                mock_docker "\$@"
            fi
            ;;
        *)
            mock_docker "\$@"
            ;;
    esac
}

systemctl() {
    if [[ "\$1" == "start" && "\$2" == "docker" ]]; then
        daemon_started=true
    fi
    mock_systemctl "\$@"
}

export -f command docker systemctl mock_command mock_docker mock_systemctl
export daemon_started

source "$VLESS_MANAGER"
install_docker
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" 2>&1)
    return_code=$?

    assert_return_code "0" "$return_code" "Docker daemon start handling"
    assert_output_contains "Starting Docker daemon..." "$output" "Daemon start message"
    assert_command_called "mock_systemctl: start docker" "$log_file" "Docker daemon started"

    rm -f "$test_script" "$log_file"
}

#######################################################################################
# ERROR HANDLING TESTS
#######################################################################################

test_apt_get_failure() {
    test_log "INFO" "Testing Docker installation with apt-get failure"

    local test_script="/tmp/test_apt_failure_$$"
    local log_file="/tmp/test_apt_failure_log_$$"

    cat > "$test_script" << EOF
#!/bin/bash
export MOCK_LOG_FILE="$log_file"

command() {
    if [[ "\$1" == "-v" && "\$2" == "docker" ]]; then
        return 1  # Docker not found
    fi
    mock_command "\$@"
}

# Mock apt-get to fail on Docker installation
apt-get() {
    if [[ "\$2" == "docker-ce" ]]; then
        echo "E: Unable to locate package docker-ce" >&2
        return 1
    fi
    mock_apt_get "\$@"
}

curl() { mock_curl "\$@"; }
gpg() { mock_gpg "\$@"; }
lsb_release() { mock_lsb_release "\$@"; }
dpkg() { mock_dpkg "\$@"; }
tee() { mock_tee "\$@"; }

export -f command apt-get curl gpg lsb_release dpkg tee
export -f mock_command mock_apt_get mock_curl mock_gpg mock_lsb_release mock_dpkg mock_tee

source "$VLESS_MANAGER"
install_docker 2>&1
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" 2>&1 || true)
    return_code=$?

    assert_return_code "1" "$return_code" "Docker installation with apt-get failure"
    assert_output_contains "Unable to locate package docker-ce" "$output" "Apt-get failure message"

    rm -f "$test_script" "$log_file"
}

test_network_connectivity_failure() {
    test_log "INFO" "Testing Docker installation with network failure"

    local test_script="/tmp/test_network_fail_$$"
    local log_file="/tmp/test_network_fail_log_$$"

    cat > "$test_script" << EOF
#!/bin/bash
export MOCK_LOG_FILE="$log_file"

command() {
    if [[ "\$1" == "-v" && "\$2" == "docker" ]]; then
        return 1  # Docker not found
    fi
    mock_command "\$@"
}

# Mock curl to fail
curl() {
    echo "curl: (7) Failed to connect to download.docker.com port 443: Connection refused" >&2
    return 7
}

apt-get() { mock_apt_get "\$@"; }
gpg() { mock_gpg "\$@"; }
lsb_release() { mock_lsb_release "\$@"; }
dpkg() { mock_dpkg "\$@"; }
tee() { mock_tee "\$@"; }

export -f command curl apt-get gpg lsb_release dpkg tee
export -f mock_command mock_apt_get mock_gpg mock_lsb_release mock_dpkg mock_tee

source "$VLESS_MANAGER"
install_docker 2>&1
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" 2>&1 || true)
    return_code=$?

    assert_return_code "7" "$return_code" "Docker installation with network failure"
    assert_output_contains "Failed to connect" "$output" "Network failure message"

    rm -f "$test_script" "$log_file"
}

#######################################################################################
# TEST REPORT AND EXECUTION
#######################################################################################

# Generate test report
generate_installation_test_report() {
    local report_file="/tmp/vless_installation_test_report_$(date +%Y%m%d_%H%M%S).txt"
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')

    cat > "$report_file" << EOF
================================================================================
VLESS+Reality VPN Service - Docker Installation Test Report
================================================================================

Test Execution Summary:
- Test Suite: Docker and Docker Compose Installation
- Test Version: $TEST_VERSION
- Execution Time: $end_time
- Total Tests: $TOTAL_TESTS
- Passed Tests: $PASSED_TESTS
- Failed Tests: $FAILED_TESTS
- Success Rate: $(( (PASSED_TESTS * 100) / TOTAL_TESTS ))%

Test Categories:
- Docker Installation (Fresh and Existing)
- Docker Compose Installation (Fresh and Existing)
- Installation Verification
- Error Handling and Recovery
- Integration Testing

Tested Scenarios:
✓ Docker already installed detection
✓ Fresh Docker installation process
✓ Docker installation verification
✓ Docker Compose already installed detection
✓ Fresh Docker Compose installation process
✓ Docker Compose installation verification
✓ Complete installation workflow
✓ Docker daemon startup handling
✓ Package manager failure handling
✓ Network connectivity failure handling
✓ Installation command sequence validation

Mock Environment:
- All system commands are mocked for safe testing
- No actual packages are installed
- No system modifications are made
- All network calls are simulated

EOF

    if [[ ${#FAILED_TEST_NAMES[@]} -gt 0 ]]; then
        cat >> "$report_file" << EOF
Failed Tests:
EOF
        for test_name in "${FAILED_TEST_NAMES[@]}"; do
            echo "  - $test_name" >> "$report_file"
        done
        echo >> "$report_file"
    fi

    echo "$report_file"
}

# Main test execution
run_installation_tests() {
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')

    echo
    echo -e "${BLUE}================================================================================${NC}"
    echo -e "${GREEN}     VLESS+Reality VPN - Docker Installation Test Suite${NC}"
    echo -e "${BLUE}================================================================================${NC}"
    echo -e "${WHITE}Version: $TEST_VERSION${NC}"
    echo -e "${WHITE}Start Time: $start_time${NC}"
    echo -e "${BLUE}================================================================================${NC}"
    echo

    # Set up mock environment
    export MOCK_LOG_FILE="/tmp/vless_installation_mock_$$.log"
    > "$MOCK_LOG_FILE"  # Clear log file

    # Export mock functions
    export -f mock_apt_get mock_docker mock_systemctl mock_curl mock_command
    export -f mock_gpg mock_lsb_release mock_dpkg mock_tee mock_usermod

    # Docker installation tests
    echo -e "${YELLOW}[1/4] Testing Docker Installation...${NC}"
    test_docker_already_installed
    test_docker_fresh_installation
    test_docker_installation_verification_failure
    echo

    # Docker Compose installation tests
    echo -e "${YELLOW}[2/4] Testing Docker Compose Installation...${NC}"
    test_docker_compose_already_installed
    test_docker_compose_fresh_installation
    test_docker_compose_verification_failure
    echo

    # Integration tests
    echo -e "${YELLOW}[3/4] Testing Installation Integration...${NC}"
    test_complete_docker_installation_flow
    test_docker_daemon_not_running
    echo

    # Error handling tests
    echo -e "${YELLOW}[4/4] Testing Error Handling...${NC}"
    test_apt_get_failure
    test_network_connectivity_failure
    echo

    # Generate report
    local report_file=$(generate_installation_test_report)

    # Cleanup
    rm -f "$MOCK_LOG_FILE"

    # Display results
    echo -e "${BLUE}================================================================================${NC}"
    echo -e "${WHITE}                    INSTALLATION TEST RESULTS${NC}"
    echo -e "${BLUE}================================================================================${NC}"
    echo -e "${WHITE}Total Tests:${NC}  $TOTAL_TESTS"
    echo -e "${GREEN}Passed Tests:${NC} $PASSED_TESTS"
    echo -e "${RED}Failed Tests:${NC} $FAILED_TESTS"

    if [[ $TOTAL_TESTS -gt 0 ]]; then
        local success_rate=$(( (PASSED_TESTS * 100) / TOTAL_TESTS ))
        echo -e "${WHITE}Success Rate:${NC} ${success_rate}%"
    fi

    echo -e "${WHITE}Report File:${NC}  $report_file"
    echo -e "${BLUE}================================================================================${NC}"

    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "${GREEN}🎉 ALL INSTALLATION TESTS PASSED!${NC}"
        return 0
    else
        echo -e "${RED}❌ Some installation tests failed.${NC}"
        return 1
    fi
}

# Show usage
show_usage() {
    cat << EOF
${GREEN}VLESS Installation Test Suite v$TEST_VERSION${NC}

${YELLOW}USAGE:${NC}
    $0 [COMMAND]

${YELLOW}COMMANDS:${NC}
    run                     Run Docker installation tests
    help                    Show this help message

${YELLOW}EXAMPLES:${NC}
    $0 run                  Execute installation test suite

EOF
}

# Main execution
main() {
    case "${1:-}" in
        "run")
            run_installation_tests
            ;;
        "help"|"-h"|"--help")
            show_usage
            exit 0
            ;;
        "")
            echo -e "${RED}No command specified${NC}"
            show_usage
            exit 1
            ;;
        *)
            echo -e "${RED}Unknown command: $1${NC}"
            show_usage
            exit 1
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi