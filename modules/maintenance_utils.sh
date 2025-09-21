#!/bin/bash

# VLESS+Reality VPN - Maintenance Utilities
# Automated maintenance and optimization procedures
# Version: 1.0
# Author: VLESS Management System

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_utils.sh"

# Configuration
readonly LOG_RETENTION_DAYS=30
readonly BACKUP_RETENTION_DAYS=7
readonly TEMP_CLEANUP_DAYS=3
readonly MAINTENANCE_LOG="/opt/vless/logs/maintenance.log"
readonly MAINTENANCE_MODE_FILE="/opt/vless/.maintenance_mode"

# Maintenance mode functions
enable_maintenance_mode() {
    local reason="${1:-"Scheduled maintenance"}"
    local duration="${2:-"30 minutes"}"

    log_info "Enabling maintenance mode..."

    # Create maintenance mode file
    cat > "${MAINTENANCE_MODE_FILE}" << EOF
MAINTENANCE_START=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
MAINTENANCE_REASON=${reason}
ESTIMATED_DURATION=${duration}
MAINTENANCE_BY=$(whoami)
EOF

    # Stop VPN services gracefully
    log_info "Stopping VPN services for maintenance..."

    # Stop Telegram bot if running
    systemctl stop vless-vpn 2>/dev/null || true

    # Stop Xray container
    docker-compose -f /opt/vless/docker-compose.yml stop xray 2>/dev/null || true

    # Create maintenance page/response
    create_maintenance_response

    log_info "Maintenance mode enabled: ${reason}"
    log_info "Estimated duration: ${duration}"
}

# Disable maintenance mode
disable_maintenance_mode() {
    log_info "Disabling maintenance mode..."

    if [[ ! -f "${MAINTENANCE_MODE_FILE}" ]]; then
        log_warn "System is not in maintenance mode"
        return 0
    fi

    # Remove maintenance mode file
    rm -f "${MAINTENANCE_MODE_FILE}"

    # Start services
    log_info "Starting VPN services..."

    # Start Xray container
    docker-compose -f /opt/vless/docker-compose.yml start xray 2>/dev/null || true

    # Start Telegram bot
    systemctl start vless-vpn 2>/dev/null || true

    # Wait for services to stabilize
    sleep 5

    # Verify services are running
    if is_service_running "docker"; then
        log_info "Docker service is running"
    else
        log_warn "Docker service is not running"
    fi

    if docker ps | grep -q "vless-xray"; then
        log_info "Xray container is running"
    else
        log_warn "Xray container is not running"
    fi

    log_info "Maintenance mode disabled"
}

# Check if system is in maintenance mode
is_maintenance_mode() {
    [[ -f "${MAINTENANCE_MODE_FILE}" ]]
}

# Create maintenance response
create_maintenance_response() {
    local maintenance_html="/opt/vless/config/maintenance.html"

    cat > "${maintenance_html}" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>VPN Service - Maintenance</title>
    <meta charset="utf-8">
    <style>
        body { font-family: Arial, sans-serif; text-align: center; margin-top: 100px; }
        .container { max-width: 600px; margin: 0 auto; }
        .message { color: #666; }
    </style>
</head>
<body>
    <div class="container">
        <h1>VPN Service Under Maintenance</h1>
        <p class="message">
            Our VPN service is currently undergoing scheduled maintenance.
            Service will be restored shortly.
        </p>
        <p class="message">
            Please try again in a few minutes.
        </p>
    </div>
</body>
</html>
EOF
}

# Update system packages
update_system_packages() {
    local auto_approve="${1:-false}"

    log_info "Starting system package update..."

    # Create pre-update backup
    if command -v "${SCRIPT_DIR}/backup_restore.sh" &> /dev/null; then
        log_info "Creating pre-update backup..."
        "${SCRIPT_DIR}/backup_restore.sh" config "Pre-update backup $(date '+%Y%m%d_%H%M%S')"
    fi

    # Update package lists
    log_info "Updating package lists..."
    apt-get update || {
        log_error "Failed to update package lists"
        return 1
    }

    # List available upgrades
    log_info "Checking for available updates..."
    local upgrades
    upgrades=$(apt list --upgradable 2>/dev/null | grep -v "WARNING" | wc -l)

    if [[ ${upgrades} -le 1 ]]; then
        log_info "No packages to upgrade"
        return 0
    fi

    log_info "Found $((upgrades - 1)) package(s) to upgrade"

    # Show packages that will be upgraded
    apt list --upgradable 2>/dev/null | grep -v "WARNING" | tail -n +2

    # Confirm upgrade unless auto-approved
    if [[ "${auto_approve}" != "true" ]]; then
        read -p "Proceed with package upgrade? (y/N): " confirm
        if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
            log_info "Package upgrade cancelled by user"
            return 0
        fi
    fi

    # Perform upgrade
    log_info "Upgrading packages..."
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y || {
        log_error "Package upgrade failed"
        return 1
    }

    # Clean up
    apt-get autoremove -y
    apt-get autoclean

    log_info "System package update completed successfully"
}

# Update Xray core
update_xray_core() {
    local force_update="${1:-false}"

    log_info "Checking for Xray core updates..."

    # Get current version
    local current_version
    current_version=$(docker exec vless-xray xray version 2>/dev/null | head -1 | awk '{print $2}' || echo "unknown")

    log_info "Current Xray version: ${current_version}"

    # Pull latest image
    log_info "Pulling latest Xray image..."
    docker pull ghcr.io/xtls/xray-core:latest || {
        log_error "Failed to pull latest Xray image"
        return 1
    }

    # Check if update is available
    local latest_image_id
    latest_image_id=$(docker images ghcr.io/xtls/xray-core:latest --format "{{.ID}}")

    local current_image_id
    current_image_id=$(docker inspect vless-xray --format "{{.Image}}" 2>/dev/null || echo "")

    if [[ "${latest_image_id}" == "${current_image_id}" && "${force_update}" != "true" ]]; then
        log_info "Xray is already up to date"
        return 0
    fi

    log_info "Updating Xray container..."

    # Stop current container
    docker-compose -f /opt/vless/docker-compose.yml stop xray

    # Remove old container
    docker-compose -f /opt/vless/docker-compose.yml rm -f xray

    # Start new container
    docker-compose -f /opt/vless/docker-compose.yml up -d xray

    # Wait for container to start
    sleep 10

    # Verify update
    local new_version
    new_version=$(docker exec vless-xray xray version 2>/dev/null | head -1 | awk '{print $2}' || echo "unknown")

    log_info "Updated Xray version: ${new_version}"

    # Test container health
    if docker ps | grep -q "vless-xray"; then
        log_info "Xray container updated successfully"
    else
        log_error "Xray container failed to start after update"
        return 1
    fi
}

# Cleanup logs
cleanup_logs() {
    log_info "Starting log cleanup..."

    local logs_cleaned=0

    # Clean Xray logs
    if [[ -d "/opt/vless/logs" ]]; then
        find /opt/vless/logs -name "*.log" -type f -mtime +${LOG_RETENTION_DAYS} -delete
        logs_cleaned=$((logs_cleaned + $(find /opt/vless/logs -name "*.log.gz" -type f -mtime +${LOG_RETENTION_DAYS} | wc -l)))
        find /opt/vless/logs -name "*.log.gz" -type f -mtime +${LOG_RETENTION_DAYS} -delete
    fi

    # Clean Docker logs
    if command -v docker &> /dev/null; then
        log_info "Cleaning Docker logs..."
        docker system prune -f --filter "until=168h" > /dev/null 2>&1 || true
    fi

    # Clean system logs
    if command -v journalctl &> /dev/null; then
        log_info "Cleaning journal logs..."
        journalctl --vacuum-time=30d > /dev/null 2>&1 || true
    fi

    # Rotate current logs
    if command -v logrotate &> /dev/null; then
        logrotate -f /etc/logrotate.d/vless 2>/dev/null || true
    fi

    log_info "Log cleanup completed"
}

# Cleanup temporary files
cleanup_temp_files() {
    log_info "Cleaning temporary files..."

    # Clean backup temp files
    if [[ -d "/opt/vless/backups/temp" ]]; then
        find /opt/vless/backups/temp -type f -mtime +${TEMP_CLEANUP_DAYS} -delete
        find /opt/vless/backups/temp -type d -empty -delete
    fi

    # Clean system temp files
    find /tmp -name "vless_*" -type f -mtime +${TEMP_CLEANUP_DAYS} -delete 2>/dev/null || true
    find /tmp -name "xray_*" -type f -mtime +${TEMP_CLEANUP_DAYS} -delete 2>/dev/null || true

    # Clean old QR code files
    if [[ -d "/opt/vless/qrcodes" ]]; then
        find /opt/vless/qrcodes -name "*.png" -type f -mtime +7 -delete 2>/dev/null || true
    fi

    log_info "Temporary file cleanup completed"
}

# Optimize system performance
optimize_system() {
    log_info "Starting system optimization..."

    # Clear page cache if memory usage is high
    local mem_usage
    mem_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')

    if [[ ${mem_usage} -gt 80 ]]; then
        log_info "High memory usage detected (${mem_usage}%), clearing caches..."
        sync
        echo 3 > /proc/sys/vm/drop_caches
    fi

    # Optimize Docker
    if command -v docker &> /dev/null; then
        log_info "Optimizing Docker..."

        # Remove unused images
        docker image prune -f > /dev/null 2>&1 || true

        # Remove unused volumes
        docker volume prune -f > /dev/null 2>&1 || true

        # Remove unused networks
        docker network prune -f > /dev/null 2>&1 || true
    fi

    # Check and fix file permissions
    log_info "Checking file permissions..."
    chown -R root:root /opt/vless/
    chmod -R 700 /opt/vless/
    chmod +x /opt/vless/modules/*.sh 2>/dev/null || true

    # Update locate database
    if command -v updatedb &> /dev/null; then
        updatedb > /dev/null 2>&1 || true
    fi

    log_info "System optimization completed"
}

# Check system health
check_system_health() {
    log_info "Performing system health check..."

    local health_score=100
    local issues=()

    # Check disk space
    local disk_usage
    disk_usage=$(df /opt/vless | tail -1 | awk '{print $5}' | sed 's/%//')

    if [[ ${disk_usage} -gt 90 ]]; then
        issues+=("Critical: Disk usage is ${disk_usage}%")
        health_score=$((health_score - 30))
    elif [[ ${disk_usage} -gt 80 ]]; then
        issues+=("Warning: Disk usage is ${disk_usage}%")
        health_score=$((health_score - 10))
    fi

    # Check memory usage
    local mem_usage
    mem_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')

    if [[ ${mem_usage} -gt 90 ]]; then
        issues+=("Critical: Memory usage is ${mem_usage}%")
        health_score=$((health_score - 20))
    elif [[ ${mem_usage} -gt 80 ]]; then
        issues+=("Warning: Memory usage is ${mem_usage}%")
        health_score=$((health_score - 5))
    fi

    # Check Docker service
    if ! is_service_running "docker"; then
        issues+=("Critical: Docker service is not running")
        health_score=$((health_score - 40))
    fi

    # Check Xray container
    if ! docker ps | grep -q "vless-xray"; then
        issues+=("Critical: Xray container is not running")
        health_score=$((health_score - 30))
    fi

    # Check certificate expiry
    if [[ -f "/opt/vless/certs/server.crt" ]]; then
        local cert_days
        cert_days=$(openssl x509 -in /opt/vless/certs/server.crt -noout -checkend 2592000 && echo "30+" || echo "0")

        if [[ "${cert_days}" == "0" ]]; then
            issues+=("Warning: SSL certificate expires within 30 days")
            health_score=$((health_score - 15))
        fi
    fi

    # Check log file sizes
    local log_size
    log_size=$(du -sm /opt/vless/logs 2>/dev/null | cut -f1 || echo "0")

    if [[ ${log_size} -gt 1000 ]]; then
        issues+=("Warning: Log files are using ${log_size}MB")
        health_score=$((health_score - 5))
    fi

    # Check backup status
    local backup_age
    if [[ -d "/opt/vless/backups/config" ]]; then
        backup_age=$(find /opt/vless/backups/config -name "*.tar.gz" -type f -mtime -1 | wc -l)
        if [[ ${backup_age} -eq 0 ]]; then
            issues+=("Warning: No recent backups found")
            health_score=$((health_score - 10))
        fi
    fi

    # Generate health report
    echo "=== SYSTEM HEALTH REPORT ==="
    echo "Generated: $(date)"
    echo "Health Score: ${health_score}/100"
    echo

    if [[ ${#issues[@]} -eq 0 ]]; then
        echo "✓ System is healthy - no issues detected"
    else
        echo "Issues detected:"
        for issue in "${issues[@]}"; do
            echo "  × ${issue}"
        done
    fi

    echo
    echo "System metrics:"
    printf "  %-20s: %s%%\n" "Disk usage" "${disk_usage}"
    printf "  %-20s: %s%%\n" "Memory usage" "${mem_usage}"
    printf "  %-20s: %s\n" "Docker service" "$(is_service_running "docker" && echo "Running" || echo "Stopped")"
    printf "  %-20s: %s\n" "Xray container" "$(docker ps | grep -q "vless-xray" && echo "Running" || echo "Stopped")"
    printf "  %-20s: %s\n" "Log size" "${log_size}MB"

    echo

    # Return health score
    return $((100 - health_score))
}

# Generate system diagnostics
generate_diagnostics() {
    local output_file="${1:-/opt/vless/logs/diagnostics_$(date '+%Y%m%d_%H%M%S').log}"

    log_info "Generating system diagnostics..."

    cat > "${output_file}" << EOF
# VLESS VPN System Diagnostics
# Generated: $(date)
# Hostname: $(hostname)

=== SYSTEM INFORMATION ===
$(uname -a)
$(lsb_release -a 2>/dev/null || cat /etc/os-release)

=== RESOURCE USAGE ===
$(free -h)

$(df -h)

$(top -bn1 | head -20)

=== NETWORK CONFIGURATION ===
$(ip route show)

$(ss -tuln)

=== DOCKER STATUS ===
$(docker --version)
$(docker-compose --version)

$(docker ps -a)

$(docker images)

=== XRAY CONFIGURATION ===
$(docker exec vless-xray xray version 2>/dev/null || echo "Xray not available")

=== SYSTEM SERVICES ===
$(systemctl status docker --no-pager 2>/dev/null || echo "Docker status not available")

$(systemctl status vless-vpn --no-pager 2>/dev/null || echo "VPN service status not available")

=== LOG SAMPLES ===
$(tail -50 /opt/vless/logs/system.log 2>/dev/null || echo "System log not available")

=== FILE PERMISSIONS ===
$(ls -la /opt/vless/)

=== DISK USAGE DETAILS ===
$(du -sh /opt/vless/* 2>/dev/null || echo "Directory details not available")

EOF

    log_info "Diagnostics generated: ${output_file}"
    echo "Diagnostics file: ${output_file}"
}

# Schedule maintenance tasks
schedule_maintenance() {
    log_info "Setting up maintenance scheduling..."

    # Create maintenance script
    local maintenance_script="/opt/vless/bin/auto_maintenance.sh"
    create_directory_safe "$(dirname "${maintenance_script}")"

    cat > "${maintenance_script}" << 'EOF'
#!/bin/bash
# Automatic maintenance script for VLESS VPN

set -euo pipefail

# Source maintenance functions
source /opt/vless/modules/maintenance_utils.sh

# Log maintenance start
log_info "Starting scheduled maintenance..."

# Daily maintenance tasks
cleanup_logs
cleanup_temp_files

# Weekly tasks (Sundays)
if [[ $(date +%u) -eq 7 ]]; then
    log_info "Running weekly maintenance tasks..."
    optimize_system
    check_system_health
fi

# Monthly tasks (1st of month)
if [[ $(date +%d) -eq 01 ]]; then
    log_info "Running monthly maintenance tasks..."
    update_system_packages true
    update_xray_core
fi

log_info "Scheduled maintenance completed"
EOF

    chmod +x "${maintenance_script}"

    # Add cron job
    local cron_entry="0 3 * * * ${maintenance_script} >> /opt/vless/logs/maintenance.log 2>&1"

    # Check if cron job already exists
    if ! crontab -l 2>/dev/null | grep -q "${maintenance_script}"; then
        (crontab -l 2>/dev/null; echo "${cron_entry}") | crontab -
        log_info "Automatic maintenance scheduled: Daily at 3:00 AM"
    else
        log_info "Automatic maintenance already scheduled"
    fi
}

# Main function
main() {
    case "${1:-}" in
        "enable-maintenance")
            enable_maintenance_mode "${2:-"Manual maintenance"}" "${3:-"30 minutes"}"
            ;;
        "disable-maintenance")
            disable_maintenance_mode
            ;;
        "status-maintenance")
            if is_maintenance_mode; then
                echo "System is in maintenance mode"
                if [[ -f "${MAINTENANCE_MODE_FILE}" ]]; then
                    cat "${MAINTENANCE_MODE_FILE}"
                fi
            else
                echo "System is not in maintenance mode"
            fi
            ;;
        "update-packages")
            update_system_packages "${2:-false}"
            ;;
        "update-xray")
            update_xray_core "${2:-false}"
            ;;
        "cleanup-logs")
            cleanup_logs
            ;;
        "cleanup-temp")
            cleanup_temp_files
            ;;
        "optimize")
            optimize_system
            ;;
        "health-check")
            check_system_health
            ;;
        "diagnostics")
            generate_diagnostics "$2"
            ;;
        "schedule")
            schedule_maintenance
            ;;
        "full-maintenance")
            log_info "Running full maintenance cycle..."
            cleanup_logs
            cleanup_temp_files
            optimize_system
            check_system_health
            log_info "Full maintenance cycle completed"
            ;;
        *)
            echo "Usage: $0 {command} [options]"
            echo
            echo "Maintenance Mode:"
            echo "  enable-maintenance [reason] [duration]   Enable maintenance mode"
            echo "  disable-maintenance                      Disable maintenance mode"
            echo "  status-maintenance                       Check maintenance status"
            echo
            echo "System Updates:"
            echo "  update-packages [auto]                   Update system packages"
            echo "  update-xray [force]                      Update Xray core"
            echo
            echo "Cleanup Operations:"
            echo "  cleanup-logs                             Clean old log files"
            echo "  cleanup-temp                             Clean temporary files"
            echo "  optimize                                 Optimize system performance"
            echo
            echo "Monitoring:"
            echo "  health-check                             Perform system health check"
            echo "  diagnostics [file]                       Generate system diagnostics"
            echo
            echo "Automation:"
            echo "  schedule                                 Setup automatic maintenance"
            echo "  full-maintenance                         Run complete maintenance cycle"
            exit 1
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi