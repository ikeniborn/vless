#!/bin/bash
#
# Test script for stunnel heredoc configuration generation
# Purpose: Verify that stunnel config is generated correctly without template
#

set -euo pipefail

echo "=========================================="
echo "stunnel Heredoc Generation Test"
echo "=========================================="
echo ""

# Test parameters
TEST_DOMAIN="vpn.example.com"
TEST_OUTPUT_DIR="/tmp/test_stunnel_$$"
TEST_CONFIG="${TEST_OUTPUT_DIR}/stunnel.conf"

# Setup test environment
mkdir -p "$TEST_OUTPUT_DIR"

# Export required variables
export CONFIG_DIR="$TEST_OUTPUT_DIR"
export LOG_DIR="$TEST_OUTPUT_DIR"
export TEMPLATE_DIR=""  # Not used anymore

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Source stunnel_setup module
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/stunnel_setup.sh"

echo "=== Test 1: Config Generation ==="
echo ""

# Generate config
if create_stunnel_config "$TEST_DOMAIN"; then
    echo "✓ Config generation successful"
else
    echo "✗ Config generation failed"
    exit 1
fi

echo ""
echo "=== Test 2: File Existence ==="
echo ""

if [[ -f "$TEST_CONFIG" ]]; then
    echo "✓ Config file exists: $TEST_CONFIG"
else
    echo "✗ Config file not found"
    exit 1
fi

echo ""
echo "=== Test 3: File Permissions ==="
echo ""

PERMS=$(stat -c "%a" "$TEST_CONFIG")
if [[ "$PERMS" == "600" ]]; then
    echo "✓ Permissions correct: 600"
else
    echo "✗ Incorrect permissions: $PERMS (expected 600)"
    exit 1
fi

echo ""
echo "=== Test 4: Domain Substitution ==="
echo ""

if grep -q "cert = /certs/live/$TEST_DOMAIN/fullchain.pem" "$TEST_CONFIG"; then
    echo "✓ SOCKS5 certificate path correct"
else
    echo "✗ SOCKS5 certificate path incorrect"
    cat "$TEST_CONFIG" | grep "cert ="
    exit 1
fi

if grep -q "key = /certs/live/$TEST_DOMAIN/privkey.pem" "$TEST_CONFIG"; then
    echo "✓ Private key path correct"
else
    echo "✗ Private key path incorrect"
    exit 1
fi

echo ""
echo "=== Test 5: Required Sections ==="
echo ""

# Check SOCKS5 section
if grep -q '^\[socks5-tls\]' "$TEST_CONFIG"; then
    echo "✓ [socks5-tls] section present"
else
    echo "✗ [socks5-tls] section missing"
    exit 1
fi

# Check HTTP section
if grep -q '^\[http-tls\]' "$TEST_CONFIG"; then
    echo "✓ [http-tls] section present"
else
    echo "✗ [http-tls] section missing"
    exit 1
fi

echo ""
echo "=== Test 6: SOCKS5 Configuration ==="
echo ""

# Check SOCKS5 accept port
if grep -A10 '^\[socks5-tls\]' "$TEST_CONFIG" | grep -q '^accept = 0.0.0.0:1080'; then
    echo "✓ SOCKS5 accept port correct (1080)"
else
    echo "✗ SOCKS5 accept port incorrect"
    exit 1
fi

# Check SOCKS5 connect
if grep -A10 '^\[socks5-tls\]' "$TEST_CONFIG" | grep -q '^connect = vless_xray:10800'; then
    echo "✓ SOCKS5 connect target correct (vless_xray:10800)"
else
    echo "✗ SOCKS5 connect target incorrect"
    exit 1
fi

# Check TLS version
if grep -A15 '^\[socks5-tls\]' "$TEST_CONFIG" | grep -q '^sslVersion = TLSv1.3'; then
    echo "✓ SOCKS5 TLS version correct (TLSv1.3)"
else
    echo "✗ SOCKS5 TLS version incorrect"
    exit 1
fi

echo ""
echo "=== Test 7: HTTP Configuration ==="
echo ""

# Check HTTP accept port
if grep -A10 '^\[http-tls\]' "$TEST_CONFIG" | grep -q '^accept = 0.0.0.0:8118'; then
    echo "✓ HTTP accept port correct (8118)"
else
    echo "✗ HTTP accept port incorrect"
    exit 1
fi

# Check HTTP connect
if grep -A10 '^\[http-tls\]' "$TEST_CONFIG" | grep -q '^connect = vless_xray:18118'; then
    echo "✓ HTTP connect target correct (vless_xray:18118)"
else
    echo "✗ HTTP connect target incorrect"
    exit 1
fi

echo ""
echo "=== Test 8: Security Settings ==="
echo ""

# Check cipher suites
if grep -q 'ciphersuites = TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256' "$TEST_CONFIG"; then
    echo "✓ TLS 1.3 cipher suites configured"
else
    echo "✗ Cipher suites incorrect"
    exit 1
fi

# Check client verification disabled
if grep -A15 '^\[socks5-tls\]' "$TEST_CONFIG" | grep -q '^verify = 0'; then
    echo "✓ Client verification disabled (verify = 0)"
else
    echo "✗ Client verification setting incorrect"
    exit 1
fi

echo ""
echo "=== Test 9: Generated Timestamp ==="
echo ""

if grep -q "Generated:" "$TEST_CONFIG"; then
    TIMESTAMP=$(grep "Generated:" "$TEST_CONFIG" | cut -d' ' -f3)
    echo "✓ Timestamp present: $TIMESTAMP"
else
    echo "⚠ No timestamp (not critical)"
fi

echo ""
echo "=== Test 10: Config Validation ==="
echo ""

# Use stunnel_setup validation function
if validate_stunnel_config; then
    echo "✓ Config validation passed"
else
    echo "✗ Config validation failed"
    exit 1
fi

echo ""
echo "=== Test 11: Line Count ==="
echo ""

LINE_COUNT=$(wc -l < "$TEST_CONFIG")
echo "Config has $LINE_COUNT lines"

if [[ $LINE_COUNT -gt 100 ]] && [[ $LINE_COUNT -lt 150 ]]; then
    echo "✓ Line count reasonable ($LINE_COUNT lines)"
else
    echo "⚠ Unexpected line count: $LINE_COUNT (expected ~130)"
fi

echo ""
echo "=== Test 12: No Template References ==="
echo ""

if grep -q '${DOMAIN}' "$TEST_CONFIG"; then
    echo "✗ CRITICAL: Template variable not substituted!"
    grep '${DOMAIN}' "$TEST_CONFIG"
    exit 1
else
    echo "✓ No template variables in config"
fi

# Cleanup
rm -rf "$TEST_OUTPUT_DIR"

echo ""
echo "=========================================="
echo "  ALL TESTS PASSED ✓"
echo "=========================================="
echo ""
echo "Summary:"
echo "  ✓ Config generation works without templates/"
echo "  ✓ Domain variable correctly substituted"
echo "  ✓ All required sections present"
echo "  ✓ Security settings correct (TLS 1.3, strong ciphers)"
echo "  ✓ Ports configured correctly (1080, 8118)"
echo "  ✓ File permissions correct (600)"
echo ""
echo "Migration from template to heredoc: SUCCESS"
echo ""
