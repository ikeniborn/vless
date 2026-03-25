#!/bin/bash
################################################################################
# VLESS Reality VPN v3.2 - Public Proxy Integration Tests
#
# Description:
#   Comprehensive integration tests for public proxy functionality
#
# Requirements:
#   - Must be run on a server with VLESS v3.2 installed
#   - Must have sudo privileges
#   - Must have curl, jq, fail2ban-client installed
#   - Internet connectivity required
#
# Usage:
#   sudo ./test_public_proxy.sh
#
# Test Coverage:
#   1. Public proxy access (SOCKS5 + HTTP)
#   2. Fail2ban brute-force protection
#   3. Config file validation (SERVER_IP usage)
#   4. UFW firewall rules
#   5. Docker healthchecks
#   6. Password strength (32 characters)
#
# Exit Codes:
#   0 - All tests passed
#   1 - One or more tests failed
#   2 - Prerequisites not met
#
# Version: 3.2
# Date: 2025-10-04
################################################################################

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Test configuration
readonly TEST_USERNAME="test_user_$(date +%s)"
readonly VLESS_BASE_DIR="/opt/familytraffic"
readonly REQUIRED_COMMANDS=("curl" "jq" "fail2ban-client" "docker" "ufw")

# Test results tracking
declare -i TESTS_PASSED=0
declare -i TESTS_FAILED=0
declare -a FAILED_TESTS=()

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_test() {
    echo -e "${YELLOW}TEST:${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
    ((TESTS_PASSED++))
}

print_failure() {
    echo -e "${RED}✗ FAIL:${NC} $1"
    ((TESTS_FAILED++))
    FAILED_TESTS+=("$1")
}

print_info() {
    echo -e "${CYAN}INFO:${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}ERROR: This script must be run as root${NC}" >&2
        echo "Please run: sudo $0"
        exit 2
    fi
}

check_prerequisites() {
    print_header "Checking Prerequisites"

    # Check if VLESS is installed
    if [[ ! -d "$VLESS_BASE_DIR" ]]; then
        echo -e "${RED}ERROR: VLESS not installed at $VLESS_BASE_DIR${NC}" >&2
        echo "Please install VLESS v3.2 first"
        exit 2
    fi
    print_info "VLESS installation found at $VLESS_BASE_DIR"

    # Check required commands
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${RED}ERROR: Required command not found: $cmd${NC}" >&2
            exit 2
        fi
    done
    print_info "All required commands available"

    # Check if containers are running
    if ! docker ps --format '{{.Names}}' | grep -q "vless-reality"; then
        echo -e "${RED}ERROR: vless-reality container not running${NC}" >&2
        echo "Start VLESS: cd $VLESS_BASE_DIR && docker compose up -d"
        exit 2
    fi
    print_info "VLESS containers running"

    echo -e "${GREEN}✓ All prerequisites met${NC}"
}

get_server_ip() {
    local server_ip

    # Try reading from ENV file
    if [[ -f "$VLESS_BASE_DIR/.env" ]]; then
        server_ip=$(grep "^SERVER_IP=" "$VLESS_BASE_DIR/.env" 2>/dev/null | cut -d'=' -f2)
    fi

    # Fallback: auto-detect
    if [[ -z "$server_ip" || "$server_ip" == "SERVER_IP_NOT_DETECTED" ]]; then
        server_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "")
    fi

    # Final validation
    if [[ -z "$server_ip" ]]; then
        echo -e "${RED}ERROR: Cannot determine server IP${NC}" >&2
        exit 2
    fi

    echo "$server_ip"
}

cleanup_test_user() {
    print_info "Cleaning up test user: $TEST_USERNAME"

    # Remove user if exists
    if [[ -d "$VLESS_BASE_DIR/data/clients/$TEST_USERNAME" ]]; then
        sudo "$VLESS_BASE_DIR/scripts/user_management.sh" remove "$TEST_USERNAME" 2>/dev/null || true
    fi

    # Unban test IP from fail2ban (if banned)
    local server_ip
    server_ip=$(get_server_ip)
    sudo fail2ban-client unban "$server_ip" 2>/dev/null || true

    print_info "Cleanup complete"
}

################################################################################
# Test Cases
################################################################################

test_01_public_proxy_access() {
    print_header "TEST 1: Public Proxy Access"
    print_test "Verifying SOCKS5 and HTTP proxies accessible from external IP"

    local server_ip
    server_ip=$(get_server_ip)
    print_info "Server IP: $server_ip"

    # Create test user
    print_info "Creating test user: $TEST_USERNAME"
    if ! sudo "$VLESS_BASE_DIR/scripts/user_management.sh" add "$TEST_USERNAME" &>/dev/null; then
        print_failure "Failed to create test user"
        return 1
    fi

    # Wait for Xray to reload
    sleep 3

    # Get test user password
    local password
    password=$(jq -r ".users[] | select(.username==\"$TEST_USERNAME\") | .proxy_password" \
        "$VLESS_BASE_DIR/config/users.json")

    if [[ -z "$password" ]]; then
        print_failure "Failed to retrieve test user password"
        return 1
    fi
    print_info "Password retrieved (length: ${#password})"

    # Test SOCKS5 proxy
    print_info "Testing SOCKS5 proxy on port 1080..."
    if timeout 15 curl --connect-timeout 10 --socks5 "${TEST_USERNAME}:${password}@${server_ip}:1080" \
        -s -o /dev/null -w "%{http_code}" https://ifconfig.me | grep -q "200"; then
        print_success "SOCKS5 proxy accessible from external IP"
    else
        print_failure "SOCKS5 proxy NOT accessible"
        return 1
    fi

    # Test HTTP proxy
    print_info "Testing HTTP proxy on port 8118..."
    if timeout 15 curl --connect-timeout 10 --proxy "http://${TEST_USERNAME}:${password}@${server_ip}:8118" \
        -s -o /dev/null -w "%{http_code}" https://ifconfig.me | grep -q "200"; then
        print_success "HTTP proxy accessible from external IP"
    else
        print_failure "HTTP proxy NOT accessible"
        return 1
    fi

    print_success "Public proxy access test completed"
    return 0
}

test_02_fail2ban_protection() {
    print_header "TEST 2: Fail2ban Brute-Force Protection"
    print_test "Verifying fail2ban blocks IP after 5 failed authentication attempts"

    local server_ip
    server_ip=$(get_server_ip)

    # First, unban our IP (in case it was banned before)
    sudo fail2ban-client unban "$server_ip" 2>/dev/null || true
    sleep 2

    # Check initial ban status
    print_info "Initial banned IP count:"
    sudo fail2ban-client status familytraffic-socks5 | grep "Currently banned" || true

    # Attempt 6 connections with wrong password
    print_info "Attempting 6 connections with wrong password..."
    for i in {1..6}; do
        echo -n "  Attempt $i/6... "
        timeout 5 curl --connect-timeout 3 --socks5 "${TEST_USERNAME}:wrongpassword@${server_ip}:1080" \
            https://ifconfig.me 2>/dev/null || echo "failed"
        sleep 1
    done

    # Wait for fail2ban to process logs
    sleep 3

    # Check if current IP is banned
    print_info "Checking if IP is banned..."
    local banned_ips
    banned_ips=$(sudo fail2ban-client status familytraffic-socks5 | grep "Banned IP list" | awk -F':' '{print $2}' || echo "")

    if echo "$banned_ips" | grep -q "$server_ip"; then
        print_success "Fail2ban correctly banned IP after failed attempts"

        # Unban for further testing
        print_info "Unbanning test IP for further tests..."
        sudo fail2ban-client unban "$server_ip"
        sleep 2
    else
        print_failure "Fail2ban did NOT ban IP (expected after 5+ failures)"
        print_info "Banned IPs: $banned_ips"
        print_info "Our IP: $server_ip"
        return 1
    fi

    print_success "Fail2ban protection test completed"
    return 0
}

test_03_config_files_validation() {
    print_header "TEST 3: Config Files Validation"
    print_test "Verifying all config files use SERVER_IP (not 127.0.0.1)"

    local server_ip
    server_ip=$(get_server_ip)
    local config_dir="$VLESS_BASE_DIR/data/clients/$TEST_USERNAME"

    if [[ ! -d "$config_dir" ]]; then
        print_failure "Config directory not found: $config_dir"
        return 1
    fi

    # Check for 127.0.0.1 in proxy config files (should be NONE)
    print_info "Checking for localhost references (127.0.0.1)..."
    if grep -r "127.0.0.1" "$config_dir"/*.txt "$config_dir"/*.sh 2>/dev/null | grep -v "NO_PROXY"; then
        print_failure "Found 127.0.0.1 in config files (should use SERVER_IP)"
        return 1
    else
        print_success "No localhost references (127.0.0.1) found in proxy configs"
    fi

    # Verify SERVER_IP is present in config files
    print_info "Checking for SERVER_IP presence..."
    local files_with_ip=0
    for file in "$config_dir"/*.txt "$config_dir"/*.sh; do
        if [[ -f "$file" ]] && grep -q "$server_ip" "$file" 2>/dev/null; then
            ((files_with_ip++))
        fi
    done

    if [[ $files_with_ip -ge 2 ]]; then
        print_success "SERVER_IP found in $files_with_ip config files"
    else
        print_failure "SERVER_IP NOT found in config files (found in $files_with_ip files)"
        return 1
    fi

    print_success "Config files validation completed"
    return 0
}

test_04_password_strength() {
    print_header "TEST 4: Password Strength Validation"
    print_test "Verifying all passwords are 32 characters (v3.2 security requirement)"

    # Check test user password length
    local password_length
    password_length=$(jq -r ".users[] | select(.username==\"$TEST_USERNAME\") | .proxy_password | length" \
        "$VLESS_BASE_DIR/config/users.json")

    print_info "Test user password length: $password_length characters"

    if [[ $password_length -eq 32 ]]; then
        print_success "Password length is 32 characters (v3.2 requirement met)"
    else
        print_failure "Password length is $password_length (expected 32)"
        return 1
    fi

    # Check all users have 32-character passwords
    local min_length
    min_length=$(jq -r '.users[].proxy_password | length' "$VLESS_BASE_DIR/config/users.json" | sort -n | head -1)

    if [[ $min_length -eq 32 ]]; then
        print_success "All users have 32-character passwords"
    else
        print_failure "Some users have passwords shorter than 32 characters (min: $min_length)"
        return 1
    fi

    print_success "Password strength validation completed"
    return 0
}

test_05_ufw_firewall_rules() {
    print_header "TEST 5: UFW Firewall Rules"
    print_test "Verifying UFW rules for ports 1080 and 8118"

    # Check if UFW is active
    if ! sudo ufw status | grep -q "Status: active"; then
        print_failure "UFW is not active"
        return 1
    fi
    print_info "UFW is active"

    # Check SOCKS5 port rule
    if sudo ufw status numbered | grep -q "1080/tcp"; then
        print_success "UFW rule for port 1080 (SOCKS5) exists"
    else
        print_failure "UFW rule for port 1080 (SOCKS5) NOT found"
        return 1
    fi

    # Check HTTP proxy port rule
    if sudo ufw status numbered | grep -q "8118/tcp"; then
        print_success "UFW rule for port 8118 (HTTP) exists"
    else
        print_failure "UFW rule for port 8118 (HTTP) NOT found"
        return 1
    fi

    print_success "UFW firewall rules validation completed"
    return 0
}

test_06_docker_healthchecks() {
    print_header "TEST 6: Docker Healthcheck Validation"
    print_test "Verifying Xray container has healthcheck configured"

    # Get healthcheck status
    local health_status
    health_status=$(docker inspect vless-reality --format='{{.State.Health.Status}}' 2>/dev/null || echo "none")

    print_info "Container health status: $health_status"

    if [[ "$health_status" == "healthy" ]]; then
        print_success "Xray container is healthy"
    elif [[ "$health_status" == "none" ]]; then
        print_failure "No healthcheck configured for Xray container"
        return 1
    else
        print_failure "Xray container health status: $health_status (expected: healthy)"
        return 1
    fi

    # Verify healthcheck command
    local healthcheck_cmd
    healthcheck_cmd=$(docker inspect vless-reality --format='{{.Config.Healthcheck.Test}}' 2>/dev/null || echo "")

    if echo "$healthcheck_cmd" | grep -q "nc.*1080.*8118"; then
        print_success "Healthcheck command tests both proxy ports (1080, 8118)"
    else
        print_failure "Healthcheck command does not test proxy ports"
        print_info "Command: $healthcheck_cmd"
        return 1
    fi

    print_success "Docker healthcheck validation completed"
    return 0
}

test_07_fail2ban_jails_active() {
    print_header "TEST 7: Fail2ban Jails Status"
    print_test "Verifying both SOCKS5 and HTTP jails are active"

    # Check SOCKS5 jail
    if sudo fail2ban-client status familytraffic-socks5 &>/dev/null; then
        print_success "Fail2ban jail 'familytraffic-socks5' is active"
    else
        print_failure "Fail2ban jail 'familytraffic-socks5' NOT active"
        return 1
    fi

    # Check HTTP jail
    if sudo fail2ban-client status familytraffic-http &>/dev/null; then
        print_success "Fail2ban jail 'familytraffic-http' is active"
    else
        print_failure "Fail2ban jail 'familytraffic-http' NOT active"
        return 1
    fi

    print_success "Fail2ban jails validation completed"
    return 0
}

test_08_env_file_server_ip() {
    print_header "TEST 8: ENV File SERVER_IP"
    print_test "Verifying .env file contains SERVER_IP"

    if [[ ! -f "$VLESS_BASE_DIR/.env" ]]; then
        print_failure ".env file not found"
        return 1
    fi

    local server_ip
    server_ip=$(grep "^SERVER_IP=" "$VLESS_BASE_DIR/.env" 2>/dev/null | cut -d'=' -f2)

    if [[ -n "$server_ip" && "$server_ip" != "SERVER_IP_NOT_DETECTED" ]]; then
        print_success ".env file contains valid SERVER_IP: $server_ip"
    else
        print_failure ".env file does not contain valid SERVER_IP"
        return 1
    fi

    # Verify IP format
    if [[ "$server_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_success "SERVER_IP has valid IPv4 format"
    else
        print_failure "SERVER_IP has invalid format: $server_ip"
        return 1
    fi

    print_success "ENV file validation completed"
    return 0
}

################################################################################
# Main Test Runner
################################################################################

main() {
    print_header "VLESS Reality VPN v3.2 - Public Proxy Integration Tests"

    echo "Test Suite: Public Proxy Functionality"
    echo "Date: $(date)"
    echo "Server: $(hostname)"
    echo ""

    # Prerequisites
    check_root
    check_prerequisites

    # Setup trap for cleanup
    trap cleanup_test_user EXIT

    # Run all tests
    test_01_public_proxy_access || true
    test_02_fail2ban_protection || true
    test_03_config_files_validation || true
    test_04_password_strength || true
    test_05_ufw_firewall_rules || true
    test_06_docker_healthchecks || true
    test_07_fail2ban_jails_active || true
    test_08_env_file_server_ip || true

    # Print summary
    print_header "TEST SUMMARY"
    echo ""
    echo -e "Total Tests: $((TESTS_PASSED + TESTS_FAILED))"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    echo ""

    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}Failed Tests:${NC}"
        for test in "${FAILED_TESTS[@]}"; do
            echo -e "  ${RED}✗${NC} $test"
        done
        echo ""
        echo -e "${RED}RESULT: FAILED${NC}"
        exit 1
    else
        echo -e "${GREEN}RESULT: ALL TESTS PASSED ✓${NC}"
        exit 0
    fi
}

################################################################################
# Script Entry Point
################################################################################
main "$@"
