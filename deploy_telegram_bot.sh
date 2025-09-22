#!/bin/bash

# VLESS+Reality VPN Management System - Telegram Bot Deployment
# Version: 1.0.0
# Description: Complete Telegram bot deployment script
#
# This script handles the full deployment process for the VLESS Telegram bot:
# - Dependency installation
# - Configuration setup
# - Service deployment
# - Security configuration
# - Testing and validation

set -euo pipefail

# Import common utilities and modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/modules/common_utils.sh"
source "${SCRIPT_DIR}/modules/telegram_bot_manager.sh"

# Setup signal handlers
setup_signal_handlers

# Configuration
readonly DEPLOYMENT_LOG="${SCRIPT_DIR}/logs/telegram_bot_deployment.log"
readonly CONFIG_TEMPLATE="${SCRIPT_DIR}/config/bot_config.env"

# Deployment modes
readonly INTERACTIVE_MODE=true
readonly VALIDATE_ONLY=false

# Color output for interactive mode
readonly BOLD='\033[1m'
readonly UNDERLINE='\033[4m'

# Initialize deployment
init_deployment() {
    log_info "Starting VLESS Telegram Bot deployment"

    # Create logs directory if it doesn't exist
    create_directory "$(dirname "$DEPLOYMENT_LOG")" "750" "vless:vless"

    # Log deployment start
    {
        echo "=== VLESS Telegram Bot Deployment ==="
        echo "Started: $(get_timestamp)"
        echo "User: $(whoami)"
        echo "System: $(get_system_info)"
        echo ""
    } >> "$DEPLOYMENT_LOG"

    log_success "Deployment initialized"
}

# Interactive configuration
interactive_configuration() {
    if [[ "$INTERACTIVE_MODE" != "true" ]]; then
        return 0
    fi

    echo -e "\n${BOLD}🤖 VLESS Telegram Bot Deployment${NC}"
    echo -e "${UNDERLINE}Interactive Configuration${NC}\n"

    # Welcome message
    cat << 'EOF'
This script will help you deploy the VLESS Telegram Bot for remote management.

Prerequisites:
1. A Telegram bot token from @BotFather
2. Your Telegram chat ID (get from @userinfobot)
3. Root or sudo access on this server

The bot will provide secure remote access to:
- Server status monitoring
- User management
- Configuration generation with QR codes
- System monitoring and alerts
- Backup management
- Log viewing

EOF

    # Confirmation
    if ! confirm_prompt "Continue with Telegram bot deployment?"; then
        log_info "Deployment cancelled by user"
        exit 0
    fi

    echo ""
}

# Collect bot configuration
collect_bot_configuration() {
    local bot_token=""
    local admin_chat_id=""

    echo -e "${BOLD}Step 1: Bot Configuration${NC}"
    echo "Please provide your Telegram bot credentials:"
    echo ""

    # Get bot token
    while [[ -z "$bot_token" ]]; do
        echo -n "Enter your Telegram bot token (from @BotFather): "
        read -r bot_token

        if [[ -z "$bot_token" ]]; then
            echo -e "${RED}❌ Bot token cannot be empty${NC}"
            continue
        fi

        if [[ ! "$bot_token" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
            echo -e "${RED}❌ Invalid bot token format${NC}"
            echo "Expected format: 123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
            bot_token=""
            continue
        fi

        # Test bot token
        echo "Testing bot token..."
        if ! validate_bot_token "$bot_token"; then
            echo -e "${RED}❌ Bot token validation failed${NC}"
            bot_token=""
            continue
        fi

        echo -e "${GREEN}✅ Bot token validated successfully${NC}"
    done

    echo ""

    # Get admin chat ID
    while [[ -z "$admin_chat_id" ]]; do
        echo -n "Enter your Telegram chat ID (from @userinfobot): "
        read -r admin_chat_id

        if [[ -z "$admin_chat_id" ]]; then
            echo -e "${RED}❌ Chat ID cannot be empty${NC}"
            continue
        fi

        if [[ ! "$admin_chat_id" =~ ^-?[0-9]+$ ]]; then
            echo -e "${RED}❌ Invalid chat ID format (must be numeric)${NC}"
            admin_chat_id=""
            continue
        fi

        echo -e "${GREEN}✅ Chat ID format validated${NC}"
    done

    echo ""

    # Security features configuration
    echo -e "${BOLD}Step 2: Security Configuration${NC}"
    echo "Configure security features for your bot:"
    echo ""

    local enable_monitoring="y"
    local enable_user_mgmt="y"
    local enable_backup_mgmt="y"

    if confirm_prompt "Enable system monitoring features? (recommended)"; then
        enable_monitoring="y"
    else
        enable_monitoring="n"
    fi

    if confirm_prompt "Enable user management features?"; then
        enable_user_mgmt="y"
    else
        enable_user_mgmt="n"
    fi

    if confirm_prompt "Enable backup management features?"; then
        enable_backup_mgmt="y"
    else
        enable_backup_mgmt="n"
    fi

    echo ""

    # Export configuration
    export BOT_TOKEN="$bot_token"
    export ADMIN_CHAT_ID="$admin_chat_id"
    export ENABLE_MONITORING="$enable_monitoring"
    export ENABLE_USER_MGMT="$enable_user_mgmt"
    export ENABLE_BACKUP_MGMT="$enable_backup_mgmt"

    log_info "Bot configuration collected successfully"
}

# Validate bot token via API
validate_bot_token() {
    local token="$1"

    log_debug "Validating bot token via Telegram API"

    local response
    if response=$(curl -s --connect-timeout 10 "https://api.telegram.org/bot${token}/getMe"); then
        if echo "$response" | jq -e '.ok' >/dev/null 2>&1; then
            local bot_info
            bot_info=$(echo "$response" | jq -r '.result | "@\(.username) (\(.first_name))"')
            log_info "Bot validated: $bot_info"
            return 0
        fi
    fi

    log_error "Bot token validation failed"
    return 1
}

# Confirmation prompt
confirm_prompt() {
    local prompt="$1"
    local response

    echo -n "$prompt [y/N]: "
    read -r response

    case "$response" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Deploy bot system
deploy_bot() {
    echo -e "\n${BOLD}Step 3: Bot Deployment${NC}"
    echo "Installing and configuring the Telegram bot..."
    echo ""

    # Initialize bot manager
    log_info "Initializing bot manager"
    init_telegram_bot_manager

    # Configure bot
    log_info "Configuring bot with provided credentials"
    configure_telegram_bot "$BOT_TOKEN" "$ADMIN_CHAT_ID"

    # Create systemd service
    log_info "Creating systemd service"
    create_bot_service

    # Apply security configuration
    apply_security_configuration

    log_success "Bot deployment completed"
}

# Apply security configuration
apply_security_configuration() {
    log_info "Applying security configuration"

    # Set proper file permissions
    chmod 600 "${SCRIPT_DIR}/config/bot_config.env"
    chown vless:vless "${SCRIPT_DIR}/config/bot_config.env"

    # Create authorized users file
    local authorized_users_file="${SCRIPT_DIR}/config/authorized_users.json"
    if [[ ! -f "$authorized_users_file" ]]; then
        create_authorized_users_file "$ADMIN_CHAT_ID"
    fi

    # Configure firewall rules if UFW is available
    if command_exists ufw && ufw status | grep -q "Status: active"; then
        log_info "Configuring firewall for bot (if using webhooks)"
        # Note: Bot uses polling by default, so no firewall changes needed
        # If webhook mode is enabled, appropriate rules would be added here
    fi

    log_success "Security configuration applied"
}

# Test bot deployment
test_deployment() {
    echo -e "\n${BOLD}Step 4: Deployment Testing${NC}"
    echo "Testing bot deployment and functionality..."
    echo ""

    # Validate configuration
    log_info "Validating bot configuration"
    if ! validate_bot_config; then
        log_error "Configuration validation failed"
        return 1
    fi

    # Start bot service
    log_info "Starting bot service"
    if ! start_bot_service; then
        log_error "Failed to start bot service"
        return 1
    fi

    # Wait for service to be ready
    log_info "Waiting for bot to initialize..."
    sleep 10

    # Test bot functionality
    log_info "Testing bot functionality"
    if ! test_bot; then
        log_error "Bot functionality test failed"
        return 1
    fi

    echo -e "${GREEN}✅ Bot deployment test completed successfully${NC}"
    log_success "Deployment testing completed"
}

# Display deployment summary
display_deployment_summary() {
    echo -e "\n${BOLD}🎉 Deployment Summary${NC}"
    echo -e "${UNDERLINE}VLESS Telegram Bot Successfully Deployed${NC}\n"

    # Bot information
    echo "Bot Configuration:"
    echo "  • Service: vless-telegram-bot"
    echo "  • Status: $(systemctl is-active vless-telegram-bot 2>/dev/null || echo 'unknown')"
    echo "  • Config: ${SCRIPT_DIR}/config/bot_config.env"
    echo "  • Logs: ${SCRIPT_DIR}/logs/telegram_bot.log"
    echo ""

    # Next steps
    echo "Next Steps:"
    echo "  1. Send /start to your bot to verify it's working"
    echo "  2. Review bot status: telegram_bot_manager.sh status"
    echo "  3. View bot logs: telegram_bot_manager.sh logs"
    echo "  4. Add more users: telegram_bot_manager.sh add-user <chat_id>"
    echo ""

    # Security reminders
    echo "Security Reminders:"
    echo "  • Keep your bot token secure and private"
    echo "  • Regularly review authorized users"
    echo "  • Monitor bot logs for suspicious activity"
    echo "  • Update bot dependencies regularly"
    echo ""

    # Available commands
    echo "Bot Commands:"
    echo "  • /status - Server status"
    echo "  • /users - User management"
    echo "  • /config <username> - Generate user config"
    echo "  • /monitor - System monitoring"
    echo "  • /backup - Backup management"
    echo "  • /help - Show all commands"
    echo ""

    # Support information
    echo "Support:"
    echo "  • Documentation: ${SCRIPT_DIR}/docs/"
    echo "  • Bot manager: ${SCRIPT_DIR}/modules/telegram_bot_manager.sh"
    echo "  • Deployment log: $DEPLOYMENT_LOG"
    echo ""

    log_success "Deployment completed successfully"
}

# Handle deployment failure
handle_deployment_failure() {
    local exit_code=$1

    echo -e "\n${RED}❌ Deployment Failed${NC}"
    echo "The Telegram bot deployment encountered an error."
    echo ""

    echo "Troubleshooting:"
    echo "  1. Check deployment log: $DEPLOYMENT_LOG"
    echo "  2. Verify bot token and chat ID"
    echo "  3. Ensure system dependencies are installed"
    echo "  4. Check network connectivity"
    echo ""

    echo "Recovery options:"
    echo "  • Re-run deployment: $0"
    echo "  • Manual configuration: telegram_bot_manager.sh configure <token> <chat_id>"
    echo "  • Check bot status: telegram_bot_manager.sh status"
    echo ""

    log_error "Deployment failed with exit code: $exit_code"

    # Log failure details
    {
        echo "=== Deployment Failure ==="
        echo "Time: $(get_timestamp)"
        echo "Exit code: $exit_code"
        echo "User: $(whoami)"
        echo ""
    } >> "$DEPLOYMENT_LOG"

    exit "$exit_code"
}

# Cleanup on exit
cleanup_deployment() {
    log_debug "Cleaning up deployment resources"

    # Clear sensitive environment variables
    unset BOT_TOKEN ADMIN_CHAT_ID

    # Remove any temporary files
    find /tmp -name "*vless_bot*" -type f -mtime +0 -delete 2>/dev/null || true

    log_debug "Deployment cleanup completed"
}

# Pre-deployment checks
pre_deployment_checks() {
    log_info "Performing pre-deployment checks"

    # Check if running as root or with sudo
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi

    # Check network connectivity
    if ! check_network_connectivity; then
        log_error "Network connectivity check failed"
        exit 1
    fi

    # Check if VLESS system is installed
    if [[ ! -d "/opt/vless" ]]; then
        log_error "VLESS system not found. Please install VLESS first."
        exit 1
    fi

    # Check available disk space
    local available_space
    available_space=$(df /opt/vless | awk 'NR==2{print $4}')
    if [[ $available_space -lt 100000 ]]; then  # 100MB minimum
        log_warn "Low disk space detected. Consider freeing up space."
    fi

    log_success "Pre-deployment checks completed"
}

# Main deployment function
main() {
    # Set up cleanup trap
    trap cleanup_deployment EXIT
    trap 'handle_deployment_failure $?' ERR

    # Parse command line arguments
    case "${1:-deploy}" in
        "deploy")
            # Full interactive deployment
            init_deployment
            pre_deployment_checks
            interactive_configuration
            collect_bot_configuration
            deploy_bot
            test_deployment
            display_deployment_summary
            ;;
        "validate")
            # Validation only mode
            init_deployment
            pre_deployment_checks
            if validate_bot_config; then
                echo "✅ Bot configuration is valid"
                exit 0
            else
                echo "❌ Bot configuration validation failed"
                exit 1
            fi
            ;;
        "quick")
            # Quick deployment with provided arguments
            if [[ -z "${2:-}" || -z "${3:-}" ]]; then
                echo "Usage: $0 quick <bot_token> <admin_chat_id>"
                exit 1
            fi
            export BOT_TOKEN="$2"
            export ADMIN_CHAT_ID="$3"
            export INTERACTIVE_MODE=false

            init_deployment
            pre_deployment_checks
            deploy_bot
            test_deployment
            display_deployment_summary
            ;;
        "help"|*)
            echo "VLESS Telegram Bot Deployment Script"
            echo ""
            echo "Usage:"
            echo "  $0 [deploy]                      - Interactive deployment (default)"
            echo "  $0 quick <token> <chat_id>       - Quick deployment with provided credentials"
            echo "  $0 validate                      - Validate existing configuration"
            echo "  $0 help                          - Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                               - Start interactive deployment"
            echo "  $0 quick 123456:ABC 987654321    - Quick deploy with credentials"
            echo "  $0 validate                      - Check current configuration"
            echo ""
            ;;
    esac
}

# Export functions for external use
export -f init_deployment interactive_configuration collect_bot_configuration
export -f validate_bot_token confirm_prompt deploy_bot apply_security_configuration
export -f test_deployment display_deployment_summary handle_deployment_failure
export -f cleanup_deployment pre_deployment_checks

# Run main function
main "$@"