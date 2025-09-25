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
# USER DATABASE MANAGEMENT FUNCTIONS
#######################################################################################

# Initialize user database
init_user_database() {
    log_message "INFO" "Initializing user database..."

    local users_db="$PROJECT_ROOT/data/users.db"

    # Check if database already exists
    if [[ -f "$users_db" ]]; then
        log_message "INFO" "User database already exists"
        return 0
    fi

    # Create database file with header
    cat > "$users_db" << EOF
# VLESS+Reality VPN Service User Database
# Format: username:uuid:shortId:created_date:status
# Generated on $(date '+%Y-%m-%d %H:%M:%S')
#
EOF

    # Set secure permissions
    chmod 600 "$users_db"

    log_message "SUCCESS" "User database initialized: $users_db"
    return 0
}

# Add user to database
add_user_to_database() {
    local username="$1"
    local uuid="$2"
    local short_id="$3"

    # Validate input parameters
    if [[ -z "$username" ]] || [[ -z "$uuid" ]] || [[ -z "$short_id" ]]; then
        log_message "ERROR" "Missing required parameters for add_user_to_database"
        return 1
    fi

    local users_db="$PROJECT_ROOT/data/users.db"

    # Initialize database if it doesn't exist
    if [[ ! -f "$users_db" ]]; then
        init_user_database || return 1
    fi

    # Check for duplicate username (case-insensitive)
    if user_exists "$username"; then
        log_message "ERROR" "Username '$username' already exists"
        return 1
    fi

    # Create user record
    local created_date=$(date '+%Y-%m-%d')
    local user_record="${username}:${uuid}:${short_id}:${created_date}:active"

    # Use file locking to prevent race conditions
    (
        flock -w 10 200 || {
            log_message "ERROR" "Could not acquire lock on user database"
            return 1
        }

        # Append user record to database
        echo "$user_record" >> "$users_db"

    ) 200>"${users_db}.lock"

    # Remove lock file
    rm -f "${users_db}.lock"

    # Ensure proper permissions
    chmod 600 "$users_db"

    log_message "SUCCESS" "User '$username' added to database"
    return 0
}

# Remove user from database
remove_user_from_database() {
    local username="$1"

    # Validate input parameter
    if [[ -z "$username" ]]; then
        log_message "ERROR" "Username parameter is required"
        return 1
    fi

    local users_db="$PROJECT_ROOT/data/users.db"

    # Check if database exists
    if [[ ! -f "$users_db" ]]; then
        log_message "ERROR" "User database not found: $users_db"
        return 1
    fi

    # Check if user exists
    if ! user_exists "$username"; then
        log_message "ERROR" "Username '$username' does not exist"
        return 1
    fi

    # Use file locking to prevent race conditions
    (
        flock -w 10 200 || {
            log_message "ERROR" "Could not acquire lock on user database"
            return 1
        }

        # Create temporary file
        local temp_file="${users_db}.tmp"

        # Copy all records except the target user (case-insensitive)
        while IFS=':' read -r db_username db_uuid db_short_id db_created_date db_status || [[ -n "$db_username" ]]; do
            # Skip comments and empty lines
            if [[ "$db_username" =~ ^#.*$ ]] || [[ -z "$db_username" ]]; then
                echo "${db_username}:${db_uuid}:${db_short_id}:${db_created_date}:${db_status}" >> "$temp_file"
                continue
            fi

            # Skip the user to be removed (case-insensitive comparison)
            if [[ "${db_username,,}" != "${username,,}" ]]; then
                echo "${db_username}:${db_uuid}:${db_short_id}:${db_created_date}:${db_status}" >> "$temp_file"
            fi
        done < "$users_db"

        # Replace original file atomically
        if [[ -f "$temp_file" ]]; then
            mv "$temp_file" "$users_db"
        else
            log_message "ERROR" "Failed to create temporary file for user removal"
            return 1
        fi

    ) 200>"${users_db}.lock"

    # Remove lock file
    rm -f "${users_db}.lock"

    # Ensure proper permissions
    chmod 600 "$users_db"

    log_message "SUCCESS" "User '$username' removed from database"
    return 0
}

# Check if user exists in database
user_exists() {
    local username="$1"

    # Validate input parameter
    if [[ -z "$username" ]]; then
        return 1
    fi

    local users_db="$PROJECT_ROOT/data/users.db"

    # Check if database exists
    if [[ ! -f "$users_db" ]]; then
        return 1
    fi

    # Search for user (case-insensitive)
    while IFS=':' read -r db_username db_uuid db_short_id db_created_date db_status || [[ -n "$db_username" ]]; do
        # Skip comments and empty lines
        if [[ "$db_username" =~ ^#.*$ ]] || [[ -z "$db_username" ]]; then
            continue
        fi

        # Check for match (case-insensitive)
        if [[ "${db_username,,}" == "${username,,}" ]]; then
            return 0
        fi
    done < "$users_db"

    return 1
}

# Get user information from database
get_user_info() {
    local username="$1"

    # Validate input parameter
    if [[ -z "$username" ]]; then
        log_message "ERROR" "Username parameter is required"
        return 1
    fi

    local users_db="$PROJECT_ROOT/data/users.db"

    # Check if database exists
    if [[ ! -f "$users_db" ]]; then
        log_message "ERROR" "User database not found: $users_db"
        return 1
    fi

    # Search for user and return information
    while IFS=':' read -r db_username db_uuid db_short_id db_created_date db_status || [[ -n "$db_username" ]]; do
        # Skip comments and empty lines
        if [[ "$db_username" =~ ^#.*$ ]] || [[ -z "$db_username" ]]; then
            continue
        fi

        # Check for match (case-insensitive)
        if [[ "${db_username,,}" == "${username,,}" ]]; then
            # Export user information as global variables
            USER_NAME="$db_username"
            USER_UUID="$db_uuid"
            USER_SHORT_ID="$db_short_id"
            USER_CREATED_DATE="$db_created_date"
            USER_STATUS="$db_status"
            return 0
        fi
    done < "$users_db"

    log_message "ERROR" "User '$username' not found in database"
    return 1
}

#######################################################################################
# INPUT VALIDATION FUNCTIONS
#######################################################################################

# Validate username format and constraints
validate_username() {
    local username="$1"

    # Check if username is provided
    if [[ -z "$username" ]]; then
        log_message "ERROR" "Username cannot be empty"
        return 1
    fi

    # Check username length (3-32 characters)
    local username_length=${#username}
    if [[ $username_length -lt 3 ]]; then
        log_message "ERROR" "Username too short: $username_length characters (minimum 3)"
        return 1
    fi
    if [[ $username_length -gt 32 ]]; then
        log_message "ERROR" "Username too long: $username_length characters (maximum 32)"
        return 1
    fi

    # Check username format: alphanumeric, underscore, dash allowed
    # Must start with alphanumeric character
    local username_regex='^[a-zA-Z0-9][a-zA-Z0-9_-]{2,31}$'
    if [[ ! $username =~ $username_regex ]]; then
        log_message "ERROR" "Invalid username format: '$username'"
        log_message "ERROR" "Username must:"
        log_message "ERROR" "  - Be 3-32 characters long"
        log_message "ERROR" "  - Start with alphanumeric character"
        log_message "ERROR" "  - Contain only letters, numbers, underscore (_), and dash (-)"
        return 1
    fi

    # Check for reserved usernames
    local reserved_usernames=("admin" "root" "system" "daemon" "nobody" "www" "ftp" "mail" "guest" "test" "user")
    for reserved in "${reserved_usernames[@]}"; do
        if [[ "${username,,}" == "$reserved" ]]; then
            log_message "ERROR" "Username '$username' is reserved and cannot be used"
            return 1
        fi
    done

    return 0
}

# Sanitize user input to prevent injection attacks
sanitize_input() {
    local input="$1"

    # Return empty string if input is empty
    if [[ -z "$input" ]]; then
        echo ""
        return 0
    fi

    # Remove dangerous characters and control characters
    local sanitized="$input"

    # Remove control characters (ASCII 0-31 and 127)
    sanitized=$(echo "$sanitized" | tr -d '\000-\037\177')

    # Remove potentially dangerous characters
    sanitized=$(echo "$sanitized" | tr -d '`$(){}[];<>|&*?~^!')

    # Escape quotes and backslashes
    sanitized=$(echo "$sanitized" | sed 's/["'"'"'\\]/\\&/g')

    # Trim leading and trailing whitespace
    sanitized=$(echo "$sanitized" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    echo "$sanitized"
}

# Check if user limit has been reached
check_user_limit() {
    local max_users=10
    local current_users=0
    local users_db="$PROJECT_ROOT/data/users.db"

    # Check if database exists
    if [[ ! -f "$users_db" ]]; then
        # No database means no users, so under limit
        return 0
    fi

    # Count active users (skip comments and empty lines)
    while IFS=':' read -r db_username db_uuid db_short_id db_created_date db_status || [[ -n "$db_username" ]]; do
        # Skip comments and empty lines
        if [[ "$db_username" =~ ^#.*$ ]] || [[ -z "$db_username" ]]; then
            continue
        fi

        # Count active users
        if [[ "$db_status" == "active" ]]; then
            ((current_users++))
        fi
    done < "$users_db"

    log_message "INFO" "Current active users: $current_users/$max_users"

    # Check if at limit
    if [[ $current_users -ge $max_users ]]; then
        log_message "ERROR" "Maximum number of users ($max_users) reached"
        log_message "ERROR" "Please remove an existing user before adding a new one"
        return 1
    fi

    return 0
}

# Count total users in database
count_users() {
    local users_db="$PROJECT_ROOT/data/users.db"
    local total_users=0
    local active_users=0

    # Check if database exists
    if [[ ! -f "$users_db" ]]; then
        echo "0:0"  # total:active
        return 0
    fi

    # Count users (skip comments and empty lines)
    while IFS=':' read -r db_username db_uuid db_short_id db_created_date db_status || [[ -n "$db_username" ]]; do
        # Skip comments and empty lines
        if [[ "$db_username" =~ ^#.*$ ]] || [[ -z "$db_username" ]]; then
            continue
        fi

        ((total_users++))

        # Count active users
        if [[ "$db_status" == "active" ]]; then
            ((active_users++))
        fi
    done < "$users_db"

    echo "$total_users:$active_users"
}

#######################################################################################
# SERVER CONFIGURATION MANAGEMENT FUNCTIONS
#######################################################################################

# Create backup of server configuration
backup_server_config() {
    log_message "INFO" "Creating server configuration backup..."

    local config_file="$PROJECT_ROOT/config/server.json"

    # Check if server config exists
    if [[ ! -f "$config_file" ]]; then
        log_message "ERROR" "Server configuration not found: $config_file"
        return 1
    fi

    # Create backup with timestamp
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_file="${config_file}.backup.${timestamp}"

    # Copy configuration file
    if cp "$config_file" "$backup_file"; then
        chmod 600 "$backup_file"
        log_message "SUCCESS" "Configuration backup created: $backup_file"
        echo "$backup_file"  # Return backup file path
        return 0
    else
        log_message "ERROR" "Failed to create configuration backup"
        return 1
    fi
}

# Validate server configuration JSON syntax and structure
validate_server_config() {
    local config_file="$PROJECT_ROOT/config/server.json"

    log_message "INFO" "Validating server configuration..."

    # Check if file exists
    if [[ ! -f "$config_file" ]]; then
        log_message "ERROR" "Server configuration not found: $config_file"
        return 1
    fi

    # Check JSON syntax
    if command -v jq >/dev/null 2>&1; then
        if ! jq empty "$config_file" >/dev/null 2>&1; then
            log_message "ERROR" "Invalid JSON syntax in server configuration"
            return 1
        fi
    elif command -v python3 >/dev/null 2>&1; then
        if ! python3 -m json.tool "$config_file" >/dev/null 2>&1; then
            log_message "ERROR" "Invalid JSON syntax in server configuration"
            return 1
        fi
    else
        log_message "WARNING" "Cannot validate JSON syntax (jq or python3 not available)"
    fi

    # Check for required structure using jq if available
    if command -v jq >/dev/null 2>&1; then
        # Check if inbounds array exists
        if ! jq -e '.inbounds' "$config_file" >/dev/null 2>&1; then
            log_message "ERROR" "Missing 'inbounds' array in configuration"
            return 1
        fi

        # Check if first inbound has clients array
        if ! jq -e '.inbounds[0].settings.clients' "$config_file" >/dev/null 2>&1; then
            log_message "ERROR" "Missing 'clients' array in first inbound configuration"
            return 1
        fi

        # Check if all client UUIDs are valid format
        local client_count
        client_count=$(jq -r '.inbounds[0].settings.clients | length' "$config_file")

        for ((i=0; i<client_count; i++)); do
            local uuid
            uuid=$(jq -r ".inbounds[0].settings.clients[$i].id" "$config_file")

            # UUID format validation
            if [[ ! $uuid =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
                log_message "ERROR" "Invalid UUID format in client $i: $uuid"
                return 1
            fi
        done
    fi

    log_message "SUCCESS" "Server configuration validation passed"
    return 0
}

# Add client to server configuration
add_client_to_server() {
    local uuid="$1"
    local short_id="$2"

    # Validate input parameters
    if [[ -z "$uuid" ]] || [[ -z "$short_id" ]]; then
        log_message "ERROR" "Missing required parameters for add_client_to_server"
        return 1
    fi

    local config_file="$PROJECT_ROOT/config/server.json"

    log_message "INFO" "Adding client to server configuration..."
    log_message "INFO" "UUID: $uuid"
    log_message "INFO" "ShortId: $short_id"

    # Check if configuration exists
    if [[ ! -f "$config_file" ]]; then
        log_message "ERROR" "Server configuration not found: $config_file"
        return 1
    fi

    # Check if jq is available for JSON manipulation
    if ! command -v jq >/dev/null 2>&1; then
        log_message "ERROR" "jq is required for JSON manipulation but not found"
        log_message "INFO" "Install with: sudo apt-get install jq"
        return 1
    fi

    # Create new client object
    local new_client
    new_client=$(jq -n \
        --arg id "$uuid" \
        --arg short_id "$short_id" \
        '{
            "id": $id,
            "flow": "xtls-rprx-vision",
            "shortId": $short_id
        }')

    # Add client to configuration
    local temp_config="${config_file}.tmp"

    if jq ".inbounds[0].settings.clients += [$new_client]" "$config_file" > "$temp_config"; then
        # Validate the updated configuration
        if validate_server_config_temp "$temp_config"; then
            mv "$temp_config" "$config_file"
            chmod 600 "$config_file"
            log_message "SUCCESS" "Client added to server configuration"
            return 0
        else
            rm -f "$temp_config"
            log_message "ERROR" "Generated configuration failed validation"
            return 1
        fi
    else
        rm -f "$temp_config"
        log_message "ERROR" "Failed to add client to server configuration"
        return 1
    fi
}

# Remove client from server configuration
remove_client_from_server() {
    local uuid="$1"

    # Validate input parameter
    if [[ -z "$uuid" ]]; then
        log_message "ERROR" "UUID parameter is required for remove_client_from_server"
        return 1
    fi

    local config_file="$PROJECT_ROOT/config/server.json"

    log_message "INFO" "Removing client from server configuration..."
    log_message "INFO" "UUID: $uuid"

    # Check if configuration exists
    if [[ ! -f "$config_file" ]]; then
        log_message "ERROR" "Server configuration not found: $config_file"
        return 1
    fi

    # Check if jq is available for JSON manipulation
    if ! command -v jq >/dev/null 2>&1; then
        log_message "ERROR" "jq is required for JSON manipulation but not found"
        log_message "INFO" "Install with: sudo apt-get install jq"
        return 1
    fi

    # Check if client exists
    local client_exists
    client_exists=$(jq --arg uuid "$uuid" '.inbounds[0].settings.clients | map(select(.id == $uuid)) | length' "$config_file")

    if [[ "$client_exists" == "0" ]]; then
        log_message "WARNING" "Client with UUID $uuid not found in configuration"
        return 0
    fi

    # Remove client from configuration
    local temp_config="${config_file}.tmp"

    if jq --arg uuid "$uuid" '.inbounds[0].settings.clients |= map(select(.id != $uuid))' "$config_file" > "$temp_config"; then
        # Validate the updated configuration
        if validate_server_config_temp "$temp_config"; then
            mv "$temp_config" "$config_file"
            chmod 600 "$config_file"
            log_message "SUCCESS" "Client removed from server configuration"
            return 0
        else
            rm -f "$temp_config"
            log_message "ERROR" "Generated configuration failed validation"
            return 1
        fi
    else
        rm -f "$temp_config"
        log_message "ERROR" "Failed to remove client from server configuration"
        return 1
    fi
}

# Validate temporary server configuration (internal function)
validate_server_config_temp() {
    local temp_config="$1"

    # Check if file exists
    if [[ ! -f "$temp_config" ]]; then
        return 1
    fi

    # Check JSON syntax
    if command -v jq >/dev/null 2>&1; then
        if ! jq empty "$temp_config" >/dev/null 2>&1; then
            return 1
        fi
    elif command -v python3 >/dev/null 2>&1; then
        if ! python3 -m json.tool "$temp_config" >/dev/null 2>&1; then
            return 1
        fi
    fi

    return 0
}

# Main function to update server configuration
update_server_config() {
    local action="$1"
    local username="$2"
    local uuid="$3"
    local short_id="$4"

    log_message "INFO" "Updating server configuration..."
    log_message "INFO" "Action: $action"
    log_message "INFO" "Username: $username"

    # Validate action parameter
    if [[ "$action" != "add" ]] && [[ "$action" != "remove" ]]; then
        log_message "ERROR" "Invalid action: $action (must be 'add' or 'remove')"
        return 1
    fi

    # Create backup before making changes
    local backup_file
    backup_file=$(backup_server_config)
    if [[ $? -ne 0 ]]; then
        log_message "ERROR" "Failed to create configuration backup"
        return 1
    fi

    # Perform the requested action
    local result=0
    case "$action" in
        "add")
            if [[ -z "$uuid" ]] || [[ -z "$short_id" ]]; then
                log_message "ERROR" "UUID and shortId are required for add action"
                result=1
            else
                add_client_to_server "$uuid" "$short_id"
                result=$?
            fi
            ;;
        "remove")
            if [[ -z "$uuid" ]]; then
                log_message "ERROR" "UUID is required for remove action"
                result=1
            else
                remove_client_from_server "$uuid"
                result=$?
            fi
            ;;
    esac

    # Check if operation was successful
    if [[ $result -eq 0 ]]; then
        # Validate final configuration
        if validate_server_config; then
            log_message "SUCCESS" "Server configuration updated successfully"
            # Keep backup for safety but don't delete it automatically
            log_message "INFO" "Configuration backup available: $backup_file"
            return 0
        else
            log_message "ERROR" "Updated configuration failed validation, restoring backup"
            # Restore from backup
            cp "$backup_file" "$PROJECT_ROOT/config/server.json"
            chmod 600 "$PROJECT_ROOT/config/server.json"
            return 1
        fi
    else
        log_message "ERROR" "Failed to update server configuration, restoring backup"
        # Restore from backup
        cp "$backup_file" "$PROJECT_ROOT/config/server.json"
        chmod 600 "$PROJECT_ROOT/config/server.json"
        return 1
    fi
}

#######################################################################################
# CLIENT CONFIGURATION GENERATION FUNCTIONS
#######################################################################################

# Create VLESS URL for easy client import
create_vless_url() {
    local uuid="$1"
    local server_ip="$2"
    local port="$3"
    local public_key="$4"
    local short_id="$5"

    # Validate input parameters
    if [[ -z "$uuid" ]] || [[ -z "$server_ip" ]] || [[ -z "$port" ]] || [[ -z "$public_key" ]] || [[ -z "$short_id" ]]; then
        log_message "ERROR" "Missing required parameters for create_vless_url"
        return 1
    fi

    # URL encode the public key if necessary
    local encoded_public_key
    encoded_public_key=$(echo "$public_key" | sed 's/+/%2B/g' | sed 's/\//%2F/g' | sed 's/=/%3D/g')

    # Create VLESS URL
    local vless_url="vless://${uuid}@${server_ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=speed.cloudflare.com&fp=chrome&pbk=${encoded_public_key}&sid=${short_id}&type=tcp&headerType=none#VLESS_Reality"

    echo "$vless_url"
}

# Create JSON configuration for advanced clients
create_client_json() {
    local uuid="$1"
    local server_ip="$2"
    local port="$3"
    local public_key="$4"
    local short_id="$5"

    # Validate input parameters
    if [[ -z "$uuid" ]] || [[ -z "$server_ip" ]] || [[ -z "$port" ]] || [[ -z "$public_key" ]] || [[ -z "$short_id" ]]; then
        log_message "ERROR" "Missing required parameters for create_client_json"
        return 1
    fi

    # Create JSON configuration
    local client_json
    client_json=$(jq -n \
        --arg uuid "$uuid" \
        --arg server_ip "$server_ip" \
        --arg port "$port" \
        --arg public_key "$public_key" \
        --arg short_id "$short_id" \
        '{
            "outbounds": [
                {
                    "protocol": "vless",
                    "settings": {
                        "vnext": [
                            {
                                "address": $server_ip,
                                "port": ($port | tonumber),
                                "users": [
                                    {
                                        "id": $uuid,
                                        "encryption": "none",
                                        "flow": "xtls-rprx-vision"
                                    }
                                ]
                            }
                        ]
                    },
                    "streamSettings": {
                        "network": "tcp",
                        "security": "reality",
                        "realitySettings": {
                            "serverName": "speed.cloudflare.com",
                            "fingerprint": "chrome",
                            "publicKey": $public_key,
                            "shortId": $short_id
                        }
                    },
                    "tag": "proxy"
                },
                {
                    "protocol": "freedom",
                    "tag": "direct"
                }
            ],
            "routing": {
                "rules": [
                    {
                        "type": "field",
                        "ip": [
                            "geoip:private"
                        ],
                        "outboundTag": "direct"
                    }
                ]
            }
        }')

    echo "$client_json"
}

# Save client configuration files
save_client_config() {
    local username="$1"
    local vless_url="$2"
    local json_config="$3"

    # Validate input parameters
    if [[ -z "$username" ]] || [[ -z "$vless_url" ]] || [[ -z "$json_config" ]]; then
        log_message "ERROR" "Missing required parameters for save_client_config"
        return 1
    fi

    local users_config_dir="$PROJECT_ROOT/config/users"
    local url_file="${users_config_dir}/${username}.url"
    local json_file="${users_config_dir}/${username}.json"

    log_message "INFO" "Saving client configuration for user: $username"

    # Ensure users config directory exists
    if [[ ! -d "$users_config_dir" ]]; then
        mkdir -p "$users_config_dir"
        chmod 700 "$users_config_dir"
    fi

    # Save VLESS URL
    echo "$vless_url" > "$url_file"
    if [[ $? -eq 0 ]]; then
        chmod 600 "$url_file"
        log_message "SUCCESS" "VLESS URL saved: $url_file"
    else
        log_message "ERROR" "Failed to save VLESS URL for user: $username"
        return 1
    fi

    # Save JSON configuration
    echo "$json_config" > "$json_file"
    if [[ $? -eq 0 ]]; then
        chmod 600 "$json_file"
        log_message "SUCCESS" "JSON configuration saved: $json_file"
    else
        log_message "ERROR" "Failed to save JSON configuration for user: $username"
        return 1
    fi

    return 0
}

# Generate complete client configuration
generate_client_config() {
    local username="$1"
    local uuid="$2"
    local short_id="$3"

    # Validate input parameters
    if [[ -z "$username" ]] || [[ -z "$uuid" ]] || [[ -z "$short_id" ]]; then
        log_message "ERROR" "Missing required parameters for generate_client_config"
        return 1
    fi

    log_message "INFO" "Generating client configuration for user: $username"

    # Read environment variables
    local env_file="$PROJECT_ROOT/.env"
    if [[ ! -f "$env_file" ]]; then
        log_message "ERROR" "Environment file not found: $env_file"
        return 1
    fi

    source "$env_file"

    # Validate required environment variables
    if [[ -z "$SERVER_IP" ]] || [[ -z "$XRAY_PORT" ]]; then
        log_message "ERROR" "Required environment variables not set (SERVER_IP, XRAY_PORT)"
        return 1
    fi

    # Read public key
    local public_key_file="$PROJECT_ROOT/data/keys/public.key"
    if [[ ! -f "$public_key_file" ]]; then
        log_message "ERROR" "Public key file not found: $public_key_file"
        return 1
    fi

    local public_key
    public_key=$(cat "$public_key_file")
    if [[ -z "$public_key" ]]; then
        log_message "ERROR" "Public key is empty"
        return 1
    fi

    # Check if jq is available for JSON generation
    if ! command -v jq >/dev/null 2>&1; then
        log_message "ERROR" "jq is required for JSON configuration generation but not found"
        log_message "INFO" "Install with: sudo apt-get install jq"
        return 1
    fi

    # Generate VLESS URL
    local vless_url
    vless_url=$(create_vless_url "$uuid" "$SERVER_IP" "$XRAY_PORT" "$public_key" "$short_id")
    if [[ $? -ne 0 ]] || [[ -z "$vless_url" ]]; then
        log_message "ERROR" "Failed to generate VLESS URL"
        return 1
    fi

    # Generate JSON configuration
    local json_config
    json_config=$(create_client_json "$uuid" "$SERVER_IP" "$XRAY_PORT" "$public_key" "$short_id")
    if [[ $? -ne 0 ]] || [[ -z "$json_config" ]]; then
        log_message "ERROR" "Failed to generate JSON configuration"
        return 1
    fi

    # Save configuration files
    if save_client_config "$username" "$vless_url" "$json_config"; then
        log_message "SUCCESS" "Client configuration generated successfully for user: $username"

        # Display configuration details
        echo
        color_echo "blue" "Client Configuration Generated:"
        echo "  👤 Username: $username"
        echo "  🆔 UUID: $uuid"
        echo "  🔑 ShortId: $short_id"
        echo "  🌐 Server: $SERVER_IP:$XRAY_PORT"
        echo "  📄 VLESS URL: $PROJECT_ROOT/config/users/${username}.url"
        echo "  📄 JSON Config: $PROJECT_ROOT/config/users/${username}.json"
        echo

        return 0
    else
        log_message "ERROR" "Failed to save client configuration files"
        return 1
    fi
}

#######################################################################################
# USER MANAGEMENT COMMAND FUNCTIONS
#######################################################################################

# Add new user to the VPN service
add_user() {
    local username="$1"

    # Sanitize and validate username
    username=$(sanitize_input "$username")
    if [[ -z "$username" ]]; then
        log_message "ERROR" "Username cannot be empty"
        return 1
    fi

    log_message "INFO" "Starting user addition process for: $username"

    # Validate username format
    if ! validate_username "$username"; then
        return 1
    fi

    # Check if user already exists
    if user_exists "$username"; then
        log_message "ERROR" "User '$username' already exists"
        return 1
    fi

    # Check user limit
    if ! check_user_limit; then
        return 1
    fi

    # Generate UUID for the new user
    local uuid
    uuid=$(generate_uuid)
    if [[ $? -ne 0 ]] || [[ -z "$uuid" ]]; then
        log_message "ERROR" "Failed to generate UUID for user: $username"
        return 1
    fi

    # Generate shortId for the new user
    local short_id
    short_id=$(generate_short_id 8)
    if [[ $? -ne 0 ]] || [[ -z "$short_id" ]]; then
        log_message "ERROR" "Failed to generate shortId for user: $username"
        return 1
    fi

    log_message "INFO" "Generated credentials for user: $username"
    log_message "INFO" "UUID: $uuid"
    log_message "INFO" "ShortId: $short_id"

    # Add user to database
    if ! add_user_to_database "$username" "$uuid" "$short_id"; then
        log_message "ERROR" "Failed to add user to database"
        return 1
    fi

    # Update server configuration
    if ! update_server_config "add" "$username" "$uuid" "$short_id"; then
        log_message "ERROR" "Failed to update server configuration, removing user from database"
        # Rollback: remove user from database
        remove_user_from_database "$username"
        return 1
    fi

    # Generate client configuration
    if ! generate_client_config "$username" "$uuid" "$short_id"; then
        log_message "ERROR" "Failed to generate client configuration, rolling back changes"
        # Rollback: remove from server config and database
        update_server_config "remove" "$username" "$uuid" "$short_id"
        remove_user_from_database "$username"
        return 1
    fi

    # Restart Docker container to apply changes
    log_message "INFO" "Restarting Xray service to apply configuration changes..."
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        local compose_dir="$PROJECT_ROOT"
        local restart_result=0

        # Use timeout to prevent hanging
        if timeout 30 docker compose -f "${compose_dir}/docker-compose.yml" restart xray >/dev/null 2>&1; then
            log_message "SUCCESS" "Xray service restarted successfully"
        else
            log_message "WARNING" "Failed to restart Xray service automatically"
            log_message "INFO" "Please restart manually: cd $PROJECT_ROOT && docker compose restart xray"
            restart_result=1
        fi

        # Verify service is running
        sleep 2
        if docker compose -f "${compose_dir}/docker-compose.yml" ps xray | grep -q "Up\|running"; then
            log_message "SUCCESS" "Xray service is running"
        else
            log_message "WARNING" "Xray service may not be running properly"
            log_message "INFO" "Check status: cd $PROJECT_ROOT && docker compose ps"
        fi
    else
        log_message "WARNING" "Docker or Docker Compose not available, manual service restart required"
    fi

    # Display success message
    echo
    color_echo "green" "✅ User '$username' added successfully!"
    echo
    color_echo "blue" "Connection Details:"
    echo "  👤 Username: $username"
    echo "  🆔 UUID: $uuid"
    echo "  🔑 ShortId: $short_id"
    echo "  📄 Configuration files:"
    echo "     - VLESS URL: $PROJECT_ROOT/config/users/${username}.url"
    echo "     - JSON Config: $PROJECT_ROOT/config/users/${username}.json"
    echo
    color_echo "yellow" "Next Steps:"
    echo "  1. Share the configuration files with the user"
    echo "  2. Import the configuration in a VLESS client"
    echo "  3. Test the connection"
    echo

    # Display current user count
    local user_counts
    user_counts=$(count_users)
    local total_users=${user_counts%:*}
    local active_users=${user_counts#*:}
    echo "📊 User Statistics: $active_users/$total_users active users (10 max)"
    echo

    return 0
}

# Remove user from the VPN service
remove_user() {
    local username="$1"

    # Sanitize input
    username=$(sanitize_input "$username")
    if [[ -z "$username" ]]; then
        log_message "ERROR" "Username cannot be empty"
        return 1
    fi

    log_message "INFO" "Starting user removal process for: $username"

    # Check if user exists
    if ! user_exists "$username"; then
        log_message "ERROR" "User '$username' does not exist"
        return 1
    fi

    # Get user information
    if ! get_user_info "$username"; then
        log_message "ERROR" "Failed to retrieve user information for: $username"
        return 1
    fi

    # Store user info for rollback
    local user_uuid="$USER_UUID"
    local user_short_id="$USER_SHORT_ID"

    log_message "INFO" "Found user: $USER_NAME"
    log_message "INFO" "UUID: $user_uuid"
    log_message "INFO" "ShortId: $user_short_id"

    # Remove from server configuration
    if ! update_server_config "remove" "$username" "$user_uuid" "$user_short_id"; then
        log_message "ERROR" "Failed to remove user from server configuration"
        return 1
    fi

    # Remove from user database
    if ! remove_user_from_database "$username"; then
        log_message "ERROR" "Failed to remove user from database, attempting rollback"
        # Rollback: re-add to server configuration
        update_server_config "add" "$username" "$user_uuid" "$user_short_id"
        return 1
    fi

    # Remove client configuration files
    local users_config_dir="$PROJECT_ROOT/config/users"
    local url_file="${users_config_dir}/${username}.url"
    local json_file="${users_config_dir}/${username}.json"

    if [[ -f "$url_file" ]]; then
        rm -f "$url_file"
        log_message "INFO" "Removed VLESS URL file: $url_file"
    fi

    if [[ -f "$json_file" ]]; then
        rm -f "$json_file"
        log_message "INFO" "Removed JSON configuration file: $json_file"
    fi

    # Restart Docker container to apply changes
    log_message "INFO" "Restarting Xray service to apply configuration changes..."
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        local compose_dir="$PROJECT_ROOT"

        # Use timeout to prevent hanging
        if timeout 30 docker compose -f "${compose_dir}/docker-compose.yml" restart xray >/dev/null 2>&1; then
            log_message "SUCCESS" "Xray service restarted successfully"
        else
            log_message "WARNING" "Failed to restart Xray service automatically"
            log_message "INFO" "Please restart manually: cd $PROJECT_ROOT && docker compose restart xray"
        fi

        # Verify service is running
        sleep 2
        if docker compose -f "${compose_dir}/docker-compose.yml" ps xray | grep -q "Up\|running"; then
            log_message "SUCCESS" "Xray service is running"
        else
            log_message "WARNING" "Xray service may not be running properly"
            log_message "INFO" "Check status: cd $PROJECT_ROOT && docker compose ps"
        fi
    else
        log_message "WARNING" "Docker or Docker Compose not available, manual service restart required"
    fi

    # Display success message
    echo
    color_echo "green" "✅ User '$username' removed successfully!"
    echo
    color_echo "blue" "Cleanup Summary:"
    echo "  🗑️  User removed from database"
    echo "  🗑️  User removed from server configuration"
    echo "  🗑️  Client configuration files deleted"
    echo "  🔄 Service restarted"
    echo

    # Display current user count
    local user_counts
    user_counts=$(count_users)
    local total_users=${user_counts%:*}
    local active_users=${user_counts#*:}
    echo "📊 User Statistics: $active_users/$total_users active users (10 max)"
    echo

    return 0
}

# List all users in the VPN service
list_users() {
    log_message "INFO" "Retrieving user list..."

    local users_db="$PROJECT_ROOT/data/users.db"

    # Check if database exists
    if [[ ! -f "$users_db" ]]; then
        echo
        color_echo "yellow" "📋 User List"
        echo "════════════════════════════════════════════════════════════"
        echo "No users found. Database does not exist."
        echo
        echo "💡 Add your first user with: $0 add-user USERNAME"
        echo
        return 0
    fi

    # Count users
    local user_counts
    user_counts=$(count_users)
    local total_users=${user_counts%:*}
    local active_users=${user_counts#*:}

    if [[ $total_users -eq 0 ]]; then
        echo
        color_echo "yellow" "📋 User List"
        echo "════════════════════════════════════════════════════════════"
        echo "No users found. Database is empty."
        echo
        echo "💡 Add your first user with: $0 add-user USERNAME"
        echo
        return 0
    fi

    # Display header
    echo
    color_echo "blue" "📋 VLESS+Reality VPN Users"
    echo "════════════════════════════════════════════════════════════"
    printf "%-16s %-8s %-10s %-12s %-8s\n" "Username" "UUID" "Status" "Created" "Config"
    echo "────────────────────────────────────────────────────────────"

    # Display users
    while IFS=':' read -r db_username db_uuid db_short_id db_created_date db_status || [[ -n "$db_username" ]]; do
        # Skip comments and empty lines
        if [[ "$db_username" =~ ^#.*$ ]] || [[ -z "$db_username" ]]; then
            continue
        fi

        # Truncate UUID for display
        local uuid_short="${db_uuid:0:8}..."

        # Check if configuration files exist
        local config_status="❌"
        if [[ -f "$PROJECT_ROOT/config/users/${db_username}.url" ]] && [[ -f "$PROJECT_ROOT/config/users/${db_username}.json" ]]; then
            config_status="✅"
        fi

        # Color code by status
        local status_colored
        case "$db_status" in
            "active")
                status_colored="$(color_echo "green" "active")"
                ;;
            "inactive")
                status_colored="$(color_echo "yellow" "inactive")"
                ;;
            *)
                status_colored="$(color_echo "red" "$db_status")"
                ;;
        esac

        printf "%-16s %-8s %-10s %-12s %-8s\n" "$db_username" "$uuid_short" "$status_colored" "$db_created_date" "$config_status"
    done < "$users_db"

    echo "────────────────────────────────────────────────────────────"
    echo "📊 Total: $total_users users | Active: $active_users | Slots remaining: $((10 - active_users))/10"
    echo

    # Show usage suggestions
    color_echo "yellow" "💡 Quick Actions:"
    echo "  $0 show-user USERNAME     - Show detailed user information"
    echo "  $0 add-user USERNAME      - Add a new user"
    echo "  $0 remove-user USERNAME   - Remove an existing user"
    echo

    return 0
}

# Show detailed information for a specific user
show_user() {
    local username="$1"

    # Sanitize input
    username=$(sanitize_input "$username")
    if [[ -z "$username" ]]; then
        log_message "ERROR" "Username cannot be empty"
        return 1
    fi

    log_message "INFO" "Retrieving user information for: $username"

    # Check if user exists
    if ! user_exists "$username"; then
        log_message "ERROR" "User '$username' does not exist"
        echo
        color_echo "red" "❌ User '$username' not found"
        echo
        color_echo "yellow" "💡 List all users with: $0 list-users"
        echo
        return 1
    fi

    # Get user information
    if ! get_user_info "$username"; then
        log_message "ERROR" "Failed to retrieve user information"
        return 1
    fi

    # Check configuration files
    local users_config_dir="$PROJECT_ROOT/config/users"
    local url_file="${users_config_dir}/${username}.url"
    local json_file="${users_config_dir}/${username}.json"
    local url_exists=false
    local json_exists=false

    if [[ -f "$url_file" ]]; then
        url_exists=true
    fi

    if [[ -f "$json_file" ]]; then
        json_exists=true
    fi

    # Display user information
    echo
    color_echo "blue" "👤 User Information: $username"
    echo "════════════════════════════════════════════════════════════"
    echo "Username:     $USER_NAME"
    echo "UUID:         $USER_UUID"
    echo "ShortId:      $USER_SHORT_ID"
    echo "Created:      $USER_CREATED_DATE"
    echo "Status:       $(color_echo "green" "$USER_STATUS")"
    echo

    # Configuration files section
    color_echo "blue" "📄 Configuration Files:"
    echo "────────────────────────────────────────────────────────────"
    if [[ $url_exists == true ]]; then
        echo "VLESS URL:    ✅ $url_file"
    else
        echo "VLESS URL:    ❌ File not found"
    fi

    if [[ $json_exists == true ]]; then
        echo "JSON Config:  ✅ $json_file"
    else
        echo "JSON Config:  ❌ File not found"
    fi
    echo

    # Show VLESS URL if file exists
    if [[ $url_exists == true ]]; then
        color_echo "blue" "🔗 VLESS URL:"
        echo "────────────────────────────────────────────────────────────"
        cat "$url_file"
        echo
        echo

        # Generate QR code if qrencode is available
        if command -v qrencode >/dev/null 2>&1; then
            color_echo "blue" "📱 QR Code:"
            echo "────────────────────────────────────────────────────────────"
            qrencode -t ANSI "$(cat "$url_file")"
            echo
        else
            color_echo "yellow" "💡 Install qrencode to display QR code: sudo apt-get install qrencode"
            echo
        fi
    fi

    # Connection details
    if [[ -f "$PROJECT_ROOT/.env" ]]; then
        source "$PROJECT_ROOT/.env"
        color_echo "blue" "🌐 Connection Details:"
        echo "────────────────────────────────────────────────────────────"
        echo "Server:       $SERVER_IP:$XRAY_PORT"
        echo "Protocol:     VLESS"
        echo "Transport:    Reality (TCP)"
        echo "SNI:          speed.cloudflare.com"
        echo "Fingerprint:  chrome"
        echo
    fi

    # Show instructions
    color_echo "yellow" "💡 Instructions:"
    echo "────────────────────────────────────────────────────────────"
    echo "1. Copy the VLESS URL or download the JSON configuration"
    echo "2. Import into a compatible VLESS client (v2rayN, v2rayNG, etc.)"
    echo "3. Test the connection"
    echo

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
    $0 [COMMAND] [ARGUMENTS]

${YELLOW}SYSTEM COMMANDS:${NC}
    install                 Install and configure the service
    help                    Show this help message

${YELLOW}USER MANAGEMENT COMMANDS:${NC}
    add-user USERNAME       Add a new VPN user
    remove-user USERNAME    Remove an existing VPN user
    list-users             List all VPN users
    show-user USERNAME     Show detailed user information

${YELLOW}EXAMPLES:${NC}
    $0 install              Run full installation process
    $0 add-user alice       Add user 'alice' to VPN service
    $0 remove-user alice    Remove user 'alice' from VPN service
    $0 list-users           Display all VPN users
    $0 show-user alice      Show detailed info for user 'alice'
    $0 help                 Display this help

${YELLOW}USERNAME REQUIREMENTS:${NC}
    - Length: 3-32 characters
    - Start with alphanumeric character
    - Contains only: letters, numbers, underscore (_), dash (-)
    - Maximum 10 users allowed

${YELLOW}SYSTEM REQUIREMENTS:${NC}
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

${YELLOW}USER WORKFLOW:${NC}
    1. Install the service: sudo $0 install
    2. Add users: sudo $0 add-user USERNAME
    3. Start service: docker compose up -d
    4. Share client configs from config/users/
    5. Manage users as needed

For more information, visit: https://github.com/your-repo/vless-manager

EOF
}

# Parse command line arguments
parse_arguments() {
    case "${1:-}" in
        "install")
            return 0
            ;;
        "add-user")
            if [[ -z "${2:-}" ]]; then
                log_message "ERROR" "Username is required for add-user command"
                echo "Usage: $0 add-user USERNAME"
                exit 1
            fi
            return 0
            ;;
        "remove-user")
            if [[ -z "${2:-}" ]]; then
                log_message "ERROR" "Username is required for remove-user command"
                echo "Usage: $0 remove-user USERNAME"
                exit 1
            fi
            return 0
            ;;
        "list-users")
            return 0
            ;;
        "show-user")
            if [[ -z "${2:-}" ]]; then
                log_message "ERROR" "Username is required for show-user command"
                echo "Usage: $0 show-user USERNAME"
                exit 1
            fi
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
            echo
            color_echo "yellow" "Available commands:"
            echo "  install                 - Install and configure the service"
            echo "  add-user USERNAME       - Add a new VPN user"
            echo "  remove-user USERNAME    - Remove an existing VPN user"
            echo "  list-users             - List all VPN users"
            echo "  show-user USERNAME     - Show detailed user information"
            echo "  help                   - Show help message"
            echo
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

    # Execute the appropriate command
    case "${1:-}" in
        "install")
            install_service
            ;;
        "add-user")
            # Check for root privileges for user management
            if ! check_root; then
                exit 1
            fi
            add_user "$2"
            ;;
        "remove-user")
            # Check for root privileges for user management
            if ! check_root; then
                exit 1
            fi
            remove_user "$2"
            ;;
        "list-users")
            # Check for root privileges for user management
            if ! check_root; then
                exit 1
            fi
            list_users
            ;;
        "show-user")
            # Check for root privileges for user management
            if ! check_root; then
                exit 1
            fi
            show_user "$2"
            ;;
    esac
}

# Execute main function with all arguments
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi