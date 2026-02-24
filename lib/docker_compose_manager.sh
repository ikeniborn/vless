#!/bin/bash
# lib/docker_compose_manager.sh
#
# Docker Compose Configuration Manager (VLESS v4.3)
# Dynamic port management for nginx reverse proxy container
#
# Features:
# - Add/remove ports dynamically via heredoc regeneration
# - Atomic operations with backups
# - PRD v4.1 compliant (heredoc-based, no yq dependency)
# - Container reload after changes
# - v4.3: Port range 9443-9452 for HAProxy unified architecture
#
# Version: 4.3.0
# Author: VLESS Development Team
# Date: 2025-10-18

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_COMPOSE_PATH="/opt/familytraffic/docker-compose.yml"
DOCKER_COMPOSE_BACKUP_DIR="/opt/familytraffic/data/backups"

# Source docker compose generator (heredoc-based)
source "${SCRIPT_DIR}/docker_compose_generator.sh"

# Logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [docker-compose-manager] $*" >&2
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [docker-compose-manager] ERROR: $*" >&2
}

# ============================================================================
# Function: backup_docker_compose
# Description: Creates backup of docker-compose.yml
#
# Returns:
#   0 on success, 1 on failure
#   Prints backup file path
# ============================================================================
backup_docker_compose() {
    if [ ! -f "$DOCKER_COMPOSE_PATH" ]; then
        log_error "docker-compose.yml not found: $DOCKER_COMPOSE_PATH"
        return 1
    fi

    mkdir -p "$DOCKER_COMPOSE_BACKUP_DIR"

    local backup_file="${DOCKER_COMPOSE_BACKUP_DIR}/docker-compose_$(date +%Y%m%d_%H%M%S).yml"

    if cp "$DOCKER_COMPOSE_PATH" "$backup_file"; then
        log "✅ Backup created: $backup_file"
        echo "$backup_file"
        return 0
    else
        log_error "Failed to create backup"
        return 1
    fi
}

# ============================================================================
# Function: add_nginx_port
# Description: Adds port mapping to nginx service via heredoc regeneration
#
# Parameters:
#   $1 - port: Port number to add (e.g., 9443, v4.3 range: 9443-9452)
#
# Returns:
#   0 on success, 1 on failure
# ============================================================================
add_nginx_port() {
    local port="$1"

    if [[ -z "$port" ]]; then
        log_error "Missing port parameter"
        return 1
    fi

    # Validate port range (v4.3: 9443-9452)
    if [ "$port" -lt 9443 ] || [ "$port" -gt 9452 ]; then
        log_error "Port must be in range 9443-9452"
        return 1
    fi

    log "Adding port $port to nginx service..."

    # Backup first
    backup_docker_compose > /dev/null

    # Get current nginx ports from existing docker-compose.yml
    local current_ports_raw
    current_ports_raw=$(get_current_nginx_ports)

    # Convert to array
    local current_ports=()
    if [[ -n "$current_ports_raw" ]]; then
        while IFS= read -r p; do
            current_ports+=("$p")
        done <<< "$current_ports_raw"
    fi

    # Check if port already exists
    for p in "${current_ports[@]}"; do
        if [[ "$p" == "$port" ]]; then
            log "Port $port already exists in nginx service"
            return 0
        fi
    done

    # Add new port to array
    current_ports+=("$port")

    # Regenerate docker-compose.yml with updated port list
    if generate_docker_compose "${current_ports[@]}"; then
        log "✅ Port $port added to nginx service (heredoc regeneration)"
        return 0
    else
        log_error "Failed to regenerate docker-compose.yml with port $port"

        # Restore backup on failure
        local latest_backup
        latest_backup=$(ls -t "${DOCKER_COMPOSE_BACKUP_DIR}"/docker-compose_*.yml 2>/dev/null | head -1)
        if [[ -f "$latest_backup" ]]; then
            cp "$latest_backup" "$DOCKER_COMPOSE_PATH"
            log "  Backup restored from: $latest_backup"
        fi

        return 1
    fi
}

# ============================================================================
# Function: remove_nginx_port
# Description: Removes port mapping from nginx service via heredoc regeneration
#
# Parameters:
#   $1 - port: Port number to remove (e.g., 9443, v4.3 range: 9443-9452)
#
# Returns:
#   0 on success, 1 on failure
# ============================================================================
remove_nginx_port() {
    local port="$1"

    if [[ -z "$port" ]]; then
        log_error "Missing port parameter"
        return 1
    fi

    log "Removing port $port from nginx service..."

    # Backup first
    backup_docker_compose > /dev/null

    # Get current nginx ports
    local current_ports_raw
    current_ports_raw=$(get_current_nginx_ports)

    # Convert to array
    local current_ports=()
    if [[ -n "$current_ports_raw" ]]; then
        while IFS= read -r p; do
            current_ports+=("$p")
        done <<< "$current_ports_raw"
    fi

    # Check if port exists
    local port_found=false
    for p in "${current_ports[@]}"; do
        if [[ "$p" == "$port" ]]; then
            port_found=true
            break
        fi
    done

    if [[ "$port_found" == "false" ]]; then
        log "Port $port not found in nginx service"
        return 0
    fi

    # Remove port from array
    local updated_ports=()
    for p in "${current_ports[@]}"; do
        if [[ "$p" != "$port" ]]; then
            updated_ports+=("$p")
        fi
    done

    # Regenerate docker-compose.yml with updated port list
    if generate_docker_compose "${updated_ports[@]}"; then
        log "✅ Port $port removed from nginx service (heredoc regeneration)"
        return 0
    else
        log_error "Failed to regenerate docker-compose.yml after removing port $port"

        # Restore backup on failure
        local latest_backup
        latest_backup=$(ls -t "${DOCKER_COMPOSE_BACKUP_DIR}"/docker-compose_*.yml 2>/dev/null | head -1)
        if [[ -f "$latest_backup" ]]; then
            cp "$latest_backup" "$DOCKER_COMPOSE_PATH"
            log "  Backup restored from: $latest_backup"
        fi

        return 1
    fi
}

# ============================================================================
# Function: list_nginx_ports
# Description: Lists all port mappings for nginx service (uses generator helper)
#
# Returns:
#   Port list (one per line)
# ============================================================================
list_nginx_ports() {
    if [ ! -f "$DOCKER_COMPOSE_PATH" ]; then
        log_error "docker-compose.yml not found: $DOCKER_COMPOSE_PATH"
        return 1
    fi

    # Use get_current_nginx_ports() from docker_compose_generator.sh
    local ports
    ports=$(get_current_nginx_ports)

    if [[ -z "$ports" ]]; then
        log "No ports configured for nginx service"
        return 0
    fi

    echo "$ports"
    return 0
}

# ============================================================================
# Function: get_next_available_port
# Description: Finds next available port in range 9443-9452 for nginx
#
# Returns:
#   Next available port number to stdout
#   Returns 1 if all ports are occupied
#
# Algorithm:
#   1. Get current nginx ports
#   2. Check range 9443-9452 sequentially
#   3. Return first unoccupied port
#   4. Error if all 10 ports are used
# ============================================================================
get_next_available_port() {
    local current_ports_raw
    current_ports_raw=$(get_current_nginx_ports)

    # Convert to array for easier checking
    local current_ports=()
    if [[ -n "$current_ports_raw" ]]; then
        while IFS= read -r p; do
            current_ports+=("$p")
        done <<< "$current_ports_raw"
    fi

    # Check ports 9443-9452 sequentially
    for port in {9443..9452}; do
        local port_occupied=false

        for used_port in "${current_ports[@]}"; do
            if [[ "$used_port" == "$port" ]]; then
                port_occupied=true
                break
            fi
        done

        if [[ "$port_occupied" == "false" ]]; then
            echo "$port"
            return 0
        fi
    done

    # All ports occupied
    log_error "All ports in range 9443-9452 are occupied (max 10 reverse proxies)"
    return 1
}

# ============================================================================
# Function: reload_nginx_container
# Description: Reloads nginx container with docker-compose
#
# Returns:
#   0 on success, 1 on failure
# ============================================================================
reload_nginx_container() {
    log "Reloading nginx container..."

    local compose_dir
    compose_dir=$(dirname "$DOCKER_COMPOSE_PATH")

    # Use docker compose (v2) or docker-compose (v1)
    local compose_cmd="docker compose"
    if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null 2>&1; then
        compose_cmd="docker-compose"
    fi

    if cd "$compose_dir" && $compose_cmd up -d nginx 2>&1; then
        log "✅ Nginx container reloaded successfully"
        return 0
    else
        log_error "Failed to reload nginx container"
        return 1
    fi
}

# ============================================================================
# Function: validate_docker_compose
# Description: Validates docker-compose.yml syntax
#
# Returns:
#   0 if valid, 1 if invalid
# ============================================================================
validate_docker_compose() {
    if [ ! -f "$DOCKER_COMPOSE_PATH" ]; then
        log_error "docker-compose.yml not found: $DOCKER_COMPOSE_PATH"
        return 1
    fi

    log "Validating docker-compose.yml..."

    local compose_dir
    compose_dir=$(dirname "$DOCKER_COMPOSE_PATH")

    local compose_cmd="docker compose"
    if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null 2>&1; then
        compose_cmd="docker-compose"
    fi

    if cd "$compose_dir" && $compose_cmd config > /dev/null 2>&1; then
        log "✅ docker-compose.yml is valid"
        return 0
    else
        log_error "❌ docker-compose.yml has invalid syntax"
        return 1
    fi
}

# ============================================================================
# Main execution (for testing)
# ============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly (not sourced)

    if [ $# -lt 1 ]; then
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  add-port <port>       - Add port to nginx service"
        echo "  remove-port <port>    - Remove port from nginx service"
        echo "  list-ports            - List all nginx ports"
        echo "  next-port             - Get next available port (9443-9452)"
        echo "  reload                - Reload nginx container"
        echo "  validate              - Validate docker-compose.yml"
        exit 1
    fi

    command="$1"
    shift

    case "$command" in
        add-port)
            add_nginx_port "$@"
            ;;
        remove-port)
            remove_nginx_port "$@"
            ;;
        list-ports)
            list_nginx_ports
            ;;
        next-port)
            get_next_available_port
            ;;
        reload)
            reload_nginx_container
            ;;
        validate)
            validate_docker_compose
            ;;
        *)
            log_error "Unknown command: $command"
            exit 1
            ;;
    esac
fi
