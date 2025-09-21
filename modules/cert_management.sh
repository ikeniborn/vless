#!/bin/bash

# Certificate Management Module for VLESS+Reality VPN
# This module manages TLS certificates for Reality protocol including
# generation, validation, renewal, and monitoring
# Version: 1.0

set -euo pipefail

# Import common utilities and process isolation
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_utils.sh" 2>/dev/null || {
    echo "Error: Cannot find common_utils.sh"
    exit 1
}

# Import process isolation module
source "${SCRIPT_DIR}/process_isolation/process_safe.sh" 2>/dev/null || {
    log_warn "Process isolation module not found, using standard execution"
}

# Setup signal handlers if process isolation is available
if command -v setup_signal_handlers >/dev/null 2>&1; then
    setup_signal_handlers
fi

# Configuration - use values from common_utils.sh if available
if [[ -z "${CERT_DIR:-}" ]]; then
    CERT_DIR="/opt/vless/certs"
fi
if [[ -z "${CERT_BACKUP_DIR:-}" ]]; then
    CERT_BACKUP_DIR="/opt/vless/backups/certs"
fi
if [[ -z "${CERT_LOG:-}" ]]; then
    CERT_LOG="/opt/vless/logs/certificates.log"
fi

readonly DEFAULT_DOMAIN="vless.local"
readonly CERT_VALIDITY_DAYS=365
readonly RENEWAL_THRESHOLD_DAYS=30

# Certificate file names
CERT_KEY="${CERT_DIR}/server.key"
CERT_CRT="${CERT_DIR}/server.crt"
CERT_CSR="${CERT_DIR}/server.csr"
CERT_CONFIG="${CERT_DIR}/cert_config.conf"

# Create certificate directories
create_cert_directories() {
    log_info "Creating certificate directories"

    mkdir -p "${CERT_DIR}"
    mkdir -p "${CERT_BACKUP_DIR}"
    mkdir -p "$(dirname "${CERT_LOG}")"

    chmod 700 "${CERT_DIR}"
    chmod 700 "${CERT_BACKUP_DIR}"

    log_info "Certificate directories created"
}

# Check if OpenSSL is available
check_openssl() {
    if ! command -v openssl >/dev/null 2>&1; then
        log_error "OpenSSL is not installed"

        # Try to install OpenSSL
        if command -v apt-get >/dev/null 2>&1; then
            log_info "Installing OpenSSL"
            apt-get update && apt-get install -y openssl
        else
            log_error "Please install OpenSSL manually"
            return 1
        fi
    fi

    log_info "OpenSSL is available"
}

# Generate OpenSSL configuration for certificate
generate_cert_config() {
    local domain="${1:-$DEFAULT_DOMAIN}"
    local alt_names="${2:-}"

    log_info "Generating certificate configuration for domain: $domain"

    cat > "${CERT_CONFIG}" << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C=US
ST=VPN
L=Server
O=VLESS VPN
OU=IT Department
CN=$domain

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $domain
DNS.2 = localhost
IP.1 = 127.0.0.1
EOF

    # Add additional alternative names if provided
    if [[ -n "$alt_names" ]]; then
        local index=3
        IFS=',' read -ra NAMES <<< "$alt_names"
        for name in "${NAMES[@]}"; do
            name=$(echo "$name" | xargs)  # trim whitespace
            if [[ $name =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo "IP.$((index-1)) = $name" >> "${CERT_CONFIG}"
            else
                echo "DNS.$index = $name" >> "${CERT_CONFIG}"
                ((index++))
            fi
        done
    fi

    log_info "Certificate configuration generated"
}

# Generate private key
generate_private_key() {
    log_info "Generating private key"

    # Generate 2048-bit RSA private key
    openssl genpkey -algorithm RSA -out "${CERT_KEY}" -pkcs8 -aes256 \
        -pass pass:vless_temp_pass 2>/dev/null || {
        log_error "Failed to generate private key with password"
        return 1
    }

    # Remove password from private key for automated use
    openssl rsa -in "${CERT_KEY}" -out "${CERT_KEY}.tmp" \
        -passin pass:vless_temp_pass 2>/dev/null || {
        log_error "Failed to remove password from private key"
        return 1
    }

    mv "${CERT_KEY}.tmp" "${CERT_KEY}"
    chmod 600 "${CERT_KEY}"

    log_info "Private key generated successfully"
}

# Generate certificate signing request
generate_csr() {
    log_info "Generating certificate signing request"

    openssl req -new -key "${CERT_KEY}" -out "${CERT_CSR}" \
        -config "${CERT_CONFIG}" 2>/dev/null || {
        log_error "Failed to generate CSR"
        return 1
    }

    log_info "Certificate signing request generated"
}

# Generate self-signed certificate
generate_self_signed_cert() {
    local domain="${1:-$DEFAULT_DOMAIN}"
    local alt_names="${2:-}"
    local validity_days="${3:-$CERT_VALIDITY_DAYS}"

    log_info "Generating self-signed certificate for domain: $domain"

    # Create certificate directories
    create_cert_directories

    # Check OpenSSL availability
    check_openssl

    # Generate certificate configuration
    generate_cert_config "$domain" "$alt_names"

    # Generate private key
    generate_private_key

    # Generate CSR
    generate_csr

    # Generate self-signed certificate
    openssl x509 -req -in "${CERT_CSR}" -signkey "${CERT_KEY}" \
        -out "${CERT_CRT}" -days "$validity_days" \
        -extensions v3_req -extfile "${CERT_CONFIG}" 2>/dev/null || {
        log_error "Failed to generate self-signed certificate"
        return 1
    }

    # Set proper permissions
    chmod 644 "${CERT_CRT}"
    chmod 600 "${CERT_KEY}"

    # Log certificate generation
    {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Certificate generated for domain: $domain"
        echo "Certificate file: $CERT_CRT"
        echo "Private key file: $CERT_KEY"
        echo "Validity: $validity_days days"
    } >> "${CERT_LOG}"

    log_info "Self-signed certificate generated successfully"
    log_info "Certificate: $CERT_CRT"
    log_info "Private key: $CERT_KEY"

    # Display certificate information
    display_cert_info
}

# Display certificate information
display_cert_info() {
    if [[ ! -f "$CERT_CRT" ]]; then
        log_error "Certificate file not found: $CERT_CRT"
        return 1
    fi

    log_info "Certificate Information:"
    log_info "========================"

    # Extract certificate details
    local subject serial issuer not_before not_after

    subject=$(openssl x509 -in "$CERT_CRT" -noout -subject 2>/dev/null | sed 's/subject=//')
    serial=$(openssl x509 -in "$CERT_CRT" -noout -serial 2>/dev/null | sed 's/serial=//')
    issuer=$(openssl x509 -in "$CERT_CRT" -noout -issuer 2>/dev/null | sed 's/issuer=//')
    not_before=$(openssl x509 -in "$CERT_CRT" -noout -startdate 2>/dev/null | sed 's/notBefore=//')
    not_after=$(openssl x509 -in "$CERT_CRT" -noout -enddate 2>/dev/null | sed 's/notAfter=//')

    log_info "Subject: $subject"
    log_info "Serial: $serial"
    log_info "Issuer: $issuer"
    log_info "Valid from: $not_before"
    log_info "Valid until: $not_after"

    # Display subject alternative names
    local san
    san=$(openssl x509 -in "$CERT_CRT" -noout -text 2>/dev/null | \
          grep -A1 "Subject Alternative Name" | tail -1 | sed 's/^\s*//' || echo "None")
    log_info "Alternative names: $san"

    # Check certificate validity
    check_cert_validity
}

# Check certificate validity and expiration
check_cert_validity() {
    if [[ ! -f "$CERT_CRT" ]]; then
        log_error "Certificate file not found: $CERT_CRT"
        return 1
    fi

    log_info "Checking certificate validity"

    # Verify certificate
    if openssl x509 -in "$CERT_CRT" -noout -checkend 0 2>/dev/null; then
        log_info "✓ Certificate is currently valid"
    else
        log_error "✗ Certificate has expired"
        return 1
    fi

    # Check expiration in threshold days
    local threshold_seconds=$((RENEWAL_THRESHOLD_DAYS * 24 * 3600))
    if openssl x509 -in "$CERT_CRT" -noout -checkend "$threshold_seconds" 2>/dev/null; then
        log_info "✓ Certificate is valid for more than $RENEWAL_THRESHOLD_DAYS days"
    else
        log_warn "⚠ Certificate expires within $RENEWAL_THRESHOLD_DAYS days"

        # Calculate exact days until expiration
        local end_date_str
        end_date_str=$(openssl x509 -in "$CERT_CRT" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
        local end_date_epoch
        end_date_epoch=$(date -d "$end_date_str" +%s 2>/dev/null || echo "0")
        local current_epoch
        current_epoch=$(date +%s)
        local days_until_expiry=$(( (end_date_epoch - current_epoch) / 86400 ))

        if [[ $days_until_expiry -ge 0 ]]; then
            log_warn "Certificate expires in $days_until_expiry days"
        else
            log_error "Certificate expired $((days_until_expiry * -1)) days ago"
        fi
    fi

    # Verify private key matches certificate
    verify_key_cert_match
}

# Verify that private key matches certificate
verify_key_cert_match() {
    if [[ ! -f "$CERT_KEY" ]] || [[ ! -f "$CERT_CRT" ]]; then
        log_error "Certificate or private key file not found"
        return 1
    fi

    log_info "Verifying private key matches certificate"

    local cert_hash key_hash
    cert_hash=$(openssl x509 -in "$CERT_CRT" -noout -modulus 2>/dev/null | openssl md5)
    key_hash=$(openssl rsa -in "$CERT_KEY" -noout -modulus 2>/dev/null | openssl md5)

    if [[ "$cert_hash" == "$key_hash" ]]; then
        log_info "✓ Private key matches certificate"
    else
        log_error "✗ Private key does not match certificate"
        return 1
    fi
}

# Backup certificates
backup_certificates() {
    log_info "Backing up certificates"

    local backup_timestamp
    backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${CERT_BACKUP_DIR}/certificates_${backup_timestamp}.tar.gz"

    if [[ -d "$CERT_DIR" ]]; then
        tar -czf "$backup_file" -C "$(dirname "$CERT_DIR")" "$(basename "$CERT_DIR")" 2>/dev/null || {
            log_error "Failed to create certificate backup"
            return 1
        }

        log_info "Certificates backed up to: $backup_file"

        # Log backup
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Certificate backup created: $backup_file" >> "${CERT_LOG}"

        # Cleanup old backups (keep last 10)
        find "$CERT_BACKUP_DIR" -name "certificates_*.tar.gz" -type f | \
            sort -r | tail -n +11 | xargs rm -f 2>/dev/null || true
    else
        log_warn "Certificate directory not found, nothing to backup"
    fi
}

# Restore certificates from backup
restore_certificates() {
    local backup_file="$1"

    if [[ -z "$backup_file" ]]; then
        log_error "Backup file path is required"
        return 1
    fi

    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi

    log_info "Restoring certificates from: $backup_file"

    # Backup current certificates if they exist
    if [[ -d "$CERT_DIR" ]]; then
        local current_backup
        current_backup="${CERT_BACKUP_DIR}/pre_restore_$(date +%Y%m%d_%H%M%S).tar.gz"
        tar -czf "$current_backup" -C "$(dirname "$CERT_DIR")" "$(basename "$CERT_DIR")" 2>/dev/null || true
        log_info "Current certificates backed up to: $current_backup"
    fi

    # Extract backup
    tar -xzf "$backup_file" -C "$(dirname "$CERT_DIR")" 2>/dev/null || {
        log_error "Failed to restore certificates from backup"
        return 1
    }

    # Set proper permissions
    chmod 700 "$CERT_DIR"
    chmod 600 "$CERT_KEY" 2>/dev/null || true
    chmod 644 "$CERT_CRT" 2>/dev/null || true

    log_info "Certificates restored successfully"

    # Verify restored certificates
    if [[ -f "$CERT_CRT" ]]; then
        check_cert_validity
    fi
}

# Renew certificate
renew_certificates() {
    local domain="${1:-$DEFAULT_DOMAIN}"
    local alt_names="${2:-}"

    log_info "Renewing certificates for domain: $domain"

    # Backup current certificates
    backup_certificates

    # Generate new certificates
    generate_self_signed_cert "$domain" "$alt_names"

    log_info "Certificate renewal completed"

    # Log renewal
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Certificate renewed for domain: $domain" >> "${CERT_LOG}"
}

# Setup certificate monitoring
setup_cert_monitoring() {
    log_info "Setting up certificate monitoring"

    # Create certificate monitoring script
    cat > /usr/local/bin/vless-cert-monitor << 'EOF'
#!/bin/bash
# VLESS Certificate Monitoring Script

CERT_DIR="/opt/vless/certs"
CERT_CRT="${CERT_DIR}/server.crt"
CERT_LOG="/opt/vless/logs/certificates.log"
THRESHOLD_DAYS=30

log_cert() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$CERT_LOG"
}

if [[ ! -f "$CERT_CRT" ]]; then
    log_cert "WARNING: Certificate file not found: $CERT_CRT"
    exit 1
fi

# Check certificate validity
if ! openssl x509 -in "$CERT_CRT" -noout -checkend 0 2>/dev/null; then
    log_cert "CRITICAL: Certificate has expired!"
    exit 1
fi

# Check if certificate expires within threshold
threshold_seconds=$((THRESHOLD_DAYS * 24 * 3600))
if ! openssl x509 -in "$CERT_CRT" -noout -checkend "$threshold_seconds" 2>/dev/null; then
    # Calculate exact days until expiration
    end_date_str=$(openssl x509 -in "$CERT_CRT" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
    end_date_epoch=$(date -d "$end_date_str" +%s 2>/dev/null || echo "0")
    current_epoch=$(date +%s)
    days_until_expiry=$(( (end_date_epoch - current_epoch) / 86400 ))

    if [[ $days_until_expiry -ge 0 ]]; then
        log_cert "WARNING: Certificate expires in $days_until_expiry days"
    else
        log_cert "CRITICAL: Certificate expired $((days_until_expiry * -1)) days ago"
    fi
fi
EOF

    chmod +x /usr/local/bin/vless-cert-monitor

    # Create cron job for certificate monitoring
    cat > /etc/cron.d/vless-cert-monitor << 'EOF'
# VLESS Certificate Monitoring
0 2 * * * root /usr/local/bin/vless-cert-monitor
EOF

    log_info "Certificate monitoring configured"
    log_info "Monitoring script: /usr/local/bin/vless-cert-monitor"
    log_info "Runs daily at 2:00 AM via cron"
}

# Install certificate monitoring
install_cert_monitoring() {
    setup_cert_monitoring
    log_info "Certificate monitoring installed successfully"
}

# List all certificates
list_certificates() {
    log_info "Certificate Inventory"
    log_info "===================="

    if [[ -d "$CERT_DIR" ]]; then
        find "$CERT_DIR" -name "*.crt" -o -name "*.pem" | while read -r cert_file; do
            if [[ -f "$cert_file" ]]; then
                log_info "Certificate: $cert_file"
                local subject
                subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | sed 's/subject=//' || echo "Unknown")
                log_info "  Subject: $subject"

                local not_after
                not_after=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | sed 's/notAfter=//' || echo "Unknown")
                log_info "  Expires: $not_after"
                echo ""
            fi
        done
    else
        log_info "Certificate directory not found: $CERT_DIR"
    fi

    # List backups
    log_info "Certificate Backups"
    log_info "=================="
    if [[ -d "$CERT_BACKUP_DIR" ]]; then
        find "$CERT_BACKUP_DIR" -name "*.tar.gz" -type f | sort -r | while read -r backup_file; do
            local backup_date
            backup_date=$(stat -c %y "$backup_file" 2>/dev/null | cut -d' ' -f1 || echo "Unknown")
            log_info "Backup: $(basename "$backup_file") (Date: $backup_date)"
        done
    else
        log_info "No backup directory found"
    fi
}

# Generate certificate for specific domain with interactive prompts
interactive_cert_generation() {
    echo "Certificate Generation Wizard"
    echo "============================"

    # Get domain name
    read -p "Enter domain name [$DEFAULT_DOMAIN]: " domain
    domain=${domain:-$DEFAULT_DOMAIN}

    # Get alternative names
    echo "Enter alternative names (comma-separated, optional):"
    echo "Examples: www.example.com,api.example.com,192.168.1.10"
    read -r alt_names

    # Get validity period
    read -p "Enter certificate validity in days [$CERT_VALIDITY_DAYS]: " validity
    validity=${validity:-$CERT_VALIDITY_DAYS}

    # Validate input
    if ! [[ "$validity" =~ ^[0-9]+$ ]] || [[ $validity -lt 1 ]] || [[ $validity -gt 3650 ]]; then
        log_error "Invalid validity period. Must be between 1 and 3650 days."
        return 1
    fi

    # Generate certificate
    generate_self_signed_cert "$domain" "$alt_names" "$validity"
}

# Main script execution
main() {
    case "${1:-}" in
        "generate"|"")
            if [[ $# -gt 1 ]]; then
                generate_self_signed_cert "$2" "${3:-}" "${4:-$CERT_VALIDITY_DAYS}"
            else
                interactive_cert_generation
            fi
            ;;
        "info")
            display_cert_info
            ;;
        "check")
            check_cert_validity
            ;;
        "backup")
            backup_certificates
            ;;
        "restore")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 restore <backup_file>"
                exit 1
            fi
            restore_certificates "$2"
            ;;
        "renew")
            renew_certificates "${2:-$DEFAULT_DOMAIN}" "${3:-}"
            ;;
        "monitor")
            install_cert_monitoring
            ;;
        "list")
            list_certificates
            ;;
        "verify")
            verify_key_cert_match
            ;;
        "help"|"-h"|"--help")
            cat << EOF
Certificate Management Module for VLESS+Reality VPN

Usage: $0 [command] [options]

Commands:
    generate [domain] [alt_names] [days]  Generate self-signed certificate
    info                                  Display certificate information
    check                                Check certificate validity
    backup                               Backup certificates
    restore <backup_file>                Restore from backup
    renew [domain] [alt_names]           Renew certificate
    monitor                              Setup certificate monitoring
    list                                 List all certificates and backups
    verify                               Verify private key matches certificate
    help                                 Show this help message

Examples:
    $0 generate                          # Interactive certificate generation
    $0 generate example.com              # Generate cert for example.com
    $0 generate example.com "www.example.com,api.example.com" 730
    $0 info                              # Show certificate information
    $0 check                             # Check certificate validity
    $0 renew example.com                 # Renew certificate
    $0 backup                            # Backup certificates

Certificate files are stored in: $CERT_DIR
Backups are stored in: $CERT_BACKUP_DIR
EOF
            ;;
        *)
            log_error "Unknown command: $1"
            log_info "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi