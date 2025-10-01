#!/bin/bash

# X25519 Keys Diagnostic Script
# Validates key correspondence and diagnoses connection issues

set -euo pipefail

# Load dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/config.sh"

# Configuration
VLESS_HOME="${VLESS_HOME:-/opt/vless}"
CONFIG_FILE="$VLESS_HOME/config/config.json"
ENV_FILE="$VLESS_HOME/.env"
LOG_FILE="$VLESS_HOME/logs/error.log"

# Print diagnostic header
print_diagnostic_header() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║          X25519 Keys Diagnostic Report                             ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo ""
}

# Extract private key from config.json
extract_private_key_from_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "ERROR: config.json not found"
        return 1
    fi

    local private_key=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CONFIG_FILE" 2>/dev/null)

    if [ -z "$private_key" ] || [ "$private_key" = "null" ]; then
        echo "ERROR: privateKey not found in config.json"
        return 1
    fi

    echo "$private_key"
}

# Extract keys from .env file
extract_keys_from_env() {
    if [ ! -f "$ENV_FILE" ]; then
        echo "ERROR: .env file not found"
        return 1
    fi

    local key_name="$1"
    local key_value=$(grep "^${key_name}=" "$ENV_FILE" | cut -d'=' -f2)

    if [ -z "$key_value" ]; then
        echo "ERROR: ${key_name} not found in .env"
        return 1
    fi

    echo "$key_value"
}

# Compute public key from private key
compute_public_key() {
    local private_key="$1"

    local output=$(docker run --rm teddysun/xray:24.11.30 xray x25519 -i "$private_key" 2>&1)

    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to compute public key"
        return 1
    fi

    local public_key=$(echo "$output" | grep -iE "(public.key:|password:)" | awk '{print $NF}')

    if [ -z "$public_key" ]; then
        echo "ERROR: Could not extract public key from output"
        return 1
    fi

    echo "$public_key"
}

# Validate key format (base64, correct length)
validate_key_format() {
    local key="$1"
    local key_name="$2"

    # Check length (X25519 keys are 43 characters in base64)
    if [ ${#key} -ne 43 ]; then
        echo "  ✗ $key_name length: ${#key} (expected: 43)"
        return 1
    fi

    # Check base64 format (alphanumeric + - _)
    if ! echo "$key" | grep -qE '^[A-Za-z0-9_-]{43}$'; then
        echo "  ✗ $key_name format: Invalid characters (expected base64)"
        return 1
    fi

    echo "  ✓ $key_name format is valid (base64, 43 chars)"
    return 0
}

# Analyze logs for connection errors
analyze_logs() {
    if [ ! -f "$LOG_FILE" ]; then
        echo "  ⚠ Log file not found: $LOG_FILE"
        return 0
    fi

    # Check log file size (skip if too large)
    local log_size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo "0")
    if [ "$log_size" -gt 10485760 ]; then  # 10MB
        echo "  ⚠ Log file too large ($(($log_size / 1048576))MB), analyzing last 10000 lines only"
        local log_content=$(tail -10000 "$LOG_FILE")
    else
        local log_content=$(cat "$LOG_FILE")
    fi

    # Count invalid connection errors (last 24 hours if possible)
    local invalid_count=$(echo "$log_content" | grep -i "invalid connection" | wc -l | tr -d ' ')

    # Count successful connections (accepted tcp)
    local success_count=$(echo "$log_content" | grep -i "accepted.*tcp" | wc -l | tr -d ' ')

    # Recent errors (last 10)
    local recent_errors=$(echo "$log_content" | grep -i "invalid connection" | tail -10)

    echo "  Invalid connections (in logs): $invalid_count"
    echo "  Successful connections (in logs): $success_count"

    if [ "$invalid_count" -gt 0 ]; then
        echo ""
        echo "  Recent 'invalid connection' errors:"
        echo "$recent_errors" | while read -r line; do
            echo "    - $(echo "$line" | cut -c1-100)"
        done
    fi
}

# Main diagnostic workflow
main() {
    print_diagnostic_header

    # Section 1: Keys from config.json
    echo "[1] Keys from config.json:"
    echo "───────────────────────────────────────────────────────────────────"

    CONFIG_PRIVATE_KEY=$(extract_private_key_from_config)
    if [[ "$CONFIG_PRIVATE_KEY" == ERROR* ]]; then
        print_error "$CONFIG_PRIVATE_KEY"
        echo ""
        exit 1
    fi

    echo "  privateKey: $CONFIG_PRIVATE_KEY"
    echo ""

    # Section 2: Keys from .env
    echo "[2] Keys from .env file:"
    echo "───────────────────────────────────────────────────────────────────"

    ENV_PRIVATE_KEY=$(extract_keys_from_env "PRIVATE_KEY")
    ENV_PUBLIC_KEY=$(extract_keys_from_env "PUBLIC_KEY")

    if [[ "$ENV_PRIVATE_KEY" == ERROR* ]] || [[ "$ENV_PUBLIC_KEY" == ERROR* ]]; then
        print_error "Failed to extract keys from .env"
        echo ""
        exit 1
    fi

    echo "  PRIVATE_KEY: $ENV_PRIVATE_KEY"
    echo "  PUBLIC_KEY:  $ENV_PUBLIC_KEY"
    echo ""

    # Section 3: Computed public key
    echo "[3] Computed publicKey from privateKey:"
    echo "───────────────────────────────────────────────────────────────────"

    COMPUTED_PUBLIC_KEY=$(compute_public_key "$CONFIG_PRIVATE_KEY")
    if [[ "$COMPUTED_PUBLIC_KEY" == ERROR* ]]; then
        print_error "$COMPUTED_PUBLIC_KEY"
        echo ""
        exit 1
    fi

    echo "  Computed:    $COMPUTED_PUBLIC_KEY"
    echo ""

    # Section 4: Validation results
    echo "[4] Validation Results:"
    echo "───────────────────────────────────────────────────────────────────"

    local validation_passed=true

    # Check if privateKey in config matches PRIVATE_KEY in .env
    if [ "$CONFIG_PRIVATE_KEY" = "$ENV_PRIVATE_KEY" ]; then
        echo "  ✓ privateKey in config.json matches PRIVATE_KEY in .env"
    else
        echo "  ✗ privateKey MISMATCH between config.json and .env"
        validation_passed=false
    fi

    # Check if computed public key matches stored PUBLIC_KEY
    if [ "$COMPUTED_PUBLIC_KEY" = "$ENV_PUBLIC_KEY" ]; then
        echo "  ✓ PUBLIC_KEY matches computed publicKey (keys are valid)"
    else
        echo "  ✗ PUBLIC_KEY MISMATCH - keys are mathematically incorrect!"
        echo "    Stored:   $ENV_PUBLIC_KEY"
        echo "    Computed: $COMPUTED_PUBLIC_KEY"
        validation_passed=false
    fi

    # Validate key formats
    validate_key_format "$CONFIG_PRIVATE_KEY" "privateKey"
    validate_key_format "$ENV_PUBLIC_KEY" "PUBLIC_KEY"

    echo ""

    # Section 5: Log analysis
    echo "[5] Log Analysis (REALITY connection errors):"
    echo "───────────────────────────────────────────────────────────────────"

    analyze_logs

    echo ""

    # Section 6: Conclusion
    echo "[6] Conclusion:"
    echo "───────────────────────────────────────────────────────────────────"

    if [ "$validation_passed" = true ]; then
        print_success "All keys are correctly configured and consistent"
        print_success "No key-related issues detected"
        echo ""
        echo "  If clients still cannot connect, check:"
        echo "  • Server firewall allows port $SERVER_PORT"
        echo "  • Client configuration matches server settings"
        echo "  • REALITY_DEST is accessible from server"
        echo "  • Docker container is running: docker ps | grep xray-server"
    else
        print_error "KEY MISMATCH DETECTED - This will cause connection failures!"
        echo ""
        echo "  Recommended actions:"
        echo "  1. Run key rotation to generate valid keys:"
        echo "     → sudo $SCRIPT_DIR/security/rotate-keys.sh"
        echo ""
        echo "  2. Or manually fix the mismatch:"
        echo "     → Ensure privateKey in config.json matches PRIVATE_KEY in .env"
        echo "     → Compute correct PUBLIC_KEY: docker run --rm teddysun/xray:24.11.30 xray x25519 -i <PRIVATE_KEY>"
        echo "     → Update PUBLIC_KEY in .env"
        echo "     → Restart: cd $VLESS_HOME && docker-compose restart"
        echo ""
        echo "  3. Update ALL client configurations with new PUBLIC_KEY"
    fi

    echo ""
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo ""

    if [ "$validation_passed" = false ]; then
        exit 1
    fi
}

# Run main function
main "$@"
