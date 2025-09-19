#!/bin/bash
# Process Isolation Module for VLESS VPN Project
# Prevents EPERM errors by implementing safe process management
# Author: Claude Code
# Version: 1.0

set -euo pipefail

# Global variables for process tracking
declare -a CHILD_PIDS=()
declare CLEANUP_DONE=false

# Color codes for output (check if already defined)
if [[ -z "${RED:-}" ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly NC='\033[0m' # No Color
fi

# Log function with timestamp
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" >&2
}

# Signal handlers for graceful shutdown
cleanup_child_processes() {
    if [[ "$CLEANUP_DONE" == "true" ]]; then
        return 0
    fi

    CLEANUP_DONE=true
    log_message "INFO" "Cleaning up child processes..."

    for pid in "${CHILD_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            log_message "INFO" "Terminating process $pid"
            kill -TERM "$pid" 2>/dev/null || true
            sleep 2
            if kill -0 "$pid" 2>/dev/null; then
                kill -KILL "$pid" 2>/dev/null || true
            fi
        fi
    done

    CHILD_PIDS=()
}

# Setup signal handlers
setup_signal_handlers() {
    trap cleanup_child_processes EXIT
    trap cleanup_child_processes SIGTERM
    trap cleanup_child_processes SIGINT
}

# Add PID to tracking array
track_child_process() {
    local pid="$1"
    CHILD_PIDS+=("$pid")
}

# Safe execute with timeout and cleanup
safe_execute() {
    local command="$1"
    local timeout_seconds="${2:-120}"
    local description="${3:-Command execution}"

    log_message "INFO" "Executing: $description"
    log_message "DEBUG" "Command: $command"

    # Execute command in background with timeout
    timeout "$timeout_seconds" bash -c "$command" &
    local cmd_pid=$!
    track_child_process "$cmd_pid"

    # Wait for completion
    if wait "$cmd_pid"; then
        log_message "INFO" "$description completed successfully"
        return 0
    else
        local exit_code=$?
        log_message "ERROR" "$description failed with exit code $exit_code"
        return $exit_code
    fi
}

# Isolated systemctl command execution
isolate_systemctl_command() {
    local action="$1"
    local service="$2"
    local timeout_seconds="${3:-30}"

    log_message "INFO" "Executing systemctl $action $service"

    local cmd="systemctl $action $service"
    safe_execute "$cmd" "$timeout_seconds" "systemctl $action $service"
}

# Safe Docker Compose operations
safe_docker_compose_up() {
    local compose_dir="$1"
    local timeout_seconds="${2:-120}"

    log_message "INFO" "Starting Docker Compose in $compose_dir"

    local cmd="cd '$compose_dir' && docker compose up -d --remove-orphans"
    safe_execute "$cmd" "$timeout_seconds" "Docker Compose up"
}

safe_docker_compose_down() {
    local compose_dir="$1"
    local timeout_seconds="${2:-60}"

    log_message "INFO" "Stopping Docker Compose in $compose_dir"

    local cmd="cd '$compose_dir' && docker compose down --remove-orphans"
    safe_execute "$cmd" "$timeout_seconds" "Docker Compose down"
}

# Interruptible monitoring loop
interruptible_monitor() {
    local check_function="$1"
    local check_interval="${2:-60}"
    local startup_delay="${3:-0}"
    local max_duration="${4:-3600}"

    log_message "INFO" "Starting monitoring with $max_duration seconds max duration"

    # Initial delay
    if [[ "$startup_delay" -gt 0 ]]; then
        interruptible_sleep "$startup_delay" 1
    fi

    local start_time=$(date +%s)
    local end_time=$((start_time + max_duration))

    while [[ $(date +%s) -lt $end_time ]]; do
        if ! $check_function; then
            log_message "WARNING" "Monitor check failed, continuing..."
        fi

        interruptible_sleep "$check_interval" 5
    done

    log_message "INFO" "Monitoring completed after $max_duration seconds"
}

# Controlled tail command
controlled_tail() {
    local file_path="$1"
    local duration="${2:-60}"
    local lines="${3:-100}"

    log_message "INFO" "Tailing $file_path for $duration seconds"

    if [[ ! -f "$file_path" ]]; then
        log_message "ERROR" "File $file_path does not exist"
        return 1
    fi

    timeout "$duration" tail -n "$lines" -f "$file_path" &
    local tail_pid=$!
    track_child_process "$tail_pid"

    wait "$tail_pid" 2>/dev/null || true
}

# Isolated sudo command execution
isolated_sudo_command() {
    local command="$1"
    local timeout_seconds="${2:-60}"
    local description="${3:-Sudo command}"

    log_message "INFO" "Executing sudo command: $description"

    local cmd="sudo bash -c '$command'"
    safe_execute "$cmd" "$timeout_seconds" "$description"
}

# Interruptible sleep function
interruptible_sleep() {
    local total_seconds="$1"
    local check_interval="${2:-5}"

    local elapsed=0
    while [[ $elapsed -lt $total_seconds ]]; do
        local remaining=$((total_seconds - elapsed))
        local sleep_time=$((remaining < check_interval ? remaining : check_interval))

        sleep "$sleep_time"
        elapsed=$((elapsed + sleep_time))
    done
}

# Health check function for services
check_service_health() {
    local service_name="$1"
    local max_attempts="${2:-3}"
    local delay_between_attempts="${3:-5}"

    log_message "INFO" "Checking health of service: $service_name"

    for ((i=1; i<=max_attempts; i++)); do
        if systemctl is-active --quiet "$service_name"; then
            log_message "INFO" "Service $service_name is healthy"
            return 0
        fi

        if [[ $i -lt $max_attempts ]]; then
            log_message "WARNING" "Service $service_name not healthy, attempt $i/$max_attempts. Retrying in $delay_between_attempts seconds..."
            sleep "$delay_between_attempts"
        fi
    done

    log_message "ERROR" "Service $service_name failed health check after $max_attempts attempts"
    return 1
}

# Docker container health check
check_docker_container_health() {
    local container_name="$1"
    local max_attempts="${2:-3}"
    local delay_between_attempts="${3:-5}"

    log_message "INFO" "Checking health of Docker container: $container_name"

    for ((i=1; i<=max_attempts; i++)); do
        if docker ps --filter "name=$container_name" --filter "status=running" --quiet | grep -q .; then
            log_message "INFO" "Container $container_name is healthy"
            return 0
        fi

        if [[ $i -lt $max_attempts ]]; then
            log_message "WARNING" "Container $container_name not healthy, attempt $i/$max_attempts. Retrying in $delay_between_attempts seconds..."
            sleep "$delay_between_attempts"
        fi
    done

    log_message "ERROR" "Container $container_name failed health check after $max_attempts attempts"
    return 1
}

# Safe file operations with backup
safe_file_operation() {
    local operation="$1"
    local source_file="$2"
    local target_file="${3:-}"
    local backup_suffix="${4:-.backup.$(date +%Y%m%d_%H%M%S)}"

    case "$operation" in
        "copy")
            if [[ -z "$target_file" ]]; then
                log_message "ERROR" "Target file required for copy operation"
                return 1
            fi

            # Create backup if target exists
            if [[ -f "$target_file" ]]; then
                cp "$target_file" "${target_file}${backup_suffix}"
                log_message "INFO" "Created backup: ${target_file}${backup_suffix}"
            fi

            cp "$source_file" "$target_file"
            log_message "INFO" "Copied $source_file to $target_file"
            ;;

        "move")
            if [[ -z "$target_file" ]]; then
                log_message "ERROR" "Target file required for move operation"
                return 1
            fi

            # Create backup if target exists
            if [[ -f "$target_file" ]]; then
                cp "$target_file" "${target_file}${backup_suffix}"
                log_message "INFO" "Created backup: ${target_file}${backup_suffix}"
            fi

            mv "$source_file" "$target_file"
            log_message "INFO" "Moved $source_file to $target_file"
            ;;

        "delete")
            if [[ -f "$source_file" ]]; then
                cp "$source_file" "${source_file}${backup_suffix}"
                log_message "INFO" "Created backup: ${source_file}${backup_suffix}"
                rm "$source_file"
                log_message "INFO" "Deleted $source_file"
            fi
            ;;

        *)
            log_message "ERROR" "Unknown operation: $operation"
            return 1
            ;;
    esac
}

# Verify process isolation module is loaded
log_message "INFO" "Process isolation module loaded successfully"

# Export functions for use by other modules
export -f log_message
export -f cleanup_child_processes
export -f setup_signal_handlers
export -f track_child_process
export -f safe_execute
export -f isolate_systemctl_command
export -f safe_docker_compose_up
export -f safe_docker_compose_down
export -f interruptible_monitor
export -f controlled_tail
export -f isolated_sudo_command
export -f interruptible_sleep
export -f check_service_health
export -f check_docker_container_health
export -f safe_file_operation