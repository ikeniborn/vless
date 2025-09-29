#!/bin/bash

# Load colors if not already loaded
if [ -z "$NC" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"
fi

# Array of trusted domains for REALITY
TRUSTED_DOMAINS=(
    "speed.cloudflare.com:443"
    "www.google.com:443"
    "www.microsoft.com:443"
    "www.apple.com:443"
    "www.amazon.com:443"
    "www.bing.com:443"
    "www.yahoo.com:443"
    "www.wikipedia.org:443"
    "www.cloudflare.com:443"
    "github.com:443"
    "gitlab.com:443"
    "www.youtube.com:443"
    "stackoverflow.com:443"
    "www.reddit.com:443"
)

# Function to select REALITY domain
select_reality_domain() {
    local selected_domain=""

    # Display to stderr to not interfere with return value
    print_header "Select Target Domain for REALITY" >&2
    echo "Choose a domain to masquerade as:" >&2
    echo "" >&2
    echo "  0) Enter custom domain" >&2

    for i in "${!TRUSTED_DOMAINS[@]}"; do
        printf "  %2d) %s\n" $((i+1)) "${TRUSTED_DOMAINS[$i]}" >&2
    done

    echo "" >&2
    while true; do
        read -p "Select option [0-${#TRUSTED_DOMAINS[@]}]: " choice

        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if [ "$choice" -eq 0 ]; then
                read -p "Enter custom domain (format: domain.com:443): " selected_domain
                if validate_domain "$selected_domain"; then
                    echo "$selected_domain"
                    return 0
                else
                    print_error "Invalid domain format or domain is not accessible" >&2
                fi
            elif [ "$choice" -ge 1 ] && [ "$choice" -le ${#TRUSTED_DOMAINS[@]} ]; then
                selected_domain="${TRUSTED_DOMAINS[$((choice-1))]}"
                echo "$selected_domain"
                return 0
            else
                print_error "Invalid selection. Please choose a number between 0 and ${#TRUSTED_DOMAINS[@]}" >&2
            fi
        else
            print_error "Please enter a valid number" >&2
        fi
    done
}

# Validate domain accessibility
validate_domain() {
    local domain=$1
    
    # Check format
    if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+:[0-9]+$ ]]; then
        return 1
    fi
    
    # Extract host and port
    local host="${domain%:*}"
    local port="${domain##*:}"
    
    # Check if domain is accessible
    # Output messages to stderr to avoid contaminating return values
    print_step "Checking domain accessibility: $host:$port" >&2

    # Try to connect with timeout
    if timeout 5 bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null; then
        print_success "Domain is accessible" >&2
        return 0
    else
        print_error "Domain is not accessible" >&2
        return 1
    fi
}

# Get domain without port
get_domain_name() {
    local domain_with_port=$1
    echo "${domain_with_port%:*}"
}

# Get port from domain string
get_domain_port() {
    local domain_with_port=$1
    echo "${domain_with_port##*:}"
}