#!/bin/bash
#==============================================================================
# Certificate Management Module for Let's Encrypt
# Part of VLESS + Reality VPN v4.3
#
# This module handles:
# - Let's Encrypt certificate acquisition via certbot
# - DNS validation before certificate requests
# - Port 80 management for ACME HTTP-01 challenge
# - Auto-renewal setup with cron jobs
# - HAProxy combined.pem creation (v4.3)
# - Deploy hooks for HAProxy/Xray restart
#
# Version: 4.3
# Author: VLESS Team
# Date: 2025-10-17
#==============================================================================

# Color codes for output (conditional to avoid conflicts when sourced by CLI)
[[ -z "${RED:-}" ]] && readonly RED='\033[0;31m'
[[ -z "${GREEN:-}" ]] && readonly GREEN='\033[0;32m'
[[ -z "${YELLOW:-}" ]] && readonly YELLOW='\033[1;33m'
[[ -z "${NC:-}" ]] && readonly NC='\033[0m' # No Color

# Source certificate manager for combined.pem creation (v4.3)
CERT_MANAGER_PATH="$(dirname "${BASH_SOURCE[0]}")/certificate_manager.sh"
if [[ -f "$CERT_MANAGER_PATH" ]]; then
    source "$CERT_MANAGER_PATH"
fi

# Source certbot manager for Certbot Nginx service (v4.3)
CERTBOT_MANAGER_PATH="$(dirname "${BASH_SOURCE[0]}")/certbot_manager.sh"
if [[ -f "$CERTBOT_MANAGER_PATH" ]]; then
    source "$CERTBOT_MANAGER_PATH"
fi

#==============================================================================
# FUNCTION: validate_domain_dns
# PURPOSE: Validate that domain DNS A record points to server IP
# USAGE: validate_domain_dns <domain> <server_ip>
# RETURNS: 0 on success, 1 on failure
#==============================================================================
validate_domain_dns() {
    local domain="$1"
    local server_ip="$2"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "DNS Validation for Let's Encrypt"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Domain: $domain"
    echo "Expected IP: $server_ip"
    echo ""

    # Check if dig is available
    if ! command -v dig &> /dev/null; then
        echo -e "${RED}❌ ERROR: dig command not found${NC}"
        echo "Installing dnsutils..."
        apt update -qq
        apt install -y dnsutils
    fi

    # Get DNS A record using dig
    echo "Querying DNS for $domain..."
    local dns_ip=$(dig +short "$domain" A | head -1)

    # Check if domain resolves
    if [ -z "$dns_ip" ]; then
        echo ""
        echo -e "${RED}❌ DNS RESOLUTION FAILED${NC}"
        echo ""
        echo "Domain: $domain"
        echo "Status: No DNS A record found"
        echo ""
        echo "FIX STEPS:"
        echo "1. Ensure DNS A record is configured for $domain"
        echo "2. Point A record to: $server_ip"
        echo "3. Wait 1-48 hours for DNS propagation"
        echo "4. Verify: dig +short $domain"
        echo ""
        return 1
    fi

    # Check if DNS points to server
    if [ "$dns_ip" != "$server_ip" ]; then
        echo ""
        echo -e "${RED}❌ DNS MISMATCH${NC}"
        echo ""
        echo "Domain:       $domain"
        echo "Resolves to:  $dns_ip"
        echo "Expected:     $server_ip"
        echo ""
        echo "FIX STEPS:"
        echo "1. Update DNS A record for $domain"
        echo "2. Change IP from $dns_ip to $server_ip"
        echo "3. Wait 1-48 hours for DNS propagation"
        echo "4. Retry installation"
        echo ""
        echo "VERIFY DNS:"
        echo "  dig +short $domain"
        echo "  nslookup $domain"
        echo ""
        return 1
    fi

    # Success
    echo ""
    echo -e "${GREEN}✅ DNS VALIDATION SUCCESSFUL${NC}"
    echo ""
    echo "Domain: $domain"
    echo "Resolves to: $dns_ip"
    echo "Match: YES"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    return 0
}

#==============================================================================
# FUNCTION: install_certbot
# PURPOSE: Install certbot (Let's Encrypt client) if not already present
# USAGE: install_certbot
# RETURNS: 0 on success, 1 on failure
#==============================================================================
install_certbot() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Certbot Installation Check"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Check if already installed
    if command -v certbot &> /dev/null; then
        local version=$(certbot --version 2>&1 | head -1)
        echo -e "${GREEN}✅ Certbot already installed${NC}"
        echo "Version: $version"
        echo ""
        return 0
    fi

    # Install certbot
    echo "Installing certbot..."
    echo ""

    apt update -qq || {
        echo -e "${RED}❌ apt update failed${NC}"
        return 1
    }

    apt install -y certbot || {
        echo -e "${RED}❌ Certbot installation failed${NC}"
        echo ""
        echo "Manual installation:"
        echo "  sudo apt update"
        echo "  sudo apt install certbot"
        echo ""
        return 1
    }

    # Verify installation
    if ! command -v certbot &> /dev/null; then
        echo -e "${RED}❌ Certbot installation verification failed${NC}"
        echo "Command 'certbot' not found after installation"
        return 1
    fi

    local version=$(certbot --version 2>&1 | head -1)
    echo ""
    echo -e "${GREEN}✅ Certbot installed successfully${NC}"
    echo "Version: $version"
    echo ""

    return 0
}

#==============================================================================
# FUNCTION: obtain_certificate
# PURPOSE: Obtain Let's Encrypt certificate using ACME HTTP-01 challenge
# USAGE: obtain_certificate <domain> <email>
# RETURNS: 0 on success, 1 on failure
# NOTE: v4.3 uses Certbot Nginx service (webroot mode) instead of standalone
#==============================================================================
obtain_certificate() {
    local domain="$1"
    local email="$2"

    # v4.3: Use Certbot Nginx service (webroot mode) via certbot_manager.sh
    if command -v acquire_certificate &>/dev/null; then
        # Use new certbot_manager.sh workflow
        if acquire_certificate "$domain" "$email"; then
            return 0
        else
            return 1
        fi
    else
        # Fallback to standalone mode (legacy v3.3)
        echo ""
        echo -e "${YELLOW}WARNING: certbot_manager.sh not found, using standalone mode${NC}"
        echo ""

        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Let's Encrypt Certificate Acquisition (Standalone Mode)"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Domain: $domain"
        echo "Email:  $email"
        echo ""

        # Run certbot in standalone mode
        certbot certonly \
            --standalone \
            --non-interactive \
            --agree-tos \
            --email "$email" \
            --domain "$domain" \
            --preferred-challenges http

        local exit_code=$?

        if [ $exit_code -ne 0 ]; then
            echo ""
            echo -e "${RED}❌ CERTIFICATE ACQUISITION FAILED${NC}"
            echo ""
            return 1
        fi

        # Verify certificate files exist
        local cert_path="/etc/letsencrypt/live/$domain"

        if [[ ! -f "$cert_path/fullchain.pem" ]] || [[ ! -f "$cert_path/privkey.pem" ]]; then
            echo -e "${RED}❌ Certificate files not found${NC}"
            return 1
        fi

        # Secure permissions
        chmod 600 "$cert_path/privkey.pem"
        chmod 600 "$cert_path/cert.pem"
        chmod 644 "$cert_path/fullchain.pem"
        chmod 644 "$cert_path/chain.pem"

        # Display certificate info
        echo ""
        echo -e "${GREEN}✅ CERTIFICATE OBTAINED SUCCESSFULLY!${NC}"
        echo ""

        # v5.33: HAProxy combined.pem removed (single container, nginx reads LE certs directly)
        # Nginx reload via supervisorctl SIGHUP is handled inside the container by certbot-renew.sh

        return 0
    fi
}

#==============================================================================
# FUNCTION: setup_renewal_cron
# PURPOSE: Setup cron job for automatic certificate renewal
# USAGE: setup_renewal_cron
# RETURNS: 0 on success, 1 on failure
#==============================================================================
setup_renewal_cron() {
    local cron_file="/etc/cron.d/certbot-vless-renew"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Auto-Renewal Cron Job Setup"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Create cron job file
    cat > "$cron_file" <<'EOF'
# Auto-renewal for VLESS Let's Encrypt certificates
# Runs twice daily at midnight and noon (UTC)
# Certbot checks if renewal is needed (< 30 days until expiry)
# Deploy hook restarts Xray after successful renewal

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Twice daily renewal check (v5.33: deploy-hook sends SIGHUP to nginx via supervisorctl)
0 0,12 * * * root certbot renew --quiet --deploy-hook "docker exec familytraffic supervisorctl signal SIGHUP nginx" >> /opt/familytraffic/logs/certbot-renew.log 2>&1
EOF

    # Set correct permissions
    chmod 644 "$cron_file"

    echo -e "${GREEN}✅ Cron job created successfully${NC}"
    echo ""
    echo "Cron file: $cron_file"
    echo "Schedule:  Twice daily (00:00 and 12:00 UTC)"
    echo "Command:   certbot renew --quiet --deploy-hook '/usr/local/bin/vless-cert-renew'"
    echo "Log file:  /opt/familytraffic/logs/certbot-renew.log"
    echo ""
    echo "RENEWAL BEHAVIOR:"
    echo "  - Certbot checks twice daily if renewal needed"
    echo "  - Renewal triggered when < 30 days until expiry"
    echo "  - Deploy hook restarts Xray after successful renewal"
    echo "  - Email notifications sent to registered email on failures"
    echo ""
    echo "MANUAL OPERATIONS:"
    echo "  - Dry-run test: sudo certbot renew --dry-run"
    echo "  - Force renewal: sudo certbot renew --force-renewal"
    echo "  - Check logs:    cat /opt/familytraffic/logs/certbot-renew.log"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    return 0
}

#==============================================================================
# FUNCTION: cleanup_certificates
# PURPOSE: Remove Let's Encrypt certificates and cron jobs (v3.4)
# USAGE: cleanup_certificates [domain]
# ARGS: domain (optional) - specific domain to remove, or all if not specified
# RETURNS: 0 on success, 1 on failure
# CALLED WHEN: Switching from TLS to plaintext mode, or during uninstallation
#==============================================================================
cleanup_certificates() {
    local domain="${1:-}"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Certificate Cleanup (v3.4)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Step 1: Remove cron job
    local cron_file="/etc/cron.d/certbot-vless-renew"
    if [[ -f "$cron_file" ]]; then
        echo "Removing auto-renewal cron job..."
        rm -f "$cron_file"
        echo -e "${GREEN}✅ Cron job removed: $cron_file${NC}"
    else
        echo "ℹ  Cron job not found (already removed or never created)"
    fi
    echo ""

    # Step 2: Remove certificates
    if [[ -n "$domain" ]]; then
        # Remove specific domain
        echo "Removing certificates for domain: $domain"
        echo ""

        local cert_path="/etc/letsencrypt/live/$domain"
        local renewal_conf="/etc/letsencrypt/renewal/$domain.conf"
        local archive_path="/etc/letsencrypt/archive/$domain"

        if [[ -d "$cert_path" ]]; then
            rm -rf "$cert_path"
            echo -e "${GREEN}✅ Certificate directory removed: $cert_path${NC}"
        else
            echo "ℹ  Certificate directory not found: $cert_path"
        fi

        if [[ -f "$renewal_conf" ]]; then
            rm -f "$renewal_conf"
            echo -e "${GREEN}✅ Renewal config removed: $renewal_conf${NC}"
        else
            echo "ℹ  Renewal config not found: $renewal_conf"
        fi

        if [[ -d "$archive_path" ]]; then
            rm -rf "$archive_path"
            echo -e "${GREEN}✅ Certificate archive removed: $archive_path${NC}"
        else
            echo "ℹ  Certificate archive not found: $archive_path"
        fi
    else
        # Remove all VLESS-related certificates (scan for certificates)
        echo "Scanning for VLESS certificates..."
        echo ""

        if [[ -d "/etc/letsencrypt/live" ]]; then
            local found_certs=0
            for cert_dir in /etc/letsencrypt/live/*/; do
                # Skip README
                [[ "$(basename "$cert_dir")" == "README" ]] && continue

                local cert_domain=$(basename "$cert_dir")
                echo "Found certificate: $cert_domain"

                # Ask user for confirmation
                local confirm
                read -rp "Remove certificate for $cert_domain? [y/N]: " confirm
                confirm=${confirm,,}

                if [[ "$confirm" == "y" || "$confirm" == "yes" ]]; then
                    rm -rf "/etc/letsencrypt/live/$cert_domain"
                    rm -f "/etc/letsencrypt/renewal/$cert_domain.conf"
                    rm -rf "/etc/letsencrypt/archive/$cert_domain"
                    echo -e "${GREEN}✅ Removed certificates for $cert_domain${NC}"
                    found_certs=1
                else
                    echo "ℹ  Skipped $cert_domain"
                fi
                echo ""
            done

            if [[ $found_certs -eq 0 ]]; then
                echo "ℹ  No certificates found to remove"
            fi
        else
            echo "ℹ  /etc/letsencrypt/live directory not found"
        fi
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}✅ Certificate cleanup completed${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    return 0
}

# End of certbot_setup.sh
