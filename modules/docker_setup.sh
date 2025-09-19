#!/bin/bash
# Docker Setup Module for VLESS VPN Project
# Automated Docker and Docker Compose installation with safety measures
# Compatible with Ubuntu 20.04+ and Debian 11+
# Author: Claude Code
# Version: 1.0

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(dirname "$SCRIPT_DIR")"

# Import process isolation module
source "${SCRIPT_DIR}/process_isolation/process_safe.sh" 2>/dev/null || {
    echo "ERROR: Cannot load process isolation module" >&2
    exit 1
}

# Setup signal handlers
setup_signal_handlers

# Configuration
readonly LOG_DIR="/opt/vless/logs"
readonly LOG_FILE="${LOG_DIR}/docker_setup.log"
readonly BACKUP_DIR="/opt/vless/backups"
readonly DOCKER_TIMEOUT=600  # 10 minutes for Docker operations
readonly DOCKER_COMPOSE_VERSION="v2.21.0"  # Latest stable version

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m'

# Logging functions
log_to_file() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$LOG_FILE"
}

log_info() {
    local message="$1"
    echo -e "${GREEN}[INFO]${NC} $message"
    log_to_file "INFO: $message"
}

log_warning() {
    local message="$1"
    echo -e "${YELLOW}[WARNING]${NC} $message"
    log_to_file "WARNING: $message"
}

log_error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC} $message"
    log_to_file "ERROR: $message"
}

log_debug() {
    local message="$1"
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $message"
    fi
    log_to_file "DEBUG: $message"
}

log_success() {
    local message="$1"
    echo -e "${GREEN}✓${NC} $message"
    log_to_file "SUCCESS: $message"
}

# Initialize logging
init_logging() {
    if [[ ! -d "$LOG_DIR" ]]; then
        sudo mkdir -p "$LOG_DIR"
        sudo chown "$USER:$USER" "$LOG_DIR"
        sudo chmod 755 "$LOG_DIR"
    fi

    if [[ ! -f "$LOG_FILE" ]]; then
        touch "$LOG_FILE"
        chmod 644 "$LOG_FILE"
    fi

    log_info "Docker setup module initialized"
}

# Check if running as root (when needed)
check_root_privileges() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This function requires root privileges. Please run with sudo."
        return 1
    fi
}

# Detect OS distribution and architecture
detect_system_info() {
    local info_array=()

    # Detect OS
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        info_array+=("$ID")
        info_array+=("$VERSION_ID")
    else
        log_error "Cannot detect OS distribution"
        return 1
    fi

    # Detect architecture
    local arch=$(uname -m)
    case "$arch" in
        x86_64)
            info_array+=("amd64")
            ;;
        aarch64|arm64)
            info_array+=("arm64")
            ;;
        armv7l)
            info_array+=("armhf")
            ;;
        *)
            log_error "Unsupported architecture: $arch"
            return 1
            ;;
    esac

    echo "${info_array[@]}"
}

# Check Docker installation requirements
check_docker_requirements() {
    log_info "Checking Docker installation requirements..."

    local system_info
    if ! system_info=($(detect_system_info)); then
        return 1
    fi

    local os_id="${system_info[0]}"
    local os_version="${system_info[1]}"
    local arch="${system_info[2]}"

    log_info "Detected system: $os_id $os_version ($arch)"

    # Check OS compatibility
    case "$os_id" in
        ubuntu)
            if ! dpkg --compare-versions "$os_version" ge "20.04"; then
                log_error "Ubuntu $os_version is not supported. Minimum version: 20.04"
                return 1
            fi
            ;;
        debian)
            if ! dpkg --compare-versions "$os_version" ge "11"; then
                log_error "Debian $os_version is not supported. Minimum version: 11"
                return 1
            fi
            ;;
        *)
            log_error "Unsupported OS: $os_id. Only Ubuntu 20.04+ and Debian 11+ are supported."
            return 1
            ;;
    esac

    # Check available disk space (minimum 2GB)
    local available_space=$(df / | awk 'NR==2 {print $4}')
    local min_space=$((2 * 1024 * 1024))  # 2GB in KB

    if [[ "$available_space" -lt "$min_space" ]]; then
        log_error "Insufficient disk space. Available: $(($available_space / 1024 / 1024))GB, Required: 2GB"
        return 1
    fi

    # Check memory (minimum 1GB)
    local total_memory=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local min_memory=$((1024 * 1024))  # 1GB in KB

    if [[ "$total_memory" -lt "$min_memory" ]]; then
        log_error "Insufficient memory. Available: $(($total_memory / 1024 / 1024))GB, Required: 1GB"
        return 1
    fi

    log_success "System requirements check passed"
    return 0
}

# Check if Docker is already installed
check_docker_installed() {
    if command -v docker >/dev/null 2>&1; then
        local docker_version=$(docker --version 2>/dev/null || echo "unknown")
        log_info "Docker is already installed: $docker_version"
        return 0
    else
        log_info "Docker is not installed"
        return 1
    fi
}

# Check if Docker Compose is already installed
check_docker_compose_installed() {
    if command -v docker-compose >/dev/null 2>&1; then
        local compose_version=$(docker-compose --version 2>/dev/null || echo "unknown")
        log_info "Docker Compose (standalone) is installed: $compose_version"
        return 0
    elif docker compose version >/dev/null 2>&1; then
        local compose_version=$(docker compose version 2>/dev/null || echo "unknown")
        log_info "Docker Compose (plugin) is installed: $compose_version"
        return 0
    else
        log_info "Docker Compose is not installed"
        return 1
    fi
}

# Remove old Docker versions
remove_old_docker() {
    log_info "Removing old Docker versions..."

    local old_packages=(
        "docker"
        "docker-engine"
        "docker.io"
        "containerd"
        "runc"
        "docker-compose"
    )

    local remove_cmd="apt-get remove -y"
    for package in "${old_packages[@]}"; do
        remove_cmd+=" $package"
    done

    if isolated_sudo_command "$remove_cmd" 180 "Remove old Docker packages"; then
        log_success "Old Docker packages removed"
    else
        log_warning "Some old packages could not be removed (this may be normal)"
    fi

    # Clean up residual files
    local cleanup_cmd="apt-get autoremove -y && apt-get autoclean"
    isolated_sudo_command "$cleanup_cmd" 120 "Cleanup after package removal"
}

# Install required packages
install_prerequisites() {
    log_info "Installing prerequisite packages..."

    local update_cmd="apt-get update"
    if ! isolated_sudo_command "$update_cmd" 300 "Update package lists"; then
        log_error "Failed to update package lists"
        return 1
    fi

    local packages=(
        "ca-certificates"
        "curl"
        "gnupg"
        "lsb-release"
        "apt-transport-https"
        "software-properties-common"
    )

    local install_cmd="DEBIAN_FRONTEND=noninteractive apt-get install -y"
    for package in "${packages[@]}"; do
        install_cmd+=" $package"
    done

    if isolated_sudo_command "$install_cmd" 300 "Install prerequisite packages"; then
        log_success "Prerequisite packages installed"
        return 0
    else
        log_error "Failed to install prerequisite packages"
        return 1
    fi
}

# Add Docker GPG key and repository
setup_docker_repository() {
    log_info "Setting up Docker repository..."

    local system_info
    system_info=($(detect_system_info))
    local os_id="${system_info[0]}"
    local arch="${system_info[2]}"

    # Create keyrings directory
    local keyring_setup_cmd="mkdir -p /etc/apt/keyrings"
    if ! isolated_sudo_command "$keyring_setup_cmd" 30 "Create keyrings directory"; then
        log_error "Failed to create keyrings directory"
        return 1
    fi

    # Download and add Docker GPG key
    local gpg_key_cmd="curl -fsSL https://download.docker.com/linux/$os_id/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
    if ! isolated_sudo_command "$gpg_key_cmd" 120 "Download Docker GPG key"; then
        log_error "Failed to download Docker GPG key"
        return 1
    fi

    # Set proper permissions for GPG key
    local chmod_cmd="chmod a+r /etc/apt/keyrings/docker.gpg"
    isolated_sudo_command "$chmod_cmd" 10 "Set GPG key permissions"

    # Add Docker repository
    local repo_cmd="echo \"deb [arch=$arch signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$os_id \$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list"
    if ! isolated_sudo_command "$repo_cmd" 30 "Add Docker repository"; then
        log_error "Failed to add Docker repository"
        return 1
    fi

    # Update package lists with new repository
    local update_cmd="apt-get update"
    if isolated_sudo_command "$update_cmd" 300 "Update package lists with Docker repo"; then
        log_success "Docker repository configured"
        return 0
    else
        log_error "Failed to update package lists after adding Docker repository"
        return 1
    fi
}

# Install Docker Engine
install_docker_engine() {
    log_info "Installing Docker Engine..."

    local docker_packages=(
        "docker-ce"
        "docker-ce-cli"
        "containerd.io"
        "docker-buildx-plugin"
        "docker-compose-plugin"
    )

    local install_cmd="DEBIAN_FRONTEND=noninteractive apt-get install -y"
    for package in "${docker_packages[@]}"; do
        install_cmd+=" $package"
    done

    if isolated_sudo_command "$install_cmd" "$DOCKER_TIMEOUT" "Install Docker packages"; then
        log_success "Docker Engine installed successfully"
        return 0
    else
        log_error "Failed to install Docker Engine"
        return 1
    fi
}

# Configure Docker service
configure_docker_service() {
    log_info "Configuring Docker service..."

    # Enable Docker service
    if isolate_systemctl_command "enable" "docker" 30; then
        log_success "Docker service enabled"
    else
        log_error "Failed to enable Docker service"
        return 1
    fi

    # Start Docker service
    if isolate_systemctl_command "start" "docker" 60; then
        log_success "Docker service started"
    else
        log_error "Failed to start Docker service"
        return 1
    fi

    # Verify Docker is running
    if check_service_health "docker" 3 5; then
        log_success "Docker service is running properly"
        return 0
    else
        log_error "Docker service health check failed"
        return 1
    fi
}

# Add user to docker group
add_user_to_docker_group() {
    local username="${1:-$USER}"

    log_info "Adding user '$username' to docker group..."

    local usermod_cmd="usermod -aG docker $username"
    if isolated_sudo_command "$usermod_cmd" 30 "Add user to docker group"; then
        log_success "User '$username' added to docker group"
        log_warning "You may need to log out and back in for group changes to take effect"
        return 0
    else
        log_error "Failed to add user to docker group"
        return 1
    fi
}

# Install Docker Compose (if not installed as plugin)
install_docker_compose_standalone() {
    log_info "Installing Docker Compose standalone..."

    local system_info
    system_info=($(detect_system_info))
    local arch="${system_info[2]}"

    # Map architecture for Docker Compose
    local compose_arch
    case "$arch" in
        amd64) compose_arch="x86_64" ;;
        arm64) compose_arch="aarch64" ;;
        armhf) compose_arch="armv7" ;;
        *)
            log_error "Unsupported architecture for Docker Compose: $arch"
            return 1
            ;;
    esac

    local compose_url="https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-${compose_arch}"
    local download_cmd="curl -L '$compose_url' -o /usr/local/bin/docker-compose"

    if isolated_sudo_command "$download_cmd" 300 "Download Docker Compose"; then
        local chmod_cmd="chmod +x /usr/local/bin/docker-compose"
        if isolated_sudo_command "$chmod_cmd" 10 "Make Docker Compose executable"; then
            log_success "Docker Compose standalone installed"
            return 0
        else
            log_error "Failed to make Docker Compose executable"
            return 1
        fi
    else
        log_error "Failed to download Docker Compose"
        return 1
    fi
}

# Verify Docker installation
verify_docker_installation() {
    log_info "Verifying Docker installation..."

    # Test Docker command
    local docker_test_cmd="docker --version"
    if safe_execute "$docker_test_cmd" 30 "Docker version check"; then
        local docker_version=$(docker --version 2>/dev/null)
        log_success "Docker verified: $docker_version"
    else
        log_error "Docker verification failed"
        return 1
    fi

    # Test Docker Compose
    local compose_test_cmd="docker compose version"
    if safe_execute "$compose_test_cmd" 30 "Docker Compose version check"; then
        local compose_version=$(docker compose version 2>/dev/null)
        log_success "Docker Compose verified: $compose_version"
    else
        log_warning "Docker Compose plugin not available, checking standalone..."
        if command -v docker-compose >/dev/null 2>&1; then
            local compose_version=$(docker-compose --version 2>/dev/null)
            log_success "Docker Compose standalone verified: $compose_version"
        else
            log_error "Docker Compose verification failed"
            return 1
        fi
    fi

    # Test Docker daemon
    local daemon_test_cmd="docker info"
    if safe_execute "$daemon_test_cmd" 30 "Docker daemon connectivity check"; then
        log_success "Docker daemon is accessible"
    else
        log_error "Docker daemon is not accessible"
        return 1
    fi

    # Run hello-world container test
    log_info "Running Docker hello-world test..."
    local hello_test_cmd="docker run --rm hello-world"
    if safe_execute "$hello_test_cmd" 120 "Docker hello-world test"; then
        log_success "Docker hello-world test passed"
        return 0
    else
        log_error "Docker hello-world test failed"
        return 1
    fi
}

# Clean up Docker test containers and images
cleanup_docker_test() {
    log_info "Cleaning up Docker test resources..."

    local cleanup_commands=(
        "docker system prune -f"
        "docker image prune -f"
    )

    for cmd in "${cleanup_commands[@]}"; do
        if safe_execute "$cmd" 60 "Docker cleanup: $cmd"; then
            log_debug "Cleanup command succeeded: $cmd"
        else
            log_warning "Cleanup command failed: $cmd"
        fi
    done

    log_success "Docker cleanup completed"
}

# Main Docker installation function
install_docker() {
    local skip_user_setup="${1:-false}"
    local install_compose_standalone="${2:-false}"

    log_info "Starting Docker installation process"

    # Initialize logging
    init_logging

    # Check requirements
    if ! check_docker_requirements; then
        log_error "System requirements not met"
        return 1
    fi

    # Check if Docker is already installed
    if check_docker_installed; then
        local docker_version=$(docker --version 2>/dev/null)
        log_warning "Docker is already installed: $docker_version"

        read -p "Do you want to reinstall Docker? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping Docker installation"

            # Still verify the installation
            if verify_docker_installation; then
                log_success "Existing Docker installation verified"
                return 0
            else
                log_error "Existing Docker installation has issues"
                return 1
            fi
        fi
    fi

    # Remove old Docker versions
    remove_old_docker

    # Install prerequisites
    if ! install_prerequisites; then
        log_error "Failed to install prerequisites"
        return 1
    fi

    # Setup Docker repository
    if ! setup_docker_repository; then
        log_error "Failed to setup Docker repository"
        return 1
    fi

    # Install Docker Engine
    if ! install_docker_engine; then
        log_error "Failed to install Docker Engine"
        return 1
    fi

    # Configure Docker service
    if ! configure_docker_service; then
        log_error "Failed to configure Docker service"
        return 1
    fi

    # Add user to docker group (unless skipped)
    if [[ "$skip_user_setup" != "true" ]]; then
        add_user_to_docker_group "$USER"
    fi

    # Install standalone Docker Compose if requested
    if [[ "$install_compose_standalone" == "true" ]]; then
        if ! check_docker_compose_installed; then
            install_docker_compose_standalone
        fi
    fi

    # Verify installation
    if ! verify_docker_installation; then
        log_error "Docker installation verification failed"
        return 1
    fi

    # Cleanup test resources
    cleanup_docker_test

    log_success "Docker installation completed successfully!"
    log_info "Note: You may need to log out and back in for group changes to take effect"

    return 0
}

# Uninstall Docker
uninstall_docker() {
    log_info "Uninstalling Docker..."

    # Stop and disable Docker service
    if isolate_systemctl_command "stop" "docker" 60; then
        log_info "Docker service stopped"
    fi

    if isolate_systemctl_command "disable" "docker" 30; then
        log_info "Docker service disabled"
    fi

    # Remove Docker packages
    local docker_packages=(
        "docker-ce"
        "docker-ce-cli"
        "containerd.io"
        "docker-buildx-plugin"
        "docker-compose-plugin"
        "docker"
        "docker-engine"
        "docker.io"
        "containerd"
        "runc"
    )

    local remove_cmd="apt-get purge -y"
    for package in "${docker_packages[@]}"; do
        remove_cmd+=" $package"
    done

    if isolated_sudo_command "$remove_cmd" 300 "Remove Docker packages"; then
        log_success "Docker packages removed"
    else
        log_error "Failed to remove all Docker packages"
    fi

    # Remove Docker data
    local cleanup_cmd="rm -rf /var/lib/docker /var/lib/containerd /etc/docker"
    if isolated_sudo_command "$cleanup_cmd" 60 "Remove Docker data"; then
        log_success "Docker data removed"
    fi

    # Remove repository and keys
    local repo_cleanup_cmd="rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg"
    isolated_sudo_command "$repo_cleanup_cmd" 30 "Remove Docker repository"

    # Update package lists
    local update_cmd="apt-get update"
    isolated_sudo_command "$update_cmd" 300 "Update package lists"

    log_success "Docker uninstallation completed"
}

# Interactive Docker setup
interactive_docker_setup() {
    echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         Docker Setup Manager         ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
    echo

    # Check current Docker status
    if check_docker_installed; then
        echo -e "${GREEN}✓${NC} Docker is currently installed"
        docker --version 2>/dev/null || echo "Version detection failed"
    else
        echo -e "${YELLOW}⚠${NC} Docker is not installed"
    fi

    if check_docker_compose_installed; then
        echo -e "${GREEN}✓${NC} Docker Compose is available"
    else
        echo -e "${YELLOW}⚠${NC} Docker Compose is not available"
    fi

    echo
    echo "Available options:"
    echo "1) Install Docker (recommended)"
    echo "2) Install Docker with standalone Compose"
    echo "3) Reinstall Docker"
    echo "4) Uninstall Docker"
    echo "5) Verify current installation"
    echo "6) Exit"
    echo

    while true; do
        read -p "Please select an option (1-6): " choice

        case $choice in
            1)
                echo -e "\n${GREEN}Installing Docker...${NC}"
                install_docker "false" "false"
                break
                ;;
            2)
                echo -e "\n${GREEN}Installing Docker with standalone Compose...${NC}"
                install_docker "false" "true"
                break
                ;;
            3)
                echo -e "\n${YELLOW}Reinstalling Docker...${NC}"
                read -p "This will remove existing Docker installation. Continue? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    uninstall_docker
                    install_docker "false" "false"
                fi
                break
                ;;
            4)
                echo -e "\n${RED}WARNING: This will remove Docker and all containers/images${NC}"
                read -p "Are you sure? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    uninstall_docker
                fi
                break
                ;;
            5)
                echo -e "\n${CYAN}Verifying Docker installation...${NC}"
                if check_docker_installed; then
                    verify_docker_installation
                else
                    log_error "Docker is not installed"
                fi
                echo
                ;;
            6)
                echo "Exiting Docker setup."
                break
                ;;
            *)
                echo -e "${RED}Invalid option. Please select 1-6.${NC}"
                ;;
        esac
    done
}

# Export functions for use by other modules
export -f install_docker
export -f uninstall_docker
export -f check_docker_installed
export -f check_docker_compose_installed
export -f verify_docker_installation
export -f interactive_docker_setup

# If script is run directly, start interactive mode
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Parse command line arguments
    case "${1:-interactive}" in
        "install")
            install_docker "false" "false"
            ;;
        "install-with-compose")
            install_docker "false" "true"
            ;;
        "uninstall")
            uninstall_docker
            ;;
        "verify")
            if check_docker_installed; then
                verify_docker_installation
            else
                log_error "Docker is not installed"
                exit 1
            fi
            ;;
        "interactive"|"")
            interactive_docker_setup
            ;;
        *)
            echo "Usage: $0 [install|install-with-compose|uninstall|verify|interactive]"
            echo "  install              - Install Docker with plugin Compose"
            echo "  install-with-compose - Install Docker with standalone Compose"
            echo "  uninstall           - Remove Docker completely"
            echo "  verify              - Verify existing installation"
            echo "  interactive         - Interactive setup menu (default)"
            exit 1
            ;;
    esac
fi