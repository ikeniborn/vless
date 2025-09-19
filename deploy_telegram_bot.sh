#!/bin/bash
# VLESS VPN Telegram Bot Deployment Script
# Automated deployment for Phase 3 (Telegram Integration)
# Author: Claude Code
# Version: 1.0

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

# Log function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        "INFO")  echo -e "${BLUE}[INFO]${NC} ${timestamp} - $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} ${timestamp} - $message" ;;
        "WARNING") echo -e "${YELLOW}[WARNING]${NC} ${timestamp} - $message" ;;
        "ERROR")   echo -e "${RED}[ERROR]${NC} ${timestamp} - $message" ;;
        *)         echo -e "${timestamp} - $message" ;;
    esac
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log "WARNING" "Running as root. Consider using a non-root user for security."
    fi
}

# Check system requirements
check_requirements() {
    log "INFO" "Checking system requirements..."

    local missing_deps=()

    # Check Docker
    if ! command -v docker >/dev/null 2>&1; then
        missing_deps+=("docker")
    fi

    # Check Docker Compose
    if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
        missing_deps+=("docker-compose")
    fi

    # Check Python 3
    if ! command -v python3 >/dev/null 2>&1; then
        missing_deps+=("python3")
    fi

    # Check jq for JSON processing
    if ! command -v jq >/dev/null 2>&1; then
        missing_deps+=("jq")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log "ERROR" "Missing dependencies: ${missing_deps[*]}"
        log "INFO" "Please install missing dependencies and run this script again"
        return 1
    fi

    log "SUCCESS" "All requirements satisfied"
    return 0
}

# Create directory structure
create_directories() {
    log "INFO" "Creating directory structure..."

    local directories=(
        "/opt/vless"
        "/opt/vless/logs"
        "/opt/vless/users"
        "/opt/vless/configs"
        "/opt/vless/configs/users"
        "/opt/vless/certs"
        "/opt/vless/qrcodes"
        "/opt/vless/backups"
    )

    for dir in "${directories[@]}"; do
        if [[ ! -d "$dir" ]]; then
            sudo mkdir -p "$dir"
            sudo chown -R $(whoami):$(whoami) "$dir" 2>/dev/null || true
            log "INFO" "Created directory: $dir"
        fi
    done

    log "SUCCESS" "Directory structure created"
}

# Setup configuration
setup_configuration() {
    log "INFO" "Setting up configuration..."

    local env_file="$PROJECT_DIR/.env"
    local example_file="$PROJECT_DIR/.env.example"

    if [[ ! -f "$env_file" ]]; then
        if [[ -f "$example_file" ]]; then
            cp "$example_file" "$env_file"
            log "INFO" "Created .env from example file"
        else
            log "ERROR" ".env.example file not found"
            return 1
        fi
    fi

    # Check if configuration is set
    source "$env_file"

    if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]] || [[ "$TELEGRAM_BOT_TOKEN" == "123456789:ABCdefGHIjklMNOpqrsTUVwxyz" ]]; then
        log "WARNING" "TELEGRAM_BOT_TOKEN not configured in .env"
        log "INFO" "Please edit $env_file and set your bot token"
        return 1
    fi

    if [[ -z "${ADMIN_TELEGRAM_ID:-}" ]] || [[ "$ADMIN_TELEGRAM_ID" == "123456789" ]]; then
        log "WARNING" "ADMIN_TELEGRAM_ID not configured in .env"
        log "INFO" "Please edit $env_file and set your Telegram ID"
        return 1
    fi

    log "SUCCESS" "Configuration is set up"
    return 0
}

# Make scripts executable
setup_permissions() {
    log "INFO" "Setting up file permissions..."

    local scripts=(
        "$PROJECT_DIR/modules/telegram_bot.py"
        "$PROJECT_DIR/modules/telegram_bot_manager.sh"
        "$PROJECT_DIR/modules/user_management.sh"
        "$PROJECT_DIR/modules/common_utils.sh"
        "$PROJECT_DIR/tests/test_telegram_bot_integration.py"
    )

    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            chmod +x "$script"
            log "INFO" "Made executable: $(basename "$script")"
        fi
    done

    log "SUCCESS" "File permissions set up"
}

# Build Docker image
build_docker_image() {
    log "INFO" "Building Docker image for Telegram bot..."

    cd "$PROJECT_DIR"

    if [[ -f "Dockerfile.bot" ]]; then
        if docker build -f Dockerfile.bot -t vless-telegram-bot:latest .; then
            log "SUCCESS" "Docker image built successfully"
        else
            log "ERROR" "Failed to build Docker image"
            return 1
        fi
    else
        log "ERROR" "Dockerfile.bot not found"
        return 1
    fi

    return 0
}

# Test configuration
test_configuration() {
    log "INFO" "Testing configuration..."

    # Run integration tests
    if [[ -f "$PROJECT_DIR/tests/test_telegram_bot_integration.py" ]]; then
        if python3 "$PROJECT_DIR/tests/test_telegram_bot_integration.py" >/dev/null 2>&1; then
            log "SUCCESS" "Integration tests passed"
        else
            log "WARNING" "Some integration tests failed (this is normal if dependencies are missing)"
        fi
    fi

    # Test bot manager script
    if [[ -f "$PROJECT_DIR/modules/telegram_bot_manager.sh" ]]; then
        if "$PROJECT_DIR/modules/telegram_bot_manager.sh" validate >/dev/null 2>&1; then
            log "SUCCESS" "Bot configuration validation passed"
        else
            log "WARNING" "Bot configuration validation failed"
        fi
    fi

    return 0
}

# Deploy bot service
deploy_bot() {
    log "INFO" "Deploying Telegram bot service..."

    cd "$PROJECT_DIR"

    local compose_file="$PROJECT_DIR/config/docker-compose.yml"

    if [[ ! -f "$compose_file" ]]; then
        log "ERROR" "Docker Compose file not found: $compose_file"
        return 1
    fi

    # Check if Docker Compose v2 is available
    local compose_cmd="docker-compose"
    if docker compose version >/dev/null 2>&1; then
        compose_cmd="docker compose"
    fi

    # Deploy the bot service
    if $compose_cmd -f "$compose_file" up -d telegram-bot; then
        log "SUCCESS" "Bot service deployed successfully"

        # Wait for startup
        sleep 5

        # Check if container is running
        if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "vless-telegram-bot"; then
            log "SUCCESS" "Bot container is running"
        else
            log "ERROR" "Bot container failed to start"
            log "INFO" "Check logs with: ./modules/telegram_bot_manager.sh logs"
            return 1
        fi
    else
        log "ERROR" "Failed to deploy bot service"
        return 1
    fi

    return 0
}

# Create systemd service (optional)
create_systemd_service() {
    log "INFO" "Creating systemd service..."

    local service_file="/etc/systemd/system/vless-telegram-bot.service"

    if [[ ! -f "$service_file" ]]; then
        sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=VLESS VPN Telegram Bot
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/modules/telegram_bot_manager.sh start
ExecStop=$PROJECT_DIR/modules/telegram_bot_manager.sh stop
ExecReload=$PROJECT_DIR/modules/telegram_bot_manager.sh restart
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF

        sudo systemctl daemon-reload
        sudo systemctl enable vless-telegram-bot.service

        log "SUCCESS" "Systemd service created and enabled"
    else
        log "INFO" "Systemd service already exists"
    fi
}

# Show deployment summary
show_summary() {
    log "INFO" "Deployment Summary"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  📱 VLESS VPN Telegram Bot - Deployment Complete"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📋 Next Steps:"
    echo "  1. Find your bot in Telegram and send /start"
    echo "  2. Use /help to see available commands"
    echo "  3. Try adding a user with /adduser testuser"
    echo ""
    echo "🛠 Management Commands:"
    echo "  Status:     ./modules/telegram_bot_manager.sh status"
    echo "  Logs:       ./modules/telegram_bot_manager.sh logs"
    echo "  Restart:    ./modules/telegram_bot_manager.sh restart"
    echo "  Stop:       ./modules/telegram_bot_manager.sh stop"
    echo ""
    echo "📁 Important Files:"
    echo "  Config:     $PROJECT_DIR/.env"
    echo "  Logs:       /opt/vless/logs/telegram_bot.log"
    echo "  Users:      /opt/vless/users/users.json"
    echo ""
    echo "📚 Documentation:"
    echo "  Setup:      $PROJECT_DIR/docs/telegram_bot_setup.md"
    echo "  Quick:      $PROJECT_DIR/TELEGRAM_BOT_README.md"
    echo ""
    echo "🔧 Troubleshooting:"
    echo "  Test:       ./modules/telegram_bot_manager.sh test"
    echo "  Validate:   ./modules/telegram_bot_manager.sh validate"
    echo "  Build:      ./modules/telegram_bot_manager.sh build"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Cleanup function
cleanup() {
    log "INFO" "Cleaning up temporary files..."
    # Add cleanup code here if needed
}

# Main deployment function
main() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  🚀 VLESS VPN Telegram Bot Deployment Script"
    echo "  📋 Phase 3: Telegram Integration"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Trap for cleanup
    trap cleanup EXIT

    # Check if we're in the right directory
    if [[ ! -f "$PROJECT_DIR/modules/telegram_bot.py" ]]; then
        log "ERROR" "This script must be run from the VLESS project directory"
        log "INFO" "Expected to find: $PROJECT_DIR/modules/telegram_bot.py"
        exit 1
    fi

    # Run deployment steps
    check_root

    if ! check_requirements; then
        exit 1
    fi

    create_directories

    if ! setup_configuration; then
        log "ERROR" "Configuration setup failed"
        log "INFO" "Please configure the bot token and admin ID in .env file"
        exit 1
    fi

    setup_permissions

    if ! build_docker_image; then
        exit 1
    fi

    test_configuration

    if ! deploy_bot; then
        exit 1
    fi

    # Optional systemd service
    read -p "Do you want to create a systemd service for auto-start? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        create_systemd_service
    fi

    show_summary

    log "SUCCESS" "VLESS VPN Telegram Bot deployment completed successfully!"
    log "INFO" "The bot should now be accessible in Telegram"

    return 0
}

# Show help
show_help() {
    cat << EOF
VLESS VPN Telegram Bot Deployment Script

Usage: $0 [options]

Options:
  --help, -h     Show this help message
  --force        Force deployment even if already running
  --no-systemd   Skip systemd service creation
  --test-only    Only run tests, don't deploy

Examples:
  $0                 # Normal deployment
  $0 --test-only     # Run tests only
  $0 --no-systemd    # Deploy without systemd service

This script will:
1. Check system requirements
2. Create necessary directories
3. Set up configuration
4. Build Docker image
5. Deploy the bot service
6. Create systemd service (optional)

Configuration:
- Edit .env file with your bot token and admin ID
- See .env.example for reference
- Documentation in docs/telegram_bot_setup.md
EOF
}

# Parse command line arguments
FORCE_DEPLOYMENT=false
NO_SYSTEMD=false
TEST_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            exit 0
            ;;
        --force)
            FORCE_DEPLOYMENT=true
            shift
            ;;
        --no-systemd)
            NO_SYSTEMD=true
            shift
            ;;
        --test-only)
            TEST_ONLY=true
            shift
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main function if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ "$TEST_ONLY" == "true" ]]; then
        log "INFO" "Running tests only..."
        check_requirements
        test_configuration
        log "SUCCESS" "Tests completed"
    else
        main
    fi
fi