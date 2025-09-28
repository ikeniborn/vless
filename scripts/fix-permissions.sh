#!/bin/bash

# Fix permissions for VLESS installation
# This script sets proper permissions according to PRD.md requirements
# Must be run with sudo

set -euo pipefail

VLESS_HOME="${VLESS_HOME:-/opt/vless}"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run with sudo" 
   exit 1
fi

# Check if VLESS is installed
if [ ! -d "$VLESS_HOME" ]; then
    echo "Error: VLESS directory not found at $VLESS_HOME"
    echo "Please install VLESS first using install.sh"
    exit 1
fi

echo "Fixing permissions for VLESS installation..."

# Set directory permissions according to PRD.md section 5.4
echo "Setting directory permissions..."

# Root directory - accessible for all
chmod 755 "$VLESS_HOME"

# Scripts directory - public read and execute for all users
# This allows normal users to run the scripts
if [ -d "$VLESS_HOME/scripts" ]; then
    chmod 755 "$VLESS_HOME/scripts"
    chmod 755 "$VLESS_HOME/scripts/lib" 2>/dev/null || true
    
    # Make all scripts executable and readable
    find "$VLESS_HOME/scripts" -name "*.sh" -type f -exec chmod 755 {} \;
    
    # Library files also need to be readable
    if [ -d "$VLESS_HOME/scripts/lib" ]; then
        chmod 644 "$VLESS_HOME/scripts/lib"/*.sh 2>/dev/null || true
    fi
fi

# Config directory - restricted but readable for services
if [ -d "$VLESS_HOME/config" ]; then
    chmod 750 "$VLESS_HOME/config"
    
    # Sensitive config files
    [ -f "$VLESS_HOME/config/config.json" ] && chmod 600 "$VLESS_HOME/config/config.json"
    [ -f "$VLESS_HOME/config/config.json.template" ] && chmod 644 "$VLESS_HOME/config/config.json.template"
fi

# Data directory - most restricted
if [ -d "$VLESS_HOME/data" ]; then
    chmod 700 "$VLESS_HOME/data"
    
    # Keys subdirectory
    [ -d "$VLESS_HOME/data/keys" ] && chmod 700 "$VLESS_HOME/data/keys"
    
    # Sensitive data files
    [ -f "$VLESS_HOME/data/users.json" ] && chmod 600 "$VLESS_HOME/data/users.json"
    
    # All key files
    find "$VLESS_HOME/data/keys" -type f -exec chmod 600 {} \; 2>/dev/null || true
    
    # QR codes directory
    [ -d "$VLESS_HOME/data/qr_codes" ] && chmod 755 "$VLESS_HOME/data/qr_codes"
fi

# Backups directory - restricted
if [ -d "$VLESS_HOME/backups" ]; then
    chmod 700 "$VLESS_HOME/backups"
fi

# Logs directory - readable for monitoring
if [ -d "$VLESS_HOME/logs" ]; then
    chmod 755 "$VLESS_HOME/logs"
fi

# Docs directory - public
if [ -d "$VLESS_HOME/docs" ]; then
    chmod 755 "$VLESS_HOME/docs"
fi

# Templates directory - public read
if [ -d "$VLESS_HOME/templates" ]; then
    chmod 755 "$VLESS_HOME/templates"
    chmod 644 "$VLESS_HOME/templates"/* 2>/dev/null || true
fi

# Environment file - most sensitive
[ -f "$VLESS_HOME/.env" ] && chmod 600 "$VLESS_HOME/.env"

# Docker-compose file
[ -f "$VLESS_HOME/docker-compose.yml" ] && chmod 644 "$VLESS_HOME/docker-compose.yml"

# Fix symlinks permissions (they should be accessible)
if [ -L "/usr/local/bin/vless-users" ]; then
    # Symlinks themselves don't need special permissions
    # but we ensure the target scripts are executable
    echo "Symlinks already exist in /usr/local/bin"
fi

echo "Permissions fixed successfully!"
echo ""
echo "Note: Regular users can now run vless commands for reading operations."
echo "Operations that modify data will still require sudo."
echo ""
echo "You can test with: vless-users (should work without sudo for listing users)"