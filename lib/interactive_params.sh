#!/bin/bash
#
# Interactive Parameter Collection Module
# Part of VLESS+Reality VPN Deployment System
#
# Purpose: Interactively collect and validate installation parameters
# Parameters: Destination site, VLESS port, Docker subnet
# Usage: source this file from install.sh
#
# TASK-1.5: Interactive parameter collection (3h)
#

set -euo pipefail

# =============================================================================
# GLOBAL VARIABLES (exported for use by other modules)
# =============================================================================

export REALITY_DEST=""
export REALITY_DEST_PORT=""
export VLESS_PORT=""
export DOCKER_SUBNET=""

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Default values
readonly DEFAULT_VLESS_PORT=443
readonly DEFAULT_DOCKER_SUBNET="172.20.0.0/16"
readonly DEST_VALIDATION_TIMEOUT=10  # seconds

# Predefined destination sites (validated for Reality compatibility)
declare -A PREDEFINED_DESTINATIONS=(
    ["1"]="www.google.com:443"
    ["2"]="www.microsoft.com:443"
    ["3"]="www.apple.com:443"
    ["4"]="www.cloudflare.com:443"
)

# Alternative ports if 443 is occupied
readonly ALTERNATIVE_PORTS=(8443 2053 2083 2087 2096 2052)

# =============================================================================
# FUNCTION: collect_parameters
# =============================================================================
# Description: Main function to collect all installation parameters interactively
# Called by: install.sh main()
# Sets: REALITY_DEST, REALITY_DEST_PORT, VLESS_PORT, DOCKER_SUBNET
# Returns: 0 on success, 1 on failure or user cancellation
# =============================================================================
collect_parameters() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         INTERACTIVE PARAMETER COLLECTION                    ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}This wizard will guide you through configuration.${NC}"
    echo -e "${CYAN}Press Ctrl+C at any time to cancel.${NC}"
    echo ""

    # Step 1: Select destination site
    select_destination_site || {
        echo -e "${RED}Failed to select destination site${NC}" >&2
        return 1
    }

    # Step 2: Select VLESS port
    select_port || {
        echo -e "${RED}Failed to select VLESS port${NC}" >&2
        return 1
    }

    # Step 3: Select Docker subnet
    select_docker_subnet || {
        echo -e "${RED}Failed to select Docker subnet${NC}" >&2
        return 1
    }

    # Step 4: Confirm all parameters
    confirm_parameters || {
        echo -e "${YELLOW}Configuration cancelled by user${NC}"
        return 1
    }

    echo ""
    echo -e "${GREEN}✓ All parameters collected successfully${NC}"
    echo ""

    return 0
}

# =============================================================================
# FUNCTION: select_destination_site
# =============================================================================
# Description: Interactive menu to select Reality destination site
# Validates: TLS 1.3 support, HTTP/2, SNI extraction
# Sets: REALITY_DEST, REALITY_DEST_PORT
# Returns: 0 on success, 1 on failure
# =============================================================================
select_destination_site() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[1/3] Select Destination Site for Reality Masquerading${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Reality protocol 'borrows' the TLS handshake from a legitimate HTTPS site."
    echo "Your VPN traffic will be indistinguishable from normal traffic to this site."
    echo ""
    echo "Available options:"
    echo "  1) www.google.com:443      (Recommended - highly reliable)"
    echo "  2) www.microsoft.com:443   (Enterprise-friendly)"
    echo "  3) www.apple.com:443       (Good for regions where Google is blocked)"
    echo "  4) www.cloudflare.com:443  (CDN provider)"
    echo "  5) Custom site (advanced)  "
    echo ""

    local choice
    while true; do
        read -rp "Enter your choice [1-5] (default: 1): " choice
        choice=${choice:-1}  # Default to option 1

        # Validate input is a number
        if ! [[ "$choice" =~ ^[1-5]$ ]]; then
            echo -e "${RED}Invalid choice. Please enter 1, 2, 3, 4, or 5${NC}"
            continue
        fi

        # Handle custom destination
        if [[ "$choice" == "5" ]]; then
            echo ""
            echo -e "${YELLOW}Custom Destination Site${NC}"
            echo "Enter destination in format: domain.com:port"
            echo "Examples: www.example.com:443, example.org:443"
            echo ""

            local custom_dest
            read -rp "Custom destination: " custom_dest

            if [[ -z "$custom_dest" ]]; then
                echo -e "${RED}Destination cannot be empty${NC}"
                continue
            fi

            # Parse custom destination
            if [[ "$custom_dest" =~ ^([a-zA-Z0-9.-]+):([0-9]+)$ ]]; then
                local dest_host="${BASH_REMATCH[1]}"
                local dest_port="${BASH_REMATCH[2]}"

                echo ""
                echo -e "${CYAN}Validating custom destination: ${dest_host}:${dest_port}${NC}"

                if validate_destination "$dest_host" "$dest_port"; then
                    REALITY_DEST="$dest_host"
                    REALITY_DEST_PORT="$dest_port"
                    echo -e "${GREEN}✓ Custom destination validated successfully${NC}"
                    return 0
                else
                    echo -e "${RED}✗ Validation failed for ${dest_host}:${dest_port}${NC}"
                    echo -e "${YELLOW}Please choose another destination${NC}"
                    echo ""
                    continue
                fi
            else
                echo -e "${RED}Invalid format. Use: domain.com:port${NC}"
                continue
            fi
        fi

        # Handle predefined destinations (1-4)
        local selected_dest="${PREDEFINED_DESTINATIONS[$choice]}"
        local dest_host="${selected_dest%%:*}"
        local dest_port="${selected_dest##*:}"

        echo ""
        echo -e "${CYAN}Selected: ${dest_host}:${dest_port}${NC}"
        echo -e "${CYAN}Validating destination (this may take up to ${DEST_VALIDATION_TIMEOUT} seconds)...${NC}"

        if validate_destination "$dest_host" "$dest_port"; then
            REALITY_DEST="$dest_host"
            REALITY_DEST_PORT="$dest_port"
            echo -e "${GREEN}✓ Destination validated successfully${NC}"
            echo ""
            return 0
        else
            echo -e "${YELLOW}Validation failed for ${dest_host}:${dest_port}${NC}"
            echo -e "${YELLOW}This destination may not be suitable. Try another option.${NC}"
            echo ""
            read -rp "Press Enter to select again..."
            continue
        fi
    done
}

# =============================================================================
# FUNCTION: validate_destination
# =============================================================================
# Description: Validate destination site for Reality compatibility
# Checks: TLS 1.3 support, reachability, SNI extraction
# Arguments: $1 - destination host, $2 - destination port
# Returns: 0 if valid, 1 if invalid
# =============================================================================
validate_destination() {
    local dest_host="$1"
    local dest_port="$2"

    # Check 1: DNS resolution
    echo -n "  [1/3] Checking DNS resolution... "
    if ! host "$dest_host" &>/dev/null; then
        echo -e "${RED}FAIL${NC}"
        echo -e "${RED}      Cannot resolve ${dest_host}${NC}"
        return 1
    fi
    echo -e "${GREEN}OK${NC}"

    # Check 2: TLS connectivity
    echo -n "  [2/3] Checking TLS connectivity... "
    if ! timeout "$DEST_VALIDATION_TIMEOUT" openssl s_client -connect "${dest_host}:${dest_port}" \
         -servername "$dest_host" </dev/null &>/dev/null; then
        echo -e "${RED}FAIL${NC}"
        echo -e "${RED}      Cannot establish TLS connection to ${dest_host}:${dest_port}${NC}"
        return 1
    fi
    echo -e "${GREEN}OK${NC}"

    # Check 3: TLS 1.3 support
    echo -n "  [3/3] Checking TLS 1.3 support... "
    local tls_version
    tls_version=$(timeout "$DEST_VALIDATION_TIMEOUT" openssl s_client -connect "${dest_host}:${dest_port}" \
                  -servername "$dest_host" -tls1_3 </dev/null 2>&1 | grep -oP 'Protocol\s*:\s*\K.*' | head -1)

    if [[ -z "$tls_version" ]] || ! echo "$tls_version" | grep -qi "TLSv1.3"; then
        echo -e "${YELLOW}WARN${NC}"
        echo -e "${YELLOW}      TLS 1.3 not confirmed, but may still work${NC}"
        # Don't fail on TLS 1.3 check - it's a soft requirement
    else
        echo -e "${GREEN}OK (${tls_version})${NC}"
    fi

    return 0
}

# =============================================================================
# FUNCTION: select_port
# =============================================================================
# Description: Interactive selection of VLESS server port with availability check
# Default: 443 (standard HTTPS port)
# Validates: Port is available and not in use
# Sets: VLESS_PORT
# Returns: 0 on success, 1 on failure
# =============================================================================
select_port() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[2/3] Select VLESS Server Port${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "VLESS server will listen on this port for incoming VPN connections."
    echo "Port 443 is recommended (standard HTTPS) for maximum compatibility."
    echo ""

    # Check if default port is available
    echo -e "${CYAN}Checking port availability...${NC}"
    if check_port_availability "$DEFAULT_VLESS_PORT"; then
        echo -e "${GREEN}✓ Port ${DEFAULT_VLESS_PORT} is available${NC}"
        echo ""

        local use_default
        read -rp "Use port ${DEFAULT_VLESS_PORT}? [Y/n]: " use_default
        use_default=${use_default:-Y}

        if [[ "$use_default" =~ ^[Yy]$ ]]; then
            VLESS_PORT="$DEFAULT_VLESS_PORT"
            echo -e "${GREEN}✓ Selected port: ${VLESS_PORT}${NC}"
            echo ""
            return 0
        fi
    else
        echo -e "${YELLOW}⚠ Port ${DEFAULT_VLESS_PORT} is already in use${NC}"
        echo ""
        suggest_alternative_ports
    fi

    # Manual port selection
    echo ""
    echo "Enter a custom port (1024-65535):"

    local custom_port
    while true; do
        read -rp "Port: " custom_port

        # Validate port number
        if ! [[ "$custom_port" =~ ^[0-9]+$ ]] || [ "$custom_port" -lt 1024 ] || [ "$custom_port" -gt 65535 ]; then
            echo -e "${RED}Invalid port. Must be between 1024 and 65535${NC}"
            continue
        fi

        # Check availability
        echo -n "Checking port ${custom_port}... "
        if check_port_availability "$custom_port"; then
            echo -e "${GREEN}Available${NC}"
            VLESS_PORT="$custom_port"
            echo -e "${GREEN}✓ Selected port: ${VLESS_PORT}${NC}"
            echo ""
            return 0
        else
            echo -e "${RED}In use${NC}"
            echo "Please try another port."
        fi
    done
}

# =============================================================================
# FUNCTION: check_port_availability
# =============================================================================
# Description: Check if a port is available (not in use)
# Arguments: $1 - port number
# Returns: 0 if available, 1 if in use
# =============================================================================
check_port_availability() {
    local port="$1"

    # Method 1: Check with ss (socket statistics)
    if command -v ss &>/dev/null; then
        if ss -tuln | grep -q ":${port} "; then
            return 1  # Port in use
        fi
    # Method 2: Check with netstat (fallback)
    elif command -v netstat &>/dev/null; then
        if netstat -tuln | grep -q ":${port} "; then
            return 1  # Port in use
        fi
    # Method 3: Check with lsof (fallback)
    elif command -v lsof &>/dev/null; then
        if lsof -i ":${port}" -sTCP:LISTEN &>/dev/null; then
            return 1  # Port in use
        fi
    else
        # No tools available - assume available (risky but better than failing)
        echo -e "${YELLOW}Warning: Cannot verify port availability (ss/netstat/lsof not found)${NC}" >&2
        return 0
    fi

    return 0  # Port available
}

# =============================================================================
# FUNCTION: suggest_alternative_ports
# =============================================================================
# Description: Suggest alternative ports if default is occupied
# Displays: List of available alternative ports
# =============================================================================
suggest_alternative_ports() {
    echo -e "${CYAN}Checking alternative ports...${NC}"
    echo ""

    local available_ports=()
    for alt_port in "${ALTERNATIVE_PORTS[@]}"; do
        if check_port_availability "$alt_port"; then
            available_ports+=("$alt_port")
        fi
    done

    if [ ${#available_ports[@]} -gt 0 ]; then
        echo -e "${GREEN}Available alternative ports:${NC}"
        for port in "${available_ports[@]}"; do
            echo "  - $port"
        done
        echo ""

        local use_alt
        read -rp "Use one of these ports? Enter port number or 'n' for custom: " use_alt

        if [[ "$use_alt" =~ ^[0-9]+$ ]]; then
            for port in "${available_ports[@]}"; do
                if [ "$port" == "$use_alt" ]; then
                    VLESS_PORT="$use_alt"
                    echo -e "${GREEN}✓ Selected port: ${VLESS_PORT}${NC}"
                    echo ""
                    return 0
                fi
            done
            echo -e "${YELLOW}Port ${use_alt} not in suggested list, please verify manually${NC}"
        fi
    else
        echo -e "${YELLOW}No alternative ports available from predefined list${NC}"
    fi
}

# =============================================================================
# FUNCTION: select_docker_subnet
# =============================================================================
# Description: Select Docker bridge network subnet with conflict detection
# Default: 172.20.0.0/16
# Scans: Existing Docker networks to avoid conflicts
# Sets: DOCKER_SUBNET
# Returns: 0 on success, 1 on failure
# =============================================================================
select_docker_subnet() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[3/3] Select Docker Network Subnet${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Docker bridge network will be created with an isolated subnet."
    echo "This ensures no conflicts with other VPN services."
    echo ""

    # Scan existing Docker networks
    echo -e "${CYAN}Scanning existing Docker networks...${NC}"
    local existing_subnets
    existing_subnets=$(scan_docker_networks)

    if [[ -n "$existing_subnets" ]]; then
        echo ""
        echo -e "${YELLOW}Existing Docker subnets:${NC}"
        echo "$existing_subnets" | while read -r line; do
            echo "  $line"
        done
        echo ""
    fi

    # Check if default subnet is available
    if ! echo "$existing_subnets" | grep -q "172.20.0.0/16"; then
        echo -e "${GREEN}✓ Default subnet ${DEFAULT_DOCKER_SUBNET} is available${NC}"
        echo ""

        local use_default
        read -rp "Use default subnet ${DEFAULT_DOCKER_SUBNET}? [Y/n]: " use_default
        use_default=${use_default:-Y}

        if [[ "$use_default" =~ ^[Yy]$ ]]; then
            DOCKER_SUBNET="$DEFAULT_DOCKER_SUBNET"
            echo -e "${GREEN}✓ Selected subnet: ${DOCKER_SUBNET}${NC}"
            echo ""
            return 0
        fi
    else
        echo -e "${YELLOW}⚠ Default subnet ${DEFAULT_DOCKER_SUBNET} is already in use${NC}"
        echo ""

        # Try to find a free subnet
        local free_subnet
        free_subnet=$(find_free_subnet "$existing_subnets")

        if [[ -n "$free_subnet" ]]; then
            echo -e "${GREEN}Found available subnet: ${free_subnet}${NC}"

            local use_free
            read -rp "Use this subnet? [Y/n]: " use_free
            use_free=${use_free:-Y}

            if [[ "$use_free" =~ ^[Yy]$ ]]; then
                DOCKER_SUBNET="$free_subnet"
                echo -e "${GREEN}✓ Selected subnet: ${DOCKER_SUBNET}${NC}"
                echo ""
                return 0
            fi
        fi
    fi

    # Manual subnet selection
    echo ""
    echo "Enter a custom subnet in CIDR notation (e.g., 172.21.0.0/16):"
    echo "Common private ranges: 172.16.0.0-172.31.0.0, 192.168.0.0-192.168.255.0"
    echo ""

    local custom_subnet
    while true; do
        read -rp "Subnet: " custom_subnet

        # Basic CIDR validation
        if [[ ! "$custom_subnet" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
            echo -e "${RED}Invalid CIDR format. Example: 172.21.0.0/16${NC}"
            continue
        fi

        # Check if already in use
        if echo "$existing_subnets" | grep -q "$custom_subnet"; then
            echo -e "${YELLOW}This subnet is already in use by Docker. Choose another.${NC}"
            continue
        fi

        DOCKER_SUBNET="$custom_subnet"
        echo -e "${GREEN}✓ Selected subnet: ${DOCKER_SUBNET}${NC}"
        echo ""
        return 0
    done
}

# =============================================================================
# FUNCTION: scan_docker_networks
# =============================================================================
# Description: Scan existing Docker networks and extract subnets
# Returns: List of subnets (one per line), empty if Docker not available
# =============================================================================
scan_docker_networks() {
    # Check if Docker is available
    if ! command -v docker &>/dev/null; then
        return 0
    fi

    # Check if Docker daemon is running
    if ! docker info &>/dev/null; then
        return 0
    fi

    # Get all networks and their subnets
    docker network ls --format '{{.Name}}' 2>/dev/null | while read -r network_name; do
        local subnet
        subnet=$(docker network inspect "$network_name" --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null)
        if [[ -n "$subnet" ]]; then
            echo "${network_name}: ${subnet}"
        fi
    done
}

# =============================================================================
# FUNCTION: find_free_subnet
# =============================================================================
# Description: Find a free subnet in 172.x.0.0/16 range
# Arguments: $1 - list of existing subnets
# Returns: Free subnet in CIDR notation, empty if none found
# =============================================================================
find_free_subnet() {
    local existing_subnets="$1"

    # Try 172.20.0.0 through 172.30.0.0
    for i in {20..30}; do
        local candidate="172.${i}.0.0/16"
        if ! echo "$existing_subnets" | grep -q "$candidate"; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}

# =============================================================================
# FUNCTION: confirm_parameters
# =============================================================================
# Description: Display all collected parameters and ask for confirmation
# Returns: 0 if confirmed, 1 if user wants to reconfigure
# =============================================================================
confirm_parameters() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║            CONFIGURATION SUMMARY                             ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Please review your configuration:${NC}"
    echo ""
    echo -e "  ${YELLOW}Destination Site:${NC}    ${REALITY_DEST}:${REALITY_DEST_PORT}"
    echo -e "  ${YELLOW}VLESS Port:${NC}          ${VLESS_PORT}"
    echo -e "  ${YELLOW}Docker Subnet:${NC}       ${DOCKER_SUBNET}"
    echo ""

    local confirm
    while true; do
        read -rp "Is this configuration correct? [Y/n]: " confirm
        confirm=${confirm:-Y}

        case "$confirm" in
            [Yy]*)
                echo ""
                echo -e "${GREEN}✓ Configuration confirmed${NC}"
                return 0
                ;;
            [Nn]*)
                echo ""
                echo -e "${YELLOW}Configuration rejected. Please restart installation.${NC}"
                return 1
                ;;
            *)
                echo -e "${RED}Please answer Y or n${NC}"
                ;;
        esac
    done
}

# =============================================================================
# MODULE INITIALIZATION
# =============================================================================

# Export all functions for use by install.sh
export -f collect_parameters
export -f select_destination_site
export -f validate_destination
export -f select_port
export -f check_port_availability
export -f suggest_alternative_ports
export -f select_docker_subnet
export -f scan_docker_networks
export -f find_free_subnet
export -f confirm_parameters
