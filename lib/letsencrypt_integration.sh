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

    # Prepare certbot command
    local certbot_cmd="certbot certonly --webroot -w $CERTBOT_WEBROOT -d $domain --non-interactive --agree-tos"

    if [[ -n "$email" ]]; then
        certbot_cmd+=" --email $email"
    else
        certbot_cmd+=" --register-unsafely-without-email"
    fi

    # Acquire certificate
    if eval "$certbot_cmd" 2>&1; then
        return 0
    else
        echo "Error: Failed to acquire certificate for $domain" >&2
        return 1
    fi
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
    export -f acquire_certificate
    export -f validate_dns_for_domain
fi
