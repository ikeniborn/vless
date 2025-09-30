#!/bin/bash

# Load colors if not already loaded
if [ -z "$NC" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"
fi

# ═══════════════════════════════════════════════════════════════════
# TRUSTED DOMAINS FOR REALITY
# ═══════════════════════════════════════════════════════════════════
#
# Критерии выбора доменов:
# 1. Поддержка TLSv1.3 и HTTP/2
# 2. Отсутствие редиректов (прямой HTTPS доступ)
# 3. Стабильная доступность 24/7 (99.9%+ uptime)
# 4. Вне юрисдикции цензурирующих стран
# 5. Высокий легитимный трафик (для эффективной маскировки)
# 6. Крупные корпоративные/популярные сайты с хорошей репутацией
#
# Формат: "domain.com:port"
# ═══════════════════════════════════════════════════════════════════

# Array of trusted domains for REALITY (with metadata)
declare -A DOMAIN_METADATA

# Primary recommended domains (проверены на соответствие всем критериям)
TRUSTED_DOMAINS=(
    "speed.cloudflare.com:443"      # CDN, очень высокий трафик, TLS 1.3, HTTP/2
    "www.microsoft.com:443"          # Крупный корп, стабильный, TLS 1.3, HTTP/2
    "www.apple.com:443"              # Крупный корп, стабильный, TLS 1.3, HTTP/2
    "github.com:443"                 # Популярный, высокий dev трафик, TLS 1.3, HTTP/2
    "www.cloudflare.com:443"         # CDN провайдер, отличная репутация, TLS 1.3, HTTP/2
    "stackoverflow.com:443"          # Высокий трафик разработчиков, TLS 1.3, HTTP/2
    "www.wikipedia.org:443"          # Нейтральный контент, глобальный, TLS 1.3, HTTP/2
)

# Дополнительные проверенные домены (альтернативы)
ALTERNATIVE_DOMAINS=(
    "www.google.com:443"
    "www.amazon.com:443"
    "www.bing.com:443"
    "www.yahoo.com:443"
    "gitlab.com:443"
    "www.youtube.com:443"
    "www.reddit.com:443"
)

# Метаданные доменов (для информации и проверок)
DOMAIN_METADATA["speed.cloudflare.com"]="TLS:1.3|HTTP2:yes|CDN:yes|Uptime:99.99%"
DOMAIN_METADATA["www.microsoft.com"]="TLS:1.3|HTTP2:yes|CDN:yes|Uptime:99.9%"
DOMAIN_METADATA["www.apple.com"]="TLS:1.3|HTTP2:yes|CDN:yes|Uptime:99.9%"
DOMAIN_METADATA["github.com"]="TLS:1.3|HTTP2:yes|CDN:yes|Uptime:99.95%"
DOMAIN_METADATA["www.cloudflare.com"]="TLS:1.3|HTTP2:yes|CDN:yes|Uptime:99.99%"
DOMAIN_METADATA["stackoverflow.com"]="TLS:1.3|HTTP2:yes|CDN:yes|Uptime:99.9%"
DOMAIN_METADATA["www.wikipedia.org"]="TLS:1.3|HTTP2:yes|CDN:yes|Uptime:99.95%"

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

# ═══════════════════════════════════════════════════════════════════
# NEW FUNCTION: Get random domain from trusted list
# ═══════════════════════════════════════════════════════════════════
# Возвращает случайный домен из массива TRUSTED_DOMAINS
# Использование: domain=$(get_random_domain)
# Формат возврата: "domain.com:443"
get_random_domain() {
    local array_size=${#TRUSTED_DOMAINS[@]}
    local random_index=$((RANDOM % array_size))
    echo "${TRUSTED_DOMAINS[$random_index]}"
}

# ═══════════════════════════════════════════════════════════════════
# NEW FUNCTION: Get domain metadata
# ═══════════════════════════════════════════════════════════════════
# Получить метаданные домена (TLS версия, HTTP/2, CDN, Uptime)
# Использование: get_domain_metadata "speed.cloudflare.com"
# Формат возврата: "TLS:1.3|HTTP2:yes|CDN:yes|Uptime:99.99%"
get_domain_metadata() {
    local domain_name=$1
    # Remove port if present
    domain_name="${domain_name%:*}"

    if [[ -n "${DOMAIN_METADATA[$domain_name]}" ]]; then
        echo "${DOMAIN_METADATA[$domain_name]}"
    else
        echo "No metadata available"
    fi
}

# ═══════════════════════════════════════════════════════════════════
# NEW FUNCTION: List all trusted domains with metadata
# ═══════════════════════════════════════════════════════════════════
# Выводит список всех проверенных доменов с их характеристиками
list_trusted_domains() {
    print_header "Trusted REALITY Domains"
    echo ""
    echo "Primary recommended domains (used in config templates):"
    echo ""

    local index=1
    for domain in "${TRUSTED_DOMAINS[@]}"; do
        local domain_name="${domain%:*}"
        local metadata=$(get_domain_metadata "$domain_name")
        printf "  %2d) %-30s %s\n" "$index" "$domain" "$metadata"
        ((index++))
    done

    echo ""
    echo "Alternative domains (can be used as fallbacks):"
    echo ""

    index=1
    for domain in "${ALTERNATIVE_DOMAINS[@]}"; do
        printf "  %2d) %s\n" "$index" "$domain"
        ((index++))
    done
}

# ═══════════════════════════════════════════════════════════════════
# NEW FUNCTION: Verify REALITY domain during installation
# ═══════════════════════════════════════════════════════════════════
# Упрощенная проверка домена для использования в install.sh
# Проверяет базовые требования: доступность, TLS 1.3, HTTP/2
# Возвращает 0 если все проверки прошли, 1 если есть проблемы
#
# Usage: verify_reality_domain "domain.com:443"
verify_reality_domain() {
    local domain_with_port=$1
    local host="${domain_with_port%:*}"
    local port="${domain_with_port##*:}"
    local timeout=10
    local checks_passed=0
    local checks_total=0

    # Check if required tools are available
    if ! command -v openssl >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
        print_warning "Verification tools not available (openssl/curl), skipping domain check"
        return 0  # Don't block installation
    fi

    print_info "Verifying REALITY destination domain..."
    echo ""

    # Check 1: Server accessibility
    ((checks_total++))
    echo -n "  → Checking server accessibility... "
    if timeout "$timeout" bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null; then
        echo -e "${GREEN}✓${NC}"
        ((checks_passed++))
    else
        echo -e "${RED}✗${NC}"
    fi

    # Check 2: TLS 1.3 support
    ((checks_total++))
    echo -n "  → Checking TLS 1.3 support... "
    if timeout "$timeout" openssl s_client -connect "$host:$port" -tls1_3 -servername "$host" </dev/null 2>&1 | grep -q "Protocol.*TLSv1.3"; then
        echo -e "${GREEN}✓${NC}"
        ((checks_passed++))
    else
        echo -e "${YELLOW}⚠${NC}"
    fi

    # Check 3: HTTP/2 support
    ((checks_total++))
    echo -n "  → Checking HTTP/2 support... "
    if timeout "$timeout" curl -sI --http2 --max-time "$timeout" "https://$host:$port" 2>&1 | grep -qi "HTTP/2"; then
        echo -e "${GREEN}✓${NC}"
        ((checks_passed++))
    else
        echo -e "${YELLOW}⚠${NC}"
    fi

    echo ""

    # Summary
    if [ "$checks_passed" -eq "$checks_total" ]; then
        print_success "Domain verification passed ($checks_passed/$checks_total checks)"
        return 0
    elif [ "$checks_passed" -ge 2 ]; then
        print_warning "Domain verification partially passed ($checks_passed/$checks_total checks)"
        echo ""
        print_info "The domain is accessible but may not support all optimal features."
        read -p "Continue with this domain? [Y/n]: " continue_choice
        if [[ "$continue_choice" =~ ^[Nn]$ ]]; then
            return 1
        fi
        return 0
    else
        print_error "Domain verification failed ($checks_passed/$checks_total checks)"
        echo ""
        print_warning "This domain may not be suitable for REALITY protocol."
        read -p "Continue anyway? [y/N]: " continue_choice
        if [[ "$continue_choice" =~ ^[Yy]$ ]]; then
            return 0
        fi
        return 1
    fi
}