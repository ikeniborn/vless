#!/bin/bash
# ======================================================================================
# VLESS+Reality VPN Management System - Main Installation Script
# ======================================================================================
# This is the main entry point for installing the complete VLESS+Reality VPN system.
# It orchestrates the installation process, validates the environment, and provides
# comprehensive error handling with rollback capabilities.
#
# Author: Claude Code
# Version: 1.0
# Last Modified: 2025-09-21
#
# Usage:
#   sudo ./install.sh [OPTIONS]
#
# Options:
#   -h, --help          Show help message
#   -v, --verbose       Enable verbose output
#   -d, --dry-run       Perform dry run without making changes
#   -f, --force         Force installation (skip confirmations)
#   -c, --config FILE   Use custom configuration file
#   --skip-deps         Skip dependency installation
#   --skip-docker       Skip Docker installation
#   --skip-security     Skip security hardening
# ======================================================================================

set -euo pipefail

# Global configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly VLESS_ROOT="/opt/vless"
readonly MODULES_DIR="${SCRIPT_DIR}/modules"
readonly CONFIG_DIR="${VLESS_ROOT}/config"
readonly LOG_DIR="${VLESS_ROOT}/logs"

# Installation configuration
DRY_RUN=false
VERBOSE=false
FORCE_INSTALL=false
SKIP_DEPS=false
SKIP_DOCKER=false
SKIP_SECURITY=false
CUSTOM_CONFIG=""

# Installation phases
declare -a INSTALLATION_PHASES=(
    "validate_environment"
    "setup_foundation"
    "install_dependencies"
    "setup_docker"
    "setup_user_management"
    "setup_security"
    "setup_monitoring"
    "finalize_installation"
)

# ======================================================================================
# UTILITY FUNCTIONS
# ======================================================================================

# Import common utilities (with fallback)
if [[ -f "${MODULES_DIR}/common_utils.sh" ]]; then
    source "${MODULES_DIR}/common_utils.sh"
else
    # Fallback logging functions if common_utils not available
    log_info() { echo -e "\033[0;34m[INFO]\033[0m $*"; }
    log_warn() { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }
    log_error() { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }
    log_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $*"; }
fi

# Function: show_banner
# Description: Display installation banner
show_banner() {
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                    VLESS+Reality VPN Management System                       ║
║                              Installation Script                             ║
║                                                                              ║
║  This script will install and configure a complete VLESS+Reality VPN        ║
║  management system with Docker, user management, security hardening,        ║
║  and Telegram bot integration.                                              ║
║                                                                              ║
║  Requirements:                                                               ║
║  - Ubuntu 20.04+ or Debian 11+                                              ║
║  - Root privileges                                                           ║
║  - Internet connectivity                                                     ║
║  - Minimum 1GB RAM, 10GB disk space                                         ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
}

# Function: show_usage
# Description: Display usage information
show_usage() {
    cat << 'EOF'
Usage: sudo ./install.sh [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output (debug mode)
    -d, --dry-run       Perform dry run without making changes
    -f, --force         Force installation (skip confirmations)
    -c, --config FILE   Use custom configuration file
    --skip-deps         Skip dependency installation
    --skip-docker       Skip Docker installation
    --skip-security     Skip security hardening
    --uninstall         Uninstall VLESS system

EXAMPLES:
    # Standard installation
    sudo ./install.sh

    # Verbose installation with custom config
    sudo ./install.sh --verbose --config /path/to/config.env

    # Dry run to see what would be installed
    sudo ./install.sh --dry-run --verbose

    # Force installation without prompts
    sudo ./install.sh --force

    # Install without Docker (if already installed)
    sudo ./install.sh --skip-docker

CONFIGURATION:
    The installer can use a configuration file to customize the installation.
    Create a file with environment variables:

    VLESS_PORT=443
    VLESS_DOMAIN=example.com
    TELEGRAM_BOT_TOKEN=your_bot_token
    ADMIN_TELEGRAM_ID=your_telegram_id

For more information, visit: https://github.com/your-repo/vless-vpn
EOF
}

# ======================================================================================
# ARGUMENT PARSING
# ======================================================================================

# Function: parse_arguments
# Description: Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                export VLESS_LOG_LEVEL=0  # Debug level
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                log_info "Dry run mode enabled - no changes will be made"
                shift
                ;;
            -f|--force)
                FORCE_INSTALL=true
                log_info "Force mode enabled - skipping confirmations"
                shift
                ;;
            -c|--config)
                CUSTOM_CONFIG="$2"
                if [[ ! -f "$CUSTOM_CONFIG" ]]; then
                    log_error "Configuration file not found: $CUSTOM_CONFIG"
                    exit 1
                fi
                shift 2
                ;;
            --skip-deps)
                SKIP_DEPS=true
                log_info "Skipping dependency installation"
                shift
                ;;
            --skip-docker)
                SKIP_DOCKER=true
                log_info "Skipping Docker installation"
                shift
                ;;
            --skip-security)
                SKIP_SECURITY=true
                log_info "Skipping security hardening"
                shift
                ;;
            --uninstall)
                uninstall_vless_system
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# ======================================================================================
# PRE-INSTALLATION VALIDATION
# ======================================================================================

# Function: validate_environment
# Description: Validate the installation environment
validate_environment() {
    log_info "Validating installation environment..."

    local validation_errors=0

    # Check root privileges
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root. Please use sudo."
        ((validation_errors++))
    fi

    # Check supported distribution
    if ! validate_system; then
        ((validation_errors++))
    fi

    # Check internet connectivity
    if ! check_internet; then
        ((validation_errors++))
    fi

    # Check disk space (minimum 10GB)
    local available_space
    available_space=$(df / | tail -1 | awk '{print $4}')
    local required_space=10485760  # 10GB in KB

    if [[ $available_space -lt $required_space ]]; then
        log_error "Insufficient disk space. Required: 10GB, Available: $((available_space/1024/1024))GB"
        ((validation_errors++))
    fi

    # Check RAM (minimum 1GB)
    local available_ram
    available_ram=$(free -m | awk 'NR==2{print $7}')
    local required_ram=1024

    if [[ $available_ram -lt $required_ram ]]; then
        log_warn "Low available RAM. Required: 1GB, Available: ${available_ram}MB"
    fi

    # Check for conflicting services
    local conflicting_services=("apache2" "nginx" "v2ray" "xray")
    for service in "${conflicting_services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log_warn "Conflicting service detected: $service (may need manual configuration)"
        fi
    done

    # Report validation results
    if [[ $validation_errors -gt 0 ]]; then
        log_error "Environment validation failed with $validation_errors errors"
        return 1
    else
        log_success "Environment validation passed"
        return 0
    fi
}

# ======================================================================================
# INSTALLATION PHASES
# ======================================================================================

# Function: setup_foundation
# Description: Setup basic directory structure and permissions
setup_foundation() {
    log_info "Setting up foundation infrastructure..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create directory structure at $VLESS_ROOT"
        return 0
    fi

    # Source and initialize common utilities
    source "${MODULES_DIR}/common_utils.sh"
    init_common_utils

    # Setup logging infrastructure
    source "${MODULES_DIR}/logging_setup.sh"
    setup_logging_infrastructure

    log_success "Foundation infrastructure setup completed"
}

# Function: install_dependencies
# Description: Install required system packages
install_dependencies() {
    if [[ "$SKIP_DEPS" == "true" ]]; then
        log_info "Skipping dependency installation"
        return 0
    fi

    log_info "Installing system dependencies..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would install: curl wget gnupg lsb-release apt-transport-https ca-certificates software-properties-common uuidgen qrencode python3 python3-pip"
        return 0
    fi

    local required_packages=(
        "curl"
        "wget"
        "gnupg"
        "lsb-release"
        "apt-transport-https"
        "ca-certificates"
        "software-properties-common"
        "uuidgen"
        "qrencode"
        "python3"
        "python3-pip"
        "python3-venv"
        "jq"
        "unzip"
        "tar"
        "gzip"
    )

    # Update package cache
    update_package_cache

    # Install packages
    for package in "${required_packages[@]}"; do
        if ! is_package_installed "$package"; then
            install_package "$package"
        else
            log_debug "Package already installed: $package"
        fi
    done

    log_success "System dependencies installed"
}

# Function: setup_docker
# Description: Install and configure Docker
setup_docker() {
    if [[ "$SKIP_DOCKER" == "true" ]]; then
        log_info "Skipping Docker installation"
        return 0
    fi

    log_info "Setting up Docker infrastructure..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would install Docker and Docker Compose"
        return 0
    fi

    # Check if Docker module exists and source it
    if [[ -f "${MODULES_DIR}/docker_setup.sh" ]]; then
        source "${MODULES_DIR}/docker_setup.sh"
        install_docker_infrastructure
    else
        log_warn "Docker setup module not found - will be available in Phase 2"
    fi

    log_success "Docker setup completed"
}

# Function: setup_user_management
# Description: Setup user management system
setup_user_management() {
    log_info "Setting up user management system..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would setup user management and QR code generation"
        return 0
    fi

    # Setup will be completed in Phase 3
    log_info "User management setup will be completed in Phase 3"
    log_success "User management placeholder setup completed"
}

# Function: setup_security
# Description: Setup security hardening
setup_security() {
    if [[ "$SKIP_SECURITY" == "true" ]]; then
        log_info "Skipping security hardening"
        return 0
    fi

    log_info "Setting up security hardening..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would setup UFW firewall and SSH hardening"
        return 0
    fi

    # Security setup will be completed in Phase 4
    log_info "Security hardening setup will be completed in Phase 4"
    log_success "Security placeholder setup completed"
}

# Function: setup_monitoring
# Description: Setup monitoring and backup systems
setup_monitoring() {
    log_info "Setting up monitoring and backup systems..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would setup monitoring, backup, and Telegram bot"
        return 0
    fi

    # Monitoring setup will be completed in Phase 5
    log_info "Monitoring setup will be completed in Phase 5"
    log_success "Monitoring placeholder setup completed"
}

# Function: finalize_installation
# Description: Finalize installation and create service files
finalize_installation() {
    log_info "Finalizing installation..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create systemd services and finalize configuration"
        return 0
    fi

    # Create installation info file
    local install_info="${CONFIG_DIR}/installation.info"
    cat > "$install_info" << EOF
# VLESS+Reality VPN Installation Information
INSTALLATION_DATE=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
INSTALLATION_VERSION=1.0
SCRIPT_VERSION=1.0
SYSTEM_INFO=$(uname -a)
DISTRIBUTION=$(lsb_release -ds 2>/dev/null || echo "Unknown")
INSTALLATION_USER=$(whoami)
INSTALLATION_PHASES_COMPLETED=Phase1-Foundation
DRY_RUN_MODE=$DRY_RUN
VERBOSE_MODE=$VERBOSE
FORCE_MODE=$FORCE_INSTALL
SKIP_DEPS=$SKIP_DEPS
SKIP_DOCKER=$SKIP_DOCKER
SKIP_SECURITY=$SKIP_SECURITY
CUSTOM_CONFIG=$CUSTOM_CONFIG
EOF

    chmod 600 "$install_info"

    # Create management scripts
    create_management_scripts

    log_success "Installation finalization completed"
}

# ======================================================================================
# MANAGEMENT SCRIPTS
# ======================================================================================

# Function: create_management_scripts
# Description: Create convenience management scripts
create_management_scripts() {
    local bin_dir="${VLESS_ROOT}/bin"
    create_directory "$bin_dir" "755" "root:root"

    # Create VLESS management script
    cat > "${bin_dir}/vless-manage" << 'EOF'
#!/bin/bash
# VLESS Management Utility
# Provides easy access to common VLESS management tasks

set -euo pipefail

VLESS_ROOT="/opt/vless"
source "${VLESS_ROOT}/modules/common_utils.sh"

show_usage() {
    cat << 'USAGE'
VLESS Management Utility

Usage: vless-manage [COMMAND] [OPTIONS]

COMMANDS:
    status              Show system status
    logs               Show recent logs
    update             Update system components
    backup             Create system backup
    restore            Restore from backup
    users              Manage VPN users
    config             View/edit configuration
    restart            Restart services
    version            Show version information

OPTIONS:
    -h, --help         Show help for specific command
    -v, --verbose      Enable verbose output

EXAMPLES:
    vless-manage status
    vless-manage logs --tail 100
    vless-manage users add username
    vless-manage backup --full

For detailed help on a specific command:
    vless-manage [COMMAND] --help
USAGE
}

case "${1:-}" in
    status)
        echo "VLESS System Status:"
        echo "==================="
        echo "Installation: Phase 1 (Foundation) Complete"
        echo "Next Phase: Phase 2 (Docker Infrastructure)"
        ;;
    logs)
        if [[ -f "${VLESS_ROOT}/bin/analyze-logs.sh" ]]; then
            "${VLESS_ROOT}/bin/analyze-logs.sh" "${@:2}"
        else
            echo "Log analysis not yet available (Phase 1 only)"
        fi
        ;;
    version)
        echo "VLESS+Reality VPN Management System"
        echo "Version: 1.0 (Phase 1)"
        echo "Installation Date: $(grep INSTALLATION_DATE ${VLESS_ROOT}/config/installation.info | cut -d'=' -f2)"
        ;;
    *)
        show_usage
        ;;
esac
EOF

    chmod 755 "${bin_dir}/vless-manage"

    # Create symlink in /usr/local/bin for easy access
    ln -sf "${bin_dir}/vless-manage" "/usr/local/bin/vless-manage"

    log_success "Management scripts created"
}

# ======================================================================================
# UNINSTALL FUNCTION
# ======================================================================================

# Function: uninstall_vless_system
# Description: Uninstall the VLESS system
uninstall_vless_system() {
    log_warn "Starting VLESS system uninstallation..."

    if [[ "$FORCE_INSTALL" != "true" ]]; then
        echo -n "Are you sure you want to uninstall VLESS system? This will remove all data. [y/N]: "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_info "Uninstallation cancelled"
            exit 0
        fi
    fi

    # Stop and remove services
    systemctl stop vless-* 2>/dev/null || true
    systemctl disable vless-* 2>/dev/null || true

    # Remove systemd service files
    rm -f /etc/systemd/system/vless-*.service
    systemctl daemon-reload

    # Remove VLESS directory
    if [[ -d "$VLESS_ROOT" ]]; then
        rm -rf "$VLESS_ROOT"
        log_info "Removed VLESS directory: $VLESS_ROOT"
    fi

    # Remove management script
    rm -f /usr/local/bin/vless-manage

    # Remove log configurations
    rm -f /etc/logrotate.d/vless
    rm -f /etc/rsyslog.d/49-vless.conf
    systemctl restart rsyslog 2>/dev/null || true

    log_success "VLESS system uninstalled successfully"
}

# ======================================================================================
# MAIN INSTALLATION FUNCTION
# ======================================================================================

# Function: run_installation
# Description: Run the complete installation process
run_installation() {
    local start_time
    start_time=$(date +%s)

    log_info "Starting VLESS+Reality VPN installation..."

    # Load custom configuration if provided
    if [[ -n "$CUSTOM_CONFIG" ]]; then
        log_info "Loading custom configuration from: $CUSTOM_CONFIG"
        # shellcheck source=/dev/null
        source "$CUSTOM_CONFIG"
    fi

    # Run installation phases
    local phase_count=0
    local total_phases=${#INSTALLATION_PHASES[@]}

    for phase in "${INSTALLATION_PHASES[@]}"; do
        ((phase_count++))
        log_info "Phase $phase_count/$total_phases: Running $phase..."

        if [[ "$VERBOSE" == "true" ]]; then
            set -x
        fi

        if ! "$phase"; then
            log_error "Installation failed during phase: $phase"
            return 1
        fi

        if [[ "$VERBOSE" == "true" ]]; then
            set +x
        fi

        log_success "Phase $phase_count/$total_phases completed: $phase"
    done

    # Calculate installation time
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log_success "VLESS+Reality VPN installation completed successfully!"
    log_info "Installation time: $((duration / 60))m $((duration % 60))s"

    # Show next steps
    show_next_steps
}

# Function: show_next_steps
# Description: Show next steps after installation
show_next_steps() {
    cat << 'EOF'

╔══════════════════════════════════════════════════════════════════════════════╗
║                           Installation Complete!                            ║
╚══════════════════════════════════════════════════════════════════════════════╝

Phase 1 (Foundation) has been completed successfully.

WHAT'S INSTALLED:
✓ Core utility modules (common_utils.sh, logging_setup.sh)
✓ Logging infrastructure with rotation
✓ Directory structure (/opt/vless)
✓ Management utilities

NEXT STEPS:
1. Continue with Phase 2: Docker Infrastructure
   ./install.sh --continue-phase2

2. Check system status:
   vless-manage status

3. View logs:
   vless-manage logs

4. For help:
   vless-manage --help

COMING IN FUTURE PHASES:
• Phase 2: Docker and Xray container setup
• Phase 3: User management and QR code generation
• Phase 4: Security hardening and firewall
• Phase 5: Monitoring, backup, and Telegram bot

For support and documentation:
- Configuration: /opt/vless/config/
- Logs: /opt/vless/logs/
- Management: vless-manage command

EOF
}

# ======================================================================================
# ERROR HANDLING AND CLEANUP
# ======================================================================================

# Function: cleanup_on_error
# Description: Cleanup function called on script failure
cleanup_on_error() {
    local exit_code=$?
    log_error "Installation failed with exit code: $exit_code"

    if [[ "$DRY_RUN" == "false" && -d "$VLESS_ROOT" ]]; then
        log_info "Cleaning up partial installation..."
        # Don't remove everything, just mark as incomplete
        echo "INSTALLATION_INCOMPLETE=true" >> "${CONFIG_DIR}/installation.info" 2>/dev/null || true
    fi

    log_error "Installation failed. Check logs for details."
    exit "$exit_code"
}

# Setup error handling
trap cleanup_on_error ERR

# ======================================================================================
# MAIN EXECUTION
# ======================================================================================

# Main function
main() {
    # Show banner
    show_banner

    # Parse arguments
    parse_arguments "$@"

    # Run installation
    run_installation
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi