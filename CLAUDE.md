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

# Test network.sh functions
bash -n scripts/lib/network.sh

# Validate template processing
source scripts/lib/colors.sh scripts/lib/config.sh
apply_template "templates/config.json.tpl" "/tmp/test.json" "ADMIN_UUID=test-uuid" "REALITY_DEST=speed.cloudflare.com:443"

# Check available Docker subnets
source scripts/lib/colors.sh scripts/lib/network.sh
find_available_docker_subnet
```

### Docker Management
```bash
# All docker operations use docker-compose (not docker compose)
cd /opt/vless
docker-compose down
docker-compose up -d
docker-compose logs xray-server

# Check Docker network
docker network ls
docker network inspect vless-reality_vless-network

# Verify network configuration
sysctl net.ipv4.ip_forward
iptables -t nat -L POSTROUTING -n
```

### Script Dependencies
All scripts source dependencies in this order:
1. `lib/colors.sh` - Terminal colors and formatting
2. `lib/utils.sh` - Common utility functions
3. `lib/domains.sh` - REALITY target domains list
4. `lib/config.sh` - Configuration management
5. `lib/network.sh` - Network configuration (IP forwarding, NAT, subnet detection)

### Key Functions in lib/config.sh
- `apply_template()` - Replaces {{VARIABLE}} in templates with values (uses sed escaping)
- `generate_x25519_keys()` - Creates private/public key pair using xray container
- `add_user_to_config()` - Updates config.json with new user
- `restart_xray_service()` - Safe restart with docker-compose

### Key Functions in lib/network.sh
#### Network Configuration (Added 2025-09-30)
- `find_available_docker_subnet()` - Finds free Docker subnet in 172.16-254.x.x range
- `enable_ip_forwarding()` - Enables and persists IP forwarding via sysctl
- `configure_nat_iptables()` - Sets up NAT MASQUERADE rules for Docker subnet
- `configure_ufw_for_docker()` - Configures UFW for Docker bridge network (adds NAT rules to /etc/ufw/before.rules)
- `configure_network_for_vless()` - Main function to configure all network settings
- `verify_network_configuration()` - Validates network setup
- `get_external_interface()` - Auto-detects external network interface
- `display_network_summary()` - Shows network configuration summary

### Key Functions in lib/utils.sh
#### Symlink Management
- `validate_symlink()` - Validates symlink existence, target, and executability
- `test_command_availability()` - Tests if command is available in PATH for root/current user
- `ensure_in_path()` - Ensures directory is added to PATH in shell rc files
- `create_robust_symlink()` - Creates symlinks with comprehensive validation

#### Firewall Management
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
- `$VLESS_HOME/.env` - Environment variables including Docker network config (mode 600)
- `/etc/sysctl.conf` - IP forwarding configuration
- `/etc/ufw/before.rules` - UFW NAT rules for Docker (if UFW is used)

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
- Network mode: bridge (isolated network with NAT)
- Port mapping configured via SERVER_PORT variable
- IP forwarding and NAT MASQUERADE automatically configured
- UFW rules automatically added for Docker bridge network

## Common Issues and Solutions

### Network Configuration and VPN Routing
**Issue:** VPN clients cannot access internet after connection
**Solution:** Bridge network mode with automatic NAT and IP forwarding configuration
- Installation automatically detects free Docker subnet (172.16-254.x.x/16)
- IP forwarding enabled via sysctl (`net.ipv4.ip_forward = 1`)
- NAT MASQUERADE configured via iptables for Docker subnet
- UFW automatically configured with NAT rules in /etc/ufw/before.rules
- Verification: `sysctl net.ipv4.ip_forward` should return 1
- Verification: `iptables -t nat -L POSTROUTING -n` should show MASQUERADE rule

**Troubleshooting:**
```bash
# Check IP forwarding
sysctl net.ipv4.ip_forward

# Check iptables NAT rules
iptables -t nat -L -n -v

# Check UFW configuration
cat /etc/ufw/before.rules | grep -A 10 "NAT table"

# Manually reconfigure network if needed
source /opt/vless/scripts/lib/network.sh
configure_network_for_vless "172.20.0.0/16" "443"
```

### sed Expression Errors
Fixed in `lib/config.sh:167` - split complex sed command into pipeline:
- Changed from: `sed 's/\\/\\\\/g; s/\//\\\//g; s/&/\\&/g'` (caused "unterminated `s' command" error)
- Changed to: `sed 's/\\/\\\\/g' | sed 's/\//\\\//g' | sed 's/&/\\&/g'`
- Each sed command now runs separately in pipeline, avoiding parsing issues with semicolons

### Docker Compose Version
Always use `docker-compose` (hyphenated), not `docker compose` (space)

### Docker Subnet Conflicts
**Issue:** Docker subnet 172.20.0.0/16 already in use
**Solution:** Installation automatically detects and uses free subnet
- Scans existing Docker networks for used subnets
- Selects first available subnet from 172.16-254.x.x/16 range
- Stores selected subnet in $VLESS_HOME/.env
- If all 172.x subnets are occupied, installation will fail with error

**Manual subnet change (if needed):**
```bash
# Edit .env file
nano /opt/vless/.env
# Change DOCKER_SUBNET and DOCKER_GATEWAY

# Recreate network
cd /opt/vless
docker-compose down
docker network rm vless-reality_vless-network
docker-compose up -d
```

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