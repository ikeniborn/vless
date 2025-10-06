#!/bin/bash
#==============================================================================
# Certificate Management Module for Let's Encrypt
# Part of VLESS + Reality VPN v3.3
#
# This module handles:
# - Let's Encrypt certificate acquisition via certbot
# - DNS validation before certificate requests
# - Port 80 management for ACME HTTP-01 challenge
# - Auto-renewal setup with cron jobs
# - Deploy hooks for Xray restart
#
# Version: 3.3
# Author: VLESS Team
# Date: 2025-10-06
#==============================================================================

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

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
# NOTE: Port 80 must be open before calling this function
#==============================================================================
obtain_certificate() {
    local domain="$1"
    local email="$2"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Let's Encrypt Certificate Acquisition"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Domain: $domain"
    echo "Email:  $email"
    echo ""
    echo "Using ACME HTTP-01 challenge (requires port 80)"
    echo "This may take 30-60 seconds..."
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
        echo "Exit code: $exit_code"
        echo ""
        echo "POSSIBLE CAUSES:"
        echo "  1. Port 80 not accessible from the internet"
        echo "  2. DNS not pointing to this server"
        echo "  3. Let's Encrypt rate limit hit:"
        echo "     - 5 failed validations per hour"
        echo "     - 50 certificates per domain per week"
        echo "  4. Firewall blocking HTTP traffic"
        echo "  5. Another service occupying port 80"
        echo ""
        echo "DEBUGGING STEPS:"
        echo "  1. Check DNS:"
        echo "     dig +short $domain"
        echo ""
        echo "  2. Check port 80 accessibility:"
        echo "     nc -zv $domain 80"
        echo "     curl -I http://$domain"
        echo ""
        echo "  3. Check certbot logs:"
        echo "     cat /var/log/letsencrypt/letsencrypt.log"
        echo ""
        echo "  4. Check for services on port 80:"
        echo "     sudo ss -tulnp | grep :80"
        echo "     sudo lsof -i :80"
        echo ""
        echo "  5. Try staging environment (for testing):"
        echo "     certbot certonly --staging --standalone -d $domain"
        echo ""
        return 1
    fi

    # Verify certificate files exist
    local cert_path="/etc/letsencrypt/live/$domain"

    if [[ ! -f "$cert_path/fullchain.pem" ]]; then
        echo -e "${RED}❌ Certificate file not found${NC}"
        echo "Expected: $cert_path/fullchain.pem"
        return 1
    fi

    if [[ ! -f "$cert_path/privkey.pem" ]]; then
        echo -e "${RED}❌ Private key not found${NC}"
        echo "Expected: $cert_path/privkey.pem"
        return 1
    fi

    # Secure private key permissions
    chmod 600 "$cert_path/privkey.pem"
    chmod 600 "$cert_path/cert.pem"
    chmod 644 "$cert_path/fullchain.pem"
    chmod 644 "$cert_path/chain.pem"

    # Display certificate info
    echo ""
    echo -e "${GREEN}✅ CERTIFICATE OBTAINED SUCCESSFULLY!${NC}"
    echo ""
    echo "Certificate location: $cert_path"
    echo ""
    echo "Files:"
    ls -lh "$cert_path" | grep -E "(fullchain|privkey|cert|chain)\.pem" | awk '{print "  " $9 " (" $5 ")"}'
    echo ""

    # Show expiry date
    local expiry=$(openssl x509 -in "$cert_path/cert.pem" -noout -enddate | cut -d= -f2)
    echo "Certificate expires: $expiry"
    echo "Auto-renewal scheduled at 60 days (30 days before expiry)"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    return 0
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

# Twice daily renewal check
0 0,12 * * * root certbot renew --quiet --deploy-hook "/usr/local/bin/vless-cert-renew" >> /opt/vless/logs/certbot-renew.log 2>&1
EOF

    # Set correct permissions
    chmod 644 "$cron_file"

    echo -e "${GREEN}✅ Cron job created successfully${NC}"
    echo ""
    echo "Cron file: $cron_file"
    echo "Schedule:  Twice daily (00:00 and 12:00 UTC)"
    echo "Command:   certbot renew --quiet --deploy-hook '/usr/local/bin/vless-cert-renew'"
    echo "Log file:  /opt/vless/logs/certbot-renew.log"
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
    echo "  - Check logs:    cat /opt/vless/logs/certbot-renew.log"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    return 0
}

# End of certbot_setup.sh
