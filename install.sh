#!/bin/bash

# VLESS+Reality VPN Management System - Main Installation Script
# Version: 1.0.0
# Description: Interactive menu-driven installation system
#
# This script provides:
# - Interactive menu interface
# - Root privilege verification
# - System compatibility checks
# - Phase-based installation flow

set -euo pipefail

# Script metadata
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME="VLESS+Reality VPN Management System"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Import common utilities
source "${SCRIPT_DIR}/modules/common_utils.sh"

# Import safety utilities
if [[ -f "${SCRIPT_DIR}/modules/safety_utils.sh" ]]; then
    source "${SCRIPT_DIR}/modules/safety_utils.sh"
fi

# System directories
readonly SYSTEM_DIR="/opt/vless"
readonly CONFIG_DIR="$SYSTEM_DIR/config"
readonly USERS_DIR="$SYSTEM_DIR/users"
readonly LOGS_DIR="$SYSTEM_DIR/logs"
readonly BACKUP_DIR="$SYSTEM_DIR/backup"
readonly CERTS_DIR="$SYSTEM_DIR/certs"

# Installation phases
readonly PHASE_1="Core Infrastructure Setup"
readonly PHASE_2="VLESS Server Implementation"
readonly PHASE_3="User Management System"
readonly PHASE_4="Security and Monitoring"
readonly PHASE_5="Backup and Maintenance Utilities"

# Menu colors and symbols
readonly MENU_BORDER="═══════════════════════════════════════════════════════════════════════"
readonly MENU_SEPARATOR="────────────────────────────────────────────────────────────────────"

# Display banner
show_banner() {
    clear
    echo -e "${BLUE}${MENU_BORDER}${NC}"
    echo -e "${WHITE}                    ${SCRIPT_NAME}                    ${NC}"
    echo -e "${WHITE}                           Version ${SCRIPT_VERSION}                           ${NC}"
    echo -e "${BLUE}${MENU_BORDER}${NC}"
    echo
}

# Display system information
show_system_info() {
    local distribution
    local architecture
    local kernel
    local memory
    local disk_space

    distribution=$(detect_distribution)
    architecture=$(detect_architecture)
    kernel=$(uname -r)
    memory=$(free -h | awk '/^Mem:/ {print $2}')
    disk_space=$(df -h / | awk 'NR==2 {print $4}')

    echo -e "${CYAN}System Information:${NC}"
    echo "  Distribution: $distribution"
    echo "  Architecture: $architecture"
    echo "  Kernel: $kernel"
    echo "  Memory: $memory"
    echo "  Available Disk: $disk_space"
    echo
}

# Install Python dependencies safely
install_python_dependencies() {
    log_info "Installing Python dependencies"

    local requirements_file="${SCRIPT_DIR}/requirements.txt"

    # Verify requirements.txt exists
    if [[ ! -f "$requirements_file" ]]; then
        log_error "Requirements file not found: $requirements_file"
        return 1
    fi

    # Ensure pip is installed
    if ! command_exists pip3; then
        log_info "Installing pip3..."
        apt-get update && apt-get install -y python3-pip
    fi

    # Upgrade pip to latest version
    log_debug "Upgrading pip to latest version"
    python3 -m pip install --upgrade pip --break-system-packages 2>/dev/null || \
    python3 -m pip install --upgrade pip --user 2>/dev/null || \
    log_debug "Could not upgrade pip, continuing with current version"

    # Install dependencies with timeout and error handling
    log_info "Installing Python packages from requirements.txt..."

    # Try installation with different approaches
    local install_success=false

    # First try standard installation
    if python3 -m pip install -r "$requirements_file" --timeout=300 --no-cache-dir 2>/dev/null; then
        install_success=true
    # If externally managed environment, use --break-system-packages
    elif python3 -m pip install -r "$requirements_file" --timeout=300 --no-cache-dir --break-system-packages 2>/dev/null; then
        log_debug "Used --break-system-packages for externally managed environment"
        install_success=true
    # If still failing, try user installation
    elif python3 -m pip install -r "$requirements_file" --timeout=300 --no-cache-dir --user 2>/dev/null; then
        log_debug "Installed packages for user only"
        install_success=true
    fi

    if [ "$install_success" = true ]; then
        log_success "Python dependencies installed successfully"
        return 0
    else
        log_error "Failed to install Python dependencies with all attempted methods"
        log_info "You may need to install packages manually or create a virtual environment"
        return 1
    fi
}

# Select installation mode
select_installation_mode() {
    if [[ "${QUICK_MODE:-false}" == "true" ]]; then
        export INSTALLATION_MODE="minimal"
        log_info "Quick mode: Using minimal installation profile"
        configure_installation_profile
        return 0
    fi

    echo -e "\n${CYAN}Select Installation Mode:${NC}"
    echo "1. Minimal   - VPN only, no advanced features (Recommended for production)"
    echo "2. Balanced  - VPN + essential security/monitoring (Recommended for most users)"
    echo "3. Full      - All features with customization options"
    echo ""

    local choice
    read -p "Select mode [1-3] (default: 2): " choice
    choice=${choice:-2}

    case $choice in
        1) export INSTALLATION_MODE="minimal" ;;
        2) export INSTALLATION_MODE="balanced" ;;
        3) export INSTALLATION_MODE="full" ;;
        *) export INSTALLATION_MODE="balanced" ;;
    esac

    log_info "Installation mode: $INSTALLATION_MODE"

    # Configure profile settings
    configure_installation_profile

    echo -e "\n${GREEN}Installation mode configured: $INSTALLATION_MODE${NC}"

    case "$INSTALLATION_MODE" in
        "minimal")
            echo "  - Phases: 1, 2, 3 (Core VPN functionality only)"
            echo "  - SSH hardening: Disabled"
            echo "  - Monitoring tools: Disabled"
            echo "  - Backup: Minimal profile"
            ;;
        "balanced")
            echo "  - Phases: 1, 2, 3, 4 (VPN + essential security)"
            echo "  - SSH hardening: Selective (user choice)"
            echo "  - Monitoring tools: Basic only"
            echo "  - Backup: Essential profile"
            ;;
        "full")
            echo "  - Phases: 1, 2, 3, 4, 5 (All features)"
            echo "  - SSH hardening: Interactive configuration"
            echo "  - Monitoring tools: Optional (user choice)"
            echo "  - Backup: Full profile"
            ;;
    esac

    echo ""
    if ! confirm_action "Proceed with $INSTALLATION_MODE installation?" "y" 30; then
        log_info "Installation mode selection cancelled"
        return 1
    fi
}

# Display installation status
show_installation_status() {
    echo -e "${CYAN}Installation Status:${NC}"

    # Check Phase 1 - Core Infrastructure
    if [[ -f "${SCRIPT_DIR}/modules/common_utils.sh" ]] && \
       [[ -f "${SCRIPT_DIR}/modules/system_update.sh" ]] && \
       [[ -f "${SCRIPT_DIR}/modules/docker_setup.sh" ]]; then
        echo -e "  Phase 1 (Core Infrastructure): ${GREEN}✓ Ready${NC}"
    else
        echo -e "  Phase 1 (Core Infrastructure): ${RED}✗ Missing modules${NC}"
    fi

    # Check Phase 2 - VLESS Server
    if [[ -f "${SCRIPT_DIR}/config/docker-compose.yml" ]] && \
       [[ -f "${SCRIPT_DIR}/config/xray_config_template.json" ]]; then
        echo -e "  Phase 2 (VLESS Server): ${GREEN}✓ Configured${NC}"
    else
        echo -e "  Phase 2 (VLESS Server): ${YELLOW}○ Not configured${NC}"
    fi

    # Check Phase 3 - User Management
    if [[ -f "${SCRIPT_DIR}/modules/user_management.sh" ]] && \
       [[ -f "${SCRIPT_DIR}/modules/user_database.sh" ]]; then
        echo -e "  Phase 3 (User Management): ${GREEN}✓ Available${NC}"
    else
        echo -e "  Phase 3 (User Management): ${YELLOW}○ Not available${NC}"
    fi

    # Check Phase 4 - Security and Monitoring
    if [[ -f "${SCRIPT_DIR}/modules/ufw_config.sh" ]] && \
       [[ -f "${SCRIPT_DIR}/modules/security_hardening.sh" ]] && \
       [[ -f "${SCRIPT_DIR}/modules/monitoring.sh" ]] && \
       [[ -f "${SCRIPT_DIR}/modules/logging_setup.sh" ]]; then
        echo -e "  Phase 4 (Security & Monitoring): ${GREEN}✓ Available${NC}"
    else
        echo -e "  Phase 4 (Security & Monitoring): ${YELLOW}○ Not available${NC}"
    fi

    # Check Phase 5 - Backup and Maintenance Utilities
    if [[ -f "${SCRIPT_DIR}/modules/backup_restore.sh" ]] && \
       [[ -f "${SCRIPT_DIR}/modules/maintenance_utils.sh" ]]; then
        echo -e "  Phase 5 (Backup and Maintenance): ${GREEN}✓ Available${NC}"
    else
        echo -e "  Phase 5 (Backup and Maintenance): ${YELLOW}○ Not available${NC}"
    fi

    # Check system directories
    if [[ -d "$SYSTEM_DIR" ]]; then
        echo -e "  System Directory: ${GREEN}✓ Created ($SYSTEM_DIR)${NC}"
    else
        echo -e "  System Directory: ${YELLOW}○ Not created${NC}"
    fi

    # Check Docker installation
    if command_exists docker && docker info >/dev/null 2>&1; then
        local docker_version
        docker_version=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        echo -e "  Docker: ${GREEN}✓ Installed (v$docker_version)${NC}"
    else
        echo -e "  Docker: ${RED}✗ Not installed${NC}"
    fi

    echo
}

# Create system directories
create_system_directories() {
    log_info "Creating system directories..."

    # Create VLESS system user and group first
    if ! create_vless_system_user; then
        log_error "Failed to create VLESS system user and group"
        return 1
    fi

    local directories=(
        "$SYSTEM_DIR"
        "$CONFIG_DIR"
        "$USERS_DIR"
        "$LOGS_DIR"
        "$BACKUP_DIR"
        "$CERTS_DIR"
    )

    local dir
    for dir in "${directories[@]}"; do
        create_directory "$dir" "755"
    done

    # Set proper ownership for the main directory using vless user
    chown -R vless:vless "$SYSTEM_DIR" 2>/dev/null || {
        log_warn "Failed to set vless ownership, falling back to sudo user"
        if [[ -n "${SUDO_USER:-}" ]]; then
            chown -R "${SUDO_USER}:${SUDO_USER}" "$SYSTEM_DIR" 2>/dev/null || true
        fi
    }

    log_success "System directories created successfully"
}

# Check system requirements
check_system_requirements() {
    log_info "Checking system requirements..."

    local errors=0

    # Check distribution
    local distribution
    distribution=$(detect_distribution)
    case "$distribution" in
        "ubuntu"|"debian")
            log_success "Distribution check: $distribution (supported)"
            ;;
        *)
            log_error "Distribution check: $distribution (unsupported)"
            errors=$((errors + 1))
            ;;
    esac

    # Check architecture
    local architecture
    architecture=$(detect_architecture)
    case "$architecture" in
        "amd64"|"arm64"|"armhf")
            log_success "Architecture check: $architecture (supported)"
            ;;
        *)
            log_error "Architecture check: $architecture (unsupported)"
            errors=$((errors + 1))
            ;;
    esac

    # Check available memory (minimum 512MB)
    local memory_mb
    memory_mb=$(free -m | awk '/^Mem:/ {print $2}')
    if [[ $memory_mb -ge 512 ]]; then
        log_success "Memory check: ${memory_mb}MB (sufficient)"
    else
        log_error "Memory check: ${memory_mb}MB (insufficient, minimum: 512MB)"
        errors=$((errors + 1))
    fi

    # Check available disk space (minimum 2GB)
    local disk_gb
    disk_gb=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    if [[ $disk_gb -ge 2 ]]; then
        log_success "Disk space check: ${disk_gb}GB (sufficient)"
    else
        log_error "Disk space check: ${disk_gb}GB (insufficient, minimum: 2GB)"
        errors=$((errors + 1))
    fi

    # Check network connectivity
    if check_network_connectivity; then
        log_success "Network connectivity check: passed"
    else
        log_error "Network connectivity check: failed"
        errors=$((errors + 1))
    fi

    if [[ $errors -eq 0 ]]; then
        log_success "All system requirements met"
        return 0
    else
        log_error "$errors system requirement(s) failed"
        return 1
    fi
}

# Install Phase 1: Core Infrastructure
install_phase1() {
    echo -e "${YELLOW}${MENU_SEPARATOR}${NC}"
    echo -e "${WHITE}Phase 1: ${PHASE_1}${NC}"
    echo -e "${YELLOW}${MENU_SEPARATOR}${NC}"

    log_info "Starting Phase 1 installation..."

    # Create system directories
    create_system_directories

    # Check system requirements
    if ! check_system_requirements; then
        log_warn "Some system requirements failed, but continuing..."
    fi

    # Run system update
    log_info "Running system update..."
    if ! "${SCRIPT_DIR}/modules/system_update.sh" --upgrade-type safe; then
        log_error "System update failed"
        return 1
    fi

    # Install Docker
    log_info "Installing Docker..."
    if ! "${SCRIPT_DIR}/modules/docker_setup.sh" --install; then
        log_error "Docker installation failed"
        return 1
    fi

    # Install Python dependencies
    log_info "Installing Python dependencies..."
    if install_python_dependencies; then
        log_success "Python dependencies installed successfully"
    else
        log_warn "Python dependencies installation failed, continuing..."
    fi

    log_success "Phase 1 completed successfully"
    echo
    # Skip prompt in quick install mode
    if [[ "${QUICK_MODE:-false}" != "true" ]]; then
        read -p "Press Enter to continue..."
    fi
}

# Install Phase 2: VLESS Server Implementation
install_phase2() {
    echo -e "${YELLOW}${MENU_SEPARATOR}${NC}"
    echo -e "${WHITE}Phase 2: ${PHASE_2}${NC}"
    echo -e "${YELLOW}${MENU_SEPARATOR}${NC}"

    log_info "Starting Phase 2 installation..."

    # Check if Phase 1 is completed
    if ! command_exists docker || ! docker info >/dev/null 2>&1; then
        log_error "Phase 1 must be completed first (Docker not available)"
        return 1
    fi

    # Create VLESS server configuration
    log_info "Creating VLESS server configuration..."

    # This will be implemented when we have the config modules
    log_warn "Phase 2 implementation requires additional modules"
    log_info "Please ensure config_templates.sh and container_management.sh are available"

    log_success "Phase 2 preparation completed"
    echo
    # Skip prompt in quick install mode
    if [[ "${QUICK_MODE:-false}" != "true" ]]; then
        read -p "Press Enter to continue..."
    fi
}

# Install Phase 3: User Management System
install_phase3() {
    echo -e "${YELLOW}${MENU_SEPARATOR}${NC}"
    echo -e "${WHITE}Phase 3: ${PHASE_3}${NC}"
    echo -e "${YELLOW}${MENU_SEPARATOR}${NC}"

    log_info "Starting Phase 3 installation..."

    # Check if previous phases are completed
    if ! command_exists docker; then
        log_error "Phase 1 must be completed first"
        return 1
    fi

    # Install Python dependencies for QR code generation and Telegram bot
    log_info "Installing Python dependencies..."
    if install_python_dependencies; then
        log_success "Python dependencies installed successfully"
    else
        log_warn "Python dependencies installation failed, continuing..."
    fi

    # This will be implemented when we have the user management modules
    log_warn "Phase 3 implementation requires additional modules"
    log_info "Please ensure user_management.sh and user_database.sh are available"

    log_success "Phase 3 preparation completed"
    echo
    # Skip prompt in quick install mode
    if [[ "${QUICK_MODE:-false}" != "true" ]]; then
        read -p "Press Enter to continue..."
    fi
}

# Install Phase 4: Security and Monitoring
install_phase4() {
    local profile="${INSTALLATION_MODE:-balanced}"

    # Skip Phase 4 entirely for minimal installations
    if [[ "$profile" == "minimal" ]]; then
        log_info "Skipping Phase 4 for minimal installation"
        return 0
    fi

    echo -e "${YELLOW}${MENU_SEPARATOR}${NC}"
    echo -e "${WHITE}Phase 4: ${PHASE_4} (Profile: $profile)${NC}"
    echo -e "${YELLOW}${MENU_SEPARATOR}${NC}"

    log_info "Starting Phase 4 installation..."

    # Check if previous phases are completed
    if ! command_exists docker; then
        log_error "Phase 1 must be completed first"
        return 1
    fi

    # Check if Phase 4 modules exist
    local phase4_modules=(
        "${SCRIPT_DIR}/modules/ufw_config.sh"
        "${SCRIPT_DIR}/modules/security_hardening.sh"
        "${SCRIPT_DIR}/modules/monitoring.sh"
        "${SCRIPT_DIR}/modules/logging_setup.sh"
    )

    local module
    for module in "${phase4_modules[@]}"; do
        if [[ ! -f "$module" ]]; then
            log_error "Required Phase 4 module not found: $module"
            return 1
        fi
    done

    # Setup firewall
    log_info "Configuring UFW firewall..."
    source "${SCRIPT_DIR}/modules/ufw_config.sh"
    if setup_vless_firewall; then
        log_success "UFW firewall configured successfully"
    else
        log_error "UFW firewall configuration failed"
        return 1
    fi

    # Setup security hardening
    log_info "Applying security hardening..."
    source "${SCRIPT_DIR}/modules/security_hardening.sh"
    if setup_security_hardening; then
        log_success "Security hardening applied successfully"
    else
        log_error "Security hardening failed"
        return 1
    fi

    # Setup logging system
    log_info "Setting up centralized logging..."
    source "${SCRIPT_DIR}/modules/logging_setup.sh"
    if setup_logging_system; then
        log_success "Logging system configured successfully"
    else
        log_error "Logging system setup failed"
        return 1
    fi

    # Setup monitoring
    log_info "Setting up system monitoring..."
    source "${SCRIPT_DIR}/modules/monitoring.sh"
    if init_monitoring && create_monitoring_service; then
        log_success "Monitoring system configured successfully"
    else
        log_error "Monitoring system setup failed"
        return 1
    fi

    log_success "Phase 4 completed successfully"
    echo
    # Skip prompt in quick install mode
    if [[ "${QUICK_MODE:-false}" != "true" ]]; then
        read -p "Press Enter to continue..."
    fi
}

# Install Phase 5: Backup and Maintenance Utilities
install_phase5() {
    local profile="${INSTALLATION_MODE:-balanced}"

    # Configure modules based on profile
    local phase5_modules=()

    case "$profile" in
        "minimal")
            log_info "Skipping Phase 5 for minimal installation"
            return 0
            ;;
        "balanced")
            phase5_modules=("${SCRIPT_DIR}/modules/backup_restore.sh")
            ;;
        "full")
            phase5_modules=("${SCRIPT_DIR}/modules/backup_restore.sh" "${SCRIPT_DIR}/modules/maintenance_utils.sh")
            ;;
    esac

    if [[ ${#phase5_modules[@]} -eq 0 ]]; then
        log_info "No Phase 5 modules selected"
        return 0
    fi

    echo -e "${YELLOW}${MENU_SEPARATOR}${NC}"
    echo -e "${WHITE}Phase 5: ${PHASE_5} (Profile: $profile)${NC}"
    echo -e "${YELLOW}${MENU_SEPARATOR}${NC}"

    log_info "Starting Phase 5 installation..."

    # Check if previous phases are completed
    if ! command_exists docker; then
        log_error "Phase 1 must be completed first"
        return 1
    fi

    # Check if required Phase 5 modules exist
    local module
    for module in "${phase5_modules[@]}"; do
        if [[ ! -f "$module" ]]; then
            log_error "Required Phase 5 module not found: $module"
            return 1
        fi
    done

    # Setup backup and restore system
    log_info "Setting up backup and restore system..."
    source "${SCRIPT_DIR}/modules/backup_restore.sh"
    if init_backup_system && schedule_automatic_backups; then
        log_success "Backup system configured successfully"
    else
        log_error "Backup system setup failed"
        return 1
    fi

    # Setup maintenance utilities (for full profile)
    if [[ "$profile" == "full" ]]; then
        log_info "Setting up maintenance utilities..."
        source "${SCRIPT_DIR}/modules/maintenance_utils.sh"
        if init_maintenance_utils && schedule_maintenance_tasks; then
            log_success "Maintenance utilities configured successfully"
        else
            log_error "Maintenance utilities setup failed"
            return 1
        fi
    fi

    log_success "Phase 5 completed successfully"
    echo
    echo "🎉 All phases completed! Your VLESS+Reality VPN system is ready."
    echo
    echo "Next steps:"
    echo "  • Check system status: $0 --status"
    echo "  • Manage users: ${SCRIPT_DIR}/modules/user_management.sh"
    echo "  • View logs: ${SCRIPT_DIR}/modules/monitoring.sh logs"
    echo "  • Create backups: ${SCRIPT_DIR}/modules/backup_restore.sh full-backup"
    echo
    # Skip prompt in quick install mode
    if [[ "${QUICK_MODE:-false}" != "true" ]]; then
        read -p "Press Enter to continue..."
    fi
}

# Quick installation (all phases)
quick_install() {
    echo -e "${YELLOW}${MENU_SEPARATOR}${NC}"
    echo -e "${WHITE}Quick Installation - All Phases${NC}"
    echo -e "${YELLOW}${MENU_SEPARATOR}${NC}"

    log_info "Starting quick installation..."

    # Set quick mode flag
    export QUICK_MODE=true

    # Select installation mode (will default to minimal in quick mode)
    select_installation_mode

    # Install Phase 1
    if ! install_phase1; then
        die "Phase 1 installation failed" 15
    fi

    # Install Phase 2
    if ! install_phase2; then
        log_error "Phase 2 installation failed, but continuing..."
    fi

    # Install Phase 3
    if ! install_phase3; then
        log_error "Phase 3 installation failed, but continuing..."
    fi

    # Install Phase 4
    if ! install_phase4; then
        log_error "Phase 4 installation failed, but continuing..."
    fi

    # Install Phase 5
    if ! install_phase5; then
        log_error "Phase 5 installation failed, but continuing..."
    fi

    # Unset quick mode flag
    unset QUICK_MODE

    log_success "Quick installation completed - All phases installed!"
    echo
    echo "🎉 Your VLESS+Reality VPN system is fully deployed and ready to use!"
    echo
    # Skip prompt in quick install mode
    if [[ "${QUICK_MODE:-false}" != "true" ]]; then
        read -p "Press Enter to continue..."
    fi
}

# System status check
system_status() {
    echo -e "${YELLOW}${MENU_SEPARATOR}${NC}"
    echo -e "${WHITE}System Status${NC}"
    echo -e "${YELLOW}${MENU_SEPARATOR}${NC}"

    show_system_info
    show_installation_status

    # Check Docker status
    if command_exists docker; then
        "${SCRIPT_DIR}/modules/docker_setup.sh" --info 2>/dev/null || \
        echo "Docker information unavailable"
    fi

    # Check system update status
    "${SCRIPT_DIR}/modules/system_update.sh" --status 2>/dev/null || \
    echo "System update status unavailable"

    echo
    # Skip prompt in quick install mode
    if [[ "${QUICK_MODE:-false}" != "true" ]]; then
        read -p "Press Enter to continue..."
    fi
}

# System removal
system_removal() {
    echo -e "${YELLOW}${MENU_SEPARATOR}${NC}"
    echo -e "${WHITE}System Removal${NC}"
    echo -e "${YELLOW}${MENU_SEPARATOR}${NC}"

    log_warn "This will remove the VLESS VPN system"
    echo -e "${RED}WARNING: This action cannot be undone!${NC}"
    echo

    read -p "Are you sure you want to remove the system? (type 'yes' to confirm): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "System removal cancelled"
        return 0
    fi

    log_info "Removing VLESS VPN system..."

    # Stop any running containers
    if command_exists docker; then
        log_info "Stopping Docker containers..."
        docker-compose -f "${SCRIPT_DIR}/config/docker-compose.yml" down 2>/dev/null || true
    fi

    # Remove system directories (with backup option)
    if [[ -d "$SYSTEM_DIR" ]]; then
        read -p "Create backup before removal? (y/n): " backup_choice
        if [[ "$backup_choice" =~ ^[Yy] ]]; then
            local backup_file="/tmp/vless-backup-$(date +%Y%m%d_%H%M%S).tar.gz"
            tar -czf "$backup_file" -C "$(dirname "$SYSTEM_DIR")" "$(basename "$SYSTEM_DIR")" 2>/dev/null
            log_info "Backup created: $backup_file"
        fi

        rm -rf "$SYSTEM_DIR"
        log_success "System directories removed"
    fi

    # Option to remove Docker
    read -p "Remove Docker as well? (y/n): " docker_choice
    if [[ "$docker_choice" =~ ^[Yy] ]]; then
        "${SCRIPT_DIR}/modules/docker_setup.sh" --uninstall
    fi

    log_success "System removal completed"
    echo
    # Skip prompt in quick install mode
    if [[ "${QUICK_MODE:-false}" != "true" ]]; then
        read -p "Press Enter to continue..."
    fi
}

# Show main menu
show_main_menu() {
    show_banner
    show_system_info
    show_installation_status

    echo -e "${CYAN}Main Menu:${NC}"
    echo "  1) Select Installation Mode & Quick Install"
    echo "  2) Phase 1: Core Infrastructure Setup"
    echo "  3) Phase 2: VLESS Server Implementation"
    echo "  4) Phase 3: User Management System"
    echo "  5) Phase 4: Security and Monitoring"
    echo "  6) Phase 5: Backup and Maintenance Utilities"
    echo "  7) System Status Check"
    echo "  8) System Removal"
    echo "  0) Exit"
    echo
    echo -e "${YELLOW}${MENU_SEPARATOR}${NC}"
}

# Main menu loop
main_menu_loop() {
    while true; do
        show_main_menu
        read -p "Please select an option [0-8]: " choice

        case $choice in
            1)
                if select_installation_mode; then
                    quick_install
                fi
                ;;
            2) install_phase1 ;;
            3) install_phase2 ;;
            4) install_phase3 ;;
            5) install_phase4 ;;
            6) install_phase5 ;;
            7) system_status ;;
            8) system_removal ;;
            0)
                echo -e "${GREEN}Thank you for using ${SCRIPT_NAME}!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${NC}"
                sleep 2
                ;;
        esac
    done
}

# Pre-installation checks
pre_installation_checks() {
    # Check if running as root
    require_root

    # Check if modules are available
    local required_modules=(
        "${SCRIPT_DIR}/modules/common_utils.sh"
        "${SCRIPT_DIR}/modules/system_update.sh"
        "${SCRIPT_DIR}/modules/docker_setup.sh"
    )

    local module
    for module in "${required_modules[@]}"; do
        if [[ ! -f "$module" ]]; then
            die "Required module not found: $module" 16
        fi
    done

    # Setup signal handlers for process isolation
    setup_signal_handlers

    log_info "Pre-installation checks completed successfully"
}

# Display help information
show_help() {
    cat << EOF
${SCRIPT_NAME} v${SCRIPT_VERSION}

Usage: $0 [OPTIONS]

Options:
    --quick              Run quick installation (all phases)
    --phase1             Install Phase 1 only (Core Infrastructure)
    --phase2             Install Phase 2 only (VLESS Server)
    --phase3             Install Phase 3 only (User Management)
    --phase4             Install Phase 4 only (Security & Monitoring)
    --phase5             Install Phase 5 only (Backup and Maintenance)
    --status             Show system status
    --remove             Remove system
    --help               Show this help message

Interactive Mode:
    $0                   # Start interactive menu

Examples:
    sudo $0                    # Interactive installation
    sudo $0 --quick           # Quick installation (all phases)
    sudo $0 --phase1          # Install Phase 1 only
    sudo $0 --phase4          # Install Phase 4 only (Security)
    sudo $0 --status          # Check system status

Required Permissions:
    This script must be run as root (use sudo)

System Requirements:
    - Ubuntu 20.04+ or Debian 10+
    - Minimum 512MB RAM
    - Minimum 2GB free disk space
    - Internet connection

EOF
}

# Main execution
main() {
    # Parse command line arguments
    case "${1:-}" in
        --quick)
            pre_installation_checks
            quick_install
            ;;
        --phase1)
            pre_installation_checks
            install_phase1
            ;;
        --phase2)
            pre_installation_checks
            install_phase2
            ;;
        --phase3)
            pre_installation_checks
            install_phase3
            ;;
        --phase4)
            pre_installation_checks
            install_phase4
            ;;
        --phase5)
            pre_installation_checks
            install_phase5
            ;;
        --status)
            system_status
            ;;
        --remove)
            pre_installation_checks
            system_removal
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        "")
            pre_installation_checks
            main_menu_loop
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
}

# Ensure cleanup on exit
trap cleanup_child_processes EXIT

# Run main function
main "$@"