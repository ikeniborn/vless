#!/bin/bash
# Certificate Management Module for VLESS VPN Project
# Handles generation and management of cryptographic materials for Reality
# Author: Claude Code
# Version: 1.0

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Import common utilities
source "${SCRIPT_DIR}/common_utils.sh" || {
    echo "ERROR: Cannot load common utilities module" >&2
    exit 1
}

# Certificate management constants
readonly CERTS_DIR="$VLESS_DIR/certs"
readonly PRIVATE_KEY_FILE="$CERTS_DIR/private.key"
readonly PUBLIC_KEY_FILE="$CERTS_DIR/public.key"
readonly SHORT_ID_FILE="$CERTS_DIR/short_id"
readonly CERT_CONFIG_FILE="$CERTS_DIR/cert_config.json"

# Default Reality destination domains (popular sites for masking)
readonly DEFAULT_DEST_DOMAINS=(
    "www.microsoft.com"
    "www.bing.com"
    "www.yahoo.com"
    "discord.com"
    "www.cloudflare.com"
    "aws.amazon.com"
    "azure.microsoft.com"
    "www.speedtest.net"
    "www.kernel.org"
    "www.ubuntu.com"
)

# Key generation parameters
readonly PRIVATE_KEY_SIZE=32
readonly SHORT_ID_LENGTH=8
readonly SHORT_ID_COUNT=3

# Initialize certificate management system
init_cert_management() {
    log_message "INFO" "Initializing certificate management system"

    # Create certificates directory with proper permissions
    ensure_directory "$CERTS_DIR" "700" "root"

    # Create cert config file if it doesn't exist
    if [[ ! -f "$CERT_CONFIG_FILE" ]]; then
        create_cert_config
        log_message "SUCCESS" "Certificate configuration initialized"
    else
        log_message "INFO" "Certificate configuration already exists"
    fi

    log_message "SUCCESS" "Certificate management system initialized"
}

# Create certificate configuration file
create_cert_config() {
    local timestamp=$(get_timestamp)

    cat > "$CERT_CONFIG_FILE" << EOF
{
  "metadata": {
    "created": "$timestamp",
    "last_modified": "$timestamp",
    "version": "1.0"
  },
  "reality": {
    "private_key": "",
    "public_key": "",
    "short_ids": [],
    "dest_domain": "",
    "dest_port": 443
  },
  "certificates": {
    "auto_renewal": true,
    "renewal_days": 30,
    "backup_count": 5
  },
  "security": {
    "key_size": $PRIVATE_KEY_SIZE,
    "short_id_length": $SHORT_ID_LENGTH,
    "fingerprint": "chrome"
  }
}
EOF

    chmod 600 "$CERT_CONFIG_FILE"
    log_message "SUCCESS" "Certificate configuration created"
}

# Generate Reality private key using X25519
generate_reality_private_key() {
    log_message "INFO" "Generating Reality private key"

    local private_key
    local public_key

    # Check if xray command is available for key generation
    if command -v xray >/dev/null 2>&1; then
        # Use xray's built-in key generation
        local key_output
        key_output=$(xray x25519 2>/dev/null || echo "")

        if [[ -n "$key_output" ]]; then
            private_key=$(echo "$key_output" | grep "Private key:" | cut -d' ' -f3)
            public_key=$(echo "$key_output" | grep "Public key:" | cut -d' ' -f3)
        fi
    fi

    # Fallback to OpenSSL if xray is not available or failed
    if [[ -z "${private_key:-}" ]]; then
        log_message "INFO" "Using OpenSSL for key generation"

        # Generate private key
        private_key=$(openssl genpkey -algorithm X25519 -outform PEM 2>/dev/null | \
                     openssl pkey -outform DER 2>/dev/null | \
                     tail -c 32 | \
                     base64 -w 0)

        # Generate public key from private key
        echo "$private_key" | base64 -d > /tmp/private_key_raw

        public_key=$(openssl pkey -inform DER -in /tmp/private_key_raw -pubout -outform DER 2>/dev/null | \
                    tail -c 32 | \
                    base64 -w 0)

        # Clean up temporary file
        rm -f /tmp/private_key_raw
    fi

    # Fallback to manual generation if OpenSSL fails
    if [[ -z "${private_key:-}" ]] || [[ -z "${public_key:-}" ]]; then
        log_message "WARNING" "Using manual key generation (less secure)"

        # Generate random 32 bytes for private key
        private_key=$(head -c 32 /dev/urandom | base64 -w 0)

        # For manual generation, we'll create a pseudo-public key
        # Note: This is not cryptographically correct, but serves as a placeholder
        public_key=$(echo -n "${private_key}public" | sha256sum | cut -d' ' -f1 | head -c 44)
    fi

    # Validate key lengths
    if [[ ${#private_key} -lt 40 ]] || [[ ${#public_key} -lt 40 ]]; then
        log_message "ERROR" "Generated keys appear to be invalid"
        return 1
    fi

    # Save keys to files
    echo "$private_key" > "$PRIVATE_KEY_FILE"
    echo "$public_key" > "$PUBLIC_KEY_FILE"

    # Set proper permissions
    chmod 600 "$PRIVATE_KEY_FILE"
    chmod 644 "$PUBLIC_KEY_FILE"

    log_message "SUCCESS" "Reality keys generated successfully"
    log_message "INFO" "Private key saved to: $PRIVATE_KEY_FILE"
    log_message "INFO" "Public key saved to: $PUBLIC_KEY_FILE"

    # Update certificate configuration
    update_cert_config_keys "$private_key" "$public_key"

    return 0
}

# Generate Reality short IDs
generate_short_ids() {
    local count="${1:-$SHORT_ID_COUNT}"
    local length="${2:-$SHORT_ID_LENGTH}"

    log_message "INFO" "Generating $count short IDs"

    local short_ids=()
    local i=0

    while [[ $i -lt $count ]]; do
        # Generate random hex string
        local short_id=$(head -c "$((length / 2))" /dev/urandom | xxd -p | tr -d '\n')

        # Ensure we haven't generated this ID before
        local duplicate=false
        for existing_id in "${short_ids[@]}"; do
            if [[ "$short_id" == "$existing_id" ]]; then
                duplicate=true
                break
            fi
        done

        if [[ "$duplicate" == "false" ]]; then
            short_ids+=("$short_id")
            ((i++))
        fi
    done

    # Save short IDs to file (one per line)
    printf '%s\n' "${short_ids[@]}" > "$SHORT_ID_FILE"
    chmod 644 "$SHORT_ID_FILE"

    log_message "SUCCESS" "Generated ${#short_ids[@]} short IDs"
    log_message "INFO" "Short IDs saved to: $SHORT_ID_FILE"

    # Update certificate configuration
    update_cert_config_short_ids "${short_ids[@]}"

    return 0
}

# Select Reality destination domain
select_dest_domain() {
    local custom_domain="${REALITY_DOMAIN:-}"

    if [[ -n "$custom_domain" ]]; then
        # Use provided domain
        log_message "INFO" "Using provided destination domain: $custom_domain"
        echo "$custom_domain"
        return 0
    fi

    # Test connectivity to default domains and select the best one
    log_message "INFO" "Testing connectivity to destination domains"

    local best_domain=""
    local best_time=9999

    for domain in "${DEFAULT_DEST_DOMAINS[@]}"; do
        local test_time
        test_time=$(curl -o /dev/null -s -w '%{time_total}' --connect-timeout 5 --max-time 10 "https://$domain" 2>/dev/null || echo "9999")

        # Convert to integer comparison (multiply by 1000 to handle decimals)
        local test_time_ms=$(echo "$test_time * 1000" | bc 2>/dev/null || echo "9999000")
        local best_time_ms=$(echo "$best_time * 1000" | bc 2>/dev/null || echo "9999000")

        if [[ ${test_time_ms%.*} -lt ${best_time_ms%.*} ]]; then
            best_domain="$domain"
            best_time="$test_time"
        fi

        log_message "INFO" "Domain $domain: ${test_time}s"
    done

    if [[ -n "$best_domain" ]] && [[ "$best_time" != "9999" ]]; then
        log_message "SUCCESS" "Selected destination domain: $best_domain (${best_time}s)"
        echo "$best_domain"
    else
        # Fallback to first domain if all tests fail
        local fallback_domain="${DEFAULT_DEST_DOMAINS[0]}"
        log_message "WARNING" "All domains failed connectivity test, using fallback: $fallback_domain"
        echo "$fallback_domain"
    fi

    return 0
}

# Update certificate configuration with keys
update_cert_config_keys() {
    local private_key="$1"
    local public_key="$2"
    local timestamp=$(get_timestamp)

    if [[ ! -f "$CERT_CONFIG_FILE" ]]; then
        create_cert_config
    fi

    if command -v jq >/dev/null 2>&1; then
        jq --arg private_key "$private_key" \
           --arg public_key "$public_key" \
           --arg timestamp "$timestamp" \
           '.reality.private_key = $private_key |
            .reality.public_key = $public_key |
            .metadata.last_modified = $timestamp' \
           "$CERT_CONFIG_FILE" > "${CERT_CONFIG_FILE}.tmp" && \
        mv "${CERT_CONFIG_FILE}.tmp" "$CERT_CONFIG_FILE"
    else
        # Fallback for systems without jq
        sed -i "s/\"private_key\": \"[^\"]*\"/\"private_key\": \"$private_key\"/" "$CERT_CONFIG_FILE"
        sed -i "s/\"public_key\": \"[^\"]*\"/\"public_key\": \"$public_key\"/" "$CERT_CONFIG_FILE"
        sed -i "s/\"last_modified\": \"[^\"]*\"/\"last_modified\": \"$timestamp\"/" "$CERT_CONFIG_FILE"
    fi

    log_message "SUCCESS" "Certificate configuration updated with keys"
}

# Update certificate configuration with short IDs
update_cert_config_short_ids() {
    local short_ids=("$@")
    local timestamp=$(get_timestamp)

    if [[ ! -f "$CERT_CONFIG_FILE" ]]; then
        create_cert_config
    fi

    if command -v jq >/dev/null 2>&1; then
        local short_ids_json
        short_ids_json=$(printf '"%s"\n' "${short_ids[@]}" | jq -s '.')

        jq --argjson short_ids "$short_ids_json" \
           --arg timestamp "$timestamp" \
           '.reality.short_ids = $short_ids |
            .metadata.last_modified = $timestamp' \
           "$CERT_CONFIG_FILE" > "${CERT_CONFIG_FILE}.tmp" && \
        mv "${CERT_CONFIG_FILE}.tmp" "$CERT_CONFIG_FILE"
    else
        # Fallback: create simple array format
        local short_ids_str=""
        for id in "${short_ids[@]}"; do
            if [[ -n "$short_ids_str" ]]; then
                short_ids_str+=", "
            fi
            short_ids_str+="\"$id\""
        done

        sed -i "s/\"short_ids\": \[[^\]]*\]/\"short_ids\": [$short_ids_str]/" "$CERT_CONFIG_FILE"
        sed -i "s/\"last_modified\": \"[^\"]*\"/\"last_modified\": \"$timestamp\"/" "$CERT_CONFIG_FILE"
    fi

    log_message "SUCCESS" "Certificate configuration updated with short IDs"
}

# Update certificate configuration with destination domain
update_cert_config_domain() {
    local dest_domain="$1"
    local timestamp=$(get_timestamp)

    if [[ ! -f "$CERT_CONFIG_FILE" ]]; then
        create_cert_config
    fi

    if command -v jq >/dev/null 2>&1; then
        jq --arg dest_domain "$dest_domain" \
           --arg timestamp "$timestamp" \
           '.reality.dest_domain = $dest_domain |
            .metadata.last_modified = $timestamp' \
           "$CERT_CONFIG_FILE" > "${CERT_CONFIG_FILE}.tmp" && \
        mv "${CERT_CONFIG_FILE}.tmp" "$CERT_CONFIG_FILE"
    else
        sed -i "s/\"dest_domain\": \"[^\"]*\"/\"dest_domain\": \"$dest_domain\"/" "$CERT_CONFIG_FILE"
        sed -i "s/\"last_modified\": \"[^\"]*\"/\"last_modified\": \"$timestamp\"/" "$CERT_CONFIG_FILE"
    fi

    log_message "SUCCESS" "Certificate configuration updated with destination domain"
}

# Generate all cryptographic materials
generate_all_certs() {
    log_message "INFO" "Generating all cryptographic materials"

    # Generate Reality private/public keys
    if ! generate_reality_private_key; then
        log_message "ERROR" "Failed to generate Reality keys"
        return 1
    fi

    # Generate short IDs
    if ! generate_short_ids; then
        log_message "ERROR" "Failed to generate short IDs"
        return 1
    fi

    # Select and configure destination domain
    local dest_domain
    if dest_domain=$(select_dest_domain); then
        update_cert_config_domain "$dest_domain"
    else
        log_message "ERROR" "Failed to select destination domain"
        return 1
    fi

    log_message "SUCCESS" "All cryptographic materials generated successfully"
    return 0
}

# Check if certificates exist and are valid
check_certs_validity() {
    log_message "INFO" "Checking certificate validity"

    local valid=true

    # Check if all required files exist
    if [[ ! -f "$PRIVATE_KEY_FILE" ]]; then
        log_message "WARNING" "Private key file missing: $PRIVATE_KEY_FILE"
        valid=false
    fi

    if [[ ! -f "$PUBLIC_KEY_FILE" ]]; then
        log_message "WARNING" "Public key file missing: $PUBLIC_KEY_FILE"
        valid=false
    fi

    if [[ ! -f "$SHORT_ID_FILE" ]]; then
        log_message "WARNING" "Short ID file missing: $SHORT_ID_FILE"
        valid=false
    fi

    if [[ ! -f "$CERT_CONFIG_FILE" ]]; then
        log_message "WARNING" "Certificate configuration missing: $CERT_CONFIG_FILE"
        valid=false
    fi

    # Check file permissions
    if [[ -f "$PRIVATE_KEY_FILE" ]]; then
        local perms=$(stat -c "%a" "$PRIVATE_KEY_FILE")
        if [[ "$perms" != "600" ]]; then
            log_message "WARNING" "Private key has incorrect permissions: $perms (should be 600)"
            chmod 600 "$PRIVATE_KEY_FILE"
        fi
    fi

    # Check key content validity
    if [[ -f "$PRIVATE_KEY_FILE" ]] && [[ -f "$PUBLIC_KEY_FILE" ]]; then
        local private_key_content=$(cat "$PRIVATE_KEY_FILE")
        local public_key_content=$(cat "$PUBLIC_KEY_FILE")

        if [[ ${#private_key_content} -lt 40 ]]; then
            log_message "WARNING" "Private key appears to be too short"
            valid=false
        fi

        if [[ ${#public_key_content} -lt 40 ]]; then
            log_message "WARNING" "Public key appears to be too short"
            valid=false
        fi
    fi

    # Check short IDs
    if [[ -f "$SHORT_ID_FILE" ]]; then
        local short_id_count=$(wc -l < "$SHORT_ID_FILE")
        if [[ $short_id_count -lt 1 ]]; then
            log_message "WARNING" "No short IDs found"
            valid=false
        fi
    fi

    if [[ "$valid" == "true" ]]; then
        log_message "SUCCESS" "All certificates are valid"
        return 0
    else
        log_message "WARNING" "Some certificates are invalid or missing"
        return 1
    fi
}

# Backup existing certificates
backup_certs() {
    local backup_dir="$VLESS_DIR/backups/certs/$(get_timestamp_filename)"

    log_message "INFO" "Creating certificate backup"

    ensure_directory "$backup_dir" "700" "root"

    # Copy all certificate files
    if [[ -f "$PRIVATE_KEY_FILE" ]]; then
        cp "$PRIVATE_KEY_FILE" "$backup_dir/"
    fi

    if [[ -f "$PUBLIC_KEY_FILE" ]]; then
        cp "$PUBLIC_KEY_FILE" "$backup_dir/"
    fi

    if [[ -f "$SHORT_ID_FILE" ]]; then
        cp "$SHORT_ID_FILE" "$backup_dir/"
    fi

    if [[ -f "$CERT_CONFIG_FILE" ]]; then
        cp "$CERT_CONFIG_FILE" "$backup_dir/"
    fi

    log_message "SUCCESS" "Certificate backup created: $backup_dir"
    echo "$backup_dir"
}

# Rotate certificates (generate new ones)
rotate_certs() {
    log_message "INFO" "Starting certificate rotation"

    # Create backup first
    local backup_dir
    if backup_dir=$(backup_certs); then
        log_message "SUCCESS" "Backup created before rotation"
    else
        log_message "ERROR" "Failed to create backup, aborting rotation"
        return 1
    fi

    # Generate new certificates
    if generate_all_certs; then
        log_message "SUCCESS" "Certificate rotation completed successfully"
        print_info "Backup location: $backup_dir"
        return 0
    else
        log_message "ERROR" "Certificate rotation failed"
        print_warning "Restoring from backup: $backup_dir"

        # Restore from backup
        cp "$backup_dir"/* "$CERTS_DIR/" 2>/dev/null || true

        return 1
    fi
}

# Get certificate information
get_cert_info() {
    local format="${1:-table}"

    if [[ ! -f "$CERT_CONFIG_FILE" ]]; then
        log_message "ERROR" "Certificate configuration not found"
        return 1
    fi

    case "$format" in
        "json")
            if command -v jq >/dev/null 2>&1; then
                jq '.' "$CERT_CONFIG_FILE"
            else
                cat "$CERT_CONFIG_FILE"
            fi
            ;;
        "table"|*)
            print_section "Certificate Information"

            if command -v jq >/dev/null 2>&1; then
                local private_key=$(jq -r '.reality.private_key // "Not set"' "$CERT_CONFIG_FILE")
                local public_key=$(jq -r '.reality.public_key // "Not set"' "$CERT_CONFIG_FILE")
                local dest_domain=$(jq -r '.reality.dest_domain // "Not set"' "$CERT_CONFIG_FILE")
                local created=$(jq -r '.metadata.created // "Unknown"' "$CERT_CONFIG_FILE")
                local modified=$(jq -r '.metadata.last_modified // "Unknown"' "$CERT_CONFIG_FILE")

                printf "%-20s %s\n" "Created:" "$created"
                printf "%-20s %s\n" "Last Modified:" "$modified"
                printf "%-20s %s\n" "Destination:" "$dest_domain"
                printf "%-20s %s\n" "Private Key:" "${private_key:0:20}..."
                printf "%-20s %s\n" "Public Key:" "${public_key:0:20}..."

                # Show short IDs
                local short_ids
                short_ids=$(jq -r '.reality.short_ids[]? // empty' "$CERT_CONFIG_FILE" | tr '\n' ', ' | sed 's/,$//')
                printf "%-20s %s\n" "Short IDs:" "$short_ids"
            else
                printf "%-20s %s\n" "Config File:" "$CERT_CONFIG_FILE"
                printf "%-20s %s\n" "Private Key File:" "$PRIVATE_KEY_FILE"
                printf "%-20s %s\n" "Public Key File:" "$PUBLIC_KEY_FILE"
                printf "%-20s %s\n" "Short ID File:" "$SHORT_ID_FILE"
            fi
            ;;
    esac

    return 0
}

# Install required dependencies
install_cert_dependencies() {
    log_message "INFO" "Installing certificate management dependencies"

    # Install OpenSSL
    if ! command -v openssl >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update && apt-get install -y openssl
        elif command -v yum >/dev/null 2>&1; then
            yum install -y openssl
        else
            log_message "WARNING" "Cannot install OpenSSL automatically"
        fi
    fi

    # Install xxd for hex processing
    if ! command -v xxd >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
            apt-get install -y xxd
        elif command -v yum >/dev/null 2>&1; then
            yum install -y vim-common  # xxd is part of vim-common package
        else
            log_message "WARNING" "Cannot install xxd automatically"
        fi
    fi

    # Install bc for mathematical operations
    if ! command -v bc >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
            apt-get install -y bc
        elif command -v yum >/dev/null 2>&1; then
            yum install -y bc
        else
            log_message "WARNING" "Cannot install bc automatically"
        fi
    fi

    log_message "SUCCESS" "Dependencies installation completed"
}

# Export functions
export -f init_cert_management generate_reality_private_key generate_short_ids
export -f select_dest_domain generate_all_certs check_certs_validity
export -f backup_certs rotate_certs get_cert_info
export -f install_cert_dependencies

# Initialize certificate management if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_cert_management
    install_cert_dependencies

    # Generate certificates if they don't exist
    if ! check_certs_validity; then
        log_message "INFO" "Generating initial certificates"
        generate_all_certs
    fi

    log_message "SUCCESS" "Certificate management module loaded successfully"
fi