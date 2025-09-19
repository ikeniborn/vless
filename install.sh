#!/bin/bash
# VLESS+Reality VPN Installation Script
# Main installation script with interactive menu
# Author: Claude Code
# Version: 1.0

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Import common utilities
source "${SCRIPT_DIR}/modules/common_utils.sh" || {
    echo "ERROR: Cannot load common utilities module" >&2
    exit 1
}

# Script constants
readonly SCRIPT_NAME="VLESS VPN Installer"
readonly REQUIRED_OS_VERSIONS=("ubuntu:20.04" "ubuntu:22.04" "ubuntu:24.04" "debian:11" "debian:12")
readonly MIN_RAM_GB=1
readonly MIN_DISK_GB=5
readonly LOG_FILE="/var/log/vless-install.log"

# Installation state
OPERATION=""
DOMAIN=""
SSH_PORT=""
TELEGRAM_BOT_TOKEN=""
ADMIN_TELEGRAM_ID=""

# Trap function for cleanup on script interruption
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        print_error "Installation interrupted. Exit code: $exit_code"
        if [[ -n "${OPERATION:-}" ]]; then
            print_warning "You can resume installation by running this script again"
        fi
    fi
    exit $exit_code
}

trap cleanup EXIT INT TERM

# Logging function
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(get_timestamp)

    # Create log directory if it doesn't exist
    sudo mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

    # Log to file
    echo "[$timestamp] [$level] $message" | sudo tee -a "$LOG_FILE" >/dev/null 2>&1 || true

    # Also output to console based on level
    case "$level" in
        "INFO") print_info "$message" ;;
        "SUCCESS") print_success "$message" ;;
        "WARNING") print_warning "$message" ;;
        "ERROR") print_error "$message" ;;
    esac
}

# Check if running as root
check_root_privileges() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        print_info "Usage: sudo $0"
        exit 1
    fi
}

# Check OS compatibility
check_os_compatibility() {
    log_message "INFO" "Checking OS compatibility..."

    if [[ ! -f /etc/os-release ]]; then
        log_message "ERROR" "Cannot determine OS version"
        return 1
    fi

    source /etc/os-release
    local os_id="${ID,,}"
    local os_version="${VERSION_ID}"
    local os_check="${os_id}:${os_version}"

    local compatible=false
    for version in "${REQUIRED_OS_VERSIONS[@]}"; do
        if [[ "$os_check" == "$version" ]]; then
            compatible=true
            break
        fi
    done

    if [[ "$compatible" == "true" ]]; then
        log_message "SUCCESS" "OS compatibility verified: $PRETTY_NAME"
        return 0
    else
        log_message "ERROR" "Unsupported OS: $PRETTY_NAME"
        print_info "Supported versions: ${REQUIRED_OS_VERSIONS[*]}"
        return 1
    fi
}

# Check system requirements
check_system_requirements() {
    log_message "INFO" "Checking system requirements..."

    # Check memory
    local total_ram_mb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_ram_gb=$((total_ram_mb / 1024 / 1024))

    if [[ $total_ram_gb -lt $MIN_RAM_GB ]]; then
        log_message "ERROR" "Insufficient RAM: ${total_ram_gb}GB (minimum: ${MIN_RAM_GB}GB)"
        return 1
    fi

    # Check disk space
    local available_space_gb=$(df / | awk 'NR==2 {print int($4/1024/1024)}')

    if [[ $available_space_gb -lt $MIN_DISK_GB ]]; then
        log_message "ERROR" "Insufficient disk space: ${available_space_gb}GB (minimum: ${MIN_DISK_GB}GB)"
        return 1
    fi

    # Check internet connectivity
    if ! check_internet_connectivity; then
        log_message "ERROR" "No internet connection available"
        return 1
    fi

    log_message "SUCCESS" "System requirements verified"
    log_message "INFO" "RAM: ${total_ram_gb}GB, Disk: ${available_space_gb}GB available"

    return 0
}

# Validate domain name
validate_domain_input() {
    local domain="$1"

    if ! validate_domain "$domain"; then
        return 1
    fi

    # Check if domain resolves
    if ! nslookup "$domain" >/dev/null 2>&1; then
        print_warning "Domain $domain does not resolve to an IP address"
        if ! prompt_yes_no "Continue anyway?"; then
            return 1
        fi
    fi

    return 0
}

# Validate Telegram token format
validate_telegram_token() {
    local token="$1"

    # Basic format validation for Telegram bot token: XXXXXXXXX:XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
    if [[ "$token" =~ ^[0-9]{8,10}:[a-zA-Z0-9_-]{35}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Validate Telegram ID (numeric)
validate_telegram_id() {
    local id="$1"

    if [[ "$id" =~ ^[0-9]+$ ]] && [[ ${#id} -ge 5 ]] && [[ ${#id} -le 12 ]]; then
        return 0
    else
        return 1
    fi
}

# Collect installation parameters
collect_installation_params() {
    print_header "Installation Configuration"

    # Domain configuration
    print_section "Domain Configuration"
    DOMAIN=$(prompt_input "Enter your domain name (e.g., example.com)" "" validate_domain_input)
    log_message "INFO" "Domain configured: $DOMAIN"

    # SSH port configuration
    print_section "SSH Configuration"
    print_info "Current SSH port: $(ss -tlpn | awk '/sshd/ && /0.0.0.0/ {gsub(/.*:/, "", $4); print $4}' | head -1 || echo "22")"
    SSH_PORT=$(prompt_input "SSH port" "22" validate_port)
    log_message "INFO" "SSH port configured: $SSH_PORT"

    # Telegram bot configuration
    print_section "Telegram Bot Configuration"
    print_info "You need to create a Telegram bot with @BotFather first"
    TELEGRAM_BOT_TOKEN=$(prompt_input "Telegram Bot Token" "" validate_telegram_token)

    print_info "You can get your Telegram ID from @userinfobot"
    ADMIN_TELEGRAM_ID=$(prompt_input "Admin Telegram ID" "" validate_telegram_id)

    log_message "INFO" "Telegram bot configured"

    # Configuration summary
    print_section "Configuration Summary"
    printf "%-20s %s\n" "Domain:" "$DOMAIN"
    printf "%-20s %s\n" "SSH Port:" "$SSH_PORT"
    printf "%-20s %s\n" "Bot Token:" "${TELEGRAM_BOT_TOKEN:0:10}...${TELEGRAM_BOT_TOKEN: -5}"
    printf "%-20s %s\n" "Admin ID:" "$ADMIN_TELEGRAM_ID"

    echo
    if ! prompt_yes_no "Proceed with this configuration?" "y"; then
        log_message "INFO" "Installation cancelled by user"
        exit 0
    fi
}

# Execute installation modules
execute_installation() {
    log_message "INFO" "Starting VLESS VPN installation..."

    # Step 1: System update
    print_step "1/6" "Updating system packages"
    if source "${MODULES_DIR}/system_update.sh"; then
        log_message "SUCCESS" "System update completed"
    else
        log_message "ERROR" "System update failed"
        return 1
    fi

    # Step 2: Docker installation
    print_step "2/6" "Installing Docker and Docker Compose"
    if source "${MODULES_DIR}/docker_setup.sh"; then
        log_message "SUCCESS" "Docker installation completed"
    else
        log_message "ERROR" "Docker installation failed"
        return 1
    fi

    # Step 3: UFW configuration
    print_step "3/6" "Configuring firewall"
    if UFW_SSH_PORT="$SSH_PORT" source "${MODULES_DIR}/ufw_config.sh"; then
        log_message "SUCCESS" "Firewall configuration completed"
    else
        log_message "ERROR" "Firewall configuration failed"
        return 1
    fi

    # Step 4: Certificate management
    print_step "4/6" "Setting up certificate management"
    if REALITY_DOMAIN="$DOMAIN" source "${MODULES_DIR}/cert_management.sh"; then
        log_message "SUCCESS" "Certificate management setup completed"
    else
        log_message "ERROR" "Certificate management setup failed"
        return 1
    fi

    # Step 5: User management setup
    print_step "5/6" "Setting up user management"
    if source "${MODULES_DIR}/user_management.sh"; then
        log_message "SUCCESS" "User management setup completed"
    else
        log_message "ERROR" "User management setup failed"
        return 1
    fi

    # Step 6: Docker services deployment
    print_step "6/6" "Deploying Docker services"
    cd "$PROJECT_DIR"

    # Create environment file
    cat > .env << EOF
DOMAIN=$DOMAIN
TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN
ADMIN_TELEGRAM_ID=$ADMIN_TELEGRAM_ID
VLESS_DIR=$VLESS_DIR
EOF

    if docker-compose -f "${CONFIG_DIR}/docker-compose.yml" up -d; then
        log_message "SUCCESS" "Docker services deployed successfully"
    else
        log_message "ERROR" "Docker services deployment failed"
        return 1
    fi

    # Wait for services to start
    print_info "Waiting for services to initialize..."
    sleep 10

    # Verify services are running
    if docker-compose -f "${CONFIG_DIR}/docker-compose.yml" ps | grep -q "Up"; then
        log_message "SUCCESS" "All services are running"
    else
        log_message "WARNING" "Some services may not be running properly"
        docker-compose -f "${CONFIG_DIR}/docker-compose.yml" ps
    fi

    log_message "SUCCESS" "VLESS VPN installation completed successfully"
}

# Uninstall function
execute_uninstall() {
    print_header "VLESS VPN Uninstallation"

    if ! prompt_yes_no "Are you sure you want to uninstall VLESS VPN? This will remove all data." "n"; then
        log_message "INFO" "Uninstallation cancelled by user"
        exit 0
    fi

    log_message "INFO" "Starting VLESS VPN uninstallation..."

    # Stop Docker services
    print_step "1/4" "Stopping Docker services"
    cd "$PROJECT_DIR" 2>/dev/null || true
    docker-compose -f "${CONFIG_DIR}/docker-compose.yml" down 2>/dev/null || true
    log_message "INFO" "Docker services stopped"

    # Remove Docker images
    print_step "2/4" "Removing Docker images"
    docker rmi $(docker images -q "teddysun/xray" "python" 2>/dev/null) 2>/dev/null || true
    log_message "INFO" "Docker images removed"

    # Remove VLESS directories
    print_step "3/4" "Removing VLESS data"
    sudo rm -rf "$VLESS_DIR" 2>/dev/null || true
    rm -f .env 2>/dev/null || true
    log_message "INFO" "VLESS data removed"

    # Remove systemd service (if exists)
    print_step "4/4" "Cleaning up system services"
    sudo systemctl stop vless-vpn 2>/dev/null || true
    sudo systemctl disable vless-vpn 2>/dev/null || true
    sudo rm -f /etc/systemd/system/vless-vpn.service 2>/dev/null || true
    sudo systemctl daemon-reload 2>/dev/null || true
    log_message "INFO" "System services cleaned"

    log_message "SUCCESS" "VLESS VPN uninstallation completed"
    print_success "VLESS VPN has been completely removed from your system"
}

# Reinstall function
execute_reinstall() {
    print_header "VLESS VPN Reinstallation"

    print_warning "This will remove existing installation and install fresh copy"
    if ! prompt_yes_no "Continue with reinstallation?" "n"; then
        log_message "INFO" "Reinstallation cancelled by user"
        exit 0
    fi

    # Execute uninstall first
    execute_uninstall

    echo
    print_info "Starting fresh installation..."
    sleep 2

    # Execute installation
    collect_installation_params
    execute_installation
}

# Display post-installation information
show_post_install_info() {
    print_header "Installation Complete"

    print_success "VLESS VPN has been successfully installed!"
    echo

    print_section "Service Information"
    printf "%-20s %s\n" "Domain:" "$DOMAIN"
    printf "%-20s %s\n" "Status:" "$(docker-compose -f "${CONFIG_DIR}/docker-compose.yml" ps --services --filter status=running | wc -l) services running"
    printf "%-20s %s\n" "Configuration:" "$VLESS_DIR/configs/"
    printf "%-20s %s\n" "Logs:" "$VLESS_DIR/logs/"

    echo
    print_section "Next Steps"
    print_info "1. Add your first user via Telegram bot: /adduser <username>"
    print_info "2. Get user configuration: /getconfig <user-uuid>"
    print_info "3. Monitor system status: /status"
    print_info "4. View this information anytime: /help"

    echo
    print_section "Management Commands"
    print_info "Start services: docker-compose -f ${CONFIG_DIR}/docker-compose.yml up -d"
    print_info "Stop services: docker-compose -f ${CONFIG_DIR}/docker-compose.yml down"
    print_info "View logs: docker-compose -f ${CONFIG_DIR}/docker-compose.yml logs -f"
    print_info "Restart installation: sudo $0"

    echo
    print_warning "Save this information! Your Telegram bot is ready to use."
}

# Phase 4 menu and operations
execute_phase4_menu() {
    print_header "Phase 4: Security & Monitoring"

    print_info "Phase 4 includes advanced security, monitoring, and maintenance features:"
    echo "• Enhanced security hardening (fail2ban, kernel security, file integrity)"
    echo "• Centralized logging with rsyslog and logrotate"
    echo "• System monitoring with alerting and auto-recovery"
    echo "• SystemD service integration"
    echo "• Maintenance utilities and diagnostics"
    echo

    local options=(
        "Install Phase 4 (full setup)"
        "Show Phase 4 status"
        "Update configurations"
        "Remove Phase 4 components"
        "Back to main menu"
    )

    local choice=$(prompt_choice "Select Phase 4 operation:" "${options[@]}")

    case $choice in
        0) execute_phase4_install ;;
        1) execute_phase4_status ;;
        2) execute_phase4_update ;;
        3) execute_phase4_remove ;;
        4) main ;;
    esac
}

# Execute Phase 4 installation
execute_phase4_install() {
    print_header "Installing Phase 4 Components"

    # Check if base installation exists
    if [[ ! -f "/opt/vless/docker-compose.yml" ]]; then
        print_error "Base VLESS installation not found. Please run fresh installation first."
        return 1
    fi

    log_message "INFO" "Starting Phase 4 installation"

    # Load and execute Phase 4 integration
    if source "${MODULES_DIR}/phase4_integration.sh"; then
        if install_phase4; then
            log_message "SUCCESS" "Phase 4 installation completed"
            print_success "Phase 4 installation completed successfully!"

            # Show status
            echo
            show_phase4_status

            print_info "New commands available:"
            echo "• vless-maintenance - Maintenance utilities"
            echo "• vless-monitoring - Monitoring tools"
            echo "• vless-logger - Logging utilities"
            echo "• systemctl status vless-vpn - Service status"

        else
            log_message "ERROR" "Phase 4 installation failed"
            print_error "Phase 4 installation failed. Check logs for details."
            return 1
        fi
    else
        log_message "ERROR" "Failed to load Phase 4 integration module"
        print_error "Failed to load Phase 4 integration module"
        return 1
    fi
}

# Show Phase 4 status
execute_phase4_status() {
    print_header "Phase 4 Status"

    if source "${MODULES_DIR}/phase4_integration.sh"; then
        show_phase4_status
    else
        print_error "Failed to load Phase 4 integration module"
        return 1
    fi

    # Ask if user wants to return to menu or exit
    echo
    if prompt_yes_no "Return to Phase 4 menu?" "y"; then
        execute_phase4_menu
    fi
}

# Update Phase 4 configurations
execute_phase4_update() {
    print_header "Updating Phase 4 Configurations"

    if source "${MODULES_DIR}/phase4_integration.sh"; then
        if update_configurations; then
            print_success "Phase 4 configurations updated successfully"
        else
            print_error "Failed to update Phase 4 configurations"
            return 1
        fi
    else
        print_error "Failed to load Phase 4 integration module"
        return 1
    fi

    # Ask if user wants to return to menu or exit
    echo
    if prompt_yes_no "Return to Phase 4 menu?" "y"; then
        execute_phase4_menu
    fi
}

# Remove Phase 4 components
execute_phase4_remove() {
    print_header "Removing Phase 4 Components"

    print_warning "This will remove all Phase 4 security and monitoring features!"
    print_warning "This includes:"
    echo "• Security hardening configurations"
    echo "• Monitoring and alerting system"
    echo "• Centralized logging setup"
    echo "• SystemD service integration"
    echo "• Maintenance utilities"
    echo

    if ! prompt_yes_no "Are you absolutely sure you want to proceed?" "n"; then
        print_info "Phase 4 removal cancelled"
        execute_phase4_menu
        return 0
    fi

    log_message "WARNING" "Phase 4 removal requested"

    if source "${MODULES_DIR}/phase4_integration.sh"; then
        if remove_phase4; then
            log_message "WARNING" "Phase 4 removal completed"
            print_success "Phase 4 components removed successfully"
        else
            log_message "ERROR" "Phase 4 removal failed"
            print_error "Failed to remove Phase 4 components"
            return 1
        fi
    else
        print_error "Failed to load Phase 4 integration module"
        return 1
    fi

    # Ask if user wants to return to menu or exit
    echo
    if prompt_yes_no "Return to main menu?" "y"; then
        main
    fi
}

# Main menu
show_main_menu() {
    print_header "$SCRIPT_NAME"

    echo "Please select an operation:"
    echo
    echo "1) Fresh Installation"
    echo "2) Reinstall (remove existing + fresh install)"
    echo "3) Uninstall (remove completely)"
    echo "4) Phase 4 Security & Monitoring (advanced features)"
    echo "5) Exit"
    echo

    local choice=$(prompt_choice "Select option:" "Fresh Installation" "Reinstall" "Uninstall" "Phase 4 Security & Monitoring" "Exit")

    case $choice in
        0) OPERATION="install" ;;
        1) OPERATION="reinstall" ;;
        2) OPERATION="uninstall" ;;
        3) OPERATION="phase4" ;;
        4) exit 0 ;;
    esac
}

# Main function
main() {
    # Show system information
    show_system_info

    # Check prerequisites
    check_root_privileges
    check_os_compatibility
    check_system_requirements

    # Show main menu
    show_main_menu

    log_message "INFO" "Starting operation: $OPERATION"

    # Execute selected operation
    case "$OPERATION" in
        "install")
            collect_installation_params
            execute_installation
            show_post_install_info
            ;;
        "reinstall")
            execute_reinstall
            show_post_install_info
            ;;
        "uninstall")
            execute_uninstall
            ;;
        "phase4")
            execute_phase4_menu
            ;;
        *)
            log_message "ERROR" "Unknown operation: $OPERATION"
            exit 1
            ;;
    esac

    log_message "SUCCESS" "Operation '$OPERATION' completed successfully"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi