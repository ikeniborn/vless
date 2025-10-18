#!/bin/bash
#==============================================================================
# Certificate Manager Module for HAProxy (v4.3)
# Part of VLESS + Reality VPN v4.3
#
# This module handles:
# - HAProxy combined.pem generation (fullchain + privkey)
# - Certificate validation for HAProxy
# - Integration with certbot lifecycle
#
# Version: 4.3
# Author: VLESS Team
# Date: 2025-10-17
#==============================================================================

set -euo pipefail

# Color codes for output (conditional to avoid conflicts when sourced by CLI)
[[ -z "${RED:-}" ]] && readonly RED='\033[0;31m'
[[ -z "${GREEN:-}" ]] && readonly GREEN='\033[0;32m'
[[ -z "${YELLOW:-}" ]] && readonly YELLOW='\033[1;33m'
[[ -z "${CYAN:-}" ]] && readonly CYAN='\033[0;36m'
[[ -z "${NC:-}" ]] && readonly NC='\033[0m' # No Color

#==============================================================================
# FUNCTION: validate_dns_for_domain
# PURPOSE: Validate that domain DNS A record points to server's public IP
# USAGE: validate_dns_for_domain <domain>
# RETURNS: 0 on success, 1 on failure
#
# DETAILS:
#   - Automatically detects server's public IP
#   - Uses dig to query DNS A record
#   - Compares DNS IP with server IP
#   - Required before certificate acquisition
#
# DEPENDENCIES: dig (dnsutils package)
#==============================================================================
validate_dns_for_domain() {
    local domain="$1"

    # Validate domain parameter
    if [[ -z "$domain" ]]; then
        echo -e "${RED}ERROR: Domain parameter required${NC}" >&2
        return 1
    fi

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}DNS Validation for Certificate Acquisition${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "Domain: $domain"
    echo ""

    # Step 1: Check if dig is available
    if ! command -v dig &> /dev/null; then
        echo -e "${YELLOW}⚠️  dig command not found, installing dnsutils...${NC}"
        if apt update -qq && apt install -y dnsutils >/dev/null 2>&1; then
            echo -e "${GREEN}✅ dnsutils installed${NC}"
        else
            echo -e "${RED}ERROR: Failed to install dnsutils${NC}" >&2
            echo "Install manually: apt install dnsutils" >&2
            return 1
        fi
    fi

    # Step 2: Detect server's public IP
    echo "Detecting server public IP..."
    local server_ip
    server_ip=$(curl -s -4 ifconfig.me || curl -s -4 icanhazip.com || curl -s -4 checkip.amazonaws.com)

    if [[ -z "$server_ip" ]]; then
        echo -e "${RED}ERROR: Failed to detect server public IP${NC}" >&2
        echo "Ensure server has internet connectivity" >&2
        return 1
    fi

    echo "  Server IP: $server_ip"
    echo ""

    # Step 3: Query DNS A record
    echo "Querying DNS for $domain..."
    local dns_ip
    dns_ip=$(dig +short "$domain" A | head -1)

    # Step 4: Validate DNS resolution
    if [[ -z "$dns_ip" ]]; then
        echo ""
        echo -e "${RED}❌ DNS RESOLUTION FAILED${NC}"
        echo ""
        echo "Domain: $domain"
        echo "Status: No DNS A record found"
        echo ""
        echo -e "${YELLOW}FIX STEPS:${NC}"
        echo "  1. Configure DNS A record for $domain"
        echo "  2. Point A record to: $server_ip"
        echo "  3. Wait 1-48 hours for DNS propagation"
        echo "  4. Verify: dig +short $domain"
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        return 1
    fi

    echo "  DNS resolves to: $dns_ip"
    echo ""

    # Step 5: Compare DNS IP with server IP
    if [[ "$dns_ip" != "$server_ip" ]]; then
        echo ""
        echo -e "${RED}❌ DNS MISMATCH${NC}"
        echo ""
        echo "Domain:       $domain"
        echo "Resolves to:  $dns_ip"
        echo "Expected:     $server_ip"
        echo ""
        echo -e "${YELLOW}FIX STEPS:${NC}"
        echo "  1. Update DNS A record for $domain"
        echo "  2. Change IP from $dns_ip to $server_ip"
        echo "  3. Wait 1-48 hours for DNS propagation"
        echo "  4. Retry validation"
        echo ""
        echo -e "${CYAN}VERIFY DNS:${NC}"
        echo "  dig +short $domain"
        echo "  nslookup $domain"
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        return 1
    fi

    # Success
    echo -e "${GREEN}✅ DNS VALIDATION SUCCESSFUL${NC}"
    echo ""
    echo "Domain:       $domain"
    echo "Resolves to:  $dns_ip"
    echo "Server IP:    $server_ip"
    echo "Match:        YES"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    return 0
}

#==============================================================================
# FUNCTION: create_haproxy_combined_cert
# PURPOSE: Create HAProxy combined.pem file from Let's Encrypt certificates
# USAGE: create_haproxy_combined_cert <domain>
# RETURNS: 0 on success, 1 on failure
#
# DETAILS:
#   HAProxy requires combined.pem format: fullchain.pem + privkey.pem
#   Location: /etc/letsencrypt/live/<domain>/combined.pem
#
# CALLED WHEN:
#   - After successful certificate acquisition
#   - After successful certificate renewal
#==============================================================================
create_haproxy_combined_cert() {
    local domain="$1"

    # Validate domain parameter
    if [[ -z "$domain" ]]; then
        echo -e "${RED}ERROR: Domain parameter required${NC}" >&2
        return 1
    fi

    local cert_dir="/etc/letsencrypt/live/${domain}"
    local fullchain="${cert_dir}/fullchain.pem"
    local privkey="${cert_dir}/privkey.pem"
    local combined="${cert_dir}/combined.pem"

    echo ""
    echo -e "${CYAN}Creating HAProxy combined.pem for ${domain}...${NC}"
    echo ""

    # Step 1: Validate certificate directory exists
    if [[ ! -d "$cert_dir" ]]; then
        echo -e "${RED}ERROR: Certificate directory not found${NC}" >&2
        echo "Expected: $cert_dir" >&2
        return 1
    fi

    # Step 2: Validate certificate files exist
    local missing_files=()
    [[ ! -f "$fullchain" ]] && missing_files+=("fullchain.pem")
    [[ ! -f "$privkey" ]] && missing_files+=("privkey.pem")

    if [[ ${#missing_files[@]} -gt 0 ]]; then
        echo -e "${RED}ERROR: Missing certificate files${NC}" >&2
        for file in "${missing_files[@]}"; do
            echo "  ✗ $file" >&2
        done
        return 1
    fi

    # Step 3: Validate certificate files are readable
    if [[ ! -r "$fullchain" ]]; then
        echo -e "${RED}ERROR: Cannot read fullchain.pem${NC}" >&2
        echo "File: $fullchain" >&2
        echo "Check permissions" >&2
        return 1
    fi

    if [[ ! -r "$privkey" ]]; then
        echo -e "${RED}ERROR: Cannot read privkey.pem${NC}" >&2
        echo "File: $privkey" >&2
        echo "Check permissions" >&2
        return 1
    fi

    # Step 4: Create combined.pem (fullchain + privkey)
    echo "Concatenating fullchain.pem and privkey.pem..."

    # Use temporary file for atomic operation
    local temp_combined="${combined}.tmp"

    if ! cat "$fullchain" "$privkey" > "$temp_combined"; then
        echo -e "${RED}ERROR: Failed to create combined.pem${NC}" >&2
        rm -f "$temp_combined"
        return 1
    fi

    # Move temporary file to final location (atomic operation)
    if ! mv "$temp_combined" "$combined"; then
        echo -e "${RED}ERROR: Failed to move combined.pem to final location${NC}" >&2
        rm -f "$temp_combined"
        return 1
    fi

    # Step 5: Set permissions (root read-only for private key)
    chmod 600 "$combined" || {
        echo -e "${YELLOW}WARNING: Failed to set permissions on combined.pem${NC}" >&2
    }

    # Step 6: Validate combined.pem format
    if ! validate_haproxy_cert "$combined"; then
        echo -e "${RED}ERROR: Generated combined.pem failed validation${NC}" >&2
        return 1
    fi

    # Step 7: Display summary
    local cert_size
    cert_size=$(stat -c%s "$combined" 2>/dev/null || echo "unknown")

    echo ""
    echo -e "${GREEN}✅ HAProxy combined.pem created successfully${NC}"
    echo ""
    echo "Location: $combined"
    echo "Size:     $cert_size bytes"
    echo "Permissions: $(stat -c%a "$combined" 2>/dev/null || echo "unknown")"
    echo ""

    # Show certificate expiry
    local expiry
    expiry=$(openssl x509 -in "$fullchain" -noout -enddate 2>/dev/null | cut -d= -f2)
    if [[ -n "$expiry" ]]; then
        echo "Certificate expires: $expiry"
        echo ""
    fi

    return 0
}

#==============================================================================
# FUNCTION: validate_haproxy_cert
# PURPOSE: Validate HAProxy combined.pem format
# USAGE: validate_haproxy_cert <combined_pem_path>
# RETURNS: 0 if valid, 1 if invalid
#==============================================================================
validate_haproxy_cert() {
    local combined_pem="$1"

    if [[ ! -f "$combined_pem" ]]; then
        echo -e "${RED}ERROR: File not found: $combined_pem${NC}" >&2
        return 1
    fi

    # Check 1: File contains certificate
    if ! grep -q "BEGIN CERTIFICATE" "$combined_pem"; then
        echo -e "${RED}ERROR: No certificate found in $combined_pem${NC}" >&2
        return 1
    fi

    # Check 2: File contains private key
    if ! grep -q "BEGIN PRIVATE KEY" "$combined_pem"; then
        echo -e "${RED}ERROR: No private key found in $combined_pem${NC}" >&2
        return 1
    fi

    # Check 3: Certificate is valid (OpenSSL validation)
    if ! openssl x509 -in "$combined_pem" -noout -checkend 0 2>/dev/null; then
        echo -e "${YELLOW}WARNING: Certificate has expired or is invalid${NC}" >&2
        return 1
    fi

    # Check 4: Private key is valid
    if ! openssl pkey -in "$combined_pem" -noout 2>/dev/null; then
        echo -e "${RED}ERROR: Private key validation failed${NC}" >&2
        return 1
    fi

    # Success
    return 0
}

#==============================================================================
# FUNCTION: create_combined_cert_for_all_domains
# PURPOSE: Create combined.pem for all domains with Let's Encrypt certificates
# USAGE: create_combined_cert_for_all_domains
# RETURNS: 0 on success, 1 if any domain fails
#==============================================================================
create_combined_cert_for_all_domains() {
    echo ""
    echo -e "${CYAN}Creating HAProxy combined.pem for all domains...${NC}"
    echo ""

    local letsencrypt_dir="/etc/letsencrypt/live"

    if [[ ! -d "$letsencrypt_dir" ]]; then
        echo -e "${YELLOW}WARNING: Let's Encrypt directory not found${NC}"
        echo "Location: $letsencrypt_dir"
        echo "No certificates to process"
        return 0
    fi

    local processed=0
    local failed=0

    # Iterate through all certificate directories
    for cert_dir in "$letsencrypt_dir"/*/; do
        # Skip README directory
        [[ "$(basename "$cert_dir")" == "README" ]] && continue

        local domain
        domain=$(basename "$cert_dir")

        echo "Processing: $domain"

        if create_haproxy_combined_cert "$domain"; then
            ((processed++))
        else
            echo -e "${RED}✗ Failed to create combined.pem for $domain${NC}" >&2
            ((failed++))
        fi
    done

    echo ""
    echo "Summary:"
    echo "  Processed: $processed"
    echo "  Failed:    $failed"
    echo ""

    if [[ $failed -gt 0 ]]; then
        return 1
    fi

    return 0
}

#==============================================================================
# FUNCTION: reload_haproxy_after_cert_update
# PURPOSE: Gracefully reload HAProxy after certificate update
# USAGE: reload_haproxy_after_cert_update
# RETURNS: 0 on success, 1 on failure
#==============================================================================
reload_haproxy_after_cert_update() {
    echo ""
    echo -e "${CYAN}Reloading HAProxy with new certificates...${NC}"
    echo ""

    # Check if HAProxy container exists
    if ! docker ps -a --format '{{.Names}}' | grep -q "vless_haproxy"; then
        echo -e "${YELLOW}WARNING: HAProxy container not found${NC}"
        echo "Skipping HAProxy reload"
        return 0
    fi

    # Check if container is running
    local haproxy_status
    haproxy_status=$(docker inspect vless_haproxy -f '{{.State.Status}}' 2>/dev/null || echo "not-found")

    if [[ "$haproxy_status" != "running" ]]; then
        echo -e "${RED}ERROR: HAProxy container not running (status: $haproxy_status)${NC}" >&2
        return 1
    fi

    # Graceful reload: haproxy -f config.cfg -sf <old_pid>
    echo "Performing graceful reload..."

    local old_pid
    old_pid=$(docker exec vless_haproxy pidof haproxy 2>/dev/null || echo "")

    if [[ -z "$old_pid" ]]; then
        echo -e "${YELLOW}WARNING: Could not get HAProxy PID, attempting restart${NC}"

        if docker restart vless_haproxy >/dev/null 2>&1; then
            sleep 2
            echo -e "${GREEN}✅ HAProxy restarted successfully${NC}"
            return 0
        else
            echo -e "${RED}ERROR: Failed to restart HAProxy${NC}" >&2
            return 1
        fi
    fi

    # Graceful reload with old PID
    if docker exec vless_haproxy haproxy -f /usr/local/etc/haproxy/haproxy.cfg -sf $old_pid 2>&1; then
        echo -e "${GREEN}✅ HAProxy reloaded gracefully (zero downtime)${NC}"
        echo "  Old PID: $old_pid"
        echo "  New PID: $(docker exec vless_haproxy pidof haproxy 2>/dev/null || echo 'unknown')"
        return 0
    else
        echo -e "${RED}ERROR: HAProxy graceful reload failed${NC}" >&2
        return 1
    fi
}

# Export functions for use by other modules
export -f validate_dns_for_domain
export -f create_haproxy_combined_cert
export -f validate_haproxy_cert
export -f create_combined_cert_for_all_domains
export -f reload_haproxy_after_cert_update

#==============================================================================
# CLI Interface (for standalone testing)
#==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly (not sourced)

    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  validate-dns <domain>         - Validate DNS A record for domain"
        echo "  create-combined <domain>      - Create HAProxy combined.pem"
        echo "  validate-cert <combined.pem>  - Validate HAProxy certificate"
        echo "  create-all                    - Create combined.pem for all domains"
        echo "  reload-haproxy                - Reload HAProxy gracefully"
        exit 1
    fi

    command="$1"
    shift

    case "$command" in
        validate-dns)
            validate_dns_for_domain "$@"
            ;;
        create-combined)
            create_haproxy_combined_cert "$@"
            ;;
        validate-cert)
            validate_haproxy_cert "$@"
            ;;
        create-all)
            create_combined_cert_for_all_domains
            ;;
        reload-haproxy)
            reload_haproxy_after_cert_update
            ;;
        *)
            echo "ERROR: Unknown command: $command" >&2
            exit 1
            ;;
    esac
fi

# End of certificate_manager.sh
