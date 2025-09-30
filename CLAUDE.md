# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

VLESS+Reality VPN service using Xray-core in Docker with bash-based CLI management system. The project is designed for personal use (up to 50 users) with focus on simplicity and automation.

## Architecture

### Two-Part Structure
1. **Git Repository** (`/vless/`) - Contains scripts, templates, documentation
2. **Working Directory** (`/opt/vless/`) - Created during installation, contains runtime data, configs, and user data

### Key Components
- **Xray-core Container**: Main VPN server running in Docker (teddysun/xray:latest)
- **REALITY Protocol**: Traffic obfuscation using TLS masquerading
- **X25519 Cryptography**: Key generation and management for REALITY
- **Interactive CLI Menus**: All management scripts have both menu and direct command modes
- **DNS Configuration**: Customizable DNS servers during installation (Google, Cloudflare, Quad9, or custom)

## Common Development Commands

### Testing Installation
```bash
# Test install script locally (without running)
bash -n scripts/install.sh

# Validate template processing
source scripts/lib/colors.sh scripts/lib/config.sh
apply_template "templates/config.json.tpl" "/tmp/test.json" "ADMIN_UUID=test-uuid" "REALITY_DEST=speed.cloudflare.com:443"
```

### Docker Management
```bash
# All docker operations use docker-compose (not docker compose)
cd /opt/vless
docker-compose down
docker-compose up -d
docker-compose logs xray-server
```

### Script Dependencies
All scripts source dependencies in this order:
1. `lib/colors.sh` - Terminal colors and formatting
2. `lib/utils.sh` - Common utility functions
3. `lib/config.sh` - Configuration management
4. `lib/domains.sh` - REALITY target domains list

### Key Functions in lib/config.sh
- `apply_template()` - Replaces {{VARIABLE}} in templates with values (uses sed escaping)
- `generate_x25519_keys()` - Creates private/public key pair using xray container
- `add_user_to_config()` - Updates config.json with new user
- `restart_xray_service()` - Safe restart with docker-compose

### Key Functions in lib/utils.sh
#### Symlink Management
- `validate_symlink()` - Validates symlink existence, target, and executability
- `test_command_availability()` - Tests if command is available in PATH for root/current user
- `ensure_in_path()` - Ensures directory is added to PATH in shell rc files
- `create_robust_symlink()` - Creates symlinks with comprehensive validation

#### Firewall Management (Added for host network mode)
- `check_ufw_status()` - Checks if UFW is installed and active
- `ensure_ufw_rule()` - Adds UFW allow rule for specified port if not exists
- `configure_firewall_for_vless()` - Main function to configure firewall for VLESS service

## Critical Implementation Details

### Template Processing
The `apply_template` function uses sed to replace {{VARIABLE}} placeholders. Special characters in values are escaped with `sed 's/[\/&]/\\&/g'` to prevent sed errors.

### UUID and Short ID Generation
- **UUID**: `uuidgen` command (standard Linux utility)
- **Short ID**: `openssl rand -hex 4` (8 hex characters)
- Both are auto-generated, never user-provided

### DNS Configuration (Added 2025-09-29)
During installation, users can select DNS servers:
- **Google DNS**: 8.8.8.8, 8.8.4.4
- **Cloudflare DNS**: 1.1.1.1, 1.0.0.1
- **Quad9 DNS**: 9.9.9.9, 149.112.112.112
- **System Default**: Uses system-configured DNS (no custom configuration)
- **Custom DNS**: User-specified primary and optional secondary servers

DNS configuration is stored in `.env` file and applied to Xray config when custom DNS is selected.
Template selection is automatic: `config_with_dns.json.tpl` for custom DNS, original template for system default.

### User Data Structure
Users stored in `/opt/vless/data/users.json`:
```json
{
  "users": [
    {
      "name": "username",
      "uuid": "uuid-here",
      "short_id": "8-hex-chars",
      "created_at": "ISO-8601-date"
    }
  ]
}
```

### Config Updates
When adding/removing users:
1. Update `users.json` database
2. Modify `config.json` (clients array and shortIds array)
3. Restart xray service via docker-compose

### QR Code Generation
- Uses `qrencode` command
- PNG output: 640x640 pixels
- Stored in `/opt/vless/data/qr_codes/`
- vless:// URL format includes all connection parameters

## Testing Scripts

### Syntax Validation
```bash
# Check all scripts for syntax errors
for script in scripts/*.sh scripts/lib/*.sh; do
    bash -n "$script" && echo " $script" || echo " $script"
done
```

### Function Testing
```bash
# Test key generation (requires Docker)
source scripts/lib/*.sh
generate_x25519_keys
```

## Important Paths and Variables

### Environment Variable
`VLESS_HOME="${VLESS_HOME:-/opt/vless}"` - Base directory for all operations

### Critical Files
- `$VLESS_HOME/config/config.json` - Xray configuration (mode 600)
- `$VLESS_HOME/data/users.json` - User database (mode 600)
- `$VLESS_HOME/data/keys/` - X25519 keys (mode 700 dir, 600 files)
- `$VLESS_HOME/.env` - Environment variables (mode 600)

### Docker Volumes
```yaml
volumes:
  - ./config:/etc/xray:ro  # Read-only config mount
  - ./logs:/var/log/xray    # Writable logs
  - ./data:/data:ro         # Read-only data
```

## Error Handling Patterns

All scripts follow this pattern:
1. Set error handling: `set -euo pipefail`
2. Check prerequisites with `command_exists` function
3. Validate paths/files before operations
4. Use `print_error` for user-facing errors
5. Return non-zero exit codes on failure

## Menu System Implementation

Interactive menus use `select` with these conventions:
- Option arrays defined at script start
- "Exit/Back" always last option
- Input validation with case statements
- Clear screen between menu transitions
- Confirmation prompts for destructive operations

## Security Considerations

### File Permissions
Set automatically by scripts:
- Sensitive files (keys, .env, configs): 600
- Scripts: 750
- Data directories: 700
- Public directories: 755

### Docker Security
- Container runs with UID 1000
- Config mounted read-only
- No privileged mode required
- Network mode: host (bypasses Docker NAT issues, binds directly to port 443)

## Common Issues and Solutions

### Network Mode (Host vs Bridge)
**Issue:** Docker bridge network may fail to route traffic on some servers
**Solution:** Using `network_mode: host` in docker-compose.yml
- Container binds directly to host port 443
- Bypasses Docker NAT translation issues
- Better performance and real client IPs visible
- UFW firewall rules automatically configured during installation

### sed Expression Errors
Fixed in `lib/config.sh:167` - split complex sed command into pipeline:
- Changed from: `sed 's/\\/\\\\/g; s/\//\\\//g; s/&/\\&/g'` (caused "unterminated `s' command" error)
- Changed to: `sed 's/\\/\\\\/g' | sed 's/\//\\\//g' | sed 's/&/\\&/g'`
- Each sed command now runs separately in pipeline, avoiding parsing issues with semicolons

### Docker Compose Version
Always use `docker-compose` (hyphenated), not `docker compose` (space)

### Key Generation Failures
Requires Docker running and teddysun/xray image accessible

### Port 443 Conflicts
Check with `netstat -tlnp | grep 443` before installation

### Permission Issues (Fixed)
If vless commands show "lib/colors.sh: No such file or directory" or "Permission denied":
- Run: `sudo /opt/vless/scripts/fix-permissions.sh`
- This sets proper permissions for read-only operations without sudo
- Read operations (list users, view logs) work without sudo
- Write operations (add/remove users, clear logs) require sudo
- Scripts include fallback library loading mechanisms
- All scripts have been updated with selective root requirements

### Symlink Issues (Enhanced)
If vless commands are not found or symlinks don't work for root:
- Run: `sudo /opt/vless/scripts/fix-symlinks.sh` to repair symlinks
- Or run: `sudo /home/ikeniborn/Documents/Project/vless/scripts/reinstall.sh` for clean reinstall
- Commands are available in two locations:
  - Primary: `/usr/local/bin/vless-*` (symlinks)
  - Fallback: `/usr/bin/vless-*` (wrapper scripts)
- Installation automatically adds `/usr/local/bin` to root's PATH
- If commands still not found after fix: `source /etc/profile` or restart shell