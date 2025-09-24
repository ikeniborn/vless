#!/bin/bash

# VLESS+Reality VPN Management System - Docker Setup Module
# Version: 1.0.0
# Description: Docker and Docker Compose installation and configuration
#
# This module provides:
# - Docker Engine installation via official repository
# - Docker Compose installation (latest version)
# - User permissions configuration
# - Docker daemon startup verification
# - Version compatibility checks

set -euo pipefail

# Import common utilities
# Check if SCRIPT_DIR is already defined (e.g., by parent script)
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
source "${SCRIPT_DIR}/common_utils.sh"

# Docker configuration
readonly DOCKER_GPG_URL="https://download.docker.com/linux/ubuntu/gpg"
readonly DOCKER_REPO_URL="https://download.docker.com/linux"
readonly DOCKER_COMPOSE_RELEASES_URL="https://api.github.com/repos/docker/compose/releases/latest"
readonly MIN_DOCKER_VERSION="20.10.0"
readonly MIN_COMPOSE_VERSION="2.0.0"

# Check if Docker is installed and get version
get_docker_version() {
    if command_exists docker; then
        docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown"
    else
        echo "not_installed"
    fi
}

# Check if Docker Compose is installed and get version
get_docker_compose_version() {
    if command_exists docker-compose; then
        docker-compose --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown"
    elif docker compose version >/dev/null 2>&1; then
        docker compose version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown"
    else
        echo "not_installed"
    fi
}

# Compare version strings
version_compare() {
    local version1="$1"
    local version2="$2"

    if [[ "$version1" == "$version2" ]]; then
        return 0
    fi

    local IFS=.
    local i ver1=($version1) ver2=($version2)

    # Fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
        ver1[i]=0
    done

    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 2
        fi
    done
    return 0
}

# Check Docker version compatibility
check_docker_version_compatibility() {
    local current_version
    current_version=$(get_docker_version)

    if [[ "$current_version" == "not_installed" ]]; then
        log_info "Docker is not installed"
        return 1
    elif [[ "$current_version" == "unknown" ]]; then
        log_warn "Unable to determine Docker version"
        return 1
    fi

    version_compare "$current_version" "$MIN_DOCKER_VERSION"
    local result=$?

    case $result in
        0|1)
            log_success "Docker version $current_version is compatible (minimum: $MIN_DOCKER_VERSION)"
            return 0
            ;;
        2)
            log_error "Docker version $current_version is too old (minimum: $MIN_DOCKER_VERSION)"
            return 1
            ;;
    esac
}

# Check Docker Compose version compatibility
check_docker_compose_version_compatibility() {
    local current_version
    current_version=$(get_docker_compose_version)

    if [[ "$current_version" == "not_installed" ]]; then
        log_info "Docker Compose is not installed"
        return 1
    elif [[ "$current_version" == "unknown" ]]; then
        log_warn "Unable to determine Docker Compose version"
        return 1
    fi

    version_compare "$current_version" "$MIN_COMPOSE_VERSION"
    local result=$?

    case $result in
        0|1)
            log_success "Docker Compose version $current_version is compatible (minimum: $MIN_COMPOSE_VERSION)"
            return 0
            ;;
        2)
            log_error "Docker Compose version $current_version is too old (minimum: $MIN_COMPOSE_VERSION)"
            return 1
            ;;
    esac
}

# Remove old Docker installations
remove_old_docker() {
    log_info "Removing old Docker installations..."

    local old_packages=(
        "docker"
        "docker-engine"
        "docker.io"
        "containerd"
        "runc"
        "docker-compose"
    )

    local package
    for package in "${old_packages[@]}"; do
        if dpkg -l | grep -q "^ii.*${package}"; then
            log_info "Removing old package: $package"
            apt-get remove -y -qq "$package" 2>/dev/null || true
        fi
    done

    # Remove old Docker data (optional, with confirmation)
    local old_docker_dirs=(
        "/var/lib/docker"
        "/var/lib/containerd"
    )

    local dir
    for dir in "${old_docker_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log_warn "Old Docker data directory exists: $dir"
            log_warn "Consider backing up or removing this directory manually"
        fi
    done

    log_success "Old Docker installations removed"
}

# Install Docker repository
install_docker_repository() {
    local distribution
    local codename

    log_info "Installing Docker repository..."

    distribution=$(detect_distribution)
    codename=$(lsb_release -cs)

    # Install required packages for repository management
    local required_packages=(
        "ca-certificates"
        "curl"
        "gnupg"
        "lsb-release"
    )

    local package
    for package in "${required_packages[@]}"; do
        install_package_if_missing "$package"
    done

    # Create Docker keyring directory
    create_directory "/etc/apt/keyrings" "755"

    # Download and install Docker GPG key
    log_debug "Downloading Docker GPG key..."
    if ! curl -fsSL "$DOCKER_GPG_URL" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
        log_error "Failed to download Docker GPG key"
        return 1
    fi

    chmod 644 /etc/apt/keyrings/docker.gpg

    # Add Docker repository
    local repo_url
    case "$distribution" in
        "ubuntu")
            repo_url="$DOCKER_REPO_URL/ubuntu"
            ;;
        "debian")
            repo_url="$DOCKER_REPO_URL/debian"
            ;;
        *)
            log_error "Unsupported distribution for Docker repository: $distribution"
            return 1
            ;;
    esac

    local architecture
    architecture=$(dpkg --print-architecture)

    echo "deb [arch=${architecture} signed-by=/etc/apt/keyrings/docker.gpg] ${repo_url} ${codename} stable" \
        > /etc/apt/sources.list.d/docker.list

    # Update package repositories with time sync support
    if ! safe_apt_update; then
        log_error "Failed to update package repositories after adding Docker repository"
        return 1
    fi

    log_success "Docker repository installed successfully"
}

# Install Docker Engine
install_docker_engine() {
    log_info "Installing Docker Engine..."

    # Install Docker packages
    local docker_packages=(
        "docker-ce"
        "docker-ce-cli"
        "containerd.io"
        "docker-buildx-plugin"
        "docker-compose-plugin"
    )

    if ! apt-get install -y -qq "${docker_packages[@]}"; then
        log_error "Failed to install Docker Engine"
        return 1
    fi

    log_success "Docker Engine installed successfully"
}

# Install Docker Compose (standalone)
install_docker_compose_standalone() {
    log_info "Installing Docker Compose standalone..."

    local architecture
    local compose_url
    local latest_version

    architecture=$(detect_architecture)

    # Map architecture names for Docker Compose
    case "$architecture" in
        "amd64") architecture="x86_64" ;;
        "arm64") architecture="aarch64" ;;
        "armhf") architecture="armv7" ;;
    esac

    # Get latest version from GitHub API
    if ! latest_version=$(curl -s "$DOCKER_COMPOSE_RELEASES_URL" | jq -r '.tag_name' 2>/dev/null); then
        log_error "Failed to get Docker Compose latest version"
        return 1
    fi

    compose_url="https://github.com/docker/compose/releases/download/${latest_version}/docker-compose-linux-${architecture}"

    # Download Docker Compose
    log_debug "Downloading Docker Compose $latest_version for $architecture..."
    if ! curl -L "$compose_url" -o /usr/local/bin/docker-compose; then
        log_error "Failed to download Docker Compose"
        return 1
    fi

    # Make executable
    chmod +x /usr/local/bin/docker-compose

    # Create symlink for global access
    if [[ ! -L /usr/bin/docker-compose ]]; then
        ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    fi

    log_success "Docker Compose $latest_version installed successfully"
}

# Configure Docker daemon
configure_docker_daemon() {
    log_info "Configuring Docker daemon..."

    local docker_config_dir="/etc/docker"
    local docker_config_file="$docker_config_dir/daemon.json"

    create_directory "$docker_config_dir" "755"

    # Backup existing configuration
    if [[ -f "$docker_config_file" ]]; then
        backup_file "$docker_config_file"
    fi

    # Create Docker daemon configuration
    cat > "$docker_config_file" << 'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "userland-proxy": false,
    "experimental": false,
    "live-restore": true,
    "default-address-pools": [
        {
            "base": "172.17.0.0/12",
            "size": 24
        }
    ]
}
EOF

    log_success "Docker daemon configured"
}

# Start and enable Docker service
start_docker_service() {
    log_info "Starting Docker service..."

    # Enable Docker service to start on boot
    if ! isolate_systemctl_command "enable" "docker" 30; then
        log_error "Failed to enable Docker service"
        return 1
    fi

    # Start Docker service
    if ! isolate_systemctl_command "start" "docker" 30; then
        log_error "Failed to start Docker service"
        return 1
    fi

    # Wait for Docker daemon to be ready
    if ! wait_for_condition "docker info >/dev/null 2>&1" 30 2; then
        log_error "Docker daemon failed to start properly"
        return 1
    fi

    log_success "Docker service started successfully"
}

# Configure user permissions
configure_user_permissions() {
    local target_user="${1:-$SUDO_USER}"

    if [[ -z "$target_user" ]]; then
        log_warn "No target user specified for Docker permissions"
        return 0
    fi

    log_info "Configuring Docker permissions for user: $target_user"

    # Add user to docker group
    if ! usermod -aG docker "$target_user"; then
        log_error "Failed to add user $target_user to docker group"
        return 1
    fi

    log_success "User $target_user added to docker group"
    log_warn "User needs to log out and log back in for group changes to take effect"
}

# Verify Docker installation
verify_docker_installation() {
    log_info "Verifying Docker installation..."

    # Check Docker version
    local docker_version
    docker_version=$(get_docker_version)
    if [[ "$docker_version" == "not_installed" || "$docker_version" == "unknown" ]]; then
        log_error "Docker verification failed - version check"
        return 1
    fi

    # Check Docker daemon status
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker verification failed - daemon not running"
        return 1
    fi

    # Check Docker Compose version
    local compose_version
    compose_version=$(get_docker_compose_version)
    if [[ "$compose_version" == "not_installed" || "$compose_version" == "unknown" ]]; then
        log_error "Docker Compose verification failed - version check"
        return 1
    fi

    # Test Docker functionality with hello-world
    log_debug "Testing Docker functionality..."
    if docker run --rm hello-world >/dev/null 2>&1; then
        log_success "Docker functionality test passed"
    else
        log_error "Docker functionality test failed"
        return 1
    fi

    # Clean up test image
    docker rmi hello-world >/dev/null 2>&1 || true

    log_success "Docker installation verified successfully"
    log_info "Docker version: $docker_version"
    log_info "Docker Compose version: $compose_version"
}

# Get Docker system information
get_docker_info() {
    if ! command_exists docker || ! docker info >/dev/null 2>&1; then
        echo "Docker is not installed or not running"
        return 1
    fi

    local docker_version
    local compose_version
    local containers_running
    local containers_total
    local images_count

    docker_version=$(get_docker_version)
    compose_version=$(get_docker_compose_version)
    containers_running=$(docker ps -q | wc -l)
    containers_total=$(docker ps -a -q | wc -l)
    images_count=$(docker images -q | wc -l)

    cat << EOF

=== Docker System Information ===
Docker Version: $docker_version
Docker Compose Version: $compose_version
Running Containers: $containers_running
Total Containers: $containers_total
Total Images: $images_count

EOF

    # Show running containers if any
    if [[ $containers_running -gt 0 ]]; then
        echo "=== Running Containers ==="
        docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
        echo
    fi
}

# Uninstall Docker (if needed)
uninstall_docker() {
    log_warn "Uninstalling Docker..."

    # Stop Docker service
    isolate_systemctl_command "stop" "docker" 30 || true

    # Remove Docker packages
    local docker_packages=(
        "docker-ce"
        "docker-ce-cli"
        "containerd.io"
        "docker-buildx-plugin"
        "docker-compose-plugin"
    )

    local package
    for package in "${docker_packages[@]}"; do
        if dpkg -l | grep -q "^ii.*${package}"; then
            apt-get remove -y -qq "$package" 2>/dev/null || true
        fi
    done

    # Remove Docker Compose standalone
    rm -f /usr/local/bin/docker-compose /usr/bin/docker-compose

    # Remove Docker repository
    rm -f /etc/apt/sources.list.d/docker.list
    rm -f /etc/apt/keyrings/docker.gpg

    # Update package repositories with time sync support
    safe_apt_update || true

    log_warn "Docker uninstalled (Docker data preserved)"
    log_warn "To remove all Docker data, manually delete /var/lib/docker"
}

# Main Docker installation function
install_docker_complete() {
    local configure_user="${1:-true}"
    local target_user="${2:-$SUDO_USER}"

    log_info "Starting complete Docker installation..."

    # Ensure we have root privileges
    require_root

    # Check network connectivity
    if ! check_network_connectivity; then
        die "Network connectivity required for Docker installation" 10
    fi

    # Check if Docker is already installed and compatible
    if check_docker_version_compatibility && check_docker_compose_version_compatibility; then
        log_success "Compatible Docker installation already exists"
        get_docker_info
        return 0
    fi

    # Remove old Docker installations
    remove_old_docker

    # Install Docker repository
    if ! install_docker_repository; then
        die "Failed to install Docker repository" 11
    fi

    # Install Docker Engine
    if ! install_docker_engine; then
        die "Failed to install Docker Engine" 12
    fi

    # Install Docker Compose standalone (as backup)
    install_docker_compose_standalone || log_warn "Failed to install Docker Compose standalone"

    # Configure Docker daemon
    configure_docker_daemon

    # Start Docker service
    if ! start_docker_service; then
        die "Failed to start Docker service" 13
    fi

    # Configure user permissions
    if [[ "$configure_user" == "true" && -n "$target_user" ]]; then
        configure_user_permissions "$target_user"
    fi

    # Verify installation
    if ! verify_docker_installation; then
        die "Docker installation verification failed" 14
    fi

    log_success "Docker installation completed successfully"
    get_docker_info
}

# Display help information
show_help() {
    cat << EOF
VLESS+Reality VPN Docker Setup Module

Usage: $0 [OPTIONS]

Options:
    --install            Install Docker and Docker Compose
    --verify             Verify existing Docker installation
    --uninstall          Uninstall Docker (preserves data)
    --info               Show Docker system information
    --no-user-config     Skip user permission configuration
    --user USERNAME      Configure permissions for specific user
    --help               Show this help message

Examples:
    $0 --install                    # Install Docker completely
    $0 --verify                    # Verify existing installation
    $0 --install --user myuser     # Install and configure for specific user
    $0 --info                      # Show Docker information
    $0 --uninstall                 # Uninstall Docker

EOF
}

# Main execution
main() {
    local action=""
    local configure_user="true"
    local target_user="$SUDO_USER"

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --install)
                action="install"
                shift
                ;;
            --verify)
                action="verify"
                shift
                ;;
            --uninstall)
                action="uninstall"
                shift
                ;;
            --info)
                action="info"
                shift
                ;;
            --no-user-config)
                configure_user="false"
                shift
                ;;
            --user)
                target_user="$2"
                shift 2
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

    # Default action is install
    if [[ -z "$action" ]]; then
        action="install"
    fi

    # Execute requested action
    case "$action" in
        "install")
            install_docker_complete "$configure_user" "$target_user"
            ;;
        "verify")
            verify_docker_installation
            ;;
        "uninstall")
            uninstall_docker
            ;;
        "info")
            get_docker_info
            ;;
        *)
            log_error "Unknown action: $action"
            show_help
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi