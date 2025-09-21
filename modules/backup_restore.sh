#!/bin/bash

# VLESS+Reality VPN - Backup and Restore System
# Comprehensive backup solution for all system components
# Version: 1.0
# Author: VLESS Management System

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_utils.sh"

# Backup configuration
readonly BACKUP_BASE_DIR="/opt/vless/backups"
readonly CONFIG_DIR="/opt/vless/config"
readonly LOGS_DIR="/opt/vless/logs"
readonly USERS_DIR="/opt/vless/users"
readonly CERTS_DIR="/opt/vless/certs"
readonly DOCKER_COMPOSE_FILE="/opt/vless/docker-compose.yml"
readonly BACKUP_RETENTION_DAYS=7
readonly MAX_BACKUPS=14

# Backup types
readonly BACKUP_TYPE_FULL="full"
readonly BACKUP_TYPE_CONFIG="config"
readonly BACKUP_TYPE_USERS="users"

# Initialize backup system
init_backup_system() {
    log_info "Initializing backup system..."

    # Create backup directories
    create_directory_safe "${BACKUP_BASE_DIR}"
    create_directory_safe "${BACKUP_BASE_DIR}/full"
    create_directory_safe "${BACKUP_BASE_DIR}/config"
    create_directory_safe "${BACKUP_BASE_DIR}/users"
    create_directory_safe "${BACKUP_BASE_DIR}/temp"

    # Set proper permissions
    chmod 700 "${BACKUP_BASE_DIR}"
    chmod 700 "${BACKUP_BASE_DIR}"/*

    log_info "Backup system initialized successfully"
}

# Generate backup filename with timestamp
generate_backup_filename() {
    local backup_type="$1"
    local hostname=$(hostname)
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    echo "vless_${backup_type}_${hostname}_${timestamp}.tar.gz"
}

# Create full system backup
create_full_backup() {
    local backup_comment="${1:-"Manual full backup"}"

    log_info "Starting full system backup..."

    local backup_file
    backup_file=$(generate_backup_filename "${BACKUP_TYPE_FULL}")
    local backup_path="${BACKUP_BASE_DIR}/full/${backup_file}"
    local temp_dir="${BACKUP_BASE_DIR}/temp/backup_$$"

    # Create temporary directory
    mkdir -p "${temp_dir}"

    # Cleanup function
    cleanup_temp() {
        rm -rf "${temp_dir}" 2>/dev/null || true
    }
    trap cleanup_temp EXIT

    log_info "Creating backup directory structure..."

    # Create backup structure
    mkdir -p "${temp_dir}/vless"
    mkdir -p "${temp_dir}/system"
    mkdir -p "${temp_dir}/metadata"

    # Backup VLESS configuration and data
    if [[ -d "${CONFIG_DIR}" ]]; then
        cp -r "${CONFIG_DIR}" "${temp_dir}/vless/"
        log_info "Configuration backed up"
    fi

    if [[ -d "${USERS_DIR}" ]]; then
        cp -r "${USERS_DIR}" "${temp_dir}/vless/"
        log_info "User data backed up"
    fi

    if [[ -d "${CERTS_DIR}" ]]; then
        cp -r "${CERTS_DIR}" "${temp_dir}/vless/"
        log_info "Certificates backed up"
    fi

    if [[ -f "${DOCKER_COMPOSE_FILE}" ]]; then
        cp "${DOCKER_COMPOSE_FILE}" "${temp_dir}/vless/"
        log_info "Docker compose configuration backed up"
    fi

    # Backup system configuration
    if [[ -f "/etc/ufw/user.rules" ]]; then
        cp "/etc/ufw/user.rules" "${temp_dir}/system/ufw_user.rules"
    fi

    if [[ -f "/etc/ufw/user6.rules" ]]; then
        cp "/etc/ufw/user6.rules" "${temp_dir}/system/ufw_user6.rules"
    fi

    if [[ -f "/etc/ssh/sshd_config" ]]; then
        cp "/etc/ssh/sshd_config" "${temp_dir}/system/sshd_config"
    fi

    # Backup Docker configuration if exists
    if [[ -f "/etc/docker/daemon.json" ]]; then
        cp "/etc/docker/daemon.json" "${temp_dir}/system/docker_daemon.json"
    fi

    # Create metadata
    create_backup_metadata "${temp_dir}/metadata" "${BACKUP_TYPE_FULL}" "${backup_comment}"

    # Create compressed archive
    log_info "Creating compressed archive..."
    cd "${temp_dir}"
    tar -czf "${backup_path}" .
    cd - > /dev/null

    # Validate backup
    if validate_backup_integrity "${backup_path}"; then
        log_info "Full backup created successfully: ${backup_file}"
        log_info "Backup size: $(get_file_size_human "${backup_path}")"
        cleanup_old_backups "${BACKUP_TYPE_FULL}"
        return 0
    else
        log_error "Backup validation failed, removing corrupt backup"
        rm -f "${backup_path}"
        return 1
    fi
}

# Create configuration-only backup
create_config_backup() {
    local backup_comment="${1:-"Configuration backup"}"

    log_info "Starting configuration backup..."

    local backup_file
    backup_file=$(generate_backup_filename "${BACKUP_TYPE_CONFIG}")
    local backup_path="${BACKUP_BASE_DIR}/config/${backup_file}"
    local temp_dir="${BACKUP_BASE_DIR}/temp/config_$$"

    # Create temporary directory
    mkdir -p "${temp_dir}"

    # Cleanup function
    cleanup_temp() {
        rm -rf "${temp_dir}" 2>/dev/null || true
    }
    trap cleanup_temp EXIT

    # Backup configuration files
    mkdir -p "${temp_dir}/config"
    mkdir -p "${temp_dir}/metadata"

    if [[ -d "${CONFIG_DIR}" ]]; then
        cp -r "${CONFIG_DIR}"/* "${temp_dir}/config/" 2>/dev/null || true
    fi

    if [[ -f "${DOCKER_COMPOSE_FILE}" ]]; then
        cp "${DOCKER_COMPOSE_FILE}" "${temp_dir}/config/"
    fi

    # Create metadata
    create_backup_metadata "${temp_dir}/metadata" "${BACKUP_TYPE_CONFIG}" "${backup_comment}"

    # Create compressed archive
    cd "${temp_dir}"
    tar -czf "${backup_path}" .
    cd - > /dev/null

    # Validate backup
    if validate_backup_integrity "${backup_path}"; then
        log_info "Configuration backup created successfully: ${backup_file}"
        cleanup_old_backups "${BACKUP_TYPE_CONFIG}"
        return 0
    else
        log_error "Configuration backup validation failed"
        rm -f "${backup_path}"
        return 1
    fi
}

# Create users-only backup
create_users_backup() {
    local backup_comment="${1:-"Users backup"}"

    log_info "Starting users backup..."

    local backup_file
    backup_file=$(generate_backup_filename "${BACKUP_TYPE_USERS}")
    local backup_path="${BACKUP_BASE_DIR}/users/${backup_file}"
    local temp_dir="${BACKUP_BASE_DIR}/temp/users_$$"

    # Create temporary directory
    mkdir -p "${temp_dir}"

    # Cleanup function
    cleanup_temp() {
        rm -rf "${temp_dir}" 2>/dev/null || true
    }
    trap cleanup_temp EXIT

    # Backup user data
    mkdir -p "${temp_dir}/users"
    mkdir -p "${temp_dir}/metadata"

    if [[ -d "${USERS_DIR}" ]]; then
        cp -r "${USERS_DIR}"/* "${temp_dir}/users/" 2>/dev/null || true
    fi

    # Create metadata
    create_backup_metadata "${temp_dir}/metadata" "${BACKUP_TYPE_USERS}" "${backup_comment}"

    # Create compressed archive
    cd "${temp_dir}"
    tar -czf "${backup_path}" .
    cd - > /dev/null

    # Validate backup
    if validate_backup_integrity "${backup_path}"; then
        log_info "Users backup created successfully: ${backup_file}"
        cleanup_old_backups "${BACKUP_TYPE_USERS}"
        return 0
    else
        log_error "Users backup validation failed"
        rm -f "${backup_path}"
        return 1
    fi
}

# Create backup metadata
create_backup_metadata() {
    local metadata_dir="$1"
    local backup_type="$2"
    local comment="$3"

    local metadata_file="${metadata_dir}/backup_info.txt"

    cat > "${metadata_file}" << EOF
# VLESS VPN Backup Metadata
# Generated: $(date)

BACKUP_TYPE=${backup_type}
BACKUP_DATE=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
BACKUP_TIMESTAMP=$(date '+%s')
HOSTNAME=$(hostname)
SYSTEM_INFO=$(uname -a)
COMMENT=${comment}

# System State
DOCKER_VERSION=$(docker --version 2>/dev/null || echo "Not installed")
XRAY_VERSION=$(docker exec vless-xray xray version 2>/dev/null | head -1 || echo "Not available")
SYSTEM_UPTIME=$(uptime)

# Backup Contents
$(find . -type f -name "*.json" -o -name "*.conf" -o -name "*.yml" -o -name "*.yaml" | sort)
EOF

    # Create checksums
    find "${metadata_dir}/.." -type f ! -path "*/metadata/*" -exec sha256sum {} \; > "${metadata_dir}/checksums.txt"
}

# Validate backup integrity
validate_backup_integrity() {
    local backup_path="$1"

    log_info "Validating backup integrity..."

    # Check if file exists and is readable
    if [[ ! -f "${backup_path}" ]]; then
        log_error "Backup file does not exist: ${backup_path}"
        return 1
    fi

    # Check if file is not empty
    if [[ ! -s "${backup_path}" ]]; then
        log_error "Backup file is empty: ${backup_path}"
        return 1
    fi

    # Test archive integrity
    if ! tar -tzf "${backup_path}" > /dev/null 2>&1; then
        log_error "Backup archive is corrupted: ${backup_path}"
        return 1
    fi

    # Check if metadata exists in archive
    if ! tar -tzf "${backup_path}" | grep -q "metadata/backup_info.txt"; then
        log_error "Backup metadata missing: ${backup_path}"
        return 1
    fi

    log_info "Backup integrity validation passed"
    return 0
}

# List available backups
list_backups() {
    local backup_type="${1:-all}"

    log_info "Available backups:"
    echo

    if [[ "${backup_type}" == "all" || "${backup_type}" == "${BACKUP_TYPE_FULL}" ]]; then
        echo "=== FULL BACKUPS ==="
        list_backups_by_type "${BACKUP_TYPE_FULL}"
        echo
    fi

    if [[ "${backup_type}" == "all" || "${backup_type}" == "${BACKUP_TYPE_CONFIG}" ]]; then
        echo "=== CONFIG BACKUPS ==="
        list_backups_by_type "${BACKUP_TYPE_CONFIG}"
        echo
    fi

    if [[ "${backup_type}" == "all" || "${backup_type}" == "${BACKUP_TYPE_USERS}" ]]; then
        echo "=== USERS BACKUPS ==="
        list_backups_by_type "${BACKUP_TYPE_USERS}"
        echo
    fi
}

# List backups by type
list_backups_by_type() {
    local backup_type="$1"
    local backup_dir="${BACKUP_BASE_DIR}/${backup_type}"

    if [[ ! -d "${backup_dir}" ]]; then
        echo "No ${backup_type} backups found"
        return 0
    fi

    local count=0
    for backup in "${backup_dir}"/*.tar.gz; do
        [[ -f "${backup}" ]] || continue

        local filename=$(basename "${backup}")
        local size=$(get_file_size_human "${backup}")
        local date=$(date -r "${backup}" '+%Y-%m-%d %H:%M:%S')

        printf "  %-50s %10s %s\n" "${filename}" "${size}" "${date}"
        ((count++))
    done

    if [[ ${count} -eq 0 ]]; then
        echo "  No ${backup_type} backups found"
    else
        echo "  Total: ${count} backup(s)"
    fi
}

# Restore from backup
restore_from_backup() {
    local backup_path="$1"
    local force="${2:-false}"

    log_info "Starting restore from backup: $(basename "${backup_path}")"

    # Validate backup
    if ! validate_backup_integrity "${backup_path}"; then
        log_error "Backup validation failed, cannot restore"
        return 1
    fi

    # Create confirmation prompt unless forced
    if [[ "${force}" != "true" ]]; then
        log_warn "This will overwrite current system configuration!"
        read -p "Are you sure you want to continue? (yes/no): " confirm
        if [[ "${confirm}" != "yes" ]]; then
            log_info "Restore cancelled by user"
            return 1
        fi
    fi

    local temp_dir="${BACKUP_BASE_DIR}/temp/restore_$$"

    # Cleanup function
    cleanup_temp() {
        rm -rf "${temp_dir}" 2>/dev/null || true
    }
    trap cleanup_temp EXIT

    # Extract backup
    mkdir -p "${temp_dir}"
    cd "${temp_dir}"

    log_info "Extracting backup..."
    if ! tar -xzf "${backup_path}"; then
        log_error "Failed to extract backup"
        return 1
    fi

    # Read backup metadata
    local backup_info="${temp_dir}/metadata/backup_info.txt"
    if [[ -f "${backup_info}" ]]; then
        log_info "Backup information:"
        grep -E "^(BACKUP_TYPE|BACKUP_DATE|HOSTNAME|COMMENT)=" "${backup_info}" | \
        while IFS='=' read -r key value; do
            printf "  %-15s: %s\n" "${key}" "${value}"
        done
    fi

    # Create pre-restore backup
    log_info "Creating pre-restore backup..."
    create_full_backup "Pre-restore backup $(date '+%Y%m%d_%H%M%S')"

    # Stop services before restore
    log_info "Stopping services..."
    systemctl stop vless-vpn 2>/dev/null || true
    docker-compose -f "${DOCKER_COMPOSE_FILE}" down 2>/dev/null || true

    # Restore VLESS data
    if [[ -d "${temp_dir}/vless" ]]; then
        log_info "Restoring VLESS configuration and data..."

        # Restore configuration
        if [[ -d "${temp_dir}/vless/config" ]]; then
            create_directory_safe "${CONFIG_DIR}"
            cp -r "${temp_dir}/vless/config"/* "${CONFIG_DIR}/" 2>/dev/null || true
            log_info "Configuration restored"
        fi

        # Restore users
        if [[ -d "${temp_dir}/vless/users" ]]; then
            create_directory_safe "${USERS_DIR}"
            cp -r "${temp_dir}/vless/users"/* "${USERS_DIR}/" 2>/dev/null || true
            log_info "User data restored"
        fi

        # Restore certificates
        if [[ -d "${temp_dir}/vless/certs" ]]; then
            create_directory_safe "${CERTS_DIR}"
            cp -r "${temp_dir}/vless/certs"/* "${CERTS_DIR}/" 2>/dev/null || true
            log_info "Certificates restored"
        fi

        # Restore docker-compose
        if [[ -f "${temp_dir}/vless/docker-compose.yml" ]]; then
            cp "${temp_dir}/vless/docker-compose.yml" "${DOCKER_COMPOSE_FILE}"
            log_info "Docker compose configuration restored"
        fi
    fi

    # Restore system configuration
    if [[ -d "${temp_dir}/system" ]]; then
        log_info "Restoring system configuration..."

        # UFW rules (with caution)
        if [[ -f "${temp_dir}/system/ufw_user.rules" ]]; then
            log_warn "UFW rules restoration requires manual review"
            cp "${temp_dir}/system/ufw_user.rules" "/tmp/ufw_user.rules.restore"
            log_info "UFW rules saved to /tmp/ufw_user.rules.restore for manual review"
        fi

        # SSH config (with caution)
        if [[ -f "${temp_dir}/system/sshd_config" ]]; then
            log_warn "SSH config restoration requires manual review"
            cp "${temp_dir}/system/sshd_config" "/tmp/sshd_config.restore"
            log_info "SSH config saved to /tmp/sshd_config.restore for manual review"
        fi

        # Docker daemon config
        if [[ -f "${temp_dir}/system/docker_daemon.json" ]]; then
            cp "${temp_dir}/system/docker_daemon.json" "/etc/docker/daemon.json"
            log_info "Docker daemon configuration restored"
        fi
    fi

    # Set proper permissions
    chown -R root:root /opt/vless/
    chmod -R 700 /opt/vless/

    # Start services
    log_info "Starting services..."
    if [[ -f "${DOCKER_COMPOSE_FILE}" ]]; then
        cd "$(dirname "${DOCKER_COMPOSE_FILE}")"
        docker-compose up -d
    fi

    systemctl start vless-vpn 2>/dev/null || true

    log_info "Restore completed successfully"
    log_warn "Please review system configuration and restart services if needed"

    cd - > /dev/null
}

# Schedule automatic backups
schedule_automatic_backups() {
    log_info "Setting up automatic backup scheduling..."

    # Create backup script
    local backup_script="/opt/vless/bin/auto_backup.sh"
    create_directory_safe "$(dirname "${backup_script}")"

    cat > "${backup_script}" << 'EOF'
#!/bin/bash
# Automatic backup script for VLESS VPN

set -euo pipefail

# Source backup functions
source /opt/vless/modules/backup_restore.sh

# Perform daily config backup
log_info "Starting scheduled configuration backup..."
if create_config_backup "Scheduled daily backup"; then
    log_info "Scheduled backup completed successfully"
else
    log_error "Scheduled backup failed"
    exit 1
fi

# Weekly full backup (Sundays)
if [[ $(date +%u) -eq 7 ]]; then
    log_info "Starting scheduled weekly full backup..."
    if create_full_backup "Scheduled weekly full backup"; then
        log_info "Weekly full backup completed successfully"
    else
        log_error "Weekly full backup failed"
    fi
fi
EOF

    chmod +x "${backup_script}"

    # Add cron job
    local cron_entry="30 2 * * * ${backup_script} >> /opt/vless/logs/backup.log 2>&1"

    # Check if cron job already exists
    if ! crontab -l 2>/dev/null | grep -q "${backup_script}"; then
        (crontab -l 2>/dev/null; echo "${cron_entry}") | crontab -
        log_info "Automatic backup scheduled: Daily at 2:30 AM"
    else
        log_info "Automatic backup already scheduled"
    fi
}

# Cleanup old backups
cleanup_old_backups() {
    local backup_type="$1"
    local backup_dir="${BACKUP_BASE_DIR}/${backup_type}"

    if [[ ! -d "${backup_dir}" ]]; then
        return 0
    fi

    log_info "Cleaning up old ${backup_type} backups..."

    # Count current backups
    local backup_count
    backup_count=$(find "${backup_dir}" -name "*.tar.gz" -type f | wc -l)

    if [[ ${backup_count} -gt ${MAX_BACKUPS} ]]; then
        # Remove oldest backups
        local to_remove=$((backup_count - MAX_BACKUPS))
        find "${backup_dir}" -name "*.tar.gz" -type f -printf '%T+ %p\n' | \
        sort | head -n ${to_remove} | cut -d' ' -f2- | \
        while read -r backup_file; do
            log_info "Removing old backup: $(basename "${backup_file}")"
            rm -f "${backup_file}"
        done
    fi

    # Also remove backups older than retention period
    find "${backup_dir}" -name "*.tar.gz" -type f -mtime +${BACKUP_RETENTION_DAYS} -delete
}

# Get file size in human readable format
get_file_size_human() {
    local file_path="$1"
    du -h "${file_path}" | cut -f1
}

# Backup status and statistics
backup_status() {
    echo "=== VLESS VPN Backup System Status ==="
    echo

    echo "Backup directories:"
    printf "  %-20s: %s\n" "Base directory" "${BACKUP_BASE_DIR}"
    printf "  %-20s: %s\n" "Full backups" "${BACKUP_BASE_DIR}/full"
    printf "  %-20s: %s\n" "Config backups" "${BACKUP_BASE_DIR}/config"
    printf "  %-20s: %s\n" "Users backups" "${BACKUP_BASE_DIR}/users"
    echo

    echo "Backup statistics:"
    for backup_type in full config users; do
        local backup_dir="${BACKUP_BASE_DIR}/${backup_type}"
        if [[ -d "${backup_dir}" ]]; then
            local count=$(find "${backup_dir}" -name "*.tar.gz" -type f | wc -l)
            local size="0"
            if [[ ${count} -gt 0 ]]; then
                size=$(du -sh "${backup_dir}" 2>/dev/null | cut -f1)
            fi
            printf "  %-20s: %d backup(s), %s\n" "${backup_type^}" "${count}" "${size}"
        fi
    done
    echo

    echo "Latest backups:"
    for backup_type in full config users; do
        local backup_dir="${BACKUP_BASE_DIR}/${backup_type}"
        if [[ -d "${backup_dir}" ]]; then
            local latest=$(find "${backup_dir}" -name "*.tar.gz" -type f -printf '%T+ %p\n' | sort -r | head -1 | cut -d' ' -f2-)
            if [[ -n "${latest}" ]]; then
                local date=$(date -r "${latest}" '+%Y-%m-%d %H:%M:%S')
                printf "  %-20s: %s (%s)\n" "${backup_type^}" "$(basename "${latest}")" "${date}"
            else
                printf "  %-20s: No backups found\n" "${backup_type^}"
            fi
        fi
    done
    echo

    # Check cron job
    if crontab -l 2>/dev/null | grep -q "auto_backup.sh"; then
        echo "Automatic backup: Enabled (Daily at 2:30 AM)"
    else
        echo "Automatic backup: Not configured"
    fi
    echo

    echo "Disk usage:"
    df -h "${BACKUP_BASE_DIR}" 2>/dev/null | tail -1 | \
    awk '{printf "  Available space: %s (%s used)\n", $4, $5}'
}

# Main function
main() {
    case "${1:-}" in
        "init")
            init_backup_system
            ;;
        "full")
            create_full_backup "${2:-"Manual full backup"}"
            ;;
        "config")
            create_config_backup "${2:-"Manual config backup"}"
            ;;
        "users")
            create_users_backup "${2:-"Manual users backup"}"
            ;;
        "list")
            list_backups "${2:-all}"
            ;;
        "restore")
            if [[ -z "${2:-}" ]]; then
                log_error "Please specify backup file to restore"
                exit 1
            fi
            restore_from_backup "$2" "${3:-false}"
            ;;
        "schedule")
            schedule_automatic_backups
            ;;
        "cleanup")
            cleanup_old_backups "full"
            cleanup_old_backups "config"
            cleanup_old_backups "users"
            ;;
        "status")
            backup_status
            ;;
        *)
            echo "Usage: $0 {init|full|config|users|list|restore|schedule|cleanup|status}"
            echo
            echo "Commands:"
            echo "  init              Initialize backup system"
            echo "  full [comment]    Create full system backup"
            echo "  config [comment]  Create configuration backup"
            echo "  users [comment]   Create users backup"
            echo "  list [type]       List backups (type: all|full|config|users)"
            echo "  restore <file>    Restore from backup file"
            echo "  schedule          Setup automatic backups"
            echo "  cleanup           Remove old backups"
            echo "  status            Show backup system status"
            exit 1
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi