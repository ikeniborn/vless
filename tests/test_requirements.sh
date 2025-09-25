#!/bin/bash
set -euo pipefail

# VLESS+Reality VPN Service - System Requirements Test Suite
# Version: 1.0.0
# Description: Comprehensive testing for system requirements validation
# Author: VLESS Testing Team

#######################################################################################
# TEST CONSTANTS AND CONFIGURATION
#######################################################################################

readonly TEST_SCRIPT_NAME="test_requirements"
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

# Mock data for testing
readonly MOCK_LOW_RAM=256
readonly MOCK_HIGH_RAM=2048
readonly MOCK_LOW_DISK=0
readonly MOCK_HIGH_DISK=10
readonly MOCK_USED_PORT=443
readonly MOCK_FREE_PORT=8443

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
            echo -e "${BLUE}[REQ-INFO]${NC} ${timestamp} - $message"
            ;;
        "PASS")
            echo -e "${GREEN}[REQ-PASS]${NC} ${timestamp} - $message"
            ;;
        "FAIL")
            echo -e "${RED}[REQ-FAIL]${NC} ${timestamp} - $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[REQ-WARN]${NC} ${timestamp} - $message"
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

#######################################################################################
# MOCK SYSTEM FUNCTIONS
#######################################################################################

# Mock free command for RAM testing
mock_free_low() {
    echo "              total        used        free      shared  buff/cache   available"
    echo "Mem:        $(($MOCK_LOW_RAM * 1024))      200000     100000        1000      50000     150000"
}

mock_free_high() {
    echo "              total        used        free      shared  buff/cache   available"
    echo "Mem:        $(($MOCK_HIGH_RAM * 1024))      512000    1536000        1000      100000    1400000"
}

# Mock df command for disk testing
mock_df_low() {
    echo "Filesystem     1G-blocks      Used Available Use% Mounted on"
    echo "/dev/sda1             10         9        $MOCK_LOW_DISK  90% /"
}

mock_df_high() {
    echo "Filesystem     1G-blocks      Used Available Use% Mounted on"
    echo "/dev/sda1             50        20       $MOCK_HIGH_DISK  40% /"
}

# Mock netstat/ss for port testing
mock_netstat_port_used() {
    echo "Proto Recv-Q Send-Q Local Address           Foreign Address         State"
    echo "tcp        0      0 0.0.0.0:$MOCK_USED_PORT         0.0.0.0:*               LISTEN"
}

mock_netstat_port_free() {
    echo "Proto Recv-Q Send-Q Local Address           Foreign Address         State"
    echo "tcp        0      0 0.0.0.0:22              0.0.0.0:*               LISTEN"
}

# Mock sudo command
mock_sudo() {
    if [[ "$1" == "-n" && "$2" == "true" ]]; then
        return 0  # Simulate successful sudo without password
    fi
    # Execute the command normally for other cases
    "$@"
}

#######################################################################################
# ROOT PRIVILEGE TESTS
#######################################################################################

test_root_check_with_root() {
    test_log "INFO" "Testing root check with root privileges"

    # Create test script that simulates root user
    local test_script="/tmp/test_root_$$"
    cat > "$test_script" << 'EOF'
#!/bin/bash
EUID=0
source "$1"
check_root
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" "$VLESS_MANAGER" 2>&1)
    return_code=$?

    assert_return_code "0" "$return_code" "Root check with EUID=0"
    assert_output_contains "Root privileges verified" "$output" "Root check success message"

    rm -f "$test_script"
}

test_root_check_with_sudo() {
    test_log "INFO" "Testing root check with sudo access"

    # Test current environment (likely has sudo)
    if command -v sudo >/dev/null 2>&1; then
        # Create test script that simulates non-root user with sudo
        local test_script="/tmp/test_sudo_$$"
        cat > "$test_script" << 'EOF'
#!/bin/bash
EUID=1000
sudo() { mock_sudo "$@"; }
export -f mock_sudo
source "$1"
check_root
EOF
        chmod +x "$test_script"

        local output
        local return_code
        output=$("$test_script" "$VLESS_MANAGER" 2>&1)
        return_code=$?

        assert_return_code "0" "$return_code" "Root check with sudo access"

        rm -f "$test_script"
    else
        test_log "WARN" "Sudo not available, skipping sudo test"
    fi
}

test_root_check_without_privileges() {
    test_log "INFO" "Testing root check without privileges"

    # Create test script that simulates non-root user without sudo
    local test_script="/tmp/test_no_priv_$$"
    cat > "$test_script" << 'EOF'
#!/bin/bash
EUID=1000
command() {
    if [[ "$1" == "-v" && "$2" == "sudo" ]]; then
        return 1  # Simulate sudo not found
    fi
    /usr/bin/command "$@"
}
export -f command
source "$1"
check_root 2>&1
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" "$VLESS_MANAGER" 2>&1 || true)
    return_code=$?

    assert_return_code "1" "$return_code" "Root check without privileges should fail"
    assert_output_contains "requires root privileges" "$output" "No privileges error message"

    rm -f "$test_script"
}

#######################################################################################
# OS COMPATIBILITY TESTS
#######################################################################################

test_os_check_ubuntu_20() {
    test_log "INFO" "Testing OS check with Ubuntu 20.04"

    local temp_os_release="/tmp/test_os_ubuntu20_$$"
    cat > "$temp_os_release" << EOF
NAME="Ubuntu"
VERSION="20.04.4 LTS (Focal Fossa)"
ID=ubuntu
ID_LIKE=debian
PRETTY_NAME="Ubuntu 20.04.4 LTS"
VERSION_ID="20.04"
VERSION_CODENAME=focal
EOF

    local test_script="/tmp/test_ubuntu20_$$"
    cat > "$test_script" << EOF
#!/bin/bash
source() {
    if [[ "\$1" == "/etc/os-release" ]]; then
        source "$temp_os_release"
    else
        builtin source "\$@"
    fi
}
export -f source
source "$VLESS_MANAGER"
check_os
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" 2>&1)
    return_code=$?

    assert_return_code "0" "$return_code" "Ubuntu 20.04 OS check"
    assert_output_contains "OS compatibility verified" "$output" "Ubuntu 20.04 success message"

    rm -f "$test_script" "$temp_os_release"
}

test_os_check_ubuntu_18() {
    test_log "INFO" "Testing OS check with Ubuntu 18.04 (unsupported)"

    local temp_os_release="/tmp/test_os_ubuntu18_$$"
    cat > "$temp_os_release" << EOF
NAME="Ubuntu"
VERSION="18.04.6 LTS (Bionic Beaver)"
ID=ubuntu
ID_LIKE=debian
PRETTY_NAME="Ubuntu 18.04.6 LTS"
VERSION_ID="18.04"
VERSION_CODENAME=bionic
EOF

    local test_script="/tmp/test_ubuntu18_$$"
    cat > "$test_script" << EOF
#!/bin/bash
source() {
    if [[ "\$1" == "/etc/os-release" ]]; then
        source "$temp_os_release"
    else
        builtin source "\$@"
    fi
}
export -f source
source "$VLESS_MANAGER"
check_os 2>&1
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" 2>&1 || true)
    return_code=$?

    assert_return_code "1" "$return_code" "Ubuntu 18.04 OS check should fail"
    assert_output_contains "Ubuntu 20.04 or higher is required" "$output" "Ubuntu 18.04 error message"

    rm -f "$test_script" "$temp_os_release"
}

test_os_check_debian_11() {
    test_log "INFO" "Testing OS check with Debian 11"

    local temp_os_release="/tmp/test_os_debian11_$$"
    cat > "$temp_os_release" << EOF
PRETTY_NAME="Debian GNU/Linux 11 (bullseye)"
NAME="Debian GNU/Linux"
VERSION_ID="11"
VERSION="11 (bullseye)"
VERSION_CODENAME=bullseye
ID=debian
EOF

    local test_script="/tmp/test_debian11_$$"
    cat > "$test_script" << EOF
#!/bin/bash
source() {
    if [[ "\$1" == "/etc/os-release" ]]; then
        source "$temp_os_release"
    else
        builtin source "\$@"
    fi
}
export -f source
source "$VLESS_MANAGER"
check_os
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" 2>&1)
    return_code=$?

    assert_return_code "0" "$return_code" "Debian 11 OS check"
    assert_output_contains "OS compatibility verified" "$output" "Debian 11 success message"

    rm -f "$test_script" "$temp_os_release"
}

test_os_check_unsupported() {
    test_log "INFO" "Testing OS check with unsupported OS"

    local temp_os_release="/tmp/test_os_centos_$$"
    cat > "$temp_os_release" << EOF
NAME="CentOS Linux"
VERSION="7 (Core)"
ID="centos"
ID_LIKE="rhel fedora"
VERSION_ID="7"
PRETTY_NAME="CentOS Linux 7 (Core)"
EOF

    local test_script="/tmp/test_centos_$$"
    cat > "$test_script" << EOF
#!/bin/bash
source() {
    if [[ "\$1" == "/etc/os-release" ]]; then
        source "$temp_os_release"
    else
        builtin source "\$@"
    fi
}
export -f source
source "$VLESS_MANAGER"
check_os 2>&1
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" 2>&1 || true)
    return_code=$?

    assert_return_code "1" "$return_code" "Unsupported OS check should fail"
    assert_output_contains "Unsupported OS" "$output" "Unsupported OS error message"

    rm -f "$test_script" "$temp_os_release"
}

#######################################################################################
# ARCHITECTURE TESTS
#######################################################################################

test_architecture_x86_64() {
    test_log "INFO" "Testing architecture check with x86_64"

    local test_script="/tmp/test_arch_x86_$$"
    cat > "$test_script" << 'EOF'
#!/bin/bash
uname() {
    if [[ "$1" == "-m" ]]; then
        echo "x86_64"
    else
        /usr/bin/uname "$@"
    fi
}
export -f uname
source "$1"
check_architecture
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" "$VLESS_MANAGER" 2>&1)
    return_code=$?

    assert_return_code "0" "$return_code" "x86_64 architecture check"
    assert_output_contains "Architecture verified: x86_64" "$output" "x86_64 success message"

    rm -f "$test_script"
}

test_architecture_arm64() {
    test_log "INFO" "Testing architecture check with ARM64"

    local test_script="/tmp/test_arch_arm64_$$"
    cat > "$test_script" << 'EOF'
#!/bin/bash
uname() {
    if [[ "$1" == "-m" ]]; then
        echo "aarch64"
    else
        /usr/bin/uname "$@"
    fi
}
export -f uname
source "$1"
check_architecture
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" "$VLESS_MANAGER" 2>&1)
    return_code=$?

    assert_return_code "0" "$return_code" "ARM64 architecture check"
    assert_output_contains "Architecture verified: ARM64" "$output" "ARM64 success message"

    rm -f "$test_script"
}

test_architecture_unsupported() {
    test_log "INFO" "Testing architecture check with unsupported architecture"

    local test_script="/tmp/test_arch_unsupported_$$"
    cat > "$test_script" << 'EOF'
#!/bin/bash
uname() {
    if [[ "$1" == "-m" ]]; then
        echo "i686"
    else
        /usr/bin/uname "$@"
    fi
}
export -f uname
source "$1"
check_architecture 2>&1
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" "$VLESS_MANAGER" 2>&1 || true)
    return_code=$?

    assert_return_code "1" "$return_code" "Unsupported architecture should fail"
    assert_output_contains "Unsupported architecture" "$output" "Unsupported architecture error"

    rm -f "$test_script"
}

#######################################################################################
# RESOURCE TESTS
#######################################################################################

test_resources_sufficient_ram() {
    test_log "INFO" "Testing resource check with sufficient RAM"

    local test_script="/tmp/test_ram_ok_$$"
    cat > "$test_script" << 'EOF'
#!/bin/bash
free() { mock_free_high; }
df() { mock_df_high; }
export -f free df mock_free_high mock_df_high
source "$1"
check_resources
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" "$VLESS_MANAGER" 2>&1)
    return_code=$?

    assert_return_code "0" "$return_code" "Sufficient RAM check"
    assert_output_contains "RAM check passed" "$output" "Sufficient RAM success message"

    rm -f "$test_script"
}

test_resources_insufficient_ram() {
    test_log "INFO" "Testing resource check with insufficient RAM"

    local test_script="/tmp/test_ram_low_$$"
    cat > "$test_script" << 'EOF'
#!/bin/bash
free() { mock_free_low; }
df() { mock_df_high; }
export -f free df mock_free_low mock_df_high
source "$1"
check_resources 2>&1
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" "$VLESS_MANAGER" 2>&1 || true)
    return_code=$?

    assert_return_code "1" "$return_code" "Insufficient RAM should fail"
    assert_output_contains "Insufficient RAM" "$output" "Insufficient RAM error message"

    rm -f "$test_script"
}

test_resources_insufficient_disk() {
    test_log "INFO" "Testing resource check with insufficient disk space"

    local test_script="/tmp/test_disk_low_$$"
    cat > "$test_script" << 'EOF'
#!/bin/bash
free() { mock_free_high; }
df() { mock_df_low; }
export -f free df mock_free_high mock_df_low
source "$1"
check_resources 2>&1
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" "$VLESS_MANAGER" 2>&1 || true)
    return_code=$?

    assert_return_code "1" "$return_code" "Insufficient disk space should fail"
    assert_output_contains "Insufficient disk space" "$output" "Insufficient disk error message"

    rm -f "$test_script"
}

#######################################################################################
# PORT AVAILABILITY TESTS
#######################################################################################

test_port_available() {
    test_log "INFO" "Testing port availability check with free port"

    local test_script="/tmp/test_port_free_$$"
    cat > "$test_script" << 'EOF'
#!/bin/bash
netstat() { mock_netstat_port_free; }
ss() { mock_netstat_port_free; }
export -f netstat ss mock_netstat_port_free
source "$1"
check_port
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" "$VLESS_MANAGER" 2>&1)
    return_code=$?

    assert_return_code "0" "$return_code" "Free port check"
    assert_output_contains "Port 443 is available" "$output" "Free port success message"

    rm -f "$test_script"
}

test_port_in_use() {
    test_log "INFO" "Testing port availability check with used port"

    local test_script="/tmp/test_port_used_$$"
    cat > "$test_script" << 'EOF'
#!/bin/bash
netstat() { mock_netstat_port_used; }
ss() { mock_netstat_port_used; }
export -f netstat ss mock_netstat_port_used
source "$1"
check_port 2>&1
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" "$VLESS_MANAGER" 2>&1 || true)
    return_code=$?

    assert_return_code "1" "$return_code" "Used port should fail"
    assert_output_contains "Port 443 is already in use" "$output" "Used port error message"

    rm -f "$test_script"
}

test_port_check_no_tools() {
    test_log "INFO" "Testing port check without netstat/ss tools"

    local test_script="/tmp/test_port_no_tools_$$"
    cat > "$test_script" << 'EOF'
#!/bin/bash
command() {
    if [[ "$2" == "netstat" || "$2" == "ss" ]]; then
        return 1  # Simulate tools not found
    fi
    /usr/bin/command "$@"
}
export -f command
source "$1"
check_port
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" "$VLESS_MANAGER" 2>&1)
    return_code=$?

    assert_return_code "0" "$return_code" "Port check without tools should succeed with warning"
    assert_output_contains "Cannot check port availability" "$output" "No tools warning message"

    rm -f "$test_script"
}

#######################################################################################
# INTEGRATION TESTS
#######################################################################################

test_complete_system_requirements() {
    test_log "INFO" "Testing complete system requirements check"

    local test_script="/tmp/test_complete_req_$$"
    cat > "$test_script" << 'EOF'
#!/bin/bash
# Mock all system checks to pass
EUID=0
sudo() { mock_sudo "$@"; }
uname() {
    if [[ "$1" == "-m" ]]; then
        echo "x86_64";
    else
        /usr/bin/uname "$@";
    fi
}
free() { mock_free_high; }
df() { mock_df_high; }
netstat() { mock_netstat_port_free; }
ss() { mock_netstat_port_free; }

# Create mock os-release
temp_os_release="/tmp/mock_os_release_$$"
cat > "$temp_os_release" << OSEOF
ID=ubuntu
VERSION_ID="20.04"
PRETTY_NAME="Ubuntu 20.04 LTS"
OSEOF

source() {
    if [[ "\$1" == "/etc/os-release" ]]; then
        builtin source "$temp_os_release"
    else
        builtin source "\$@"
    fi
}

export -f sudo uname free df netstat ss source mock_sudo mock_free_high mock_df_high mock_netstat_port_free

source "$1"
check_system_requirements
rm -f "$temp_os_release"
EOF
    chmod +x "$test_script"

    local output
    local return_code
    output=$("$test_script" "$VLESS_MANAGER" 2>&1)
    return_code=$?

    assert_return_code "0" "$return_code" "Complete system requirements check"
    assert_output_contains "All system requirements met" "$output" "Complete requirements success"

    rm -f "$test_script"
}

#######################################################################################
# TEST REPORT AND EXECUTION
#######################################################################################

# Generate test report
generate_requirements_test_report() {
    local report_file="/tmp/vless_requirements_test_report_$(date +%Y%m%d_%H%M%S).txt"
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')

    cat > "$report_file" << EOF
================================================================================
VLESS+Reality VPN Service - System Requirements Test Report
================================================================================

Test Execution Summary:
- Test Suite: System Requirements Validation
- Test Version: $TEST_VERSION
- Execution Time: $end_time
- Total Tests: $TOTAL_TESTS
- Passed Tests: $PASSED_TESTS
- Failed Tests: $FAILED_TESTS
- Success Rate: $(( (PASSED_TESTS * 100) / TOTAL_TESTS ))%

Test Categories:
- Root Privilege Validation
- OS Compatibility Checks (Ubuntu 18.04+, Debian 11+)
- Architecture Support (x86_64, ARM64)
- Resource Requirements (RAM: 512MB+, Disk: 1GB+)
- Port Availability (Port 443)
- Integration Testing

Tested Scenarios:
✓ Root user access
✓ Sudo user access
✓ No privileges handling
✓ Ubuntu 20.04 compatibility
✓ Ubuntu 18.04 rejection
✓ Debian 11 compatibility
✓ Unsupported OS rejection
✓ x86_64 architecture support
✓ ARM64 architecture support
✓ Unsupported architecture rejection
✓ Sufficient RAM validation
✓ Insufficient RAM detection
✓ Sufficient disk space validation
✓ Insufficient disk space detection
✓ Port availability check
✓ Port in use detection
✓ Missing network tools handling

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
run_requirements_tests() {
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')

    echo
    echo -e "${BLUE}================================================================================${NC}"
    echo -e "${GREEN}         VLESS+Reality VPN - System Requirements Test Suite${NC}"
    echo -e "${BLUE}================================================================================${NC}"
    echo -e "${WHITE}Version: $TEST_VERSION${NC}"
    echo -e "${WHITE}Start Time: $start_time${NC}"
    echo -e "${BLUE}================================================================================${NC}"
    echo

    # Export mock functions
    export -f mock_free_low mock_free_high mock_df_low mock_df_high
    export -f mock_netstat_port_used mock_netstat_port_free mock_sudo

    # Root privilege tests
    echo -e "${YELLOW}[1/6] Testing Root Privilege Validation...${NC}"
    test_root_check_with_root
    test_root_check_with_sudo
    test_root_check_without_privileges
    echo

    # OS compatibility tests
    echo -e "${YELLOW}[2/6] Testing OS Compatibility...${NC}"
    test_os_check_ubuntu_20
    test_os_check_ubuntu_18
    test_os_check_debian_11
    test_os_check_unsupported
    echo

    # Architecture tests
    echo -e "${YELLOW}[3/6] Testing Architecture Support...${NC}"
    test_architecture_x86_64
    test_architecture_arm64
    test_architecture_unsupported
    echo

    # Resource tests
    echo -e "${YELLOW}[4/6] Testing Resource Requirements...${NC}"
    test_resources_sufficient_ram
    test_resources_insufficient_ram
    test_resources_insufficient_disk
    echo

    # Port availability tests
    echo -e "${YELLOW}[5/6] Testing Port Availability...${NC}"
    test_port_available
    test_port_in_use
    test_port_check_no_tools
    echo

    # Integration tests
    echo -e "${YELLOW}[6/6] Testing Complete Requirements Check...${NC}"
    test_complete_system_requirements
    echo

    # Generate report
    local report_file=$(generate_requirements_test_report)

    # Display results
    echo -e "${BLUE}================================================================================${NC}"
    echo -e "${WHITE}                    REQUIREMENTS TEST RESULTS${NC}"
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
        echo -e "${GREEN}🎉 ALL REQUIREMENTS TESTS PASSED!${NC}"
        return 0
    else
        echo -e "${RED}❌ Some requirements tests failed.${NC}"
        return 1
    fi
}

# Show usage
show_usage() {
    cat << EOF
${GREEN}VLESS Requirements Test Suite v$TEST_VERSION${NC}

${YELLOW}USAGE:${NC}
    $0 [COMMAND]

${YELLOW}COMMANDS:${NC}
    run                     Run system requirements tests
    help                    Show this help message

${YELLOW}EXAMPLES:${NC}
    $0 run                  Execute requirements test suite

EOF
}

# Main execution
main() {
    case "${1:-}" in
        "run")
            run_requirements_tests
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