#!/bin/bash
# Backup and Restore Module for VLESS VPN Project
# Comprehensive backup system with incremental support and integrity checking
# Compatible with Ubuntu 20.04+ and Debian 11+
# Author: Claude Code
# Version: 1.0

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(dirname "$SCRIPT_DIR")"

# Import process isolation module
source "${SCRIPT_DIR}/process_isolation/process_safe.sh" 2>/dev/null || {
    echo "ERROR: Cannot load process isolation module" >&2
    exit 1
}

# Setup signal handlers
setup_signal_handlers

# Configuration
readonly LOG_DIR="/opt/vless/logs"
readonly LOG_FILE="${LOG_DIR}/backup_restore.log"
readonly BACKUP_DIR="/opt/vless/backups"
readonly VLESS_CONFIG_DIR="/opt/vless"
readonly PROJECT_DIR="${SOURCE_DIR}"
readonly BACKUP_TIMEOUT=3600  # 1 hour for backup operations
readonly RESTORE_TIMEOUT=1800 # 30 minutes for restore operations
readonly MAX_BACKUP_AGE_DAYS=30
readonly INCREMENTAL_BASE_AGE_DAYS=7

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m'

# Logging functions
log_to_file() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$LOG_FILE"
}

log_info() {
    local message="$1"
    echo -e "${GREEN}[INFO]${NC} $message"
    log_to_file "INFO: $message"
}

log_warning() {
    local message="$1"
    echo -e "${YELLOW}[WARNING]${NC} $message"
    log_to_file "WARNING: $message"
}

log_error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC} $message"
    log_to_file "ERROR: $message"
}

log_debug() {
    local message="$1"
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $message"
    fi
    log_to_file "DEBUG: $message"
}

log_success() {
    local message="$1"
    echo -e "${GREEN}✓${NC} $message"
    log_to_file "SUCCESS: $message"
}

# Initialize logging and backup directory
init_backup_system() {
    if [[ ! -d "$LOG_DIR" ]]; then
        sudo mkdir -p "$LOG_DIR"
        sudo chown "$USER:$USER" "$LOG_DIR"
        sudo chmod 755 "$LOG_DIR"
    fi

    if [[ ! -f "$LOG_FILE" ]]; then
        touch "$LOG_FILE"
        chmod 644 "$LOG_FILE"
    fi

    if [[ ! -d "$BACKUP_DIR" ]]; then
        sudo mkdir -p "$BACKUP_DIR"
        sudo chown "$USER:$USER" "$BACKUP_DIR"
        sudo chmod 755 "$BACKUP_DIR"
    fi

    log_info "Backup and restore module initialized"
}

# Generate backup filename with timestamp
generate_backup_filename() {
    local backup_type="$1"  # full, incremental, config, user, etc.
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local hostname=$(hostname -s)

    echo "${BACKUP_DIR}/vless_${backup_type}_${hostname}_${timestamp}.tar.gz"
}

# Get list of paths to backup
get_backup_paths() {
    local backup_type="$1"

    local paths=()

    case "$backup_type" in
        "full")
            paths+=(
                "$VLESS_CONFIG_DIR/configs"
                "$VLESS_CONFIG_DIR/certs"
                "$VLESS_CONFIG_DIR/users"
                "$PROJECT_DIR/config"
                "$PROJECT_DIR/modules"
                "/etc/systemd/system/vless-vpn.service"
                "/etc/ufw"
                "/etc/docker/daemon.json"
            )
            ;;
        "config")
            paths+=(
                "$VLESS_CONFIG_DIR/configs"
                "$PROJECT_DIR/config"
                "/etc/systemd/system/vless-vpn.service"
            )
            ;;
        "users")
            paths+=(
                "$VLESS_CONFIG_DIR/users"
            )
            ;;
        "certs")
            paths+=(
                "$VLESS_CONFIG_DIR/certs"
            )
            ;;
        "system")
            paths+=(
                "/etc/ufw"
                "/etc/docker/daemon.json"
                "/etc/systemd/system/vless-vpn.service"
            )
            ;;
        *)
            log_error "Unknown backup type: $backup_type"
            return 1
            ;;
    esac

    # Filter out non-existent paths
    local existing_paths=()
    for path in "${paths[@]}"; do
        if [[ -e "$path" ]]; then
            existing_paths+=("$path")
        else
            log_debug "Path does not exist, skipping: $path"
        fi
    done

    printf '%s\n' "${existing_paths[@]}"
}

# Calculate directory size
calculate_backup_size() {
    local paths=("$@")
    local total_size=0

    for path in "${paths[@]}"; do
        if [[ -e "$path" ]]; then
            local size=$(du -sb "$path" 2>/dev/null | cut -f1 || echo "0")
            total_size=$((total_size + size))
        fi
    done

    echo "$total_size"
}

# Format size in human readable format
format_size() {
    local size="$1"
    local units=("B" "KB" "MB" "GB" "TB")
    local unit=0

    while [[ $size -gt 1024 ]] && [[ $unit -lt ${#units[@]} ]]; do
        size=$((size / 1024))
        unit=$((unit + 1))
    done

    echo "${size}${units[$unit]}"
}

# Check available disk space
check_disk_space() {
    local required_size="$1"
    local target_dir="$2"

    local available_space=$(df "$target_dir" | awk 'NR==2 {print $4 * 1024}')

    if [[ "$available_space" -lt "$required_size" ]]; then
        log_error "Insufficient disk space. Required: $(format_size $required_size), Available: $(format_size $available_space)"
        return 1
    else
        log_info "Disk space check passed. Required: $(format_size $required_size), Available: $(format_size $available_space)"
        return 0
    fi
}

# Create backup manifest
create_backup_manifest() {
    local backup_file="$1"
    local backup_type="$2"
    local manifest_file="${backup_file%.tar.gz}.manifest"

    log_info "Creating backup manifest: $manifest_file"

    cat > "$manifest_file" <<EOF
{
    "backup_file": "$(basename "$backup_file")",
    "backup_type": "$backup_type",
    "timestamp": "$(date -Iseconds)",
    "hostname": "$(hostname -f)",
    "creator": "$USER",
    "vless_version": "1.0",
    "system_info": {
        "os": "$(lsb_release -d | cut -f2 2>/dev/null || echo 'Unknown')",
        "kernel": "$(uname -r)",
        "architecture": "$(uname -m)"
    },
    "file_info": {
        "size": $(stat -c%s "$backup_file" 2>/dev/null || echo "0"),
        "md5sum": "$(md5sum "$backup_file" | cut -d' ' -f1 2>/dev/null || echo 'unknown')",
        "sha256sum": "$(sha256sum "$backup_file" | cut -d' ' -f1 2>/dev/null || echo 'unknown')"
    }
}
EOF

    log_success "Backup manifest created"
    return 0
}

# Verify backup integrity
verify_backup_integrity() {
    local backup_file="$1"
    local manifest_file="${backup_file%.tar.gz}.manifest"

    log_info "Verifying backup integrity: $(basename "$backup_file")"

    # Check if backup file exists
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi

    # Check if manifest exists
    if [[ ! -f "$manifest_file" ]]; then
        log_warning "Manifest file not found, skipping checksum verification"

        # Basic archive integrity check
        if tar -tzf "$backup_file" >/dev/null 2>&1; then
            log_success "Basic archive integrity check passed"
            return 0
        else
            log_error "Archive integrity check failed"
            return 1
        fi
    fi

    # Extract checksums from manifest
    local expected_md5=$(grep '"md5sum"' "$manifest_file" | cut -d'"' -f4)
    local expected_sha256=$(grep '"sha256sum"' "$manifest_file" | cut -d'"' -f4)

    # Verify MD5
    if [[ "$expected_md5" != "unknown" ]]; then
        local actual_md5=$(md5sum "$backup_file" | cut -d' ' -f1)
        if [[ "$actual_md5" == "$expected_md5" ]]; then
            log_success "MD5 checksum verification passed"
        else
            log_error "MD5 checksum mismatch. Expected: $expected_md5, Actual: $actual_md5"
            return 1
        fi
    fi

    # Verify SHA256
    if [[ "$expected_sha256" != "unknown" ]]; then
        local actual_sha256=$(sha256sum "$backup_file" | cut -d' ' -f1)
        if [[ "$actual_sha256" == "$expected_sha256" ]]; then
            log_success "SHA256 checksum verification passed"
        else
            log_error "SHA256 checksum mismatch. Expected: $expected_sha256, Actual: $actual_sha256"
            return 1
        fi
    fi

    # Archive integrity check
    if tar -tzf "$backup_file" >/dev/null 2>&1; then
        log_success "Archive integrity verification passed"
        return 0
    else
        log_error "Archive integrity verification failed"
        return 1
    fi
}

# Create full backup
create_full_backup() {
    local description="${1:-Full system backup}"

    log_info "Creating full backup: $description"

    # Initialize backup system
    init_backup_system

    # Get backup paths
    local backup_paths
    if ! backup_paths=($(get_backup_paths "full")); then
        log_error "Failed to get backup paths"
        return 1
    fi

    if [[ ${#backup_paths[@]} -eq 0 ]]; then
        log_error "No paths found to backup"
        return 1
    fi

    # Calculate backup size
    local estimated_size=$(calculate_backup_size "${backup_paths[@]}")
    log_info "Estimated backup size: $(format_size $estimated_size)"

    # Check disk space (with 20% margin)
    local required_space=$((estimated_size * 120 / 100))
    if ! check_disk_space "$required_space" "$BACKUP_DIR"; then
        return 1
    fi

    # Generate backup filename
    local backup_file
    backup_file=$(generate_backup_filename "full")

    # Create tar command
    local tar_cmd="tar -czf '$backup_file' --exclude='*.log' --exclude='*.tmp'"
    for path in "${backup_paths[@]}"; do
        tar_cmd+=" '$path'"
    done

    # Execute backup
    log_info "Starting backup creation..."
    if safe_execute "$tar_cmd" "$BACKUP_TIMEOUT" "Full backup creation"; then
        log_success "Backup created: $(basename "$backup_file")"

        # Create manifest
        create_backup_manifest "$backup_file" "full"

        # Verify backup
        if verify_backup_integrity "$backup_file"; then
            log_success "Full backup completed successfully: $(basename "$backup_file")"
            echo "$backup_file"
            return 0
        else
            log_error "Backup verification failed"
            return 1
        fi
    else
        log_error "Backup creation failed"
        return 1
    fi
}

# Create incremental backup
create_incremental_backup() {
    local base_backup="$1"
    local description="${2:-Incremental backup}"

    log_info "Creating incremental backup: $description"

    if [[ ! -f "$base_backup" ]]; then
        log_error "Base backup file not found: $base_backup"
        return 1
    fi

    # Extract base backup timestamp for comparison
    local base_timestamp=$(stat -c %Y "$base_backup")

    # Get backup paths
    local backup_paths
    if ! backup_paths=($(get_backup_paths "full")); then
        log_error "Failed to get backup paths"
        return 1
    fi

    # Generate incremental backup filename
    local backup_file
    backup_file=$(generate_backup_filename "incremental")

    # Create tar command with newer files only
    local tar_cmd="tar -czf '$backup_file' --exclude='*.log' --exclude='*.tmp' --newer-mtime='@$base_timestamp'"
    for path in "${backup_paths[@]}"; do
        tar_cmd+=" '$path'"
    done

    # Execute incremental backup
    log_info "Starting incremental backup creation..."
    if safe_execute "$tar_cmd" "$BACKUP_TIMEOUT" "Incremental backup creation"; then
        log_success "Incremental backup created: $(basename "$backup_file")"

        # Create manifest
        create_backup_manifest "$backup_file" "incremental"

        # Verify backup
        if verify_backup_integrity "$backup_file"; then
            log_success "Incremental backup completed successfully: $(basename "$backup_file")"
            echo "$backup_file"
            return 0
        else
            log_error "Incremental backup verification failed"
            return 1
        fi
    else
        log_error "Incremental backup creation failed"
        return 1
    fi
}

# Create specific type backup
create_specific_backup() {
    local backup_type="$1"  # config, users, certs, system
    local description="${2:-${backup_type^} backup}"

    log_info "Creating $backup_type backup: $description"

    # Initialize backup system
    init_backup_system

    # Get backup paths
    local backup_paths
    if ! backup_paths=($(get_backup_paths "$backup_type")); then
        log_error "Failed to get backup paths for type: $backup_type"
        return 1
    fi

    if [[ ${#backup_paths[@]} -eq 0 ]]; then
        log_warning "No paths found to backup for type: $backup_type"
        return 0
    fi

    # Generate backup filename
    local backup_file
    backup_file=$(generate_backup_filename "$backup_type")

    # Create tar command
    local tar_cmd="tar -czf '$backup_file' --exclude='*.log' --exclude='*.tmp'"
    for path in "${backup_paths[@]}"; do
        tar_cmd+=" '$path'"
    done

    # Execute backup
    log_info "Starting $backup_type backup creation..."
    if safe_execute "$tar_cmd" "$BACKUP_TIMEOUT" "${backup_type^} backup creation"; then
        log_success "$backup_type backup created: $(basename "$backup_file")"

        # Create manifest
        create_backup_manifest "$backup_file" "$backup_type"

        # Verify backup
        if verify_backup_integrity "$backup_file"; then
            log_success "$backup_type backup completed successfully: $(basename "$backup_file")"
            echo "$backup_file"
            return 0
        else
            log_error "$backup_type backup verification failed"
            return 1
        fi
    else
        log_error "$backup_type backup creation failed"
        return 1
    fi
}

# List available backups
list_backups() {
    log_info "Available backups in $BACKUP_DIR:"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    printf "%-40s %-12s %-12s %-20s\n" "Backup File" "Type" "Size" "Date"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"

    local backup_count=0
    while IFS= read -r -d '' backup_file; do
        local basename_file=$(basename "$backup_file")
        local file_size=$(stat -c%s "$backup_file" 2>/dev/null || echo "0")
        local formatted_size=$(format_size "$file_size")
        local file_date=$(stat -c%y "$backup_file" 2>/dev/null | cut -d' ' -f1 || echo "unknown")

        # Extract backup type from filename
        local backup_type="unknown"
        if [[ "$basename_file" =~ vless_([^_]+)_ ]]; then
            backup_type="${BASH_REMATCH[1]}"
        fi

        printf "%-40s %-12s %-12s %-20s\n" "$basename_file" "$backup_type" "$formatted_size" "$file_date"

        # Check if manifest exists and is valid
        local manifest_file="${backup_file%.tar.gz}.manifest"
        if [[ -f "$manifest_file" ]]; then
            echo -e "${CYAN}  ✓ Manifest available${NC}"
        else
            echo -e "${YELLOW}  ⚠ No manifest${NC}"
        fi

        backup_count=$((backup_count + 1))
    done < <(find "$BACKUP_DIR" -name "vless_*.tar.gz" -type f -print0 2>/dev/null | sort -z)

    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    log_info "Total backups found: $backup_count"
}

# Restore from backup
restore_from_backup() {
    local backup_file="$1"
    local target_dir="${2:-/}"
    local verify_first="${3:-true}"

    log_info "Starting restore from backup: $(basename "$backup_file")"

    # Check if backup file exists
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi

    # Verify backup integrity first
    if [[ "$verify_first" == "true" ]]; then
        if ! verify_backup_integrity "$backup_file"; then
            log_error "Backup integrity verification failed. Restore aborted."
            return 1
        fi
    fi

    # Warning about destructive operation
    log_warning "This operation will overwrite existing files in $target_dir"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Restore operation cancelled by user"
        return 1
    fi

    # Create restore command
    local restore_cmd="tar -xzf '$backup_file' -C '$target_dir' --overwrite"

    # Execute restore
    log_info "Starting restore operation..."
    if safe_execute "$restore_cmd" "$RESTORE_TIMEOUT" "Backup restore"; then
        log_success "Restore completed successfully"

        # Restart services if needed
        log_info "Checking if services need to be restarted..."
        if systemctl is-active --quiet docker; then
            log_info "Restarting Docker service..."
            isolate_systemctl_command "restart" "docker" 60
        fi

        if systemctl is-active --quiet vless-vpn 2>/dev/null; then
            log_info "Restarting VLESS VPN service..."
            isolate_systemctl_command "restart" "vless-vpn" 60
        fi

        log_success "Restore from backup completed successfully"
        return 0
    else
        log_error "Restore operation failed"
        return 1
    fi
}

# Clean old backups
cleanup_old_backups() {
    local max_age_days="${1:-$MAX_BACKUP_AGE_DAYS}"
    local dry_run="${2:-false}"

    log_info "Cleaning up backups older than $max_age_days days"

    local deleted_count=0
    local total_size_freed=0

    while IFS= read -r -d '' backup_file; do
        local file_age_days=$((($(date +%s) - $(stat -c %Y "$backup_file")) / 86400))

        if [[ $file_age_days -gt $max_age_days ]]; then
            local file_size=$(stat -c%s "$backup_file" 2>/dev/null || echo "0")
            local manifest_file="${backup_file%.tar.gz}.manifest"

            if [[ "$dry_run" == "true" ]]; then
                log_info "Would delete: $(basename "$backup_file") (age: ${file_age_days} days, size: $(format_size $file_size))"
            else
                log_info "Deleting old backup: $(basename "$backup_file") (age: ${file_age_days} days)"
                rm -f "$backup_file"
                [[ -f "$manifest_file" ]] && rm -f "$manifest_file"
            fi

            deleted_count=$((deleted_count + 1))
            total_size_freed=$((total_size_freed + file_size))
        fi
    done < <(find "$BACKUP_DIR" -name "vless_*.tar.gz" -type f -print0 2>/dev/null)

    if [[ "$dry_run" == "true" ]]; then
        log_info "Dry run completed. Would delete $deleted_count backups, freeing $(format_size $total_size_freed)"
    else
        log_success "Cleanup completed. Deleted $deleted_count backups, freed $(format_size $total_size_freed)"
    fi

    return 0
}

# Automated backup function
automated_backup() {
    local backup_type="${1:-smart}"  # smart, full, incremental

    log_info "Starting automated backup (type: $backup_type)"

    case "$backup_type" in
        "smart")
            # Check if we have recent full backup
            local latest_full_backup=$(find "$BACKUP_DIR" -name "vless_full_*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2- || echo "")

            if [[ -n "$latest_full_backup" ]]; then
                local full_backup_age_days=$((($(date +%s) - $(stat -c %Y "$latest_full_backup")) / 86400))

                if [[ $full_backup_age_days -gt $INCREMENTAL_BASE_AGE_DAYS ]]; then
                    log_info "Latest full backup is $full_backup_age_days days old, creating new full backup"
                    create_full_backup "Automated full backup"
                else
                    log_info "Creating incremental backup based on recent full backup"
                    create_incremental_backup "$latest_full_backup" "Automated incremental backup"
                fi
            else
                log_info "No full backup found, creating initial full backup"
                create_full_backup "Initial automated full backup"
            fi
            ;;
        "full")
            create_full_backup "Automated full backup"
            ;;
        "incremental")
            local latest_full_backup=$(find "$BACKUP_DIR" -name "vless_full_*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2- || echo "")
            if [[ -n "$latest_full_backup" ]]; then
                create_incremental_backup "$latest_full_backup" "Automated incremental backup"
            else
                log_error "No full backup found for incremental backup"
                return 1
            fi
            ;;
        *)
            log_error "Unknown automated backup type: $backup_type"
            return 1
            ;;
    esac

    # Cleanup old backups
    cleanup_old_backups "$MAX_BACKUP_AGE_DAYS" "false"

    log_success "Automated backup completed"
    return 0
}

# Interactive backup and restore menu
interactive_backup_menu() {
    echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     Backup & Restore Manager         ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
    echo

    while true; do
        echo "Available options:"
        echo "1) Create full backup"
        echo "2) Create incremental backup"
        echo "3) Create configuration backup"
        echo "4) Create users backup"
        echo "5) Create certificates backup"
        echo "6) List available backups"
        echo "7) Restore from backup"
        echo "8) Verify backup integrity"
        echo "9) Cleanup old backups"
        echo "10) Automated backup"
        echo "11) Exit"
        echo

        read -p "Please select an option (1-11): " choice

        case $choice in
            1)
                echo -e "\n${GREEN}Creating full backup...${NC}"
                create_full_backup
                echo
                ;;
            2)
                echo -e "\n${CYAN}Select base backup for incremental:${NC}"
                list_backups
                echo
                read -p "Enter full backup filename: " base_backup
                if [[ -n "$base_backup" ]]; then
                    create_incremental_backup "${BACKUP_DIR}/${base_backup}"
                fi
                echo
                ;;
            3)
                echo -e "\n${GREEN}Creating configuration backup...${NC}"
                create_specific_backup "config"
                echo
                ;;
            4)
                echo -e "\n${GREEN}Creating users backup...${NC}"
                create_specific_backup "users"
                echo
                ;;
            5)
                echo -e "\n${GREEN}Creating certificates backup...${NC}"
                create_specific_backup "certs"
                echo
                ;;
            6)
                echo -e "\n${CYAN}Available backups:${NC}"
                list_backups
                echo
                ;;
            7)
                echo -e "\n${CYAN}Available backups:${NC}"
                list_backups
                echo
                read -p "Enter backup filename to restore: " backup_filename
                if [[ -n "$backup_filename" ]]; then
                    restore_from_backup "${BACKUP_DIR}/${backup_filename}"
                fi
                echo
                ;;
            8)
                echo -e "\n${CYAN}Available backups:${NC}"
                list_backups
                echo
                read -p "Enter backup filename to verify: " backup_filename
                if [[ -n "$backup_filename" ]]; then
                    verify_backup_integrity "${BACKUP_DIR}/${backup_filename}"
                fi
                echo
                ;;
            9)
                echo -e "\n${YELLOW}Cleanup old backups${NC}"
                read -p "Maximum age in days (default: $MAX_BACKUP_AGE_DAYS): " max_age
                max_age=${max_age:-$MAX_BACKUP_AGE_DAYS}
                read -p "Dry run first? (Y/n): " -n 1 -r dry_run
                echo
                [[ ! $dry_run =~ ^[Nn]$ ]] && dry_run="true" || dry_run="false"
                cleanup_old_backups "$max_age" "$dry_run"
                echo
                ;;
            10)
                echo -e "\n${GREEN}Automated backup options:${NC}"
                echo "1) Smart backup (full if old, incremental if recent)"
                echo "2) Force full backup"
                echo "3) Force incremental backup"
                read -p "Select backup type (1-3): " backup_type_choice
                case $backup_type_choice in
                    1) automated_backup "smart" ;;
                    2) automated_backup "full" ;;
                    3) automated_backup "incremental" ;;
                    *) log_error "Invalid backup type" ;;
                esac
                echo
                ;;
            11)
                echo "Exiting backup manager."
                break
                ;;
            *)
                echo -e "${RED}Invalid option. Please select 1-11.${NC}"
                ;;
        esac
    done
}

# Export functions for use by other modules
export -f create_full_backup
export -f create_incremental_backup
export -f create_specific_backup
export -f restore_from_backup
export -f list_backups
export -f verify_backup_integrity
export -f cleanup_old_backups
export -f automated_backup
export -f interactive_backup_menu

# If script is run directly, start interactive mode
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Parse command line arguments
    case "${1:-interactive}" in
        "full")
            create_full_backup "${2:-Manual full backup}"
            ;;
        "incremental")
            if [[ -z "${2:-}" ]]; then
                log_error "Base backup file required for incremental backup"
                exit 1
            fi
            create_incremental_backup "$2" "${3:-Manual incremental backup}"
            ;;
        "config")
            create_specific_backup "config" "${2:-Configuration backup}"
            ;;
        "users")
            create_specific_backup "users" "${2:-Users backup}"
            ;;
        "certs")
            create_specific_backup "certs" "${2:-Certificates backup}"
            ;;
        "restore")
            if [[ -z "${2:-}" ]]; then
                log_error "Backup file required for restore operation"
                exit 1
            fi
            restore_from_backup "$2" "${3:-/}" "${4:-true}"
            ;;
        "list")
            list_backups
            ;;
        "verify")
            if [[ -z "${2:-}" ]]; then
                log_error "Backup file required for verification"
                exit 1
            fi
            verify_backup_integrity "$2"
            ;;
        "cleanup")
            cleanup_old_backups "${2:-$MAX_BACKUP_AGE_DAYS}" "${3:-false}"
            ;;
        "auto")
            automated_backup "${2:-smart}"
            ;;
        "interactive"|"")
            interactive_backup_menu
            ;;
        *)
            echo "Usage: $0 [command] [options]"
            echo "Commands:"
            echo "  full [description]                    - Create full backup"
            echo "  incremental <base_backup> [desc]      - Create incremental backup"
            echo "  config [description]                  - Create configuration backup"
            echo "  users [description]                   - Create users backup"
            echo "  certs [description]                   - Create certificates backup"
            echo "  restore <backup_file> [target] [verify] - Restore from backup"
            echo "  list                                  - List available backups"
            echo "  verify <backup_file>                  - Verify backup integrity"
            echo "  cleanup [max_age_days] [dry_run]      - Cleanup old backups"
            echo "  auto [smart|full|incremental]         - Automated backup"
            echo "  interactive                           - Interactive menu (default)"
            exit 1
            ;;
    esac
fi