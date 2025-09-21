#!/bin/bash
# ======================================================================================
# VLESS+Reality VPN Management System - Docker Setup Module
# ======================================================================================
# This module handles Docker and Docker Compose installation and configuration.
# It provides functions for automated Docker installation and validation.
#
# Author: Claude Code
# Version: 1.0
# Last Modified: 2025-09-21
# ======================================================================================

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=modules/common_utils.sh
source "${SCRIPT_DIR}/common_utils.sh"

# Docker-specific constants
readonly DOCKER_REPO_URL="https://download.docker.com/linux"
readonly DOCKER_GPG_URL="https://download.docker.com/linux/ubuntu/gpg"
readonly DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)"
readonly MIN_DOCKER_VERSION="20.10.0"
readonly MIN_COMPOSE_VERSION="2.0.0"

# ======================================================================================
# DOCKER INSTALLATION FUNCTIONS
# ======================================================================================

#
# Check if Docker is installed and meets minimum version requirements
#
# Returns:
#   0 if Docker is properly installed
#   1 if Docker is not installed or version is insufficient
#
check_docker_installed() {
    log_info "Checking Docker installation status..."

    if ! command -v docker &> /dev/null; then
        log_warn "Docker is not installed"
        return 1
    fi

    local docker_version
    docker_version=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)

    if ! version_compare "${docker_version}" "${MIN_DOCKER_VERSION}"; then
        log_warn "Docker version ${docker_version} is below minimum required version ${MIN_DOCKER_VERSION}"
        return 1
    fi

    log_info "Docker version ${docker_version} is installed and meets requirements"
    return 0
}

#
# Check if Docker Compose is installed and meets minimum version requirements
#
# Returns:
#   0 if Docker Compose is properly installed
#   1 if Docker Compose is not installed or version is insufficient
#
check_docker_compose_installed() {
    log_info "Checking Docker Compose installation status..."

    # Check for Docker Compose v2 (plugin)
    if docker compose version &> /dev/null; then
        local compose_version
        compose_version=$(docker compose version --short)

        if version_compare "${compose_version}" "${MIN_COMPOSE_VERSION}"; then
            log_info "Docker Compose v2 (plugin) version ${compose_version} is installed"
            return 0
        else
            log_warn "Docker Compose version ${compose_version} is below minimum required version ${MIN_COMPOSE_VERSION}"
            return 1
        fi
    fi

    # Check for standalone Docker Compose v1
    if command -v docker-compose &> /dev/null; then
        local compose_version
        compose_version=$(docker-compose --version | grep -oP '\d+\.\d+\.\d+' | head -1)

        log_warn "Found Docker Compose v1 (${compose_version}). Recommend upgrading to v2"
        return 0
    fi

    log_warn "Docker Compose is not installed"
    return 1
}

#
# Install Docker from official repository
#
# Returns:
#   0 on successful installation
#   1 on installation failure
#
install_docker() {
    log_info "Installing Docker from official repository..."

    validate_root
    check_internet

    # Detect OS distribution
    local distro
    distro=$(get_os_info)

    case "${distro}" in
        "ubuntu"|"debian")
            install_docker_debian_ubuntu
            ;;
        "centos"|"rhel"|"fedora")
            install_docker_redhat
            ;;
        *)
            log_error "Unsupported distribution: ${distro}"
            return 1
            ;;
    esac

    # Start and enable Docker service
    systemctl enable docker
    systemctl start docker

    # Add current user to docker group if not root
    if [[ "${EUID}" -ne 0 ]] && [[ -n "${SUDO_USER:-}" ]]; then
        usermod -aG docker "${SUDO_USER}"
        log_info "Added user ${SUDO_USER} to docker group. Please log out and back in for changes to take effect."
    fi

    # Verify installation
    if check_docker_installed; then
        log_info "Docker installation completed successfully"
        return 0
    else
        log_error "Docker installation failed verification"
        return 1
    fi
}

#
# Install Docker on Debian/Ubuntu systems
#
install_docker_debian_ubuntu() {
    log_info "Installing Docker on Debian/Ubuntu system..."

    # Update package index
    apt-get update

    # Install prerequisites
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # Add Docker's official GPG key
    curl -fsSL "${DOCKER_GPG_URL}" | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    # Add Docker repository
    local distro_id
    distro_id=$(lsb_release -is | tr '[:upper:]' '[:lower:]')

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] ${DOCKER_REPO_URL}/${distro_id} $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Update package index again
    apt-get update

    # Install Docker Engine
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    log_info "Docker installation on Debian/Ubuntu completed"
}

#
# Install Docker on RedHat/CentOS/Fedora systems
#
install_docker_redhat() {
    log_info "Installing Docker on RedHat/CentOS/Fedora system..."

    # Install prerequisites
    if command -v dnf &> /dev/null; then
        dnf install -y dnf-plugins-core
        dnf config-manager --add-repo "${DOCKER_REPO_URL}/centos/docker-ce.repo"
        dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    else
        yum install -y yum-utils
        yum-config-manager --add-repo "${DOCKER_REPO_URL}/centos/docker-ce.repo"
        yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi

    log_info "Docker installation on RedHat/CentOS/Fedora completed"
}

#
# Install Docker Compose if not available as plugin
#
# Returns:
#   0 on successful installation
#   1 on installation failure
#
install_docker_compose() {
    log_info "Installing Docker Compose..."

    validate_root
    check_internet

    # Check if Docker Compose plugin is already available
    if docker compose version &> /dev/null; then
        log_info "Docker Compose plugin is already available"
        return 0
    fi

    # Download and install standalone Docker Compose
    local compose_dest="/usr/local/bin/docker-compose"

    log_info "Downloading Docker Compose from ${DOCKER_COMPOSE_URL}..."

    if curl -L "${DOCKER_COMPOSE_URL}" -o "${compose_dest}"; then
        chmod +x "${compose_dest}"

        # Create symlink for convenience
        ln -sf "${compose_dest}" /usr/bin/docker-compose 2>/dev/null || true

        log_info "Docker Compose installed successfully"
        return 0
    else
        log_error "Failed to download Docker Compose"
        return 1
    fi
}

#
# Configure Docker daemon with optimized settings
#
# Returns:
#   0 on successful configuration
#   1 on configuration failure
#
configure_docker_daemon() {
    log_info "Configuring Docker daemon..."

    validate_root

    local daemon_config="/etc/docker/daemon.json"

    # Backup existing configuration if it exists
    if [[ -f "${daemon_config}" ]]; then
        backup_file "${daemon_config}"
    fi

    # Create optimized daemon configuration
    cat > "${daemon_config}" << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "live-restore": true,
  "userland-proxy": false,
  "experimental": false,
  "ip-forward": true,
  "iptables": true,
  "bridge": "docker0"
}
EOF

    # Validate JSON configuration
    if ! python3 -m json.tool "${daemon_config}" > /dev/null 2>&1; then
        log_error "Invalid JSON in Docker daemon configuration"
        return 1
    fi

    log_info "Docker daemon configuration created successfully"
    return 0
}

#
# Setup and start Docker service
#
# Returns:
#   0 on successful setup
#   1 on setup failure
#
setup_docker_service() {
    log_info "Setting up Docker service..."

    validate_root

    # Reload systemd daemon
    systemctl daemon-reload

    # Enable Docker service
    if systemctl enable docker; then
        log_info "Docker service enabled"
    else
        log_error "Failed to enable Docker service"
        return 1
    fi

    # Start Docker service
    if systemctl start docker; then
        log_info "Docker service started"
    else
        log_error "Failed to start Docker service"
        return 1
    fi

    # Wait for Docker to be ready
    local max_attempts=30
    local attempt=0

    while [[ ${attempt} -lt ${max_attempts} ]]; do
        if docker info &> /dev/null; then
            log_info "Docker service is ready"
            return 0
        fi

        ((attempt++))
        log_info "Waiting for Docker service to be ready... (${attempt}/${max_attempts})"
        sleep 2
    done

    log_error "Docker service failed to become ready within ${max_attempts} attempts"
    return 1
}

#
# Validate Docker installation and functionality
#
# Returns:
#   0 if Docker is working properly
#   1 if Docker validation fails
#
validate_docker_installation() {
    log_info "Validating Docker installation..."

    # Check if Docker daemon is running
    if ! systemctl is-active docker &> /dev/null; then
        log_error "Docker service is not running"
        return 1
    fi

    # Check Docker info
    if ! docker info &> /dev/null; then
        log_error "Cannot connect to Docker daemon"
        return 1
    fi

    # Test Docker functionality with hello-world
    log_info "Testing Docker functionality..."
    if docker run --rm hello-world &> /dev/null; then
        log_info "Docker functionality test passed"
    else
        log_error "Docker functionality test failed"
        return 1
    fi

    # Check Docker Compose
    if docker compose version &> /dev/null; then
        local compose_version
        compose_version=$(docker compose version --short)
        log_info "Docker Compose plugin version ${compose_version} is working"
    elif command -v docker-compose &> /dev/null; then
        local compose_version
        compose_version=$(docker-compose --version | grep -oP '\d+\.\d+\.\d+' | head -1)
        log_info "Docker Compose standalone version ${compose_version} is working"
    else
        log_error "Docker Compose is not available"
        return 1
    fi

    log_info "Docker installation validation completed successfully"
    return 0
}

#
# Complete Docker setup process
#
# Returns:
#   0 on successful setup
#   1 on setup failure
#
setup_docker_complete() {
    log_info "Starting complete Docker setup process..."

    # Check if Docker is already installed and working
    if check_docker_installed && check_docker_compose_installed && validate_docker_installation; then
        log_info "Docker is already properly installed and configured"
        return 0
    fi

    # Install Docker if needed
    if ! check_docker_installed; then
        if ! install_docker; then
            log_error "Docker installation failed"
            return 1
        fi
    fi

    # Install Docker Compose if needed
    if ! check_docker_compose_installed; then
        if ! install_docker_compose; then
            log_error "Docker Compose installation failed"
            return 1
        fi
    fi

    # Configure Docker daemon
    if ! configure_docker_daemon; then
        log_error "Docker daemon configuration failed"
        return 1
    fi

    # Setup Docker service
    if ! setup_docker_service; then
        log_error "Docker service setup failed"
        return 1
    fi

    # Validate installation
    if ! validate_docker_installation; then
        log_error "Docker installation validation failed"
        return 1
    fi

    log_info "Complete Docker setup process finished successfully"
    return 0
}

#
# Compare two version strings
#
# Arguments:
#   $1 - Version to compare
#   $2 - Minimum required version
#
# Returns:
#   0 if version is >= minimum required
#   1 if version is < minimum required
#
version_compare() {
    local version="$1"
    local min_version="$2"

    # Use sort -V for version comparison
    if [[ "$(printf '%s\n' "${min_version}" "${version}" | sort -V | head -n1)" == "${min_version}" ]]; then
        return 0
    else
        return 1
    fi
}

# ======================================================================================
# MAIN EXECUTION
# ======================================================================================

# Only execute main function if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main() {
        log_info "Docker setup module executed directly"

        case "${1:-help}" in
            "install")
                setup_docker_complete
                ;;
            "check")
                if check_docker_installed && check_docker_compose_installed; then
                    echo "Docker is properly installed"
                    exit 0
                else
                    echo "Docker is not properly installed"
                    exit 1
                fi
                ;;
            "validate")
                validate_docker_installation
                ;;
            "help"|*)
                echo "Usage: $0 {install|check|validate|help}"
                echo "  install  - Install and configure Docker"
                echo "  check    - Check if Docker is installed"
                echo "  validate - Validate Docker installation"
                echo "  help     - Show this help message"
                exit 0
                ;;
        esac
    }

    main "$@"
fi