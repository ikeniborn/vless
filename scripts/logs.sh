#!/bin/bash

set -e

# Script directory - resolve symlinks to get real path
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
VLESS_HOME="${VLESS_HOME:-/opt/vless}"

# Load libraries
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/utils.sh"

# Check root
check_root

# Check if VLESS is installed
if [ ! -d "$VLESS_HOME" ]; then
    print_error "VLESS is not installed. Please run install.sh first."
    exit 1
fi

# Log management functions
show_logs() {
    local lines=${1:-100}
    print_header "Xray Logs (Last $lines lines)"
    
    cd "$VLESS_HOME"
    
    # Check if container is running
    if ! docker ps | grep -q "xray-server"; then
        print_error "Xray container is not running"
        return 1
    fi
    
    print_info "Container logs:"
    echo "----------------------------------------"
    docker-compose logs --tail=$lines xray-server
    echo "----------------------------------------"
}

follow_logs() {
    print_header "Following Xray Logs (Ctrl+C to stop)"
    
    cd "$VLESS_HOME"
    
    # Check if container is running
    if ! docker ps | grep -q "xray-server"; then
        print_error "Xray container is not running"
        return 1
    fi
    
    print_info "Following logs in real-time..."
    docker-compose logs -f xray-server
}

export_logs() {
    print_header "Export Logs"
    
    cd "$VLESS_HOME"
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local export_file="$VLESS_HOME/logs/xray_logs_$timestamp.log"
    
    print_step "Exporting logs to file..."
    
    # Export all logs
    docker-compose logs --no-color xray-server > "$export_file" 2>&1
    
    # Compress if large
    local file_size=$(stat -c%s "$export_file" 2>/dev/null || stat -f%z "$export_file" 2>/dev/null || echo 0)
    if [ $file_size -gt 10485760 ]; then  # 10MB
        print_step "Compressing large log file..."
        gzip "$export_file"
        export_file="${export_file}.gz"
    fi
    
    print_success "Logs exported to: $export_file"
    
    # Show file info
    if [ -f "$export_file" ]; then
        local size=$(du -h "$export_file" | cut -f1)
        print_info "File size: $size"
    fi
}

clear_logs() {
    print_header "Clear Logs"
    
    print_warning "This will clear all Docker logs for the Xray container"
    
    if ! confirm_action "Are you sure you want to clear logs?" "n"; then
        print_info "Operation cancelled"
        return 0
    fi
    
    cd "$VLESS_HOME"
    
    # Export logs before clearing
    print_step "Exporting current logs before clearing..."
    export_logs
    
    # Get container ID
    local container_id=$(docker ps -q -f name=xray-server)
    if [ -z "$container_id" ]; then
        print_error "Xray container is not running"
        return 1
    fi
    
    # Clear Docker logs
    print_step "Clearing Docker logs..."
    truncate -s 0 "/var/lib/docker/containers/${container_id}"*/*.log 2>/dev/null || {
        print_warning "Could not clear Docker logs directly"
        print_info "Logs will be rotated on next restart"
    }
    
    # Clear local log files if they exist
    if [ -d "$VLESS_HOME/logs" ]; then
        find "$VLESS_HOME/logs" -name "*.log" -type f -delete
        print_success "Local log files cleared"
    fi
    
    print_success "Logs cleared successfully"
}

show_stats() {
    print_header "Service Statistics"
    
    cd "$VLESS_HOME"
    
    # Container status
    print_info "Container Status:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep xray-server || echo "Not running"
    
    echo ""
    
    # Resource usage
    print_info "Resource Usage:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" xray-server || echo "Not available"
    
    echo ""
    
    # Connection test
    print_info "Service Health:"
    if docker exec xray-server nc -z localhost 443 2>/dev/null; then
        print_success "Port 443 is listening"
    else
        print_error "Port 443 is not responding"
    fi
    
    # User count
    if [ -f "$VLESS_HOME/data/users.json" ]; then
        local user_count=$(jq '.users | length' "$VLESS_HOME/data/users.json")
        print_info "Active users: $user_count"
    fi
    
    # Disk usage
    echo ""
    print_info "Disk Usage:"
    du -sh "$VLESS_HOME"/* 2>/dev/null | sort -rh | head -10
}

filter_logs() {
    print_header "Filter Logs"
    
    echo "Filter options:"
    echo "1) Errors only"
    echo "2) Warnings and errors"
    echo "3) Connection events"
    echo "4) Search for specific text"
    echo "5) Back to menu"
    echo ""
    read -p "Select filter [1-5]: " choice
    
    cd "$VLESS_HOME"
    
    case $choice in
        1)
            print_info "Showing errors only:"
            docker-compose logs xray-server | grep -i error | tail -50
            ;;
        2)
            print_info "Showing warnings and errors:"
            docker-compose logs xray-server | grep -iE "(warning|error)" | tail -50
            ;;
        3)
            print_info "Showing connection events:"
            docker-compose logs xray-server | grep -iE "(accepted|connection|connected)" | tail -50
            ;;
        4)
            read -p "Enter search text: " search_text
            if [ -n "$search_text" ]; then
                print_info "Searching for: $search_text"
                docker-compose logs xray-server | grep -i "$search_text" | tail -50
            fi
            ;;
        5)
            return 0
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
}

# Main menu
main_menu() {
    while true; do
        print_header "VLESS Logs Manager"
        
        echo "1) Show recent logs (last 100 lines)"
        echo "2) Follow logs in real-time"
        echo "3) Filter logs"
        echo "4) Export logs to file"
        echo "5) Show service statistics"
        echo "6) Clear logs"
        echo "7) Exit"
        echo ""
        read -p "Select option [1-7]: " choice
        
        case $choice in
            1)
                read -p "Number of lines to show [100]: " lines
                lines=${lines:-100}
                show_logs $lines
                echo ""
                read -p "Press Enter to continue..."
                ;;
            2)
                follow_logs
                ;;
            3)
                filter_logs
                echo ""
                read -p "Press Enter to continue..."
                ;;
            4)
                export_logs
                echo ""
                read -p "Press Enter to continue..."
                ;;
            5)
                show_stats
                echo ""
                read -p "Press Enter to continue..."
                ;;
            6)
                clear_logs
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

# Quick mode for command line arguments
if [ $# -gt 0 ]; then
    case "$1" in
        show)
            show_logs ${2:-100}
            ;;
        follow|tail)
            follow_logs
            ;;
        export)
            export_logs
            ;;
        stats)
            show_stats
            ;;
        clear)
            clear_logs
            ;;
        *)
            print_error "Unknown command: $1"
            echo "Usage: $0 [show|follow|export|stats|clear]"
            exit 1
            ;;
    esac
else
    # Run interactive menu
    main_menu
fi