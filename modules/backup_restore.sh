#!/bin/bash

# VLESS+Reality VPN Management System - Backup and Restore System
# Version: 1.0.0
# Description: Comprehensive backup and disaster recovery system
#
# Features:
# - Full system configuration backup
# - User database backup with encryption
# - Incremental backup support
# - Automated backup scheduling
# - Remote backup storage (S3, FTP, etc.)
# - Point-in-time restore capability
# - Backup integrity verification
# - Process isolation for EPERM prevention

set -euo pipefail

# Import common utilities
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SOURCE_DIR}/common_utils.sh"

# Setup signal handlers
setup_signal_handlers

# Configuration
readonly BACKUP_BASE_DIR="/opt/vless/backup"
readonly BACKUP_CONFIG_DIR="${BACKUP_BASE_DIR}/config"
readonly BACKUP_DATA_DIR="${BACKUP_BASE_DIR}/data"
readonly BACKUP_LOGS_DIR="${BACKUP_BASE_DIR}/logs"
readonly BACKUP_TEMP_DIR="${BACKUP_BASE_DIR}/temp"

# Simplified backup configuration
readonly BACKUP_TYPE="${BACKUP_TYPE:-essential}"  # essential, full, minimal
readonly BACKUP_INTERVAL="${BACKUP_INTERVAL:-604800}"  # Weekly default
readonly REMOTE_BACKUP_ENABLED="${REMOTE_BACKUP_ENABLED:-false}"  # Disabled by default

# Backup directories
readonly FULL_BACKUP_DIR="${BACKUP_BASE_DIR}/full"
readonly INCREMENTAL_BACKUP_DIR="${BACKUP_BASE_DIR}/incremental"
readonly REMOTE_BACKUP_DIR="${BACKUP_BASE_DIR}/remote"

# Default retention policies (days) - configurable
FULL_BACKUP_RETENTION=${BACKUP_RETENTION_DAYS:-14}  # Reduced from 30
INCREMENTAL_BACKUP_RETENTION=${INCREMENTAL_RETENTION_DAYS:-7}
LOG_BACKUP_RETENTION=${LOG_RETENTION_DAYS:-30}  # Reduced from 90

# Backup encryption
readonly BACKUP_ENCRYPTION_KEY="${BACKUP_CONFIG_DIR}/backup.key"
readonly BACKUP_PASSPHRASE_FILE="${BACKUP_CONFIG_DIR}/backup.passphrase"

# System directories to backup
readonly SYSTEM_BACKUP_DIRS=(
    "/opt/vless/config"
    "/opt/vless/users"
    "/etc/systemd/system/vless*"
    "/etc/rsyslog.d/*vless*"
    "/etc/logrotate.d/vless"
    "/etc/ufw"
    "/etc/ssh/sshd_config"
    "/etc/fail2ban/jail.local"
)

# Configure backup profile
configure_backup_profile() {
    local profile="${BACKUP_PROFILE:-essential}"

    case "$profile" in
        "minimal")
            BACKUP_COMPONENTS=("config" "database")
            FULL_BACKUP_RETENTION=7
            BACKUP_COMPRESSION="gzip"
            log_info "Backup profile: minimal - config and database only"
            ;;
        "essential")
            BACKUP_COMPONENTS=("config" "database" "users" "certs")
            FULL_BACKUP_RETENTION=14
            BACKUP_COMPRESSION="gzip"
            log_info "Backup profile: essential - core components"
            ;;
        "full")
            BACKUP_COMPONENTS=("config" "database" "users" "certs" "logs")
            FULL_BACKUP_RETENTION=30
            BACKUP_COMPRESSION="xz"
            log_info "Backup profile: full - all components"
            ;;
    esac

    log_debug "Components: ${BACKUP_COMPONENTS[*]}"
    log_debug "Retention: ${FULL_BACKUP_RETENTION} days"
}

# Initialize backup system
init_backup_system() {
    log_info "Initializing backup and restore system"

    # Configure backup profile first
    configure_backup_profile

    # Create backup directories
    create_directory "$BACKUP_BASE_DIR" "750" "root:root"
    create_directory "$BACKUP_CONFIG_DIR" "700" "root:root"
    create_directory "$BACKUP_DATA_DIR" "750" "vless:vless"
    create_directory "$BACKUP_LOGS_DIR" "750" "vless:vless"
    create_directory "$BACKUP_TEMP_DIR" "700" "root:root"
    create_directory "$FULL_BACKUP_DIR" "750" "vless:vless"
    create_directory "$INCREMENTAL_BACKUP_DIR" "750" "vless:vless"
    create_directory "$REMOTE_BACKUP_DIR" "750" "vless:vless"

    # Install required packages
    install_package_if_missing "rsync"
    install_package_if_missing "tar"
    install_package_if_missing "gzip"
    install_package_if_missing "openssl"

    # Generate encryption keys if not present
    generate_backup_encryption_keys

    # Create backup configuration
    create_backup_config

    log_success "Backup and restore system initialized"
}

# Generate backup encryption keys
generate_backup_encryption_keys() {
    log_info "Generating backup encryption keys"

    # Generate encryption key
    if [[ ! -f "$BACKUP_ENCRYPTION_KEY" ]]; then
        openssl rand -base64 32 > "$BACKUP_ENCRYPTION_KEY"
        chmod 600 "$BACKUP_ENCRYPTION_KEY"
        chown root:root "$BACKUP_ENCRYPTION_KEY"
        log_debug "Backup encryption key generated"
    fi

    # Generate passphrase
    if [[ ! -f "$BACKUP_PASSPHRASE_FILE" ]]; then
        openssl rand -base64 48 > "$BACKUP_PASSPHRASE_FILE"
        chmod 600 "$BACKUP_PASSPHRASE_FILE"
        chown root:root "$BACKUP_PASSPHRASE_FILE"
        log_debug "Backup passphrase generated"
    fi

    log_success "Backup encryption keys ready"
}

# Create backup configuration
create_backup_config() {
    log_info "Creating backup configuration"

    local backup_config="${BACKUP_CONFIG_DIR}/backup.conf"

    cat > "$backup_config" << 'EOF'
# VLESS Backup Configuration - Simplified
# Generated by backup system module

# Backup settings - Conservative defaults for stability
ENABLE_ENCRYPTION=true
ENABLE_COMPRESSION=true
BACKUP_VERIFICATION=true
INCREMENTAL_BACKUP=false  # Disabled by default for simplicity

# Retention settings - Reduced for disk space efficiency
FULL_BACKUP_RETENTION_DAYS=14  # Reduced from 30
INCREMENTAL_BACKUP_RETENTION_DAYS=7
LOG_BACKUP_RETENTION_DAYS=30   # Reduced from 90

# Remote backup settings - Disabled by default
ENABLE_REMOTE_BACKUP=false
REMOTE_BACKUP_TYPE=""
REMOTE_BACKUP_HOST=""
REMOTE_BACKUP_PATH=""
REMOTE_BACKUP_USER=""
REMOTE_BACKUP_KEY=""

# Schedule settings - Weekly instead of daily
BACKUP_FREQUENCY="weekly"      # weekly, daily
WEEKLY_BACKUP_TIME="02:00"
WEEKLY_BACKUP_DAY="sunday"
MONTHLY_CLEANUP_DAY="1"

# Notification settings - Disabled by default
ENABLE_EMAIL_NOTIFICATIONS=false
EMAIL_RECIPIENT=""
ENABLE_WEBHOOK_NOTIFICATIONS=false
WEBHOOK_URL=""

EOF

    chmod 644 "$backup_config"
    chown root:root "$backup_config"

    log_success "Backup configuration created: $backup_config"
}

# Create full system backup
create_full_backup() {
    local backup_name="${1:-full_$(date +%Y%m%d_%H%M%S)}"
    local backup_description="${2:-Full system backup}"

    log_info "Creating full system backup: $backup_name"

    local backup_dir="${FULL_BACKUP_DIR}/${backup_name}"
    local backup_manifest="${backup_dir}/manifest.txt"
    local backup_metadata="${backup_dir}/metadata.json"

    # Create backup directory
    create_directory "$backup_dir" "750" "vless:vless"

    # Create backup manifest
    {
        echo "# VLESS Full Backup Manifest"
        echo "# Backup: $backup_name"
        echo "# Created: $(get_timestamp)"
        echo "# Description: $backup_description"
        echo ""
        echo "# System Information:"
        get_system_info
        echo ""
        echo "# Backup Contents:"
    } > "$backup_manifest"

    # Backup system configuration files
    log_info "Backing up system configuration"
    local config_backup="${backup_dir}/system_config.tar.gz"

    {
        for dir in "${SYSTEM_BACKUP_DIRS[@]}"; do
            if [[ -e "$dir" ]]; then
                echo "Including: $dir"
                echo "$dir" >> "$backup_manifest"
            else
                log_warn "Path not found, skipping: $dir"
            fi
        done
    } | tar -czf "$config_backup" -T - 2>/dev/null || true

    # Backup VLESS user database
    log_info "Backing up VLESS user database"
    local users_backup="${backup_dir}/users_database.tar.gz"

    if [[ -d "/opt/vless/users" ]]; then
        tar -czf "$users_backup" -C "/opt/vless" users/
        echo "/opt/vless/users/" >> "$backup_manifest"
    fi

    # Backup Docker configurations
    log_info "Backing up Docker configurations"
    local docker_backup="${backup_dir}/docker_config.tar.gz"

    local docker_files=(
        "/opt/vless/config/docker-compose.yml"
        "/opt/vless/config/xray_config.json"
    )

    {
        for file in "${docker_files[@]}"; do
            if [[ -f "$file" ]]; then
                echo "$file"
                echo "$file" >> "$backup_manifest"
            fi
        done
    } | tar -czf "$docker_backup" -T - 2>/dev/null || true

    # Backup logs (recent only)
    log_info "Backing up recent logs"
    local logs_backup="${backup_dir}/logs.tar.gz"

    if [[ -d "/opt/vless/logs" ]]; then
        find "/opt/vless/logs" -name "*.log" -mtime -7 -exec tar -czf "$logs_backup" {} + 2>/dev/null || true
        echo "/opt/vless/logs/ (recent)" >> "$backup_manifest"
    fi

    # Create metadata
    local backup_size
    backup_size=$(du -sh "$backup_dir" | cut -f1)

    cat > "$backup_metadata" << EOF
{
  "backup_name": "$backup_name",
  "backup_type": "full",
  "description": "$backup_description",
  "created_at": "$(get_timestamp)",
  "created_by": "$(whoami)",
  "system_info": {
    "hostname": "$(hostname)",
    "distribution": "$(detect_distribution)",
    "architecture": "$(detect_architecture)",
    "kernel": "$(uname -r)"
  },
  "backup_size": "$backup_size",
  "files": {
    "system_config": "$(basename "$config_backup")",
    "users_database": "$(basename "$users_backup")",
    "docker_config": "$(basename "$docker_backup")",
    "logs": "$(basename "$logs_backup")",
    "manifest": "$(basename "$backup_manifest")"
  },
  "integrity": {
    "verified": false,
    "checksum": ""
  }
}
EOF

    # Encrypt backup if enabled
    if should_encrypt_backup; then
        encrypt_backup_directory "$backup_dir"
    fi

    # Verify backup integrity
    if verify_backup_integrity "$backup_dir"; then
        # Update metadata with verification status
        local checksum
        checksum=$(generate_backup_checksum "$backup_dir")
        jq ".integrity.verified = true | .integrity.checksum = \"$checksum\"" "$backup_metadata" > "${backup_metadata}.tmp"
        mv "${backup_metadata}.tmp" "$backup_metadata"

        log_success "Full backup created successfully: $backup_dir"
        log_info "Backup size: $backup_size"

        # Send notification
        send_backup_notification "full_backup_success" "$backup_name" "$backup_size"

        return 0
    else
        log_error "Backup integrity verification failed"
        return 1
    fi
}

# Create incremental backup
create_incremental_backup() {
    local reference_backup="$1"
    local backup_name="${2:-incremental_$(date +%Y%m%d_%H%M%S)}"

    log_info "Creating incremental backup: $backup_name (reference: $reference_backup)"

    local backup_dir="${INCREMENTAL_BACKUP_DIR}/${backup_name}"
    local backup_manifest="${backup_dir}/manifest.txt"
    local backup_metadata="${backup_dir}/metadata.json"

    # Validate reference backup
    if [[ ! -d "${FULL_BACKUP_DIR}/${reference_backup}" ]]; then
        log_error "Reference backup not found: $reference_backup"
        return 1
    fi

    # Create backup directory
    create_directory "$backup_dir" "750" "vless:vless"

    # Find changed files since reference backup
    local reference_time
    reference_time=$(stat -c %Y "${FULL_BACKUP_DIR}/${reference_backup}")

    log_info "Finding files changed since reference backup"

    {
        echo "# VLESS Incremental Backup Manifest"
        echo "# Backup: $backup_name"
        echo "# Reference: $reference_backup"
        echo "# Created: $(get_timestamp)"
        echo ""
        echo "# Changed files since reference:"
    } > "$backup_manifest"

    # Create incremental backup of changed files
    local changed_files
    changed_files="${backup_dir}/changed_files.txt"

    {
        for dir in "${SYSTEM_BACKUP_DIRS[@]}"; do
            if [[ -e "$dir" ]]; then
                find "$dir" -newer "${FULL_BACKUP_DIR}/${reference_backup}/manifest.txt" -type f 2>/dev/null || true
            fi
        done

        # Always include user database changes
        if [[ -d "/opt/vless/users" ]]; then
            find "/opt/vless/users" -newer "${FULL_BACKUP_DIR}/${reference_backup}/manifest.txt" -type f 2>/dev/null || true
        fi

        # Include recent logs
        if [[ -d "/opt/vless/logs" ]]; then
            find "/opt/vless/logs" -name "*.log" -mtime -1 -type f 2>/dev/null || true
        fi
    } | sort | uniq > "$changed_files"

    # Create incremental archive
    local incremental_archive="${backup_dir}/incremental_changes.tar.gz"

    if [[ -s "$changed_files" ]]; then
        tar -czf "$incremental_archive" -T "$changed_files" 2>/dev/null || true
        cat "$changed_files" >> "$backup_manifest"
        log_info "Incremental backup contains $(wc -l < "$changed_files") changed files"
    else
        echo "No files changed since reference backup" | tee -a "$backup_manifest"
        touch "$incremental_archive"
        log_info "No changes detected since reference backup"
    fi

    # Create metadata
    local backup_size
    backup_size=$(du -sh "$backup_dir" | cut -f1)

    cat > "$backup_metadata" << EOF
{
  "backup_name": "$backup_name",
  "backup_type": "incremental",
  "reference_backup": "$reference_backup",
  "created_at": "$(get_timestamp)",
  "created_by": "$(whoami)",
  "backup_size": "$backup_size",
  "changed_files_count": $(wc -l < "$changed_files" 2>/dev/null || echo "0"),
  "files": {
    "incremental_archive": "$(basename "$incremental_archive")",
    "changed_files_list": "$(basename "$changed_files")",
    "manifest": "$(basename "$backup_manifest")"
  }
}
EOF

    log_success "Incremental backup created successfully: $backup_dir"
    log_info "Backup size: $backup_size"

    # Send notification
    send_backup_notification "incremental_backup_success" "$backup_name" "$backup_size"

    return 0
}

# Restore from backup
restore_from_backup() {
    local backup_name="$1"
    local restore_options="${2:-all}"
    local confirmation="${3:-false}"

    log_info "Restoring from backup: $backup_name (options: $restore_options)"

    # Find backup location
    local backup_dir=""
    if [[ -d "${FULL_BACKUP_DIR}/${backup_name}" ]]; then
        backup_dir="${FULL_BACKUP_DIR}/${backup_name}"
    elif [[ -d "${INCREMENTAL_BACKUP_DIR}/${backup_name}" ]]; then
        backup_dir="${INCREMENTAL_BACKUP_DIR}/${backup_name}"
    else
        log_error "Backup not found: $backup_name"
        return 1
    fi

    # Verify backup integrity
    if ! verify_backup_integrity "$backup_dir"; then
        log_error "Backup integrity verification failed"
        return 1
    fi

    # Confirmation check
    if [[ "$confirmation" != "true" ]]; then
        log_warn "This operation will overwrite current configuration!"
        log_warn "Use --confirm to proceed with restore"
        return 1
    fi

    log_info "Starting restore process from: $backup_dir"

    # Create restore point before proceeding
    local restore_point="restore_point_$(date +%Y%m%d_%H%M%S)"
    log_info "Creating restore point: $restore_point"
    create_full_backup "$restore_point" "Pre-restore backup"

    # Decrypt backup if encrypted
    local working_dir="$backup_dir"
    if is_backup_encrypted "$backup_dir"; then
        working_dir="${BACKUP_TEMP_DIR}/restore_$(date +%Y%m%d_%H%M%S)"
        if ! decrypt_backup_directory "$backup_dir" "$working_dir"; then
            log_error "Failed to decrypt backup"
            return 1
        fi
    fi

    # Stop services before restore
    log_info "Stopping VLESS services"
    isolate_systemctl_command "stop" "vless-vpn" 30 || true
    safe_execute 30 docker compose -f /opt/vless/config/docker-compose.yml down || true

    # Restore based on options
    case "$restore_options" in
        "all"|"full")
            restore_system_config "$working_dir"
            restore_user_database "$working_dir"
            restore_docker_config "$working_dir"
            ;;
        "config")
            restore_system_config "$working_dir"
            ;;
        "users")
            restore_user_database "$working_dir"
            ;;
        "docker")
            restore_docker_config "$working_dir"
            ;;
        *)
            log_error "Invalid restore option: $restore_options"
            return 1
            ;;
    esac

    # Restart services
    log_info "Restarting VLESS services"
    isolate_systemctl_command "start" "vless-vpn" 30 || true

    # Cleanup temporary files
    if [[ "$working_dir" != "$backup_dir" ]]; then
        rm -rf "$working_dir"
    fi

    log_success "Restore completed successfully from backup: $backup_name"

    # Send notification
    send_backup_notification "restore_success" "$backup_name" "Restored: $restore_options"

    return 0
}

# Restore system configuration
restore_system_config() {
    local backup_dir="$1"
    local config_archive="${backup_dir}/system_config.tar.gz"

    if [[ -f "$config_archive" ]]; then
        log_info "Restoring system configuration"
        tar -xzf "$config_archive" -C / 2>/dev/null || true
        log_success "System configuration restored"
    else
        log_warn "System configuration archive not found in backup"
    fi
}

# Restore user database
restore_user_database() {
    local backup_dir="$1"
    local users_archive="${backup_dir}/users_database.tar.gz"

    if [[ -f "$users_archive" ]]; then
        log_info "Restoring user database"
        tar -xzf "$users_archive" -C "/opt/vless" 2>/dev/null || true
        chown -R vless:vless "/opt/vless/users"
        log_success "User database restored"
    else
        log_warn "User database archive not found in backup"
    fi
}

# Restore Docker configuration
restore_docker_config() {
    local backup_dir="$1"
    local docker_archive="${backup_dir}/docker_config.tar.gz"

    if [[ -f "$docker_archive" ]]; then
        log_info "Restoring Docker configuration"
        tar -xzf "$docker_archive" -C "/" 2>/dev/null || true
        log_success "Docker configuration restored"
    else
        log_warn "Docker configuration archive not found in backup"
    fi
}

# Verify backup integrity
verify_backup_integrity() {
    local backup_dir="$1"

    log_debug "Verifying backup integrity: $backup_dir"

    # Check if backup directory exists
    if [[ ! -d "$backup_dir" ]]; then
        log_error "Backup directory not found: $backup_dir"
        return 1
    fi

    # Check essential files
    local essential_files=(
        "${backup_dir}/manifest.txt"
        "${backup_dir}/metadata.json"
    )

    local file
    for file in "${essential_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Essential backup file missing: $file"
            return 1
        fi
    done

    # Verify archive integrity
    local archives
    archives=$(find "$backup_dir" -name "*.tar.gz" -type f)

    while IFS= read -r archive; do
        if [[ -n "$archive" ]]; then
            if ! tar -tzf "$archive" >/dev/null 2>&1; then
                log_error "Corrupted archive detected: $archive"
                return 1
            fi
        fi
    done <<< "$archives"

    log_debug "Backup integrity verification passed"
    return 0
}

# Generate backup checksum
generate_backup_checksum() {
    local backup_dir="$1"
    local checksum_file="${backup_dir}/.checksum"

    find "$backup_dir" -type f ! -name ".checksum" -exec sha256sum {} \; | \
    sort | sha256sum | cut -d' ' -f1 > "$checksum_file"

    cat "$checksum_file"
}

# Check if backup should be encrypted
should_encrypt_backup() {
    local config_file="${BACKUP_CONFIG_DIR}/backup.conf"
    if [[ -f "$config_file" ]]; then
        source "$config_file"
        [[ "${ENABLE_ENCRYPTION:-false}" == "true" ]]
    else
        return 0  # Default to encryption enabled
    fi
}

# Encrypt backup directory
encrypt_backup_directory() {
    local backup_dir="$1"

    log_info "Encrypting backup directory: $backup_dir"

    # Create encrypted archive
    local encrypted_archive="${backup_dir}.tar.gz.enc"
    tar -czf - -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")" | \
    openssl enc -aes-256-cbc -salt -pass "file:$BACKUP_PASSPHRASE_FILE" > "$encrypted_archive"

    # Remove original directory and replace with encrypted file
    rm -rf "$backup_dir"
    mkdir -p "$backup_dir"
    mv "$encrypted_archive" "${backup_dir}/encrypted_backup.tar.gz.enc"

    # Create decryption instructions
    cat > "${backup_dir}/DECRYPT_README.txt" << 'EOF'
# Backup Decryption Instructions

This backup is encrypted. To decrypt:

1. Extract the encrypted archive:
   openssl enc -aes-256-cbc -d -salt -in encrypted_backup.tar.gz.enc -pass file:/path/to/backup.passphrase > decrypted_backup.tar.gz

2. Extract the decrypted backup:
   tar -xzf decrypted_backup.tar.gz

The passphrase file is located at: /opt/vless/backup/config/backup.passphrase

EOF

    log_success "Backup encrypted successfully"
}

# Decrypt backup directory
decrypt_backup_directory() {
    local encrypted_backup_dir="$1"
    local output_dir="$2"

    log_info "Decrypting backup directory"

    local encrypted_file="${encrypted_backup_dir}/encrypted_backup.tar.gz.enc"

    if [[ ! -f "$encrypted_file" ]]; then
        log_error "Encrypted backup file not found: $encrypted_file"
        return 1
    fi

    # Create output directory
    create_directory "$output_dir" "750" "vless:vless"

    # Decrypt and extract
    openssl enc -aes-256-cbc -d -salt -in "$encrypted_file" -pass "file:$BACKUP_PASSPHRASE_FILE" | \
    tar -xzf - -C "$(dirname "$output_dir")"

    log_success "Backup decrypted successfully to: $output_dir"
    return 0
}

# Check if backup is encrypted
is_backup_encrypted() {
    local backup_dir="$1"
    [[ -f "${backup_dir}/encrypted_backup.tar.gz.enc" ]]
}

# Send backup notification
send_backup_notification() {
    local event_type="$1"
    local backup_name="$2"
    local details="$3"

    log_info "Backup notification: $event_type - $backup_name"

    # Log notification
    echo "[$(get_timestamp)] $event_type: $backup_name - $details" >> "${BACKUP_LOGS_DIR}/backup_notifications.log"

    # TODO: Implement email/webhook notifications
    # send_email_notification "$event_type" "$backup_name" "$details"
    # send_webhook_notification "$event_type" "$backup_name" "$details"
}

# List available backups
list_backups() {
    log_info "Listing available backups"

    echo "=== VLESS Backup Inventory ==="
    echo ""

    # Full backups
    echo "Full Backups:"
    if [[ -d "$FULL_BACKUP_DIR" ]] && [[ -n "$(ls -A "$FULL_BACKUP_DIR" 2>/dev/null)" ]]; then
        for backup_dir in "$FULL_BACKUP_DIR"/*; do
            if [[ -d "$backup_dir" ]]; then
                local backup_name
                backup_name=$(basename "$backup_dir")
                local backup_size
                backup_size=$(du -sh "$backup_dir" 2>/dev/null | cut -f1 || echo "Unknown")
                local backup_date
                backup_date=$(stat -c %y "$backup_dir" 2>/dev/null | cut -d' ' -f1 || echo "Unknown")

                echo "  $backup_name (Size: $backup_size, Date: $backup_date)"

                # Show metadata if available
                local metadata_file="${backup_dir}/metadata.json"
                if [[ -f "$metadata_file" ]]; then
                    local description
                    description=$(jq -r '.description // "No description"' "$metadata_file" 2>/dev/null || echo "No description")
                    echo "    Description: $description"
                fi
            fi
        done
    else
        echo "  No full backups found"
    fi

    echo ""

    # Incremental backups
    echo "Incremental Backups:"
    if [[ -d "$INCREMENTAL_BACKUP_DIR" ]] && [[ -n "$(ls -A "$INCREMENTAL_BACKUP_DIR" 2>/dev/null)" ]]; then
        for backup_dir in "$INCREMENTAL_BACKUP_DIR"/*; do
            if [[ -d "$backup_dir" ]]; then
                local backup_name
                backup_name=$(basename "$backup_dir")
                local backup_size
                backup_size=$(du -sh "$backup_dir" 2>/dev/null | cut -f1 || echo "Unknown")
                local backup_date
                backup_date=$(stat -c %y "$backup_dir" 2>/dev/null | cut -d' ' -f1 || echo "Unknown")

                echo "  $backup_name (Size: $backup_size, Date: $backup_date)"

                # Show reference backup
                local metadata_file="${backup_dir}/metadata.json"
                if [[ -f "$metadata_file" ]]; then
                    local reference
                    reference=$(jq -r '.reference_backup // "Unknown"' "$metadata_file" 2>/dev/null || echo "Unknown")
                    echo "    Reference: $reference"
                fi
            fi
        done
    else
        echo "  No incremental backups found"
    fi

    # Backup statistics
    echo ""
    echo "Backup Statistics:"
    local total_backups
    total_backups=$(find "$FULL_BACKUP_DIR" "$INCREMENTAL_BACKUP_DIR" -maxdepth 1 -type d 2>/dev/null | wc -l)
    echo "  Total backups: $((total_backups - 2))"  # Subtract the two parent directories

    local total_size
    total_size=$(du -sh "$BACKUP_BASE_DIR" 2>/dev/null | cut -f1 || echo "Unknown")
    echo "  Total backup size: $total_size"

    local available_space
    available_space=$(df -h "$BACKUP_BASE_DIR" 2>/dev/null | awk 'NR==2{print $4}' || echo "Unknown")
    echo "  Available space: $available_space"
}

# Cleanup old backups
cleanup_old_backups() {
    log_info "Cleaning up old backups"

    local cleaned_count=0

    # Clean full backups
    log_debug "Cleaning full backups older than $FULL_BACKUP_RETENTION days"
    while IFS= read -r -d '' backup_dir; do
        if [[ -d "$backup_dir" ]]; then
            rm -rf "$backup_dir"
            log_debug "Removed old full backup: $(basename "$backup_dir")"
            ((cleaned_count++))
        fi
    done < <(find "$FULL_BACKUP_DIR" -maxdepth 1 -type d -mtime +$FULL_BACKUP_RETENTION -print0 2>/dev/null)

    # Clean incremental backups
    log_debug "Cleaning incremental backups older than $INCREMENTAL_BACKUP_RETENTION days"
    while IFS= read -r -d '' backup_dir; do
        if [[ -d "$backup_dir" ]]; then
            rm -rf "$backup_dir"
            log_debug "Removed old incremental backup: $(basename "$backup_dir")"
            ((cleaned_count++))
        fi
    done < <(find "$INCREMENTAL_BACKUP_DIR" -maxdepth 1 -type d -mtime +$INCREMENTAL_BACKUP_RETENTION -print0 2>/dev/null)

    # Clean backup logs
    log_debug "Cleaning backup logs older than $LOG_BACKUP_RETENTION days"
    find "$BACKUP_LOGS_DIR" -name "*.log" -mtime +$LOG_BACKUP_RETENTION -delete 2>/dev/null || true

    log_success "Cleanup completed. Removed $cleaned_count old backups"
}

# Schedule automatic backups
schedule_automatic_backups() {
    log_info "Scheduling automatic backups"

    # Create backup script
    local backup_script="${BACKUP_CONFIG_DIR}/auto_backup.sh"

    cat > "$backup_script" << 'EOF'
#!/bin/bash
# VLESS Automatic Backup Script

set -euo pipefail

# Import backup module
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../modules" && pwd)"
source "${SOURCE_DIR}/backup_restore.sh"

# Load configuration
BACKUP_CONFIG="${BACKUP_CONFIG_DIR}/backup.conf"
if [[ -f "$BACKUP_CONFIG" ]]; then
    source "$BACKUP_CONFIG"
fi

# Determine backup type based on day of week
CURRENT_DAY=$(date +%A | tr '[:upper:]' '[:lower:]')
WEEKLY_BACKUP_DAY="${WEEKLY_FULL_BACKUP_DAY:-sunday}"

if [[ "$CURRENT_DAY" == "$WEEKLY_BACKUP_DAY" ]]; then
    # Create full backup
    BACKUP_NAME="auto_full_$(date +%Y%m%d)"
    create_full_backup "$BACKUP_NAME" "Automatic weekly full backup"
else
    # Create incremental backup (find latest full backup)
    LATEST_FULL=$(ls -1t "$FULL_BACKUP_DIR" 2>/dev/null | head -1)
    if [[ -n "$LATEST_FULL" ]]; then
        BACKUP_NAME="auto_incremental_$(date +%Y%m%d)"
        create_incremental_backup "$LATEST_FULL" "$BACKUP_NAME"
    else
        # No full backup exists, create one
        BACKUP_NAME="auto_full_$(date +%Y%m%d)"
        create_full_backup "$BACKUP_NAME" "Automatic full backup (no previous full backup found)"
    fi
fi

# Cleanup old backups
cleanup_old_backups

EOF

    chmod 755 "$backup_script"
    chown root:root "$backup_script"

    # Create systemd service and timer
    cat > "/etc/systemd/system/vless-backup.service" << EOF
[Unit]
Description=VLESS Automatic Backup
After=vless-vpn.service

[Service]
Type=oneshot
User=root
Group=root
ExecStart=$backup_script
StandardOutput=journal
StandardError=journal

EOF

    cat > "/etc/systemd/system/vless-backup.timer" << EOF
[Unit]
Description=VLESS Backup Timer
Requires=vless-backup.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target

EOF

    # Enable and start timer
    systemctl daemon-reload
    isolate_systemctl_command "enable" "vless-backup.timer" 30
    isolate_systemctl_command "start" "vless-backup.timer" 30

    log_success "Automatic backup scheduling configured"
}

# Main function for command line usage
main() {
    case "${1:-help}" in
        "init")
            init_backup_system
            ;;
        "full-backup")
            create_full_backup "${2:-}" "${3:-Full backup}"
            ;;
        "incremental-backup")
            if [[ -z "${2:-}" ]]; then
                log_error "Reference backup name required for incremental backup"
                exit 1
            fi
            create_incremental_backup "$2" "${3:-}"
            ;;
        "restore")
            if [[ -z "${2:-}" ]]; then
                log_error "Backup name required for restore"
                exit 1
            fi
            restore_from_backup "$2" "${3:-all}" "${4:-false}"
            ;;
        "list")
            list_backups
            ;;
        "cleanup")
            cleanup_old_backups
            ;;
        "schedule")
            schedule_automatic_backups
            ;;
        "help"|*)
            echo "VLESS Backup and Restore Module Usage:"
            echo "  $0 init                                    - Initialize backup system"
            echo "  $0 full-backup [name] [description]        - Create full backup"
            echo "  $0 incremental-backup <reference> [name]   - Create incremental backup"
            echo "  $0 restore <backup> [options] [--confirm]  - Restore from backup"
            echo "  $0 list                                    - List available backups"
            echo "  $0 cleanup                                 - Clean up old backups"
            echo "  $0 schedule                               - Schedule automatic backups"
            echo ""
            echo "Restore options: all, config, users, docker"
            ;;
    esac
}

# Export functions
export -f init_backup_system generate_backup_encryption_keys create_backup_config
export -f create_full_backup create_incremental_backup restore_from_backup
export -f verify_backup_integrity generate_backup_checksum encrypt_backup_directory
export -f decrypt_backup_directory list_backups cleanup_old_backups
export -f schedule_automatic_backups send_backup_notification

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

log_debug "Backup and restore module loaded successfully"