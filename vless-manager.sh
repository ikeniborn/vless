#!/bin/bash
set -euo pipefail

# VLESS+Reality VPN Service Management Script
# Version: 1.0.0
# Description: Complete management solution for VLESS+Reality VPN service
# Author: VLESS Management Team
# License: MIT

#######################################################################################
# SCRIPT CONSTANTS AND CONFIGURATION
#######################################################################################

readonly SCRIPT_NAME="vless-manager"
readonly SCRIPT_VERSION="1.0.0"
readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MIN_RAM_MB=512
readonly MIN_DISK_GB=1
readonly REQUIRED_PORT=443

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

#######################################################################################
# CORE UTILITY FUNCTIONS
#######################################################################################

# Logging function with colors and timestamps
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} ${timestamp} - $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} ${timestamp} - $message"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} ${timestamp} - $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${timestamp} - $message" >&2
            ;;
    esac
}

# Colored echo function
color_echo() {
    local color="$1"
    local message="$2"

    case "$color" in
        "red")    echo -e "${RED}$message${NC}" ;;
        "green")  echo -e "${GREEN}$message${NC}" ;;
        "yellow") echo -e "${YELLOW}$message${NC}" ;;
        "blue")   echo -e "${BLUE}$message${NC}" ;;
        "white")  echo -e "${WHITE}$message${NC}" ;;
        *)        echo "$message" ;;
    esac
}

# Error handling function
handle_error() {
    local exit_code=$?
    local line_number=$1
    log_message "ERROR" "Script failed at line $line_number with exit code $exit_code"
    exit $exit_code
}

# Set up error trap
trap 'handle_error $LINENO' ERR

#######################################################################################
# SYSTEM REQUIREMENTS VERIFICATION FUNCTIONS
#######################################################################################

# Check for root privileges
check_root() {
    log_message "INFO" "Checking root privileges..."

    if [[ $EUID -ne 0 ]]; then
        if ! command -v sudo >/dev/null 2>&1; then
            log_message "ERROR" "This script requires root privileges or sudo access"
            return 1
        fi

        if ! sudo -n true 2>/dev/null; then
            log_message "ERROR" "Please run with sudo or as root"
            return 1
        fi
    fi

    log_message "SUCCESS" "Root privileges verified"
    return 0
}

# Check OS compatibility
check_os() {
    log_message "INFO" "Checking OS compatibility..."

    if [[ ! -f /etc/os-release ]]; then
        log_message "ERROR" "Cannot determine OS version"
        return 1
    fi

    source /etc/os-release

    case "$ID" in
        "ubuntu")
            if [[ "${VERSION_ID%.*}" -lt 20 ]]; then
                log_message "ERROR" "Ubuntu 20.04 or higher is required (current: $VERSION_ID)"
                return 1
            fi
            ;;
        "debian")
            if [[ "${VERSION_ID%.*}" -lt 11 ]]; then
                log_message "ERROR" "Debian 11 or higher is required (current: $VERSION_ID)"
                return 1
            fi
            ;;
        *)
            log_message "ERROR" "Unsupported OS: $ID. Only Ubuntu 20.04+ and Debian 11+ are supported"
            return 1
            ;;
    esac

    log_message "SUCCESS" "OS compatibility verified: $PRETTY_NAME"
    return 0
}

# Check system architecture
check_architecture() {
    log_message "INFO" "Checking system architecture..."

    local arch=$(uname -m)

    case "$arch" in
        "x86_64"|"amd64")
            log_message "SUCCESS" "Architecture verified: x86_64"
            ;;
        "aarch64"|"arm64")
            log_message "SUCCESS" "Architecture verified: ARM64"
            ;;
        *)
            log_message "ERROR" "Unsupported architecture: $arch. Only x86_64 and ARM64 are supported"
            return 1
            ;;
    esac

    return 0
}

# Check system resources
check_resources() {
    log_message "INFO" "Checking system resources..."

    # Check RAM
    local ram_mb=$(free -m | awk '/^Mem:/ {print $2}')
    if [[ $ram_mb -lt $MIN_RAM_MB ]]; then
        log_message "ERROR" "Insufficient RAM: ${ram_mb}MB available, ${MIN_RAM_MB}MB required"
        return 1
    fi
    log_message "SUCCESS" "RAM check passed: ${ram_mb}MB available"

    # Check disk space
    local disk_gb=$(df -BG "$PROJECT_ROOT" | awk 'NR==2 {print int($4)}')
    if [[ $disk_gb -lt $MIN_DISK_GB ]]; then
        log_message "ERROR" "Insufficient disk space: ${disk_gb}GB available, ${MIN_DISK_GB}GB required"
        return 1
    fi
    log_message "SUCCESS" "Disk space check passed: ${disk_gb}GB available"

    return 0
}

# Check port availability
check_port() {
    log_message "INFO" "Checking port $REQUIRED_PORT availability..."

    if command -v netstat >/dev/null 2>&1; then
        if netstat -tuln | grep -q ":$REQUIRED_PORT "; then
            log_message "ERROR" "Port $REQUIRED_PORT is already in use"
            return 1
        fi
    elif command -v ss >/dev/null 2>&1; then
        if ss -tuln | grep -q ":$REQUIRED_PORT "; then
            log_message "ERROR" "Port $REQUIRED_PORT is already in use"
            return 1
        fi
    else
        log_message "WARNING" "Cannot check port availability (netstat/ss not found)"
    fi

    log_message "SUCCESS" "Port $REQUIRED_PORT is available"
    return 0
}

# Run all system checks
check_system_requirements() {
    log_message "INFO" "Starting system requirements verification..."

    check_root || return 1
    check_os || return 1
    check_architecture || return 1
    check_resources || return 1
    check_port || return 1

    log_message "SUCCESS" "All system requirements met"
    return 0
}

#######################################################################################
# DOCKER INSTALLATION FUNCTIONS
#######################################################################################

# Install Docker
install_docker() {
    log_message "INFO" "Starting Docker installation..."

    # Check if Docker is already installed
    if command -v docker >/dev/null 2>&1; then
        log_message "INFO" "Docker is already installed"
        local docker_version=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
        log_message "INFO" "Docker version: $docker_version"

        # Check if Docker daemon is running
        if ! docker info >/dev/null 2>&1; then
            log_message "INFO" "Starting Docker daemon..."
            sudo systemctl start docker
            sudo systemctl enable docker
        fi

        log_message "SUCCESS" "Docker is ready"
        return 0
    fi

    log_message "INFO" "Installing Docker..."

    # Update package index
    sudo apt-get update -qq

    # Install prerequisites
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/$(lsb_release -is | tr '[:upper:]' '[:lower:]')/gpg | \
        sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    # Set up stable repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
        https://download.docker.com/linux/$(lsb_release -is | tr '[:upper:]' '[:lower:]') \
        $(lsb_release -cs) stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Update package index with Docker repository
    sudo apt-get update -qq

    # Install Docker Engine
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io

    # Start and enable Docker service
    sudo systemctl start docker
    sudo systemctl enable docker

    # Add current user to docker group (if not root)
    if [[ $EUID -ne 0 ]]; then
        sudo usermod -aG docker "$USER"
        log_message "WARNING" "You may need to log out and back in for Docker group membership to take effect"
    fi

    # Verify installation
    if docker run --rm hello-world >/dev/null 2>&1; then
        log_message "SUCCESS" "Docker installed and verified successfully"
        return 0
    else
        log_message "ERROR" "Docker installation verification failed"
        return 1
    fi
}

# Install Docker Compose
install_docker_compose() {
    log_message "INFO" "Starting Docker Compose installation..."

    # Check if Docker Compose is already installed
    if docker compose version >/dev/null 2>&1; then
        log_message "INFO" "Docker Compose is already installed"
        local compose_version=$(docker compose version --short)
        log_message "INFO" "Docker Compose version: $compose_version"
        log_message "SUCCESS" "Docker Compose is ready"
        return 0
    fi

    log_message "INFO" "Installing Docker Compose plugin..."

    # Install Docker Compose plugin
    sudo apt-get update -qq
    sudo apt-get install -y docker-compose-plugin

    # Verify installation
    if docker compose version >/dev/null 2>&1; then
        local compose_version=$(docker compose version --short)
        log_message "SUCCESS" "Docker Compose installed successfully: $compose_version"
        return 0
    else
        log_message "ERROR" "Docker Compose installation verification failed"
        return 1
    fi
}

#######################################################################################
# PROJECT STRUCTURE FUNCTIONS
#######################################################################################

# Create project directory structure
create_directories() {
    log_message "INFO" "Creating project directory structure..."

    local directories=(
        "$PROJECT_ROOT/config"
        "$PROJECT_ROOT/config/users"
        "$PROJECT_ROOT/data"
        "$PROJECT_ROOT/data/keys"
        "$PROJECT_ROOT/logs"
    )

    # Create directories
    for dir in "${directories[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_message "INFO" "Created directory: $dir"
        else
            log_message "INFO" "Directory already exists: $dir"
        fi
    done

    # Set proper permissions
    chmod 700 "$PROJECT_ROOT/config"
    chmod 700 "$PROJECT_ROOT/config/users"
    chmod 700 "$PROJECT_ROOT/data"
    chmod 700 "$PROJECT_ROOT/data/keys"
    chmod 755 "$PROJECT_ROOT/logs"

    # Create users database file if it doesn't exist
    local users_db="$PROJECT_ROOT/data/users.db"
    if [[ ! -f "$users_db" ]]; then
        touch "$users_db"
        chmod 600 "$users_db"
        log_message "INFO" "Created users database: $users_db"
    fi

    # Create log file if it doesn't exist
    local log_file="$PROJECT_ROOT/logs/xray.log"
    if [[ ! -f "$log_file" ]]; then
        touch "$log_file"
        chmod 644 "$log_file"
        log_message "INFO" "Created log file: $log_file"
    fi

    log_message "SUCCESS" "Directory structure created successfully"
    return 0
}

#######################################################################################
# ENVIRONMENT CONFIGURATION FUNCTIONS
#######################################################################################

# Create environment configuration
create_env_file() {
    log_message "INFO" "Creating environment configuration..."

    local env_file="$PROJECT_ROOT/.env"

    # Detect server IP
    local server_ip
    server_ip=$(curl -s https://ipv4.icanhazip.com/ 2>/dev/null || \
                curl -s https://api.ipify.org/ 2>/dev/null || \
                curl -s https://ifconfig.me/ 2>/dev/null || \
                echo "127.0.0.1")

    # Create .env file
    cat > "$env_file" << EOF
# VLESS+Reality VPN Service Configuration
# Generated on $(date '+%Y-%m-%d %H:%M:%S')

# Project settings
PROJECT_PATH=$PROJECT_ROOT
SCRIPT_VERSION=$SCRIPT_VERSION

# Server configuration
SERVER_IP=$server_ip
XRAY_PORT=443
REALITY_DEST=speed.cloudflare.com:443
REALITY_SERVER_NAMES=speed.cloudflare.com

# Logging
LOG_LEVEL=warning
LOG_FILE=$PROJECT_ROOT/logs/xray.log

# Database
USERS_DB=$PROJECT_ROOT/data/users.db
KEYS_DIR=$PROJECT_ROOT/data/keys

# Docker configuration
DOCKER_IMAGE=teddysun/xray:latest
COMPOSE_PROJECT_NAME=vless-service
EOF

    chmod 600 "$env_file"
    log_message "SUCCESS" "Environment configuration created: $env_file"
    log_message "INFO" "Detected server IP: $server_ip"

    return 0
}

#######################################################################################
# CONFIGURATION GENERATION FUNCTIONS
#######################################################################################

# Generate X25519 key pair for Reality transport
generate_keys() {
    log_message "INFO" "Generating X25519 key pair..."

    local private_key_file="$PROJECT_ROOT/data/keys/private.key"
    local public_key_file="$PROJECT_ROOT/data/keys/public.key"

    # Check if keys already exist
    if [[ -f "$private_key_file" ]] && [[ -f "$public_key_file" ]]; then
        log_message "INFO" "X25519 keys already exist, skipping generation"
        return 0
    fi

    # Check if Docker is available
    if ! command -v docker >/dev/null 2>&1; then
        log_message "ERROR" "Docker is required for key generation but not found"
        return 1
    fi

    # Check if Docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        log_message "ERROR" "Docker daemon is not running"
        return 1
    fi

    log_message "INFO" "Pulling Xray Docker image for key generation..."
    if ! docker pull teddysun/xray:latest >/dev/null 2>&1; then
        log_message "WARNING" "Failed to pull latest image, attempting to use existing image"
    fi

    # Generate X25519 key pair using Docker
    log_message "INFO" "Generating key pair with Xray..."
    local key_output
    key_output=$(docker run --rm teddysun/xray:latest x25519 2>/dev/null)

    if [[ $? -ne 0 ]] || [[ -z "$key_output" ]]; then
        log_message "ERROR" "Failed to generate X25519 key pair"
        return 1
    fi

    # Parse private and public keys from output
    local private_key
    local public_key

    private_key=$(echo "$key_output" | grep "Private key:" | awk '{print $3}' | tr -d '\r\n')
    public_key=$(echo "$key_output" | grep "Public key:" | awk '{print $3}' | tr -d '\r\n')

    if [[ -z "$private_key" ]] || [[ -z "$public_key" ]]; then
        log_message "ERROR" "Failed to parse generated keys from output"
        return 1
    fi

    # Validate key format (should be base64-like strings)
    if [[ ! $private_key =~ ^[A-Za-z0-9+/]+=*$ ]] || [[ ! $public_key =~ ^[A-Za-z0-9+/]+=*$ ]]; then
        log_message "ERROR" "Generated keys have invalid format"
        return 1
    fi

    # Save keys to files
    echo "$private_key" > "$private_key_file"
    echo "$public_key" > "$public_key_file"

    # Set secure permissions
    chmod 600 "$private_key_file"
    chmod 600 "$public_key_file"

    log_message "SUCCESS" "X25519 key pair generated and stored securely"
    log_message "INFO" "Private key saved to: $private_key_file"
    log_message "INFO" "Public key saved to: $public_key_file"

    return 0
}

# Generate UUID v4 for user identification
generate_uuid() {
    local uuid

    # Method 1: Use uuidgen command if available
    if command -v uuidgen >/dev/null 2>&1; then
        uuid=$(uuidgen)
        if [[ $? -eq 0 ]] && [[ -n "$uuid" ]]; then
            echo "$uuid"
            return 0
        fi
    fi

    # Method 2: Use /proc/sys/kernel/random/uuid if available
    if [[ -r "/proc/sys/kernel/random/uuid" ]]; then
        uuid=$(cat /proc/sys/kernel/random/uuid)
        if [[ $? -eq 0 ]] && [[ -n "$uuid" ]]; then
            echo "$uuid"
            return 0
        fi
    fi

    # Method 3: Generate UUID manually using /dev/urandom
    if [[ -r "/dev/urandom" ]]; then
        # Generate 16 random bytes and format as UUID v4
        local hex_string
        hex_string=$(dd if=/dev/urandom bs=16 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')

        if [[ ${#hex_string} -eq 32 ]]; then
            # Format as UUID v4: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
            # Set version (4) and variant bits
            local uuid_formatted
            uuid_formatted="${hex_string:0:8}-${hex_string:8:4}-4${hex_string:13:3}-$(printf "%x" $(( 0x${hex_string:16:1} & 0x3 | 0x8 )))${hex_string:17:3}-${hex_string:20:12}"
            echo "$uuid_formatted"
            return 0
        fi
    fi

    log_message "ERROR" "Failed to generate UUID using all available methods"
    return 1
}

# Generate hexadecimal shortId for Reality transport
generate_short_id() {
    local length=${1:-8}

    # Validate length parameter
    if ! [[ "$length" =~ ^[0-9]+$ ]] || [[ $length -lt 2 ]] || [[ $length -gt 16 ]] || [[ $((length % 2)) -ne 0 ]]; then
        log_message "WARNING" "Invalid shortId length: $length. Using default length 8"
        length=8
    fi

    # Generate random bytes and convert to hexadecimal
    if [[ -r "/dev/urandom" ]]; then
        local hex_string
        hex_string=$(dd if=/dev/urandom bs=$((length / 2)) count=1 2>/dev/null | od -An -tx1 | tr -d ' \n' | head -c $length)

        if [[ ${#hex_string} -eq $length ]]; then
            # Ensure lowercase
            echo "$hex_string" | tr '[:upper:]' '[:lower:]'
            return 0
        fi
    fi

    log_message "ERROR" "Failed to generate shortId"
    return 1
}

# Create Xray server configuration
create_server_config() {
    log_message "INFO" "Creating Xray server configuration..."

    local config_file="$PROJECT_ROOT/config/server.json"
    local env_file="$PROJECT_ROOT/.env"
    local private_key_file="$PROJECT_ROOT/data/keys/private.key"

    # Check if configuration already exists
    if [[ -f "$config_file" ]]; then
        log_message "INFO" "Server configuration already exists, regenerating..."
    fi

    # Check if environment file exists
    if [[ ! -f "$env_file" ]]; then
        log_message "ERROR" "Environment file not found: $env_file"
        return 1
    fi

    # Source environment variables
    source "$env_file"

    # Check if private key exists
    if [[ ! -f "$private_key_file" ]]; then
        log_message "ERROR" "Private key file not found: $private_key_file"
        log_message "ERROR" "Please run generate_keys() first"
        return 1
    fi

    # Read private key
    local private_key
    private_key=$(cat "$private_key_file")
    if [[ -z "$private_key" ]]; then
        log_message "ERROR" "Private key is empty"
        return 1
    fi

    # Generate admin UUID
    local admin_uuid
    admin_uuid=$(generate_uuid)
    if [[ $? -ne 0 ]] || [[ -z "$admin_uuid" ]]; then
        log_message "ERROR" "Failed to generate admin UUID"
        return 1
    fi

    # Generate shortIds array
    local short_id_1 short_id_2
    short_id_1=$(generate_short_id 8)
    short_id_2=$(generate_short_id 16)

    if [[ $? -ne 0 ]] || [[ -z "$short_id_1" ]] || [[ -z "$short_id_2" ]]; then
        log_message "ERROR" "Failed to generate shortIds"
        return 1
    fi

    # Create server configuration JSON
    cat > "$config_file" << EOF
{
  "log": {
    "level": "${LOG_LEVEL:-warning}",
    "output": "${LOG_FILE:-/app/logs/xray.log}"
  },
  "inbounds": [
    {
      "tag": "vless-reality",
      "port": ${XRAY_PORT:-443},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$admin_uuid",
            "email": "admin@vless-service",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${REALITY_DEST:-speed.cloudflare.com:443}",
          "serverNames": [
            "${REALITY_SERVER_NAMES:-speed.cloudflare.com}"
          ],
          "privateKey": "$private_key",
          "shortIds": [
            "",
            "$short_id_1",
            "$short_id_2"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "block"
      }
    ]
  }
}
EOF

    # Set secure permissions
    chmod 600 "$config_file"

    # Validate JSON syntax
    if command -v python3 >/dev/null 2>&1; then
        if ! python3 -m json.tool "$config_file" >/dev/null 2>&1; then
            log_message "ERROR" "Generated configuration has invalid JSON syntax"
            return 1
        fi
    elif command -v jq >/dev/null 2>&1; then
        if ! jq . "$config_file" >/dev/null 2>&1; then
            log_message "ERROR" "Generated configuration has invalid JSON syntax"
            return 1
        fi
    else
        log_message "WARNING" "Cannot validate JSON syntax (python3 or jq not found)"
    fi

    # Store admin UUID in environment for reference
    echo "" >> "$env_file"
    echo "# Generated configuration values" >> "$env_file"
    echo "ADMIN_UUID=$admin_uuid" >> "$env_file"
    echo "SHORT_ID_1=$short_id_1" >> "$env_file"
    echo "SHORT_ID_2=$short_id_2" >> "$env_file"

    log_message "SUCCESS" "Server configuration created: $config_file"
    log_message "INFO" "Admin UUID: $admin_uuid"
    log_message "INFO" "ShortIds: '' (empty), $short_id_1, $short_id_2"

    return 0
}

# Create Docker Compose configuration
create_docker_compose() {
    log_message "INFO" "Creating Docker Compose configuration..."

    local compose_file="$PROJECT_ROOT/docker-compose.yml"
    local env_file="$PROJECT_ROOT/.env"

    # Check if Docker Compose configuration already exists
    if [[ -f "$compose_file" ]]; then
        log_message "INFO" "Docker Compose configuration already exists, regenerating..."
    fi

    # Check if environment file exists
    if [[ ! -f "$env_file" ]]; then
        log_message "ERROR" "Environment file not found: $env_file"
        return 1
    fi

    # Source environment variables
    source "$env_file"

    # Validate required environment variables
    local required_vars=("DOCKER_IMAGE" "XRAY_PORT" "COMPOSE_PROJECT_NAME")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            log_message "ERROR" "Required environment variable not set: $var"
            return 1
        fi
    done

    # Create Docker Compose YAML
    cat > "$compose_file" << EOF
version: '3.8'

services:
  xray:
    image: ${DOCKER_IMAGE:-teddysun/xray:latest}
    container_name: vless-xray
    restart: unless-stopped
    ports:
      - "${XRAY_PORT:-443}:443"
    volumes:
      - "./config:/etc/xray:ro"
      - "./data:/app/data:rw"
      - "./logs:/app/logs:rw"
    environment:
      - "TZ=UTC"
    networks:
      - vless-network
    healthcheck:
      test: ["CMD-SHELL", "netstat -an | grep :443 || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: '0.5'
        reservations:
          memory: 64M
          cpus: '0.1'

networks:
  vless-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
EOF

    # Set proper permissions
    chmod 644 "$compose_file"

    # Validate Docker Compose syntax
    if docker compose -f "$compose_file" config >/dev/null 2>&1; then
        log_message "SUCCESS" "Docker Compose configuration validated successfully"
    else
        log_message "WARNING" "Docker Compose validation failed, but configuration was created"
        log_message "INFO" "You can validate manually with: docker compose -f $compose_file config"
    fi

    log_message "SUCCESS" "Docker Compose configuration created: $compose_file"
    log_message "INFO" "Service: vless-xray on port ${XRAY_PORT:-443}"
    log_message "INFO" "Network: vless-network (172.20.0.0/16)"

    return 0
}

#######################################################################################
# HELP AND ARGUMENT PARSING FUNCTIONS
#######################################################################################

# Display help information
show_help() {
    cat << EOF
${GREEN}$SCRIPT_NAME v$SCRIPT_VERSION${NC}
VLESS+Reality VPN Service Management Script

${YELLOW}USAGE:${NC}
    $0 [COMMAND] [OPTIONS]

${YELLOW}COMMANDS:${NC}
    install                 Install and configure the service
    help                    Show this help message

${YELLOW}EXAMPLES:${NC}
    $0 install              Run full installation process
    $0 help                 Display this help

${YELLOW}REQUIREMENTS:${NC}
    - Ubuntu 20.04+ / Debian 11+
    - Architecture: x86_64 / ARM64
    - RAM: minimum 512 MB
    - Disk: minimum 1 GB free space
    - Port 443 available
    - Root or sudo privileges

${YELLOW}INSTALLATION PROCESS:${NC}
    1. System requirements verification
    2. Docker and Docker Compose installation
    3. Project directory structure creation
    4. Environment configuration setup
    5. X25519 key pair generation
    6. Server configuration creation
    7. Docker Compose configuration creation

For more information, visit: https://github.com/your-repo/vless-manager

EOF
}

# Parse command line arguments
parse_arguments() {
    case "${1:-}" in
        "install")
            return 0
            ;;
        "help"|"-h"|"--help")
            show_help
            exit 0
            ;;
        "")
            log_message "ERROR" "No command specified"
            show_help
            exit 1
            ;;
        *)
            log_message "ERROR" "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

#######################################################################################
# MAIN INSTALLATION FUNCTION
#######################################################################################

# Main installation function
install_service() {
    log_message "INFO" "Starting VLESS+Reality VPN service installation..."
    echo
    color_echo "blue" "=== VLESS+Reality VPN Service Installation ==="
    color_echo "blue" "Version: $SCRIPT_VERSION"
    color_echo "blue" "=============================================="
    echo

    local start_time=$(date +%s)

    # Step 1: System requirements check
    color_echo "yellow" "[1/8] Checking system requirements..."
    if ! check_system_requirements; then
        log_message "ERROR" "System requirements check failed"
        color_echo "red" "Installation aborted due to system requirements"
        echo
        color_echo "yellow" "Please resolve the above issues and try again:"
        color_echo "white" "- Ensure you have root/sudo privileges"
        color_echo "white" "- Verify OS compatibility (Ubuntu 20.04+/Debian 11+)"
        color_echo "white" "- Check available RAM (min 512MB) and disk space (min 1GB)"
        color_echo "white" "- Ensure port 443 is not in use"
        return 1
    fi
    echo

    # Step 2: Docker installation
    color_echo "yellow" "[2/8] Installing Docker..."
    if ! install_docker; then
        log_message "ERROR" "Docker installation failed"
        color_echo "red" "Installation aborted due to Docker installation failure"
        echo
        color_echo "yellow" "Troubleshooting suggestions:"
        color_echo "white" "- Check internet connectivity"
        color_echo "white" "- Verify repository access"
        color_echo "white" "- Run: sudo apt-get update && sudo apt-get upgrade"
        return 1
    fi
    echo

    # Step 3: Docker Compose installation
    color_echo "yellow" "[3/8] Installing Docker Compose..."
    if ! install_docker_compose; then
        log_message "ERROR" "Docker Compose installation failed"
        color_echo "red" "Installation aborted due to Docker Compose installation failure"
        return 1
    fi
    echo

    # Step 4: Directory structure creation
    color_echo "yellow" "[4/8] Creating directory structure..."
    if ! create_directories; then
        log_message "ERROR" "Directory structure creation failed"
        color_echo "red" "Installation aborted due to directory creation failure"
        return 1
    fi
    echo

    # Step 5: Environment configuration
    color_echo "yellow" "[5/8] Configuring environment..."
    if ! create_env_file; then
        log_message "ERROR" "Environment configuration failed"
        color_echo "red" "Installation aborted due to environment configuration failure"
        return 1
    fi
    echo

    # Step 6: Generate X25519 keys
    color_echo "yellow" "[6/8] Generating X25519 key pair..."
    if ! generate_keys; then
        log_message "ERROR" "X25519 key generation failed"
        color_echo "red" "Installation aborted due to key generation failure"
        echo
        color_echo "yellow" "Troubleshooting suggestions:"
        color_echo "white" "- Ensure Docker is running: sudo systemctl start docker"
        color_echo "white" "- Check Docker permissions: sudo usermod -aG docker $USER"
        color_echo "white" "- Verify internet connectivity for image download"
        return 1
    fi
    echo

    # Step 7: Create server configuration
    color_echo "yellow" "[7/8] Creating server configuration..."
    if ! create_server_config; then
        log_message "ERROR" "Server configuration creation failed"
        color_echo "red" "Installation aborted due to configuration creation failure"
        return 1
    fi
    echo

    # Step 8: Create Docker Compose configuration
    color_echo "yellow" "[8/8] Creating Docker Compose configuration..."
    if ! create_docker_compose; then
        log_message "ERROR" "Docker Compose configuration creation failed"
        color_echo "red" "Installation aborted due to Docker Compose configuration failure"
        return 1
    fi
    echo

    # Installation completed successfully
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    color_echo "green" "=============================================="
    color_echo "green" "     INSTALLATION COMPLETED SUCCESSFULLY"
    color_echo "green" "=============================================="
    echo
    log_message "SUCCESS" "Installation completed in ${duration} seconds"

    # Display installation summary
    echo
    color_echo "blue" "Installation Summary:"
    echo "  ✓ System requirements verified"
    echo "  ✓ Docker installed and configured"
    echo "  ✓ Docker Compose installed"
    echo "  ✓ Directory structure created"
    echo "  ✓ Environment configured"
    echo "  ✓ X25519 key pair generated"
    echo "  ✓ Server configuration created"
    echo "  ✓ Docker Compose configuration created"
    echo

    color_echo "blue" "Project Structure:"
    echo "  📁 $PROJECT_ROOT/"
    echo "  ├── 📁 config/          (Server configurations)"
    echo "  │   └── 📁 users/       (Client configurations)"
    echo "  ├── 📁 data/            (Database and keys)"
    echo "  │   ├── 📄 users.db     (User database)"
    echo "  │   └── 📁 keys/        (Private keys)"
    echo "  ├── 📁 logs/            (Service logs)"
    echo "  └── 📄 .env             (Environment variables)"
    echo

    color_echo "blue" "Configuration Details:"
    echo "  🖥️  Server IP: $(grep SERVER_IP $PROJECT_ROOT/.env | cut -d'=' -f2)"
    echo "  🔌 Service Port: 443"
    echo "  📝 Log Level: warning"
    echo "  🔑 Admin UUID: $(grep ADMIN_UUID $PROJECT_ROOT/.env | cut -d'=' -f2 || echo 'Generated')"
    echo "  📋 Configuration: $PROJECT_ROOT/config/server.json"
    echo "  🐳 Docker Compose: $PROJECT_ROOT/docker-compose.yml"
    echo

    color_echo "yellow" "Next Steps:"
    echo "  1. Review generated configuration files"
    echo "  2. Add users (Stage 3)"
    echo "  3. Start the service: docker compose up -d"
    echo "  4. Check service status: docker compose logs"
    echo

    return 0
}

#######################################################################################
# MAIN SCRIPT EXECUTION
#######################################################################################

# Main script execution
main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Execute the install command
    case "${1:-}" in
        "install")
            install_service
            ;;
    esac
}

# Execute main function with all arguments
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi