#!/bin/bash
# ============================================================================
# MTProxy Integration Test Suite
# Part of familyTraffic VPN Deployment System (v5.33)
#
# Purpose: Integration tests for MTProxy supervisord lifecycle, port 2053,
#          cloak-port 4443, and UFW rules.
#
# DEV_MODE: auto-detected when /opt/familytraffic/ is absent or DEV_MODE=true.
#           Container-dependent tests are skipped in DEV_MODE.
#           Static checks (supervisord.conf content) always run.
#
# Usage:
#   # DEV_MODE (no Docker required):
#   DEV_MODE=true sudo bash lib/tests/test_mtproxy_integration.sh
#
#   # Full integration (requires running familytraffic container):
#   sudo bash lib/tests/test_mtproxy_integration.sh
#
# Version: 1.0.0
# Date: 2026-03-12
# ============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

readonly TEST_ROOT="/tmp/ft_mtproxy_integration_$$"

# Locate supervisord.conf — prefer production path, fall back to project source
SUPERVISORD_CONF_CANDIDATE=""
if [[ -f "/opt/familytraffic/config/supervisord.conf" ]]; then
    SUPERVISORD_CONF_CANDIDATE="/opt/familytraffic/config/supervisord.conf"
elif [[ -f "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)/docker/familytraffic/supervisord.conf" ]]; then
    SUPERVISORD_CONF_CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)/docker/familytraffic/supervisord.conf"
fi
readonly SUPERVISORD_CONF="${SUPERVISORD_CONF_CANDIDATE}"

# DEV_MODE auto-detect
if [[ "${DEV_MODE:-}" == "true" ]] || [[ ! -d "/opt/familytraffic" ]]; then
    readonly DEV_MODE_ACTIVE=true
else
    readonly DEV_MODE_ACTIVE=false
fi

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# =============================================================================
# HELPERS
# =============================================================================

assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    ((++TESTS_RUN))
    if [[ "$expected" == "$actual" ]]; then
        echo -e "  ${GREEN}✓${NC} $test_name"
        ((++TESTS_PASSED))
    else
        echo -e "  ${RED}✗${NC} $test_name"
        echo "    Expected: $expected"
        echo "    Actual:   $actual"
        ((++TESTS_FAILED))
    fi
}

assert_file_exists() {
    local file_path="$1"
    local test_name="$2"
    ((++TESTS_RUN))
    if [[ -f "$file_path" ]]; then
        echo -e "  ${GREEN}✓${NC} $test_name"
        ((++TESTS_PASSED))
    else
        echo -e "  ${RED}✗${NC} $test_name"
        echo "    File not found: $file_path"
        ((++TESTS_FAILED))
    fi
}

assert_contains() {
    local file="$1"
    local pattern="$2"
    local test_name="$3"
    ((++TESTS_RUN))
    if grep -qE "$pattern" "$file" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $test_name"
        ((++TESTS_PASSED))
    else
        echo -e "  ${RED}✗${NC} $test_name"
        echo "    Pattern not found: $pattern"
        echo "    File: $file"
        ((++TESTS_FAILED))
    fi
}

skip_test() {
    local test_name="$1"
    local reason="${2:-requires running container}"
    echo -e "  ${YELLOW}⊘${NC} $test_name (skipped: $reason)"
    ((++TESTS_SKIPPED))
}

# =============================================================================
# TEST CASES
# =============================================================================

test_01_mtg_binary_in_container() {
    echo -e "${BLUE}Test 01: mtg binary present in familytraffic container${NC}"

    if [[ "$DEV_MODE_ACTIVE" == "true" ]]; then
        skip_test "mtg binary in container" "DEV_MODE"
        echo ""
        return 0
    fi

    local exit_code=0
    docker exec familytraffic which mtg >/dev/null 2>&1 || exit_code=$?
    assert_equals "0" "$exit_code" "docker exec familytraffic which mtg → exit 0"

    echo ""
}

test_02_mtg_version_output() {
    echo -e "${BLUE}Test 02: mtg --version reports v2.x${NC}"

    if [[ "$DEV_MODE_ACTIVE" == "true" ]]; then
        skip_test "mtg --version" "DEV_MODE"
        echo ""
        return 0
    fi

    local version_output
    version_output=$(docker exec familytraffic mtg --version 2>&1 || true)

    ((++TESTS_RUN))
    if echo "$version_output" | grep -q "2\."; then
        echo -e "  ${GREEN}✓${NC} mtg version contains '2.' (got: ${version_output})"
        ((++TESTS_PASSED))
    else
        echo -e "  ${RED}✗${NC} mtg version does not contain '2.' (got: ${version_output})"
        ((++TESTS_FAILED))
    fi

    echo ""
}

test_03_supervisord_config_mtg_section() {
    echo -e "${BLUE}Test 03: supervisord.conf contains [program:mtg] section${NC}"

    if [[ -z "${SUPERVISORD_CONF}" ]] || [[ ! -f "${SUPERVISORD_CONF}" ]]; then
        ((++TESTS_RUN))
        echo -e "  ${RED}✗${NC} supervisord.conf not found (searched: /opt/familytraffic/config/ and docker/familytraffic/)"
        ((++TESTS_FAILED))
        echo ""
        return 1
    fi

    assert_contains "${SUPERVISORD_CONF}" '^\[program:mtg\]' "[program:mtg] section present"
    assert_contains "${SUPERVISORD_CONF}" 'autostart=false' "autostart=false (mtg disabled by default)"
    assert_contains "${SUPERVISORD_CONF}" 'priority=4' "priority=4 (mtg starts last)"

    echo ""
}

test_04_supervisord_knows_mtg_program() {
    echo -e "${BLUE}Test 04: supervisorctl inside container knows 'mtg' program${NC}"

    if [[ "$DEV_MODE_ACTIVE" == "true" ]]; then
        skip_test "supervisorctl status mtg" "DEV_MODE"
        echo ""
        return 0
    fi

    local status_output
    status_output=$(docker exec familytraffic supervisorctl status mtg 2>&1 || true)

    ((++TESTS_RUN))
    if echo "$status_output" | grep -qi "unknown program\|no such process"; then
        echo -e "  ${RED}✗${NC} supervisorctl does not know 'mtg' program (output: ${status_output})"
        ((++TESTS_FAILED))
    else
        echo -e "  ${GREEN}✓${NC} supervisorctl recognizes 'mtg' program"
        ((++TESTS_PASSED))
    fi

    echo ""
}

test_05_mtg_start_and_port_2053() {
    echo -e "${BLUE}Test 05: starting mtg via supervisorctl opens port 2053${NC}"

    if [[ "$DEV_MODE_ACTIVE" == "true" ]]; then
        skip_test "start mtg + port 2053" "DEV_MODE"
        echo ""
        return 0
    fi

    # Ensure mtg is stopped first
    docker exec familytraffic supervisorctl stop mtg >/dev/null 2>&1 || true
    sleep 1

    # Start mtg
    docker exec familytraffic supervisorctl start mtg >/dev/null 2>&1 || true
    sleep 3

    # Check port 2053 is listening
    local port_open=0
    if docker exec familytraffic ss -tulnp 2>/dev/null | grep -q ':2053'; then
        port_open=1
    fi

    ((++TESTS_RUN))
    if [[ "$port_open" -eq 1 ]]; then
        echo -e "  ${GREEN}✓${NC} Port 2053 is listening after supervisorctl start mtg"
        ((++TESTS_PASSED))
    else
        echo -e "  ${RED}✗${NC} Port 2053 NOT listening after supervisorctl start mtg"
        ((++TESTS_FAILED))
    fi

    # Cleanup: stop mtg
    docker exec familytraffic supervisorctl stop mtg >/dev/null 2>&1 || true

    echo ""
}

test_06_port_4443_tls_handshake() {
    echo -e "${BLUE}Test 06: port 4443 (cloak-port) accepts TLS handshake${NC}"

    if [[ "$DEV_MODE_ACTIVE" == "true" ]]; then
        skip_test "port 4443 TLS handshake" "DEV_MODE"
        echo ""
        return 0
    fi

    local exit_code=0
    echo "" | openssl s_client -connect 127.0.0.1:4443 -timeout 5 \
        >/dev/null 2>&1 || exit_code=$?

    ((++TESTS_RUN))
    if [[ "$exit_code" -eq 0 ]]; then
        echo -e "  ${GREEN}✓${NC} openssl s_client 127.0.0.1:4443 → TLS handshake succeeded"
        ((++TESTS_PASSED))
    else
        echo -e "  ${RED}✗${NC} openssl s_client 127.0.0.1:4443 → TLS handshake failed (exit: $exit_code)"
        ((++TESTS_FAILED))
    fi

    echo ""
}

test_07_port_4443_returns_html() {
    echo -e "${BLUE}Test 07: HTTPS GET to port 4443 returns non-empty HTML${NC}"

    if [[ "$DEV_MODE_ACTIVE" == "true" ]]; then
        skip_test "HTTPS GET :4443" "DEV_MODE"
        echo ""
        return 0
    fi

    local response
    local exit_code=0
    response=$(curl -sk --max-time 5 https://127.0.0.1:4443/ 2>/dev/null) || exit_code=$?

    ((++TESTS_RUN))
    if [[ "$exit_code" -eq 0 ]] && [[ -n "$response" ]]; then
        echo -e "  ${GREEN}✓${NC} curl https://127.0.0.1:4443/ → exit 0, non-empty response"
        ((++TESTS_PASSED))
    else
        echo -e "  ${RED}✗${NC} curl https://127.0.0.1:4443/ failed (exit: $exit_code, empty: $([[ -z "$response" ]] && echo yes || echo no))"
        ((++TESTS_FAILED))
    fi

    echo ""
}

test_08_ufw_rule_2053_after_setup() {
    echo -e "${BLUE}Test 08: UFW allows 2053/tcp after mtproxy setup${NC}"

    if [[ "$DEV_MODE_ACTIVE" == "true" ]]; then
        skip_test "UFW rule 2053/tcp" "DEV_MODE (no UFW)"
        echo ""
        return 0
    fi

    if ! command -v ufw &>/dev/null; then
        skip_test "UFW rule 2053/tcp" "ufw not installed"
        echo ""
        return 0
    fi

    ((++TESTS_RUN))
    if ufw status 2>/dev/null | grep -q "2053/tcp.*ALLOW"; then
        echo -e "  ${GREEN}✓${NC} UFW ALLOW 2053/tcp rule exists"
        ((++TESTS_PASSED))
    else
        echo -e "  ${RED}✗${NC} UFW ALLOW 2053/tcp rule NOT found (run: mtproxy setup)"
        ((++TESTS_FAILED))
    fi

    echo ""
}

test_09_port_4443_no_ufw_rule() {
    echo -e "${BLUE}Test 09: UFW does NOT allow 4443 (cloak-port is loopback-only)${NC}"

    if [[ "$DEV_MODE_ACTIVE" == "true" ]]; then
        skip_test "UFW no rule for 4443" "DEV_MODE (no UFW)"
        echo ""
        return 0
    fi

    if ! command -v ufw &>/dev/null; then
        skip_test "UFW no rule for 4443" "ufw not installed"
        echo ""
        return 0
    fi

    ((++TESTS_RUN))
    if ufw status 2>/dev/null | grep -q "4443"; then
        echo -e "  ${RED}✗${NC} UFW has a rule for 4443 — cloak-port must remain loopback-only!"
        ((++TESTS_FAILED))
    else
        echo -e "  ${GREEN}✓${NC} Port 4443 NOT in UFW (correct: loopback-only)"
        ((++TESTS_PASSED))
    fi

    echo ""
}

# =============================================================================
# TEST RUNNER
# =============================================================================

run_all_tests() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║      MTProxy Integration Test Suite (v1.0)                  ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [[ "$DEV_MODE_ACTIVE" == "true" ]]; then
        echo -e "${YELLOW}⚠ DEV_MODE active — container tests will be skipped${NC}"
    else
        echo -e "${GREEN}✓ Production mode — all tests will run${NC}"
    fi
    echo ""

    test_01_mtg_binary_in_container        || true
    test_02_mtg_version_output             || true
    test_03_supervisord_config_mtg_section || true
    test_04_supervisord_knows_mtg_program  || true
    test_05_mtg_start_and_port_2053        || true
    test_06_port_4443_tls_handshake        || true
    test_07_port_4443_returns_html         || true
    test_08_ufw_rule_2053_after_setup      || true
    test_09_port_4443_no_ufw_rule          || true

    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                      TEST SUMMARY                            ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  Total Tests Run: $TESTS_RUN"
    echo -e "  ${GREEN}Passed:  $TESTS_PASSED${NC}"
    echo -e "  ${RED}Failed:  $TESTS_FAILED${NC}"
    echo -e "  ${YELLOW}Skipped: $TESTS_SKIPPED${NC}"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ All executed tests passed!${NC}"
        return 0
    else
        echo -e "${RED}✗ $TESTS_FAILED test(s) failed${NC}"
        return 1
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root${NC}" >&2
        echo "Please use: sudo bash $0" >&2
        exit 1
    fi

    run_all_tests
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
