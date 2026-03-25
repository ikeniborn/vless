#!/bin/bash
################################################################################
# lib/container_management.sh
#
# Container Management and Health Check Module (v5.22)
# Ensures Docker containers are running and healthy before operations
#
# Features:
# - Container status checking
# - Automatic container startup
# - Health monitoring with timeouts
# - Retry logic with exponential backoff
#
# Usage:
#   source lib/container_management.sh
#   ensure_container_running "familytraffic"
#   ensure_all_containers_running
#
# Version: 5.22.0
# Author: VLESS Development Team
# Date: 2025-10-21
################################################################################

set -euo pipefail

# Logging functions (if not already defined)
if ! command -v log &> /dev/null; then
    log() {
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [container-mgmt] $*" >&2
    }
fi

if ! command -v log_error &> /dev/null; then
    log_error() {
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [container-mgmt] ERROR: $*" >&2
    }
fi

# =============================================================================
# Function: is_container_running
# Description: Checks if a Docker container is running
#
# Parameters:
#   $1 - container_name: Name of the Docker container
#
# Returns:
#   0 if running, 1 if not running
#
# Example:
#   if is_container_running "familytraffic"; then
#       echo "familytraffic is running"
#   fi
# =============================================================================
is_container_running() {
    local container="$1"

    if [ -z "$container" ]; then
        log_error "Container name required"
        return 1
    fi

    # Check if container exists and is running
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        return 0
    fi

    return 1
}

# =============================================================================
# Function: ensure_container_running
# Description: Ensures a container is running, starts it if stopped
#
# Parameters:
#   $1 - container_name: Name of the Docker container
#   $2 - max_wait: (Optional) Maximum seconds to wait (default: 30)
#
# Returns:
#   0 if container running/started successfully, 1 on failure
#
# Example:
#   ensure_container_running "familytraffic" 30
# =============================================================================
ensure_container_running() {
    local container="$1"
    local max_wait="${2:-30}"

    if [ -z "$container" ]; then
        log_error "Container name required"
        return 1
    fi

    # Check if already running
    if is_container_running "$container"; then
        return 0
    fi

    log "⚠️  Container '$container' not running, attempting to start..."

    # Check if container exists
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
        log_error "Container '$container' does not exist"
        log_error "  Run: docker ps -a | grep '$container'"
        return 1
    fi

    # Start container
    if ! docker start "$container" &>/dev/null; then
        log_error "Failed to start container: $container"
        log_error "  Check logs: docker logs $container --tail 50"
        return 1
    fi

    # Wait for container to be running
    local waited=0
    while [ $waited -lt $max_wait ]; do
        if is_container_running "$container"; then
            # Additional wait for services inside container to initialize
            sleep 2
            log "✅ Container '$container' started successfully"
            return 0
        fi

        sleep 1
        waited=$((waited + 1))
    done

    log_error "Container '$container' failed to start within ${max_wait}s"
    log_error "  Check status: docker ps -a --filter \"name=$container\""
    log_error "  Check logs: docker logs $container --tail 50"
    return 1
}

# =============================================================================
# Function: ensure_all_containers_running
# Description: Ensures all critical VLESS containers are running
#
# Parameters:
#   None
#
# Returns:
#   0 if all containers running, 1 if any failed to start
#
# Example:
#   if ensure_all_containers_running; then
#       echo "All containers ready"
#   fi
# =============================================================================
ensure_all_containers_running() {
    # v5.33: single container replaces multi-container architecture
    local containers=("familytraffic")
    local failed=()

    log "Checking critical containers (v5.33 single container)..."

    for container in "${containers[@]}"; do
        if ! ensure_container_running "$container"; then
            failed+=("$container")
        fi
    done

    if [ ${#failed[@]} -gt 0 ]; then
        log_error "Failed to start containers: ${failed[*]}"
        log_error ""
        log_error "TROUBLESHOOTING:"
        log_error "  1. Check container status: docker ps -a"
        log_error "  2. Check logs: docker logs familytraffic --tail 50"
        log_error "  3. Restart: cd /opt/familytraffic && docker compose up -d"
        log_error "  4. Check supervisord: docker exec familytraffic supervisorctl status"
        return 1
    fi

    log "✅ All critical containers running"
    return 0
}

# =============================================================================
# Function: retry_operation
# Description: Retries an operation with exponential backoff
#
# Parameters:
#   $1 - max_attempts: Maximum number of retry attempts
#   $2 - operation_name: Human-readable name for logging
#   $3+ - command: Command and arguments to execute
#
# Returns:
#   0 if operation succeeded, 1 if all attempts failed
#
# Example:
#   retry_operation 3 "nginx reload" nginx -s reload --silent
# =============================================================================
retry_operation() {
    local max_attempts="$1"
    shift
    local operation_name="$1"
    shift

    if [ -z "$max_attempts" ] || [ -z "$operation_name" ]; then
        log_error "Usage: retry_operation <max_attempts> <operation_name> <command> [args...]"
        return 1
    fi

    local attempt=1
    local wait_time=2

    while [ $attempt -le $max_attempts ]; do
        if [ $attempt -eq 1 ]; then
            log "Executing: $operation_name"
        else
            log "Retry attempt $attempt/$max_attempts: $operation_name"
        fi

        # Execute command with all arguments
        if "$@"; then
            if [ $attempt -gt 1 ]; then
                log "✅ Operation succeeded on attempt $attempt: $operation_name"
            fi
            return 0
        fi

        # Check if this was the last attempt
        if [ $attempt -eq $max_attempts ]; then
            log_error "❌ Operation failed after $max_attempts attempts: $operation_name"
            return 1
        fi

        # Wait before retry with exponential backoff
        log "⏳ Attempt $attempt failed, waiting ${wait_time}s before retry..."
        sleep $wait_time

        # Exponential backoff: 2s, 4s, 8s, 16s...
        wait_time=$((wait_time * 2))
        attempt=$((attempt + 1))
    done

    return 1
}

# =============================================================================
# Function: wait_for_container_healthy
# Description: Waits for container to be healthy (if health check configured)
#
# Parameters:
#   $1 - container_name: Name of the Docker container
#   $2 - max_wait: (Optional) Maximum seconds to wait (default: 60)
#
# Returns:
#   0 if healthy or no health check, 1 on timeout
#
# Note: Not all containers have health checks configured
#
# Example:
#   wait_for_container_healthy "familytraffic" 60
# =============================================================================
wait_for_container_healthy() {
    local container="$1"
    local max_wait="${2:-60}"

    if [ -z "$container" ]; then
        log_error "Container name required"
        return 1
    fi

    # Check if container has health check configured
    local health_status
    health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")

    if [ "$health_status" = "none" ] || [ -z "$health_status" ]; then
        # No health check configured, just verify it's running
        if is_container_running "$container"; then
            return 0
        fi
        return 1
    fi

    log "Waiting for container '$container' to be healthy..."

    local waited=0
    while [ $waited -lt $max_wait ]; do
        health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")

        if [ "$health_status" = "healthy" ]; then
            log "✅ Container '$container' is healthy"
            return 0
        fi

        if [ "$health_status" = "unhealthy" ]; then
            log_error "Container '$container' is unhealthy"
            log_error "  Check logs: docker logs $container --tail 50"
            return 1
        fi

        # Status: starting
        sleep 2
        waited=$((waited + 2))
    done

    log_error "Container '$container' did not become healthy within ${max_wait}s"
    log_error "  Current status: $health_status"
    log_error "  Check logs: docker logs $container --tail 50"
    return 1
}

################################################################################
# Module loaded successfully
################################################################################
