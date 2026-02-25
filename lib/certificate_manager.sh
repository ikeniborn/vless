#!/bin/bash
#==============================================================================
# Certificate Manager Module (v5.33)
# Part of familyTraffic VPN v5.33
#
# This module handles:
# - Certificate validation (Let's Encrypt)
# - Integration with certbot lifecycle
#
# Note: HAProxy combined.pem functions preserved as no-op stubs (v5.33).
# In v5.33 single-container architecture nginx reads LE certs directly.
#
# Version: 5.33
# Author: familyTraffic Development Team
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

    # Step 2: Detect server's public IP (use same sequence as wizard for consistency)
    echo "Detecting server public IP..."
    local server_ip
    server_ip=$(curl -s -4 https://api.ipify.org || curl -s -4 https://ifconfig.me || echo "")

    if [[ -z "$server_ip" ]]; then
        echo -e "${RED}ERROR: Failed to detect server public IP${NC}" >&2
        echo "Ensure server has internet connectivity" >&2
        return 1
    fi

    echo "  Server IP: $server_ip"
    echo ""

    # Step 3: Query DNS A record (v5.25: use auto-detected DNS or fallback)
    echo "Querying DNS for $domain..."
    local dns_ip
    local dns_server="${DETECTED_DNS_PRIMARY:-8.8.8.8}"
    dns_ip=$(dig +short "$domain" "@${dns_server}" | tail -1)

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
# PURPOSE: No-op stub — HAProxy removed in v5.33
# USAGE: create_haproxy_combined_cert <domain>
# RETURNS: 0 (always succeeds)
#
# NOTE: In v5.33 single-container architecture nginx inside familytraffic
#       reads fullchain.pem + privkey.pem directly. combined.pem not needed.
#==============================================================================
create_haproxy_combined_cert() {
    local domain="${1:-}"
    echo -e "${YELLOW}ℹ️  create_haproxy_combined_cert: HAProxy removed in v5.33 — skipping for ${domain}${NC}"
    echo "    nginx inside familytraffic reads LE certs directly (no combined.pem needed)"
    return 0
}

#==============================================================================
# FUNCTION: validate_haproxy_cert
# PURPOSE: No-op stub — HAProxy removed in v5.33
# USAGE: validate_haproxy_cert <combined_pem_path>
# RETURNS: 0 (always succeeds)
#==============================================================================
validate_haproxy_cert() {
    local combined_pem="${1:-}"
    echo -e "${YELLOW}ℹ️  validate_haproxy_cert: HAProxy removed in v5.33 — skipping validation for ${combined_pem}${NC}"
    return 0
}

#==============================================================================
# FUNCTION: create_combined_cert_for_all_domains
# PURPOSE: No-op stub — HAProxy removed in v5.33
# USAGE: create_combined_cert_for_all_domains
# RETURNS: 0 (always succeeds)
#==============================================================================
create_combined_cert_for_all_domains() {
    echo -e "${YELLOW}ℹ️  create_combined_cert_for_all_domains: HAProxy removed in v5.33 — skipping${NC}"
    echo "    nginx inside familytraffic reads LE certs directly (no combined.pem needed)"
    return 0
}

#==============================================================================
# FUNCTION: reload_haproxy_after_cert_update
# PURPOSE: Gracefully reload HAProxy after certificate update
# USAGE: reload_haproxy_after_cert_update
# RETURNS: 0 on success, 1 on failure
#==============================================================================
reload_haproxy_after_cert_update() {
    # v5.33: HAProxy removed — nginx runs inside familytraffic container as a supervisord process
    # Certificate reload is handled internally by certbot-renew.sh via supervisorctl signal SIGHUP nginx
    echo -e "${YELLOW}ℹ️  HAProxy removed in v5.33 — cert reload handled by familytraffic container internally${NC}"
    echo "    To manually reload nginx: docker exec familytraffic supervisorctl signal SIGHUP nginx"
    return 0
}

#==============================================================================
# FUNCTION: acquire_certificate_for_domain
# PURPOSE: Unified certificate acquisition workflow (v5.33)
# USAGE: acquire_certificate_for_domain <domain> <email>
# RETURNS: 0 on success, 1 on failure
#
# COMPLETE WORKFLOW:
#   1. Validate DNS A record points to server
#   2. Start Certbot Nginx (port 80)
#   3. Run certbot with ACME HTTP-01 challenge
#   4. nginx reads LE certs directly (combined.pem not needed)
#   5. Stop Certbot Nginx
#   6. nginx in familytraffic container reads certs directly
#
# DEPENDENCIES:
#   - certificate_manager.sh (this module)
#   - certbot_manager.sh (acquire_certificate)
#==============================================================================
acquire_certificate_for_domain() {
    local domain="$1"
    local email="$2"

    # Validate parameters
    if [[ -z "$domain" ]]; then
        echo -e "${RED}ERROR: Domain parameter required${NC}" >&2
        echo "Usage: acquire_certificate_for_domain <domain> <email>" >&2
        return 1
    fi

    if [[ -z "$email" ]]; then
        echo -e "${RED}ERROR: Email parameter required${NC}" >&2
        echo "Usage: acquire_certificate_for_domain <domain> <email>" >&2
        return 1
    fi

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Unified Certificate Acquisition (v5.33)             ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Domain: $domain"
    echo "Email:  $email"
    echo ""

    # STEP 1: DNS Validation (MANDATORY)
    echo -e "${CYAN}[STEP 1/6] DNS Validation${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if ! validate_dns_for_domain "$domain"; then
        echo ""
        echo -e "${RED}✗ ABORTED: DNS validation failed${NC}" >&2
        echo ""
        echo "Certificate acquisition requires valid DNS configuration."
        echo "Fix DNS A record and retry."
        echo ""
        return 1
    fi

    # STEP 2-5: Certificate Acquisition (via letsencrypt_integration.sh)
    echo -e "${CYAN}[STEP 2-5/6] Certificate Acquisition${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Source letsencrypt_integration.sh if not already loaded
    local letsencrypt_lib_path
    letsencrypt_lib_path="$(dirname "${BASH_SOURCE[0]}")/letsencrypt_integration.sh"

    if [[ ! -f "$letsencrypt_lib_path" ]]; then
        echo -e "${RED}ERROR: letsencrypt_integration.sh not found${NC}" >&2
        echo "Expected: $letsencrypt_lib_path" >&2
        return 1
    fi

    if ! command -v acquire_certificate &>/dev/null; then
        source "$letsencrypt_lib_path"
    fi

    # Run certbot acquisition workflow
    if ! acquire_certificate "$domain" "$email"; then
        echo ""
        echo -e "${RED}✗ ABORTED: Certificate acquisition failed${NC}" >&2
        echo ""
        echo "Check certbot logs: /var/log/letsencrypt/letsencrypt.log"
        echo ""
        return 1
    fi

    # STEP 6: HAProxy Reload
    echo ""
    echo -e "${CYAN}[STEP 6/6] nginx Reload (via familytraffic container)${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if ! reload_haproxy_after_cert_update; then
        echo ""
        echo -e "${YELLOW}⚠️  WARNING: nginx reload failed${NC}"
        echo ""
        echo "Certificate acquired successfully, but nginx did not reload."
        echo "Manually reload nginx to use the new certificate:"
        echo "  reload_haproxy_after_cert_update"
        echo ""
        return 1
    fi

    # SUCCESS SUMMARY
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  ${GREEN}✅ CERTIFICATE ACQUISITION COMPLETED${CYAN}                      ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Domain:         $domain"
    echo "Email:          $email"
    echo "Certificate:    /etc/letsencrypt/live/$domain/fullchain.pem"
    echo "Private Key:    /etc/letsencrypt/live/$domain/privkey.pem"
    echo "nginx reads: /etc/letsencrypt/live/$domain/fullchain.pem directly"
    echo "nginx Status: Reloaded via familytraffic container"
    echo ""
    echo -e "${GREEN}Ready to configure reverse proxy or other services using this certificate.${NC}"
    echo ""

    return 0
}

# Export functions for use by other modules
export -f validate_dns_for_domain
export -f acquire_certificate_for_domain
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
        echo "  validate-dns <domain>              - Validate DNS A record for domain"
        echo "  acquire <domain> <email>           - Complete certificate acquisition workflow (v5.33)"
        echo "  create-combined <domain>           - Create combined cert [no-op in v5.33, nginx reads LE directly]"
        echo "  validate-cert <combined.pem>       - Validate certificate [no-op in v5.33]"
        echo "  create-all                         - Create combined certs [no-op in v5.33]"
        echo "  reload-haproxy                     - Reload nginx in familytraffic container"
        echo ""
        echo "v5.33 Workflow (acquire command):"
        echo "  1. Validate DNS"
        echo "  2. Start Certbot Nginx (port 80)"
        echo "  3. Run certbot (ACME HTTP-01)"
        echo "  4. nginx reads LE certs directly (combined.pem not needed)"
        echo "  5. Stop Certbot Nginx"
        echo "  6. Reload HAProxy"
        exit 1
    fi

    command="$1"
    shift

    case "$command" in
        validate-dns)
            validate_dns_for_domain "$@"
            ;;
        acquire)
            acquire_certificate_for_domain "$@"
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
