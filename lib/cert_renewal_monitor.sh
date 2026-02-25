#!/bin/bash
# lib/cert_renewal_monitor.sh
#
# Certificate Renewal Monitoring & Auto-Renewal (v4.3)
# Monitors all reverse proxy certificates and triggers renewal if needed
#
# Features:
# - Checks all certificates from database
# - Auto-renews certificates < 30 days from expiry
# - Email alerts for critical certificates (< 7 days)
# - Integrates with familytraffic-cert-renew deploy hook
# - Comprehensive logging
#
# Integration with existing infrastructure:
# - Uses certbot for renewal
# - Delegates to familytraffic-cert-renew deploy hook
# - Database updates handled by deploy hook
#
# Cron Schedule:
#   Daily:  0 2 * * * /opt/familytraffic/lib/cert_renewal_monitor.sh --auto-renew
#   Weekly: 0 9 * * 1 /opt/familytraffic/lib/cert_renewal_monitor.sh --report
#
# Version: 4.3.0
# Author: VLESS Development Team
# Date: 2025-10-18

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/vless/cert_renewal_monitor.log"
EMAIL_ALERTS="${EMAIL_ALERTS:-false}"
EMAIL_TO="${EMAIL_TO:-root@localhost}"

# Thresholds (days)
AUTO_RENEW_THRESHOLD=30
WARNING_THRESHOLD=14
CRITICAL_THRESHOLD=7

# Source libraries
[[ -f "${SCRIPT_DIR}/letsencrypt_integration.sh" ]] && source "${SCRIPT_DIR}/letsencrypt_integration.sh"

# Colors (for terminal output)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# =============================================================================
# Logging
# =============================================================================

setup_logging() {
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
}

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [cert-monitor] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [cert-monitor] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

# =============================================================================
# Helper Functions
# =============================================================================

get_days_until_expiry() {
    local domain="$1"

    # Get expiry date from database
    local proxy_json
    proxy_json=$(get_proxy "$domain" 2>/dev/null) || return 1

    local cert_expires
    cert_expires=$(echo "$proxy_json" | jq -r '.certificate_expires')

    if [[ -z "$cert_expires" || "$cert_expires" == "null" ]]; then
        log_error "No certificate_expires date for $domain"
        return 1
    fi

    local expiry_epoch
    expiry_epoch=$(date -d "$cert_expires" +%s 2>/dev/null || echo "0")

    if [ "$expiry_epoch" -eq 0 ]; then
        log_error "Invalid certificate_expires date format: $cert_expires"
        return 1
    fi

    local current_epoch
    current_epoch=$(date +%s)

    local days_left=$(( (expiry_epoch - current_epoch) / 86400 ))

    echo "$days_left"
    return 0
}

send_email_alert() {
    local subject="$1"
    local body="$2"

    if [ "$EMAIL_ALERTS" != "true" ]; then
        return 0
    fi

    if command -v mail &> /dev/null; then
        echo "$body" | mail -s "$subject" "$EMAIL_TO"
        log "Email alert sent to $EMAIL_TO"
    else
        log "Warning: 'mail' command not found, email alerts disabled"
    fi
}

# =============================================================================
# Certificate Checking
# =============================================================================

check_certificate() {
    local domain="$1"
    local auto_renew="${2:-false}"

    log "Checking certificate for: $domain"

    # Get days until expiry
    local days_left
    if ! days_left=$(get_days_until_expiry "$domain"); then
        log_error "Failed to get expiry for $domain"
        return 1
    fi

    log "  Certificate expires in: $days_left days"

    # Determine status and action
    local status="OK"
    local action="none"
    local color="$GREEN"

    if [ "$days_left" -lt 0 ]; then
        status="EXPIRED"
        action="renew"
        color="$RED"
    elif [ "$days_left" -lt "$CRITICAL_THRESHOLD" ]; then
        status="CRITICAL"
        action="renew"
        color="$RED"
    elif [ "$days_left" -lt "$WARNING_THRESHOLD" ]; then
        status="WARNING"
        action="watch"
        color="$YELLOW"
    elif [ "$days_left" -lt "$AUTO_RENEW_THRESHOLD" ]; then
        status="RENEW_SOON"
        action="renew"
        color="$YELLOW"
    fi

    echo -e "  Status: ${color}${status}${NC} | Action: $action"

    # Auto-renew if needed
    if [ "$auto_renew" = "true" ] && [ "$action" = "renew" ]; then
        log "  Auto-renewing certificate for $domain..."

        if renew_certificate "$domain"; then
            log "  ✅ Certificate renewed successfully for $domain"

            # Send success notification
            if [ "$EMAIL_ALERTS" = "true" ]; then
                send_email_alert \
                    "✅ Certificate Renewed: $domain" \
                    "Certificate for $domain has been successfully renewed.

New expiry date: $(date -d '+90 days' +'%Y-%m-%d')
Previous days left: $days_left days

Automatic renewal performed by cert_renewal_monitor.sh"
            fi

            return 0
        else
            log_error "  ❌ Failed to renew certificate for $domain"

            # Send failure alert
            send_email_alert \
                "❌ Certificate Renewal Failed: $domain" \
                "CRITICAL: Failed to renew certificate for $domain!

Days until expiry: $days_left days
Status: $status

Manual intervention required. Run:
  sudo vless-proxy renew-cert $domain

Check logs:
  sudo tail -f $LOG_FILE"

            return 1
        fi
    fi

    # Send alert for critical certificates (not auto-renewed)
    if [ "$status" = "CRITICAL" ] || [ "$status" = "EXPIRED" ]; then
        send_email_alert \
            "🚨 Certificate Alert: $domain ($status)" \
            "URGENT: Certificate for $domain is $status!

Days until expiry: $days_left days

Action required:
  sudo vless-proxy renew-cert $domain

This is an automated alert from cert_renewal_monitor.sh"
    fi

    return 0
}

# =============================================================================
# Main Operations
# =============================================================================

check_all_certificates() {
    local auto_renew="${1:-false}"

    log "Starting certificate check (auto_renew=$auto_renew)..."

    # Get all proxies
    local proxy_count
    proxy_count=$(get_proxy_count)

    if [ "$proxy_count" -eq 0 ]; then
        log "No reverse proxies configured"
        return 0
    fi

    log "Found $proxy_count reverse proxy(ies)"
    echo ""

    local checked=0
    local renewed=0
    local failed=0
    local critical=0

    # Check each proxy
    list_proxies | jq -r '.domain' | while read -r domain; do
        ((checked++))

        echo "[$checked/$proxy_count] Checking: $domain"

        if check_certificate "$domain" "$auto_renew"; then
            # Check if renewal happened (days_left changed significantly)
            local new_days
            if new_days=$(get_days_until_expiry "$domain"); then
                if [ "$new_days" -gt 80 ]; then
                    ((renewed++))
                fi
            fi
        else
            ((failed++))
        fi

        # Track critical certificates
        local days_left
        if days_left=$(get_days_until_expiry "$domain"); then
            if [ "$days_left" -lt "$CRITICAL_THRESHOLD" ]; then
                ((critical++))
            fi
        fi

        echo ""
    done

    # Summary
    log "Certificate check complete"
    log "  Checked:  $checked"
    log "  Renewed:  $renewed"
    log "  Failed:   $failed"
    log "  Critical: $critical"

    if [ "$failed" -gt 0 ] || [ "$critical" -gt 0 ]; then
        return 1
    fi

    return 0
}

generate_report() {
    log "Generating certificate status report..."

    local report_file="/tmp/cert_status_report_$(date +%Y%m%d).txt"

    {
        echo "═══════════════════════════════════════════════════════════"
        echo "  VLESS v4.3 - Certificate Status Report"
        echo "  Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════"
        echo ""

        local proxy_count
        proxy_count=$(get_proxy_count)

        echo "Total Reverse Proxies: $proxy_count"
        echo ""

        if [ "$proxy_count" -eq 0 ]; then
            echo "No reverse proxies configured."
            return 0
        fi

        # Table header
        printf "%-35s %-25s %-10s %-12s\n" "DOMAIN" "EXPIRES" "DAYS LEFT" "STATUS"
        echo "─────────────────────────────────────────────────────────────────────────────────"

        local critical_count=0
        local warning_count=0
        local ok_count=0

        # List all certificates
        list_proxies | jq -r '.domain + "|" + .certificate_expires' | while IFS='|' read -r domain cert_expires; do
            local expiry_epoch
            expiry_epoch=$(date -d "$cert_expires" +%s 2>/dev/null || echo "0")

            local current_epoch
            current_epoch=$(date +%s)

            local days_left=$(( (expiry_epoch - current_epoch) / 86400 ))

            local status
            if [ "$days_left" -lt 0 ]; then
                status="EXPIRED"
                ((critical_count++))
            elif [ "$days_left" -lt "$CRITICAL_THRESHOLD" ]; then
                status="CRITICAL"
                ((critical_count++))
            elif [ "$days_left" -lt "$WARNING_THRESHOLD" ]; then
                status="WARNING"
                ((warning_count++))
            else
                status="OK"
                ((ok_count++))
            fi

            printf "%-35s %-25s %-10s %-12s\n" \
                "$domain" \
                "$cert_expires" \
                "$days_left" \
                "$status"
        done

        echo ""
        echo "Summary:"
        echo "  OK:       $ok_count"
        echo "  WARNING:  $warning_count (< $WARNING_THRESHOLD days)"
        echo "  CRITICAL: $critical_count (< $CRITICAL_THRESHOLD days)"
        echo ""

        if [ "$critical_count" -gt 0 ]; then
            echo "⚠️  ATTENTION REQUIRED: $critical_count certificate(s) in CRITICAL state!"
            echo ""
            echo "Recommended actions:"
            echo "  1. Run: sudo /opt/familytraffic/lib/cert_renewal_monitor.sh --auto-renew"
            echo "  2. Or manually: sudo vless-proxy renew-cert <domain>"
            echo ""
        fi

        echo "Auto-renewal configuration:"
        echo "  Threshold: < $AUTO_RENEW_THRESHOLD days"
        echo "  Cron job: 0 2 * * * (daily at 2 AM)"
        echo ""

    } | tee "$report_file"

    log "Report saved: $report_file"

    # Email report if configured
    if [ "$EMAIL_ALERTS" = "true" ]; then
        send_email_alert \
            "Certificate Status Report - $(date +%Y-%m-%d)" \
            "$(cat "$report_file")"
    fi
}

setup_cron_jobs() {
    log "Setting up automatic certificate monitoring cron jobs..."

    # Check if cron jobs already exist
    if sudo crontab -l 2>/dev/null | grep -q "cert_renewal_monitor.sh"; then
        log "Cron jobs already configured"
        return 0
    fi

    # Add cron jobs
    (
        sudo crontab -l 2>/dev/null || true
        echo ""
        echo "# VLESS v4.3 - Certificate Renewal Monitoring"
        echo "# Daily auto-renewal check (2 AM)"
        echo "0 2 * * * /opt/familytraffic/lib/cert_renewal_monitor.sh --auto-renew >> /var/log/vless/cert_cron.log 2>&1"
        echo ""
        echo "# Weekly status report (Monday 9 AM)"
        echo "0 9 * * 1 /opt/familytraffic/lib/cert_renewal_monitor.sh --report >> /var/log/vless/cert_cron.log 2>&1"
    ) | sudo crontab -

    log "✅ Cron jobs configured:"
    log "  - Daily auto-renewal: 0 2 * * *"
    log "  - Weekly report: 0 9 * * 1"

    return 0
}

# =============================================================================
# Usage / Help
# =============================================================================

show_usage() {
    cat <<EOF
VLESS v4.3 - Certificate Renewal Monitor

USAGE:
  sudo $0 [command]

COMMANDS:
  --check              Check all certificates (no auto-renewal)
  --auto-renew         Check and auto-renew certificates < $AUTO_RENEW_THRESHOLD days
  --report             Generate detailed status report
  --setup-cron         Setup automatic cron jobs
  -h, --help           Show this help

EXAMPLES:
  # Manual check (no renewal)
  sudo $0 --check

  # Auto-renew expiring certificates
  sudo $0 --auto-renew

  # Generate report
  sudo $0 --report

  # Setup automatic monitoring
  sudo $0 --setup-cron

CONFIGURATION:
  AUTO_RENEW_THRESHOLD: $AUTO_RENEW_THRESHOLD days
  WARNING_THRESHOLD:    $WARNING_THRESHOLD days
  CRITICAL_THRESHOLD:   $CRITICAL_THRESHOLD days

  EMAIL_ALERTS:         $EMAIL_ALERTS
  EMAIL_TO:             $EMAIL_TO

EOF
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    setup_logging

    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run with sudo"
        exit 1
    fi

    # Parse command
    local command="${1:-}"

    case "$command" in
        --check)
            check_all_certificates false
            ;;
        --auto-renew)
            check_all_certificates true
            ;;
        --report)
            generate_report
            ;;
        --setup-cron)
            setup_cron_jobs
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        "")
            log_error "No command specified"
            echo ""
            show_usage
            exit 1
            ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
