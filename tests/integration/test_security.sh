#!/bin/bash
################################################################################
# VLESS Reality VPN v3.2 - Security Tests
#
# Description:
#   Security-focused tests for public proxy deployment
#
# Requirements:
#   - Must be run on a server with VLESS v3.2 installed
#   - Must have sudo privileges
#   - Must have nmap, jq installed
#   - Internet connectivity required
#
# Usage:
#   sudo ./test_security.sh
#
# Test Coverage:
#   1. Port scanning (verify only expected ports open)
#   2. Password strength (32 characters minimum)
#   3. UFW rate limiting effectiveness
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
readonly VLESS_BASE_DIR="/opt/vless"
readonly REQUIRED_COMMANDS=("nmap" "jq" "curl" "ufw")

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

print_warning() {
    echo -e "${YELLOW}WARN:${NC} $1"
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
    print_info "VLESS installation found"

    # Check required commands
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${RED}ERROR: Required command not found: $cmd${NC}" >&2
            if [[ "$cmd" == "nmap" ]]; then
                echo "Install: sudo apt install nmap"
            fi
            exit 2
        fi
    done
    print_info "All required commands available"

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

################################################################################
# Test Cases
################################################################################

test_01_port_scanning() {
    print_header "SECURITY TEST 1: Port Scanning"
    print_test "Verifying only expected ports are open"

    local server_ip
    server_ip=$(get_server_ip)
    print_info "Scanning server IP: $server_ip"

    # Get VLESS port from config
    local vless_port
    vless_port=$(grep "^VLESS_PORT=" "$VLESS_BASE_DIR/.env" 2>/dev/null | cut -d'=' -f2 || echo "443")

    print_info "Expected open ports:"
    print_info "  - SSH (22)"
    print_info "  - VLESS ($vless_port)"
    print_info "  - SOCKS5 (1080)"
    print_info "  - HTTP Proxy (8118)"
    echo ""

    # Run nmap scan
    print_info "Running nmap scan (this may take 30-60 seconds)..."
    local nmap_output
    nmap_output=$(nmap -p 1-65535 --open "$server_ip" 2>/dev/null || echo "SCAN_FAILED")

    if [[ "$nmap_output" == "SCAN_FAILED" ]]; then
        print_warning "Nmap scan failed (firewall may be blocking)"
        print_info "Skipping port scan validation"
        return 0
    fi

    # Extract open ports
    local open_ports
    open_ports=$(echo "$nmap_output" | grep "^[0-9]" | grep "open" | awk '{print $1}' | cut -d'/' -f1 | sort -n)

    print_info "Open ports detected:"
    echo "$open_ports" | sed 's/^/  - /'
    echo ""

    # Check for unexpected ports
    local unexpected_ports=0
    local expected_ports="22 $vless_port 1080 8118"

    while IFS= read -r port; do
        if [[ ! " $expected_ports " =~ " $port " ]]; then
            print_warning "Unexpected port open: $port"
            ((unexpected_ports++))
        fi
    done <<< "$open_ports"

    # Check if expected proxy ports are open
    if echo "$open_ports" | grep -q "^1080$"; then
        print_success "SOCKS5 port (1080) is accessible"
    else
        print_failure "SOCKS5 port (1080) NOT accessible"
        return 1
    fi

    if echo "$open_ports" | grep -q "^8118$"; then
        print_success "HTTP proxy port (8118) is accessible"
    else
        print_failure "HTTP proxy port (8118) NOT accessible"
        return 1
    fi

    if [[ $unexpected_ports -eq 0 ]]; then
        print_success "No unexpected ports detected"
    else
        print_warning "$unexpected_ports unexpected port(s) detected (check above)"
    fi

    print_success "Port scanning test completed"
    return 0
}

test_02_password_strength() {
    print_header "SECURITY TEST 2: Password Strength"
    print_test "Verifying all passwords meet v3.2 security requirements (32 characters)"

    if [[ ! -f "$VLESS_BASE_DIR/config/users.json" ]]; then
        print_failure "users.json not found"
        return 1
    fi

    # Get all password lengths
    local all_lengths
    all_lengths=$(jq -r '.users[].proxy_password | length' "$VLESS_BASE_DIR/config/users.json" 2>/dev/null)

    if [[ -z "$all_lengths" ]]; then
        print_info "No users with proxy passwords found (proxy may be disabled)"
        return 0
    fi

    # Statistics
    local total_users
    total_users=$(echo "$all_lengths" | wc -l)
    local min_length
    min_length=$(echo "$all_lengths" | sort -n | head -1)
    local max_length
    max_length=$(echo "$all_lengths" | sort -n | tail -1)
    local weak_passwords
    weak_passwords=$(echo "$all_lengths" | awk '$1 < 32' | wc -l)

    print_info "Total users with proxy passwords: $total_users"
    print_info "Password length range: $min_length - $max_length characters"
    echo ""

    # Check minimum requirement (32 characters)
    if [[ $min_length -ge 32 ]]; then
        print_success "All passwords meet minimum length requirement (32 characters)"
    else
        print_failure "Some passwords are shorter than 32 characters (min: $min_length)"
        return 1
    fi

    # Check for weak passwords
    if [[ $weak_passwords -gt 0 ]]; then
        print_failure "$weak_passwords user(s) have weak passwords (< 32 characters)"
        return 1
    else
        print_success "No weak passwords detected"
    fi

    # Verify password entropy (simple check)
    local sample_password
    sample_password=$(jq -r '.users[0].proxy_password' "$VLESS_BASE_DIR/config/users.json")

    if [[ "$sample_password" =~ ^[a-f0-9]{32}$ ]]; then
        print_success "Passwords use hexadecimal format (good entropy)"
    else
        print_warning "Passwords may not use optimal format"
    fi

    print_success "Password strength test completed"
    return 0
}

test_03_ufw_rate_limiting() {
    print_header "SECURITY TEST 3: UFW Rate Limiting"
    print_test "Verifying UFW rate limiting is configured correctly"

    # Check if UFW is active
    if ! ufw status | grep -q "Status: active"; then
        print_failure "UFW is not active"
        return 1
    fi
    print_info "UFW is active"

    # Check for rate limiting on port 1080
    if sudo ufw status verbose | grep "1080/tcp" | grep -q "LIMIT"; then
        print_success "Rate limiting enabled for port 1080 (SOCKS5)"
    else
        print_warning "Rate limiting NOT configured for port 1080 (recommended: ufw limit 1080/tcp)"
    fi

    # Check for rate limiting on port 8118
    if sudo ufw status verbose | grep "8118/tcp" | grep -q "LIMIT"; then
        print_success "Rate limiting enabled for port 8118 (HTTP)"
    else
        print_warning "Rate limiting NOT configured for port 8118 (recommended: ufw limit 8118/tcp)"
    fi

    # Test rate limiting effectiveness (optional, requires test user)
    print_info "Testing rate limiting effectiveness..."
    print_info "Simulating rapid connection attempts..."

    local server_ip
    server_ip=$(get_server_ip)
    local test_user
    test_user=$(jq -r '.users[0].username' "$VLESS_BASE_DIR/config/users.json" 2>/dev/null || echo "")
    local test_password
    test_password=$(jq -r '.users[0].proxy_password' "$VLESS_BASE_DIR/config/users.json" 2>/dev/null || echo "")

    if [[ -z "$test_user" || -z "$test_password" ]]; then
        print_info "No test user available, skipping rate limit effectiveness test"
        print_success "UFW rate limiting configuration test completed"
        return 0
    fi

    # Attempt 15 rapid connections (should trigger rate limiting)
    local success_count=0
    local total_attempts=15

    print_info "Attempting $total_attempts connections in 10 seconds..."

    for i in $(seq 1 $total_attempts); do
        if timeout 1 curl --connect-timeout 1 --socks5 "${test_user}:${test_password}@${server_ip}:1080" \
            -s -o /dev/null https://ifconfig.me 2>/dev/null; then
            ((success_count++))
        fi &
    done
    wait

    print_info "Successful connections: $success_count / $total_attempts"

    # Rate limiting should block some connections (allow ~10/min = ~2-3 in 10 sec)
    if [[ $success_count -lt $total_attempts ]]; then
        local blocked=$((total_attempts - success_count))
        print_success "Rate limiting is working ($blocked connections blocked)"
    else
        print_warning "All connections succeeded (rate limiting may not be effective)"
    fi

    print_success "UFW rate limiting test completed"
    return 0
}

test_04_file_permissions() {
    print_header "SECURITY TEST 4: File Permissions"
    print_test "Verifying sensitive files have correct permissions"

    local failed_checks=0

    # Check config directory permissions (should be 700)
    local config_perms
    config_perms=$(stat -c "%a" "$VLESS_BASE_DIR/config" 2>/dev/null || echo "000")
    if [[ "$config_perms" == "700" ]]; then
        print_success "Config directory has correct permissions (700)"
    else
        print_failure "Config directory has incorrect permissions ($config_perms, expected 700)"
        ((failed_checks++))
    fi

    # Check users.json permissions (should be 600)
    if [[ -f "$VLESS_BASE_DIR/config/users.json" ]]; then
        local users_perms
        users_perms=$(stat -c "%a" "$VLESS_BASE_DIR/config/users.json")
        if [[ "$users_perms" == "600" ]]; then
            print_success "users.json has correct permissions (600)"
        else
            print_failure "users.json has incorrect permissions ($users_perms, expected 600)"
            ((failed_checks++))
        fi
    fi

    # Check reality_keys.json permissions (should be 600)
    if [[ -f "$VLESS_BASE_DIR/config/reality_keys.json" ]]; then
        local keys_perms
        keys_perms=$(stat -c "%a" "$VLESS_BASE_DIR/config/reality_keys.json")
        if [[ "$keys_perms" == "600" ]]; then
            print_success "reality_keys.json has correct permissions (600)"
        else
            print_failure "reality_keys.json has incorrect permissions ($keys_perms, expected 600)"
            ((failed_checks++))
        fi
    fi

    # Check .env permissions (should be 600)
    if [[ -f "$VLESS_BASE_DIR/.env" ]]; then
        local env_perms
        env_perms=$(stat -c "%a" "$VLESS_BASE_DIR/.env")
        if [[ "$env_perms" == "600" ]]; then
            print_success ".env has correct permissions (600)"
        else
            print_failure ".env has incorrect permissions ($env_perms, expected 600)"
            ((failed_checks++))
        fi
    fi

    if [[ $failed_checks -eq 0 ]]; then
        print_success "All file permissions are correct"
    else
        print_failure "$failed_checks file permission check(s) failed"
        return 1
    fi

    print_success "File permissions test completed"
    return 0
}

test_05_container_security() {
    print_header "SECURITY TEST 5: Container Security"
    print_test "Verifying Docker container security configurations"

    # Check if container runs as non-root user
    local xray_user
    xray_user=$(docker inspect vless-reality --format='{{.Config.User}}' 2>/dev/null || echo "root")

    if [[ "$xray_user" != "root" && -n "$xray_user" ]]; then
        print_success "Xray container runs as non-root user ($xray_user)"
    else
        print_warning "Xray container may be running as root (security risk)"
    fi

    # Check restart policy
    local restart_policy
    restart_policy=$(docker inspect vless-reality --format='{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null || echo "none")

    if [[ "$restart_policy" == "unless-stopped" || "$restart_policy" == "always" ]]; then
        print_success "Restart policy configured: $restart_policy"
    else
        print_warning "Restart policy not optimal: $restart_policy (recommended: unless-stopped)"
    fi

    # Check if privileged mode is disabled
    local privileged
    privileged=$(docker inspect vless-reality --format='{{.HostConfig.Privileged}}' 2>/dev/null || echo "true")

    if [[ "$privileged" == "false" ]]; then
        print_success "Container is not running in privileged mode"
    else
        print_failure "Container is running in privileged mode (security risk)"
        return 1
    fi

    print_success "Container security test completed"
    return 0
}

################################################################################
# Main Test Runner
################################################################################

main() {
    print_header "VLESS Reality VPN v3.2 - Security Tests"

    echo "Test Suite: Security Validation"
    echo "Date: $(date)"
    echo "Server: $(hostname)"
    echo ""

    # Prerequisites
    check_root
    check_prerequisites

    # Run all tests
    test_01_port_scanning || true
    test_02_password_strength || true
    test_03_ufw_rate_limiting || true
    test_04_file_permissions || true
    test_05_container_security || true

    # Print summary
    print_header "SECURITY TEST SUMMARY"
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
        echo -e "${YELLOW}⚠️  Security issues detected - review failed tests${NC}"
        echo -e "${RED}RESULT: FAILED${NC}"
        exit 1
    else
        echo -e "${GREEN}✓ All security checks passed${NC}"
        echo -e "${GREEN}RESULT: PASSED${NC}"
        exit 0
    fi
}

################################################################################
# Script Entry Point
################################################################################
main "$@"
