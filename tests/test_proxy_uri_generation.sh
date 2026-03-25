#!/bin/bash
# Test script to verify proxy URI generation with correct schemes
# Tests both localhost and public proxy modes

set -euo pipefail

echo "=========================================="
echo "Proxy URI Generation Test"
echo "=========================================="
echo ""

# Test parameters
TEST_USERNAME="proxy-dev"
TEST_PASSWORD="1d1ce6a71943a7012ed474ba8a803099"
TEST_DOMAIN="proxy-dev.ikeniborn.ru"
TEST_OUTPUT_DIR="/tmp/test_proxy_configs_$$"

# Create test directory
mkdir -p "$TEST_OUTPUT_DIR"

# Source the user_management functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export VLESS_HOME="/tmp/test_familytraffic_$$"
export CLIENTS_DIR="${VLESS_HOME}/data/clients"
export ENV_FILE="${VLESS_HOME}/.env"

mkdir -p "${VLESS_HOME}/data/clients"
mkdir -p "$(dirname "$ENV_FILE")"

echo ""
echo "=== Test 1: Localhost Mode (No TLS) ==="
echo ""

# Configure localhost mode
cat > "$ENV_FILE" <<EOF
ENABLE_PUBLIC_PROXY=false
DOMAIN=
EOF

export ENABLE_PUBLIC_PROXY="false"
export DOMAIN=""

# Source functions
source "${SCRIPT_DIR}/lib/user_management.sh"

# Generate configs
export_http_config "$TEST_USERNAME" "$TEST_PASSWORD" "$TEST_OUTPUT_DIR"
export_socks5_config "$TEST_USERNAME" "$TEST_PASSWORD" "$TEST_OUTPUT_DIR"

# Read generated URIs
HTTP_URI=$(cat "$TEST_OUTPUT_DIR/http_config.txt")
SOCKS5_URI=$(cat "$TEST_OUTPUT_DIR/socks5_config.txt")

echo "HTTP URI:   $HTTP_URI"
echo "SOCKS5 URI: $SOCKS5_URI"

# Validate
EXPECTED_HTTP_LOCAL="http://${TEST_USERNAME}:${TEST_PASSWORD}@127.0.0.1:8118"
EXPECTED_SOCKS5_LOCAL="socks5://${TEST_USERNAME}:${TEST_PASSWORD}@127.0.0.1:1080"

if [[ "$HTTP_URI" == "$EXPECTED_HTTP_LOCAL" ]]; then
    echo "✓ HTTP URI correct (localhost, no TLS)"
else
    echo "✗ HTTP URI incorrect."
    echo "  Expected: $EXPECTED_HTTP_LOCAL"
    echo "  Got:      $HTTP_URI"
fi

if [[ "$SOCKS5_URI" == "$EXPECTED_SOCKS5_LOCAL" ]]; then
    echo "✓ SOCKS5 URI correct (localhost, no TLS)"
else
    echo "✗ SOCKS5 URI incorrect."
    echo "  Expected: $EXPECTED_SOCKS5_LOCAL"
    echo "  Got:      $SOCKS5_URI"
fi

echo ""
echo "=== Test 2: Public Proxy Mode (With TLS) ==="
echo ""

# Configure public proxy mode
cat > "$ENV_FILE" <<EOF
ENABLE_PUBLIC_PROXY=true
DOMAIN=${TEST_DOMAIN}
EOF

export ENABLE_PUBLIC_PROXY="true"
export DOMAIN="$TEST_DOMAIN"

# Generate configs
rm -f "$TEST_OUTPUT_DIR/http_config.txt" "$TEST_OUTPUT_DIR/socks5_config.txt"
export_http_config "$TEST_USERNAME" "$TEST_PASSWORD" "$TEST_OUTPUT_DIR"
export_socks5_config "$TEST_USERNAME" "$TEST_PASSWORD" "$TEST_OUTPUT_DIR"

# Read generated URIs
HTTP_URI=$(cat "$TEST_OUTPUT_DIR/http_config.txt")
SOCKS5_URI=$(cat "$TEST_OUTPUT_DIR/socks5_config.txt")

echo "HTTP URI:   $HTTP_URI"
echo "SOCKS5 URI: $SOCKS5_URI"

# Validate
EXPECTED_HTTP="https://${TEST_USERNAME}:${TEST_PASSWORD}@${TEST_DOMAIN}:8118"
EXPECTED_SOCKS5="socks5s://${TEST_USERNAME}:${TEST_PASSWORD}@${TEST_DOMAIN}:1080"

if [[ "$HTTP_URI" == "$EXPECTED_HTTP" ]]; then
    echo "✓ HTTP URI correct (public, with TLS)"
else
    echo "✗ HTTP URI incorrect."
    echo "  Expected: $EXPECTED_HTTP"
    echo "  Got:      $HTTP_URI"
fi

if [[ "$SOCKS5_URI" == "$EXPECTED_SOCKS5" ]]; then
    echo "✓ SOCKS5 URI correct (public, with TLS)"
else
    echo "✗ SOCKS5 URI incorrect."
    echo "  Expected: $EXPECTED_SOCKS5"
    echo "  Got:      $SOCKS5_URI"
fi

echo ""
echo "=== Test 3: VSCode Config (Public Mode) ==="
echo ""

export_vscode_config "$TEST_USERNAME" "$TEST_PASSWORD" "$TEST_OUTPUT_DIR"

# Check VSCode config
if grep -q '"http.proxy": "https://'"$TEST_DOMAIN"':8118"' "$TEST_OUTPUT_DIR/vscode_settings.json"; then
    echo "✓ VSCode config uses HTTPS correctly"
else
    echo "✗ VSCode config incorrect:"
    cat "$TEST_OUTPUT_DIR/vscode_settings.json"
fi

echo ""
echo "=== Test 4: Docker Config (Public Mode) ==="
echo ""

export_docker_config "$TEST_USERNAME" "$TEST_PASSWORD" "$TEST_OUTPUT_DIR"

# Check Docker config
if grep -q "https://${TEST_USERNAME}:${TEST_PASSWORD}@${TEST_DOMAIN}:8118" "$TEST_OUTPUT_DIR/docker_daemon.json"; then
    echo "✓ Docker config uses HTTPS correctly"
else
    echo "✗ Docker config incorrect:"
    cat "$TEST_OUTPUT_DIR/docker_daemon.json"
fi

echo ""
echo "=== Test 5: Bash Config (Public Mode) ==="
echo ""

export_bash_config "$TEST_USERNAME" "$TEST_PASSWORD" "$TEST_OUTPUT_DIR"

# Check Bash config
if grep -q "https://${TEST_USERNAME}:${TEST_PASSWORD}@${TEST_DOMAIN}:8118" "$TEST_OUTPUT_DIR/bash_exports.sh"; then
    echo "✓ Bash config uses HTTPS correctly"
else
    echo "✗ Bash config incorrect:"
    cat "$TEST_OUTPUT_DIR/bash_exports.sh"
fi

# Cleanup
rm -rf "$TEST_OUTPUT_DIR" "$VLESS_HOME"

echo ""
echo "=========================================="
echo "Test Complete"
echo "=========================================="
