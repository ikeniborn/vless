#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
# VLESS Fake Site Setup Script
# ═══════════════════════════════════════════════════════════════════
# Создает и настраивает fake веб-сервер для fallback механизма REALITY
#
# Использование:
#   ./setup-fake-site.sh                 # Интерактивная установка
#   ./setup-fake-site.sh --auto          # Автоматическая установка
#   ./setup-fake-site.sh --remove        # Удаление fake site
# ═══════════════════════════════════════════════════════════════════

set -euo pipefail

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Load libraries
source "${SCRIPT_DIR}/lib/colors.sh"
source "${SCRIPT_DIR}/lib/utils.sh"

# Configuration
VLESS_HOME="${VLESS_HOME:-/opt/vless}"
FAKE_SITE_DIR="$VLESS_HOME/fake-site"
FAKE_HTML_DIR="$FAKE_SITE_DIR/html"
FAKE_NGINX_CONF="$FAKE_SITE_DIR/nginx.conf"
FAKE_INDEX_HTML="$FAKE_HTML_DIR/index.html"
DOCKER_COMPOSE_FAKE="$VLESS_HOME/docker-compose.fake.yml"

# ═══════════════════════════════════════════════════════════════════
# FUNCTIONS
# ═══════════════════════════════════════════════════════════════════

# Create fake site directory structure
create_fake_site_structure() {
    print_step "Creating fake site directory structure"

    mkdir -p "$FAKE_HTML_DIR"
    chmod 755 "$FAKE_SITE_DIR"
    chmod 755 "$FAKE_HTML_DIR"

    print_success "Directory structure created"
}

# Create HTML index page
create_index_html() {
    print_step "Creating fake website HTML"

    cat > "$FAKE_INDEX_HTML" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Site Under Construction</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            color: #fff;
        }

        .container {
            text-align: center;
            padding: 2rem;
            max-width: 600px;
        }

        h1 {
            font-size: 3rem;
            margin-bottom: 1rem;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }

        p {
            font-size: 1.2rem;
            margin-bottom: 2rem;
            opacity: 0.9;
        }

        .icon {
            font-size: 5rem;
            margin-bottom: 2rem;
        }

        .info {
            background: rgba(255,255,255,0.1);
            padding: 1rem;
            border-radius: 8px;
            backdrop-filter: blur(10px);
            margin-top: 2rem;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="icon">🚧</div>
        <h1>Under Construction</h1>
        <p>This site is currently undergoing maintenance. Please check back later.</p>
        <div class="info">
            <p style="font-size: 0.9rem; opacity: 0.7;">
                Expected completion: Soon™
            </p>
        </div>
    </div>
</body>
</html>
EOF

    chmod 644 "$FAKE_INDEX_HTML"
    print_success "HTML page created"
}

# Create nginx configuration
create_nginx_config() {
    print_step "Creating nginx configuration"

    cat > "$FAKE_NGINX_CONF" << 'EOF'
user  nginx;
worker_processes  auto;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;
    keepalive_timeout  65;
    types_hash_max_size 2048;
    server_tokens off;

    gzip  on;
    gzip_vary on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;

    server {
        listen       80;
        server_name  localhost;

        root   /usr/share/nginx/html;
        index  index.html;

        # Main page
        location / {
            try_files $uri $uri/ =404;
        }

        # Fake API endpoints (return 503 Service Unavailable)
        location /api/ {
            return 503 '{"error":"Service temporarily unavailable","code":503}';
            add_header Content-Type application/json;
        }

        # Fake static resources
        location /static/ {
            return 404;
        }

        # Fake admin panel (return 403 Forbidden)
        location /admin/ {
            return 403 '{"error":"Access forbidden","code":403}';
            add_header Content-Type application/json;
        }

        # Health check endpoint
        location /health {
            access_log off;
            return 200 "OK\n";
            add_header Content-Type text/plain;
        }

        # Deny access to hidden files
        location ~ /\. {
            deny all;
            access_log off;
            log_not_found off;
        }

        error_page  404              /404.html;
        error_page  500 502 503 504  /50x.html;

        location = /404.html {
            root   /usr/share/nginx/html;
            internal;
        }

        location = /50x.html {
            root   /usr/share/nginx/html;
            internal;
        }
    }
}
EOF

    chmod 644 "$FAKE_NGINX_CONF"
    print_success "Nginx configuration created"
}

# Copy docker-compose.fake.yml
copy_docker_compose() {
    print_step "Copying docker-compose configuration"

    local template_file="$REPO_DIR/templates/docker-compose.fake.yml"

    if [ ! -f "$template_file" ]; then
        print_error "Template file not found: $template_file"
        return 1
    fi

    cp "$template_file" "$DOCKER_COMPOSE_FAKE"
    chmod 644 "$DOCKER_COMPOSE_FAKE"

    print_success "Docker Compose configuration copied"
}

# Start fake site container
start_fake_site() {
    print_step "Starting fake site container"

    cd "$VLESS_HOME"

    # Stop if already running
    docker-compose -f "$DOCKER_COMPOSE_FAKE" down 2>/dev/null || true

    # Start container
    if docker-compose -f "$DOCKER_COMPOSE_FAKE" up -d; then
        print_success "Fake site container started"
        return 0
    else
        print_error "Failed to start fake site container"
        return 1
    fi
}

# Check if fake site is accessible
check_fake_site() {
    print_step "Checking fake site accessibility"

    local max_attempts=5
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        # Check container health
        if docker ps --filter "name=vless-fake-site" --filter "status=running" | grep -q "vless-fake-site"; then
            print_success "Fake site container is running"
            print_info "Container: vless-fake-site"
            print_info "Network: vless-network (shared with xray-server)"
            print_info "Internal endpoint: vless-fake-site:80"
            return 0
        fi

        print_info "Waiting for fake site to start (attempt $attempt/$max_attempts)..."
        sleep 2
        ((attempt++))
    done

    print_error "Fake site container is not running after $max_attempts attempts"
    return 1
}

# Remove fake site
remove_fake_site() {
    print_header "Removing Fake Site"
    echo ""

    # Stop container
    if [ -f "$DOCKER_COMPOSE_FAKE" ]; then
        print_step "Stopping fake site container"
        cd "$VLESS_HOME"
        docker-compose -f "$DOCKER_COMPOSE_FAKE" down 2>/dev/null || true
        print_success "Container stopped"
    fi

    # Remove files
    print_step "Removing fake site files"
    rm -rf "$FAKE_SITE_DIR"
    rm -f "$DOCKER_COMPOSE_FAKE"
    print_success "Files removed"

    echo ""
    print_success "Fake site removed successfully"
}

# Install fake site
install_fake_site() {
    print_header "Setting Up Fake Site for REALITY Fallback"
    echo ""

    # Check if Docker is available
    if ! command_exists docker; then
        print_error "Docker is not installed"
        return 1
    fi

    if ! command_exists docker-compose; then
        print_error "Docker Compose is not installed"
        return 1
    fi

    # Create structure
    create_fake_site_structure

    # Create HTML and nginx config
    create_index_html
    create_nginx_config

    # Copy docker-compose
    copy_docker_compose

    # Start container
    start_fake_site

    # Check accessibility
    sleep 3
    check_fake_site

    echo ""
    print_success "Fake site setup completed!"
    echo ""
    print_info "Container: vless-fake-site"
    print_info "Network: vless-network (shared with xray-server)"
    print_info "Internal endpoint: vless-fake-site:80"
    print_info "Configuration: $FAKE_SITE_DIR"
    print_info "Docker Compose: $DOCKER_COMPOSE_FAKE"
    echo ""
    print_warning "Note: Fake site is only accessible from within Docker network"
    print_info "      It will respond to fallback requests from xray-server"
}

# ═══════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════

main() {
    # Parse arguments
    if [ $# -eq 0 ]; then
        # No arguments - interactive mode
        print_header "Fake Site Setup"
        echo ""
        echo "This script will create a fake website for REALITY fallback mechanism."
        echo ""
        read -p "Do you want to continue? [Y/n]: " choice

        if [[ "$choice" =~ ^[Nn]$ ]]; then
            print_info "Installation cancelled"
            exit 0
        fi

        install_fake_site
    elif [ "$1" = "--auto" ]; then
        # Automatic installation
        install_fake_site
    elif [ "$1" = "--remove" ]; then
        # Remove fake site
        remove_fake_site
    elif [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        # Show help
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --auto             Automatic installation without prompts"
        echo "  --remove           Remove fake site"
        echo "  --help, -h         Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0                 # Interactive installation"
        echo "  $0 --auto          # Automatic installation"
        echo "  $0 --remove        # Remove fake site"
        exit 0
    else
        print_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
    fi
}

# Run main function
main "$@"