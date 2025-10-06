#!/bin/bash
#
# stunnel Setup Module for VLESS Reality VPN
# Version: 4.0
# Purpose: Configure and deploy stunnel for TLS termination of proxy services
#
# This module provides functions for:
# - stunnel configuration generation from template
# - Configuration validation
# - Log directory setup
# - Docker integration
#
# Architecture:
#   Client → stunnel (TLS, 1080/8118) → Xray (plaintext, 10800/18118) → Internet
#

set -euo pipefail

# Source paths (relative to install root)
readonly STUNNEL_TEMPLATE="${TEMPLATE_DIR}/stunnel.conf.template"
readonly STUNNEL_CONFIG="${CONFIG_DIR}/stunnel.conf"
readonly STUNNEL_LOG_DIR="${LOG_DIR}/stunnel"

# Docker image
readonly STUNNEL_IMAGE="dweomer/stunnel:latest"

# ============================================================================
# Logging Functions
# ============================================================================

log_stunnel_info() {
    echo -e "${CYAN}[stunnel]${NC} $*"
}

log_stunnel_success() {
    echo -e "${GREEN}[stunnel]${NC} ✓ $*"
}

log_stunnel_warning() {
    echo -e "${YELLOW}[stunnel]${NC} ⚠ $*"
}

log_stunnel_error() {
    echo -e "${RED}[stunnel]${NC} ✗ $*" >&2
}

# ============================================================================
# Configuration Generation
# ============================================================================

#
# create_stunnel_config()
#
# Generate stunnel configuration from template with variable substitution
#
# Arguments:
#   $1 - Domain name for certificate path
#
# Returns:
#   0 - Success
#   1 - Failure (missing template, invalid domain, etc.)
#
# Output:
#   Creates ${CONFIG_DIR}/stunnel.conf
#
create_stunnel_config() {
    local domain="$1"

    log_stunnel_info "Generating stunnel configuration..."

    # Validate domain
    if [[ -z "$domain" ]]; then
        log_stunnel_error "Domain name required for stunnel configuration"
        return 1
    fi

    # Check template exists
    if [[ ! -f "$STUNNEL_TEMPLATE" ]]; then
        log_stunnel_error "stunnel template not found: $STUNNEL_TEMPLATE"
        return 1
    fi

    # Generate config from template (variable substitution)
    if ! envsubst '${DOMAIN}' < "$STUNNEL_TEMPLATE" > "$STUNNEL_CONFIG"; then
        log_stunnel_error "Failed to generate stunnel configuration"
        return 1
    fi

    # Set permissions
    chmod 600 "$STUNNEL_CONFIG"

    log_stunnel_success "stunnel configuration created: $STUNNEL_CONFIG"
    return 0
}

# ============================================================================
# Configuration Validation
# ============================================================================

#
# validate_stunnel_config()
#
# Validate stunnel configuration syntax
#
# Arguments:
#   None (uses global STUNNEL_CONFIG)
#
# Returns:
#   0 - Valid configuration
#   1 - Invalid configuration
#
# Note:
#   stunnel doesn't have native -test flag, so we validate:
#   1. File exists and readable
#   2. Required sections present ([socks5-tls], [http-tls])
#   3. Required parameters present (accept, connect, cert, key)
#
validate_stunnel_config() {
    log_stunnel_info "Validating stunnel configuration..."

    # Check file exists
    if [[ ! -f "$STUNNEL_CONFIG" ]]; then
        log_stunnel_error "stunnel config not found: $STUNNEL_CONFIG"
        return 1
    fi

    # Check readable
    if [[ ! -r "$STUNNEL_CONFIG" ]]; then
        log_stunnel_error "stunnel config not readable: $STUNNEL_CONFIG"
        return 1
    fi

    local errors=0

    # Validate SOCKS5 service section
    if ! grep -q '^\[socks5-tls\]' "$STUNNEL_CONFIG"; then
        log_stunnel_error "Missing [socks5-tls] section"
        ((errors++))
    fi

    # Validate HTTP service section
    if ! grep -q '^\[http-tls\]' "$STUNNEL_CONFIG"; then
        log_stunnel_error "Missing [http-tls] section"
        ((errors++))
    fi

    # Validate SOCKS5 accept port
    if ! grep -A5 '^\[socks5-tls\]' "$STUNNEL_CONFIG" | grep -q '^accept.*:1080'; then
        log_stunnel_error "Missing or invalid SOCKS5 accept port (expected 1080)"
        ((errors++))
    fi

    # Validate HTTP accept port
    if ! grep -A5 '^\[http-tls\]' "$STUNNEL_CONFIG" | grep -q '^accept.*:8118'; then
        log_stunnel_error "Missing or invalid HTTP accept port (expected 8118)"
        ((errors++))
    fi

    # Validate SOCKS5 connect target
    if ! grep -A5 '^\[socks5-tls\]' "$STUNNEL_CONFIG" | grep -q '^connect.*vless_xray:10800'; then
        log_stunnel_error "Missing or invalid SOCKS5 connect target (expected vless_xray:10800)"
        ((errors++))
    fi

    # Validate HTTP connect target
    if ! grep -A5 '^\[http-tls\]' "$STUNNEL_CONFIG" | grep -q '^connect.*vless_xray:18118'; then
        log_stunnel_error "Missing or invalid HTTP connect target (expected vless_xray:18118)"
        ((errors++))
    fi

    # Validate certificate paths (must contain ${DOMAIN} substitution result)
    if ! grep -q '^cert = /certs/live/.*/fullchain.pem' "$STUNNEL_CONFIG"; then
        log_stunnel_error "Missing or invalid certificate path"
        ((errors++))
    fi

    if ! grep -q '^key = /certs/live/.*/privkey.pem' "$STUNNEL_CONFIG"; then
        log_stunnel_error "Missing or invalid key path"
        ((errors++))
    fi

    # Check for errors
    if [[ $errors -gt 0 ]]; then
        log_stunnel_error "stunnel configuration validation failed ($errors errors)"
        return 1
    fi

    log_stunnel_success "stunnel configuration valid"
    return 0
}

# ============================================================================
# Logging Setup
# ============================================================================

#
# setup_stunnel_logging()
#
# Create stunnel log directory
#
# Arguments:
#   None
#
# Returns:
#   0 - Success
#   1 - Failure
#
setup_stunnel_logging() {
    log_stunnel_info "Setting up stunnel logging..."

    # Create log directory
    if ! mkdir -p "$STUNNEL_LOG_DIR"; then
        log_stunnel_error "Failed to create stunnel log directory: $STUNNEL_LOG_DIR"
        return 1
    fi

    # Set permissions (755 - accessible for reading)
    chmod 755 "$STUNNEL_LOG_DIR"

    # Create initial log file (optional, stunnel will create it)
    touch "${STUNNEL_LOG_DIR}/stunnel.log" 2>/dev/null || true
    chmod 644 "${STUNNEL_LOG_DIR}/stunnel.log" 2>/dev/null || true

    log_stunnel_success "stunnel logging configured: $STUNNEL_LOG_DIR"
    return 0
}

# ============================================================================
# Certificate Verification
# ============================================================================

#
# verify_certificates()
#
# Verify Let's Encrypt certificates exist and are valid
#
# Arguments:
#   $1 - Domain name
#
# Returns:
#   0 - Certificates valid
#   1 - Certificates missing or invalid
#
verify_certificates() {
    local domain="$1"
    # Certificates are always in /etc/letsencrypt on the host
    # Docker mounts /etc/letsencrypt:/certs:ro for containers
    local cert_dir="/etc/letsencrypt/live/${domain}"

    log_stunnel_info "Verifying certificates for ${domain}..."

    # Check directory exists
    if [[ ! -d "$cert_dir" ]]; then
        log_stunnel_error "Certificate directory not found: $cert_dir"
        return 1
    fi

    # Check required files
    local required_files=("fullchain.pem" "privkey.pem")
    for file in "${required_files[@]}"; do
        if [[ ! -f "${cert_dir}/${file}" ]]; then
            log_stunnel_error "Certificate file not found: ${cert_dir}/${file}"
            return 1
        fi

        if [[ ! -r "${cert_dir}/${file}" ]]; then
            log_stunnel_error "Certificate file not readable: ${cert_dir}/${file}"
            return 1
        fi
    done

    # Verify certificate validity with openssl
    if ! openssl x509 -in "${cert_dir}/fullchain.pem" -noout -checkend 86400 &>/dev/null; then
        log_stunnel_warning "Certificate expires within 24 hours or is already expired"
        log_stunnel_warning "Certbot should auto-renew, but check: certbot renew"
    fi

    log_stunnel_success "Certificates valid for ${domain}"
    return 0
}

# ============================================================================
# Main Initialization
# ============================================================================

#
# init_stunnel()
#
# Main stunnel initialization function
# Called from orchestrator.sh during installation
#
# Arguments:
#   $1 - Domain name for certificates
#
# Returns:
#   0 - Success
#   1 - Failure
#
# Side effects:
#   - Creates stunnel.conf in config directory
#   - Creates log directory
#   - Verifies certificates
#
init_stunnel() {
    local domain="$1"

    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          stunnel TLS Termination Setup (v4.0)            ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    log_stunnel_info "Initializing stunnel for domain: ${domain}"

    # Step 1: Setup logging
    if ! setup_stunnel_logging; then
        log_stunnel_error "Failed to setup stunnel logging"
        return 1
    fi

    # Step 2: Verify certificates exist
    if ! verify_certificates "$domain"; then
        log_stunnel_error "Certificate verification failed"
        return 1
    fi

    # Step 3: Generate configuration
    if ! create_stunnel_config "$domain"; then
        log_stunnel_error "Failed to create stunnel configuration"
        return 1
    fi

    # Step 4: Validate configuration
    if ! validate_stunnel_config; then
        log_stunnel_error "stunnel configuration validation failed"
        return 1
    fi

    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    log_stunnel_success "stunnel initialization complete"
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo ""

    # Show configuration summary
    cat <<EOF
${CYAN}stunnel Configuration Summary:${NC}
  Domain:         ${domain}
  Config:         ${STUNNEL_CONFIG}
  Logs:           ${STUNNEL_LOG_DIR}
  Certificates:   /etc/letsencrypt/live/${domain}/

${CYAN}TLS Services:${NC}
  SOCKS5:         0.0.0.0:1080 → vless_xray:10800 (TLS termination)
  HTTP:           0.0.0.0:8118 → vless_xray:18118 (TLS termination)

${CYAN}Security:${NC}
  TLS Version:    1.3 only (SSLv2/v3, TLSv1/1.1/1.2 disabled)
  Cipher Suites:  TLS_AES_256_GCM_SHA384, TLS_CHACHA20_POLY1305_SHA256
  Authentication: Password-based (handled by Xray)

${YELLOW}Next steps:${NC}
  - stunnel will be added to docker-compose.yml
  - Xray inbounds will be reconfigured for localhost (10800/18118)
  - Docker network will handle stunnel ↔ Xray communication

EOF

    return 0
}

# ============================================================================
# Utility Functions
# ============================================================================

#
# show_stunnel_status()
#
# Show stunnel service status
#
# Arguments:
#   None
#
# Returns:
#   0 - Always
#
show_stunnel_status() {
    echo ""
    echo -e "${CYAN}stunnel Service Status:${NC}"
    echo "─────────────────────────────────────"

    # Check if stunnel container exists
    if docker ps -a --format '{{.Names}}' | grep -q '^vless_stunnel$'; then
        local status=$(docker ps --filter "name=vless_stunnel" --format "{{.Status}}")
        if [[ -n "$status" ]]; then
            echo -e "Container: ${GREEN}Running${NC}"
            echo "Status:    $status"
        else
            echo -e "Container: ${RED}Stopped${NC}"
        fi

        # Show listening ports
        echo ""
        echo "Listening ports:"
        docker port vless_stunnel 2>/dev/null || echo "  (Container not running)"
    else
        echo -e "Container: ${YELLOW}Not created${NC}"
    fi

    # Show configuration
    if [[ -f "$STUNNEL_CONFIG" ]]; then
        echo ""
        echo "Configuration: $STUNNEL_CONFIG"
        echo "TLS Services:"
        grep -A1 '^\[socks5-tls\]' "$STUNNEL_CONFIG" | grep '^accept' | awk '{print "  SOCKS5: " $3}'
        grep -A1 '^\[http-tls\]' "$STUNNEL_CONFIG" | grep '^accept' | awk '{print "  HTTP:   " $3}'
    else
        echo ""
        echo "Configuration: Not found"
    fi

    echo ""
}

#
# reload_stunnel()
#
# Reload stunnel configuration (restart container)
#
# Arguments:
#   None
#
# Returns:
#   0 - Success
#   1 - Failure
#
reload_stunnel() {
    log_stunnel_info "Reloading stunnel configuration..."

    # Validate configuration before reload
    if ! validate_stunnel_config; then
        log_stunnel_error "Configuration invalid, refusing to reload"
        return 1
    fi

    # Restart stunnel container
    if docker ps --filter "name=vless_stunnel" --format "{{.Names}}" | grep -q '^vless_stunnel$'; then
        if docker restart vless_stunnel &>/dev/null; then
            log_stunnel_success "stunnel reloaded successfully"
            return 0
        else
            log_stunnel_error "Failed to restart stunnel container"
            return 1
        fi
    else
        log_stunnel_error "stunnel container not running"
        return 1
    fi
}

# ============================================================================
# Module Export
# ============================================================================

# Functions exported for use by other modules:
#   - init_stunnel(domain)               # Main initialization
#   - create_stunnel_config(domain)      # Generate config
#   - validate_stunnel_config()          # Validate config
#   - verify_certificates(domain)        # Check certs
#   - show_stunnel_status()              # Status display
#   - reload_stunnel()                   # Restart service

# This module is sourced by:
#   - lib/orchestrator.sh (installation)
#   - cli/vless (status command)
