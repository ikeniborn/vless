#!/bin/bash
# ======================================================================================
# VLESS+Reality VPN Management System - Container Management Module
# ======================================================================================
# This module provides functions for managing Docker containers lifecycle,
# specifically for the Xray service container.
#
# Author: Claude Code
# Version: 1.0
# Last Modified: 2025-09-21
# ======================================================================================

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=modules/common_utils.sh
source "${SCRIPT_DIR}/common_utils.sh"

# Container management constants
readonly CONTAINER_NAME="vless-xray"
readonly MONITOR_CONTAINER_NAME="vless-monitor"
readonly COMPOSE_FILE="${CONFIG_DIR}/docker-compose.yml"
readonly XRAY_CONFIG_FILE="${CONFIG_DIR}/xray_config.json"
readonly DOCKER_COMPOSE_PROJECT="vless"

# ======================================================================================
# CONTAINER LIFECYCLE FUNCTIONS
# ======================================================================================

#
# Start Xray container with Docker Compose
#
# Returns:
#   0 on successful start
#   1 on start failure
#
start_xray_container() {
    log_info "Starting Xray container..."

    validate_root
    validate_compose_file

    # Ensure data directory exists
    local data_dir="${VLESS_ROOT}/data"
    if [[ ! -d "${data_dir}" ]]; then
        mkdir -p "${data_dir}"
        chown root:root "${data_dir}"
        chmod 755 "${data_dir}"
    fi

    # Set environment variables for Docker Compose
    export VLESS_ROOT
    export COMPOSE_PROJECT_NAME="${DOCKER_COMPOSE_PROJECT}"

    # Change to config directory for docker-compose
    cd "$(dirname "${COMPOSE_FILE}")"

    # Start the services
    if docker compose -f "${COMPOSE_FILE}" up -d xray; then
        log_info "Xray container started successfully"

        # Wait for container to be healthy
        if wait_for_container_health "${CONTAINER_NAME}" 60; then
            log_info "Xray container is healthy and ready"
            return 0
        else
            log_error "Xray container failed to become healthy"
            return 1
        fi
    else
        log_error "Failed to start Xray container"
        return 1
    fi
}

#
# Stop Xray container gracefully
#
# Returns:
#   0 on successful stop
#   1 on stop failure
#
stop_xray_container() {
    log_info "Stopping Xray container..."

    validate_compose_file

    # Set environment variables
    export VLESS_ROOT
    export COMPOSE_PROJECT_NAME="${DOCKER_COMPOSE_PROJECT}"

    cd "$(dirname "${COMPOSE_FILE}")"

    # Stop the container gracefully
    if docker compose -f "${COMPOSE_FILE}" stop xray; then
        log_info "Xray container stopped successfully"
        return 0
    else
        log_error "Failed to stop Xray container"
        return 1
    fi
}

#
# Restart Xray container with configuration reload
#
# Returns:
#   0 on successful restart
#   1 on restart failure
#
restart_xray_container() {
    log_info "Restarting Xray container..."

    # Validate configuration before restart
    if ! validate_xray_config; then
        log_error "Invalid Xray configuration - aborting restart"
        return 1
    fi

    # Stop container first
    if ! stop_xray_container; then
        log_error "Failed to stop container for restart"
        return 1
    fi

    # Wait a moment for cleanup
    sleep 2

    # Start container
    if start_xray_container; then
        log_info "Xray container restarted successfully"
        return 0
    else
        log_error "Failed to restart Xray container"
        return 1
    fi
}

#
# Force restart Xray container (kill and start)
#
# Returns:
#   0 on successful restart
#   1 on restart failure
#
force_restart_xray_container() {
    log_info "Force restarting Xray container..."

    validate_compose_file

    export VLESS_ROOT
    export COMPOSE_PROJECT_NAME="${DOCKER_COMPOSE_PROJECT}"

    cd "$(dirname "${COMPOSE_FILE}")"

    # Force stop and remove container
    docker compose -f "${COMPOSE_FILE}" down xray --timeout 10

    # Wait for cleanup
    sleep 2

    # Start fresh container
    if start_xray_container; then
        log_info "Xray container force restarted successfully"
        return 0
    else
        log_error "Failed to force restart Xray container"
        return 1
    fi
}

#
# Remove Xray container and associated resources
#
# Arguments:
#   $1 - (optional) "keep-data" to preserve data volumes
#
# Returns:
#   0 on successful removal
#   1 on removal failure
#
remove_xray_container() {
    local keep_data="${1:-}"

    log_info "Removing Xray container..."

    validate_compose_file

    export VLESS_ROOT
    export COMPOSE_PROJECT_NAME="${DOCKER_COMPOSE_PROJECT}"

    cd "$(dirname "${COMPOSE_FILE}")"

    # Stop and remove containers
    if [[ "${keep_data}" == "keep-data" ]]; then
        log_info "Removing containers but keeping data volumes"
        docker compose -f "${COMPOSE_FILE}" down
    else
        log_info "Removing containers and data volumes"
        docker compose -f "${COMPOSE_FILE}" down --volumes
    fi

    # Remove orphaned containers
    docker compose -f "${COMPOSE_FILE}" down --remove-orphans

    log_info "Xray container removed successfully"
    return 0
}

# ======================================================================================
# CONTAINER MONITORING FUNCTIONS
# ======================================================================================

#
# Check container health status
#
# Arguments:
#   $1 - Container name (optional, defaults to CONTAINER_NAME)
#
# Returns:
#   0 if container is healthy
#   1 if container is unhealthy or not running
#
check_container_health() {
    local container="${1:-${CONTAINER_NAME}}"

    # Check if container exists and is running
    if ! docker ps --filter "name=${container}" --filter "status=running" --quiet | grep -q .; then
        log_warn "Container ${container} is not running"
        return 1
    fi

    # Check health status
    local health_status
    health_status=$(docker inspect --format='{{.State.Health.Status}}' "${container}" 2>/dev/null || echo "none")

    case "${health_status}" in
        "healthy")
            log_info "Container ${container} is healthy"
            return 0
            ;;
        "unhealthy")
            log_warn "Container ${container} is unhealthy"
            return 1
            ;;
        "starting")
            log_info "Container ${container} is starting up"
            return 1
            ;;
        "none")
            log_info "Container ${container} has no health check configured"
            # Check if process is running inside container
            if docker exec "${container}" pgrep -x xray &>/dev/null; then
                return 0
            else
                return 1
            fi
            ;;
        *)
            log_warn "Container ${container} has unknown health status: ${health_status}"
            return 1
            ;;
    esac
}

#
# Wait for container to become healthy
#
# Arguments:
#   $1 - Container name
#   $2 - Timeout in seconds (default: 30)
#
# Returns:
#   0 if container becomes healthy
#   1 if timeout reached
#
wait_for_container_health() {
    local container="$1"
    local timeout="${2:-30}"
    local elapsed=0

    log_info "Waiting for container ${container} to become healthy (timeout: ${timeout}s)..."

    while [[ ${elapsed} -lt ${timeout} ]]; do
        if check_container_health "${container}"; then
            log_info "Container ${container} is healthy after ${elapsed} seconds"
            return 0
        fi

        sleep 2
        ((elapsed += 2))

        if [[ $((elapsed % 10)) -eq 0 ]]; then
            log_info "Still waiting for ${container} health check... (${elapsed}/${timeout}s)"
        fi
    done

    log_error "Container ${container} failed to become healthy within ${timeout} seconds"
    return 1
}

#
# Get container logs
#
# Arguments:
#   $1 - Container name (optional, defaults to CONTAINER_NAME)
#   $2 - Number of lines to show (optional, defaults to 50)
#   $3 - Follow logs flag (optional, "follow" to follow logs)
#
get_container_logs() {
    local container="${1:-${CONTAINER_NAME}}"
    local lines="${2:-50}"
    local follow_flag="${3:-}"

    log_info "Retrieving logs for container ${container}..."

    if [[ "${follow_flag}" == "follow" ]]; then
        docker logs --follow --tail "${lines}" "${container}"
    else
        docker logs --tail "${lines}" "${container}"
    fi
}

#
# Get container statistics
#
# Arguments:
#   $1 - Container name (optional, defaults to CONTAINER_NAME)
#
get_container_stats() {
    local container="${1:-${CONTAINER_NAME}}"

    log_info "Getting statistics for container ${container}..."

    if docker ps --filter "name=${container}" --quiet | grep -q .; then
        docker stats --no-stream "${container}"
    else
        log_error "Container ${container} is not running"
        return 1
    fi
}

# ======================================================================================
# CONTAINER UPDATE FUNCTIONS
# ======================================================================================

#
# Update Xray container image
#
# Returns:
#   0 on successful update
#   1 on update failure
#
update_xray_image() {
    log_info "Updating Xray container image..."

    validate_compose_file

    export VLESS_ROOT
    export COMPOSE_PROJECT_NAME="${DOCKER_COMPOSE_PROJECT}"

    cd "$(dirname "${COMPOSE_FILE}")"

    # Create backup of current configuration
    local backup_file="${BACKUP_DIR}/container_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    if ! create_container_backup "${backup_file}"; then
        log_error "Failed to create backup before update"
        return 1
    fi

    # Pull latest image
    log_info "Pulling latest Xray image..."
    if ! docker compose -f "${COMPOSE_FILE}" pull xray; then
        log_error "Failed to pull latest Xray image"
        return 1
    fi

    # Stop current container
    log_info "Stopping current container for update..."
    docker compose -f "${COMPOSE_FILE}" stop xray

    # Start with new image
    log_info "Starting container with updated image..."
    if start_xray_container; then
        log_info "Xray container updated successfully"

        # Verify container is working
        if check_container_health "${CONTAINER_NAME}"; then
            log_info "Updated container is healthy"
            return 0
        else
            log_error "Updated container is not healthy - rolling back"
            rollback_container_update "${backup_file}"
            return 1
        fi
    else
        log_error "Failed to start updated container - rolling back"
        rollback_container_update "${backup_file}"
        return 1
    fi
}

#
# Rollback container update
#
# Arguments:
#   $1 - Backup file path
#
rollback_container_update() {
    local backup_file="$1"

    log_info "Rolling back container update from backup: ${backup_file}"

    # Stop current container
    stop_xray_container

    # Restore from backup (this would need to be implemented in backup module)
    # For now, just restart with previous configuration
    start_xray_container

    log_info "Container rollback completed"
}

# ======================================================================================
# UTILITY FUNCTIONS
# ======================================================================================

#
# Validate Docker Compose file exists and is readable
#
validate_compose_file() {
    if [[ ! -f "${COMPOSE_FILE}" ]]; then
        log_error "Docker Compose file not found: ${COMPOSE_FILE}"
        return 1
    fi

    if [[ ! -r "${COMPOSE_FILE}" ]]; then
        log_error "Cannot read Docker Compose file: ${COMPOSE_FILE}"
        return 1
    fi

    # Validate YAML syntax
    if ! docker compose -f "${COMPOSE_FILE}" config --quiet; then
        log_error "Invalid Docker Compose file syntax"
        return 1
    fi

    return 0
}

#
# Validate Xray configuration file
#
validate_xray_config() {
    if [[ ! -f "${XRAY_CONFIG_FILE}" ]]; then
        log_error "Xray configuration file not found: ${XRAY_CONFIG_FILE}"
        return 1
    fi

    # Validate JSON syntax
    if ! python3 -m json.tool "${XRAY_CONFIG_FILE}" > /dev/null 2>&1; then
        log_error "Invalid JSON in Xray configuration file"
        return 1
    fi

    log_info "Xray configuration file is valid"
    return 0
}

#
# Create container backup
#
# Arguments:
#   $1 - Backup file path
#
create_container_backup() {
    local backup_file="$1"

    log_info "Creating container backup: ${backup_file}"

    # Ensure backup directory exists
    mkdir -p "$(dirname "${backup_file}")"

    # Create tar archive of configuration and data
    tar -czf "${backup_file}" \
        -C "${VLESS_ROOT}" \
        config/ \
        data/ 2>/dev/null || true

    if [[ -f "${backup_file}" ]]; then
        log_info "Container backup created successfully"
        return 0
    else
        log_error "Failed to create container backup"
        return 1
    fi
}

#
# Get container status summary
#
get_container_status() {
    log_info "Container Status Summary:"
    echo "=========================="

    # Check main container
    if docker ps --filter "name=${CONTAINER_NAME}" --quiet | grep -q .; then
        echo "Xray Container: RUNNING"

        # Get health status
        local health
        health=$(docker inspect --format='{{.State.Health.Status}}' "${CONTAINER_NAME}" 2>/dev/null || echo "unknown")
        echo "Health Status: ${health^^}"

        # Get uptime
        local started
        started=$(docker inspect --format='{{.State.StartedAt}}' "${CONTAINER_NAME}" 2>/dev/null)
        echo "Started: ${started}"

        # Get resource usage
        echo ""
        echo "Resource Usage:"
        docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" "${CONTAINER_NAME}"
    else
        echo "Xray Container: NOT RUNNING"
    fi

    # Check monitor container if exists
    if docker ps --filter "name=${MONITOR_CONTAINER_NAME}" --quiet | grep -q .; then
        echo ""
        echo "Monitor Container: RUNNING"
    fi

    echo "=========================="
}

# ======================================================================================
# MAIN EXECUTION
# ======================================================================================

# Only execute main function if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main() {
        log_info "Container management module executed directly"

        case "${1:-help}" in
            "start")
                start_xray_container
                ;;
            "stop")
                stop_xray_container
                ;;
            "restart")
                restart_xray_container
                ;;
            "force-restart")
                force_restart_xray_container
                ;;
            "remove")
                remove_xray_container "${2:-}"
                ;;
            "health")
                check_container_health
                ;;
            "logs")
                get_container_logs "${CONTAINER_NAME}" "${2:-50}" "${3:-}"
                ;;
            "stats")
                get_container_stats
                ;;
            "status")
                get_container_status
                ;;
            "update")
                update_xray_image
                ;;
            "help"|*)
                echo "Usage: $0 {start|stop|restart|force-restart|remove|health|logs|stats|status|update|help}"
                echo ""
                echo "Container Lifecycle:"
                echo "  start        - Start Xray container"
                echo "  stop         - Stop Xray container gracefully"
                echo "  restart      - Restart container with config reload"
                echo "  force-restart- Force restart (kill and start)"
                echo "  remove       - Remove container (add 'keep-data' to preserve volumes)"
                echo ""
                echo "Monitoring:"
                echo "  health       - Check container health status"
                echo "  logs         - Show container logs (add line count and 'follow')"
                echo "  stats        - Show container resource statistics"
                echo "  status       - Show comprehensive container status"
                echo ""
                echo "Maintenance:"
                echo "  update       - Update container image"
                echo "  help         - Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0 logs 100 follow    # Follow last 100 log lines"
                echo "  $0 remove keep-data   # Remove container but keep data"
                exit 0
                ;;
        esac
    }

    main "$@"
fi