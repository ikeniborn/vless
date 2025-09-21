#!/bin/bash

# VLESS+Reality VPN - Telegram Bot Deployment Script
# Complete deployment and setup script for the Telegram bot
# Version: 1.0
# Author: VLESS Management System

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly VLESS_DIR="/opt/vless"
readonly CONFIG_DIR="${VLESS_DIR}/config"
readonly MODULES_DIR="${VLESS_DIR}/modules"
readonly LOGS_DIR="${VLESS_DIR}/logs"
readonly SERVICE_NAME="vless-vpn"

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Display banner
show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║               VLESS+Reality VPN Telegram Bot                 ║
║                    Deployment Script                        ║
║                                                              ║
║  This script will deploy and configure the Telegram bot     ║
║  for remote management of your VLESS VPN server.            ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Check system requirements
check_requirements() {
    log_step "Checking system requirements..."

    local missing_deps=()

    # Check Python 3
    if ! command -v python3 &> /dev/null; then
        missing_deps+=("python3")
    fi

    # Check pip
    if ! command -v pip3 &> /dev/null; then
        missing_deps+=("python3-pip")
    fi

    # Check SQLite
    if ! command -v sqlite3 &> /dev/null; then
        missing_deps+=("sqlite3")
    fi

    # Check systemctl
    if ! command -v systemctl &> /dev/null; then
        log_error "systemd is required but not found"
        exit 1
    fi

    # Install missing dependencies
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_info "Installing missing dependencies: ${missing_deps[*]}"
        apt-get update
        apt-get install -y "${missing_deps[@]}"
    fi

    # Check Python version
    local python_version
    python_version=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")

    if [[ $(echo "${python_version} < 3.8" | bc -l) -eq 1 ]]; then
        log_error "Python 3.8 or higher is required (found: ${python_version})"
        exit 1
    fi

    log_success "System requirements check passed"
}

# Setup directories
setup_directories() {
    log_step "Setting up directories..."

    # Create necessary directories
    mkdir -p "${VLESS_DIR}"/{config,modules,logs,backups,users,qrcodes}

    # Set proper permissions
    chown -R root:root "${VLESS_DIR}"
    chmod -R 700 "${VLESS_DIR}"

    # Make modules executable
    if [[ -d "${MODULES_DIR}" ]]; then
        chmod +x "${MODULES_DIR}"/*.sh 2>/dev/null || true
        chmod +x "${MODULES_DIR}"/*.py 2>/dev/null || true
    fi

    log_success "Directories setup completed"
}

# Copy files to target locations
copy_files() {
    log_step "Copying files to target locations..."

    # Copy modules
    if [[ -d "${SCRIPT_DIR}/modules" ]]; then
        cp -r "${SCRIPT_DIR}/modules"/* "${MODULES_DIR}/"
        chmod +x "${MODULES_DIR}"/*.sh "${MODULES_DIR}"/*.py
    fi

    # Copy config files
    if [[ -d "${SCRIPT_DIR}/config" ]]; then
        cp -r "${SCRIPT_DIR}/config"/* "${CONFIG_DIR}/"
    fi

    # Copy requirements.txt
    if [[ -f "${SCRIPT_DIR}/requirements.txt" ]]; then
        cp "${SCRIPT_DIR}/requirements.txt" "${VLESS_DIR}/"
    fi

    log_success "Files copied successfully"
}

# Install Python dependencies
install_python_deps() {
    log_step "Installing Python dependencies..."

    if [[ -f "${VLESS_DIR}/requirements.txt" ]]; then
        # Upgrade pip first
        python3 -m pip install --upgrade pip

        # Install requirements
        python3 -m pip install -r "${VLESS_DIR}/requirements.txt"

        log_success "Python dependencies installed"
    else
        log_warn "requirements.txt not found, skipping Python dependencies"
    fi
}

# Configure bot
configure_bot() {
    log_step "Configuring Telegram bot..."

    local bot_token=""
    local admin_chat_id=""

    # Check if configuration already exists
    if [[ -f "${CONFIG_DIR}/bot_config.env" ]]; then
        # Check if already configured
        if grep -q "^BOT_TOKEN=.\+" "${CONFIG_DIR}/bot_config.env" && \
           grep -q "^ADMIN_CHAT_ID=.\+" "${CONFIG_DIR}/bot_config.env"; then
            log_info "Bot already configured"
            return 0
        fi
    fi

    echo
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║                   Bot Configuration                      ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════╝${NC}"
    echo

    echo -e "${CYAN}To configure the Telegram bot, you need:${NC}"
    echo "1. A bot token from @BotFather on Telegram"
    echo "2. Your Telegram user ID (send /start to @userinfobot)"
    echo

    # Get bot token
    while [[ -z "${bot_token}" ]]; do
        read -p "Enter your bot token: " bot_token
        if [[ ! "${bot_token}" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
            echo -e "${RED}Invalid bot token format${NC}"
            bot_token=""
        fi
    done

    # Get admin chat ID
    while [[ -z "${admin_chat_id}" ]]; do
        read -p "Enter your Telegram user ID: " admin_chat_id
        if [[ ! "${admin_chat_id}" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Invalid user ID format${NC}"
            admin_chat_id=""
        fi
    done

    # Update configuration
    sed -i "s/^BOT_TOKEN=.*/BOT_TOKEN=${bot_token}/" "${CONFIG_DIR}/bot_config.env"
    sed -i "s/^ADMIN_CHAT_ID=.*/ADMIN_CHAT_ID=${admin_chat_id}/" "${CONFIG_DIR}/bot_config.env"

    log_success "Bot configuration updated"
}

# Install systemd service
install_service() {
    log_step "Installing systemd service..."

    # Copy service file
    cp "${CONFIG_DIR}/vless-vpn.service" "/etc/systemd/system/"

    # Reload systemd
    systemctl daemon-reload

    # Enable service
    systemctl enable "${SERVICE_NAME}"

    log_success "Systemd service installed and enabled"
}

# Test bot configuration
test_bot() {
    log_step "Testing bot configuration..."

    # Validate configuration
    if ! "${MODULES_DIR}/telegram_bot_manager.sh" validate; then
        log_error "Bot configuration validation failed"
        return 1
    fi

    # Start bot service
    systemctl start "${SERVICE_NAME}"

    # Wait for startup
    sleep 5

    # Check if service is running
    if systemctl is-active "${SERVICE_NAME}" > /dev/null 2>&1; then
        log_success "Bot service started successfully"

        # Show status
        "${MODULES_DIR}/telegram_bot_manager.sh" status

        echo
        echo -e "${GREEN}✅ Bot is ready!${NC}"
        echo -e "${CYAN}Send /start to your bot on Telegram to test it.${NC}"

        return 0
    else
        log_error "Bot service failed to start"

        # Show logs for debugging
        echo "Service logs:"
        journalctl -u "${SERVICE_NAME}" --no-pager -n 20

        return 1
    fi
}

# Show deployment summary
show_summary() {
    echo
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                 Deployment Summary                      ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo

    echo -e "${CYAN}Telegram Bot Commands:${NC}"
    echo "• ${MODULES_DIR}/telegram_bot_manager.sh status    - Check bot status"
    echo "• ${MODULES_DIR}/telegram_bot_manager.sh restart   - Restart bot"
    echo "• ${MODULES_DIR}/telegram_bot_manager.sh logs      - View bot logs"
    echo

    echo -e "${CYAN}Systemd Commands:${NC}"
    echo "• systemctl status ${SERVICE_NAME}      - Check service status"
    echo "• systemctl restart ${SERVICE_NAME}     - Restart service"
    echo "• systemctl stop ${SERVICE_NAME}        - Stop service"
    echo "• journalctl -u ${SERVICE_NAME} -f      - Follow service logs"
    echo

    echo -e "${CYAN}Configuration Files:${NC}"
    echo "• ${CONFIG_DIR}/bot_config.env          - Bot configuration"
    echo "• ${LOGS_DIR}/telegram_bot.log          - Bot logs"
    echo "• /etc/systemd/system/${SERVICE_NAME}.service - Service file"
    echo

    echo -e "${CYAN}Next Steps:${NC}"
    echo "1. Send /start to your bot on Telegram to test it"
    echo "2. Use /help to see all available commands"
    echo "3. Add more admin users with the bot if needed"
    echo
}

# Uninstall bot
uninstall_bot() {
    log_step "Uninstalling Telegram bot..."

    # Stop and disable service
    systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
    systemctl disable "${SERVICE_NAME}" 2>/dev/null || true

    # Remove service file
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"

    # Reload systemd
    systemctl daemon-reload

    # Remove bot files (optional - ask user)
    read -p "Remove bot files and configuration? (y/N): " confirm
    if [[ "${confirm}" == "y" || "${confirm}" == "Y" ]]; then
        rm -rf "${VLESS_DIR}/modules/telegram_bot.py"
        rm -rf "${VLESS_DIR}/modules/telegram_bot_manager.sh"
        rm -rf "${CONFIG_DIR}/bot_config.env"
        rm -rf "${CONFIG_DIR}/vless-vpn.service"
        rm -rf "${LOGS_DIR}/telegram_bot.log"
        log_info "Bot files removed"
    fi

    log_success "Bot uninstalled"
}

# Update bot
update_bot() {
    log_step "Updating Telegram bot..."

    # Stop service
    systemctl stop "${SERVICE_NAME}" 2>/dev/null || true

    # Backup current configuration
    if [[ -f "${CONFIG_DIR}/bot_config.env" ]]; then
        cp "${CONFIG_DIR}/bot_config.env" "${CONFIG_DIR}/bot_config.env.backup"
        log_info "Configuration backed up"
    fi

    # Update files
    copy_files

    # Update dependencies
    install_python_deps

    # Reload service
    systemctl daemon-reload

    # Start service
    systemctl start "${SERVICE_NAME}"

    # Check status
    if systemctl is-active "${SERVICE_NAME}" > /dev/null 2>&1; then
        log_success "Bot updated successfully"
    else
        log_error "Bot update failed"
        return 1
    fi
}

# Main deployment function
deploy() {
    show_banner

    log_info "Starting Telegram bot deployment..."
    echo

    check_root
    check_requirements
    setup_directories
    copy_files
    install_python_deps
    configure_bot
    install_service

    if test_bot; then
        show_summary
        log_success "Telegram bot deployment completed successfully!"
    else
        log_error "Deployment completed with errors. Please check the logs."
        return 1
    fi
}

# Main function
main() {
    case "${1:-deploy}" in
        "deploy")
            deploy
            ;;
        "install")
            deploy
            ;;
        "uninstall")
            uninstall_bot
            ;;
        "update")
            update_bot
            ;;
        "configure")
            configure_bot
            ;;
        "test")
            test_bot
            ;;
        "status")
            if [[ -f "${MODULES_DIR}/telegram_bot_manager.sh" ]]; then
                "${MODULES_DIR}/telegram_bot_manager.sh" status
            else
                log_error "Bot manager not found. Run deployment first."
            fi
            ;;
        "start")
            systemctl start "${SERVICE_NAME}"
            log_info "Bot service started"
            ;;
        "stop")
            systemctl stop "${SERVICE_NAME}"
            log_info "Bot service stopped"
            ;;
        "restart")
            systemctl restart "${SERVICE_NAME}"
            log_info "Bot service restarted"
            ;;
        "logs")
            journalctl -u "${SERVICE_NAME}" -f
            ;;
        *)
            echo "Usage: $0 {deploy|install|uninstall|update|configure|test|status|start|stop|restart|logs}"
            echo
            echo "Commands:"
            echo "  deploy      - Full deployment (default)"
            echo "  install     - Same as deploy"
            echo "  uninstall   - Remove bot installation"
            echo "  update      - Update bot to latest version"
            echo "  configure   - Reconfigure bot settings"
            echo "  test        - Test bot configuration"
            echo "  status      - Show bot status"
            echo "  start       - Start bot service"
            echo "  stop        - Stop bot service"
            echo "  restart     - Restart bot service"
            echo "  logs        - Follow bot logs"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"