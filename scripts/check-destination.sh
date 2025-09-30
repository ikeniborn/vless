#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
# VLESS REALITY Destination Domain Checker
# ═══════════════════════════════════════════════════════════════════
# Проверяет destination домены на соответствие требованиям REALITY:
# - Поддержка TLSv1.3
# - Поддержка HTTP/2
# - Отсутствие редиректов
# - Доступность сервера
#
# Использование:
#   ./check-destination.sh                    # Интерактивный режим
#   ./check-destination.sh <domain:port>      # Проверка конкретного домена
#   ./check-destination.sh --all              # Проверка всех доменов из lib/domains.sh
# ═══════════════════════════════════════════════════════════════════

set -euo pipefail

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load libraries
source "${SCRIPT_DIR}/lib/colors.sh"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/domains.sh"

# ═══════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════

TIMEOUT=10  # Timeout for connection tests in seconds

# ═══════════════════════════════════════════════════════════════════
# FUNCTIONS
# ═══════════════════════════════════════════════════════════════════

# Check if required commands are available
check_requirements() {
    local missing_tools=()

    if ! command_exists openssl; then
        missing_tools+=("openssl")
    fi

    if ! command_exists curl; then
        missing_tools+=("curl")
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        echo ""
        echo "Please install them:"
        echo "  sudo apt-get install openssl curl"
        return 1
    fi

    return 0
}

# Check TLS version support
check_tls_version() {
    local host=$1
    local port=$2

    print_step "Checking TLS support for $host:$port"

    # Try to connect with TLSv1.3
    if timeout "$TIMEOUT" openssl s_client -connect "$host:$port" -tls1_3 -servername "$host" </dev/null 2>&1 | grep -q "Protocol.*TLSv1.3"; then
        print_success "TLSv1.3 supported"
        return 0
    elif timeout "$TIMEOUT" openssl s_client -connect "$host:$port" -tls1_2 -servername "$host" </dev/null 2>&1 | grep -q "Protocol.*TLSv1.2"; then
        print_warning "Only TLSv1.2 supported (TLSv1.3 not available)"
        return 1
    else
        print_error "TLS connection failed or unsupported version"
        return 2
    fi
}

# Check HTTP/2 support
check_http2_support() {
    local host=$1
    local port=$2

    print_step "Checking HTTP/2 support for $host:$port"

    # Use curl to check for HTTP/2
    local response
    response=$(timeout "$TIMEOUT" curl -sI --http2 --max-time "$TIMEOUT" "https://$host:$port" 2>&1)

    if echo "$response" | grep -qi "HTTP/2"; then
        print_success "HTTP/2 supported"
        return 0
    elif echo "$response" | grep -qi "HTTP/1.1"; then
        print_warning "Only HTTP/1.1 available (HTTP/2 not supported)"
        return 1
    else
        print_error "HTTP connection failed"
        return 2
    fi
}

# Check for redirects
check_no_redirects() {
    local host=$1
    local port=$2

    print_step "Checking for redirects on $host:$port"

    # Get HTTP response code
    local http_code
    http_code=$(timeout "$TIMEOUT" curl -s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" "https://$host:$port" 2>/dev/null || echo "000")

    if [[ "$http_code" == "200" ]]; then
        print_success "No redirects (HTTP 200)"
        return 0
    elif [[ "$http_code" =~ ^30[0-9]$ ]]; then
        print_warning "Redirect detected (HTTP $http_code)"
        return 1
    elif [[ "$http_code" == "000" ]]; then
        print_error "Connection failed"
        return 2
    else
        print_warning "Unusual status code: HTTP $http_code"
        return 1
    fi
}

# Check server accessibility
check_accessibility() {
    local host=$1
    local port=$2

    print_step "Checking server accessibility for $host:$port"

    # Try to establish TCP connection
    if timeout "$TIMEOUT" bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null; then
        print_success "Server is accessible"
        return 0
    else
        print_error "Server is not accessible"
        return 1
    fi
}

# Perform full check on a domain
check_domain() {
    local domain_with_port=$1
    local host="${domain_with_port%:*}"
    local port="${domain_with_port##*:}"

    # Validate format
    if [[ ! "$domain_with_port" =~ ^[a-zA-Z0-9.-]+:[0-9]+$ ]]; then
        print_error "Invalid domain format. Expected: domain.com:port"
        return 1
    fi

    print_header "Checking REALITY Destination: $domain_with_port"
    echo ""

    local passed=0
    local total=4

    # Run checks
    if check_accessibility "$host" "$port"; then
        ((passed++))
    fi

    if check_tls_version "$host" "$port"; then
        ((passed++))
    fi

    if check_http2_support "$host" "$port"; then
        ((passed++))
    fi

    if check_no_redirects "$host" "$port"; then
        ((passed++))
    fi

    echo ""
    print_separator

    # Summary
    if [ "$passed" -eq "$total" ]; then
        print_success "✓ ALL CHECKS PASSED ($passed/$total) - Domain is suitable for REALITY"
        return 0
    elif [ "$passed" -ge 3 ]; then
        print_warning "⚠ MOSTLY PASSED ($passed/$total) - Domain is acceptable but not optimal"
        return 0
    else
        print_error "✗ CHECKS FAILED ($passed/$total) - Domain is NOT suitable for REALITY"
        return 1
    fi
}

# Check all trusted domains
check_all_domains() {
    print_header "Checking All Trusted REALITY Domains"
    echo ""

    local total_domains=${#TRUSTED_DOMAINS[@]}
    local passed_domains=0

    for domain in "${TRUSTED_DOMAINS[@]}"; do
        echo ""
        if check_domain "$domain"; then
            ((passed_domains++))
        fi
        echo ""
        print_separator
    done

    echo ""
    print_header "Summary"
    echo ""
    echo "Total domains checked: $total_domains"
    echo "Passed domains: $passed_domains"
    echo "Failed domains: $((total_domains - passed_domains))"
    echo ""

    if [ "$passed_domains" -eq "$total_domains" ]; then
        print_success "All domains passed checks!"
        return 0
    else
        print_warning "Some domains failed checks"
        return 1
    fi
}

# Interactive mode
interactive_check() {
    print_header "REALITY Destination Domain Checker"
    echo ""
    echo "What would you like to do?"
    echo ""
    echo "  1) Check a specific domain"
    echo "  2) Check all trusted domains from lib/domains.sh"
    echo "  3) List trusted domains"
    echo "  0) Exit"
    echo ""

    read -p "Select option [0-3]: " choice

    case "$choice" in
        1)
            echo ""
            read -p "Enter domain to check (format: domain.com:443): " domain
            echo ""
            check_domain "$domain"
            ;;
        2)
            echo ""
            check_all_domains
            ;;
        3)
            echo ""
            list_trusted_domains
            ;;
        0)
            print_success "Exiting"
            exit 0
            ;;
        *)
            print_error "Invalid selection"
            exit 1
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════

main() {
    # Check requirements
    if ! check_requirements; then
        exit 1
    fi

    # Parse arguments
    if [ $# -eq 0 ]; then
        # No arguments - interactive mode
        interactive_check
    elif [ "$1" = "--all" ] || [ "$1" = "-a" ]; then
        # Check all domains
        check_all_domains
    elif [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        # Show help
        echo "Usage: $0 [OPTIONS] [DOMAIN:PORT]"
        echo ""
        echo "Options:"
        echo "  --all, -a          Check all trusted domains from lib/domains.sh"
        echo "  --help, -h         Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0                           # Interactive mode"
        echo "  $0 speed.cloudflare.com:443  # Check specific domain"
        echo "  $0 --all                     # Check all trusted domains"
        exit 0
    else
        # Check specific domain
        check_domain "$1"
    fi
}

# Run main function
main "$@"