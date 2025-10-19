#!/bin/bash
# lib/service_operations.sh - Service lifecycle management for VLESS Reality VPN
# EPIC-8: Service Operations
#
# Provides functions for:
# - TASK-8.1: Start/stop/restart commands (4h)
# - TASK-8.2: Status display (3h)
# - TASK-8.3: Update mechanism preserving subnet/port (6h)
# - TASK-8.4: Log display with filtering (3h)
#
# Author: VPN Deployment System
# Version: 1.0.0

set -euo pipefail

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source required modules (conditionally - they may not exist in minimal installations)
[[ -f "${SCRIPT_DIR}/logger.sh" ]] && source "${SCRIPT_DIR}/logger.sh"
[[ -f "${SCRIPT_DIR}/validation.sh" ]] && source "${SCRIPT_DIR}/validation.sh"

# If logger.sh wasn't loaded, provide minimal logging functions
if ! declare -f log_info &>/dev/null; then
    # Colors for logging (only if not already defined)
    [[ -z "${RED:-}" ]] && RED='\033[0;31m'
    [[ -z "${GREEN:-}" ]] && GREEN='\033[0;32m'
    [[ -z "${YELLOW:-}" ]] && YELLOW='\033[1;33m'
    [[ -z "${BLUE:-}" ]] && BLUE='\033[0;34m'
    [[ -z "${NC:-}" ]] && NC='\033[0m'

    log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
    log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
    log_warn() { echo -e "${YELLOW}[⚠]${NC} $*"; }
    log_error() { echo -e "${RED}[✗]${NC} $*" >&2; }
    log_debug() { echo -e "${BLUE}[DEBUG]${NC} $*"; }
fi

# Configuration paths
COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yml"
ENV_FILE="${PROJECT_ROOT}/.env"
CONFIG_DIR="${PROJECT_ROOT}/config"
XRAY_CONFIG="${CONFIG_DIR}/xray_config.json"
BACKUP_DIR="${PROJECT_ROOT}/backups"

# Service names
XRAY_SERVICE="xray"
NGINX_SERVICE="nginx"

# Log levels for filtering
readonly LOG_LEVEL_ERROR="ERROR"
readonly LOG_LEVEL_WARN="WARN"
readonly LOG_LEVEL_INFO="INFO"
readonly LOG_LEVEL_DEBUG="DEBUG"

#######################################
# TASK-8.1: Service Control Functions
#######################################

#######################################
# Start VPN service (both Xray and Nginx containers)
# Globals:
#   COMPOSE_FILE, PROJECT_ROOT
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
start_service() {
    log_info "Starting VLESS Reality VPN service..."

    # Validate compose file exists
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        log_error "Docker Compose file not found: $COMPOSE_FILE"
        return 1
    fi

    # Check if already running
    if is_service_running; then
        log_warn "Service is already running"
        return 0
    fi

    # Start containers
    if docker-compose -f "$COMPOSE_FILE" up -d; then
        log_success "Service started successfully"

        # Wait for containers to be healthy
        log_info "Waiting for containers to be healthy..."
        sleep 2

        if wait_for_healthy 30; then
            display_service_status
            return 0
        else
            log_warn "Containers started but health check timed out"
            return 1
        fi
    else
        log_error "Failed to start service"
        return 1
    fi
}

#######################################
# Stop VPN service gracefully
# Globals:
#   COMPOSE_FILE
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
stop_service() {
    log_info "Stopping VLESS Reality VPN service..."

    if ! is_service_running; then
        log_warn "Service is not running"
        return 0
    fi

    # Graceful shutdown with 30s timeout
    if docker-compose -f "$COMPOSE_FILE" down --timeout 30; then
        log_success "Service stopped successfully"
        return 0
    else
        log_error "Failed to stop service"
        return 1
    fi
}

#######################################
# Restart VPN service
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
restart_service() {
    log_info "Restarting VLESS Reality VPN service..."

    if stop_service && start_service; then
        log_success "Service restarted successfully"
        return 0
    else
        log_error "Failed to restart service"
        return 1
    fi
}

#######################################
# Reload Xray configuration without restarting
# Sends HUP signal to Xray process for graceful reload
# Globals:
#   XRAY_SERVICE
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
reload_xray() {
    log_info "Reloading Xray configuration..."

    if ! is_container_running "$XRAY_SERVICE"; then
        log_error "Xray container is not running"
        return 1
    fi

    # Send HUP signal for graceful reload
    if docker-compose -f "$COMPOSE_FILE" kill -s HUP "$XRAY_SERVICE" 2>/dev/null; then
        log_success "Xray configuration reloaded successfully"
        return 0
    else
        log_warn "HUP signal failed, attempting container restart..."
        if docker-compose -f "$COMPOSE_FILE" restart "$XRAY_SERVICE"; then
            log_success "Xray container restarted successfully"
            return 0
        else
            log_error "Failed to reload Xray"
            return 1
        fi
    fi
}

#######################################
# TASK-8.2: Status Display Functions
#######################################

#######################################
# Check if service is running
# Globals:
#   XRAY_SERVICE, NGINX_SERVICE
# Arguments:
#   None
# Returns:
#   0 if running, 1 if not
#######################################
is_service_running() {
    is_container_running "$XRAY_SERVICE" && is_container_running "$NGINX_SERVICE"
}

#######################################
# Check if specific container is running
# Arguments:
#   $1 - Container service name
# Returns:
#   0 if running, 1 if not
#######################################
is_container_running() {
    local service="$1"

    local status
    status=$(docker-compose -f "$COMPOSE_FILE" ps -q "$service" 2>/dev/null | xargs docker inspect -f '{{.State.Running}}' 2>/dev/null || echo "false")

    [[ "$status" == "true" ]]
}

#######################################
# Get container status (running, stopped, etc.)
# Arguments:
#   $1 - Container service name
# Returns:
#   Status string
#######################################
get_container_status() {
    local service="$1"

    local container_id
    container_id=$(docker-compose -f "$COMPOSE_FILE" ps -q "$service" 2>/dev/null)

    if [[ -z "$container_id" ]]; then
        echo "not created"
        return 1
    fi

    docker inspect -f '{{.State.Status}}' "$container_id" 2>/dev/null || echo "unknown"
}

#######################################
# Get container uptime
# Arguments:
#   $1 - Container service name
# Returns:
#   Uptime string
#######################################
get_container_uptime() {
    local service="$1"

    local container_id
    container_id=$(docker-compose -f "$COMPOSE_FILE" ps -q "$service" 2>/dev/null)

    if [[ -z "$container_id" ]]; then
        echo "N/A"
        return 1
    fi

    local started_at
    started_at=$(docker inspect -f '{{.State.StartedAt}}' "$container_id" 2>/dev/null)

    if [[ -z "$started_at" ]]; then
        echo "N/A"
        return 1
    fi

    # Calculate uptime
    local start_epoch
    start_epoch=$(date -d "$started_at" +%s 2>/dev/null || echo "0")
    local current_epoch
    current_epoch=$(date +%s)
    local uptime_seconds=$((current_epoch - start_epoch))

    format_uptime "$uptime_seconds"
}

#######################################
# Format uptime in human-readable format
# Arguments:
#   $1 - Uptime in seconds
# Returns:
#   Formatted uptime string
#######################################
format_uptime() {
    local total_seconds="$1"

    if [[ "$total_seconds" -le 0 ]]; then
        echo "N/A"
        return
    fi

    local days=$((total_seconds / 86400))
    local hours=$(( (total_seconds % 86400) / 3600 ))
    local minutes=$(( (total_seconds % 3600) / 60 ))
    local seconds=$((total_seconds % 60))

    local result=""
    [[ $days -gt 0 ]] && result="${days}d "
    [[ $hours -gt 0 ]] && result="${result}${hours}h "
    [[ $minutes -gt 0 ]] && result="${result}${minutes}m "
    [[ -z "$result" ]] && result="${seconds}s"

    echo "$result" | sed 's/ $//'
}

#######################################
# Get container health status
# Arguments:
#   $1 - Container service name
# Returns:
#   Health status string
#######################################
get_container_health() {
    local service="$1"

    local container_id
    container_id=$(docker-compose -f "$COMPOSE_FILE" ps -q "$service" 2>/dev/null)

    if [[ -z "$container_id" ]]; then
        echo "N/A"
        return 1
    fi

    local health
    health=$(docker inspect -f '{{.State.Health.Status}}' "$container_id" 2>/dev/null || echo "no healthcheck")

    echo "$health"
}

#######################################
# Wait for containers to be healthy
# Arguments:
#   $1 - Timeout in seconds (default: 30)
# Returns:
#   0 if healthy, 1 if timeout
#######################################
wait_for_healthy() {
    local timeout="${1:-30}"
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        if is_container_running "$XRAY_SERVICE" && is_container_running "$NGINX_SERVICE"; then
            return 0
        fi

        sleep 1
        ((elapsed++))
    done

    return 1
}

#######################################
# Display comprehensive service status
# Globals:
#   XRAY_SERVICE, NGINX_SERVICE
# Arguments:
#   None
# Returns:
#   None
#######################################
display_service_status() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  VLESS Reality VPN Service Status"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    # Overall service status
    if is_service_running; then
        echo -e "Overall Status: \033[32m● Running\033[0m"
    else
        echo -e "Overall Status: \033[31m● Stopped\033[0m"
    fi
    echo ""

    # Xray container status
    echo "┌─ Xray Container ─────────────────────────────────────────┐"
    display_container_details "$XRAY_SERVICE"
    echo "└──────────────────────────────────────────────────────────┘"
    echo ""

    # Nginx container status
    echo "┌─ Nginx Container ────────────────────────────────────────┐"
    display_container_details "$NGINX_SERVICE"
    echo "└──────────────────────────────────────────────────────────┘"
    echo ""

    # Network information
    display_network_info

    # Proxy configuration (TASK-11.5)
    display_proxy_status

    # User count
    display_user_count

    echo "═══════════════════════════════════════════════════════════"
}

#######################################
# Display details for a specific container
# Arguments:
#   $1 - Container service name
# Returns:
#   None
#######################################
display_container_details() {
    local service="$1"

    local status
    status=$(get_container_status "$service")

    local status_color
    case "$status" in
        running)
            status_color="\033[32m● Running\033[0m"
            ;;
        stopped|exited)
            status_color="\033[31m● Stopped\033[0m"
            ;;
        paused)
            status_color="\033[33m● Paused\033[0m"
            ;;
        restarting)
            status_color="\033[33m● Restarting\033[0m"
            ;;
        *)
            status_color="\033[90m● Unknown\033[0m"
            ;;
    esac

    echo -e "  Status:     $status_color"

    if [[ "$status" == "running" ]]; then
        local uptime
        uptime=$(get_container_uptime "$service")
        echo "  Uptime:     $uptime"

        local health
        health=$(get_container_health "$service")

        local health_display
        case "$health" in
            healthy)
                health_display="\033[32m✓ Healthy\033[0m"
                ;;
            unhealthy)
                health_display="\033[31m✗ Unhealthy\033[0m"
                ;;
            starting)
                health_display="\033[33m⋯ Starting\033[0m"
                ;;
            *)
                health_display="\033[90m- No healthcheck\033[0m"
                ;;
        esac

        echo -e "  Health:     $health_display"
    fi
}

#######################################
# Display network configuration information
# Globals:
#   ENV_FILE
# Arguments:
#   None
# Returns:
#   None
#######################################
display_network_info() {
    if [[ ! -f "$ENV_FILE" ]]; then
        return
    fi

    echo "┌─ Network Configuration ──────────────────────────────────┐"

    # Read from .env
    local vless_port_internal
    vless_port_internal=$(grep "^VLESS_PORT=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 || echo "N/A")

    local docker_subnet
    docker_subnet=$(grep "^DOCKER_SUBNET=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 || echo "N/A")

    local server_ip
    server_ip=$(grep "^SERVER_IP=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 || echo "N/A")

    # v5.1: Show external port 443 (HAProxy) for clients, internal port for reference
    echo "  Client Port:  443 (HAProxy → Xray:$vless_port_internal)"
    echo "  Subnet:       $docker_subnet"
    echo "  Server IP:    $server_ip"

    echo "└──────────────────────────────────────────────────────────┘"
    echo ""
}

#######################################
# Display user count
# Globals:
#   PROJECT_ROOT
# Arguments:
#   None
# Returns:
#   None
#######################################
display_user_count() {
    local users_json="${PROJECT_ROOT}/config/users.json"

    if [[ ! -f "$users_json" ]]; then
        echo "Active Users: 0"
        return
    fi

    local count
    count=$(jq -r '.users | length' "$users_json" 2>/dev/null || echo "0")

    echo "Active Users: $count"
}

#######################################
# Display proxy configuration status
# TASK-11.5: Service Operations Update
# Globals:
#   XRAY_CONFIG
# Arguments:
#   None
# Returns:
#   None
#######################################
display_proxy_status() {
    if [[ ! -f "$XRAY_CONFIG" ]]; then
        return
    fi

    # Check if proxy inbounds exist
    local has_socks5
    has_socks5=$(jq -e '.inbounds[] | select(.tag == "socks5-proxy")' "$XRAY_CONFIG" >/dev/null 2>&1 && echo "true" || echo "false")

    local has_http
    has_http=$(jq -e '.inbounds[] | select(.tag == "http-proxy")' "$XRAY_CONFIG" >/dev/null 2>&1 && echo "true" || echo "false")

    if [[ "$has_socks5" == "false" && "$has_http" == "false" ]]; then
        echo "┌─ Proxy Configuration ────────────────────────────────────┐"
        echo -e "  Status:     \033[90m● Disabled\033[0m"
        echo "└──────────────────────────────────────────────────────────┘"
        echo ""
        return
    fi

    echo "┌─ Proxy Configuration ────────────────────────────────────┐"
    echo -e "  Status:     \033[32m● Enabled\033[0m"
    echo ""

    # SOCKS5 Proxy
    if [[ "$has_socks5" == "true" ]]; then
        local socks5_port
        socks5_port=$(jq -r '.inbounds[] | select(.tag == "socks5-proxy") | .port' "$XRAY_CONFIG" 2>/dev/null || echo "N/A")

        local socks5_listen
        socks5_listen=$(jq -r '.inbounds[] | select(.tag == "socks5-proxy") | .listen' "$XRAY_CONFIG" 2>/dev/null || echo "N/A")

        local socks5_users
        socks5_users=$(jq -r '.inbounds[] | select(.tag == "socks5-proxy") | .settings.accounts | length' "$XRAY_CONFIG" 2>/dev/null || echo "0")

        echo "  SOCKS5:"
        echo "    Listen:   ${socks5_listen}:${socks5_port}"
        echo "    Users:    $socks5_users"
    fi

    # HTTP Proxy
    if [[ "$has_http" == "true" ]]; then
        local http_port
        http_port=$(jq -r '.inbounds[] | select(.tag == "http-proxy") | .port' "$XRAY_CONFIG" 2>/dev/null || echo "N/A")

        local http_listen
        http_listen=$(jq -r '.inbounds[] | select(.tag == "http-proxy") | .listen' "$XRAY_CONFIG" 2>/dev/null || echo "N/A")

        local http_users
        http_users=$(jq -r '.inbounds[] | select(.tag == "http-proxy") | .settings.accounts | length' "$XRAY_CONFIG" 2>/dev/null || echo "0")

        echo "  HTTP:"
        echo "    Listen:   ${http_listen}:${http_port}"
        echo "    Users:    $http_users"
    fi

    echo "└──────────────────────────────────────────────────────────┘"
    echo ""
}

#######################################
# TASK-8.3: Update Mechanism
#######################################

#######################################
# Update Xray to latest version while preserving configuration
# Per Q-003: Must preserve subnet, port, keys during updates
# Globals:
#   BACKUP_DIR, ENV_FILE, CONFIG_DIR
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
update_xray() {
    log_info "Starting Xray update process..."

    # Create backup before update
    if ! create_config_backup; then
        log_error "Failed to create backup before update"
        return 1
    fi

    log_info "Configuration backup created successfully"

    # Pull latest Xray image
    log_info "Pulling latest Xray image..."
    if ! docker pull teddysun/xray:latest; then
        log_error "Failed to pull latest Xray image"
        return 1
    fi

    log_success "Latest Xray image pulled successfully"

    # Recreate only Xray container (preserves configuration)
    log_info "Recreating Xray container with new image..."
    if ! docker-compose -f "$COMPOSE_FILE" up -d --no-deps --force-recreate "$XRAY_SERVICE"; then
        log_error "Failed to recreate Xray container"
        log_warn "Attempting to restore from backup..."
        restore_config_backup
        return 1
    fi

    log_success "Xray container recreated successfully"

    # Wait for container to be healthy
    log_info "Waiting for Xray container to be healthy..."
    if wait_for_healthy 30; then
        log_success "Xray update completed successfully"

        # Display updated status
        display_service_status

        return 0
    else
        log_error "Xray container failed to start properly"
        log_warn "Attempting to restore from backup..."
        restore_config_backup
        return 1
    fi
}

#######################################
# Update entire system (Xray + Nginx)
# Per Q-003: Must preserve subnet, port, keys during updates
# Globals:
#   COMPOSE_FILE
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
update_system() {
    log_info "Starting system update process..."

    # Create backup before update
    if ! create_config_backup; then
        log_error "Failed to create backup before update"
        return 1
    fi

    log_info "Configuration backup created successfully"

    # Pull latest images
    log_info "Pulling latest images..."
    if ! docker-compose -f "$COMPOSE_FILE" pull; then
        log_error "Failed to pull latest images"
        return 1
    fi

    log_success "Latest images pulled successfully"

    # Recreate containers (preserves volumes and configuration)
    log_info "Recreating containers with new images..."
    if ! docker-compose -f "$COMPOSE_FILE" up -d --force-recreate; then
        log_error "Failed to recreate containers"
        log_warn "Attempting to restore from backup..."
        restore_config_backup
        return 1
    fi

    log_success "Containers recreated successfully"

    # Wait for containers to be healthy
    log_info "Waiting for containers to be healthy..."
    if wait_for_healthy 30; then
        log_success "System update completed successfully"

        # Display updated status
        display_service_status

        return 0
    else
        log_error "Containers failed to start properly"
        log_warn "Attempting to restore from backup..."
        restore_config_backup
        return 1
    fi
}

#######################################
# Create backup of configuration files
# Globals:
#   BACKUP_DIR, ENV_FILE, CONFIG_DIR
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
create_config_backup() {
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)

    local backup_path="${BACKUP_DIR}/${timestamp}"

    mkdir -p "$backup_path"

    # Backup .env file
    if [[ -f "$ENV_FILE" ]]; then
        cp "$ENV_FILE" "${backup_path}/.env" || return 1
    fi

    # Backup config directory
    if [[ -d "$CONFIG_DIR" ]]; then
        cp -r "$CONFIG_DIR" "${backup_path}/config" || return 1
    fi

    # Backup docker-compose.yml
    if [[ -f "$COMPOSE_FILE" ]]; then
        cp "$COMPOSE_FILE" "${backup_path}/docker-compose.yml" || return 1
    fi

    # Create backup manifest
    cat > "${backup_path}/manifest.txt" <<EOF
Backup created: $(date -Iseconds)
System: VLESS Reality VPN
Files backed up:
- .env (network parameters)
- config/ (Xray configuration, users, keys)
- docker-compose.yml (container configuration)
EOF

    # Keep only last 10 backups
    cleanup_old_backups

    log_info "Backup created: ${backup_path}"

    return 0
}

#######################################
# Restore configuration from latest backup
# Globals:
#   BACKUP_DIR, ENV_FILE, CONFIG_DIR
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
restore_config_backup() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_error "Backup directory does not exist"
        return 1
    fi

    # Find latest backup
    local latest_backup
    latest_backup=$(ls -1t "$BACKUP_DIR" | head -n 1)

    if [[ -z "$latest_backup" ]]; then
        log_error "No backups found"
        return 1
    fi

    local backup_path="${BACKUP_DIR}/${latest_backup}"

    log_info "Restoring configuration from: ${latest_backup}"

    # Stop service before restore
    stop_service

    # Restore .env
    if [[ -f "${backup_path}/.env" ]]; then
        cp "${backup_path}/.env" "$ENV_FILE" || return 1
    fi

    # Restore config directory
    if [[ -d "${backup_path}/config" ]]; then
        rm -rf "$CONFIG_DIR"
        cp -r "${backup_path}/config" "$CONFIG_DIR" || return 1
    fi

    # Restore docker-compose.yml
    if [[ -f "${backup_path}/docker-compose.yml" ]]; then
        cp "${backup_path}/docker-compose.yml" "$COMPOSE_FILE" || return 1
    fi

    log_success "Configuration restored successfully"

    # Restart service
    start_service

    return 0
}

#######################################
# Cleanup old backups (keep only last 10)
# Globals:
#   BACKUP_DIR
# Arguments:
#   None
# Returns:
#   None
#######################################
cleanup_old_backups() {
    local backup_count
    backup_count=$(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l)

    if [[ $backup_count -gt 10 ]]; then
        local to_remove=$((backup_count - 10))
        ls -1t "$BACKUP_DIR" | tail -n "$to_remove" | while read -r old_backup; do
            rm -rf "${BACKUP_DIR}/${old_backup}"
            log_debug "Removed old backup: ${old_backup}"
        done
    fi
}

#######################################
# TASK-8.4: Log Display Functions
#######################################

#######################################
# Display logs from Xray container
# Per Q-006: Support ERROR, WARN, INFO filtering
# Arguments:
#   $1 - Number of lines (default: 100)
#   $2 - Log level filter (optional: ERROR, WARN, INFO, DEBUG)
# Returns:
#   0 on success, 1 on failure
#######################################
display_xray_logs() {
    local lines="${1:-100}"
    local level="${2:-}"

    if ! is_container_running "$XRAY_SERVICE"; then
        log_error "Xray container is not running"
        return 1
    fi

    echo "═══════════════════════════════════════════════════════════"
    echo "  Xray Logs (last ${lines} lines)"
    [[ -n "$level" ]] && echo "  Filter: ${level}"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    if [[ -n "$level" ]]; then
        docker-compose -f "$COMPOSE_FILE" logs --tail="$lines" "$XRAY_SERVICE" 2>&1 | \
            filter_logs_by_level "$level"
    else
        docker-compose -f "$COMPOSE_FILE" logs --tail="$lines" "$XRAY_SERVICE" 2>&1
    fi

    echo ""
    echo "═══════════════════════════════════════════════════════════"
}

#######################################
# Display logs from Nginx container
# Arguments:
#   $1 - Number of lines (default: 100)
#   $2 - Log level filter (optional: ERROR, WARN, INFO, DEBUG)
# Returns:
#   0 on success, 1 on failure
#######################################
display_nginx_logs() {
    local lines="${1:-100}"
    local level="${2:-}"

    if ! is_container_running "$NGINX_SERVICE"; then
        log_error "Nginx container is not running"
        return 1
    fi

    echo "═══════════════════════════════════════════════════════════"
    echo "  Nginx Logs (last ${lines} lines)"
    [[ -n "$level" ]] && echo "  Filter: ${level}"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    if [[ -n "$level" ]]; then
        docker-compose -f "$COMPOSE_FILE" logs --tail="$lines" "$NGINX_SERVICE" 2>&1 | \
            filter_logs_by_level "$level"
    else
        docker-compose -f "$COMPOSE_FILE" logs --tail="$lines" "$NGINX_SERVICE" 2>&1
    fi

    echo ""
    echo "═══════════════════════════════════════════════════════════"
}

#######################################
# Display logs from all containers
# Arguments:
#   $1 - Number of lines (default: 100)
#   $2 - Log level filter (optional: ERROR, WARN, INFO, DEBUG)
# Returns:
#   0 on success, 1 on failure
#######################################
display_all_logs() {
    local lines="${1:-100}"
    local level="${2:-}"

    echo "═══════════════════════════════════════════════════════════"
    echo "  All Container Logs (last ${lines} lines)"
    [[ -n "$level" ]] && echo "  Filter: ${level}"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    if [[ -n "$level" ]]; then
        docker-compose -f "$COMPOSE_FILE" logs --tail="$lines" 2>&1 | \
            filter_logs_by_level "$level"
    else
        docker-compose -f "$COMPOSE_FILE" logs --tail="$lines" 2>&1
    fi

    echo ""
    echo "═══════════════════════════════════════════════════════════"
}

#######################################
# Follow logs in real-time
# Arguments:
#   $1 - Service name (xray, nginx, or 'all')
#   $2 - Log level filter (optional: ERROR, WARN, INFO, DEBUG)
# Returns:
#   0 on success, 1 on failure
#######################################
follow_logs() {
    local service="${1:-all}"
    local level="${2:-}"

    echo "═══════════════════════════════════════════════════════════"
    echo "  Following ${service} logs in real-time (Ctrl+C to stop)"
    [[ -n "$level" ]] && echo "  Filter: ${level}"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    local compose_args="-f $COMPOSE_FILE logs --follow"

    if [[ "$service" != "all" ]]; then
        compose_args="$compose_args $service"
    fi

    if [[ -n "$level" ]]; then
        docker-compose $compose_args 2>&1 | filter_logs_by_level "$level"
    else
        docker-compose $compose_args 2>&1
    fi
}

#######################################
# Filter logs by level
# Supports ERROR, WARN, INFO, DEBUG levels
# Arguments:
#   $1 - Log level to filter
# Returns:
#   Filtered log output via stdout
#######################################
filter_logs_by_level() {
    local level="$1"

    # Case-insensitive matching
    case "${level^^}" in
        ERROR)
            grep -iE "(error|fatal|err:|failed)" --color=never
            ;;
        WARN|WARNING)
            grep -iE "(warn|warning)" --color=never
            ;;
        INFO)
            grep -iE "(info|notice)" --color=never
            ;;
        DEBUG)
            grep -iE "(debug|trace)" --color=never
            ;;
        *)
            # No filter, pass through
            cat
            ;;
    esac
}

#######################################
# Export logs to file
# Arguments:
#   $1 - Service name (xray, nginx, or 'all')
#   $2 - Output file path
#   $3 - Number of lines (default: 1000)
# Returns:
#   0 on success, 1 on failure
#######################################
export_logs() {
    local service="$1"
    local output_file="$2"
    local lines="${3:-1000}"

    log_info "Exporting ${service} logs to: ${output_file}"

    local compose_args="-f $COMPOSE_FILE logs --tail=$lines"

    if [[ "$service" != "all" ]]; then
        compose_args="$compose_args $service"
    fi

    if docker-compose $compose_args > "$output_file" 2>&1; then
        log_success "Logs exported successfully: ${output_file}"
        return 0
    else
        log_error "Failed to export logs"
        return 1
    fi
}

#######################################
# Main execution check
#######################################

# If script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    log_error "This script should be sourced, not executed directly"
    exit 1
fi

log_debug "Service operations module loaded"
