#!/bin/bash

# VLESS+Reality VPN Management System - System Update Module
# Version: 1.0.0
# Description: Automated system updates and package management
#
# This module provides:
# - Distribution detection (Ubuntu/Debian)
# - Package manager update (apt)
# - Essential package installation
# - System reboot handling if required

set -euo pipefail

# Import common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_utils.sh"

# Essential packages required for the system
readonly ESSENTIAL_PACKAGES=(
    "curl"
    "wget"
    "gnupg2"
    "software-properties-common"
    "apt-transport-https"
    "ca-certificates"
    "lsb-release"
    "jq"
    "net-tools"
    "netstat-nat"
    "iptables"
    "ufw"
    "unzip"
    "zip"
    "tar"
    "gzip"
    "uuid-runtime"
    "python3"
    "python3-pip"
)

# Development packages (optional but recommended)
readonly DEV_PACKAGES=(
    "git"
    "vim"
    "nano"
    "htop"
    "tree"
    "screen"
    "tmux"
)

# Check if system reboot is required
check_reboot_required() {
    if [[ -f /var/run/reboot-required ]]; then
        log_warn "System reboot is required after updates"
        return 0
    fi
    return 1
}

# Update package repositories
update_package_repositories() {
    log_info "Updating package repositories..."

    # Update package lists
    if ! apt-get update -qq; then
        log_error "Failed to update package repositories"
        return 1
    fi

    log_success "Package repositories updated successfully"
    return 0
}

# Upgrade system packages
upgrade_system_packages() {
    local upgrade_type="${1:-safe}"  # safe, full, or security

    log_info "Upgrading system packages (type: $upgrade_type)..."

    case "$upgrade_type" in
        "safe")
            # Safe upgrade - only upgrade packages without removing any
            if ! apt-get upgrade -y -qq; then
                log_error "Safe package upgrade failed"
                return 1
            fi
            ;;
        "full")
            # Full upgrade - may install/remove packages as needed
            if ! apt-get dist-upgrade -y -qq; then
                log_error "Full package upgrade failed"
                return 1
            fi
            ;;
        "security")
            # Security-only updates
            if ! apt-get upgrade -y -qq -o Dir::Etc::SourceList=/etc/apt/sources.list.d/security.list; then
                log_warn "Security-only upgrade not available, performing safe upgrade"
                if ! apt-get upgrade -y -qq; then
                    log_error "Security package upgrade failed"
                    return 1
                fi
            fi
            ;;
        *)
            log_error "Invalid upgrade type: $upgrade_type (use: safe, full, security)"
            return 1
            ;;
    esac

    log_success "System packages upgraded successfully"
    return 0
}

# Install essential packages
install_essential_packages() {
    local failed_packages=()
    local package

    log_info "Installing essential packages..."

    # Check which packages are missing
    local missing_packages=()
    for package in "${ESSENTIAL_PACKAGES[@]}"; do
        if ! dpkg -l | grep -q "^ii.*${package}"; then
            missing_packages+=("$package")
        fi
    done

    if [[ ${#missing_packages[@]} -eq 0 ]]; then
        log_success "All essential packages are already installed"
        return 0
    fi

    log_info "Installing ${#missing_packages[@]} missing packages: ${missing_packages[*]}"

    # Install missing packages
    if ! apt-get install -y -qq "${missing_packages[@]}"; then
        log_warn "Bulk installation failed, trying individual packages..."

        # Try installing packages individually
        for package in "${missing_packages[@]}"; do
            if ! apt-get install -y -qq "$package"; then
                log_error "Failed to install package: $package"
                failed_packages+=("$package")
            else
                log_success "Installed package: $package"
            fi
        done
    else
        log_success "All essential packages installed successfully"
    fi

    # Report failed installations
    if [[ ${#failed_packages[@]} -gt 0 ]]; then
        log_error "Failed to install ${#failed_packages[@]} packages: ${failed_packages[*]}"
        return 1
    fi

    return 0
}

# Install development packages (optional)
install_development_packages() {
    local failed_packages=()
    local package

    log_info "Installing development packages (optional)..."

    for package in "${DEV_PACKAGES[@]}"; do
        if ! dpkg -l | grep -q "^ii.*${package}"; then
            if apt-get install -y -qq "$package"; then
                log_success "Installed development package: $package"
            else
                log_warn "Failed to install development package: $package (non-critical)"
                failed_packages+=("$package")
            fi
        fi
    done

    if [[ ${#failed_packages[@]} -eq 0 ]]; then
        log_success "All development packages installed successfully"
    else
        log_warn "Some development packages failed to install (non-critical): ${failed_packages[*]}"
    fi

    return 0
}

# Clean package cache
clean_package_cache() {
    log_info "Cleaning package cache..."

    # Remove downloaded package files
    if apt-get clean; then
        log_debug "Package cache cleaned"
    fi

    # Remove orphaned packages
    if apt-get autoremove -y -qq; then
        log_debug "Orphaned packages removed"
    fi

    # Remove unnecessary package files
    if apt-get autoclean -qq; then
        log_debug "Unnecessary package files removed"
    fi

    log_success "Package cache cleaned successfully"
    return 0
}

# Configure automatic updates
configure_automatic_updates() {
    log_info "Configuring automatic security updates..."

    # Install unattended-upgrades if not present
    install_package_if_missing "unattended-upgrades"

    # Configure unattended-upgrades
    local unattended_config="/etc/apt/apt.conf.d/50unattended-upgrades"
    local auto_config="/etc/apt/apt.conf.d/20auto-upgrades"

    # Backup existing configuration
    if [[ -f "$unattended_config" ]]; then
        backup_file "$unattended_config"
    fi

    # Create unattended-upgrades configuration
    cat > "$unattended_config" << 'EOF'
// Automatically upgrade packages from these repositories
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

// Packages to never automatically upgrade
Unattended-Upgrade::Package-Blacklist {
    // "vim";
    // "libc6-dev";
    "linux-image*";
    "linux-headers*";
    "linux-modules*";
    "docker*";
    "containerd*";
};

// Split the upgrade into the smallest possible chunks so that
// they can be interrupted with SIGTERM
Unattended-Upgrade::MinimalSteps "true";

// Install upgrades when the machine is shutting down
Unattended-Upgrade::InstallOnShutdown "false";

// Send email to this address for problems or packages upgrades
//Unattended-Upgrade::Mail "";

// Set this value to "true" to get emails only on errors
Unattended-Upgrade::MailOnlyOnError "true";

// Remove unused automatically installed kernel-related packages
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";

// Do automatic removal of newly unused dependencies after the upgrade
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";

// Do automatic removal of unused packages after the upgrade
Unattended-Upgrade::Remove-Unused-Dependencies "true";

// Automatically reboot WITHOUT CONFIRMATION if required
Unattended-Upgrade::Automatic-Reboot "false";

// Automatically reboot even if there are users currently logged in
Unattended-Upgrade::Automatic-Reboot-WithUsers "false";

// If automatic reboot is enabled and needed, reboot at the specific time
//Unattended-Upgrade::Automatic-Reboot-Time "02:00";

// Use apt bandwidth limit feature
//Acquire::http::Dl-Limit "70";

// Enable logging to syslog
Unattended-Upgrade::SyslogEnable "true";
Unattended-Upgrade::SyslogFacility "daemon";

// Verbose logging
Unattended-Upgrade::Verbose "false";
Unattended-Upgrade::Debug "false";
EOF

    # Create auto-upgrades configuration
    cat > "$auto_config" << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

    log_success "Automatic security updates configured"
    return 0
}

# Check system compatibility
check_system_compatibility() {
    local distribution
    local version
    local architecture

    log_info "Checking system compatibility..."

    distribution=$(detect_distribution)
    architecture=$(detect_architecture)

    case "$distribution" in
        "ubuntu")
            source /etc/os-release
            version="$VERSION_ID"
            if [[ $(echo "$version >= 20.04" | bc -l) -eq 1 ]]; then
                log_success "Ubuntu $version detected - compatible"
            else
                log_warn "Ubuntu $version detected - may have compatibility issues (recommended: 20.04+)"
            fi
            ;;
        "debian")
            source /etc/os-release
            version="$VERSION_ID"
            if [[ $(echo "$version >= 10" | bc -l) -eq 1 ]]; then
                log_success "Debian $version detected - compatible"
            else
                log_warn "Debian $version detected - may have compatibility issues (recommended: 10+)"
            fi
            ;;
        *)
            log_warn "Unsupported distribution: $distribution"
            log_warn "This system is designed for Ubuntu 20.04+ or Debian 10+"
            return 1
            ;;
    esac

    case "$architecture" in
        "amd64"|"arm64"|"armhf")
            log_success "Architecture $architecture detected - compatible"
            ;;
        *)
            log_warn "Unsupported architecture: $architecture"
            log_warn "Supported architectures: amd64, arm64, armhf"
            return 1
            ;;
    esac

    return 0
}

# Get system status summary
get_system_status() {
    local distribution
    local version
    local architecture
    local kernel
    local uptime
    local load
    local memory
    local disk

    distribution=$(detect_distribution)
    architecture=$(detect_architecture)
    kernel=$(uname -r)
    uptime=$(uptime -p 2>/dev/null || uptime)
    load=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    memory=$(free -h | awk '/^Mem:/ {print $3"/"$2}')
    disk=$(df -h / | awk 'NR==2 {print $3"/"$2" ("$5" used)"}')

    cat << EOF

=== System Status Summary ===
Distribution: $distribution
Architecture: $architecture
Kernel: $kernel
Uptime: $uptime
Load Average: $load
Memory Usage: $memory
Disk Usage: $disk
$(check_reboot_required && echo "Reboot Required: YES" || echo "Reboot Required: NO")

EOF
}

# Main system update function
perform_system_update() {
    local upgrade_type="${1:-safe}"
    local install_dev="${2:-false}"
    local configure_auto="${3:-true}"

    log_info "Starting system update process..."

    # Check system compatibility
    if ! check_system_compatibility; then
        log_warn "System compatibility check failed, continuing anyway..."
    fi

    # Ensure we have root privileges
    require_root

    # Check network connectivity
    if ! check_network_connectivity; then
        die "Network connectivity required for system updates" 6
    fi

    # Update package repositories
    if ! update_package_repositories; then
        die "Failed to update package repositories" 7
    fi

    # Upgrade system packages
    if ! upgrade_system_packages "$upgrade_type"; then
        die "Failed to upgrade system packages" 8
    fi

    # Install essential packages
    if ! install_essential_packages; then
        die "Failed to install essential packages" 9
    fi

    # Install development packages if requested
    if [[ "$install_dev" == "true" ]]; then
        install_development_packages
    fi

    # Configure automatic updates if requested
    if [[ "$configure_auto" == "true" ]]; then
        configure_automatic_updates
    fi

    # Clean package cache
    clean_package_cache

    # Check if reboot is required
    if check_reboot_required; then
        log_warn "System reboot is required to complete the update process"
        log_warn "Please reboot the system when convenient"
    fi

    log_success "System update completed successfully"
    get_system_status
}

# Handle system reboot
handle_system_reboot() {
    local force="${1:-false}"

    if check_reboot_required; then
        if [[ "$force" == "true" ]]; then
            log_warn "Forcing system reboot in 10 seconds..."
            log_warn "Press Ctrl+C to cancel"

            for i in {10..1}; do
                echo -n "$i... "
                sleep 1
            done
            echo

            log_info "Rebooting system now..."
            reboot
        else
            log_warn "System reboot is required but not forced"
            log_warn "Run with --force-reboot to reboot automatically"
            return 1
        fi
    else
        log_info "No system reboot required"
        return 0
    fi
}

# Display help information
show_help() {
    cat << EOF
VLESS+Reality VPN System Update Module

Usage: $0 [OPTIONS]

Options:
    --upgrade-type TYPE    Upgrade type: safe, full, or security (default: safe)
    --install-dev         Install development packages
    --no-auto-updates     Skip automatic update configuration
    --force-reboot        Force reboot if required
    --status              Show system status only
    --help                Show this help message

Examples:
    $0                           # Safe system update
    $0 --upgrade-type full       # Full system upgrade
    $0 --install-dev            # Include development packages
    $0 --status                 # Show system status only
    $0 --force-reboot           # Force reboot if required

EOF
}

# Main execution
main() {
    local upgrade_type="safe"
    local install_dev="false"
    local configure_auto="true"
    local force_reboot="false"
    local status_only="false"

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --upgrade-type)
                upgrade_type="$2"
                shift 2
                ;;
            --install-dev)
                install_dev="true"
                shift
                ;;
            --no-auto-updates)
                configure_auto="false"
                shift
                ;;
            --force-reboot)
                force_reboot="true"
                shift
                ;;
            --status)
                status_only="true"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Setup signal handlers for process isolation
    setup_signal_handlers

    # Show status only if requested
    if [[ "$status_only" == "true" ]]; then
        get_system_status
        exit 0
    fi

    # Perform system update
    perform_system_update "$upgrade_type" "$install_dev" "$configure_auto"

    # Handle reboot if requested
    if [[ "$force_reboot" == "true" ]]; then
        handle_system_reboot "true"
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi