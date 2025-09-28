#!/bin/bash

set -e

# Script directory - resolve symlinks to get real path
if command -v readlink >/dev/null 2>&1; then
    SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

VLESS_HOME="${VLESS_HOME:-/opt/vless}"

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

# Check for updates function
check_updates() {
    print_header "Checking for Updates"

    # Check current version
    print_step "Checking current Xray version..."
    local current_version=$(docker inspect xray-server 2>/dev/null | jq -r '.[0].Config.Image' | cut -d: -f2 || echo "unknown")
    print_info "Current version: $current_version"

    # Pull latest image
    print_step "Checking for latest version..."
    docker pull teddysun/xray:latest > /dev/null 2>&1

    # Get new version info
    local new_version=$(docker inspect teddysun/xray:latest 2>/dev/null | jq -r '.[0].RepoDigests[0]' | cut -d@ -f2 | cut -c1-12 || echo "latest")
    print_info "Latest version: $new_version"

    if [ "$current_version" == "$new_version" ]; then
        print_success "You are already running the latest version"
        return 1
    else
        print_warning "Update available!"
        return 0
    fi
}

# Update function
perform_update() {
    print_header "Performing Update"

    # Create backup before update
    print_step "Creating backup before update..."
    if "$SCRIPT_DIR/backup.sh" --auto; then
        print_success "Backup created successfully"
    else
        print_warning "Backup failed"
        if ! confirm_action "Continue without backup?" "n"; then
            print_info "Update cancelled"
            return 1
        fi
    fi

    # Change to VLESS directory
    cd "$VLESS_HOME"

    # Pull latest image
    print_step "Pulling latest Xray image..."
    if docker pull teddysun/xray:latest; then
        print_success "Latest image pulled successfully"
    else
        print_error "Failed to pull latest image"
        return 1
    fi

    # Stop current container
    print_step "Stopping current container..."
    if docker-compose down; then
        print_success "Container stopped"
    else
        print_error "Failed to stop container"
        return 1
    fi

    # Start with new image
    print_step "Starting container with new image..."
    if docker-compose up -d; then
        print_success "Container started with new image"
    else
        print_error "Failed to start container"
        print_info "Trying to restore previous state..."
        docker-compose up -d
        return 1
    fi

    # Wait for service to be ready
    if wait_for_service "xray-server" 30; then
        print_success "Service is running"
    else
        print_error "Service failed to start properly"
        return 1
    fi

    # Verify service health
    print_step "Verifying service health..."
    if docker exec xray-server nc -z localhost 443 2>/dev/null; then
        print_success "Service is healthy and accepting connections"
    else
        print_warning "Service may not be fully operational"
    fi

    # Clean up old images
    print_step "Cleaning up old images..."
    if docker image prune -f > /dev/null 2>&1; then
        print_success "Old images cleaned up"
    fi

    print_success "Update completed successfully!"
    return 0
}

# Force update function
force_update() {
    print_header "Force Update"

    print_warning "This will update Xray even if you're already on the latest version"

    if ! confirm_action "Continue with force update?" "n"; then
        print_info "Force update cancelled"
        return 1
    fi

    perform_update
}

# Rollback function
rollback_update() {
    print_header "Rollback to Previous Version"

    print_warning "This will restore the most recent backup"

    if ! confirm_action "Continue with rollback?" "n"; then
        print_info "Rollback cancelled"
        return 1
    fi

    # Call backup script with restore option
    "$SCRIPT_DIR/backup.sh" restore
}

# Check service status
check_status() {
    print_header "Service Status"

    cd "$VLESS_HOME"

    # Container status
    print_info "Container Status:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep xray-server || echo "Not running"

    echo ""

    # Version info
    local version=$(docker inspect xray-server 2>/dev/null | jq -r '.[0].Config.Image' || echo "N/A")
    print_info "Image version: $version"

    # Service health check
    echo ""
    print_info "Service Health:"
    if docker exec xray-server nc -z localhost 443 2>/dev/null; then
        print_success "Port 443 is listening"
    else
        print_error "Port 443 is not responding"
    fi

    # Last update time (from most recent backup)
    if [ -d "$VLESS_HOME/backups" ]; then
        local last_backup=$(ls -1t "$VLESS_HOME/backups"/vless_backup_*.tar.gz 2>/dev/null | head -1)
        if [ -n "$last_backup" ]; then
            local backup_date=$(basename "$last_backup" | sed 's/vless_backup_//;s/.tar.gz//' | sed 's/_/ /')
            print_info "Last backup: $backup_date"
        fi
    fi
}

# Clean Docker resources
clean_docker() {
    print_header "Clean Docker Resources"

    echo "This will remove:"
    echo "- Stopped containers"
    echo "- Unused networks"
    echo "- Dangling images"
    echo "- Build cache"
    echo ""

    if ! confirm_action "Continue with cleanup?" "n"; then
        print_info "Cleanup cancelled"
        return 1
    fi

    print_step "Cleaning Docker resources..."

    # Remove stopped containers
    print_info "Removing stopped containers..."
    docker container prune -f

    # Remove unused networks
    print_info "Removing unused networks..."
    docker network prune -f

    # Remove dangling images
    print_info "Removing dangling images..."
    docker image prune -f

    # Remove build cache
    print_info "Removing build cache..."
    docker builder prune -f

    # Show disk usage
    echo ""
    print_info "Docker disk usage:"
    docker system df

    print_success "Cleanup completed"
}

# Main menu
main_menu() {
    while true; do
        print_header "VLESS Update Manager"

        echo "1) Check for updates"
        echo "2) Update Xray"
        echo "3) Force update"
        echo "4) Rollback to previous version"
        echo "5) Check service status"
        echo "6) Clean Docker resources"
        echo "7) Exit"
        echo ""
        read -p "Select option [1-7]: " choice

        case $choice in
            1)
                check_updates
                echo ""
                read -p "Press Enter to continue..."
                ;;
            2)
                if check_updates; then
                    echo ""
                    if confirm_action "Do you want to update now?" "y"; then
                        perform_update
                    fi
                fi
                echo ""
                read -p "Press Enter to continue..."
                ;;
            3)
                force_update
                echo ""
                read -p "Press Enter to continue..."
                ;;
            4)
                rollback_update
                echo ""
                read -p "Press Enter to continue..."
                ;;
            5)
                check_status
                echo ""
                read -p "Press Enter to continue..."
                ;;
            6)
                clean_docker
                echo ""
                read -p "Press Enter to continue..."
                ;;
            7)
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
        check)
            check_updates
            ;;
        update)
            perform_update
            ;;
        force)
            force_update
            ;;
        rollback)
            rollback_update
            ;;
        status)
            check_status
            ;;
        clean)
            clean_docker
            ;;
        *)
            print_error "Unknown command: $1"
            echo "Usage: $0 [check|update|force|rollback|status|clean]"
            exit 1
            ;;
    esac
else
    # Run interactive menu
    main_menu
fi