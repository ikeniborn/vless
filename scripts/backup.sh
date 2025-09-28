#!/bin/bash

set -e

# Script directory - resolve symlinks to get real path
if command -v readlink >/dev/null 2>&1; then
    SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

VLESS_HOME="${VLESS_HOME:-/opt/vless}"
BACKUP_DIR="$VLESS_HOME/backups"

# Load libraries with fallback
if [ -f "$SCRIPT_DIR/lib/colors.sh" ]; then
    source "$SCRIPT_DIR/lib/colors.sh"
    source "$SCRIPT_DIR/lib/utils.sh"
elif [ -f "/opt/vless/scripts/lib/colors.sh" ]; then
    source "/opt/vless/scripts/lib/colors.sh"
    source "/opt/vless/scripts/lib/utils.sh"
else
    echo "Error: Cannot find required library files" >&2
    echo "Please ensure VLESS is properly installed" >&2
    exit 1
fi

# Check root
check_root

# Check if VLESS is installed
if [ ! -d "$VLESS_HOME" ]; then
    print_error "VLESS is not installed. Please run install.sh first."
    exit 1
fi

# Create backup directory if not exists
if [ ! -d "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"
fi

# Backup function
create_backup() {
    # Generate timestamp
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="vless_backup_$timestamp"
    local backup_path="$BACKUP_DIR/$backup_name"

    # Create temporary backup directory
    print_step "Creating backup: $backup_name"
    mkdir -p "$backup_path"

    # Backup configuration files
    print_step "Backing up configuration files..."
    if [ -d "$VLESS_HOME/config" ]; then
        cp -r "$VLESS_HOME/config" "$backup_path/" 2>/dev/null || true
    fi
    if [ -f "$VLESS_HOME/.env" ]; then
        cp "$VLESS_HOME/.env" "$backup_path/" 2>/dev/null || true
    fi
    if [ -f "$VLESS_HOME/docker-compose.yml" ]; then
        cp "$VLESS_HOME/docker-compose.yml" "$backup_path/" 2>/dev/null || true
    fi

    # Backup user data
    print_step "Backing up user data..."
    if [ -d "$VLESS_HOME/data" ]; then
        cp -r "$VLESS_HOME/data" "$backup_path/" 2>/dev/null || true
    fi

    # Backup scripts
    print_step "Backing up scripts..."
    if [ -d "$VLESS_HOME/scripts" ]; then
        cp -r "$VLESS_HOME/scripts" "$backup_path/" 2>/dev/null || true
    fi

    # Backup templates
    if [ -d "$VLESS_HOME/templates" ]; then
        cp -r "$VLESS_HOME/templates" "$backup_path/"
    fi

    # Create backup info file
    cat > "$backup_path/backup_info.txt" << EOF
Backup Information
==================
Timestamp: $(date -Iseconds)
Hostname: $(hostname)
VLESS Home: $VLESS_HOME
Docker Status: $(docker ps --format "table {{.Names}}\t{{.Status}}" | grep xray-server || echo "Not running")

Backup Contents:
- Configuration files
- User database
- X25519 keys
- Scripts
- Templates
- Environment settings

Restore Instructions:
1. Extract this backup to /opt/vless/
2. Set proper permissions
3. Restart Docker container
EOF

    # Create compressed archive
    print_step "Compressing backup..."
    cd "$BACKUP_DIR"
    tar -czf "${backup_name}.tar.gz" "$backup_name"
    rm -rf "$backup_name"

    # Calculate backup size
    local backup_size=$(du -h "${backup_name}.tar.gz" | cut -f1)

    print_success "Backup created successfully"
    print_info "Location: $BACKUP_DIR/${backup_name}.tar.gz"
    print_info "Size: $backup_size"

    # Rotate old backups (keep last 30)
    rotate_backups

    return 0
}

# Rotate old backups function
rotate_backups() {
    print_step "Rotating old backups..."
    local backup_count=$(ls -1 "$BACKUP_DIR"/vless_backup_*.tar.gz 2>/dev/null | wc -l)
    if [ $backup_count -gt 30 ]; then
        local old_backups=$(ls -1t "$BACKUP_DIR"/vless_backup_*.tar.gz | tail -n +31)
        for old_backup in $old_backups; do
            rm "$old_backup"
            print_info "Removed old backup: $(basename $old_backup)"
        done
    fi
}

# List backups function
list_backups() {
    print_header "Available Backups"

    local backups=($(ls -1t "$BACKUP_DIR"/vless_backup_*.tar.gz 2>/dev/null))

    if [ ${#backups[@]} -eq 0 ]; then
        print_warning "No backups found"
        return 1
    fi

    echo "Recent backups:"
    for i in "${!backups[@]}"; do
        local backup_file="${backups[$i]}"
        local size=$(du -h "$backup_file" | cut -f1)
        local date=$(basename "$backup_file" | sed 's/vless_backup_//;s/.tar.gz//' | sed 's/_/ /')
        echo "  $((i+1))) $date ($size)"
        if [ $i -eq 9 ]; then
            break
        fi
    done

    echo ""
    print_info "Total backups: ${#backups[@]}"
    local total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
    print_info "Total size: $total_size"

    return 0
}

# Restore function
restore_backup() {
    print_header "Restore from Backup"

    # List available backups
    local backups=($(ls -1t "$BACKUP_DIR"/vless_backup_*.tar.gz 2>/dev/null))

    if [ ${#backups[@]} -eq 0 ]; then
        print_error "No backups found"
        return 1
    fi

    echo "Available backups:"
    for i in "${!backups[@]}"; do
        local backup_file="${backups[$i]}"
        local size=$(du -h "$backup_file" | cut -f1)
        local date=$(basename "$backup_file" | sed 's/vless_backup_//;s/.tar.gz//' | sed 's/_/ /')
        echo "  $((i+1))) $date ($size)"
        if [ $i -eq 9 ]; then
            if [ ${#backups[@]} -gt 10 ]; then
                echo "  ... and $((${#backups[@]} - 10)) more"
            fi
            break
        fi
    done

    echo ""
    read -p "Select backup to restore [1-${#backups[@]}] or 0 to cancel: " choice

    if [ "$choice" == "0" ]; then
        print_info "Restore cancelled"
        return 0
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#backups[@]} ]; then
        local selected_backup="${backups[$((choice-1))]}"

        print_warning "This will restore: $(basename $selected_backup)"
        print_warning "Current configuration will be overwritten!"

        if confirm_action "Continue with restore?" "n"; then
            # Stop service
            print_step "Stopping Xray service..."
            cd "$VLESS_HOME"
            docker-compose down 2>/dev/null || true

            # Create backup of current state
            print_step "Backing up current state before restore..."
            create_backup

            # Extract backup
            print_step "Extracting backup..."
            local temp_dir=$(mktemp -d)
            tar -xzf "$selected_backup" -C "$temp_dir"

            # Find the backup directory name
            local backup_dir=$(ls -d "$temp_dir"/vless_backup_* | head -1)

            if [ -z "$backup_dir" ]; then
                print_error "Invalid backup archive structure"
                rm -rf "$temp_dir"
                return 1
            fi

            # Restore files
            print_step "Restoring files..."
            for item in config data scripts templates docker-compose.yml .env; do
                if [ -e "$backup_dir/$item" ]; then
                    rm -rf "$VLESS_HOME/$item" 2>/dev/null || true
                    cp -r "$backup_dir/$item" "$VLESS_HOME/"
                    print_info "Restored: $item"
                fi
            done

            # Clean up temp directory
            rm -rf "$temp_dir"

            # Fix permissions
            print_step "Setting permissions..."
            chmod 750 "$VLESS_HOME/config" "$VLESS_HOME/scripts" 2>/dev/null || true
            chmod 700 "$VLESS_HOME/data" "$VLESS_HOME/backups" 2>/dev/null || true
            if [ -d "$VLESS_HOME/data/keys" ]; then
                chmod 700 "$VLESS_HOME/data/keys"
                chmod 600 "$VLESS_HOME/data/keys/"* 2>/dev/null || true
            fi
            chmod 600 "$VLESS_HOME/config/config.json" 2>/dev/null || true
            chmod 600 "$VLESS_HOME/data/users.json" 2>/dev/null || true
            chmod 600 "$VLESS_HOME/.env" 2>/dev/null || true
            chmod 750 "$VLESS_HOME/scripts/"*.sh 2>/dev/null || true

            # Restart service
            print_step "Starting Xray service..."
            cd "$VLESS_HOME"
            docker-compose up -d

            if wait_for_service "xray-server" 30; then
                print_success "Restore completed successfully"
            else
                print_error "Service failed to start after restore"
                print_info "Check logs with: docker-compose logs xray-server"
                return 1
            fi
        else
            print_info "Restore cancelled"
        fi
    else
        print_error "Invalid selection"
        return 1
    fi
}

# Delete old backups
cleanup_old_backups() {
    print_header "Cleanup Old Backups"

    local backups=($(ls -1t "$BACKUP_DIR"/vless_backup_*.tar.gz 2>/dev/null))

    if [ ${#backups[@]} -eq 0 ]; then
        print_warning "No backups found"
        return 1
    fi

    print_info "Current backups: ${#backups[@]}"
    local total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
    print_info "Total size: $total_size"

    echo ""
    echo "Cleanup options:"
    echo "1) Keep last 7 backups"
    echo "2) Keep last 14 backups"
    echo "3) Keep last 30 backups"
    echo "4) Custom number"
    echo "5) Cancel"
    echo ""
    read -p "Select option [1-5]: " choice

    local keep_count
    case $choice in
        1) keep_count=7 ;;
        2) keep_count=14 ;;
        3) keep_count=30 ;;
        4)
            read -p "Number of backups to keep: " keep_count
            if ! [[ "$keep_count" =~ ^[0-9]+$ ]] || [ "$keep_count" -lt 1 ]; then
                print_error "Invalid number"
                return 1
            fi
            ;;
        5)
            print_info "Cleanup cancelled"
            return 0
            ;;
        *)
            print_error "Invalid option"
            return 1
            ;;
    esac

    if [ ${#backups[@]} -le $keep_count ]; then
        print_info "Number of backups (${#backups[@]}) is already within limit ($keep_count)"
        return 0
    fi

    local delete_count=$((${#backups[@]} - keep_count))
    print_warning "This will delete $delete_count oldest backup(s)"

    if confirm_action "Continue?" "n"; then
        local old_backups=$(ls -1t "$BACKUP_DIR"/vless_backup_*.tar.gz | tail -n +$((keep_count + 1)))
        for old_backup in $old_backups; do
            rm "$old_backup"
            print_info "Deleted: $(basename $old_backup)"
        done
        print_success "Cleanup completed. Kept $keep_count most recent backup(s)"

        local new_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
        print_info "New total size: $new_size"
    else
        print_info "Cleanup cancelled"
    fi
}

# Main menu
main_menu() {
    while true; do
        print_header "VLESS Backup Manager"

        echo "1) Create new backup"
        echo "2) List backups"
        echo "3) Restore from backup"
        echo "4) Cleanup old backups"
        echo "5) Exit"
        echo ""
        read -p "Select option [1-5]: " choice

        case $choice in
            1)
                create_backup
                echo ""
                read -p "Press Enter to continue..."
                ;;
            2)
                list_backups
                echo ""
                read -p "Press Enter to continue..."
                ;;
            3)
                restore_backup
                echo ""
                read -p "Press Enter to continue..."
                ;;
            4)
                cleanup_old_backups
                echo ""
                read -p "Press Enter to continue..."
                ;;
            5)
                print_info "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
        clear
    done
}

# Handle command line arguments
if [ $# -gt 0 ]; then
    case "$1" in
        --auto)
            # Auto mode for scripts
            create_backup
            ;;
        create)
            create_backup
            ;;
        list)
            list_backups
            ;;
        restore)
            restore_backup
            ;;
        cleanup)
            cleanup_old_backups
            ;;
        *)
            print_error "Unknown command: $1"
            echo "Usage: $0 [create|list|restore|cleanup|--auto]"
            exit 1
            ;;
    esac
else
    # Run interactive menu
    main_menu
fi