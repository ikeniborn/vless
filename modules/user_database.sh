#!/bin/bash
# ======================================================================================
# VLESS+Reality VPN Management System - User Database Management Module
# ======================================================================================
# This module provides persistent storage and management of user data including
# backup, restore, import, export, and database maintenance operations.
#
# Author: Claude Code
# Version: 1.0
# Last Modified: 2025-09-21
# ======================================================================================

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_utils.sh"

# Database management specific variables
readonly USER_DATABASE="${USER_DIR}/users.json"
readonly DATABASE_BACKUP_DIR="${BACKUP_DIR}/user_database"
readonly DATABASE_SCHEMA_VERSION="1.0"
readonly MAX_BACKUP_RETENTION_DAYS=30

# ======================================================================================
# DATABASE INITIALIZATION FUNCTIONS
# ======================================================================================

# Function: init_user_database
# Description: Initialize user database with proper schema
init_user_database() {
    log_info "Initializing user database..."

    # Create necessary directories
    create_directory "$USER_DIR" "700" "root:root"
    create_directory "$DATABASE_BACKUP_DIR" "700" "root:root"

    # Initialize database file if it doesn't exist
    if [[ ! -f "$USER_DATABASE" ]]; then
        create_empty_database
        log_success "User database initialized: $USER_DATABASE"
    else
        # Validate existing database
        if validate_database_schema; then
            log_info "User database already exists and is valid"
        else
            log_warn "Database schema validation failed, backing up and recreating..."
            backup_user_database "schema_migration"
            create_empty_database
        fi
    fi

    # Ensure proper permissions
    chmod 600 "$USER_DATABASE"
    chown root:root "$USER_DATABASE"
}

# Function: create_empty_database
# Description: Create an empty database with proper schema
create_empty_database() {
    local created_date=$(date -Iseconds)

    cat > "$USER_DATABASE" << EOF
{
  "metadata": {
    "version": "$DATABASE_SCHEMA_VERSION",
    "created": "$created_date",
    "last_modified": "$created_date",
    "total_users": 0,
    "schema_version": "$DATABASE_SCHEMA_VERSION"
  },
  "users": []
}
EOF

    log_debug "Created empty database with schema version $DATABASE_SCHEMA_VERSION"
}

# Function: validate_database_schema
# Description: Validate database schema and structure
# Returns: 0 if valid, 1 if invalid
validate_database_schema() {
    if [[ ! -f "$USER_DATABASE" ]]; then
        log_debug "Database file does not exist"
        return 1
    fi

    # Check if file is valid JSON
    if ! python3 -c "
import json
try:
    with open('$USER_DATABASE', 'r') as f:
        data = json.load(f)

    # Check required top-level keys
    if 'metadata' not in data or 'users' not in data:
        exit(1)

    # Check metadata structure
    metadata = data.get('metadata', {})
    required_metadata = ['version', 'created', 'schema_version']
    for key in required_metadata:
        if key not in metadata:
            exit(1)

    # Validate users array
    users = data.get('users', [])
    if not isinstance(users, list):
        exit(1)

    # Validate each user structure
    required_user_fields = ['username', 'uuid', 'created_date', 'enabled']
    for user in users:
        if not isinstance(user, dict):
            exit(1)
        for field in required_user_fields:
            if field not in user:
                exit(1)

    exit(0)
except Exception as e:
    exit(1)
" 2>/dev/null; then
        log_debug "Database schema validation failed"
        return 1
    fi

    log_debug "Database schema validation passed"
    return 0
}

# ======================================================================================
# BACKUP AND RESTORE FUNCTIONS
# ======================================================================================

# Function: backup_user_database
# Description: Create a timestamped backup of the user database
# Parameters: $1 - backup suffix (optional)
# Returns: 0 on success, 1 on failure
backup_user_database() {
    local backup_suffix="${1:-manual}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_filename="users_${backup_suffix}_${timestamp}.json"
    local backup_path="${DATABASE_BACKUP_DIR}/${backup_filename}"

    if [[ ! -f "$USER_DATABASE" ]]; then
        log_error "User database does not exist: $USER_DATABASE"
        return 1
    fi

    log_info "Creating database backup: $backup_filename"

    # Create backup directory if it doesn't exist
    create_directory "$DATABASE_BACKUP_DIR" "700" "root:root"

    # Copy database to backup location
    if cp "$USER_DATABASE" "$backup_path"; then
        chmod 600 "$backup_path"
        chown root:root "$backup_path"

        # Update backup metadata
        local backup_info_file="${DATABASE_BACKUP_DIR}/backup_info.json"
        update_backup_metadata "$backup_path" "$backup_suffix"

        log_success "Database backup created: $backup_path"

        # Clean old backups
        cleanup_old_backups

        echo "$backup_path"
        return 0
    else
        log_error "Failed to create database backup"
        return 1
    fi
}

# Function: update_backup_metadata
# Description: Update backup metadata information
# Parameters: $1 - backup file path, $2 - backup type
update_backup_metadata() {
    local backup_path="$1"
    local backup_type="$2"
    local backup_info_file="${DATABASE_BACKUP_DIR}/backup_info.json"
    local timestamp=$(date -Iseconds)

    # Get backup file info
    local backup_size
    backup_size=$(stat -c%s "$backup_path" 2>/dev/null || echo 0)

    # Initialize backup info file if it doesn't exist
    if [[ ! -f "$backup_info_file" ]]; then
        echo '{"backups": []}' > "$backup_info_file"
    fi

    # Add backup information
    python3 -c "
import json
import os

backup_info = {
    'file': os.path.basename('$backup_path'),
    'full_path': '$backup_path',
    'type': '$backup_type',
    'created': '$timestamp',
    'size': $backup_size
}

try:
    with open('$backup_info_file', 'r') as f:
        data = json.load(f)

    data['backups'].append(backup_info)

    # Sort by creation time (newest first)
    data['backups'].sort(key=lambda x: x['created'], reverse=True)

    with open('$backup_info_file', 'w') as f:
        json.dump(data, f, indent=2)

except Exception as e:
    print(f'Error updating backup metadata: {e}')
"

    chmod 600 "$backup_info_file"
}

# Function: list_database_backups
# Description: List available database backups
list_database_backups() {
    local backup_info_file="${DATABASE_BACKUP_DIR}/backup_info.json"

    if [[ ! -f "$backup_info_file" ]]; then
        log_warn "No backup information found"
        return 1
    fi

    echo ""
    log_info "Available Database Backups:"
    echo "==========================================="
    printf "%-30s %-15s %-20s %-10s\n" "FILENAME" "TYPE" "CREATED" "SIZE"
    printf "%-30s %-15s %-20s %-10s\n" "--------" "----" "-------" "----"

    python3 -c "
import json
import os
from datetime import datetime

try:
    with open('$backup_info_file', 'r') as f:
        data = json.load(f)

    backups = data.get('backups', [])
    for backup in backups:
        filename = backup.get('file', 'N/A')[:30]
        backup_type = backup.get('type', 'N/A')[:15]
        created = backup.get('created', 'N/A')[:19].replace('T', ' ')
        size = backup.get('size', 0)

        # Format size
        if size > 1024 * 1024:
            size_str = f'{size / (1024 * 1024):.1f}MB'
        elif size > 1024:
            size_str = f'{size / 1024:.1f}KB'
        else:
            size_str = f'{size}B'

        print(f'{filename:<30} {backup_type:<15} {created:<20} {size_str:<10}')

except Exception as e:
    print(f'Error reading backup information: {e}')
"
    echo "==========================================="
    echo ""
}

# Function: restore_user_database
# Description: Restore database from backup
# Parameters: $1 - backup file path or filename
# Returns: 0 on success, 1 on failure
restore_user_database() {
    local backup_identifier="$1"
    local backup_path=""

    if [[ -z "$backup_identifier" ]]; then
        log_error "Backup identifier cannot be empty"
        return 1
    fi

    # Determine backup file path
    if [[ -f "$backup_identifier" ]]; then
        backup_path="$backup_identifier"
    elif [[ -f "${DATABASE_BACKUP_DIR}/${backup_identifier}" ]]; then
        backup_path="${DATABASE_BACKUP_DIR}/${backup_identifier}"
    else
        # Search for backup by partial filename
        backup_path=$(find "$DATABASE_BACKUP_DIR" -name "*${backup_identifier}*" -type f | head -1)
        if [[ -z "$backup_path" ]]; then
            log_error "Backup file not found: $backup_identifier"
            return 1
        fi
    fi

    log_info "Restoring database from backup: $(basename "$backup_path")"

    # Validate backup file
    if ! python3 -c "
import json
try:
    with open('$backup_path', 'r') as f:
        data = json.load(f)
    exit(0)
except Exception:
    exit(1)
" 2>/dev/null; then
        log_error "Invalid backup file: $backup_path"
        return 1
    fi

    # Create backup of current database before restore
    if [[ -f "$USER_DATABASE" ]]; then
        local current_backup
        current_backup=$(backup_user_database "pre_restore")
        if [[ $? -eq 0 ]]; then
            log_info "Current database backed up: $(basename "$current_backup")"
        fi
    fi

    # Restore database
    if cp "$backup_path" "$USER_DATABASE"; then
        chmod 600 "$USER_DATABASE"
        chown root:root "$USER_DATABASE"

        log_success "Database restored successfully from: $(basename "$backup_path")"

        # Validate restored database
        if validate_database_schema; then
            log_success "Restored database validation passed"
            return 0
        else
            log_error "Restored database validation failed"
            return 1
        fi
    else
        log_error "Failed to restore database from backup"
        return 1
    fi
}

# Function: cleanup_old_backups
# Description: Remove old backup files based on retention policy
cleanup_old_backups() {
    if [[ ! -d "$DATABASE_BACKUP_DIR" ]]; then
        return 0
    fi

    log_debug "Cleaning up old database backups (retention: $MAX_BACKUP_RETENTION_DAYS days)"

    # Remove backup files older than retention period
    find "$DATABASE_BACKUP_DIR" -name "users_*.json" -type f -mtime +$MAX_BACKUP_RETENTION_DAYS -delete 2>/dev/null || true

    # Update backup info file to remove references to deleted files
    local backup_info_file="${DATABASE_BACKUP_DIR}/backup_info.json"
    if [[ -f "$backup_info_file" ]]; then
        python3 -c "
import json
import os

try:
    with open('$backup_info_file', 'r') as f:
        data = json.load(f)

    # Filter out backups that no longer exist
    existing_backups = []
    for backup in data.get('backups', []):
        if os.path.exists(backup.get('full_path', '')):
            existing_backups.append(backup)

    data['backups'] = existing_backups

    with open('$backup_info_file', 'w') as f:
        json.dump(data, f, indent=2)

except Exception:
    pass
"
    fi
}

# ======================================================================================
# IMPORT AND EXPORT FUNCTIONS
# ======================================================================================

# Function: export_users
# Description: Export user data to various formats
# Parameters: $1 - export format (json|csv|yaml), $2 - output file (optional)
export_users() {
    local export_format="${1:-json}"
    local output_file="$2"
    local timestamp=$(date +%Y%m%d_%H%M%S)

    # Set default output file if not provided
    if [[ -z "$output_file" ]]; then
        output_file="${EXPORT_DIR}/users_export_${timestamp}.${export_format}"
    fi

    if [[ ! -f "$USER_DATABASE" ]]; then
        log_error "User database not found: $USER_DATABASE"
        return 1
    fi

    log_info "Exporting users to $export_format format: $output_file"

    # Create export directory
    create_directory "$(dirname "$output_file")" "700" "root:root"

    case "$export_format" in
        "json")
            export_users_json "$output_file"
            ;;
        "csv")
            export_users_csv "$output_file"
            ;;
        "yaml")
            export_users_yaml "$output_file"
            ;;
        *)
            log_error "Unsupported export format: $export_format"
            log_info "Supported formats: json, csv, yaml"
            return 1
            ;;
    esac
}

# Function: export_users_json
# Description: Export users in JSON format
# Parameters: $1 - output file
export_users_json() {
    local output_file="$1"

    python3 -c "
import json
from datetime import datetime

try:
    with open('$USER_DATABASE', 'r') as f:
        data = json.load(f)

    export_data = {
        'export_info': {
            'exported_at': datetime.now().isoformat(),
            'total_users': len(data.get('users', [])),
            'database_version': data.get('metadata', {}).get('version', 'unknown')
        },
        'users': data.get('users', [])
    }

    with open('$output_file', 'w') as f:
        json.dump(export_data, f, indent=2)

    print('JSON export completed successfully')
except Exception as e:
    print(f'Error during JSON export: {e}')
    exit(1)
"

    if [[ $? -eq 0 ]]; then
        chmod 600 "$output_file"
        log_success "Users exported to JSON: $output_file"
        return 0
    else
        log_error "Failed to export users to JSON"
        return 1
    fi
}

# Function: export_users_csv
# Description: Export users in CSV format
# Parameters: $1 - output file
export_users_csv() {
    local output_file="$1"

    python3 -c "
import json
import csv
from datetime import datetime

try:
    with open('$USER_DATABASE', 'r') as f:
        data = json.load(f)

    users = data.get('users', [])

    with open('$output_file', 'w', newline='') as csvfile:
        fieldnames = ['username', 'uuid', 'email', 'description', 'created_date', 'last_modified', 'enabled']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)

        writer.writeheader()
        for user in users:
            writer.writerow({
                'username': user.get('username', ''),
                'uuid': user.get('uuid', ''),
                'email': user.get('email', ''),
                'description': user.get('description', ''),
                'created_date': user.get('created_date', ''),
                'last_modified': user.get('last_modified', ''),
                'enabled': user.get('enabled', False)
            })

    print('CSV export completed successfully')
except Exception as e:
    print(f'Error during CSV export: {e}')
    exit(1)
"

    if [[ $? -eq 0 ]]; then
        chmod 600 "$output_file"
        log_success "Users exported to CSV: $output_file"
        return 0
    else
        log_error "Failed to export users to CSV"
        return 1
    fi
}

# Function: export_users_yaml
# Description: Export users in YAML format
# Parameters: $1 - output file
export_users_yaml() {
    local output_file="$1"

    # Check if PyYAML is available
    if ! python3 -c "import yaml" 2>/dev/null; then
        log_warn "PyYAML not available, using simple YAML format"
        export_users_simple_yaml "$output_file"
        return $?
    fi

    python3 -c "
import json
import yaml
from datetime import datetime

try:
    with open('$USER_DATABASE', 'r') as f:
        data = json.load(f)

    export_data = {
        'export_info': {
            'exported_at': datetime.now().isoformat(),
            'total_users': len(data.get('users', [])),
            'database_version': data.get('metadata', {}).get('version', 'unknown')
        },
        'users': data.get('users', [])
    }

    with open('$output_file', 'w') as f:
        yaml.dump(export_data, f, default_flow_style=False, indent=2)

    print('YAML export completed successfully')
except Exception as e:
    print(f'Error during YAML export: {e}')
    exit(1)
"

    if [[ $? -eq 0 ]]; then
        chmod 600 "$output_file"
        log_success "Users exported to YAML: $output_file"
        return 0
    else
        log_error "Failed to export users to YAML"
        return 1
    fi
}

# Function: export_users_simple_yaml
# Description: Export users in simple YAML format (without PyYAML)
# Parameters: $1 - output file
export_users_simple_yaml() {
    local output_file="$1"

    python3 -c "
import json
from datetime import datetime

def simple_yaml_dump(data, indent=0):
    result = []
    spaces = '  ' * indent

    if isinstance(data, dict):
        for key, value in data.items():
            if isinstance(value, (dict, list)):
                result.append(f'{spaces}{key}:')
                result.append(simple_yaml_dump(value, indent + 1))
            else:
                if isinstance(value, str):
                    result.append(f'{spaces}{key}: \"{value}\"')
                else:
                    result.append(f'{spaces}{key}: {value}')
    elif isinstance(data, list):
        for item in data:
            result.append(f'{spaces}-')
            result.append(simple_yaml_dump(item, indent + 1))

    return '\n'.join(result)

try:
    with open('$USER_DATABASE', 'r') as f:
        data = json.load(f)

    export_data = {
        'export_info': {
            'exported_at': datetime.now().isoformat(),
            'total_users': len(data.get('users', [])),
            'database_version': data.get('metadata', {}).get('version', 'unknown')
        },
        'users': data.get('users', [])
    }

    with open('$output_file', 'w') as f:
        f.write(simple_yaml_dump(export_data))

    print('Simple YAML export completed successfully')
except Exception as e:
    print(f'Error during simple YAML export: {e}')
    exit(1)
"

    if [[ $? -eq 0 ]]; then
        chmod 600 "$output_file"
        log_success "Users exported to simple YAML: $output_file"
        return 0
    else
        log_error "Failed to export users to simple YAML"
        return 1
    fi
}

# Function: import_users
# Description: Import users from external file
# Parameters: $1 - import file, $2 - format (json|csv), $3 - merge strategy (merge|replace)
import_users() {
    local import_file="$1"
    local import_format="${2:-json}"
    local merge_strategy="${3:-merge}"

    if [[ ! -f "$import_file" ]]; then
        log_error "Import file not found: $import_file"
        return 1
    fi

    log_info "Importing users from $import_format file: $import_file (strategy: $merge_strategy)"

    # Create backup before import
    local backup_path
    backup_path=$(backup_user_database "pre_import")
    if [[ $? -eq 0 ]]; then
        log_info "Database backed up before import: $(basename "$backup_path")"
    fi

    case "$import_format" in
        "json")
            import_users_json "$import_file" "$merge_strategy"
            ;;
        "csv")
            import_users_csv "$import_file" "$merge_strategy"
            ;;
        *)
            log_error "Unsupported import format: $import_format"
            return 1
            ;;
    esac
}

# Function: import_users_json
# Description: Import users from JSON file
# Parameters: $1 - import file, $2 - merge strategy
import_users_json() {
    local import_file="$1"
    local merge_strategy="$2"

    python3 -c "
import json
import sys
from datetime import datetime

def merge_users(existing_users, new_users):
    \"\"\"Merge new users with existing ones\"\"\"
    existing_usernames = {user.get('username') for user in existing_users}
    existing_uuids = {user.get('uuid') for user in existing_users}

    merged_users = existing_users.copy()
    duplicates = []

    for new_user in new_users:
        username = new_user.get('username')
        uuid = new_user.get('uuid')

        if username in existing_usernames or uuid in existing_uuids:
            duplicates.append(username)
            continue

        # Add timestamp fields if missing
        if 'created_date' not in new_user:
            new_user['created_date'] = datetime.now().isoformat()
        if 'last_modified' not in new_user:
            new_user['last_modified'] = datetime.now().isoformat()

        merged_users.append(new_user)

    return merged_users, duplicates

try:
    # Read import file
    with open('$import_file', 'r') as f:
        import_data = json.load(f)

    # Extract users array
    if 'users' in import_data:
        new_users = import_data['users']
    elif isinstance(import_data, list):
        new_users = import_data
    else:
        print('ERROR: Invalid import file format')
        sys.exit(1)

    # Read existing database
    existing_data = {'users': []}
    try:
        with open('$USER_DATABASE', 'r') as f:
            existing_data = json.load(f)
    except FileNotFoundError:
        pass

    if '$merge_strategy' == 'replace':
        final_users = new_users
        duplicates = []
    else:  # merge
        final_users, duplicates = merge_users(existing_data.get('users', []), new_users)

    # Update database
    existing_data['users'] = final_users
    existing_data['metadata'] = existing_data.get('metadata', {})
    existing_data['metadata']['last_modified'] = datetime.now().isoformat()
    existing_data['metadata']['total_users'] = len(final_users)

    # Write updated database
    with open('$USER_DATABASE', 'w') as f:
        json.dump(existing_data, f, indent=2)

    print(f'SUCCESS: Imported {len(new_users)} users, {len(duplicates)} duplicates skipped')
    if duplicates:
        print(f'Duplicates: {', '.join(duplicates)}')

except Exception as e:
    print(f'ERROR: {e}')
    sys.exit(1)
"

    local result=$?
    if [[ $result -eq 0 ]]; then
        log_success "Users imported successfully from JSON"
        return 0
    else
        log_error "Failed to import users from JSON"
        return 1
    fi
}

# ======================================================================================
# DATABASE MAINTENANCE FUNCTIONS
# ======================================================================================

# Function: cleanup_orphaned_users
# Description: Remove orphaned user data and configurations
cleanup_orphaned_users() {
    log_info "Cleaning up orphaned user data..."

    if [[ ! -f "$USER_DATABASE" ]]; then
        log_warn "User database not found"
        return 1
    fi

    # Get list of valid usernames from database
    local valid_usernames
    valid_usernames=$(python3 -c "
import json
try:
    with open('$USER_DATABASE', 'r') as f:
        data = json.load(f)
    users = data.get('users', [])
    for user in users:
        print(user.get('username', ''))
except Exception:
    pass
")

    # Clean up user configuration directories
    if [[ -d "${USER_DIR}/configs" ]]; then
        local cleaned_configs=0
        while IFS= read -r -d '' config_file; do
            local config_basename
            config_basename=$(basename "$config_file")
            local username_from_config
            username_from_config=$(echo "$config_basename" | cut -d'_' -f1)

            # Check if username exists in database
            if ! echo "$valid_usernames" | grep -q "^${username_from_config}$"; then
                log_debug "Removing orphaned config: $config_file"
                rm -f "$config_file"
                ((cleaned_configs++))
            fi
        done < <(find "${USER_DIR}/configs" -type f -print0 2>/dev/null)

        if [[ $cleaned_configs -gt 0 ]]; then
            log_info "Cleaned up $cleaned_configs orphaned configuration files"
        fi
    fi

    # Clean up QR code directories
    if [[ -d "${USER_DIR}/qr_codes" ]]; then
        local cleaned_qr=0
        while IFS= read -r -d '' qr_file; do
            local qr_basename
            qr_basename=$(basename "$qr_file")
            local username_from_qr
            username_from_qr=$(echo "$qr_basename" | cut -d'_' -f1)

            # Check if username exists in database
            if ! echo "$valid_usernames" | grep -q "^${username_from_qr}$"; then
                log_debug "Removing orphaned QR code: $qr_file"
                rm -f "$qr_file"
                ((cleaned_qr++))
            fi
        done < <(find "${USER_DIR}/qr_codes" -type f -print0 2>/dev/null)

        if [[ $cleaned_qr -gt 0 ]]; then
            log_info "Cleaned up $cleaned_qr orphaned QR code files"
        fi
    fi

    log_success "Orphaned user data cleanup completed"
}

# Function: repair_database
# Description: Repair and optimize database
repair_database() {
    log_info "Repairing and optimizing user database..."

    if [[ ! -f "$USER_DATABASE" ]]; then
        log_error "User database not found"
        return 1
    fi

    # Create backup before repair
    local backup_path
    backup_path=$(backup_user_database "pre_repair")

    # Repair database using Python
    python3 -c "
import json
import uuid
from datetime import datetime

def validate_uuid(uuid_str):
    try:
        uuid.UUID(uuid_str)
        return True
    except ValueError:
        return False

def repair_user(user):
    repaired = False

    # Ensure required fields exist
    required_fields = {
        'username': '',
        'uuid': str(uuid.uuid4()),
        'email': '',
        'description': 'VPN User',
        'created_date': datetime.now().isoformat(),
        'last_modified': datetime.now().isoformat(),
        'enabled': True,
        'statistics': {
            'total_connections': 0,
            'last_connection': None,
            'data_usage': 0
        }
    }

    for field, default_value in required_fields.items():
        if field not in user:
            user[field] = default_value
            repaired = True

    # Validate UUID format
    if not validate_uuid(user['uuid']):
        user['uuid'] = str(uuid.uuid4())
        repaired = True

    # Ensure statistics structure
    if not isinstance(user.get('statistics'), dict):
        user['statistics'] = {
            'total_connections': 0,
            'last_connection': None,
            'data_usage': 0
        }
        repaired = True

    return user, repaired

try:
    with open('$USER_DATABASE', 'r') as f:
        data = json.load(f)

    users = data.get('users', [])
    repaired_count = 0

    for i, user in enumerate(users):
        repaired_user, was_repaired = repair_user(user)
        users[i] = repaired_user
        if was_repaired:
            repaired_count += 1

    # Update metadata
    data['metadata'] = data.get('metadata', {})
    data['metadata']['last_modified'] = datetime.now().isoformat()
    data['metadata']['total_users'] = len(users)
    data['metadata']['version'] = '$DATABASE_SCHEMA_VERSION'
    data['metadata']['schema_version'] = '$DATABASE_SCHEMA_VERSION'

    # Write repaired database
    with open('$USER_DATABASE', 'w') as f:
        json.dump(data, f, indent=2)

    print(f'SUCCESS: Repaired {repaired_count} user records')

except Exception as e:
    print(f'ERROR: {e}')
    exit(1)
"

    if [[ $? -eq 0 ]]; then
        log_success "Database repair completed successfully"
        return 0
    else
        log_error "Database repair failed"
        return 1
    fi
}

# ======================================================================================
# MAIN CLI INTERFACE
# ======================================================================================

# Function: show_database_menu
# Description: Interactive database management menu
show_database_menu() {
    while true; do
        echo ""
        echo "=================================================="
        echo "        VLESS User Database Management"
        echo "=================================================="
        echo "1. Create Database Backup"
        echo "2. List Available Backups"
        echo "3. Restore from Backup"
        echo "4. Export Users"
        echo "5. Import Users"
        echo "6. Cleanup Orphaned Data"
        echo "7. Repair Database"
        echo "8. Database Statistics"
        echo "9. Back to Main Menu"
        echo "=================================================="
        echo -n "Select an option (1-9): "

        local choice
        read -r choice

        case "$choice" in
            1)
                echo -n "Enter backup description (optional): "
                read -r description
                description=${description:-manual}
                backup_user_database "$description"
                ;;
            2)
                list_database_backups
                ;;
            3)
                list_database_backups
                echo -n "Enter backup filename or identifier: "
                read -r backup_id
                restore_user_database "$backup_id"
                ;;
            4)
                echo "Export formats: json, csv, yaml"
                echo -n "Enter export format [json]: "
                read -r format
                format=${format:-json}
                echo -n "Enter output file (optional): "
                read -r output_file
                export_users "$format" "$output_file"
                ;;
            5)
                echo -n "Enter import file path: "
                read -r import_file
                echo "Import formats: json, csv"
                echo -n "Enter import format [json]: "
                read -r format
                format=${format:-json}
                echo "Merge strategies: merge, replace"
                echo -n "Enter merge strategy [merge]: "
                read -r strategy
                strategy=${strategy:-merge}
                import_users "$import_file" "$format" "$strategy"
                ;;
            6)
                echo -n "Are you sure you want to cleanup orphaned data? (y/N): "
                read -r confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    cleanup_orphaned_users
                fi
                ;;
            7)
                echo -n "Are you sure you want to repair the database? (y/N): "
                read -r confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    repair_database
                fi
                ;;
            8)
                show_database_statistics
                ;;
            9)
                echo "Returning to main menu..."
                break
                ;;
            *)
                log_error "Invalid option. Please select 1-9."
                ;;
        esac

        echo ""
        echo "Press Enter to continue..."
        read -r
    done
}

# Function: show_database_statistics
# Description: Display database statistics
show_database_statistics() {
    if [[ ! -f "$USER_DATABASE" ]]; then
        log_error "User database not found"
        return 1
    fi

    echo ""
    log_info "Database Statistics:"
    echo "==================="

    python3 -c "
import json
import os
from datetime import datetime

try:
    with open('$USER_DATABASE', 'r') as f:
        data = json.load(f)

    metadata = data.get('metadata', {})
    users = data.get('users', [])

    # Basic statistics
    print(f'Database Version: {metadata.get(\"version\", \"unknown\")}')
    print(f'Created: {metadata.get(\"created\", \"unknown\")}')
    print(f'Last Modified: {metadata.get(\"last_modified\", \"unknown\")}')
    print(f'Total Users: {len(users)}')

    # File size
    file_size = os.path.getsize('$USER_DATABASE')
    if file_size > 1024:
        size_str = f'{file_size / 1024:.1f} KB'
    else:
        size_str = f'{file_size} bytes'
    print(f'Database Size: {size_str}')

    # User statistics
    enabled_users = sum(1 for user in users if user.get('enabled', False))
    disabled_users = len(users) - enabled_users

    print(f'Enabled Users: {enabled_users}')
    print(f'Disabled Users: {disabled_users}')

    # Most recent user
    if users:
        recent_user = max(users, key=lambda u: u.get('created_date', ''))
        print(f'Most Recent User: {recent_user.get(\"username\", \"unknown\")}')

except Exception as e:
    print(f'Error reading database statistics: {e}')
"

    # Backup statistics
    echo ""
    echo "Backup Statistics:"
    echo "=================="
    local backup_count
    backup_count=$(find "$DATABASE_BACKUP_DIR" -name "users_*.json" -type f 2>/dev/null | wc -l)
    echo "Total Backups: $backup_count"

    if [[ $backup_count -gt 0 ]]; then
        local latest_backup
        latest_backup=$(find "$DATABASE_BACKUP_DIR" -name "users_*.json" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
        if [[ -n "$latest_backup" ]]; then
            echo "Latest Backup: $(basename "$latest_backup")"
        fi
    fi

    echo ""
}

# ======================================================================================
# MAIN EXECUTION
# ======================================================================================

# Main function for direct script execution
main() {
    log_info "VLESS User Database Management System"

    # Validate root privileges
    validate_root

    # Initialize database system
    init_user_database

    # Handle command line arguments
    case "${1:-menu}" in
        "init")
            init_user_database
            ;;
        "backup")
            shift
            backup_user_database "$@"
            ;;
        "restore")
            shift
            restore_user_database "$@"
            ;;
        "export")
            shift
            export_users "$@"
            ;;
        "import")
            shift
            import_users "$@"
            ;;
        "cleanup")
            cleanup_orphaned_users
            ;;
        "repair")
            repair_database
            ;;
        "stats")
            show_database_statistics
            ;;
        "menu")
            show_database_menu
            ;;
        *)
            echo "Usage: $0 {init|backup|restore|export|import|cleanup|repair|stats|menu}"
            echo ""
            echo "Commands:"
            echo "  init                          - Initialize database"
            echo "  backup [description]          - Create database backup"
            echo "  restore <backup_file>         - Restore from backup"
            echo "  export <format> [output_file] - Export users (json|csv|yaml)"
            echo "  import <file> <format> [strategy] - Import users"
            echo "  cleanup                       - Clean orphaned data"
            echo "  repair                        - Repair database"
            echo "  stats                         - Show database statistics"
            echo "  menu                          - Interactive menu"
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi