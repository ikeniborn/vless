#!/bin/bash

# VLESS+Reality VPN - Telegram Bot Management Script
# Management utilities for the Telegram bot service
# Version: 1.0
# Author: VLESS Management System

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_utils.sh"

# Configuration
readonly BOT_SERVICE="vless-vpn"
readonly BOT_CONFIG_FILE="/opt/vless/config/bot_config.env"
readonly BOT_SCRIPT="/opt/vless/modules/telegram_bot.py"
readonly BOT_LOG_FILE="/opt/vless/logs/telegram_bot.log"
readonly ADMIN_DB_FILE="/opt/vless/config/bot_admins.db"
readonly SERVICE_FILE="/etc/systemd/system/vless-vpn.service"

# Bot status functions
bot_status() {
    echo "=== VLESS VPN Telegram Bot Status ==="
    echo

    # Service status
    if systemctl is-active "${BOT_SERVICE}" > /dev/null 2>&1; then
        echo "Service Status: ✅ Running"
        local since
        since=$(systemctl show "${BOT_SERVICE}" --property=ActiveEnterTimestamp --value)
        echo "Started: ${since}"
    else
        echo "Service Status: ❌ Stopped"
    fi

    # Configuration status
    if [[ -f "${BOT_CONFIG_FILE}" ]]; then
        echo "Configuration: ✅ Found"

        # Check required settings
        if grep -q "^BOT_TOKEN=" "${BOT_CONFIG_FILE}" && \
           grep -q "^ADMIN_CHAT_ID=" "${BOT_CONFIG_FILE}"; then
            echo "Required Settings: ✅ Configured"
        else
            echo "Required Settings: ❌ Missing BOT_TOKEN or ADMIN_CHAT_ID"
        fi
    else
        echo "Configuration: ❌ Missing"
    fi

    # Process information
    if pgrep -f "telegram_bot.py" > /dev/null; then
        local pid
        pid=$(pgrep -f "telegram_bot.py")
        local memory
        memory=$(ps -p "${pid}" -o rss= | awk '{printf "%.1f MB", $1/1024}' 2>/dev/null || echo "Unknown")
        echo "Process ID: ${pid}"
        echo "Memory Usage: ${memory}"
    fi

    # Log file info
    if [[ -f "${BOT_LOG_FILE}" ]]; then
        local log_size
        log_size=$(du -sh "${BOT_LOG_FILE}" | cut -f1)
        local last_modified
        last_modified=$(stat -c %y "${BOT_LOG_FILE}" | cut -d'.' -f1)
        echo "Log File: ${log_size} (${last_modified})"
    else
        echo "Log File: Not found"
    fi

    # Admin count
    if [[ -f "${ADMIN_DB_FILE}" ]]; then
        local admin_count
        admin_count=$(sqlite3 "${ADMIN_DB_FILE}" "SELECT COUNT(*) FROM admins WHERE active = 1" 2>/dev/null || echo "0")
        echo "Admin Users: ${admin_count}"
    else
        echo "Admin Database: Not initialized"
    fi

    echo
}

# Start bot service
start_bot() {
    log_info "Starting Telegram bot service..."

    # Validate configuration before starting
    if ! validate_bot_config; then
        log_error "Bot configuration validation failed"
        return 1
    fi

    # Install service if not exists
    if [[ ! -f "${SERVICE_FILE}" ]]; then
        log_info "Installing systemd service..."
        install_bot_service
    fi

    # Start service
    systemctl start "${BOT_SERVICE}"

    # Wait for service to start
    sleep 3

    if systemctl is-active "${BOT_SERVICE}" > /dev/null 2>&1; then
        log_info "Telegram bot started successfully"

        # Test bot connection
        test_bot_connection
    else
        log_error "Failed to start Telegram bot"
        return 1
    fi
}

# Stop bot service
stop_bot() {
    log_info "Stopping Telegram bot service..."

    if systemctl is-active "${BOT_SERVICE}" > /dev/null 2>&1; then
        systemctl stop "${BOT_SERVICE}"
        log_info "Telegram bot stopped"
    else
        log_warn "Telegram bot is not running"
    fi
}

# Restart bot service
restart_bot() {
    log_info "Restarting Telegram bot service..."

    if systemctl is-active "${BOT_SERVICE}" > /dev/null 2>&1; then
        systemctl restart "${BOT_SERVICE}"
    else
        start_bot
        return $?
    fi

    # Wait for service to restart
    sleep 3

    if systemctl is-active "${BOT_SERVICE}" > /dev/null 2>&1; then
        log_info "Telegram bot restarted successfully"
    else
        log_error "Failed to restart Telegram bot"
        return 1
    fi
}

# Enable bot service
enable_bot() {
    log_info "Enabling Telegram bot service for auto-start..."

    # Install service if not exists
    if [[ ! -f "${SERVICE_FILE}" ]]; then
        install_bot_service
    fi

    systemctl enable "${BOT_SERVICE}"
    log_info "Telegram bot service enabled"
}

# Disable bot service
disable_bot() {
    log_info "Disabling Telegram bot service..."

    systemctl disable "${BOT_SERVICE}"
    log_info "Telegram bot service disabled"
}

# Install systemd service
install_bot_service() {
    log_info "Installing Telegram bot systemd service..."

    # Copy service file
    cp "/opt/vless/config/vless-vpn.service" "${SERVICE_FILE}"

    # Reload systemd
    systemctl daemon-reload

    log_info "Systemd service installed"
}

# Uninstall systemd service
uninstall_bot_service() {
    log_info "Uninstalling Telegram bot systemd service..."

    # Stop and disable service
    systemctl stop "${BOT_SERVICE}" 2>/dev/null || true
    systemctl disable "${BOT_SERVICE}" 2>/dev/null || true

    # Remove service file
    rm -f "${SERVICE_FILE}"

    # Reload systemd
    systemctl daemon-reload

    log_info "Systemd service uninstalled"
}

# Validate bot configuration
validate_bot_config() {
    log_info "Validating bot configuration..."

    local errors=0

    # Check if config file exists
    if [[ ! -f "${BOT_CONFIG_FILE}" ]]; then
        log_error "Configuration file not found: ${BOT_CONFIG_FILE}"
        return 1
    fi

    # Check required settings
    if ! grep -q "^BOT_TOKEN=" "${BOT_CONFIG_FILE}" || \
       grep -q "^BOT_TOKEN=$" "${BOT_CONFIG_FILE}"; then
        log_error "BOT_TOKEN is not set in configuration"
        ((errors++))
    fi

    if ! grep -q "^ADMIN_CHAT_ID=" "${BOT_CONFIG_FILE}" || \
       grep -q "^ADMIN_CHAT_ID=$" "${BOT_CONFIG_FILE}"; then
        log_error "ADMIN_CHAT_ID is not set in configuration"
        ((errors++))
    fi

    # Check bot script exists
    if [[ ! -f "${BOT_SCRIPT}" ]]; then
        log_error "Bot script not found: ${BOT_SCRIPT}"
        ((errors++))
    fi

    # Check Python dependencies
    if ! python3 -c "import telegram" 2>/dev/null; then
        log_error "python-telegram-bot library not installed"
        ((errors++))
    fi

    if [[ ${errors} -eq 0 ]]; then
        log_info "Configuration validation passed"
        return 0
    else
        log_error "Configuration validation failed with ${errors} error(s)"
        return 1
    fi
}

# Test bot connection
test_bot_connection() {
    log_info "Testing bot connection..."

    # Wait a moment for bot to initialize
    sleep 5

    # Check if bot is responsive by looking at logs
    if [[ -f "${BOT_LOG_FILE}" ]]; then
        local recent_log
        recent_log=$(tail -20 "${BOT_LOG_FILE}" | grep -E "(Started|Running|Bot)" | tail -1)

        if [[ -n "${recent_log}" ]]; then
            log_info "Bot appears to be running: ${recent_log}"
        else
            log_warn "No recent bot activity in logs"
        fi
    else
        log_warn "Bot log file not found"
    fi
}

# Setup bot configuration
setup_bot_config() {
    local bot_token="$1"
    local admin_chat_id="$2"

    log_info "Setting up bot configuration..."

    # Validate inputs
    if [[ -z "${bot_token}" || -z "${admin_chat_id}" ]]; then
        log_error "Bot token and admin chat ID are required"
        return 1
    fi

    # Update configuration file
    if [[ -f "${BOT_CONFIG_FILE}" ]]; then
        # Update existing config
        sed -i "s/^BOT_TOKEN=.*/BOT_TOKEN=${bot_token}/" "${BOT_CONFIG_FILE}"
        sed -i "s/^ADMIN_CHAT_ID=.*/ADMIN_CHAT_ID=${admin_chat_id}/" "${BOT_CONFIG_FILE}"
    else
        log_error "Configuration file not found"
        return 1
    fi

    log_info "Bot configuration updated"
    log_info "Please restart the bot service to apply changes"
}

# Add admin user
add_admin() {
    local user_id="$1"
    local username="${2:-"Unknown"}"

    log_info "Adding admin user: ${user_id}"

    # Initialize admin database if needed
    if [[ ! -f "${ADMIN_DB_FILE}" ]]; then
        init_admin_db
    fi

    # Add admin to database
    sqlite3 "${ADMIN_DB_FILE}" "
        INSERT OR REPLACE INTO admins (user_id, username, added_by, added_at, active)
        VALUES (${user_id}, '${username}', 'manual', datetime('now'), 1);
    "

    log_info "Admin user added successfully"
}

# Remove admin user
remove_admin() {
    local user_id="$1"

    log_info "Removing admin user: ${user_id}"

    if [[ ! -f "${ADMIN_DB_FILE}" ]]; then
        log_error "Admin database not found"
        return 1
    fi

    sqlite3 "${ADMIN_DB_FILE}" "
        UPDATE admins SET active = 0 WHERE user_id = ${user_id};
    "

    log_info "Admin user removed successfully"
}

# List admin users
list_admins() {
    log_info "Admin users:"

    if [[ ! -f "${ADMIN_DB_FILE}" ]]; then
        log_warn "Admin database not found"
        return 0
    fi

    sqlite3 "${ADMIN_DB_FILE}" -header -column "
        SELECT user_id, username, added_by, added_at, active
        FROM admins
        ORDER BY added_at DESC;
    "
}

# Initialize admin database
init_admin_db() {
    log_info "Initializing admin database..."

    sqlite3 "${ADMIN_DB_FILE}" "
        CREATE TABLE IF NOT EXISTS admins (
            user_id INTEGER PRIMARY KEY,
            username TEXT,
            first_name TEXT,
            last_name TEXT,
            added_by TEXT,
            added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            active INTEGER DEFAULT 1
        );
    "

    log_info "Admin database initialized"
}

# View bot logs
view_logs() {
    local lines="${1:-50}"

    if [[ -f "${BOT_LOG_FILE}" ]]; then
        echo "=== Last ${lines} lines of bot log ==="
        tail -n "${lines}" "${BOT_LOG_FILE}"
    else
        echo "Bot log file not found: ${BOT_LOG_FILE}"
    fi
}

# Follow bot logs
follow_logs() {
    if [[ -f "${BOT_LOG_FILE}" ]]; then
        echo "Following bot logs (Ctrl+C to stop)..."
        tail -f "${BOT_LOG_FILE}"
    else
        echo "Bot log file not found: ${BOT_LOG_FILE}"
    fi
}

# Clear bot logs
clear_logs() {
    if [[ -f "${BOT_LOG_FILE}" ]]; then
        log_info "Clearing bot logs..."
        > "${BOT_LOG_FILE}"
        log_info "Bot logs cleared"
    else
        log_warn "Bot log file not found"
    fi
}

# Install Python dependencies
install_dependencies() {
    log_info "Installing Python dependencies..."

    # Check if pip is available
    if ! command -v pip3 &> /dev/null; then
        log_info "Installing pip..."
        apt-get update
        apt-get install -y python3-pip
    fi

    # Install requirements
    if [[ -f "/opt/vless/requirements.txt" ]]; then
        pip3 install -r /opt/vless/requirements.txt
        log_info "Dependencies installed successfully"
    else
        log_error "Requirements file not found"
        return 1
    fi
}

# Update bot
update_bot() {
    log_info "Updating Telegram bot..."

    # Stop bot
    stop_bot

    # Update dependencies
    install_dependencies

    # Restart bot
    start_bot

    log_info "Bot update completed"
}

# Main function
main() {
    case "${1:-}" in
        "status")
            bot_status
            ;;
        "start")
            start_bot
            ;;
        "stop")
            stop_bot
            ;;
        "restart")
            restart_bot
            ;;
        "enable")
            enable_bot
            ;;
        "disable")
            disable_bot
            ;;
        "install")
            install_bot_service
            ;;
        "uninstall")
            uninstall_bot_service
            ;;
        "validate")
            validate_bot_config
            ;;
        "setup")
            if [[ -z "${2:-}" || -z "${3:-}" ]]; then
                echo "Usage: $0 setup <bot_token> <admin_chat_id>"
                exit 1
            fi
            setup_bot_config "$2" "$3"
            ;;
        "add-admin")
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 add-admin <user_id> [username]"
                exit 1
            fi
            add_admin "$2" "${3:-}"
            ;;
        "remove-admin")
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 remove-admin <user_id>"
                exit 1
            fi
            remove_admin "$2"
            ;;
        "list-admins")
            list_admins
            ;;
        "logs")
            view_logs "${2:-50}"
            ;;
        "follow-logs")
            follow_logs
            ;;
        "clear-logs")
            clear_logs
            ;;
        "install-deps")
            install_dependencies
            ;;
        "update")
            update_bot
            ;;
        "test")
            test_bot_connection
            ;;
        *)
            echo "Usage: $0 {command} [options]"
            echo
            echo "Service Management:"
            echo "  status              Show bot service status"
            echo "  start               Start bot service"
            echo "  stop                Stop bot service"
            echo "  restart             Restart bot service"
            echo "  enable              Enable auto-start"
            echo "  disable             Disable auto-start"
            echo
            echo "Installation:"
            echo "  install             Install systemd service"
            echo "  uninstall           Remove systemd service"
            echo "  install-deps        Install Python dependencies"
            echo "  update              Update bot and dependencies"
            echo
            echo "Configuration:"
            echo "  validate            Validate configuration"
            echo "  setup <token> <id>  Setup bot configuration"
            echo "  test                Test bot connection"
            echo
            echo "Admin Management:"
            echo "  add-admin <id>      Add admin user"
            echo "  remove-admin <id>   Remove admin user"
            echo "  list-admins         List admin users"
            echo
            echo "Logging:"
            echo "  logs [lines]        View bot logs"
            echo "  follow-logs         Follow logs in real-time"
            echo "  clear-logs          Clear log file"
            exit 1
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi