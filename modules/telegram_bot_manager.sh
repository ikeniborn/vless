#!/bin/bash
# Telegram Bot Manager Script for VLESS VPN Project
# Provides utilities for managing the Telegram bot service
# Author: Claude Code
# Version: 1.0

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Import common utilities
source "${SCRIPT_DIR}/common_utils.sh" || {
    echo "ERROR: Cannot load common utilities module" >&2
    exit 1
}

# Bot management constants
readonly BOT_CONTAINER_NAME="vless-telegram-bot"
readonly BOT_IMAGE_NAME="vless-telegram-bot:latest"
readonly DOCKER_COMPOSE_FILE="$PROJECT_DIR/config/docker-compose.yml"
readonly BOT_CONFIG_FILE="$PROJECT_DIR/config/bot_config.env"
readonly BOT_LOG_FILE="/opt/vless/logs/telegram_bot.log"

# Function to check if Docker is running
check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        log_message "ERROR" "Docker is not installed"
        return 1
    fi

    if ! docker info >/dev/null 2>&1; then
        log_message "ERROR" "Docker daemon is not running"
        return 1
    fi

    return 0
}

# Function to check if Docker Compose is available
check_docker_compose() {
    if command -v docker-compose >/dev/null 2>&1; then
        echo "docker-compose"
    elif docker compose version >/dev/null 2>&1; then
        echo "docker compose"
    else
        log_message "ERROR" "Docker Compose is not available"
        return 1
    fi
}

# Function to validate bot configuration
validate_bot_config() {
    log_message "INFO" "Validating bot configuration"

    if [[ ! -f "$BOT_CONFIG_FILE" ]]; then
        log_message "ERROR" "Bot configuration file not found: $BOT_CONFIG_FILE"
        return 1
    fi

    # Source the config file to check variables
    set -a
    source "$BOT_CONFIG_FILE"
    set +a

    # Check required variables
    local required_vars=("TELEGRAM_BOT_TOKEN" "ADMIN_TELEGRAM_ID")
    local missing_vars=()

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_message "ERROR" "Missing required configuration variables: ${missing_vars[*]}"
        log_message "INFO" "Please update $BOT_CONFIG_FILE with the required values"
        return 1
    fi

    # Validate ADMIN_TELEGRAM_ID is numeric
    if ! [[ "$ADMIN_TELEGRAM_ID" =~ ^[0-9]+$ ]]; then
        log_message "ERROR" "ADMIN_TELEGRAM_ID must be a numeric value"
        return 1
    fi

    log_message "SUCCESS" "Bot configuration is valid"
    return 0
}

# Function to build bot image
build_bot_image() {
    log_message "INFO" "Building bot Docker image"

    if ! check_docker; then
        return 1
    fi

    local compose_cmd
    if ! compose_cmd=$(check_docker_compose); then
        return 1
    fi

    cd "$PROJECT_DIR"

    # Build the image
    if ! $compose_cmd -f "$DOCKER_COMPOSE_FILE" build telegram-bot; then
        log_message "ERROR" "Failed to build bot image"
        return 1
    fi

    log_message "SUCCESS" "Bot image built successfully"
    return 0
}

# Function to start bot
start_bot() {
    log_message "INFO" "Starting Telegram bot"

    if ! validate_bot_config; then
        return 1
    fi

    if ! check_docker; then
        return 1
    fi

    local compose_cmd
    if ! compose_cmd=$(check_docker_compose); then
        return 1
    fi

    cd "$PROJECT_DIR"

    # Start the bot service
    if ! $compose_cmd -f "$DOCKER_COMPOSE_FILE" up -d telegram-bot; then
        log_message "ERROR" "Failed to start bot"
        return 1
    fi

    # Wait a moment for startup
    sleep 3

    # Check if container is running
    if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "$BOT_CONTAINER_NAME"; then
        log_message "SUCCESS" "Telegram bot started successfully"

        # Show logs
        log_message "INFO" "Recent bot logs:"
        docker logs --tail 10 "$BOT_CONTAINER_NAME" 2>/dev/null || true
    else
        log_message "ERROR" "Bot container failed to start"
        return 1
    fi

    return 0
}

# Function to stop bot
stop_bot() {
    log_message "INFO" "Stopping Telegram bot"

    if ! check_docker; then
        return 1
    fi

    local compose_cmd
    if ! compose_cmd=$(check_docker_compose); then
        return 1
    fi

    cd "$PROJECT_DIR"

    # Stop the bot service
    if ! $compose_cmd -f "$DOCKER_COMPOSE_FILE" stop telegram-bot; then
        log_message "ERROR" "Failed to stop bot"
        return 1
    fi

    log_message "SUCCESS" "Telegram bot stopped successfully"
    return 0
}

# Function to restart bot
restart_bot() {
    log_message "INFO" "Restarting Telegram bot"

    stop_bot || true
    sleep 2
    start_bot
}

# Function to check bot status
check_bot_status() {
    log_message "INFO" "Checking Telegram bot status"

    if ! check_docker; then
        return 1
    fi

    # Check if container exists
    if ! docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | grep -q "$BOT_CONTAINER_NAME"; then
        log_message "WARNING" "Bot container does not exist"
        return 1
    fi

    # Get container status
    local container_status
    container_status=$(docker inspect --format='{{.State.Status}}' "$BOT_CONTAINER_NAME" 2>/dev/null || echo "unknown")

    print_section "Telegram Bot Status"
    printf "%-20s %s\n" "Container Name:" "$BOT_CONTAINER_NAME"
    printf "%-20s %s\n" "Status:" "$container_status"

    if [[ "$container_status" == "running" ]]; then
        local uptime
        uptime=$(docker inspect --format='{{.State.StartedAt}}' "$BOT_CONTAINER_NAME" 2>/dev/null || echo "unknown")
        printf "%-20s %s\n" "Started At:" "$uptime"

        # Show resource usage
        local stats
        if stats=$(docker stats --no-stream --format "table {{.CPUPerc}}\t{{.MemUsage}}" "$BOT_CONTAINER_NAME" 2>/dev/null); then
            printf "%-20s %s\n" "Resource Usage:" "$stats"
        fi
    fi

    return 0
}

# Function to view bot logs
view_bot_logs() {
    local lines="${1:-50}"
    local follow="${2:-false}"

    log_message "INFO" "Viewing bot logs (last $lines lines)"

    if ! check_docker; then
        return 1
    fi

    # Check if container exists
    if ! docker ps -a --format "table {{.Names}}" | grep -q "$BOT_CONTAINER_NAME"; then
        log_message "WARNING" "Bot container does not exist"
        return 1
    fi

    # Show logs
    if [[ "$follow" == "true" ]]; then
        docker logs -f --tail "$lines" "$BOT_CONTAINER_NAME"
    else
        docker logs --tail "$lines" "$BOT_CONTAINER_NAME"
    fi

    return 0
}

# Function to update bot
update_bot() {
    log_message "INFO" "Updating Telegram bot"

    # Stop the bot
    stop_bot || true

    # Rebuild the image
    if ! build_bot_image; then
        return 1
    fi

    # Start the bot
    start_bot
}

# Function to remove bot
remove_bot() {
    log_message "INFO" "Removing Telegram bot"

    if ! check_docker; then
        return 1
    fi

    local compose_cmd
    if ! compose_cmd=$(check_docker_compose); then
        return 1
    fi

    cd "$PROJECT_DIR"

    # Stop and remove the bot service
    $compose_cmd -f "$DOCKER_COMPOSE_FILE" down telegram-bot

    # Remove the image
    if docker images --format "table {{.Repository}}\t{{.Tag}}" | grep -q "$BOT_IMAGE_NAME"; then
        docker rmi "$BOT_IMAGE_NAME" || log_message "WARNING" "Failed to remove bot image"
    fi

    log_message "SUCCESS" "Telegram bot removed successfully"
    return 0
}

# Function to backup bot configuration
backup_bot_config() {
    local backup_dir="${1:-/opt/vless/backups}"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="$backup_dir/bot_config_backup_$timestamp.tar.gz"

    log_message "INFO" "Creating bot configuration backup"

    ensure_directory "$backup_dir" "755" "root"

    # Create backup archive
    tar -czf "$backup_file" -C "$PROJECT_DIR" \
        config/bot_config.env \
        modules/telegram_bot.py \
        modules/telegram_bot_manager.sh \
        Dockerfile.bot \
        requirements.txt 2>/dev/null || {
        log_message "ERROR" "Failed to create backup"
        return 1
    }

    log_message "SUCCESS" "Bot configuration backup created: $backup_file"
    return 0
}

# Function to show bot configuration
show_bot_config() {
    log_message "INFO" "Current bot configuration"

    if [[ ! -f "$BOT_CONFIG_FILE" ]]; then
        log_message "ERROR" "Configuration file not found: $BOT_CONFIG_FILE"
        return 1
    fi

    print_section "Bot Configuration"

    # Show non-sensitive configuration
    grep -E "^[A-Z_]+=" "$BOT_CONFIG_FILE" | \
    grep -v -E "(TOKEN|PASSWORD|SECRET|KEY)" | \
    while IFS='=' read -r key value; do
        printf "%-25s %s\n" "$key:" "$value"
    done

    return 0
}

# Function to test bot configuration
test_bot_config() {
    log_message "INFO" "Testing bot configuration"

    if ! validate_bot_config; then
        return 1
    fi

    # Source configuration
    set -a
    source "$BOT_CONFIG_FILE"
    set +a

    # Test Python dependencies
    python3 -c "
import sys
try:
    import telegram
    import qrcode
    print('✓ Python dependencies are available')
    sys.exit(0)
except ImportError as e:
    print(f'✗ Missing Python dependency: {e}')
    sys.exit(1)
" || {
        log_message "ERROR" "Python dependencies test failed"
        return 1
    }

    # Test Telegram API
    python3 -c "
import asyncio
import sys
from telegram import Bot

async def test_bot():
    try:
        bot = Bot(token='$TELEGRAM_BOT_TOKEN')
        bot_info = await bot.get_me()
        print(f'✓ Bot connection successful: @{bot_info.username}')
        await bot.close()
        return True
    except Exception as e:
        print(f'✗ Bot connection failed: {e}')
        return False

if asyncio.run(test_bot()):
    sys.exit(0)
else:
    sys.exit(1)
" || {
        log_message "ERROR" "Telegram API test failed"
        return 1
    }

    log_message "SUCCESS" "All configuration tests passed"
    return 0
}

# Function to show help
show_help() {
    cat << EOF
VLESS VPN Telegram Bot Manager

Usage: $0 <command> [options]

Commands:
  start         Start the Telegram bot
  stop          Stop the Telegram bot
  restart       Restart the Telegram bot
  status        Show bot status
  logs [lines]  View bot logs (default: 50 lines)
  follow-logs   Follow bot logs in real-time
  build         Build bot Docker image
  update        Update bot (rebuild and restart)
  remove        Remove bot completely
  backup        Backup bot configuration
  config        Show current configuration
  test          Test bot configuration
  validate      Validate configuration only
  help          Show this help message

Examples:
  $0 start                    # Start the bot
  $0 logs 100                 # View last 100 log lines
  $0 test                     # Test configuration
  $0 backup /tmp              # Backup to /tmp directory

Configuration:
  Bot configuration is stored in: $BOT_CONFIG_FILE
  Logs are written to: $BOT_LOG_FILE
EOF
}

# Main function
main() {
    local command="${1:-help}"

    case "$command" in
        "start")
            start_bot
            ;;
        "stop")
            stop_bot
            ;;
        "restart")
            restart_bot
            ;;
        "status")
            check_bot_status
            ;;
        "logs")
            local lines="${2:-50}"
            view_bot_logs "$lines"
            ;;
        "follow-logs")
            view_bot_logs 50 true
            ;;
        "build")
            build_bot_image
            ;;
        "update")
            update_bot
            ;;
        "remove")
            remove_bot
            ;;
        "backup")
            local backup_dir="${2:-/opt/vless/backups}"
            backup_bot_config "$backup_dir"
            ;;
        "config")
            show_bot_config
            ;;
        "test")
            test_bot_config
            ;;
        "validate")
            validate_bot_config
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi