#!/bin/bash

# VLESS+Reality VPN Management System - Container Management Module
# Version: 1.0.0
# Description: Docker container lifecycle management
#
# This module provides:
# - Service startup and shutdown procedures
# - Configuration reload without downtime
# - Health status monitoring
# - Log collection and rotation
# - Container update procedures

set -euo pipefail

# Import common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_utils.sh"

# Container configuration
readonly COMPOSE_FILE="${SCRIPT_DIR}/../config/docker-compose.yml"
readonly SYSTEM_COMPOSE_FILE="/opt/vless/docker-compose.yml"
readonly PROJECT_NAME="vless-vpn"
readonly XRAY_CONTAINER_NAME="vless-xray"
readonly NGINX_CONTAINER_NAME="vless-nginx"
readonly WATCHTOWER_CONTAINER_NAME="vless-watchtower"

# Service timeout settings
readonly START_TIMEOUT=60
readonly STOP_TIMEOUT=30
readonly RESTART_TIMEOUT=90
readonly HEALTH_CHECK_TIMEOUT=30

# Get the active compose file
get_compose_file() {
    if [[ -f "$SYSTEM_COMPOSE_FILE" ]]; then
        echo "$SYSTEM_COMPOSE_FILE"
    elif [[ -f "$COMPOSE_FILE" ]]; then
        echo "$COMPOSE_FILE"
    else
        log_error "No Docker Compose file found"
        return 1
    fi
}

# Safe Docker Compose execution with process isolation
safe_docker_compose() {
    local compose_file
    local timeout="$1"
    shift
    local cmd=("$@")

    compose_file=$(get_compose_file) || return 1

    setup_signal_handlers
    log_debug "Executing docker-compose with timeout ${timeout}s: ${cmd[*]}"

    # Use timeout with docker-compose
    timeout "$timeout" docker-compose -f "$compose_file" -p "$PROJECT_NAME" "${cmd[@]}" &
    local pid=$!
    register_child_process "$pid"

    if wait "$pid"; then
        log_debug "Docker-compose command completed successfully: ${cmd[*]}"
        return 0
    else
        local exit_code=$?
        log_error "Docker-compose command failed with exit code $exit_code: ${cmd[*]}"
        return $exit_code
    fi
}

# Check if Docker is available and running
check_docker_availability() {
    if ! command_exists docker; then
        log_error "Docker is not installed"
        return 1
    fi

    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        return 1
    fi

    if ! command_exists docker-compose; then
        log_error "Docker Compose is not installed"
        return 1
    fi

    return 0
}

# Prepare system directories and files
prepare_system_environment() {
    log_info "Preparing system environment for containers..."

    # Create required directories
    local directories=(
        "/opt/vless/config"
        "/opt/vless/logs"
        "/opt/vless/certs"
        "/opt/vless/backup"
    )

    local dir
    for dir in "${directories[@]}"; do
        create_directory "$dir" "755"
    done

    # Create log subdirectories
    create_directory "/opt/vless/logs/xray" "755"
    create_directory "/opt/vless/logs/nginx" "755"

    # Copy compose file to system location if not exists
    if [[ ! -f "$SYSTEM_COMPOSE_FILE" ]] && [[ -f "$COMPOSE_FILE" ]]; then
        cp "$COMPOSE_FILE" "$SYSTEM_COMPOSE_FILE"
        chmod 644 "$SYSTEM_COMPOSE_FILE"
        log_info "Copied Docker Compose file to system location"
    fi

    # Ensure proper ownership
    if [[ -n "${SUDO_USER:-}" ]]; then
        chown -R "${SUDO_USER}:${SUDO_USER}" "/opt/vless" 2>/dev/null || true
    fi

    log_success "System environment prepared successfully"
}

# Start all services
start_services() {
    local service="${1:-}"  # Optional specific service

    log_info "Starting VLESS VPN services${service:+ ($service)}..."

    if ! check_docker_availability; then
        die "Docker is not available" 20
    fi

    prepare_system_environment

    # Pull latest images first
    log_info "Pulling latest container images..."
    if ! safe_docker_compose 120 pull; then
        log_warn "Failed to pull latest images, continuing with existing ones"
    fi

    # Start services
    if [[ -n "$service" ]]; then
        if ! safe_docker_compose "$START_TIMEOUT" up -d "$service"; then
            log_error "Failed to start service: $service"
            return 1
        fi
    else
        if ! safe_docker_compose "$START_TIMEOUT" up -d; then
            log_error "Failed to start services"
            return 1
        fi
    fi

    # Wait for services to be healthy
    wait_for_services_healthy

    log_success "Services started successfully"
    show_service_status
}

# Stop all services
stop_services() {
    local service="${1:-}"  # Optional specific service

    log_info "Stopping VLESS VPN services${service:+ ($service)}..."

    if ! check_docker_availability; then
        log_warn "Docker not available, cannot stop services gracefully"
        return 1
    fi

    if [[ -n "$service" ]]; then
        if ! safe_docker_compose "$STOP_TIMEOUT" stop "$service"; then
            log_error "Failed to stop service: $service"
            return 1
        fi
    else
        if ! safe_docker_compose "$STOP_TIMEOUT" down; then
            log_error "Failed to stop services"
            return 1
        fi
    fi

    log_success "Services stopped successfully"
}

# Restart services
restart_services() {
    local service="${1:-}"  # Optional specific service

    log_info "Restarting VLESS VPN services${service:+ ($service)}..."

    if [[ -n "$service" ]]; then
        if ! safe_docker_compose "$RESTART_TIMEOUT" restart "$service"; then
            log_error "Failed to restart service: $service"
            return 1
        fi
    else
        # Stop all services first
        stop_services
        interruptible_sleep 5 1
        # Start all services
        start_services
    fi

    log_success "Services restarted successfully"
    show_service_status
}

# Reload configuration without downtime
reload_configuration() {
    log_info "Reloading Xray configuration..."

    # Validate configuration first
    local config_file="/opt/vless/config/config.json"
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi

    # Validate configuration
    if ! "${SCRIPT_DIR}/config_templates.sh" --validate "$config_file"; then
        log_error "Configuration validation failed"
        return 1
    fi

    # Send reload signal to Xray container
    if docker ps --format '{{.Names}}' | grep -q "^${XRAY_CONTAINER_NAME}$"; then
        log_info "Sending reload signal to Xray container..."
        if docker exec "$XRAY_CONTAINER_NAME" kill -HUP 1 2>/dev/null; then
            log_success "Configuration reloaded successfully"
        else
            log_warn "Failed to send reload signal, restarting container..."
            restart_services "xray"
        fi
    else
        log_error "Xray container is not running"
        return 1
    fi
}

# Check service health
check_service_health() {
    local service="${1:-}"
    local timeout="${2:-$HEALTH_CHECK_TIMEOUT}"

    if [[ -n "$service" ]]; then
        log_debug "Checking health of service: $service"
        local container_name
        case "$service" in
            "xray") container_name="$XRAY_CONTAINER_NAME" ;;
            "nginx") container_name="$NGINX_CONTAINER_NAME" ;;
            "watchtower") container_name="$WATCHTOWER_CONTAINER_NAME" ;;
            *) log_error "Unknown service: $service"; return 1 ;;
        esac

        # Check if container is running
        if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
            log_error "Container not running: $container_name"
            return 1
        fi

        # Check container health status
        local health_status
        health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "none")

        case "$health_status" in
            "healthy")
                log_success "Service $service is healthy"
                return 0
                ;;
            "unhealthy")
                log_error "Service $service is unhealthy"
                return 1
                ;;
            "starting")
                log_info "Service $service is starting..."
                return 2
                ;;
            "none")
                log_warn "Service $service has no health check configured"
                return 0
                ;;
            *)
                log_warn "Service $service has unknown health status: $health_status"
                return 1
                ;;
        esac
    else
        # Check all services
        local all_healthy=true
        for svc in "xray" "nginx"; do
            if ! check_service_health "$svc" "$timeout"; then
                all_healthy=false
            fi
        done

        if $all_healthy; then
            log_success "All services are healthy"
            return 0
        else
            log_error "Some services are unhealthy"
            return 1
        fi
    fi
}

# Wait for services to be healthy
wait_for_services_healthy() {
    local timeout="${1:-60}"
    local check_interval="${2:-5}"

    log_info "Waiting for services to become healthy (timeout: ${timeout}s)..."

    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if check_service_health; then
            log_success "All services are healthy"
            return 0
        fi

        # Check for starting services
        local starting_services=()
        for service in "xray" "nginx"; do
            if check_service_health "$service" 1; then
                case $? in
                    2) starting_services+=("$service") ;;
                esac
            fi
        done

        if [[ ${#starting_services[@]} -gt 0 ]]; then
            log_info "Services still starting: ${starting_services[*]}"
        fi

        interruptible_sleep "$check_interval" 1
        elapsed=$((elapsed + check_interval))
    done

    log_error "Timeout waiting for services to become healthy"
    return 1
}

# Show service status
show_service_status() {
    echo
    echo "=== VLESS VPN Service Status ==="

    if ! check_docker_availability; then
        echo "Docker is not available"
        return 1
    fi

    local compose_file
    compose_file=$(get_compose_file) || return 1

    # Show container status
    echo
    echo "Container Status:"
    docker-compose -f "$compose_file" -p "$PROJECT_NAME" ps 2>/dev/null || {
        echo "No containers found or compose file error"
        return 1
    }

    # Show resource usage
    echo
    echo "Resource Usage:"
    local containers
    containers=$(docker ps --filter "label=com.docker.compose.project=$PROJECT_NAME" --format "{{.Names}}" 2>/dev/null)

    if [[ -n "$containers" ]]; then
        echo "$containers" | while read -r container; do
            local stats
            stats=$(docker stats --no-stream --format "{{.Name}}: CPU {{.CPUPerc}}, Memory {{.MemUsage}}" "$container" 2>/dev/null)
            echo "  $stats"
        done
    else
        echo "  No running containers"
    fi

    # Show port usage
    echo
    echo "Port Usage:"
    local ports=("443" "80" "8080")
    for port in "${ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
            echo "  Port $port: IN USE"
        else
            echo "  Port $port: Available"
        fi
    done

    echo
}

# Show service logs
show_service_logs() {
    local service="${1:-}"
    local lines="${2:-50}"
    local follow="${3:-false}"

    if ! check_docker_availability; then
        log_error "Docker is not available"
        return 1
    fi

    local compose_file
    compose_file=$(get_compose_file) || return 1

    if [[ "$follow" == "true" ]]; then
        log_info "Following logs for ${service:-all services} (Ctrl+C to stop)..."
        if [[ -n "$service" ]]; then
            controlled_tail <(docker-compose -f "$compose_file" -p "$PROJECT_NAME" logs -f "$service" 2>/dev/null) 60 "$lines"
        else
            controlled_tail <(docker-compose -f "$compose_file" -p "$PROJECT_NAME" logs -f 2>/dev/null) 60 "$lines"
        fi
    else
        log_info "Showing last $lines lines for ${service:-all services}..."
        if [[ -n "$service" ]]; then
            docker-compose -f "$compose_file" -p "$PROJECT_NAME" logs --tail="$lines" "$service" 2>/dev/null
        else
            docker-compose -f "$compose_file" -p "$PROJECT_NAME" logs --tail="$lines" 2>/dev/null
        fi
    fi
}

# Update container images
update_containers() {
    local force="${1:-false}"

    log_info "Updating container images..."

    if ! check_docker_availability; then
        die "Docker is not available" 21
    fi

    # Pull latest images
    log_info "Pulling latest images..."
    if ! safe_docker_compose 180 pull; then
        log_error "Failed to pull latest images"
        return 1
    fi

    # Check if any images were updated
    local updated=false
    if [[ "$force" == "true" ]]; then
        updated=true
        log_info "Force update requested"
    else
        # This is a simplified check - in practice, you'd want to compare image IDs
        log_info "Checking for image updates..."
        updated=true  # Assume updated for now
    fi

    if $updated; then
        log_info "Restarting services with updated images..."
        restart_services
        log_success "Container images updated successfully"
    else
        log_info "No image updates available"
    fi
}

# Cleanup unused resources
cleanup_resources() {
    log_info "Cleaning up unused Docker resources..."

    if ! check_docker_availability; then
        log_warn "Docker not available for cleanup"
        return 1
    fi

    # Remove unused containers
    local removed_containers
    removed_containers=$(docker container prune -f 2>/dev/null | grep "Total reclaimed space" || echo "")
    if [[ -n "$removed_containers" ]]; then
        log_info "Removed unused containers: $removed_containers"
    fi

    # Remove unused images
    local removed_images
    removed_images=$(docker image prune -f 2>/dev/null | grep "Total reclaimed space" || echo "")
    if [[ -n "$removed_images" ]]; then
        log_info "Removed unused images: $removed_images"
    fi

    # Remove unused networks
    local removed_networks
    removed_networks=$(docker network prune -f 2>/dev/null | grep "Total reclaimed space" || echo "")
    if [[ -n "$removed_networks" ]]; then
        log_info "Removed unused networks: $removed_networks"
    fi

    # Remove unused volumes
    local removed_volumes
    removed_volumes=$(docker volume prune -f 2>/dev/null | grep "Total reclaimed space" || echo "")
    if [[ -n "$removed_volumes" ]]; then
        log_info "Removed unused volumes: $removed_volumes"
    fi

    log_success "Resource cleanup completed"
}

# Export service configuration
export_service_config() {
    local output_file="${1:-/tmp/vless-config-$(date +%Y%m%d_%H%M%S).tar.gz}"

    log_info "Exporting service configuration to: $output_file"

    # Create temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)

    # Copy configuration files
    local config_dir="$temp_dir/vless-config"
    mkdir -p "$config_dir"

    # Copy relevant files
    if [[ -d "/opt/vless/config" ]]; then
        cp -r "/opt/vless/config" "$config_dir/"
    fi

    local compose_file
    compose_file=$(get_compose_file)
    if [[ -f "$compose_file" ]]; then
        cp "$compose_file" "$config_dir/docker-compose.yml"
    fi

    # Create archive
    if tar -czf "$output_file" -C "$temp_dir" "vless-config"; then
        log_success "Configuration exported to: $output_file"
        log_info "Archive size: $(du -h "$output_file" | cut -f1)"
    else
        log_error "Failed to create configuration archive"
        rm -rf "$temp_dir"
        return 1
    fi

    # Cleanup
    rm -rf "$temp_dir"
}

# Display help information
show_help() {
    cat << EOF
VLESS+Reality VPN Container Management Module

Usage: $0 [OPTIONS]

Options:
    --start [SERVICE]         Start services (all or specific)
    --stop [SERVICE]          Stop services (all or specific)
    --restart [SERVICE]       Restart services (all or specific)
    --reload                  Reload Xray configuration without downtime
    --status                  Show service status
    --health [SERVICE]        Check service health
    --logs [SERVICE] [LINES]  Show service logs
    --follow-logs [SERVICE]   Follow service logs
    --update [--force]        Update container images
    --cleanup                 Clean up unused Docker resources
    --export [FILE]           Export service configuration
    --help                    Show this help message

Services:
    xray                      Xray VLESS+Reality server
    nginx                     Nginx reverse proxy
    watchtower                Container auto-updater

Examples:
    $0 --start                # Start all services
    $0 --restart xray         # Restart Xray service only
    $0 --logs xray 100        # Show last 100 lines of Xray logs
    $0 --follow-logs          # Follow logs for all services
    $0 --health               # Check health of all services
    $0 --update --force       # Force update all containers

EOF
}

# Main execution
main() {
    local action=""
    local service=""
    local lines="50"
    local force="false"
    local output_file=""

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --start)
                action="start"
                service="${2:-}"
                [[ -n "$service" && ! "$service" =~ ^-- ]] && shift
                shift
                ;;
            --stop)
                action="stop"
                service="${2:-}"
                [[ -n "$service" && ! "$service" =~ ^-- ]] && shift
                shift
                ;;
            --restart)
                action="restart"
                service="${2:-}"
                [[ -n "$service" && ! "$service" =~ ^-- ]] && shift
                shift
                ;;
            --reload)
                action="reload"
                shift
                ;;
            --status)
                action="status"
                shift
                ;;
            --health)
                action="health"
                service="${2:-}"
                [[ -n "$service" && ! "$service" =~ ^-- ]] && shift
                shift
                ;;
            --logs)
                action="logs"
                service="${2:-}"
                lines="${3:-50}"
                [[ -n "$service" && ! "$service" =~ ^-- ]] && shift
                [[ "$lines" =~ ^[0-9]+$ ]] && shift
                shift
                ;;
            --follow-logs)
                action="follow-logs"
                service="${2:-}"
                [[ -n "$service" && ! "$service" =~ ^-- ]] && shift
                shift
                ;;
            --update)
                action="update"
                shift
                ;;
            --force)
                force="true"
                shift
                ;;
            --cleanup)
                action="cleanup"
                shift
                ;;
            --export)
                action="export"
                output_file="${2:-}"
                [[ -n "$output_file" && ! "$output_file" =~ ^-- ]] && shift
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Setup signal handlers for process isolation
    setup_signal_handlers

    # Default action is status
    if [[ -z "$action" ]]; then
        action="status"
    fi

    # Execute requested action
    case "$action" in
        "start")
            start_services "$service"
            ;;
        "stop")
            stop_services "$service"
            ;;
        "restart")
            restart_services "$service"
            ;;
        "reload")
            reload_configuration
            ;;
        "status")
            show_service_status
            ;;
        "health")
            check_service_health "$service"
            ;;
        "logs")
            show_service_logs "$service" "$lines" "false"
            ;;
        "follow-logs")
            show_service_logs "$service" "$lines" "true"
            ;;
        "update")
            update_containers "$force"
            ;;
        "cleanup")
            cleanup_resources
            ;;
        "export")
            export_service_config "$output_file"
            ;;
        *)
            log_error "Unknown action: $action"
            show_help
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi