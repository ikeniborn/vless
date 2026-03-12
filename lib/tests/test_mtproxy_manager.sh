#!/bin/bash
# ============================================================================
# MTProxy Manager Unit Test Suite
# Part of familyTraffic VPN Deployment System (v5.33)
#
# Purpose: Unit tests for generate_mtg_toml() in lib/mtproxy_manager.sh
#          All tests run without Docker — pure shell logic only.
#
# Usage:
#   sudo bash lib/tests/test_mtproxy_manager.sh
#   DEV_MODE=true sudo bash lib/tests/test_mtproxy_manager.sh
#
# Version: 1.0.0
# Date: 2026-03-12
# ============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

readonly TEST_ROOT="/tmp/ft_mtproxy_unit_$$"
readonly PROJECT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../" && pwd)"

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

# =============================================================================
# SETUP & TEARDOWN
# =============================================================================

setup_test_environment() {
    echo -e "${CYAN}Setting up test environment...${NC}"

    # Create isolated directory structure
    mkdir -p "${TEST_ROOT}/config/mtproxy"

    # Export overridden paths BEFORE sourcing mtproxy_manager.sh
    # This uses the readonly-guard pattern in the module.
    export VLESS_HOME="${TEST_ROOT}"
    export MTPROXY_CONFIG_DIR="${TEST_ROOT}/config/mtproxy"
    export MTG_CONFIG_FILE="${TEST_ROOT}/config/mtproxy/mtg.toml"
    export MTPROXY_SECRETS_JSON="${TEST_ROOT}/config/mtproxy/secrets.json"
    export MTPROXY_PORT="2053"
    export MTG_CLOAK_PORT="4443"

    # Source mtproxy_manager.sh (suppress output — sourcing produces no user-visible init)
    if [[ -f "${PROJECT_LIB}/mtproxy_manager.sh" ]]; then
        # shellcheck disable=SC1090
        source "${PROJECT_LIB}/mtproxy_manager.sh" 2>/dev/null || true
    else
        echo -e "${RED}ERROR: ${PROJECT_LIB}/mtproxy_manager.sh not found${NC}" >&2
        exit 1
    fi

    echo -e "${GREEN}✓ Test environment ready (root: ${TEST_ROOT})${NC}"
    echo ""
}

teardown_test_environment() {
    echo ""
    echo -e "${CYAN}Cleaning up test environment...${NC}"
    rm -rf "${TEST_ROOT}"
    echo -e "${GREEN}✓ Cleanup complete${NC}"
}

# Helper: create a valid secrets.json with a given secret
create_secrets_json() {
    local secret="${1}"
    local type="${2:-ee}"
    cat > "${MTPROXY_SECRETS_JSON}" <<EOF
{
  "version": "1.0",
  "secrets": [
    {
      "id": "test-secret-001",
      "type": "${type}",
      "secret": "${secret}",
      "domain": "test.example.com",
      "created_at": "2026-03-12T00:00:00Z"
    }
  ]
}
EOF
}

# Remove generated toml before each test that needs a clean state
clean_toml() {
    rm -f "${MTG_CONFIG_FILE}" "${MTG_CONFIG_FILE}.bak"
}

# =============================================================================
# TEST UTILITIES
# =============================================================================

assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"

    ((++TESTS_RUN))

    if [[ "$expected" == "$actual" ]]; then
        echo -e "  ${GREEN}✓${NC} $test_name"
        ((++TESTS_PASSED))
        return 0
    else
        echo -e "  ${RED}✗${NC} $test_name"
        echo "    Expected: $expected"
        echo "    Actual:   $actual"
        ((++TESTS_FAILED))
        return 1
    fi
}

assert_file_exists() {
    local file_path="$1"
    local test_name="$2"

    ((++TESTS_RUN))

    if [[ -f "$file_path" ]]; then
        echo -e "  ${GREEN}✓${NC} $test_name"
        ((++TESTS_PASSED))
        return 0
    else
        echo -e "  ${RED}✗${NC} $test_name"
        echo "    File not found: $file_path"
        ((++TESTS_FAILED))
        return 1
    fi
}

assert_file_not_exists() {
    local file_path="$1"
    local test_name="$2"

    ((++TESTS_RUN))

    if [[ ! -f "$file_path" ]]; then
        echo -e "  ${GREEN}✓${NC} $test_name"
        ((++TESTS_PASSED))
        return 0
    else
        echo -e "  ${RED}✗${NC} $test_name"
        echo "    File unexpectedly exists: $file_path"
        ((++TESTS_FAILED))
        return 1
    fi
}

# grep-based content check
assert_contains() {
    local file="$1"
    local pattern="$2"
    local test_name="$3"

    ((++TESTS_RUN))

    if grep -qE "$pattern" "$file" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $test_name"
        ((++TESTS_PASSED))
        return 0
    else
        echo -e "  ${RED}✗${NC} $test_name"
        echo "    Pattern not found: $pattern"
        echo "    File: $file"
        ((++TESTS_FAILED))
        return 1
    fi
}

assert_exit_nonzero() {
    local exit_code="$1"
    local test_name="$2"

    ((++TESTS_RUN))

    if [[ "$exit_code" -ne 0 ]]; then
        echo -e "  ${GREEN}✓${NC} $test_name"
        ((++TESTS_PASSED))
        return 0
    else
        echo -e "  ${RED}✗${NC} $test_name"
        echo "    Expected non-zero exit, got 0"
        ((++TESTS_FAILED))
        return 1
    fi
}

# =============================================================================
# TEST CASES
# =============================================================================

test_01_generate_toml_valid_secret() {
    echo -e "${BLUE}Test 01: generate_mtg_toml — valid ee-secret creates mtg.toml${NC}"

    clean_toml
    create_secrets_json "ee1234567890abcdef1234567890abcdef" "ee"

    generate_mtg_toml "proxy.example.com" >/dev/null 2>&1

    assert_file_exists "${MTG_CONFIG_FILE}" "mtg.toml created"
    assert_contains "${MTG_CONFIG_FILE}" 'secret = "ee' "secret line starts with ee"
    assert_contains "${MTG_CONFIG_FILE}" 'debug = false' "debug = false present"

    echo ""
}

test_02_toml_bind_to_uses_mtproxy_port() {
    echo -e "${BLUE}Test 02: generate_mtg_toml — bind-to uses MTPROXY_PORT (2053)${NC}"

    clean_toml
    create_secrets_json "ee1234567890abcdef1234567890abcdef" "ee"

    generate_mtg_toml "proxy.example.com" >/dev/null 2>&1

    assert_contains "${MTG_CONFIG_FILE}" 'bind-to = "0\.0\.0\.0:2053"' "bind-to contains port 2053"

    echo ""
}

test_03_toml_cloak_port_matches_variable() {
    echo -e "${BLUE}Test 03: generate_mtg_toml — [cloak] port = MTG_CLOAK_PORT (4443)${NC}"

    clean_toml
    create_secrets_json "ee1234567890abcdef1234567890abcdef" "ee"

    generate_mtg_toml "proxy.example.com" >/dev/null 2>&1

    assert_contains "${MTG_CONFIG_FILE}" 'port = 4443' "[cloak] port = 4443"

    echo ""
}

test_04_toml_has_all_required_fields() {
    echo -e "${BLUE}Test 04: generate_mtg_toml — all required sections present${NC}"

    clean_toml
    create_secrets_json "ee1234567890abcdef1234567890abcdef" "ee"

    generate_mtg_toml "proxy.example.com" >/dev/null 2>&1

    assert_contains "${MTG_CONFIG_FILE}" '\[network\.timeout\]' "[network.timeout] section present"
    assert_contains "${MTG_CONFIG_FILE}" '\[cloak\]' "[cloak] section present"

    echo ""
}

test_05_validation_rejects_dd_secret() {
    echo -e "${BLUE}Test 05: generate_mtg_toml — dd-secret → exit 1, no mtg.toml${NC}"

    clean_toml
    # dd-secret does NOT start with "ee"
    create_secrets_json "dd1234567890abcdef1234567890abcdef" "dd"

    local exit_code=0
    generate_mtg_toml "proxy.example.com" >/dev/null 2>&1 || exit_code=$?

    assert_exit_nonzero "$exit_code" "exit code non-zero for dd-secret"
    assert_file_not_exists "${MTG_CONFIG_FILE}" "mtg.toml NOT created for dd-secret"

    echo ""
}

test_06_error_missing_secrets_json() {
    echo -e "${BLUE}Test 06: generate_mtg_toml — missing secrets.json → exit 1${NC}"

    clean_toml
    rm -f "${MTPROXY_SECRETS_JSON}"

    local exit_code=0
    generate_mtg_toml "proxy.example.com" >/dev/null 2>&1 || exit_code=$?

    assert_exit_nonzero "$exit_code" "exit code non-zero when secrets.json missing"
    assert_file_not_exists "${MTG_CONFIG_FILE}" "mtg.toml NOT created when secrets.json missing"

    echo ""
}

test_07_error_empty_secrets_array() {
    echo -e "${BLUE}Test 07: generate_mtg_toml — empty secrets array → exit 1${NC}"

    clean_toml
    cat > "${MTPROXY_SECRETS_JSON}" <<'EOF'
{
  "version": "1.0",
  "secrets": []
}
EOF

    local exit_code=0
    generate_mtg_toml "proxy.example.com" >/dev/null 2>&1 || exit_code=$?

    assert_exit_nonzero "$exit_code" "exit code non-zero for empty secrets array"
    assert_file_not_exists "${MTG_CONFIG_FILE}" "mtg.toml NOT created for empty secrets"

    echo ""
}

test_08_error_empty_domain() {
    echo -e "${BLUE}Test 08: generate_mtg_toml — empty domain → exit 1${NC}"

    clean_toml
    create_secrets_json "ee1234567890abcdef1234567890abcdef" "ee"

    # No domain argument AND no .env file with DOMAIN=
    rm -f "${VLESS_HOME}/.env"

    local exit_code=0
    generate_mtg_toml "" >/dev/null 2>&1 || exit_code=$?

    assert_exit_nonzero "$exit_code" "exit code non-zero for empty domain"
    assert_file_not_exists "${MTG_CONFIG_FILE}" "mtg.toml NOT created for empty domain"

    echo ""
}

test_09_backup_on_regeneration() {
    echo -e "${BLUE}Test 09: generate_mtg_toml — second call creates mtg.toml.bak${NC}"

    clean_toml
    create_secrets_json "ee1234567890abcdef1234567890abcdef" "ee"

    # First call
    generate_mtg_toml "proxy.example.com" >/dev/null 2>&1

    # Second call — should create .bak
    generate_mtg_toml "proxy.example.com" >/dev/null 2>&1

    assert_file_exists "${MTG_CONFIG_FILE}.bak" "mtg.toml.bak created on second call"

    echo ""
}

test_10_file_permissions_600() {
    echo -e "${BLUE}Test 10: generate_mtg_toml — mtg.toml permissions = 600${NC}"

    clean_toml
    create_secrets_json "ee1234567890abcdef1234567890abcdef" "ee"

    generate_mtg_toml "proxy.example.com" >/dev/null 2>&1

    local perms
    perms=$(stat -c '%a' "${MTG_CONFIG_FILE}" 2>/dev/null || echo "000")
    assert_equals "600" "$perms" "mtg.toml permissions are 600"

    echo ""
}

# =============================================================================
# TEST RUNNER
# =============================================================================

run_all_tests() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║      MTProxy Manager Unit Test Suite (v1.0)                 ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    setup_test_environment

    test_01_generate_toml_valid_secret     || true
    test_02_toml_bind_to_uses_mtproxy_port || true
    test_03_toml_cloak_port_matches_variable || true
    test_04_toml_has_all_required_fields   || true
    test_05_validation_rejects_dd_secret   || true
    test_06_error_missing_secrets_json     || true
    test_07_error_empty_secrets_array      || true
    test_08_error_empty_domain             || true
    test_09_backup_on_regeneration         || true
    test_10_file_permissions_600           || true

    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                      TEST SUMMARY                            ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  Total Tests: $TESTS_RUN"
    echo -e "  ${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "  ${RED}Failed: $TESTS_FAILED${NC}"
    echo ""

    teardown_test_environment

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
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

    if ! command -v jq &>/dev/null; then
        echo -e "${RED}Error: jq is required but not installed${NC}" >&2
        exit 1
    fi

    run_all_tests
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
