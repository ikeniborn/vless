#!/bin/bash
################################################################################
# VLESS + Reality VPN Server - Installation Entry Point
#
# Description:
#   Main entry point for VLESS Reality VPN installation system.
#   Orchestrates the complete installation process by calling modular functions
#   from the lib/ directory.
#
# Usage:
#   sudo ./install.sh
#
#   Non-Interactive Mode (for automation):
#     VLESS_AUTO_CLEANUP=1 sudo ./install.sh          # Auto backup+cleanup old installation
#     VLESS_AUTO_CLEANUP=2 sudo ./install.sh          # Auto cleanup without backup
#     VLESS_AUTO_CLEANUP=3 sudo ./install.sh          # Auto skip and exit
#     VLESS_CONFIRM_CLEANUP=yes sudo ./install.sh     # Auto-confirm cleanup prompts
#     VLESS_AUTO_INSTALL_DEPS=yes sudo ./install.sh   # Auto-install missing dependencies
#
# Requirements:
#   - Must be run as root
#   - Must be executed from project directory
#   - All lib/* modules must be present
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Permission error (not root)
#   3 - Dependency error
#
# Version: 5.17
# Date: 2025-10-21
################################################################################

set -euo pipefail

# Colors for output
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_RESET='\033[0m'

# Version tracking (matches CHANGELOG.md)
# Note: renamed from VERSION to VLESS_VERSION to avoid conflict with /etc/os-release
readonly VLESS_VERSION="5.17"

# Get script directory (works even if script is symlinked)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# Total installation steps
readonly TOTAL_STEPS=10

################################################################################
# Function: print_message
# Description: Print colored message to stdout
# Arguments:
#   $1 - Color code
#   $2 - Message text
################################################################################
print_message() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${COLOR_RESET}"
}

################################################################################
# Function: print_step
# Description: Print step indicator with progress
# Arguments:
#   $1 - Current step number
#   $2 - Step description
################################################################################
print_step() {
    local step="$1"
    local description="$2"
    print_message "${COLOR_CYAN}" "\n[${step}/${TOTAL_STEPS}] ${description}..."
}

################################################################################
# Function: print_success
# Description: Print success message
# Arguments:
#   $1 - Message text
################################################################################
print_success() {
    print_message "${COLOR_GREEN}" "✓ $1"
}

################################################################################
# Function: print_error
# Description: Print error message to stderr
# Arguments:
#   $1 - Message text
################################################################################
print_error() {
    print_message "${COLOR_RED}" "✗ ERROR: $1" >&2
}

################################################################################
# Function: print_warning
# Description: Print warning message
# Arguments:
#   $1 - Message text
################################################################################
print_warning() {
    print_message "${COLOR_YELLOW}" "⚠ WARNING: $1"
}

################################################################################
# Function: cleanup_on_error
# Description: Cleanup handler called on script errors
################################################################################
cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        print_error "Installation failed with exit code ${exit_code}"
        print_message "${COLOR_YELLOW}" "\nTo retry installation:"
        print_message "${COLOR_YELLOW}" "  cd ${SCRIPT_DIR}"
        print_message "${COLOR_YELLOW}" "  sudo ./install.sh"
    fi
}

# Set trap for error cleanup
trap cleanup_on_error EXIT

################################################################################
# Function: print_banner
# Description: Display welcome banner
################################################################################
print_banner() {
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║          VLESS + Reality VPN Server Installation            ║
║                                                              ║
║  Production-grade CLI-based Reality protocol deployment     ║
║  Version: 4.3 (HAProxy Unified Architecture)               ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo ""
}

################################################################################
# Function: check_root
# Description: Verify script is run with root privileges
# Returns: Exit code 2 if not root
################################################################################
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        print_message "${COLOR_YELLOW}" "Please run: sudo ./install.sh"
        exit 2
    fi
}

################################################################################
# Function: source_libraries
# Description: Source all required library modules from lib/ directory
# Returns: Exit code 1 if any module is missing
################################################################################
source_libraries() {
    local lib_dir="${SCRIPT_DIR}/lib"
    local required_modules=(
        "os_detection.sh"
        "dependencies.sh"
        "old_install_detect.sh"
        "interactive_params.sh"
        "sudoers_info.sh"
        "orchestrator.sh"
        "verification.sh"
        "security_hardening.sh"
        "certbot_setup.sh"
    )

    # Check if lib directory exists
    if [[ ! -d "${lib_dir}" ]]; then
        print_error "Library directory not found: ${lib_dir}"
        print_message "${COLOR_YELLOW}" "Make sure you are running this script from the project directory:"
        print_message "${COLOR_YELLOW}" "  cd /path/to/vless"
        print_message "${COLOR_YELLOW}" "  sudo ./install.sh"
        exit 1
    fi

    # Source each required module
    for module in "${required_modules[@]}"; do
        local module_path="${lib_dir}/${module}"

        if [[ ! -f "${module_path}" ]]; then
            print_error "Required module not found: ${module}"
            print_message "${COLOR_YELLOW}" "Expected location: ${module_path}"
            print_message "${COLOR_YELLOW}" "\nPlease ensure all modules are present in the lib/ directory."
            exit 1
        fi

        # shellcheck source=/dev/null
        source "${module_path}" || {
            print_error "Failed to source module: ${module}"
            exit 1
        }

        # After sourcing orchestrator.sh, export paths for subsequent modules
        if [[ "$module" == "orchestrator.sh" ]]; then
            export CONFIG_DIR
            export LOG_DIR="${LOGS_DIR}"
        fi
    done

    print_success "All library modules loaded successfully"
}

################################################################################
# Function: main
# Description: Main installation orchestration function
# Workflow:
#   1. Check root privileges
#   2. Detect operating system
#   3. Validate OS compatibility
#   4. Check for required dependencies
#   5. Install missing dependencies
#   6. Detect old installations
#   7. Collect installation parameters interactively
#   8. Orchestrate the installation process (creates /opt/vless)
#   9. Verify installation success
#   10. Display sudoers configuration instructions
################################################################################
main() {
    # Display welcome banner
    print_banner

    # Step 1: Root privilege check (before sourcing modules)
    print_step 1 "Checking root privileges"
    check_root
    print_success "Running with root privileges"

    # Source all library modules
    print_message "${COLOR_BLUE}" "\nLoading installation modules..."
    source_libraries

    # Step 2: Detect operating system
    print_step 2 "Detecting operating system"
    detect_os
    print_success "Operating system detected"

    # Step 3: Validate OS compatibility
    print_step 3 "Validating OS compatibility"
    validate_os
    print_success "Operating system is compatible"

    # Get package manager (required for dependency installation)
    get_package_manager

    # Step 4: Check dependencies
    print_step 4 "Checking dependencies"
    if ! check_dependencies; then
        # User declined to install missing dependencies
        print_error "Dependency installation declined"
        exit 1
    fi
    print_success "Dependency check complete"

    # Step 5: Install missing dependencies
    print_step 5 "Installing missing dependencies"
    install_dependencies
    print_success "Dependencies installed"

    # Step 6: Detect old installations
    print_step 6 "Detecting previous installations"
    detect_old_installation

    # If old installation found, offer cleanup before proceeding
    if [[ "$OLD_INSTALL_FOUND" == "true" ]]; then
        display_detection_summary

        # Check for non-interactive mode via environment variable
        if [[ -n "${VLESS_AUTO_CLEANUP:-}" ]]; then
            cleanup_choice="${VLESS_AUTO_CLEANUP}"
            print_message "${COLOR_CYAN}" "Non-interactive mode: Using VLESS_AUTO_CLEANUP=$cleanup_choice"
        else
            echo ""
            print_message "${COLOR_YELLOW}" "Would you like to:"
            print_message "${COLOR_CYAN}" "  1) Backup and cleanup old installation (recommended)"
            print_message "${COLOR_CYAN}" "  2) Cleanup without backup (risky)"
            print_message "${COLOR_CYAN}" "  3) Skip cleanup and exit"
            echo ""

            # Read with 60-second timeout, default to option 3 (safe exit)
            if ! read -t 60 -rp "Enter your choice [1-3] (60s timeout, default=3): " cleanup_choice; then
                cleanup_choice="3"
                echo ""
                print_message "${COLOR_YELLOW}" "Input timeout reached, defaulting to safe exit (option 3)"
            fi

            # If empty input, default to safe exit
            [[ -z "$cleanup_choice" ]] && cleanup_choice="3"
        fi

        case "$cleanup_choice" in
            1)
                print_message "${COLOR_BLUE}" "Creating backup..."
                backup_old_installation || {
                    print_error "Backup failed"
                    exit 1
                }
                print_message "${COLOR_BLUE}" "Cleaning up old installation..."
                cleanup_old_installation || {
                    print_warning "Cleanup completed with warnings"
                }
                ;;
            2)
                print_message "${COLOR_BLUE}" "Cleaning up without backup..."
                cleanup_old_installation || {
                    print_warning "Cleanup completed with warnings"
                }
                ;;
            3)
                print_message "${COLOR_YELLOW}" "Installation cancelled by user"
                exit 0
                ;;
            *)
                print_error "Invalid choice. Installation cancelled."
                exit 1
                ;;
        esac
    fi

    print_success "Old installation check complete"

    # Step 7: Collect installation parameters
    print_step 7 "Collecting installation parameters"
    collect_parameters
    print_success "Parameters collected"

    # Step 7.5: Acquire TLS certificate (v3.4) - only if public proxy + TLS enabled
    if [[ "$ENABLE_PUBLIC_PROXY" == "true" ]] && [[ "$ENABLE_PROXY_TLS" == "true" ]]; then
        print_message "${COLOR_BLUE}" "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        print_message "${COLOR_BLUE}" "  TLS CERTIFICATE ACQUISITION (v3.3)"
        print_message "${COLOR_BLUE}" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        # Get server public IP for DNS validation
        local server_ip
        server_ip=$(get_server_public_ip)

        # 1. Validate DNS
        print_message "${COLOR_CYAN}" "[1/6] Validating DNS configuration..."
        if ! validate_domain_dns "$DOMAIN" "$server_ip"; then
            print_error "DNS validation failed. Certificate acquisition aborted."
            print_message "${COLOR_YELLOW}" "Fix DNS configuration and retry installation."
            exit 1
        fi

        # 2. Install certbot
        print_message "${COLOR_CYAN}" "[2/6] Installing certbot..."
        if ! install_certbot; then
            print_error "Certbot installation failed"
            exit 1
        fi

        # 3. Open port 80 for ACME challenge
        print_message "${COLOR_CYAN}" "[3/6] Opening port 80 for ACME HTTP-01 challenge..."
        if ! open_port_80_for_acme; then
            print_error "Failed to open port 80"
            exit 1
        fi

        # 4. Obtain certificate
        print_message "${COLOR_CYAN}" "[4/6] Obtaining Let's Encrypt certificate..."
        print_message "${COLOR_YELLOW}" "  This may take 30-60 seconds..."
        if ! obtain_certificate "$DOMAIN" "$EMAIL"; then
            print_error "Certificate acquisition failed"
            # Attempt to close port 80 even on failure
            close_port_80_after_acme || true
            exit 1
        fi

        # 5. Close port 80
        print_message "${COLOR_CYAN}" "[5/6] Closing port 80..."
        if ! close_port_80_after_acme; then
            print_warning "Failed to close port 80 automatically"
            print_message "${COLOR_YELLOW}" "  You may need to manually close it: sudo ufw delete allow 80/tcp"
        fi

        # 6. Setup auto-renewal cron job
        print_message "${COLOR_CYAN}" "[6/6] Setting up certificate auto-renewal..."
        if ! setup_renewal_cron; then
            print_warning "Failed to setup auto-renewal cron"
            print_message "${COLOR_YELLOW}" "  You may need to configure it manually"
        fi

        # Install deploy hook script
        print_message "${COLOR_CYAN}" "Installing certificate renewal deploy hook..."
        if [[ -f "${SCRIPT_DIR}/scripts/vless-cert-renew" ]]; then
            cp "${SCRIPT_DIR}/scripts/vless-cert-renew" /usr/local/bin/vless-cert-renew
            chmod 755 /usr/local/bin/vless-cert-renew
            print_success "Deploy hook installed"
        else
            print_warning "Deploy hook script not found, skipping"
        fi

        print_success "TLS certificate acquisition complete"
        print_message "${COLOR_GREEN}" "  Certificate: /etc/letsencrypt/live/$DOMAIN/fullchain.pem"
        print_message "${COLOR_GREEN}" "  Auto-renewal: Enabled (twice daily)"
        echo ""
    fi

    # Step 8: Orchestrate installation (THIS creates /opt/vless and copies files)
    print_step 8 "Orchestrating installation"
    print_message "${COLOR_BLUE}" "  → Creating /opt/vless directory structure"
    print_message "${COLOR_BLUE}" "  → Copying files from project to /opt/vless"
    print_message "${COLOR_BLUE}" "  → Configuring Docker network"
    print_message "${COLOR_BLUE}" "  → Setting up Xray configuration"
    print_message "${COLOR_BLUE}" "  → Deploying containers"
    orchestrate_installation
    print_success "Installation orchestration complete"

    # Step 9: Verify installation
    print_step 9 "Verifying installation"
    verify_installation
    print_success "Installation verified"

    # Step 9.5: Save version file
    echo "${VLESS_VERSION}" > "${INSTALL_ROOT}/.version"
    chmod 644 "${INSTALL_ROOT}/.version"
    print_message "${COLOR_CYAN}" "Version file saved: v${VLESS_VERSION}"

    # Step 10: Display sudoers instructions
    print_step 10 "Displaying sudoers configuration"
    display_sudoers_instructions

    # Final success message
    echo ""
    print_message "${COLOR_GREEN}" "╔══════════════════════════════════════════════════════════════╗"
    print_message "${COLOR_GREEN}" "║                                                              ║"
    print_message "${COLOR_GREEN}" "║           Installation Completed Successfully!              ║"
    print_message "${COLOR_GREEN}" "║                                                              ║"
    print_message "${COLOR_GREEN}" "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    print_message "${COLOR_CYAN}" "Next Steps:"
    print_message "${COLOR_YELLOW}" "  1. Configure sudoers (see instructions above)"
    print_message "${COLOR_YELLOW}" "  2. Add your first user: vless add-user <username>"
    print_message "${COLOR_YELLOW}" "  3. Check service status: vless status"
    print_message "${COLOR_YELLOW}" "  4. View logs: vless logs"
    echo ""
    print_message "${COLOR_CYAN}" "Installation directory: /opt/vless"
    print_message "${COLOR_CYAN}" "Management command: vless"
    echo ""

    # Clear error trap on success
    trap - EXIT
}

################################################################################
# Script Entry Point
################################################################################
main "$@"
