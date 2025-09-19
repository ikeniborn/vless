#!/bin/bash
# Phase 4 Integration Module for VLESS VPN Project
# Integration of security, logging, monitoring and maintenance modules
# Author: Claude Code
# Version: 1.0

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load common utilities
source "${SCRIPT_DIR}/common_utils.sh"

# Integration configuration
readonly INTEGRATION_LOG="/var/log/vless/phase4-integration.log"
readonly INTEGRATION_STATE_FILE="/opt/vless/phase4_installed"
readonly SYSTEMD_SERVICE_PATH="/etc/systemd/system/vless-vpn.service"

# Log integration events
log_integration() {
    local level="$1"
    local message="$2"
    local timestamp=$(get_timestamp)

    echo "[$timestamp] [$level] $message" | tee -a "$INTEGRATION_LOG"
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Phase 4 Prerequisites"

    local missing_modules=()

    # Check for required modules
    local required_modules=(
        "security_hardening.sh"
        "logging_setup.sh"
        "monitoring.sh"
        "maintenance_utils.sh"
    )

    for module in "${required_modules[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$module" ]]; then
            missing_modules+=("$module")
        fi
    done

    if [[ ${#missing_modules[@]} -gt 0 ]]; then
        print_error "Missing required modules: ${missing_modules[*]}"
        return 1
    fi

    # Check for existing installation
    if [[ ! -f "/opt/vless/docker-compose.yml" ]]; then
        print_error "VLESS base installation not found. Please run the main installation first."
        return 1
    fi

    # Check if Docker is running
    if ! systemctl is-active --quiet docker; then
        print_error "Docker is not running. Please start Docker first."
        return 1
    fi

    print_success "All prerequisites satisfied"
    return 0
}

# Install Phase 4 components
install_phase4() {
    print_header "Installing VLESS Phase 4 Components"

    log_integration "INFO" "Starting Phase 4 installation"

    # Check prerequisites
    if ! check_prerequisites; then
        log_integration "ERROR" "Prerequisites check failed"
        return 1
    fi

    # Create necessary directories
    ensure_directory "/var/log/vless" "755" "syslog"
    ensure_directory "/opt/vless/phase4" "755" "root"

    # Install components in order
    install_logging_system
    install_security_hardening
    install_monitoring_system
    install_systemd_service
    configure_maintenance_tools

    # Mark installation as complete
    echo "$(get_timestamp)" > "$INTEGRATION_STATE_FILE"

    print_success "Phase 4 installation completed successfully"
    log_integration "INFO" "Phase 4 installation completed successfully"
}

# Install logging system
install_logging_system() {
    print_section "Installing Logging System"

    # Source and run logging setup
    source "$SCRIPT_DIR/logging_setup.sh"

    if setup_logging; then
        print_success "Logging system installed successfully"
        log_integration "INFO" "Logging system installed"
    else
        print_error "Failed to install logging system"
        log_integration "ERROR" "Logging system installation failed"
        return 1
    fi
}

# Install security hardening
install_security_hardening() {
    print_section "Installing Security Hardening"

    # Source and run security hardening
    source "$SCRIPT_DIR/security_hardening.sh"

    if apply_security_hardening; then
        print_success "Security hardening applied successfully"
        log_integration "INFO" "Security hardening applied"
    else
        print_error "Failed to apply security hardening"
        log_integration "ERROR" "Security hardening failed"
        return 1
    fi
}

# Install monitoring system
install_monitoring_system() {
    print_section "Installing Monitoring System"

    # Source and run monitoring setup
    source "$SCRIPT_DIR/monitoring.sh"

    if setup_monitoring; then
        print_success "Monitoring system installed successfully"
        log_integration "INFO" "Monitoring system installed"
    else
        print_error "Failed to install monitoring system"
        log_integration "ERROR" "Monitoring system installation failed"
        return 1
    fi
}

# Install systemd service
install_systemd_service() {
    print_section "Installing SystemD Service"

    local service_file="$SCRIPT_DIR/../config/vless-vpn.service"

    if [[ ! -f "$service_file" ]]; then
        print_error "SystemD service file not found: $service_file"
        return 1
    fi

    # Copy service file
    sudo cp "$service_file" "$SYSTEMD_SERVICE_PATH"

    # Update service file with correct paths
    sudo sed -i "s|/opt/vless|/opt/vless|g" "$SYSTEMD_SERVICE_PATH"
    sudo sed -i "s|WorkingDirectory=.*|WorkingDirectory=/opt/vless|g" "$SYSTEMD_SERVICE_PATH"

    # Reload systemd and enable service
    sudo systemctl daemon-reload
    sudo systemctl enable vless-vpn.service

    print_success "SystemD service installed and enabled"
    log_integration "INFO" "SystemD service installed"
}

# Configure maintenance tools
configure_maintenance_tools() {
    print_section "Configuring Maintenance Tools"

    # Create maintenance script wrapper
    sudo tee "/usr/local/bin/vless-maintenance" > /dev/null << EOF
#!/bin/bash
# VLESS Maintenance Script Wrapper

MAINTENANCE_SCRIPT="/opt/vless/modules/maintenance_utils.sh"

if [[ -f "\$MAINTENANCE_SCRIPT" ]]; then
    bash "\$MAINTENANCE_SCRIPT" "\$@"
else
    echo "Maintenance script not found: \$MAINTENANCE_SCRIPT"
    exit 1
fi
EOF

    sudo chmod +x "/usr/local/bin/vless-maintenance"

    # Create daily maintenance cron job
    sudo tee "/etc/cron.d/vless-daily-maintenance" > /dev/null << 'EOF'
# VLESS Daily Maintenance
# Run daily cleanup and checks at 3 AM

0 3 * * * root /usr/local/bin/vless-maintenance cleanup >/dev/null 2>&1
EOF

    print_success "Maintenance tools configured"
    log_integration "INFO" "Maintenance tools configured"
}

# Update existing configurations
update_configurations() {
    print_section "Updating Existing Configurations"

    # Update docker-compose.yml with logging configuration
    update_docker_compose_logging

    # Update Telegram bot with new commands
    update_telegram_bot_commands

    # Update Xray configuration for logging
    update_xray_logging_config

    print_success "Configurations updated"
    log_integration "INFO" "Existing configurations updated"
}

# Update docker-compose.yml for logging
update_docker_compose_logging() {
    local compose_file="/opt/vless/docker-compose.yml"

    if [[ ! -f "$compose_file" ]]; then
        print_warning "Docker Compose file not found: $compose_file"
        return 1
    fi

    # Backup original file
    backup_file "$compose_file"

    # Check if logging configuration already exists
    if grep -q "logging:" "$compose_file"; then
        print_info "Logging configuration already exists in docker-compose.yml"
        return 0
    fi

    # Add logging configuration to services
    local temp_file=$(mktemp)

    awk '
    /^  [a-zA-Z].*:$/ {
        service_name = $1
        gsub(":", "", service_name)
        print $0
        in_service = 1
        next
    }
    /^[[:space:]]*$/ {
        if (in_service && !logging_added) {
            print "    logging:"
            print "      driver: \"syslog\""
            print "      options:"
            print "        syslog-address: \"unixgram:///dev/log\""
            print "        tag: \"vless-" service_name "\""
            logging_added = 1
        }
        in_service = 0
        logging_added = 0
    }
    /^[^[:space:]]/ {
        if (in_service && !logging_added) {
            print "    logging:"
            print "      driver: \"syslog\""
            print "      options:"
            print "        syslog-address: \"unixgram:///dev/log\""
            print "        tag: \"vless-" service_name "\""
            logging_added = 1
        }
        in_service = 0
        logging_added = 0
    }
    { print }
    ' "$compose_file" > "$temp_file"

    mv "$temp_file" "$compose_file"

    print_success "Docker Compose logging configuration updated"
}

# Update Telegram bot with new commands
update_telegram_bot_commands() {
    local bot_file="/opt/vless/modules/telegram_bot.py"

    if [[ ! -f "$bot_file" ]]; then
        print_warning "Telegram bot file not found: $bot_file"
        return 1
    fi

    # Check if Phase 4 commands already exist
    if grep -q "security_status" "$bot_file"; then
        print_info "Phase 4 commands already exist in Telegram bot"
        return 0
    fi

    # Backup bot file
    backup_file "$bot_file"

    # Add new command handlers
    cat >> "$bot_file" << 'EOF'

# Phase 4 Commands

async def security_status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Show security status"""
    if not await check_admin(update):
        return

    try:
        # Run security status check
        result = subprocess.run(
            ['/opt/vless/modules/security_hardening.sh', 'status'],
            capture_output=True, text=True, timeout=30
        )

        status_text = f"🔒 Security Status:\n\n{result.stdout}"
        await update.message.reply_text(status_text, parse_mode='HTML')

    except Exception as e:
        await update.message.reply_text(f"❌ Error checking security status: {str(e)}")

async def monitoring_status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Show monitoring status"""
    if not await check_admin(update):
        return

    try:
        # Run monitoring status check
        result = subprocess.run(
            ['/opt/vless/modules/monitoring.sh', 'status'],
            capture_output=True, text=True, timeout=30
        )

        status_text = f"📊 Monitoring Status:\n\n{result.stdout}"
        await update.message.reply_text(status_text, parse_mode='HTML')

    except Exception as e:
        await update.message.reply_text(f"❌ Error checking monitoring status: {str(e)}")

async def maintenance_menu(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Show maintenance options"""
    if not await check_admin(update):
        return

    keyboard = [
        [InlineKeyboardButton("🧹 Clean Temp Files", callback_data='maint_cleanup')],
        [InlineKeyboardButton("📋 System Report", callback_data='maint_report')],
        [InlineKeyboardButton("🔍 Validate Configs", callback_data='maint_validate')],
        [InlineKeyboardButton("👥 User Statistics", callback_data='maint_users')],
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)

    await update.message.reply_text(
        "🔧 Maintenance Menu:\nSelect an operation:",
        reply_markup=reply_markup
    )

async def handle_maintenance_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle maintenance callback buttons"""
    query = update.callback_query
    await query.answer()

    if not await check_admin_callback(query):
        return

    action = query.data.replace('maint_', '')

    try:
        if action == 'cleanup':
            result = subprocess.run(['/usr/local/bin/vless-maintenance', 'cleanup'],
                                 capture_output=True, text=True, timeout=120)
        elif action == 'report':
            result = subprocess.run(['/usr/local/bin/vless-maintenance', 'report'],
                                 capture_output=True, text=True, timeout=60)
        elif action == 'validate':
            result = subprocess.run(['/usr/local/bin/vless-maintenance', 'validate'],
                                 capture_output=True, text=True, timeout=30)
        elif action == 'users':
            result = subprocess.run(['/usr/local/bin/vless-maintenance', 'users', 'user-statistics'],
                                 capture_output=True, text=True, timeout=30)

        if result.returncode == 0:
            message = f"✅ {action.title()} completed successfully:\n\n{result.stdout[:1000]}"
        else:
            message = f"❌ {action.title()} failed:\n\n{result.stderr[:500]}"

        await query.edit_message_text(message)

    except Exception as e:
        await query.edit_message_text(f"❌ Error running {action}: {str(e)}")

# Add command handlers to main function
def main():
    # ... existing code ...

    # Add new handlers
    application.add_handler(CommandHandler("security", security_status))
    application.add_handler(CommandHandler("monitoring", monitoring_status))
    application.add_handler(CommandHandler("maintenance", maintenance_menu))
    application.add_handler(CallbackQueryHandler(handle_maintenance_callback, pattern='^maint_'))

    # ... rest of existing code ...
EOF

    print_success "Telegram bot updated with Phase 4 commands"
}

# Update Xray logging configuration
update_xray_logging_config() {
    local xray_config="/opt/vless/configs/xray_config.json"

    if [[ ! -f "$xray_config" ]]; then
        print_warning "Xray configuration not found: $xray_config"
        return 1
    fi

    # Check if logging is already configured
    if jq -e '.log' "$xray_config" >/dev/null 2>&1; then
        print_info "Xray logging already configured"
        return 0
    fi

    # Backup configuration
    backup_file "$xray_config"

    # Add logging configuration
    local temp_file=$(mktemp)

    jq '. + {
        "log": {
            "access": "/var/log/vless/xray-access.log",
            "error": "/var/log/vless/xray-error.log",
            "loglevel": "info"
        }
    }' "$xray_config" > "$temp_file"

    mv "$temp_file" "$xray_config"

    print_success "Xray logging configuration updated"
}

# Show Phase 4 status
show_phase4_status() {
    print_header "VLESS Phase 4 Status"

    # Check installation status
    printf "%-30s " "Phase 4 installed:"
    if [[ -f "$INTEGRATION_STATE_FILE" ]]; then
        local install_date=$(cat "$INTEGRATION_STATE_FILE")
        echo -e "${GREEN}Yes${NC} (installed: $install_date)"
    else
        echo -e "${RED}No${NC}"
    fi

    # Check component status
    echo
    print_section "Component Status"

    # Logging system
    printf "%-30s " "Logging system:"
    if [[ -f "/etc/rsyslog.d/49-vless.conf" ]] && [[ -f "/usr/local/bin/vless-logger" ]]; then
        echo -e "${GREEN}Configured${NC}"
    else
        echo -e "${RED}Not configured${NC}"
    fi

    # Security hardening
    printf "%-30s " "Security hardening:"
    if [[ -f "/etc/fail2ban/jail.local" ]] && [[ -f "/etc/sysctl.d/99-vless-security.conf" ]]; then
        echo -e "${GREEN}Applied${NC}"
    else
        echo -e "${RED}Not applied${NC}"
    fi

    # Monitoring system
    printf "%-30s " "Monitoring system:"
    if [[ -f "/etc/cron.d/vless-monitoring" ]] && [[ -f "/usr/local/bin/vless-monitoring" ]]; then
        echo -e "${GREEN}Active${NC}"
    else
        echo -e "${RED}Not active${NC}"
    fi

    # SystemD service
    printf "%-30s " "SystemD service:"
    if [[ -f "$SYSTEMD_SERVICE_PATH" ]]; then
        if systemctl is-enabled --quiet vless-vpn; then
            echo -e "${GREEN}Enabled${NC}"
        else
            echo -e "${YELLOW}Installed but not enabled${NC}"
        fi
    else
        echo -e "${RED}Not installed${NC}"
    fi

    # Maintenance tools
    printf "%-30s " "Maintenance tools:"
    if [[ -f "/usr/local/bin/vless-maintenance" ]]; then
        echo -e "${GREEN}Available${NC}"
    else
        echo -e "${RED}Not available${NC}"
    fi

    # Show service status
    echo
    print_section "Service Status"

    local services=("fail2ban" "rsyslog" "vless-vpn")
    for service in "${services[@]}"; do
        printf "%-20s " "$service:"
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo -e "${GREEN}Active${NC}"
        else
            echo -e "${RED}Inactive${NC}"
        fi
    done
}

# Remove Phase 4 components
remove_phase4() {
    print_header "Removing VLESS Phase 4 Components"

    if [[ ! -f "$INTEGRATION_STATE_FILE" ]]; then
        print_warning "Phase 4 is not installed"
        return 0
    fi

    if ! prompt_yes_no "Are you sure you want to remove all Phase 4 components?" "n"; then
        print_info "Removal cancelled"
        return 0
    fi

    log_integration "WARNING" "Phase 4 removal started"

    # Remove components
    remove_maintenance_tools
    remove_systemd_service
    remove_monitoring_system
    remove_security_hardening
    remove_logging_system

    # Remove integration state
    rm -f "$INTEGRATION_STATE_FILE"

    print_success "Phase 4 components removed"
    log_integration "WARNING" "Phase 4 removal completed"
}

# Remove maintenance tools
remove_maintenance_tools() {
    print_section "Removing Maintenance Tools"

    sudo rm -f "/usr/local/bin/vless-maintenance"
    sudo rm -f "/etc/cron.d/vless-daily-maintenance"

    print_success "Maintenance tools removed"
}

# Remove systemd service
remove_systemd_service() {
    print_section "Removing SystemD Service"

    if systemctl is-active --quiet vless-vpn; then
        sudo systemctl stop vless-vpn
    fi

    if systemctl is-enabled --quiet vless-vpn; then
        sudo systemctl disable vless-vpn
    fi

    sudo rm -f "$SYSTEMD_SERVICE_PATH"
    sudo systemctl daemon-reload

    print_success "SystemD service removed"
}

# Remove monitoring system
remove_monitoring_system() {
    print_section "Removing Monitoring System"

    source "$SCRIPT_DIR/monitoring.sh"
    remove_monitoring

    print_success "Monitoring system removed"
}

# Remove security hardening
remove_security_hardening() {
    print_section "Removing Security Hardening"

    source "$SCRIPT_DIR/security_hardening.sh"
    remove_security_hardening

    print_success "Security hardening removed"
}

# Remove logging system
remove_logging_system() {
    print_section "Removing Logging System"

    source "$SCRIPT_DIR/logging_setup.sh"
    remove_logging

    print_success "Logging system removed"
}

# Export functions
export -f install_phase4 show_phase4_status remove_phase4 update_configurations
export -f check_prerequisites install_logging_system install_security_hardening
export -f install_monitoring_system install_systemd_service configure_maintenance_tools

# Main execution if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Ensure log directory exists
    ensure_directory "$(dirname "$INTEGRATION_LOG")" "755"

    case "${1:-install}" in
        "install"|"setup")
            install_phase4
            ;;
        "status"|"show")
            show_phase4_status
            ;;
        "update"|"configure")
            update_configurations
            ;;
        "remove"|"uninstall")
            remove_phase4
            ;;
        *)
            echo "Usage: $0 {install|status|update|remove}"
            echo "  install - Install all Phase 4 components"
            echo "  status  - Show Phase 4 installation status"
            echo "  update  - Update existing configurations"
            echo "  remove  - Remove all Phase 4 components"
            exit 1
            ;;
    esac
fi