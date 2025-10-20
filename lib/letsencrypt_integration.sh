#!/bin/bash
# ==============================================================================
# VLESS Reality Deployment System
# Module: Let's Encrypt Integration (Certbot Wrapper)
# ==============================================================================
#
# Purpose:
#   Wrapper for certbot to manage Let's Encrypt certificates
#
# Features:
#   - Certificate validation
#   - Certificate renewal
#   - Expiry checking
#   - DNS validation
#
# Requirements:
#   - certbot installed
#   - DNS records configured
#
# Certificate Location:
#   /etc/letsencrypt/live/<domain>/
#     - fullchain.pem
#     - privkey.pem
#     - cert.pem
#     - chain.pem
#
# Version: 4.3.0
# Author: VLESS Development Team
# Date: 2025-10-20
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================

readonly CERTBOT_WEBROOT="/var/www/certbot"
readonly LETSENCRYPT_DIR="/etc/letsencrypt/live"

# Flag to track if we opened port 80 (used for cleanup)
PORT_80_OPENED_BY_US=false

# ==============================================================================
# Function: validate_certificate
# ==============================================================================
# Description: Check if certificate exists and is valid
# Arguments: $1 - domain
# Returns: 0 if valid, 1 if invalid or not found
# ==============================================================================
validate_certificate() {
    local domain="$1"
    local cert_dir="${LETSENCRYPT_DIR}/${domain}"

    # Check if certificate directory exists
    if [[ ! -d "$cert_dir" ]]; then
        return 1
    fi

    # Check if certificate files exist
    if [[ ! -f "${cert_dir}/fullchain.pem" ]] || [[ ! -f "${cert_dir}/privkey.pem" ]]; then
        return 1
    fi

    # Check certificate expiry with openssl
    local expiry_date
    expiry_date=$(openssl x509 -enddate -noout -in "${cert_dir}/cert.pem" 2>/dev/null | cut -d= -f2)

    if [[ -z "$expiry_date" ]]; then
        return 1
    fi

    # Convert to epoch and compare with current time
    local expiry_epoch
    expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
    local current_epoch
    current_epoch=$(date +%s)

    # Check if expired
    if [[ $expiry_epoch -le $current_epoch ]]; then
        return 1
    fi

    return 0
}

# ==============================================================================
# Function: get_certificate_expiry
# ==============================================================================
# Description: Get certificate expiry date in ISO 8601 format
# Arguments: $1 - domain
# Returns: Prints expiry date to stdout, or empty if error
# ==============================================================================
get_certificate_expiry() {
    local domain="$1"
    local cert_file="${LETSENCRYPT_DIR}/${domain}/cert.pem"

    if [[ ! -f "$cert_file" ]]; then
        return 1
    fi

    local expiry_date
    expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)

    if [[ -z "$expiry_date" ]]; then
        return 1
    fi

    # Convert to ISO 8601
    date -d "$expiry_date" -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || return 1
}

# ==============================================================================
# Function: check_certificate_expiry_days
# ==============================================================================
# Description: Get days until certificate expires
# Arguments: $1 - domain
# Returns: Prints number of days to stdout
# ==============================================================================
check_certificate_expiry_days() {
    local domain="$1"
    local cert_file="${LETSENCRYPT_DIR}/${domain}/cert.pem"

    if [[ ! -f "$cert_file" ]]; then
        echo "-1"
        return 1
    fi

    local expiry_date
    expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)

    if [[ -z "$expiry_date" ]]; then
        echo "-1"
        return 1
    fi

    local expiry_epoch
    expiry_epoch=$(date -d "$expiry_date" +%s)
    local current_epoch
    current_epoch=$(date +%s)

    local days_left=$(( (expiry_epoch - current_epoch) / 86400 ))
    echo "$days_left"
}

# ==============================================================================
# Function: renew_certificate
# ==============================================================================
# Description: Renew Let's Encrypt certificate for domain
# Arguments: $1 - domain
# Returns: 0 on success, 1 on failure
# ==============================================================================
renew_certificate() {
    local domain="$1"

    # Check if certbot is installed
    if ! command -v certbot &>/dev/null; then
        echo "Error: certbot not installed" >&2
        return 1
    fi

    # Force renew certificate
    if certbot renew --cert-name "$domain" --force-renewal --quiet 2>&1; then
        return 0
    else
        echo "Error: Failed to renew certificate for $domain" >&2
        return 1
    fi
}

# ==============================================================================
# Function: ensure_certbot_webroot
# ==============================================================================
# Description: Ensure certbot webroot directory exists with proper permissions
# Returns: 0 on success, 1 on failure
# ==============================================================================
ensure_certbot_webroot() {
    if [[ ! -d "$CERTBOT_WEBROOT" ]]; then
        echo "Creating certbot webroot directory: $CERTBOT_WEBROOT"
        if ! mkdir -p "$CERTBOT_WEBROOT" 2>/dev/null; then
            echo "Error: Failed to create $CERTBOT_WEBROOT" >&2
            return 1
        fi
    fi

    # Ensure proper permissions (755 = rwxr-xr-x)
    # This allows certbot (running as root) to write, and nginx to read
    chmod 755 "$CERTBOT_WEBROOT" 2>/dev/null || true

    # Verify directory exists and is readable (write permission not required here)
    if [[ ! -d "$CERTBOT_WEBROOT" ]] || [[ ! -r "$CERTBOT_WEBROOT" ]]; then
        echo "Error: $CERTBOT_WEBROOT is not accessible" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Function: open_port_80_for_certbot
# ==============================================================================
# Description: Temporarily open UFW port 80 for ACME HTTP-01 challenge
# Returns: 0 on success, 1 on failure
# Side Effect: Sets PORT_80_OPENED_BY_US=true if we open the port
# ==============================================================================
open_port_80_for_certbot() {
    # Check if UFW is installed and active
    if ! command -v ufw &>/dev/null; then
        echo "UFW not installed, skipping port management"
        return 0
    fi

    local ufw_status
    ufw_status=$(ufw status 2>/dev/null | head -1)

    if [[ ! "$ufw_status" =~ "Status: active" ]]; then
        echo "UFW not active, skipping port management"
        return 0
    fi

    # Check if port 80 is already allowed
    if ufw status numbered | grep -qE "80/tcp.*ALLOW"; then
        echo "Port 80 already allowed in UFW"
        PORT_80_OPENED_BY_US=false
        return 0
    fi

    # Open port 80 temporarily
    echo "Temporarily opening port 80 in UFW for Let's Encrypt ACME challenge..."

    # Capture UFW command output for debugging
    local ufw_output
    ufw_output=$(ufw allow 80/tcp --comment "Let's Encrypt ACME challenge (temporary)" 2>&1)
    local ufw_exit_code=$?

    if [[ $ufw_exit_code -ne 0 ]]; then
        echo "Error: Failed to open port 80 in UFW" >&2
        echo "UFW output: $ufw_output" >&2
        echo "Note: Continuing anyway - certbot may still work if port 80 is already accessible" >&2
        # Don't fail - let certbot try anyway
        PORT_80_OPENED_BY_US=false
        return 0
    fi

    PORT_80_OPENED_BY_US=true
    echo "✓ Port 80 opened in UFW (will be closed automatically)"
    return 0
}

# ==============================================================================
# Function: close_port_80_for_certbot
# ==============================================================================
# Description: Close UFW port 80 if we opened it
# Returns: 0 (always succeeds for cleanup safety)
# ==============================================================================
close_port_80_for_certbot() {
    # Only close if we opened the port ourselves
    if [[ "$PORT_80_OPENED_BY_US" != "true" ]]; then
        return 0
    fi

    # Check if UFW is still active
    if ! command -v ufw &>/dev/null; then
        return 0
    fi

    echo "Closing temporary port 80 in UFW..."

    # Find and delete the rule we added (match by comment)
    local rule_number
    rule_number=$(ufw status numbered | grep "Let's Encrypt ACME challenge (temporary)" | grep -oP '^\[\s*\K[0-9]+' | head -1)

    if [[ -n "$rule_number" ]]; then
        # Delete by rule number (requires 'yes' confirmation)
        echo "y" | ufw delete "$rule_number" >/dev/null 2>&1 || true
        echo "✓ Port 80 closed in UFW"
    else
        # Fallback: delete by specification
        ufw delete allow 80/tcp >/dev/null 2>&1 || true
        echo "✓ Port 80 closed in UFW (fallback method)"
    fi

    PORT_80_OPENED_BY_US=false
    return 0
}

# ==============================================================================
# Function: start_certbot_nginx
# ==============================================================================
# Description: Start temporary nginx container for ACME HTTP-01 challenge
# Returns: 0 on success, 1 on failure
# ==============================================================================
start_certbot_nginx() {
    local container_name="certbot_nginx"

    # Check if container already exists and is running
    if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo "Certbot nginx container already running"
        return 0
    fi

    # Remove existing stopped container if present
    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo "Removing existing certbot nginx container..."
        docker rm -f "$container_name" >/dev/null 2>&1 || true
    fi

    # Check if port 80 is available
    if ss -tulnp | grep -q ":80 "; then
        echo "Error: Port 80 is already in use" >&2
        echo "Stop the service using port 80 and try again" >&2
        return 1
    fi

    echo "Starting certbot nginx container on port 80..."
    if ! docker run -d \
        --name "$container_name" \
        --network host \
        -v "$CERTBOT_WEBROOT:/usr/share/nginx/html:ro" \
        nginx:alpine >/dev/null 2>&1; then
        echo "Error: Failed to start certbot nginx container" >&2
        return 1
    fi

    # Wait for nginx to be ready
    sleep 2

    # Verify nginx is responding
    if ! curl -s -o /dev/null -w "%{http_code}" http://localhost:80 | grep -q "^[2-4]"; then
        echo "Warning: Certbot nginx may not be responding correctly"
    fi

    echo "✓ Certbot nginx started successfully"
    return 0
}

# ==============================================================================
# Function: stop_certbot_nginx
# ==============================================================================
# Description: Stop and remove certbot nginx container
# Returns: 0 on success (always succeeds)
# ==============================================================================
stop_certbot_nginx() {
    local container_name="certbot_nginx"

    if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo "Stopping certbot nginx container..."
        docker stop "$container_name" >/dev/null 2>&1 || true
        docker rm "$container_name" >/dev/null 2>&1 || true
        echo "✓ Certbot nginx stopped"
    fi

    return 0
}

# ==============================================================================
# Function: acquire_certificate
# ==============================================================================
# Description: Acquire new Let's Encrypt certificate
# Arguments:
#   $1 - domain
#   $2 - email (optional, uses --register-unsafely-without-email if empty)
# Returns: 0 on success, 1 on failure
# ==============================================================================
acquire_certificate() {
    local domain="$1"
    local email="${2:-}"

    # Check if certbot is installed
    if ! command -v certbot &>/dev/null; then
        echo "Error: certbot not installed" >&2
        return 1
    fi

    # Cleanup function (called on exit via trap)
    cleanup() {
        echo ""
        stop_certbot_nginx
        close_port_80_for_certbot
    }

    # Set trap to ensure cleanup on exit (success or failure)
    trap cleanup EXIT

    # Step 1: Ensure webroot directory exists
    if ! ensure_certbot_webroot; then
        return 1
    fi

    # Step 2: Open port 80 in UFW (if needed)
    echo ""
    if ! open_port_80_for_certbot; then
        echo "Warning: Failed to open port 80 in UFW, continuing anyway..." >&2
    fi

    # Step 3: Start certbot nginx container
    echo ""
    echo "Starting temporary nginx for ACME challenge..."
    if ! start_certbot_nginx; then
        return 1
    fi

    # Prepare certbot command
    local certbot_cmd="certbot certonly --webroot -w $CERTBOT_WEBROOT -d $domain --non-interactive --agree-tos"

    if [[ -n "$email" ]]; then
        certbot_cmd+=" --email $email"
    else
        certbot_cmd+=" --register-unsafely-without-email"
    fi

    # Step 4: Acquire certificate
    echo ""
    echo "Running certbot to acquire certificate..."
    local certbot_result=0
    if ! eval "$certbot_cmd" 2>&1; then
        echo "Error: Failed to acquire certificate for $domain" >&2
        certbot_result=1
    fi

    # Cleanup will be called automatically via trap
    # Return certbot result
    return $certbot_result
}

# ==============================================================================
# Function: validate_dns_for_domain
# ==============================================================================
# Description: Check if DNS points to current server
# Arguments: $1 - domain
# Returns: 0 if DNS resolves correctly, 1 if not
# ==============================================================================
validate_dns_for_domain() {
    local domain="$1"

    # Get server's public IP
    local server_ip
    server_ip=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "")

    if [[ -z "$server_ip" ]]; then
        echo "Error: Failed to determine server IP" >&2
        return 1
    fi

    # Resolve domain
    local domain_ip
    domain_ip=$(dig +short "$domain" @8.8.8.8 2>/dev/null | head -1)

    if [[ -z "$domain_ip" ]]; then
        echo "Error: Failed to resolve domain $domain" >&2
        return 1
    fi

    # Compare IPs
    if [[ "$server_ip" != "$domain_ip" ]]; then
        echo "Error: DNS mismatch for $domain" >&2
        echo "  Server IP: $server_ip" >&2
        echo "  Domain IP: $domain_ip" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Export Functions
# ==============================================================================

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Script is being sourced
    export -f validate_certificate
    export -f get_certificate_expiry
    export -f check_certificate_expiry_days
    export -f renew_certificate
    export -f ensure_certbot_webroot
    export -f open_port_80_for_certbot
    export -f close_port_80_for_certbot
    export -f start_certbot_nginx
    export -f stop_certbot_nginx
    export -f acquire_certificate
    export -f validate_dns_for_domain
fi
