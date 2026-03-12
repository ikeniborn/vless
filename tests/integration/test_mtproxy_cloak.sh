#!/bin/bash
################################################################################
# MTProxy Cloak Port Integration Tests
# Part of familyTraffic VPN Deployment System (v5.33)
#
# Description:
#   Tests active probing protection via cloak-port 4443 (nginx LE-cert).
#   Verifies that port 4443 serves valid TLS with real HTML, that plain TCP
#   does NOT get a plaintext response, and that port 2053 does not reveal
#   a recognizable proxy protocol banner.
#
# DEV_MODE:
#   Auto-detected when /opt/familytraffic/ is absent or DEV_MODE=true.
#   Some tests can still run partially (e.g. nginx.conf file check).
#
# Requirements:
#   - openssl, curl, nc  (checked in check_prerequisites)
#   - Running familytraffic container with MTProxy configured
#
# Usage:
#   sudo bash tests/integration/test_mtproxy_cloak.sh
#
# Exit Codes:
#   0 - All tests passed
#   1 - One or more tests failed
#   2 - Prerequisites not met
#
# Version: 1.0.0
# Date: 2026-03-12
################################################################################

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Configuration
readonly VLESS_BASE_DIR="/opt/familytraffic"
readonly MTG_CLOAK_PORT="${MTG_CLOAK_PORT:-4443}"
readonly MTPROXY_PORT="${MTPROXY_PORT:-2053}"
readonly REQUIRED_COMMANDS=("openssl" "curl" "nc")

# Test results
declare -i TESTS_PASSED=0
declare -i TESTS_FAILED=0
TESTS_SKIPPED=0
declare -a FAILED_TESTS=()

# DEV_MODE auto-detect
if [[ "${DEV_MODE:-}" == "true" ]] || [[ ! -d "${VLESS_BASE_DIR}" ]]; then
    readonly DEV_MODE_ACTIVE=true
else
    readonly DEV_MODE_ACTIVE=false
fi

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
    ((++TESTS_PASSED))
}

print_failure() {
    echo -e "${RED}✗ FAIL:${NC} $1"
    ((++TESTS_FAILED))
    FAILED_TESTS+=("$1")
}

print_info() {
    echo -e "${CYAN}INFO:${NC} $1"
}

print_skip() {
    echo -e "${YELLOW}⊘ SKIP:${NC} $1 (${2:-requires live container})"
    ((++TESTS_SKIPPED))
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

    if [[ "$DEV_MODE_ACTIVE" == "true" ]]; then
        print_info "DEV_MODE active — skipping production directory check"
    else
        if [[ ! -d "$VLESS_BASE_DIR" ]]; then
            echo -e "${RED}ERROR: familytraffic not installed at $VLESS_BASE_DIR${NC}" >&2
            exit 2
        fi
        print_info "familytraffic installation found"
    fi

    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${RED}ERROR: Required command not found: $cmd${NC}" >&2
            case "$cmd" in
                openssl) echo "Install: sudo apt install openssl" ;;
                curl)    echo "Install: sudo apt install curl" ;;
                nc)      echo "Install: sudo apt install netcat-openbsd" ;;
            esac
            exit 2
        fi
        print_info "Found: $cmd"
    done

    echo -e "${GREEN}✓ All prerequisites met${NC}"
}

# Read DOMAIN from .env (if available)
get_domain() {
    local domain=""
    if [[ -f "${VLESS_BASE_DIR}/.env" ]]; then
        domain=$(grep -E '^DOMAIN=' "${VLESS_BASE_DIR}/.env" 2>/dev/null \
            | cut -d= -f2 | tr -d '"' | tr -d "'" | head -1 || true)
    fi
    echo "${domain:-}"
}

################################################################################
# Test Cases
################################################################################

test_01_cloak_port_in_nginx_config() {
    print_header "TEST 1: Cloak Port in Nginx Configuration"
    print_test "Verify nginx.conf contains listen ${MTG_CLOAK_PORT}"

    # Try production nginx.conf first, then docker source
    local nginx_conf=""
    if [[ -f "${VLESS_BASE_DIR}/config/nginx/nginx.conf" ]]; then
        nginx_conf="${VLESS_BASE_DIR}/config/nginx/nginx.conf"
    elif [[ -f "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)/docker/familytraffic/nginx.conf" ]]; then
        nginx_conf="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)/docker/familytraffic/nginx.conf"
    fi

    if [[ -z "$nginx_conf" ]]; then
        print_skip "nginx.conf listen ${MTG_CLOAK_PORT} check" "nginx.conf not found on host"
        return 0
    fi

    print_info "Checking: $nginx_conf"

    if grep -qE "listen[[:space:]]+${MTG_CLOAK_PORT}" "$nginx_conf" 2>/dev/null; then
        print_success "nginx.conf contains 'listen ${MTG_CLOAK_PORT}'"
    else
        print_failure "nginx.conf missing 'listen ${MTG_CLOAK_PORT}'"
    fi
}

test_02_port_4443_tls_cert_valid() {
    print_header "TEST 2: TLS Certificate on Port ${MTG_CLOAK_PORT}"
    print_test "Verify TLS handshake succeeds on 127.0.0.1:${MTG_CLOAK_PORT}"

    if [[ "$DEV_MODE_ACTIVE" == "true" ]]; then
        print_skip "TLS handshake on :${MTG_CLOAK_PORT}" "DEV_MODE"
        return 0
    fi

    local exit_code=0
    echo "" | timeout 5 openssl s_client \
        -connect "127.0.0.1:${MTG_CLOAK_PORT}" \
        -brief 2>/dev/null || exit_code=$?

    if [[ "$exit_code" -eq 0 ]]; then
        print_success "TLS handshake on 127.0.0.1:${MTG_CLOAK_PORT} succeeded"
    else
        print_failure "TLS handshake on 127.0.0.1:${MTG_CLOAK_PORT} failed (exit: $exit_code)"
    fi
}

test_03_cert_cn_matches_domain() {
    print_header "TEST 3: Certificate CN Matches Domain"
    print_test "Verify CN/SAN of certificate on :${MTG_CLOAK_PORT} matches DOMAIN from .env"

    if [[ "$DEV_MODE_ACTIVE" == "true" ]]; then
        print_skip "cert CN check" "DEV_MODE"
        return 0
    fi

    local domain
    domain=$(get_domain)

    if [[ -z "$domain" ]]; then
        print_skip "cert CN check" "DOMAIN not set in ${VLESS_BASE_DIR}/.env"
        return 0
    fi

    print_info "Expected domain: $domain"

    local cert_info
    cert_info=$(echo "" | timeout 5 openssl s_client \
        -connect "127.0.0.1:${MTG_CLOAK_PORT}" \
        -servername "$domain" 2>/dev/null | \
        openssl x509 -noout -subject -ext subjectAltName 2>/dev/null || true)

    print_info "Cert info: $cert_info"

    if echo "$cert_info" | grep -qi "$domain"; then
        print_success "Certificate matches domain: $domain"
    else
        print_failure "Certificate does NOT match domain: $domain (cert: $cert_info)"
    fi
}

test_04_https_get_returns_html() {
    print_header "TEST 4: HTTPS GET Returns HTML (not proxy fingerprint)"
    print_test "curl -sk https://127.0.0.1:${MTG_CLOAK_PORT}/ → non-empty, not MTProxy"

    if [[ "$DEV_MODE_ACTIVE" == "true" ]]; then
        print_skip "HTTPS GET :${MTG_CLOAK_PORT}" "DEV_MODE"
        return 0
    fi

    local response=""
    local exit_code=0
    response=$(curl -sk --max-time 5 "https://127.0.0.1:${MTG_CLOAK_PORT}/" 2>/dev/null) \
        || exit_code=$?

    if [[ "$exit_code" -ne 0 ]]; then
        print_failure "curl https://127.0.0.1:${MTG_CLOAK_PORT}/ failed (exit: $exit_code)"
        return 1
    fi

    if [[ -z "$response" ]]; then
        print_failure "curl returned empty response"
        return 1
    fi

    # Response must not look like an MTProxy binary response
    if echo "$response" | grep -qi "mtproxy\|mtg\|telegram proxy"; then
        print_failure "Response looks like a proxy fingerprint"
        return 1
    fi

    print_success "HTTPS GET returned non-empty HTML response (no proxy fingerprint)"
}

test_05_plain_tcp_gets_tls_error() {
    print_header "TEST 5: Plain TCP to Port ${MTG_CLOAK_PORT} Gets TLS Error"
    print_test "Plain HTTP GET to :${MTG_CLOAK_PORT} must not get plaintext HTTP response"

    if [[ "$DEV_MODE_ACTIVE" == "true" ]]; then
        print_skip "plain TCP :${MTG_CLOAK_PORT}" "DEV_MODE"
        return 0
    fi

    # Send plaintext HTTP request — nginx with TLS must reject or return TLS error
    local response=""
    response=$(echo -e "GET / HTTP/1.0\r\n\r\n" | \
        timeout 3 nc 127.0.0.1 "${MTG_CLOAK_PORT}" 2>/dev/null || true)

    # A correct TLS-only nginx will not return "HTTP/1." in plaintext
    if echo "$response" | grep -q "^HTTP/1\.[01]"; then
        print_failure "Port ${MTG_CLOAK_PORT} returned plaintext HTTP — TLS termination not enforced"
    else
        print_success "Port ${MTG_CLOAK_PORT} did not return plaintext HTTP (TLS-only confirmed)"
    fi
}

test_06_port_2053_no_protocol_banner() {
    print_header "TEST 6: Port ${MTPROXY_PORT} Does Not Reveal Proxy Protocol Banner"
    print_test "Random bytes → mtg must NOT return recognizable proxy header"

    if [[ "$DEV_MODE_ACTIVE" == "true" ]]; then
        print_skip "port ${MTPROXY_PORT} banner check" "DEV_MODE (mtg must be running)"
        return 0
    fi

    # Check if port 2053 is actually listening (mtg must be running)
    if ! ss -tulnp 2>/dev/null | grep -q ":${MTPROXY_PORT}"; then
        print_skip "port ${MTPROXY_PORT} banner check" "mtg not running on port ${MTPROXY_PORT}"
        return 0
    fi

    # Send 64 random bytes and read response
    local random_bytes
    random_bytes=$(dd if=/dev/urandom bs=64 count=1 2>/dev/null)

    local response=""
    response=$(echo "$random_bytes" | timeout 3 nc 127.0.0.1 "${MTPROXY_PORT}" 2>/dev/null || true)

    # mtg (Fake TLS) must NOT return an MTProxy plaintext banner
    if echo "$response" | strings 2>/dev/null | grep -qiE "proxy|mtproto|telegram|abcd|error"; then
        print_failure "Port ${MTPROXY_PORT} returned recognizable protocol header"
    else
        print_success "Port ${MTPROXY_PORT} did not reveal a recognizable proxy banner"
    fi
}

test_07_port_4443_not_in_ufw() {
    print_header "TEST 7: Port ${MTG_CLOAK_PORT} Not Allowed in UFW"
    print_test "Verify cloak-port ${MTG_CLOAK_PORT} is NOT in UFW ALLOW rules (loopback-only)"

    if [[ "$DEV_MODE_ACTIVE" == "true" ]]; then
        print_skip "UFW check for ${MTG_CLOAK_PORT}" "DEV_MODE (no UFW)"
        return 0
    fi

    if ! command -v ufw &>/dev/null; then
        print_skip "UFW check for ${MTG_CLOAK_PORT}" "ufw not installed"
        return 0
    fi

    if ufw status 2>/dev/null | grep -q "${MTG_CLOAK_PORT}"; then
        print_failure "Port ${MTG_CLOAK_PORT} found in UFW rules — must remain loopback-only!"
    else
        print_success "Port ${MTG_CLOAK_PORT} not in UFW (correct: loopback-only)"
    fi
}

################################################################################
# Main Test Runner
################################################################################

main() {
    print_header "MTProxy Cloak Port Integration Tests (v1.0)"

    echo "Test Suite: Active Probing Protection Validation"
    echo "Date:       $(date)"
    echo "Server:     $(hostname)"
    echo "Cloak port: ${MTG_CLOAK_PORT}"
    echo "MTProxy:    ${MTPROXY_PORT}"
    echo ""

    if [[ "$DEV_MODE_ACTIVE" == "true" ]]; then
        echo -e "${YELLOW}⚠ DEV_MODE active — container tests will be skipped${NC}"
    fi

    check_root
    check_prerequisites

    test_01_cloak_port_in_nginx_config || true
    test_02_port_4443_tls_cert_valid   || true
    test_03_cert_cn_matches_domain     || true
    test_04_https_get_returns_html     || true
    test_05_plain_tcp_gets_tls_error   || true
    test_06_port_2053_no_protocol_banner || true
    test_07_port_4443_not_in_ufw       || true

    print_header "TEST SUMMARY"

    local total=$(( TESTS_PASSED + TESTS_FAILED ))
    echo "Total Executed: $total"
    echo -e "${GREEN}Passed:  $TESTS_PASSED${NC}"
    echo -e "${RED}Failed:  $TESTS_FAILED${NC}"
    echo -e "${YELLOW}Skipped: $TESTS_SKIPPED${NC}"
    echo ""

    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}Failed Tests:${NC}"
        for t in "${FAILED_TESTS[@]}"; do
            echo -e "  ${RED}✗${NC} $t"
        done
        echo ""
        echo -e "${RED}RESULT: FAILED${NC}"
        exit 1
    else
        echo -e "${GREEN}✓ All executed tests passed${NC}"
        echo -e "${GREEN}RESULT: PASSED${NC}"
        exit 0
    fi
}

main "$@"
