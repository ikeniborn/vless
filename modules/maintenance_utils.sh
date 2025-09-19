#!/bin/bash
# Maintenance Utilities Module for VLESS VPN Project
# System maintenance, diagnostics, and bulk operations
# Author: Claude Code
# Version: 1.0

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load common utilities
source "${SCRIPT_DIR}/common_utils.sh"

# Configuration
readonly MAINTENANCE_LOG="/var/log/vless/maintenance.log"
readonly TEMP_CLEANUP_DIRS=("/tmp" "/var/tmp" "/opt/vless/temp")
readonly LOG_DIRS=("/var/log/vless" "/var/log/xray" "/var/log/docker")
readonly BACKUP_DIR="/opt/vless/backups"
readonly CONFIG_BACKUP_DIR="$BACKUP_DIR/configs"
readonly USER_BACKUP_DIR="$BACKUP_DIR/users"
readonly SYSTEM_INFO_FILE="/tmp/vless-system-info.txt"
readonly DIAGNOSTICS_DIR="/tmp/vless-diagnostics"

# Maintenance logging function
log_maintenance() {
    local level="$1"
    local message="$2"
    local timestamp=$(get_timestamp)

    echo "[$timestamp] [$level] $message" | tee -a "$MAINTENANCE_LOG"

    # Also use system logger if available
    if command -v vless-logger >/dev/null 2>&1; then
        source /usr/local/bin/vless-logger
        log_system "$message"
    fi
}

# Clean temporary files
cleanup_temp_files() {
    print_header "Cleaning Temporary Files"

    local total_cleaned=0
    local space_freed=0

    for temp_dir in "${TEMP_CLEANUP_DIRS[@]}"; do
        if [[ -d "$temp_dir" ]]; then
            print_section "Cleaning $temp_dir"

            # Calculate space before cleanup
            local space_before=$(du -sb "$temp_dir" 2>/dev/null | awk '{print $1}' || echo "0")

            # Clean files older than 7 days
            local files_cleaned=$(find "$temp_dir" -type f -mtime +7 -delete -print 2>/dev/null | wc -l)

            # Clean empty directories
            find "$temp_dir" -type d -empty -delete 2>/dev/null || true

            # Calculate space after cleanup
            local space_after=$(du -sb "$temp_dir" 2>/dev/null | awk '{print $1}' || echo "0")
            local space_diff=$((space_before - space_after))

            total_cleaned=$((total_cleaned + files_cleaned))
            space_freed=$((space_freed + space_diff))

            print_success "Cleaned $files_cleaned files from $temp_dir"
            log_maintenance "INFO" "Cleaned $files_cleaned files from $temp_dir, freed $(( space_diff / 1024 / 1024 ))MB"
        fi
    done

    print_success "Total cleanup: $total_cleaned files, $(( space_freed / 1024 / 1024 ))MB freed"
}

# Clean old log files
cleanup_old_logs() {
    print_header "Cleaning Old Log Files"

    local days_to_keep="${1:-30}"
    local total_cleaned=0

    print_info "Removing log files older than $days_to_keep days"

    for log_dir in "${LOG_DIRS[@]}"; do
        if [[ -d "$log_dir" ]]; then
            print_section "Cleaning logs in $log_dir"

            # Find and remove old log files
            local old_logs=$(find "$log_dir" -name "*.log*" -type f -mtime +$days_to_keep -print 2>/dev/null || true)

            if [[ -n "$old_logs" ]]; then
                local count=$(echo "$old_logs" | wc -l)
                echo "$old_logs" | xargs rm -f
                total_cleaned=$((total_cleaned + count))
                print_success "Removed $count old log files from $log_dir"
                log_maintenance "INFO" "Removed $count old log files from $log_dir"
            else
                print_info "No old log files found in $log_dir"
            fi
        fi
    done

    # Clean compressed logs
    find /var/log -name "*.gz" -mtime +$days_to_keep -delete 2>/dev/null || true

    print_success "Total log cleanup: $total_cleaned files removed"
}

# Validate configuration files
validate_configurations() {
    print_header "Validating Configuration Files"

    local validation_passed=true
    local config_files=(
        "/opt/vless/docker-compose.yml:Docker Compose"
        "/opt/vless/configs/xray_config.json:Xray Config"
        "/etc/vless-security/fail2ban.conf:Fail2ban Config"
        "/etc/vless-monitoring/thresholds.conf:Monitoring Config"
    )

    for item in "${config_files[@]}"; do
        local file_path="${item%:*}"
        local description="${item#*:}"

        print_section "Validating $description"

        if [[ ! -f "$file_path" ]]; then
            print_warning "Configuration file not found: $file_path"
            validation_passed=false
            continue
        fi

        case "$file_path" in
            *.yml|*.yaml)
                if command -v docker-compose >/dev/null 2>&1; then
                    if docker-compose -f "$file_path" config >/dev/null 2>&1; then
                        print_success "$description syntax is valid"
                    else
                        print_error "$description has syntax errors"
                        validation_passed=false
                    fi
                else
                    print_warning "Cannot validate $description - docker-compose not available"
                fi
                ;;
            *.json)
                if command -v jq >/dev/null 2>&1; then
                    if jq empty "$file_path" >/dev/null 2>&1; then
                        print_success "$description JSON syntax is valid"
                    else
                        print_error "$description has invalid JSON syntax"
                        validation_passed=false
                    fi
                else
                    print_warning "Cannot validate $description - jq not available"
                fi
                ;;
            *.conf)
                # Basic syntax check for conf files
                if [[ -r "$file_path" ]]; then
                    # Check for basic syntax issues
                    if grep -q "=" "$file_path" && ! grep -q "^[[:space:]]*#.*=" "$file_path"; then
                        print_success "$description appears valid"
                    else
                        print_warning "$description may have syntax issues"
                    fi
                else
                    print_error "Cannot read $description"
                    validation_passed=false
                fi
                ;;
        esac
    done

    if $validation_passed; then
        print_success "All configuration validations passed"
        log_maintenance "INFO" "Configuration validation completed successfully"
    else
        print_error "Some configuration validations failed"
        log_maintenance "ERROR" "Configuration validation completed with errors"
        return 1
    fi
}

# Generate system health report
generate_system_report() {
    local output_file="${1:-$SYSTEM_INFO_FILE}"

    print_header "Generating System Health Report"

    {
        echo "VLESS VPN System Health Report"
        echo "Generated: $(date)"
        echo "Hostname: $(hostname)"
        echo "======================================"
        echo

        # System Information
        echo "SYSTEM INFORMATION"
        echo "------------------"
        echo "OS: $(get_os_info)"
        echo "Kernel: $(get_kernel_version)"
        echo "Architecture: $(get_architecture)"
        echo "Uptime: $(get_system_uptime)"
        echo "Local IP: $(get_local_ip)"
        echo "Public IP: $(get_public_ip 2>/dev/null || echo 'Unable to determine')"
        echo

        # Resource Usage
        echo "RESOURCE USAGE"
        echo "--------------"
        echo "Memory: $(get_memory_info)"
        echo "Disk Usage: $(get_disk_info)"
        echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
        echo

        # Network Information
        echo "NETWORK INFORMATION"
        echo "-------------------"
        echo "Active Connections: $(netstat -an | grep ESTABLISHED | wc -l)"
        echo "Listening Ports:"
        netstat -tlnp | grep LISTEN | awk '{print "  " $1 " " $4 " " $7}' | sort
        echo

        # Service Status
        echo "SERVICE STATUS"
        echo "--------------"
        local services=("docker" "vless-vpn" "fail2ban" "ufw" "rsyslog")
        for service in "${services[@]}"; do
            if systemctl list-unit-files | grep -q "$service"; then
                local status=$(systemctl is-active "$service" 2>/dev/null || echo "unknown")
                printf "%-15s %s\n" "$service:" "$status"
            fi
        done
        echo

        # Docker Status
        echo "DOCKER STATUS"
        echo "-------------"
        if command -v docker >/dev/null 2>&1; then
            echo "Docker Version: $(docker --version)"
            echo "Running Containers:"
            docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | tail -n +2 | sed 's/^/  /'
            echo
            echo "Container Resource Usage:"
            docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | tail -n +2 | sed 's/^/  /'
        else
            echo "Docker not available"
        fi
        echo

        # Disk Space Details
        echo "DISK SPACE DETAILS"
        echo "------------------"
        df -h | grep -E '^/dev/' | awk '{print "  " $1 ": " $3 "/" $2 " (" $5 " used)"}'
        echo

        # Recent Log Activity
        echo "RECENT LOG ACTIVITY"
        echo "-------------------"
        if [[ -f "/var/log/vless/vless.log" ]]; then
            echo "Last 5 VLESS events:"
            tail -n 5 "/var/log/vless/vless.log" | sed 's/^/  /'
        fi
        echo

        if [[ -f "/var/log/vless/error.log" ]]; then
            echo "Recent errors:"
            tail -n 3 "/var/log/vless/error.log" | sed 's/^/  /'
        fi
        echo

        # Security Status
        echo "SECURITY STATUS"
        echo "---------------"
        echo "UFW Status: $(ufw status | head -1 | awk '{print $2}')"
        echo "Fail2ban Status: $(systemctl is-active fail2ban 2>/dev/null || echo 'inactive')"
        echo "Last Failed Logins:"
        lastb | head -3 | sed 's/^/  /' 2>/dev/null || echo "  No failed login attempts"
        echo

        # User Activity
        echo "VPN USER ACTIVITY"
        echo "-----------------"
        if [[ -f "/opt/vless/users/users.json" ]]; then
            local user_count=$(jq length "/opt/vless/users/users.json" 2>/dev/null || echo "0")
            echo "Total VPN Users: $user_count"

            if [[ -f "/var/log/vless/access.log" ]]; then
                echo "Recent connections:"
                grep "connect" "/var/log/vless/access.log" | tail -3 | sed 's/^/  /' || echo "  No recent connections"
            fi
        else
            echo "No user database found"
        fi
        echo

        # Configuration Status
        echo "CONFIGURATION STATUS"
        echo "--------------------"
        local config_files=(
            "/opt/vless/docker-compose.yml"
            "/opt/vless/configs/xray_config.json"
            "/etc/vless-security"
            "/etc/vless-monitoring"
        )

        for config in "${config_files[@]}"; do
            if [[ -e "$config" ]]; then
                printf "%-40s %s\n" "$(basename "$config"):" "OK"
            else
                printf "%-40s %s\n" "$(basename "$config"):" "MISSING"
            fi
        done

    } > "$output_file"

    print_success "System report generated: $output_file"
    log_maintenance "INFO" "System health report generated: $output_file"
}

# Bulk user management operations
bulk_user_operations() {
    print_header "Bulk User Management Operations"

    local operation="${1:-}"
    if [[ -z "$operation" ]]; then
        echo "Available bulk operations:"
        echo "1. export-users    - Export all users to CSV"
        echo "2. import-users    - Import users from CSV"
        echo "3. backup-users    - Backup user database"
        echo "4. restore-users   - Restore user database"
        echo "5. cleanup-users   - Remove inactive users"
        echo "6. user-statistics - Generate user statistics"
        operation=$(prompt_choice "Select operation:" "export-users" "import-users" "backup-users" "restore-users" "cleanup-users" "user-statistics")
    fi

    case "$operation" in
        0|"export-users")
            export_users_csv
            ;;
        1|"import-users")
            import_users_csv
            ;;
        2|"backup-users")
            backup_user_database
            ;;
        3|"restore-users")
            restore_user_database
            ;;
        4|"cleanup-users")
            cleanup_inactive_users
            ;;
        5|"user-statistics")
            generate_user_statistics
            ;;
        *)
            print_error "Invalid operation: $operation"
            return 1
            ;;
    esac
}

# Export users to CSV
export_users_csv() {
    local output_file="${1:-/tmp/vless-users-$(date +%Y%m%d_%H%M%S).csv}"
    local users_db="/opt/vless/users/users.json"

    print_section "Exporting Users to CSV"

    if [[ ! -f "$users_db" ]]; then
        print_error "User database not found: $users_db"
        return 1
    fi

    # Create CSV header
    echo "uuid,name,created_date,last_seen,total_connections,status" > "$output_file"

    # Process users
    jq -r '.[] | [.uuid, .name, .created_date, (.last_seen // "never"), (.stats.total_connections // 0), (.status // "active")] | @csv' "$users_db" >> "$output_file" 2>/dev/null || {
        print_error "Failed to export users - invalid JSON format"
        return 1
    }

    local user_count=$(tail -n +2 "$output_file" | wc -l)
    print_success "Exported $user_count users to: $output_file"
    log_maintenance "INFO" "Exported $user_count users to CSV: $output_file"
}

# Import users from CSV
import_users_csv() {
    local input_file="${1:-}"

    if [[ -z "$input_file" ]]; then
        input_file=$(prompt_input "Enter CSV file path")
    fi

    if [[ ! -f "$input_file" ]]; then
        print_error "CSV file not found: $input_file"
        return 1
    fi

    print_section "Importing Users from CSV"

    # Validate CSV format
    if ! head -1 "$input_file" | grep -q "uuid,name"; then
        print_error "Invalid CSV format - missing required headers"
        return 1
    fi

    local imported=0
    local skipped=0

    # Load user management functions
    if [[ -f "$SCRIPT_DIR/user_management.sh" ]]; then
        source "$SCRIPT_DIR/user_management.sh"
    else
        print_error "User management module not found"
        return 1
    fi

    # Process CSV file
    tail -n +2 "$input_file" | while IFS=',' read -r uuid name created_date last_seen total_connections status; do
        # Remove quotes
        uuid=$(echo "$uuid" | tr -d '"')
        name=$(echo "$name" | tr -d '"')

        if [[ -n "$uuid" ]] && [[ -n "$name" ]]; then
            # Check if user already exists
            if user_exists "$uuid"; then
                print_warning "User already exists, skipping: $name ($uuid)"
                skipped=$((skipped + 1))
            else
                # Add user
                if add_user "$name" "$uuid"; then
                    imported=$((imported + 1))
                    print_success "Imported user: $name"
                else
                    print_error "Failed to import user: $name"
                fi
            fi
        fi
    done

    print_success "Import completed: $imported imported, $skipped skipped"
    log_maintenance "INFO" "User import completed: $imported imported, $skipped skipped from $input_file"
}

# Backup user database
backup_user_database() {
    print_section "Backing Up User Database"

    ensure_directory "$USER_BACKUP_DIR" "755"

    local timestamp=$(get_timestamp_filename)
    local backup_file="$USER_BACKUP_DIR/users_backup_${timestamp}.json"
    local users_db="/opt/vless/users/users.json"

    if [[ -f "$users_db" ]]; then
        cp "$users_db" "$backup_file"
        gzip "$backup_file"

        print_success "User database backed up to: ${backup_file}.gz"
        log_maintenance "INFO" "User database backed up to: ${backup_file}.gz"

        # Cleanup old backups (keep last 10)
        find "$USER_BACKUP_DIR" -name "users_backup_*.json.gz" -type f | sort -r | tail -n +11 | xargs rm -f

    else
        print_warning "User database not found: $users_db"
    fi
}

# Restore user database
restore_user_database() {
    print_section "Restoring User Database"

    if [[ ! -d "$USER_BACKUP_DIR" ]]; then
        print_error "Backup directory not found: $USER_BACKUP_DIR"
        return 1
    fi

    # List available backups
    local backups=($(find "$USER_BACKUP_DIR" -name "users_backup_*.json.gz" -type f | sort -r))

    if [[ ${#backups[@]} -eq 0 ]]; then
        print_error "No user database backups found"
        return 1
    fi

    echo "Available backups:"
    for i in "${!backups[@]}"; do
        local backup_file="${backups[i]}"
        local filename=$(basename "$backup_file")
        local date_part=$(echo "$filename" | sed 's/users_backup_\([0-9_]*\)\.json\.gz/\1/')
        local formatted_date=$(echo "$date_part" | sed 's/_/ /g; s/\([0-9]\{8\}\) \([0-9]\{6\}\)/\1 \2/')
        echo "$((i + 1)). $formatted_date"
    done

    local choice=$(prompt_input "Select backup to restore (1-${#backups[@]})" "1")

    if [[ $choice -ge 1 ]] && [[ $choice -le ${#backups[@]} ]]; then
        local selected_backup="${backups[$((choice - 1))]}"

        if prompt_yes_no "Are you sure you want to restore from this backup? This will overwrite the current user database." "n"; then
            # Backup current database first
            backup_user_database

            # Restore selected backup
            gunzip -c "$selected_backup" > "/opt/vless/users/users.json"

            print_success "User database restored from: $(basename "$selected_backup")"
            log_maintenance "INFO" "User database restored from: $selected_backup"

            # Restart services to apply changes
            if systemctl is-active --quiet vless-vpn; then
                systemctl restart vless-vpn
                print_info "VLESS VPN service restarted to apply changes"
            fi
        fi
    else
        print_error "Invalid selection"
    fi
}

# Cleanup inactive users
cleanup_inactive_users() {
    print_section "Cleaning Up Inactive Users"

    local days_inactive="${1:-90}"
    local users_db="/opt/vless/users/users.json"

    if [[ ! -f "$users_db" ]]; then
        print_error "User database not found: $users_db"
        return 1
    fi

    print_info "Finding users inactive for more than $days_inactive days"

    local cutoff_date=$(date -d "$days_inactive days ago" '+%Y-%m-%d')
    local inactive_users=()

    # Find inactive users
    while IFS= read -r line; do
        local uuid=$(echo "$line" | jq -r '.uuid')
        local name=$(echo "$line" | jq -r '.name')
        local last_seen=$(echo "$line" | jq -r '.last_seen // empty')

        if [[ -n "$last_seen" ]] && [[ "$last_seen" < "$cutoff_date" ]]; then
            inactive_users+=("$uuid:$name")
        fi
    done < <(jq -c '.[]' "$users_db")

    if [[ ${#inactive_users[@]} -eq 0 ]]; then
        print_info "No inactive users found"
        return 0
    fi

    echo "Found ${#inactive_users[@]} inactive users:"
    for user_info in "${inactive_users[@]}"; do
        local name="${user_info#*:}"
        echo "  - $name"
    done

    if prompt_yes_no "Do you want to remove these inactive users?" "n"; then
        local removed=0

        # Load user management functions
        if [[ -f "$SCRIPT_DIR/user_management.sh" ]]; then
            source "$SCRIPT_DIR/user_management.sh"
        else
            print_error "User management module not found"
            return 1
        fi

        for user_info in "${inactive_users[@]}"; do
            local uuid="${user_info%:*}"
            local name="${user_info#*:}"

            if remove_user "$uuid"; then
                removed=$((removed + 1))
                print_success "Removed inactive user: $name"
            else
                print_error "Failed to remove user: $name"
            fi
        done

        print_success "Cleanup completed: $removed users removed"
        log_maintenance "INFO" "Inactive user cleanup: $removed users removed (inactive > $days_inactive days)"
    fi
}

# Generate user statistics
generate_user_statistics() {
    local output_file="${1:-/tmp/vless-user-stats-$(date +%Y%m%d_%H%M%S).txt}"
    local users_db="/opt/vless/users/users.json"

    print_section "Generating User Statistics"

    if [[ ! -f "$users_db" ]]; then
        print_error "User database not found: $users_db"
        return 1
    fi

    {
        echo "VLESS VPN User Statistics Report"
        echo "Generated: $(date)"
        echo "========================================"
        echo

        # Basic statistics
        local total_users=$(jq length "$users_db")
        local active_users=$(jq '[.[] | select(.status == "active" or .status == null)] | length' "$users_db")
        local inactive_users=$(jq '[.[] | select(.status == "inactive")] | length' "$users_db")

        echo "OVERVIEW"
        echo "--------"
        echo "Total Users: $total_users"
        echo "Active Users: $active_users"
        echo "Inactive Users: $inactive_users"
        echo

        # Registration timeline
        echo "REGISTRATION TIMELINE"
        echo "--------------------"
        jq -r '.[] | .created_date // "unknown"' "$users_db" | sort | uniq -c | sort -nr | head -10 | \
            awk '{printf "%-12s %s users\n", $2, $1}' || echo "No registration data available"
        echo

        # User activity (if available)
        echo "USER ACTIVITY"
        echo "-------------"
        if jq -e '.[0] | has("stats")' "$users_db" >/dev/null 2>&1; then
            echo "Top 10 Users by Connection Count:"
            jq -r '.[] | select(.stats.total_connections) | [.name, .stats.total_connections] | @tsv' "$users_db" | \
                sort -k2 -nr | head -10 | awk '{printf "  %-20s %s connections\n", $1, $2}'
        else
            echo "No activity statistics available"
        fi
        echo

        # Recent activity
        echo "RECENT ACTIVITY (Last 7 days)"
        echo "-----------------------------"
        local week_ago=$(date -d '7 days ago' '+%Y-%m-%d')
        local recent_users=$(jq "[.[] | select(.last_seen and .last_seen >= \"$week_ago\")] | length" "$users_db" 2>/dev/null || echo "0")
        echo "Users active in last 7 days: $recent_users"

    } > "$output_file"

    print_success "User statistics generated: $output_file"
    log_maintenance "INFO" "User statistics report generated: $output_file"
}

# Run system diagnostics
run_system_diagnostics() {
    print_header "Running System Diagnostics"

    ensure_directory "$DIAGNOSTICS_DIR" "755"

    local diagnostic_files=(
        "system-info.txt"
        "service-status.txt"
        "network-status.txt"
        "docker-status.txt"
        "log-summary.txt"
    )

    # System information
    {
        echo "=== SYSTEM INFORMATION ==="
        uname -a
        echo
        cat /etc/os-release
        echo
        echo "=== MEMORY INFORMATION ==="
        free -h
        echo
        echo "=== DISK INFORMATION ==="
        df -h
        echo
        echo "=== CPU INFORMATION ==="
        lscpu | head -20
    } > "$DIAGNOSTICS_DIR/system-info.txt"

    # Service status
    {
        echo "=== SERVICE STATUS ==="
        systemctl status docker vless-vpn fail2ban ufw rsyslog --no-pager -l
    } > "$DIAGNOSTICS_DIR/service-status.txt" 2>&1

    # Network status
    {
        echo "=== NETWORK CONFIGURATION ==="
        ip addr show
        echo
        echo "=== ROUTING TABLE ==="
        ip route show
        echo
        echo "=== LISTENING PORTS ==="
        netstat -tlnp
        echo
        echo "=== ACTIVE CONNECTIONS ==="
        netstat -an | grep ESTABLISHED | head -20
    } > "$DIAGNOSTICS_DIR/network-status.txt"

    # Docker status
    if command -v docker >/dev/null 2>&1; then
        {
            echo "=== DOCKER VERSION ==="
            docker version
            echo
            echo "=== DOCKER SYSTEM INFO ==="
            docker system info
            echo
            echo "=== DOCKER CONTAINERS ==="
            docker ps -a
            echo
            echo "=== DOCKER IMAGES ==="
            docker images
            echo
            echo "=== DOCKER NETWORKS ==="
            docker network ls
        } > "$DIAGNOSTICS_DIR/docker-status.txt" 2>&1
    fi

    # Log summary
    {
        echo "=== LOG FILE SIZES ==="
        find /var/log -name "*.log" -type f -exec ls -lh {} \; | sort -k5 -hr | head -20
        echo
        echo "=== RECENT ERRORS ==="
        journalctl -p err --since "24 hours ago" --no-pager | tail -50
        echo
        echo "=== VLESS LOGS ==="
        if [[ -d "/var/log/vless" ]]; then
            ls -la /var/log/vless/
            echo
            if [[ -f "/var/log/vless/error.log" ]]; then
                echo "Recent VLESS errors:"
                tail -20 /var/log/vless/error.log
            fi
        fi
    } > "$DIAGNOSTICS_DIR/log-summary.txt" 2>&1

    # Create diagnostics archive
    local archive_name="vless-diagnostics-$(hostname)-$(date +%Y%m%d_%H%M%S).tar.gz"
    tar -czf "/tmp/$archive_name" -C "$(dirname "$DIAGNOSTICS_DIR")" "$(basename "$DIAGNOSTICS_DIR")"

    print_success "Diagnostics completed. Archive: /tmp/$archive_name"
    log_maintenance "INFO" "System diagnostics completed, archive created: /tmp/$archive_name"

    # Show summary
    print_section "Diagnostic Summary"
    echo "Files created in $DIAGNOSTICS_DIR:"
    ls -la "$DIAGNOSTICS_DIR/"
    echo
    echo "Archive created: /tmp/$archive_name"
    echo "Archive size: $(du -h "/tmp/$archive_name" | awk '{print $1}')"
}

# Main maintenance menu
maintenance_menu() {
    print_header "VLESS Maintenance Utilities"

    local options=(
        "Clean temporary files"
        "Clean old logs"
        "Validate configurations"
        "Generate system report"
        "Bulk user operations"
        "Run diagnostics"
        "Full maintenance (all tasks)"
    )

    echo "Available maintenance tasks:"
    for i in "${!options[@]}"; do
        echo "$((i + 1)). ${options[i]}"
    done
    echo

    local choice=$(prompt_choice "Select maintenance task:" "${options[@]}")

    case "$choice" in
        0) cleanup_temp_files ;;
        1) cleanup_old_logs ;;
        2) validate_configurations ;;
        3) generate_system_report ;;
        4) bulk_user_operations ;;
        5) run_system_diagnostics ;;
        6) run_full_maintenance ;;
        *) print_error "Invalid selection" ;;
    esac
}

# Run full maintenance
run_full_maintenance() {
    print_header "Running Full System Maintenance"

    log_maintenance "INFO" "Starting full system maintenance"

    # Run all maintenance tasks
    cleanup_temp_files
    cleanup_old_logs 30
    validate_configurations
    generate_system_report
    backup_user_database

    # Optional diagnostics
    if prompt_yes_no "Run system diagnostics as well?" "n"; then
        run_system_diagnostics
    fi

    print_success "Full system maintenance completed"
    log_maintenance "INFO" "Full system maintenance completed successfully"
}

# Export functions
export -f cleanup_temp_files cleanup_old_logs validate_configurations generate_system_report
export -f bulk_user_operations export_users_csv import_users_csv backup_user_database restore_user_database
export -f cleanup_inactive_users generate_user_statistics run_system_diagnostics
export -f maintenance_menu run_full_maintenance log_maintenance

# Main execution if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Create log file if it doesn't exist
    ensure_directory "$(dirname "$MAINTENANCE_LOG")" "755"
    touch "$MAINTENANCE_LOG"

    case "${1:-menu}" in
        "menu")
            maintenance_menu
            ;;
        "cleanup")
            cleanup_temp_files
            cleanup_old_logs "${2:-30}"
            ;;
        "validate")
            validate_configurations
            ;;
        "report")
            generate_system_report "$2"
            ;;
        "users")
            bulk_user_operations "$2"
            ;;
        "diagnostics")
            run_system_diagnostics
            ;;
        "full")
            run_full_maintenance
            ;;
        *)
            echo "Usage: $0 {menu|cleanup|validate|report|users|diagnostics|full}"
            echo "  menu        - Show interactive maintenance menu"
            echo "  cleanup     - Clean temporary files and old logs"
            echo "  validate    - Validate configuration files"
            echo "  report      - Generate system health report"
            echo "  users       - Bulk user management operations"
            echo "  diagnostics - Run system diagnostics"
            echo "  full        - Run all maintenance tasks"
            exit 1
            ;;
    esac
fi