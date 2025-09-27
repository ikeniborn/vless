#!/bin/bash

# Load colors if not already loaded
if [ -z "$NC" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"
fi

# Check if script is run as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate IP address format
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip_parts=($ip)
        IFS=$OIFS
        for part in "${ip_parts[@]}"; do
            if [[ $part -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Validate email format
validate_email() {
    local email=$1
    if [[ $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    fi
    return 1
}

# Validate port number
validate_port() {
    local port=$1
    if [[ $port =~ ^[0-9]+$ ]] && [ $port -ge 1 ] && [ $port -le 65535 ]; then
        return 0
    fi
    return 1
}

# Generate UUID
generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# Generate Short ID (8 hex characters)
generate_short_id() {
    openssl rand -hex 4
}

# Get external IP address
get_external_ip() {
    local ip=""
    # Try multiple services for redundancy
    for service in "ifconfig.me" "ipinfo.io/ip" "checkip.amazonaws.com"; do
        ip=$(curl -s -4 --max-time 5 "https://$service" 2>/dev/null)
        if validate_ip "$ip"; then
            echo "$ip"
            return 0
        fi
    done
    return 1
}

# Check if port is in use
check_port_available() {
    local port=$1
    if ! ss -tuln | grep -q ":$port "; then
        return 0
    fi
    return 1
}

# Confirm action with user
confirm_action() {
    local prompt="$1"
    local default="${2:-n}"
    local response
    
    if [[ $default == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi
    
    read -p "$prompt" response
    response=${response:-$default}
    
    if [[ $response =~ ^[Yy]$ ]]; then
        return 0
    fi
    return 1
}

# Create directory with proper permissions
create_directory() {
    local dir=$1
    local perms=${2:-755}
    
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        chmod "$perms" "$dir"
        return 0
    fi
    return 1
}

# Wait for service to be ready
wait_for_service() {
    local service_name=$1
    local max_attempts=${2:-30}
    local attempt=0

    echo -n "Waiting for $service_name to be ready"
    while [ $attempt -lt $max_attempts ]; do
        if docker ps | grep -q "$service_name"; then
            echo ""
            return 0
        fi
        echo -n "."
        sleep 1
        attempt=$((attempt + 1))
    done
    echo ""
    return 1
}

# Comprehensive health check for Xray service
check_xray_health() {
    local container_name=${1:-"xray-server"}
    local max_wait=${2:-30}

    print_step "Performing comprehensive health check..."

    # Step 1: Check if container exists and is running
    print_info "Checking container status..."
    local container_status=$(docker ps -a --filter "name=$container_name" --format "{{.Status}}" | head -1)

    if [ -z "$container_status" ]; then
        print_error "Container $container_name not found"
        return 1
    fi

    if ! echo "$container_status" | grep -q "Up"; then
        print_error "Container is not running. Status: $container_status"
        print_info "Try: docker-compose logs $container_name"
        return 1
    fi

    # Check if container is restarting
    if echo "$container_status" | grep -q "Restarting"; then
        print_error "Container is in restarting loop"
        print_info "Check logs: docker-compose logs --tail 50 $container_name"
        return 1
    fi

    print_success "Container is running"

    # Step 2: Check for critical errors in logs
    print_info "Checking logs for errors..."
    local error_count=$(docker logs "$container_name" 2>&1 | tail -50 | grep -ciE "error|fatal|panic|failed" || true)

    if [ "$error_count" -gt 0 ]; then
        print_warning "Found $error_count potential errors in recent logs"
        local recent_errors=$(docker logs "$container_name" 2>&1 | tail -10 | grep -iE "error|fatal|panic|failed" || true)
        if [ -n "$recent_errors" ]; then
            print_warning "Recent errors:"
            echo "$recent_errors" | head -3
        fi
    else
        print_success "No critical errors in logs"
    fi

    # Step 3: Check if port is listening
    print_info "Checking port availability..."
    local port=${SERVER_PORT:-443}

    if netstat -tuln | grep -q ":$port "; then
        print_success "Port $port is listening"
    else
        print_error "Port $port is not listening"
        print_info "Check firewall rules and Docker port mapping"
        return 1
    fi

    # Step 4: Validate Xray configuration (optional)
    print_info "Validating Xray configuration..."
    local config_test=$(docker exec "$container_name" xray test -c /etc/xray/config.json 2>&1 || true)

    if echo "$config_test" | grep -q "Configuration OK"; then
        print_success "Xray configuration is valid"
    elif [ -n "$config_test" ]; then
        print_warning "Configuration test output: $config_test"
    fi

    # Step 5: Check container resource usage
    print_info "Checking resource usage..."
    local stats=$(docker stats --no-stream --format "CPU: {{.CPUPerc}} | Memory: {{.MemUsage}}" "$container_name" 2>/dev/null || true)
    if [ -n "$stats" ]; then
        print_info "Resource usage: $stats"
    fi

    print_success "Health check completed successfully"
    return 0
}

# Check system requirements
check_system_requirements() {
    local errors=0
    
    print_info "Checking system requirements..."
    
    # Check OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ ! "$ID" =~ ^(debian|ubuntu)$ ]]; then
            print_warning "This script is optimized for Debian/Ubuntu. Other distributions may work but are not officially supported."
        fi
    fi
    
    # Check RAM (minimum 512MB)
    local total_ram=$(free -m | awk 'NR==2{print $2}')
    if [ $total_ram -lt 512 ]; then
        print_error "Insufficient RAM. Minimum 512MB required, found: ${total_ram}MB"
        ((errors++))
    fi
    
    # Check disk space (minimum 5GB in /opt)
    local free_space=$(df -BG /opt 2>/dev/null | awk 'NR==2{print int($4)}')
    if [ -z "$free_space" ] || [ $free_space -lt 5 ]; then
        print_error "Insufficient disk space. Minimum 5GB required in /opt"
        ((errors++))
    fi
    
    return $errors
}