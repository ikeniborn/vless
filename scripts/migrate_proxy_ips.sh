#!/bin/bash
#
# Migration Script: Per-User to Server-Level IP Whitelisting
# Version: 3.6
# Purpose: Migrate from per-user allowed_ips to server-level proxy_allowed_ips.json
#
# This script:
# 1. Checks if migration is needed
# 2. Collects unique IPs from all users' allowed_ips fields
# 3. Creates proxy_allowed_ips.json with collected IPs
# 4. Regenerates routing rules
# 5. Reloads Xray
# 6. Optionally removes allowed_ips field from users.json (cleanup)
#

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Paths
INSTALL_ROOT="/opt/vless"
CONFIG_DIR="${INSTALL_ROOT}/config"
DATA_DIR="${INSTALL_ROOT}/data"
LIB_DIR="${INSTALL_ROOT}/lib"

USERS_JSON="${DATA_DIR}/users.json"
PROXY_IPS_FILE="${CONFIG_DIR}/proxy_allowed_ips.json"

# Log functions
log_info() { echo -e "${CYAN}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Check root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   exit 1
fi

# Source proxy_whitelist module
if [[ -f "${LIB_DIR}/proxy_whitelist.sh" ]]; then
    source "${LIB_DIR}/proxy_whitelist.sh"
else
    log_error "proxy_whitelist.sh module not found: ${LIB_DIR}/proxy_whitelist.sh"
    exit 1
fi

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  MIGRATION: Per-User → Server-Level IP Whitelisting (v3.6) ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Step 1: Check if migration is needed
log_info "Checking migration requirements..."

if [[ -f "$PROXY_IPS_FILE" ]]; then
    log_warning "proxy_allowed_ips.json already exists - migration may have already run"
    echo "Existing file: $PROXY_IPS_FILE"
    echo ""
    echo "Options:"
    echo "  1. Skip migration (keep existing proxy_allowed_ips.json)"
    echo "  2. Overwrite with IPs from users.json"
    echo "  3. Abort"
    echo ""
    read -p "Select option [1/2/3]: " choice

    case "$choice" in
        1)
            log_info "Skipping migration, keeping existing file"
            exit 0
            ;;
        2)
            log_warning "Will overwrite existing proxy_allowed_ips.json"
            ;;
        *)
            log_info "Migration aborted by user"
            exit 0
            ;;
    esac
fi

if [[ ! -f "$USERS_JSON" ]]; then
    log_error "users.json not found: $USERS_JSON"
    exit 1
fi

# Step 2: Collect unique IPs from all users
log_info "Collecting IPs from users.json..."

# Check if any user has allowed_ips field
users_with_ips=$(jq '[.users[] | select(has("allowed_ips"))] | length' "$USERS_JSON" 2>/dev/null || echo "0")

if [[ "$users_with_ips" -eq 0 ]]; then
    log_warning "No users have allowed_ips field - nothing to migrate"
    log_info "Initializing proxy_allowed_ips.json with default (localhost only)"

    # Initialize with default
    init_proxy_whitelist

    log_success "Migration complete (default initialization)"
    exit 0
fi

log_info "Found $users_with_ips users with allowed_ips field"

# Collect all unique IPs from all users
all_ips=$(jq -r '[.users[] | select(has("allowed_ips")) | .allowed_ips[]] | unique | .[]' "$USERS_JSON" 2>/dev/null)

if [[ -z "$all_ips" ]]; then
    log_warning "No IPs found in allowed_ips fields"
    all_ips="127.0.0.1"  # Default to localhost
fi

# Count unique IPs
ip_count=$(echo "$all_ips" | wc -l)

echo ""
echo "Collected IPs (${ip_count} unique):"
echo "$all_ips" | while read -r ip; do
    echo "  • $ip"
done
echo ""

# Step 3: Create proxy_allowed_ips.json
log_info "Creating proxy_allowed_ips.json..."

# Convert IPs to JSON array
ips_array=$(echo "$all_ips" | jq -R . | jq -s .)

# Create proxy_allowed_ips.json
timestamp=$(date -Iseconds)
cat > "$PROXY_IPS_FILE" <<EOF
{
  "allowed_ips": ${ips_array},
  "metadata": {
    "created": "${timestamp}",
    "last_modified": "${timestamp}",
    "description": "Server-level IP whitelist for proxy access (migrated from per-user v3.5 to v3.6)",
    "migrated_from_version": "3.5",
    "migration_date": "${timestamp}"
  }
}
EOF

if [[ ! -f "$PROXY_IPS_FILE" ]]; then
    log_error "Failed to create proxy_allowed_ips.json"
    exit 1
fi

chmod 600 "$PROXY_IPS_FILE"
log_success "Created: $PROXY_IPS_FILE"

# Step 4: Regenerate routing rules
log_info "Regenerating Xray routing rules..."

if ! regenerate_proxy_routing; then
    log_error "Failed to regenerate routing rules"
    exit 1
fi

log_success "Routing rules regenerated"

# Step 5: Reload Xray
log_info "Reloading Xray..."

if ! docker compose -f "${INSTALL_ROOT}/docker-compose.yml" restart xray &>/dev/null; then
    log_error "Failed to reload Xray"
    exit 1
fi

sleep 2
log_success "Xray reloaded"

# Step 6: Cleanup (optional)
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  MIGRATION COMPLETE"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Server-level IP whitelist:"
echo "$all_ips" | while read -r ip; do
    echo "  • $ip"
done
echo ""
echo "Management commands:"
echo "  sudo vless show-proxy-ips         # Show current whitelist"
echo "  sudo vless add-proxy-ip <ip>      # Add IP to whitelist"
echo "  sudo vless remove-proxy-ip <ip>   # Remove IP from whitelist"
echo "  sudo vless reset-proxy-ips        # Reset to localhost only"
echo ""

# Ask about cleanup
read -p "Remove allowed_ips field from users.json (cleanup)? [y/N]: " cleanup

if [[ "${cleanup,,}" == "y" || "${cleanup,,}" == "yes" ]]; then
    log_info "Removing allowed_ips field from users.json..."

    # Create backup
    cp "$USERS_JSON" "${USERS_JSON}.bak.migration.$$"

    # Remove allowed_ips field from all users
    temp_file="${USERS_JSON}.tmp.$$"
    if jq '.users |= map(del(.allowed_ips))' "$USERS_JSON" > "$temp_file"; then
        # Validate JSON
        if jq empty "$temp_file" 2>/dev/null; then
            mv "$temp_file" "$USERS_JSON"
            chmod 600 "$USERS_JSON"
            log_success "Cleanup complete (backup: ${USERS_JSON}.bak.migration.$$)"
        else
            log_error "Generated invalid JSON during cleanup"
            rm -f "$temp_file"
            mv "${USERS_JSON}.bak.migration.$$" "$USERS_JSON"
        fi
    else
        log_error "Failed to remove allowed_ips field"
        rm -f "$temp_file"
    fi
else
    log_info "Skipping cleanup - allowed_ips field preserved in users.json"
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
log_success "Migration from v3.5 to v3.6 completed successfully"
echo "═══════════════════════════════════════════════════════════"
echo ""

exit 0
