#!/bin/bash
# Common Utilities Module for VLESS VPN Project
# Shared functions and utilities used across all modules
# Author: Claude Code
# Version: 1.0

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Import process isolation module
source "${SCRIPT_DIR}/process_isolation/process_safe.sh" 2>/dev/null || {
    echo "ERROR: Cannot load process isolation module" >&2
    exit 1
}

# Project information
readonly PROJECT_NAME="VLESS VPN"
readonly PROJECT_VERSION="1.0"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly CONFIG_DIR="$PROJECT_DIR/config"
readonly MODULES_DIR="$PROJECT_DIR/modules"
readonly TESTS_DIR="$PROJECT_DIR/tests"
readonly VLESS_DIR="/opt/vless"

# Color definitions - check each variable individually
[[ -z "${RED:-}" ]] && readonly RED='\033[0;31m'
[[ -z "${GREEN:-}" ]] && readonly GREEN='\033[0;32m'
[[ -z "${YELLOW:-}" ]] && readonly YELLOW='\033[1;33m'
[[ -z "${BLUE:-}" ]] && readonly BLUE='\033[0;34m'
[[ -z "${CYAN:-}" ]] && readonly CYAN='\033[0;36m'
[[ -z "${PURPLE:-}" ]] && readonly PURPLE='\033[0;35m'
[[ -z "${WHITE:-}" ]] && readonly WHITE='\033[1;37m'
[[ -z "${BOLD:-}" ]] && readonly BOLD='\033[1m'
[[ -z "${NC:-}" ]] && readonly NC='\033[0m'

# Unicode symbols
readonly CHECK_MARK="✓"
readonly CROSS_MARK="✗"
readonly WARNING_MARK="⚠"
readonly INFO_MARK="ℹ"
readonly ARROW_RIGHT="→"

# Print functions with consistent formatting
print_header() {
    # Ensure color variables are defined
    local white_color="${WHITE:-\033[1;37m}"
    local blue_color="${BLUE:-\033[0;34m}"
    local nc_color="${NC:-\033[0m}"
    local bold_color="${BOLD:-\033[1m}"

    local title="$1"
    local width=60
    local padding=$(( (width - ${#title} - 2) / 2 ))

    echo
    echo -e "${blue_color}╔$(printf '═%.0s' $(seq 1 $width))╗${nc_color}"
    printf "${blue_color}║${nc_color}"
    printf "%*s" $padding ""
    printf "${white_color}${bold_color}%s${nc_color}" "$title"
    printf "%*s" $((width - padding - ${#title})) ""
    printf "${blue_color}║${nc_color}\n"
    echo -e "${blue_color}╚$(printf '═%.0s' $(seq 1 $width))╝${nc_color}"
    echo
}

print_section() {
    local title="$1"
    echo -e "${CYAN}${BOLD}▶ $title${NC}"
}

print_info() {
    local message="$1"
    echo -e "${BLUE}${INFO_MARK}${NC} $message"
}

print_success() {
    local message="$1"
    echo -e "${GREEN}${CHECK_MARK}${NC} $message"
}

print_warning() {
    local message="$1"
    echo -e "${YELLOW}${WARNING_MARK}${NC} $message"
}

print_error() {
    local message="$1"
    echo -e "${RED}${CROSS_MARK}${NC} $message"
}

print_step() {
    local step="$1"
    local description="$2"
    echo -e "${PURPLE}[$step]${NC} $description"
}

# System information functions
get_os_info() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "$PRETTY_NAME"
    else
        echo "Unknown Linux Distribution"
    fi
}

get_architecture() {
    uname -m
}

get_kernel_version() {
    uname -r
}

get_system_uptime() {
    uptime -p 2>/dev/null || echo "Uptime unavailable"
}

get_memory_info() {
    local total_mem=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local available_mem=$(grep MemAvailable /proc/meminfo | awk '{print $2}')

    local total_gb=$((total_mem / 1024 / 1024))
    local available_gb=$((available_mem / 1024 / 1024))

    echo "${available_gb}GB / ${total_gb}GB available"
}

get_disk_info() {
    local usage=$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 " used)"}')
    echo "$usage"
}

# Network utility functions
get_public_ip() {
    local ip=""

    # Try multiple services
    local services=(
        "curl -s https://ipv4.icanhazip.com"
        "curl -s https://api.ipify.org"
        "curl -s https://checkip.amazonaws.com"
    )

    for service in "${services[@]}"; do
        if ip=$(timeout 10 $service 2>/dev/null | tr -d '\n\r'); then
            if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                echo "$ip"
                return 0
            fi
        fi
    done

    echo "Unable to determine"
    return 1
}

get_local_ip() {
    local ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || echo "")
    if [[ -n "$ip" ]]; then
        echo "$ip"
    else
        echo "Unable to determine"
    fi
}

check_internet_connectivity() {
    local test_hosts=("8.8.8.8" "1.1.1.1" "208.67.222.222")

    for host in "${test_hosts[@]}"; do
        if timeout 5 ping -c 1 "$host" >/dev/null 2>&1; then
            return 0
        fi
    done

    return 1
}

# Validation functions
validate_ip_address() {
    local ip="$1"
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if [[ $octet -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

validate_port() {
    local port="$1"
    if [[ "$port" =~ ^[0-9]+$ ]] && [[ $port -ge 1 ]] && [[ $port -le 65535 ]]; then
        return 0
    fi
    return 1
}

validate_domain() {
    local domain="$1"
    if [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    fi
    return 1
}

validate_email() {
    local email="$1"
    if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    fi
    return 1
}

# User input functions
prompt_yes_no() {
    local question="$1"
    local default="${2:-n}"

    local prompt_text="$question"
    if [[ "$default" == "y" ]]; then
        prompt_text+=" (Y/n): "
    else
        prompt_text+=" (y/N): "
    fi

    while true; do
        read -p "$prompt_text" -n 1 -r reply
        echo

        if [[ -z "$reply" ]]; then
            reply="$default"
        fi

        case "$reply" in
            [Yy]) return 0 ;;
            [Nn]) return 1 ;;
            *) echo "Please answer yes (y) or no (n)." ;;
        esac
    done
}

prompt_input() {
    local prompt="$1"
    local default="$2"
    local validator="${3:-}"

    while true; do
        if [[ -n "$default" ]]; then
            read -p "$prompt (default: $default): " input
            input="${input:-$default}"
        else
            read -p "$prompt: " input
        fi

        if [[ -z "$validator" ]] || $validator "$input"; then
            echo "$input"
            return 0
        else
            print_error "Invalid input. Please try again."
        fi
    done
}

prompt_choice() {
    local prompt="$1"
    shift
    local choices=("$@")

    echo "$prompt"
    for i in "${!choices[@]}"; do
        echo "$((i + 1))) ${choices[i]}"
    done
    echo

    while true; do
        read -p "Please select an option (1-${#choices[@]}): " choice

        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#choices[@]} ]]; then
            echo $((choice - 1))
            return 0
        else
            print_error "Invalid selection. Please choose a number between 1 and ${#choices[@]}."
        fi
    done
}

# File and directory utility functions
ensure_directory() {
    local dir_path="$1"
    local permissions="${2:-755}"
    local owner="${3:-$USER}"

    if [[ ! -d "$dir_path" ]]; then
        if [[ "$dir_path" =~ ^/opt/ ]] || [[ "$dir_path" =~ ^/etc/ ]] || [[ "$dir_path" =~ ^/var/ ]]; then
            sudo mkdir -p "$dir_path"
            sudo chown "$owner:$owner" "$dir_path"
            sudo chmod "$permissions" "$dir_path"
        else
            mkdir -p "$dir_path"
            chmod "$permissions" "$dir_path"
        fi
        print_success "Created directory: $dir_path"
    else
        print_info "Directory already exists: $dir_path"
    fi
}

backup_file() {
    local file_path="$1"
    local backup_suffix="${2:-.backup.$(date +%Y%m%d_%H%M%S)}"

    if [[ -f "$file_path" ]]; then
        local backup_path="${file_path}${backup_suffix}"
        cp "$file_path" "$backup_path"
        print_success "Backup created: $backup_path"
        echo "$backup_path"
    else
        print_warning "File does not exist, no backup needed: $file_path"
        return 1
    fi
}

# Service management functions
check_service_status() {
    local service_name="$1"

    if systemctl is-active --quiet "$service_name"; then
        return 0
    else
        return 1
    fi
}

wait_for_service() {
    local service_name="$1"
    local max_wait="${2:-30}"
    local check_interval="${3:-2}"

    local elapsed=0
    while [[ $elapsed -lt $max_wait ]]; do
        if check_service_status "$service_name"; then
            print_success "Service $service_name is running"
            return 0
        fi

        sleep "$check_interval"
        elapsed=$((elapsed + check_interval))
    done

    print_error "Service $service_name failed to start within $max_wait seconds"
    return 1
}

# Progress indication functions
show_progress() {
    local cyan_color="${CYAN:-\033[0;36m}"
    local nc_color="${NC:-\033[0m}"

    local current="$1"
    local total="$2"
    local description="${3:-Processing}"

    local percentage=$((current * 100 / total))
    local completed=$((percentage / 2))
    local remaining=$((50 - completed))

    printf "\r${cyan_color}%s:${nc_color} [" "$description"
    printf "%*s" $completed | tr ' ' '='
    printf "%*s" $remaining | tr ' ' '-'
    printf "] %d%% (%d/%d)" $percentage $current $total

    if [[ $current -eq $total ]]; then
        echo
    fi
}

spinner() {
    local cyan_color="${CYAN:-\033[0;36m}"
    local nc_color="${NC:-\033[0m}"

    local pid="$1"
    local message="${2:-Working}"
    local delay=0.1
    local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"

    while kill -0 "$pid" 2>/dev/null; do
        for (( i=0; i<${#chars}; i++ )); do
            printf "\r${cyan_color}%s${nc_color} %s" "${chars:$i:1}" "$message"
            sleep $delay
        done
    done

    printf "\r%*s\r" $((${#message} + 10)) ""
}

# Configuration file functions
read_config_value() {
    local config_file="$1"
    local key="$2"
    local default_value="${3:-}"

    if [[ -f "$config_file" ]]; then
        local value=$(grep "^${key}=" "$config_file" | cut -d'=' -f2- | sed 's/^["'"'"']//;s/["'"'"']$//')
        echo "${value:-$default_value}"
    else
        echo "$default_value"
    fi
}

write_config_value() {
    local config_file="$1"
    local key="$2"
    local value="$3"

    ensure_directory "$(dirname "$config_file")"

    if [[ -f "$config_file" ]]; then
        if grep -q "^${key}=" "$config_file"; then
            sed -i "s/^${key}=.*/${key}=\"${value}\"/" "$config_file"
        else
            echo "${key}=\"${value}\"" >> "$config_file"
        fi
    else
        echo "${key}=\"${value}\"" > "$config_file"
    fi
}

# System information display
show_system_info() {
    print_header "System Information"

    printf "%-20s %s\n" "Operating System:" "$(get_os_info)"
    printf "%-20s %s\n" "Architecture:" "$(get_architecture)"
    printf "%-20s %s\n" "Kernel Version:" "$(get_kernel_version)"
    printf "%-20s %s\n" "Uptime:" "$(get_system_uptime)"
    printf "%-20s %s\n" "Memory:" "$(get_memory_info)"
    printf "%-20s %s\n" "Disk Usage:" "$(get_disk_info)"
    printf "%-20s %s\n" "Local IP:" "$(get_local_ip)"

    if check_internet_connectivity; then
        printf "%-20s %s\n" "Public IP:" "$(get_public_ip)"
        printf "%-20s %s\n" "Internet:" "${GREEN}Connected${NC}"
    else
        printf "%-20s %s\n" "Internet:" "${RED}Disconnected${NC}"
    fi

    echo
}

# Random string generation
generate_random_string() {
    local length="${1:-16}"
    local charset="${2:-A-Za-z0-9}"

    tr -dc "$charset" < /dev/urandom | head -c "$length"
}

# UUID generation
generate_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    else
        # Fallback UUID generation
        printf '%08x-%04x-%04x-%04x-%012x\n' \
            $((RANDOM * RANDOM)) \
            $((RANDOM % 65536)) \
            $(((RANDOM % 4096) | 16384)) \
            $(((RANDOM % 16384) | 32768)) \
            $((RANDOM * RANDOM * RANDOM))
    fi
}

# Timestamp functions
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

get_timestamp_filename() {
    date '+%Y%m%d_%H%M%S'
}

# Module loading function
load_module() {
    local module_name="$1"
    local module_path="${MODULES_DIR}/${module_name}"

    if [[ -f "$module_path" ]]; then
        source "$module_path"
        print_success "Module loaded: $module_name"
        return 0
    else
        print_error "Module not found: $module_name"
        return 1
    fi
}

# Check if all color variables are properly defined
check_color_variables() {
    local required_colors=("RED" "GREEN" "YELLOW" "BLUE" "CYAN" "PURPLE" "WHITE" "BOLD" "NC")
    local missing_colors=()

    for color in "${required_colors[@]}"; do
        if [[ -z "${!color:-}" ]]; then
            missing_colors+=("$color")
        fi
    done

    if [[ ${#missing_colors[@]} -gt 0 ]]; then
        echo "WARNING: Missing color variables: ${missing_colors[*]}" >&2
        return 1
    fi

    return 0
}

# Export all functions
export -f print_header print_section print_info print_success print_warning print_error print_step
export -f get_os_info get_architecture get_kernel_version get_system_uptime get_memory_info get_disk_info
export -f get_public_ip get_local_ip check_internet_connectivity
export -f validate_ip_address validate_port validate_domain validate_email
export -f prompt_yes_no prompt_input prompt_choice
export -f ensure_directory backup_file
export -f check_service_status wait_for_service
export -f show_progress spinner
export -f read_config_value write_config_value
export -f show_system_info
export -f generate_random_string generate_uuid
export -f get_timestamp get_timestamp_filename
export -f load_module check_color_variables

# Export constants
export PROJECT_NAME PROJECT_VERSION PROJECT_DIR CONFIG_DIR MODULES_DIR TESTS_DIR VLESS_DIR
export RED GREEN YELLOW BLUE CYAN PURPLE WHITE BOLD NC
export CHECK_MARK CROSS_MARK WARNING_MARK INFO_MARK ARROW_RIGHT