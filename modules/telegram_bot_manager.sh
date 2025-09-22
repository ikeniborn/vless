#!/bin/bash

# VLESS+Reality VPN Management System - Telegram Bot Manager
# Version: 1.0.0
# Description: Telegram bot deployment and management
#
# Features:
# - Bot installation and configuration
# - Service management
# - Dependency installation
# - Security configuration
# - Monitoring and health checks
# - Process isolation for EPERM prevention

set -euo pipefail

# Import common utilities
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SOURCE_DIR}/common_utils.sh"

# Setup signal handlers
setup_signal_handlers

# Configuration
readonly BOT_CONFIG_DIR="/opt/vless/config"
readonly BOT_LOG_DIR="/opt/vless/logs"
readonly BOT_DATA_DIR="/opt/vless/data/telegram"
readonly BOT_CONFIG_FILE="${BOT_CONFIG_DIR}/bot_config.env"
readonly BOT_SCRIPT="${SOURCE_DIR}/telegram_bot.py"
readonly BOT_SERVICE_FILE="/etc/systemd/system/vless-telegram-bot.service"
readonly BOT_REQUIREMENTS_FILE="${SOURCE_DIR}/../requirements.txt"

# Python virtual environment
readonly VENV_DIR="/opt/vless/venv"
readonly PYTHON_EXECUTABLE="${VENV_DIR}/bin/python"
readonly PIP_EXECUTABLE="${VENV_DIR}/bin/pip"

# Initialize Telegram bot manager
init_telegram_bot_manager() {
    log_info "Initializing Telegram bot manager"

    # Create directories
    create_directory "$BOT_CONFIG_DIR" "750" "vless:vless"
    create_directory "$BOT_LOG_DIR" "750" "vless:vless"
    create_directory "$BOT_DATA_DIR" "750" "vless:vless"

    # Install system dependencies
    install_system_dependencies

    # Setup Python virtual environment
    setup_python_environment

    log_success "Telegram bot manager initialized"
}

# Install system dependencies
install_system_dependencies() {
    log_info "Installing system dependencies for Telegram bot"

    # Python and pip
    install_package_if_missing "python3"
    install_package_if_missing "python3-pip"
    install_package_if_missing "python3-venv"

    # Image processing libraries
    install_package_if_missing "libjpeg-dev"
    install_package_if_missing "zlib1g-dev"
    install_package_if_missing "libpng-dev"

    # Additional dependencies
    install_package_if_missing "curl"
    install_package_if_missing "wget"

    log_success "System dependencies installed"
}

# Setup Python virtual environment
setup_python_environment() {
    log_info "Setting up Python virtual environment"

    # Create virtual environment if it doesn't exist
    if [[ ! -d "$VENV_DIR" ]]; then
        python3 -m venv "$VENV_DIR"
        log_debug "Created Python virtual environment: $VENV_DIR"
    fi

    # Activate virtual environment and upgrade pip
    source "${VENV_DIR}/bin/activate"

    # Upgrade pip
    "${PIP_EXECUTABLE}" install --upgrade pip

    # Install Python packages
    install_python_packages

    log_success "Python virtual environment setup completed"
}

# Install Python packages
install_python_packages() {
    log_info "Installing Python packages for Telegram bot"

    # Required packages
    local packages=(
        "python-telegram-bot==20.7"
        "qrcode[pil]==7.4.2"
        "Pillow==10.1.0"
        "requests==2.31.0"
        "aiohttp==3.9.1"
    )

    local package
    for package in "${packages[@]}"; do
        log_debug "Installing Python package: $package"
        if ! "${PIP_EXECUTABLE}" install "$package"; then
            log_error "Failed to install Python package: $package"
            return 1
        fi
    done

    # Verify installations
    local verification_imports=(
        "telegram"
        "qrcode"
        "PIL"
        "requests"
        "aiohttp"
    )

    local import_module
    for import_module in "${verification_imports[@]}"; do
        if ! "${PYTHON_EXECUTABLE}" -c "import $import_module" 2>/dev/null; then
            log_error "Failed to verify Python module: $import_module"
            return 1
        fi
    done

    log_success "Python packages installed and verified"
}

# Configure Telegram bot
configure_telegram_bot() {
    local bot_token="$1"
    local admin_chat_id="${2:-}"

    log_info "Configuring Telegram bot"

    # Validate bot token format
    if [[ ! "$bot_token" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
        log_error "Invalid bot token format"
        return 1
    fi

    # Test bot token
    log_info "Testing bot token"
    local test_response
    test_response=$(curl -s "https://api.telegram.org/bot${bot_token}/getMe")

    if ! echo "$test_response" | jq -e '.ok' >/dev/null 2>&1; then
        log_error "Bot token test failed. Please check your token."
        return 1
    fi

    local bot_username
    bot_username=$(echo "$test_response" | jq -r '.result.username')
    log_info "Bot token verified. Bot username: @$bot_username"

    # Create bot configuration
    create_bot_config "$bot_token" "$admin_chat_id"

    # Create authorized users file
    create_authorized_users_file "$admin_chat_id"

    # Set proper permissions
    chmod 600 "$BOT_CONFIG_FILE"
    chown vless:vless "$BOT_CONFIG_FILE"

    log_success "Telegram bot configured successfully"
}

# Create bot configuration file
create_bot_config() {
    local bot_token="$1"
    local admin_chat_id="${2:-}"

    cat > "$BOT_CONFIG_FILE" << EOF
# VLESS Telegram Bot Configuration
# Generated by telegram bot manager

# Bot credentials
TELEGRAM_BOT_TOKEN="$bot_token"
TELEGRAM_ADMIN_CHAT_ID="$admin_chat_id"

# Bot settings
BOT_NAME="VLESS VPN Manager"
BOT_DESCRIPTION="Remote management bot for VLESS VPN"
BOT_TIMEZONE="UTC"

# Security settings
MAX_FAILED_ATTEMPTS=3
LOCKOUT_DURATION=300
SESSION_TIMEOUT=3600

# Logging settings
LOG_LEVEL="INFO"
LOG_FILE="/opt/vless/logs/telegram_bot.log"
AUDIT_LOG_FILE="/opt/vless/logs/telegram_bot_audit.log"

# Feature toggles
ENABLE_USER_MANAGEMENT=true
ENABLE_CONFIG_GENERATION=true
ENABLE_MONITORING=true
ENABLE_BACKUP_MANAGEMENT=true
ENABLE_LOG_ACCESS=true

# Rate limiting
RATE_LIMIT_ENABLED=true
RATE_LIMIT_REQUESTS=10
RATE_LIMIT_WINDOW=60

# Webhook settings (optional)
WEBHOOK_ENABLED=false
WEBHOOK_URL=""
WEBHOOK_SECRET=""

EOF

    log_debug "Bot configuration file created: $BOT_CONFIG_FILE"
}

# Create authorized users file
create_authorized_users_file() {
    local admin_chat_id="${1:-}"

    local authorized_users_file="${BOT_CONFIG_DIR}/authorized_users.json"

    if [[ -n "$admin_chat_id" ]]; then
        cat > "$authorized_users_file" << EOF
{
  "$admin_chat_id": {
    "username": "admin",
    "role": "admin",
    "added_at": "$(date -Iseconds)",
    "permissions": ["all"],
    "notes": "Initial admin user"
  }
}
EOF
    else
        echo "{}" > "$authorized_users_file"
    fi

    chmod 600 "$authorized_users_file"
    chown vless:vless "$authorized_users_file"

    log_debug "Authorized users file created: $authorized_users_file"
}

# Create systemd service
create_bot_service() {
    log_info "Creating systemd service for Telegram bot"

    cat > "$BOT_SERVICE_FILE" << EOF
[Unit]
Description=VLESS Telegram Bot
After=network.target vless-vpn.service
Wants=vless-vpn.service

[Service]
Type=simple
User=vless
Group=vless
WorkingDirectory=$SOURCE_DIR
Environment=PATH=$VENV_DIR/bin
ExecStart=$PYTHON_EXECUTABLE $BOT_SCRIPT
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/opt/vless

# Resource limits
LimitNOFILE=65536
MemoryHigh=512M
MemoryMax=1G

[Install]
WantedBy=multi-user.target

EOF

    chmod 644 "$BOT_SERVICE_FILE"

    # Reload systemd
    systemctl daemon-reload

    log_success "Systemd service created: $BOT_SERVICE_FILE"
}

# Start Telegram bot service
start_bot_service() {
    log_info "Starting Telegram bot service"

    # Validate configuration
    if ! validate_bot_config; then
        log_error "Bot configuration validation failed"
        return 1
    fi

    # Enable and start service
    isolate_systemctl_command "enable" "vless-telegram-bot" 30
    isolate_systemctl_command "start" "vless-telegram-bot" 30

    # Wait for service to start
    if wait_for_condition "systemctl is-active vless-telegram-bot >/dev/null 2>&1" 30 1; then
        log_success "Telegram bot service started successfully"
        return 0
    else
        log_error "Failed to start Telegram bot service"
        return 1
    fi
}

# Stop Telegram bot service
stop_bot_service() {
    log_info "Stopping Telegram bot service"

    isolate_systemctl_command "stop" "vless-telegram-bot" 30
    isolate_systemctl_command "disable" "vless-telegram-bot" 30

    log_success "Telegram bot service stopped"
}

# Restart Telegram bot service
restart_bot_service() {
    log_info "Restarting Telegram bot service"

    isolate_systemctl_command "restart" "vless-telegram-bot" 30

    # Wait for service to restart
    if wait_for_condition "systemctl is-active vless-telegram-bot >/dev/null 2>&1" 30 1; then
        log_success "Telegram bot service restarted successfully"
        return 0
    else
        log_error "Failed to restart Telegram bot service"
        return 1
    fi
}

# Get bot service status
get_bot_status() {
    log_info "Getting Telegram bot service status"

    echo "=== VLESS Telegram Bot Status ==="
    echo ""

    # Service status
    echo "Service Status:"
    if systemctl is-active vless-telegram-bot >/dev/null 2>&1; then
        echo "  Status: 🟢 Active"
        echo "  Uptime: $(systemctl show vless-telegram-bot --property=ActiveEnterTimestamp --value | xargs -I {} date -d {} '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'Unknown')"
    else
        echo "  Status: 🔴 Inactive"
    fi

    # Service enabled status
    if systemctl is-enabled vless-telegram-bot >/dev/null 2>&1; then
        echo "  Auto-start: 🟢 Enabled"
    else
        echo "  Auto-start: 🔴 Disabled"
    fi

    echo ""

    # Configuration status
    echo "Configuration:"
    if [[ -f "$BOT_CONFIG_FILE" ]]; then
        echo "  Config file: 🟢 Present"

        # Check if bot token is configured
        if grep -q "TELEGRAM_BOT_TOKEN=" "$BOT_CONFIG_FILE" && [[ -n "$(grep "TELEGRAM_BOT_TOKEN=" "$BOT_CONFIG_FILE" | cut -d'=' -f2 | tr -d '"')" ]]; then
            echo "  Bot token: 🟢 Configured"
        else
            echo "  Bot token: 🔴 Not configured"
        fi

        # Check admin chat ID
        if grep -q "TELEGRAM_ADMIN_CHAT_ID=" "$BOT_CONFIG_FILE" && [[ -n "$(grep "TELEGRAM_ADMIN_CHAT_ID=" "$BOT_CONFIG_FILE" | cut -d'=' -f2 | tr -d '"')" ]]; then
            echo "  Admin chat ID: 🟢 Configured"
        else
            echo "  Admin chat ID: 🔴 Not configured"
        fi
    else
        echo "  Config file: 🔴 Missing"
    fi

    echo ""

    # Python environment status
    echo "Python Environment:"
    if [[ -d "$VENV_DIR" ]]; then
        echo "  Virtual env: 🟢 Present"
    else
        echo "  Virtual env: 🔴 Missing"
    fi

    if [[ -x "$PYTHON_EXECUTABLE" ]]; then
        echo "  Python: 🟢 Available"
        echo "  Version: $("$PYTHON_EXECUTABLE" --version 2>/dev/null || echo 'Unknown')"
    else
        echo "  Python: 🔴 Not available"
    fi

    echo ""

    # Recent logs
    echo "Recent Logs:"
    if [[ -f "${BOT_LOG_DIR}/telegram_bot.log" ]]; then
        echo "  Last 5 log entries:"
        tail -5 "${BOT_LOG_DIR}/telegram_bot.log" 2>/dev/null | sed 's/^/    /' || echo "    No recent logs"
    else
        echo "  Log file not found"
    fi

    echo ""

    # Authorized users
    echo "Authorized Users:"
    local authorized_users_file="${BOT_CONFIG_DIR}/authorized_users.json"
    if [[ -f "$authorized_users_file" ]]; then
        local user_count
        user_count=$(jq '. | length' "$authorized_users_file" 2>/dev/null || echo "0")
        echo "  Count: $user_count"
    else
        echo "  Authorized users file not found"
    fi
}

# Validate bot configuration
validate_bot_config() {
    log_debug "Validating bot configuration"

    local validation_errors=0

    # Check if config file exists
    if [[ ! -f "$BOT_CONFIG_FILE" ]]; then
        log_error "Bot configuration file not found: $BOT_CONFIG_FILE"
        ((validation_errors++))
    else
        # Check bot token
        local bot_token
        bot_token=$(grep "TELEGRAM_BOT_TOKEN=" "$BOT_CONFIG_FILE" | cut -d'=' -f2 | tr -d '"' || echo "")

        if [[ -z "$bot_token" ]]; then
            log_error "Bot token not configured"
            ((validation_errors++))
        elif [[ ! "$bot_token" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
            log_error "Invalid bot token format"
            ((validation_errors++))
        fi
    fi

    # Check Python environment
    if [[ ! -d "$VENV_DIR" ]]; then
        log_error "Python virtual environment not found: $VENV_DIR"
        ((validation_errors++))
    fi

    if [[ ! -x "$PYTHON_EXECUTABLE" ]]; then
        log_error "Python executable not found: $PYTHON_EXECUTABLE"
        ((validation_errors++))
    fi

    # Check bot script
    if [[ ! -f "$BOT_SCRIPT" ]]; then
        log_error "Bot script not found: $BOT_SCRIPT"
        ((validation_errors++))
    fi

    # Test Python modules
    local required_modules=("telegram" "qrcode" "PIL")
    local module
    for module in "${required_modules[@]}"; do
        if ! "$PYTHON_EXECUTABLE" -c "import $module" 2>/dev/null; then
            log_error "Required Python module not found: $module"
            ((validation_errors++))
        fi
    done

    if [[ $validation_errors -eq 0 ]]; then
        log_success "Bot configuration validation passed"
        return 0
    else
        log_error "Bot configuration validation failed with $validation_errors errors"
        return 1
    fi
}

# Update bot dependencies
update_bot_dependencies() {
    log_info "Updating bot dependencies"

    # Update Python packages
    "${PIP_EXECUTABLE}" install --upgrade pip

    # Update required packages
    local packages=(
        "python-telegram-bot"
        "qrcode[pil]"
        "Pillow"
        "requests"
        "aiohttp"
    )

    local package
    for package in "${packages[@]}"; do
        log_debug "Updating Python package: $package"
        "${PIP_EXECUTABLE}" install --upgrade "$package"
    done

    log_success "Bot dependencies updated"
}

# Add authorized user
add_authorized_user() {
    local chat_id="$1"
    local username="${2:-user}"
    local role="${3:-user}"

    log_info "Adding authorized user: $username (ID: $chat_id)"

    local authorized_users_file="${BOT_CONFIG_DIR}/authorized_users.json"

    # Create file if it doesn't exist
    if [[ ! -f "$authorized_users_file" ]]; then
        echo "{}" > "$authorized_users_file"
        chmod 600 "$authorized_users_file"
        chown vless:vless "$authorized_users_file"
    fi

    # Add user
    local updated_users
    updated_users=$(jq --arg id "$chat_id" --arg username "$username" --arg role "$role" --arg timestamp "$(date -Iseconds)" '
        .[$id] = {
            "username": $username,
            "role": $role,
            "added_at": $timestamp,
            "permissions": (if $role == "admin" then ["all"] else ["status", "config_generation"] end),
            "notes": "Added via bot manager"
        }
    ' "$authorized_users_file")

    echo "$updated_users" > "$authorized_users_file"

    log_success "Authorized user added: $username"
}

# Remove authorized user
remove_authorized_user() {
    local chat_id="$1"

    log_info "Removing authorized user: $chat_id"

    local authorized_users_file="${BOT_CONFIG_DIR}/authorized_users.json"

    if [[ ! -f "$authorized_users_file" ]]; then
        log_error "Authorized users file not found"
        return 1
    fi

    # Remove user
    local updated_users
    updated_users=$(jq --arg id "$chat_id" 'del(.[$id])' "$authorized_users_file")

    echo "$updated_users" > "$authorized_users_file"

    log_success "Authorized user removed: $chat_id"
}

# View bot logs
view_bot_logs() {
    local lines="${1:-50}"
    local log_type="${2:-main}"

    log_info "Viewing bot logs (last $lines lines, type: $log_type)"

    case "$log_type" in
        "main")
            local log_file="${BOT_LOG_DIR}/telegram_bot.log"
            ;;
        "audit")
            local log_file="${BOT_LOG_DIR}/telegram_bot_audit.log"
            ;;
        "systemd")
            log_file=""
            ;;
        *)
            log_error "Invalid log type: $log_type"
            return 1
            ;;
    esac

    if [[ "$log_type" == "systemd" ]]; then
        journalctl -u vless-telegram-bot -n "$lines" --no-pager
    elif [[ -f "$log_file" ]]; then
        tail -n "$lines" "$log_file"
    else
        log_error "Log file not found: $log_file"
        return 1
    fi
}

# Test bot functionality
test_bot() {
    log_info "Testing bot functionality"

    # Check if service is running
    if ! systemctl is-active vless-telegram-bot >/dev/null 2>&1; then
        log_error "Bot service is not running"
        return 1
    fi

    # Test bot token via API
    if [[ -f "$BOT_CONFIG_FILE" ]]; then
        source "$BOT_CONFIG_FILE"

        if [[ -n "$TELEGRAM_BOT_TOKEN" ]]; then
            local test_response
            test_response=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe")

            if echo "$test_response" | jq -e '.ok' >/dev/null 2>&1; then
                local bot_info
                bot_info=$(echo "$test_response" | jq -r '.result | "@\(.username) (\(.first_name))"')
                log_success "Bot API test passed: $bot_info"
            else
                log_error "Bot API test failed"
                return 1
            fi
        else
            log_error "Bot token not configured"
            return 1
        fi
    else
        log_error "Bot configuration file not found"
        return 1
    fi

    # Check recent activity
    local log_file="${BOT_LOG_DIR}/telegram_bot.log"
    if [[ -f "$log_file" ]]; then
        local recent_activity
        recent_activity=$(tail -10 "$log_file" | grep "$(date '+%Y-%m-%d')" | wc -l)
        if [[ $recent_activity -gt 0 ]]; then
            log_info "Recent bot activity detected ($recent_activity log entries today)"
        else
            log_warn "No recent bot activity detected"
        fi
    fi

    log_success "Bot functionality test completed"
}

# Main function for command line usage
main() {
    case "${1:-help}" in
        "init")
            init_telegram_bot_manager
            ;;
        "configure")
            if [[ -z "${2:-}" ]]; then
                log_error "Bot token required: $0 configure <bot_token> [admin_chat_id]"
                exit 1
            fi
            configure_telegram_bot "$2" "${3:-}"
            create_bot_service
            ;;
        "start")
            start_bot_service
            ;;
        "stop")
            stop_bot_service
            ;;
        "restart")
            restart_bot_service
            ;;
        "status")
            get_bot_status
            ;;
        "validate")
            validate_bot_config
            ;;
        "update")
            update_bot_dependencies
            ;;
        "add-user")
            if [[ -z "${2:-}" ]]; then
                log_error "Chat ID required: $0 add-user <chat_id> [username] [role]"
                exit 1
            fi
            add_authorized_user "$2" "${3:-user}" "${4:-user}"
            ;;
        "remove-user")
            if [[ -z "${2:-}" ]]; then
                log_error "Chat ID required: $0 remove-user <chat_id>"
                exit 1
            fi
            remove_authorized_user "$2"
            ;;
        "logs")
            view_bot_logs "${2:-50}" "${3:-main}"
            ;;
        "test")
            test_bot
            ;;
        "help"|*)
            echo "VLESS Telegram Bot Manager Usage:"
            echo "  $0 init                                    - Initialize bot manager"
            echo "  $0 configure <token> [admin_id]            - Configure bot"
            echo "  $0 start                                   - Start bot service"
            echo "  $0 stop                                    - Stop bot service"
            echo "  $0 restart                                 - Restart bot service"
            echo "  $0 status                                  - Show bot status"
            echo "  $0 validate                                - Validate configuration"
            echo "  $0 update                                  - Update dependencies"
            echo "  $0 add-user <chat_id> [username] [role]    - Add authorized user"
            echo "  $0 remove-user <chat_id>                   - Remove authorized user"
            echo "  $0 logs [lines] [type]                     - View logs (main/audit/systemd)"
            echo "  $0 test                                    - Test bot functionality"
            ;;
    esac
}

# Export functions
export -f init_telegram_bot_manager install_system_dependencies setup_python_environment
export -f install_python_packages configure_telegram_bot create_bot_config
export -f create_authorized_users_file create_bot_service start_bot_service
export -f stop_bot_service restart_bot_service get_bot_status validate_bot_config
export -f update_bot_dependencies add_authorized_user remove_authorized_user
export -f view_bot_logs test_bot

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

log_debug "Telegram bot manager module loaded successfully"