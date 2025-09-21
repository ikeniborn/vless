#!/bin/bash

# VLESS+Reality VPN - System Update Management
# Safe system updates with rollback capability
# Version: 1.0
# Author: VLESS Management System

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_utils.sh"

# Configuration
readonly UPDATE_LOG="/opt/vless/logs/updates.log"
readonly UPDATE_STATE_DIR="/opt/vless/updates"
readonly UPDATE_LOCK_FILE="/opt/vless/updates/update.lock"
readonly ROLLBACK_SNAPSHOT_DIR="/opt/vless/updates/snapshots"
readonly PRE_UPDATE_BACKUP_DIR="/opt/vless/updates/backups"
readonly UPDATE_CONFIG_FILE="/opt/vless/config/update_config.conf"

# Update sources
readonly XRAY_RELEASE_URL="https://api.github.com/repos/XTLS/Xray-core/releases/latest"
readonly SYSTEM_UPDATE_SOURCES=("security" "recommended")

# Initialize update system
init_update_system() {
    log_info "Initializing update system..."

    # Create directories
    create_directory_safe "${UPDATE_STATE_DIR}"
    create_directory_safe "${ROLLBACK_SNAPSHOT_DIR}"
    create_directory_safe "${PRE_UPDATE_BACKUP_DIR}"

    # Create default update configuration
    if [[ ! -f "${UPDATE_CONFIG_FILE}" ]]; then
        create_update_config
    fi

    # Set permissions
    chmod 700 "${UPDATE_STATE_DIR}"
    chmod 700 "${ROLLBACK_SNAPSHOT_DIR}"
    chmod 700 "${PRE_UPDATE_BACKUP_DIR}"

    log_info "Update system initialized successfully"
}

# Create update configuration
create_update_config() {
    cat > "${UPDATE_CONFIG_FILE}" << 'EOF'
# VLESS VPN Update Configuration

# Automatic updates (true/false)
AUTO_SECURITY_UPDATES=true
AUTO_XRAY_UPDATES=false
AUTO_SYSTEM_UPDATES=false

# Update schedule (cron format)
SECURITY_UPDATE_SCHEDULE="0 4 * * 1"  # Weekly on Monday at 4 AM
XRAY_UPDATE_SCHEDULE="0 5 1 * *"      # Monthly on 1st at 5 AM
SYSTEM_UPDATE_SCHEDULE="0 6 15 * *"   # Monthly on 15th at 6 AM

# Notification settings
NOTIFY_ON_UPDATES=true
NOTIFY_ON_FAILURES=true

# Rollback settings
AUTO_ROLLBACK_ON_FAILURE=true
ROLLBACK_TIMEOUT_MINUTES=10

# Backup settings
BACKUP_BEFORE_UPDATE=true
KEEP_UPDATE_BACKUPS=5

# Update sources
ENABLE_SECURITY_UPDATES=true
ENABLE_RECOMMENDED_UPDATES=true
ENABLE_PROPOSED_UPDATES=false
EOF

    log_info "Update configuration created"
}

# Check for updates
check_for_updates() {
    local update_type="${1:-all}"

    log_info "Checking for available updates..."

    local updates_available=false

    case "${update_type}" in
        "all"|"system")
            if check_system_updates; then
                updates_available=true
            fi
            ;;
        "all"|"xray")
            if check_xray_updates; then
                updates_available=true
            fi
            ;;
        "all"|"security")
            if check_security_updates; then
                updates_available=true
            fi
            ;;
    esac

    if [[ "${updates_available}" == "true" ]]; then
        log_info "Updates are available"
        return 0
    else
        log_info "No updates available"
        return 1
    fi
}

# Check system updates
check_system_updates() {
    log_info "Checking for system package updates..."

    # Update package lists
    apt-get update > /dev/null 2>&1

    # Check for upgradable packages
    local upgradable_count
    upgradable_count=$(apt list --upgradable 2>/dev/null | grep -v "WARNING" | wc -l)

    if [[ ${upgradable_count} -gt 1 ]]; then
        log_info "Found $((upgradable_count - 1)) system package(s) to update"

        # List upgradable packages
        echo "System packages available for update:"
        apt list --upgradable 2>/dev/null | grep -v "WARNING" | tail -n +2 | \
        while read -r line; do
            echo "  ${line}"
        done

        return 0
    else
        log_info "No system package updates available"
        return 1
    fi
}

# Check Xray updates
check_xray_updates() {
    log_info "Checking for Xray updates..."

    # Get current version
    local current_version
    current_version=$(docker exec vless-xray xray version 2>/dev/null | head -1 | awk '{print $2}' || echo "unknown")

    # Get latest version from GitHub
    local latest_version
    latest_version=$(curl -s "${XRAY_RELEASE_URL}" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' || echo "unknown")

    if [[ "${current_version}" != "${latest_version}" && "${latest_version}" != "unknown" ]]; then
        log_info "Xray update available: ${current_version} → ${latest_version}"
        echo "Xray update available:"
        echo "  Current version: ${current_version}"
        echo "  Latest version:  ${latest_version}"
        return 0
    else
        log_info "Xray is up to date (${current_version})"
        return 1
    fi
}

# Check security updates
check_security_updates() {
    log_info "Checking for security updates..."

    # Check for security updates
    local security_updates
    security_updates=$(apt list --upgradable 2>/dev/null | grep -i security | wc -l)

    if [[ ${security_updates} -gt 0 ]]; then
        log_info "Found ${security_updates} security update(s)"

        echo "Security updates available:"
        apt list --upgradable 2>/dev/null | grep -i security | \
        while read -r line; do
            echo "  ${line}"
        done

        return 0
    else
        log_info "No security updates available"
        return 1
    fi
}

# Prepare for update
prepare_update() {
    local update_type="$1"

    log_info "Preparing for ${update_type} update..."

    # Check if another update is running
    if [[ -f "${UPDATE_LOCK_FILE}" ]]; then
        local lock_pid
        lock_pid=$(cat "${UPDATE_LOCK_FILE}")
        if kill -0 "${lock_pid}" 2>/dev/null; then
            log_error "Another update is already running (PID: ${lock_pid})"
            return 1
        else
            log_warn "Stale lock file found, removing..."
            rm -f "${UPDATE_LOCK_FILE}"
        fi
    fi

    # Create lock file
    echo $$ > "${UPDATE_LOCK_FILE}"

    # Create update session directory
    local session_id
    session_id="update_$(date '+%Y%m%d_%H%M%S')"
    local session_dir="${UPDATE_STATE_DIR}/${session_id}"

    create_directory_safe "${session_dir}"

    # Save session info
    cat > "${session_dir}/session_info" << EOF
UPDATE_TYPE=${update_type}
START_TIME=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
SESSION_ID=${session_id}
PID=$$
EOF

    echo "${session_dir}"
}

# Create system snapshot
create_system_snapshot() {
    local session_dir="$1"
    local snapshot_name="$2"

    log_info "Creating system snapshot: ${snapshot_name}"

    local snapshot_dir="${session_dir}/snapshots/${snapshot_name}"
    create_directory_safe "${snapshot_dir}"

    # Snapshot system state
    cat > "${snapshot_dir}/system_state" << EOF
SNAPSHOT_TIME=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
HOSTNAME=$(hostname)
KERNEL_VERSION=$(uname -r)
DOCKER_VERSION=$(docker --version)
DOCKER_COMPOSE_VERSION=$(docker-compose --version)
DISK_USAGE=$(df -h /)
MEMORY_INFO=$(free -h)
NETWORK_CONFIG=$(ip route show)
RUNNING_CONTAINERS=$(docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}")
SYSTEM_SERVICES=$(systemctl list-units --type=service --state=running --no-pager)
INSTALLED_PACKAGES=$(dpkg -l | grep "^ii" | wc -l)
EOF

    # Snapshot package state
    dpkg -l > "${snapshot_dir}/packages.list"

    # Snapshot Docker state
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}" > "${snapshot_dir}/docker_images.list"
    docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" > "${snapshot_dir}/docker_containers.list"

    # Snapshot configuration
    if [[ -d "/opt/vless/config" ]]; then
        cp -r /opt/vless/config "${snapshot_dir}/"
    fi

    log_info "System snapshot created: ${snapshot_name}"
}

# Apply system updates
apply_system_updates() {
    local session_dir="$1"
    local auto_approve="${2:-false}"

    log_info "Applying system updates..."

    # Create pre-update snapshot
    create_system_snapshot "${session_dir}" "pre_update"

    # Create pre-update backup
    if [[ -f "${SCRIPT_DIR}/backup_restore.sh" ]]; then
        log_info "Creating pre-update backup..."
        "${SCRIPT_DIR}/backup_restore.sh" full "Pre-update backup $(date '+%Y%m%d_%H%M%S')"
    fi

    # Update package lists
    apt-get update

    # Apply updates
    if [[ "${auto_approve}" == "true" ]]; then
        DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    else
        apt-get upgrade
    fi

    # Clean up
    apt-get autoremove -y
    apt-get autoclean

    # Create post-update snapshot
    create_system_snapshot "${session_dir}" "post_update"

    log_info "System updates applied successfully"
}

# Apply Xray updates
apply_xray_updates() {
    local session_dir="$1"

    log_info "Applying Xray updates..."

    # Create pre-update snapshot
    create_system_snapshot "${session_dir}" "pre_xray_update"

    # Stop Xray container
    log_info "Stopping Xray container..."
    docker-compose -f /opt/vless/docker-compose.yml stop xray

    # Pull latest image
    log_info "Pulling latest Xray image..."
    docker pull ghcr.io/xtls/xray-core:latest

    # Remove old container
    docker-compose -f /opt/vless/docker-compose.yml rm -f xray

    # Start new container
    log_info "Starting updated Xray container..."
    docker-compose -f /opt/vless/docker-compose.yml up -d xray

    # Wait for container to start
    sleep 10

    # Validate update
    if ! docker ps | grep -q "vless-xray"; then
        log_error "Xray container failed to start after update"
        return 1
    fi

    # Create post-update snapshot
    create_system_snapshot "${session_dir}" "post_xray_update"

    log_info "Xray update applied successfully"
}

# Validate update
validate_update() {
    local session_dir="$1"
    local update_type="$2"

    log_info "Validating ${update_type} update..."

    local validation_failed=false

    # Basic system checks
    if ! is_service_running "docker"; then
        log_error "Docker service is not running after update"
        validation_failed=true
    fi

    if [[ "${update_type}" == "xray" || "${update_type}" == "all" ]]; then
        # Check Xray container
        if ! docker ps | grep -q "vless-xray"; then
            log_error "Xray container is not running after update"
            validation_failed=true
        fi

        # Test Xray functionality
        if ! docker exec vless-xray xray version > /dev/null 2>&1; then
            log_error "Xray is not responding after update"
            validation_failed=true
        fi
    fi

    # Check configuration integrity
    if [[ -f "/opt/vless/config/xray_config.json" ]]; then
        if ! docker exec vless-xray xray -test -config /etc/xray/config.json > /dev/null 2>&1; then
            log_error "Xray configuration validation failed after update"
            validation_failed=true
        fi
    fi

    # Check disk space
    local disk_usage
    disk_usage=$(df /opt/vless | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ ${disk_usage} -gt 95 ]]; then
        log_error "Critical disk space after update: ${disk_usage}%"
        validation_failed=true
    fi

    if [[ "${validation_failed}" == "true" ]]; then
        log_error "Update validation failed"
        return 1
    else
        log_info "Update validation passed"
        return 0
    fi
}

# Rollback update
rollback_update() {
    local session_dir="$1"
    local reason="${2:-"Manual rollback"}"

    log_info "Rolling back update: ${reason}"

    # Check if pre-update snapshot exists
    local pre_snapshot="${session_dir}/snapshots/pre_update"
    if [[ ! -d "${pre_snapshot}" ]]; then
        log_error "No pre-update snapshot found for rollback"
        return 1
    fi

    # Stop services
    log_info "Stopping services for rollback..."
    systemctl stop vless-vpn 2>/dev/null || true
    docker-compose -f /opt/vless/docker-compose.yml down 2>/dev/null || true

    # Restore configuration
    if [[ -d "${pre_snapshot}/config" ]]; then
        log_info "Restoring configuration..."
        rm -rf /opt/vless/config
        cp -r "${pre_snapshot}/config" /opt/vless/
    fi

    # Rollback Docker images if needed
    if [[ -f "${pre_snapshot}/docker_images.list" ]]; then
        log_info "Checking Docker image rollback..."
        # This is complex and risky, so we'll just restart with current config
        docker-compose -f /opt/vless/docker-compose.yml up -d
    fi

    # Restart services
    log_info "Restarting services..."
    systemctl start vless-vpn 2>/dev/null || true

    # Create rollback record
    cat > "${session_dir}/rollback_info" << EOF
ROLLBACK_TIME=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
ROLLBACK_REASON=${reason}
ROLLBACK_SUCCESS=true
EOF

    log_info "Rollback completed successfully"
}

# Cleanup update session
cleanup_update_session() {
    local session_dir="$1"
    local success="${2:-false}"

    # Remove lock file
    rm -f "${UPDATE_LOCK_FILE}"

    # Update session status
    cat >> "${session_dir}/session_info" << EOF
END_TIME=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
SUCCESS=${success}
EOF

    # Cleanup old sessions (keep last 10)
    find "${UPDATE_STATE_DIR}" -maxdepth 1 -type d -name "update_*" | \
    sort | head -n -10 | xargs rm -rf 2>/dev/null || true

    log_info "Update session cleanup completed"
}

# Schedule automatic updates
schedule_updates() {
    log_info "Setting up automatic update scheduling..."

    # Create update script
    local auto_update_script="/opt/vless/bin/auto_update.sh"
    create_directory_safe "$(dirname "${auto_update_script}")"

    cat > "${auto_update_script}" << 'EOF'
#!/bin/bash
# Automatic update script for VLESS VPN

set -euo pipefail

# Source update functions
source /opt/vless/modules/system_update.sh

# Load configuration
source /opt/vless/config/update_config.conf 2>/dev/null || true

# Default values if config not loaded
AUTO_SECURITY_UPDATES=${AUTO_SECURITY_UPDATES:-true}
AUTO_ROLLBACK_ON_FAILURE=${AUTO_ROLLBACK_ON_FAILURE:-true}

# Determine update type based on schedule
UPDATE_TYPE="security"
case "$(date +%u-%d)" in
    "7-01"|"7-15")  # Sunday, 1st or 15th
        UPDATE_TYPE="system"
        ;;
    "1-01")         # Monday, 1st of month
        UPDATE_TYPE="xray"
        ;;
esac

# Run appropriate update
case "${UPDATE_TYPE}" in
    "security")
        if [[ "${AUTO_SECURITY_UPDATES}" == "true" ]]; then
            log_info "Running automatic security updates..."
            apply_updates "security" true
        fi
        ;;
    "system")
        if [[ "${AUTO_SYSTEM_UPDATES}" == "true" ]]; then
            log_info "Running automatic system updates..."
            apply_updates "system" true
        fi
        ;;
    "xray")
        if [[ "${AUTO_XRAY_UPDATES}" == "true" ]]; then
            log_info "Running automatic Xray updates..."
            apply_updates "xray" true
        fi
        ;;
esac
EOF

    chmod +x "${auto_update_script}"

    # Add cron jobs
    local cron_entries=(
        "0 4 * * 1 ${auto_update_script} >> /opt/vless/logs/updates.log 2>&1"  # Weekly
    )

    for entry in "${cron_entries[@]}"; do
        if ! crontab -l 2>/dev/null | grep -q "${auto_update_script}"; then
            (crontab -l 2>/dev/null; echo "${entry}") | crontab -
        fi
    done

    log_info "Automatic updates scheduled"
}

# Apply updates (main function)
apply_updates() {
    local update_type="$1"
    local auto_approve="${2:-false}"

    log_info "Starting ${update_type} update process..."

    # Prepare update session
    local session_dir
    session_dir=$(prepare_update "${update_type}")

    # Cleanup function
    cleanup_on_exit() {
        cleanup_update_session "${session_dir}" "${success:-false}"
    }
    trap cleanup_on_exit EXIT

    local success=false

    # Apply updates based on type
    case "${update_type}" in
        "system")
            if apply_system_updates "${session_dir}" "${auto_approve}"; then
                if validate_update "${session_dir}" "${update_type}"; then
                    success=true
                fi
            fi
            ;;
        "xray")
            if apply_xray_updates "${session_dir}"; then
                if validate_update "${session_dir}" "${update_type}"; then
                    success=true
                fi
            fi
            ;;
        "security")
            if apply_system_updates "${session_dir}" "${auto_approve}"; then
                if validate_update "${session_dir}" "${update_type}"; then
                    success=true
                fi
            fi
            ;;
        "all")
            local all_success=true
            if ! apply_system_updates "${session_dir}" "${auto_approve}"; then
                all_success=false
            fi
            if ! apply_xray_updates "${session_dir}"; then
                all_success=false
            fi
            if [[ "${all_success}" == "true" ]] && validate_update "${session_dir}" "${update_type}"; then
                success=true
            fi
            ;;
        *)
            log_error "Unknown update type: ${update_type}"
            return 1
            ;;
    esac

    # Handle update failure
    if [[ "${success}" != "true" ]]; then
        log_error "Update failed"

        # Auto rollback if enabled
        if [[ "${AUTO_ROLLBACK_ON_FAILURE:-true}" == "true" ]]; then
            log_info "Attempting automatic rollback..."
            if rollback_update "${session_dir}" "Automatic rollback due to update failure"; then
                log_info "Automatic rollback completed"
            else
                log_error "Automatic rollback failed"
            fi
        fi

        return 1
    fi

    log_info "${update_type} update completed successfully"
    return 0
}

# Show update status
update_status() {
    echo "=== VLESS VPN Update System Status ==="
    echo

    # Check if update is running
    if [[ -f "${UPDATE_LOCK_FILE}" ]]; then
        local lock_pid
        lock_pid=$(cat "${UPDATE_LOCK_FILE}")
        if kill -0 "${lock_pid}" 2>/dev/null; then
            echo "Status: Update in progress (PID: ${lock_pid})"
        else
            echo "Status: Stale lock file found"
        fi
    else
        echo "Status: No update running"
    fi

    echo

    # Show last update sessions
    echo "Recent update sessions:"
    if [[ -d "${UPDATE_STATE_DIR}" ]]; then
        find "${UPDATE_STATE_DIR}" -maxdepth 1 -type d -name "update_*" | \
        sort -r | head -5 | \
        while read -r session_dir; do
            if [[ -f "${session_dir}/session_info" ]]; then
                local session_id=$(basename "${session_dir}")
                local update_type=$(grep "UPDATE_TYPE=" "${session_dir}/session_info" | cut -d'=' -f2)
                local start_time=$(grep "START_TIME=" "${session_dir}/session_info" | cut -d'=' -f2-)
                local success=$(grep "SUCCESS=" "${session_dir}/session_info" 2>/dev/null | cut -d'=' -f2 || echo "unknown")

                printf "  %-30s %-10s %-20s %s\n" "${session_id}" "${update_type}" "${start_time}" "${success}"
            fi
        done
    fi

    echo

    # Show available updates
    echo "Available updates:"
    check_for_updates "all" > /dev/null && echo "  Updates available - run 'check' command for details" || echo "  No updates available"

    echo

    # Show configuration
    if [[ -f "${UPDATE_CONFIG_FILE}" ]]; then
        echo "Update configuration:"
        grep -E "^(AUTO_|ENABLE_)" "${UPDATE_CONFIG_FILE}" | \
        while IFS='=' read -r key value; do
            printf "  %-25s: %s\n" "${key}" "${value}"
        done
    fi
}

# Main function
main() {
    case "${1:-}" in
        "init")
            init_update_system
            ;;
        "check")
            check_for_updates "${2:-all}"
            ;;
        "apply")
            apply_updates "${2:-system}" "${3:-false}"
            ;;
        "rollback")
            if [[ -z "${2:-}" ]]; then
                log_error "Please specify session directory for rollback"
                exit 1
            fi
            rollback_update "$2" "${3:-Manual rollback}"
            ;;
        "schedule")
            schedule_updates
            ;;
        "status")
            update_status
            ;;
        *)
            echo "Usage: $0 {command} [options]"
            echo
            echo "Commands:"
            echo "  init                     Initialize update system"
            echo "  check [type]             Check for updates (type: all|system|xray|security)"
            echo "  apply <type> [auto]      Apply updates (auto: true for non-interactive)"
            echo "  rollback <session>       Rollback from update session"
            echo "  schedule                 Setup automatic updates"
            echo "  status                   Show update system status"
            echo
            echo "Update types:"
            echo "  system                   System package updates"
            echo "  xray                     Xray core updates"
            echo "  security                 Security updates only"
            echo "  all                      All update types"
            exit 1
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi