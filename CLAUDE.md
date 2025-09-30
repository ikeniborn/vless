# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

VLESS+Reality VPN service using Xray-core in Docker with bash-based CLI management system. The project is designed for personal use (up to 50 users) with focus on simplicity and automation.

## Architecture

### Two-Part Structure
1. **Git Repository** (`/vless/`) - Contains scripts, templates, documentation
2. **Working Directory** (`/opt/vless/`) - Created during installation, contains runtime data, configs, and user data

### Key Components
- **Xray-core Container**: Main VPN server running in Docker (teddysun/xray:24.11.30 - pinned version)
- **REALITY Protocol**: Traffic obfuscation using TLS masquerading
- **X25519 Cryptography**: Key generation and management for REALITY
- **Interactive CLI Menus**: All management scripts have both menu and direct command modes
- **DNS Configuration**: Customizable DNS servers during installation (Google, Cloudflare, Quad9, or custom)
- **Network Auto-Configuration**: Automatic setup of IP forwarding, NAT, and firewall rules with legacy cleanup

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
sudo iptables -t nat -L POSTROUTING -n -v | grep "172\."
```

### Network Verification and Troubleshooting
```bash
# Verify kernel modules and sysctl settings
lsmod | grep br_netfilter
sysctl net.ipv4.ip_forward
sysctl net.bridge.bridge-nf-call-iptables
cat /etc/sysctl.d/99-vless-network.conf

# Check Docker-managed NAT rules (automatic, no manual editing)
sudo iptables -t nat -L POSTROUTING -n -v | grep "172\."

# Verify Docker network
docker network inspect vless-reality_vless-network

# Test connectivity from container
docker exec xray-server ping -c 2 8.8.8.8
docker exec xray-server nslookup google.com 8.8.8.8
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
#### Network Configuration (Rewritten 2025-09-30)
**Philosophy: Docker automatically manages iptables NAT rules. Scripts only configure kernel settings.**

- `find_available_docker_subnet()` - Finds free Docker subnet in 172.16-254.x.x range
- `load_br_netfilter()` - Loads br_netfilter kernel module (required for bridge+iptables)
- `enable_ip_forwarding()` - Enables IP forwarding and bridge netfilter (bridge-nf-call-iptables)
- `make_sysctl_persistent()` - Creates /etc/sysctl.d/99-vless-network.conf for persistence
- `configure_docker_daemon()` - Creates/updates /etc/docker/daemon.json with optimal settings
- `clean_conflicting_nat_rules()` - **NEW**: Detects and removes manual NAT rules that conflict with Docker (from other VPN services)
- `configure_firewall()` - Configures UFW port and forward policy (if UFW is active)
- `configure_network_for_vless()` - Main function: loads modules, enables sysctl, cleans conflicting rules, configures Docker
- `verify_network_configuration()` - Validates network setup (checks modules, sysctl, Docker NAT)
- `get_external_interface()` - Auto-detects external network interface
- `display_network_summary()` - Shows network configuration summary

**Key Settings:**
- `net.ipv4.ip_forward = 1` - Enable routing
- `net.bridge.bridge-nf-call-iptables = 1` - **CRITICAL**: Bridge traffic through iptables
- `br_netfilter` module loaded - Required for above setting to work

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

**Template Files (.tpl):**
All configuration templates use `.tpl` extension and are stored in `templates/` directory:
- `config.json.tpl` - Main Xray configuration (without custom DNS)
- `config_with_dns.json.tpl` - Xray configuration with custom DNS
- `docker-compose.yml.tpl` - Main xray-server container
- `docker-compose.fake.yml.tpl` - Fake site container (uses COMPOSE_PROJECT_NAME, RESTART_POLICY, TZ)
- `.env.example` - Environment variables template

During installation:
1. Templates are copied to `/opt/vless/templates/`
2. Processed with `apply_template()` to create final configs in `/opt/vless/`
3. Variables loaded from `.env` file in `/opt/vless/`

**Fake Site Template Processing:**
The `setup-fake-site.sh` script processes `docker-compose.fake.yml.tpl`:
1. Loads variables from `/opt/vless/.env`
2. Applies template with COMPOSE_PROJECT_NAME, RESTART_POLICY, TZ
3. Creates `/opt/vless/docker-compose.fake.yml`
4. Network name: `${COMPOSE_PROJECT_NAME}_vless-network` (typically `vless-reality_vless-network`)

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

### Network Configuration and VPN Routing (CRITICAL)
**Issue:** VPN clients cannot access internet after connection
**Root Cause:** Missing `br_netfilter` module or `bridge-nf-call-iptables` setting

**How Docker NAT Works:**
1. Docker automatically creates MASQUERADE rule: `-A POSTROUTING -s 172.X.0.0/16 ! -o br-XXX -j MASQUERADE`
2. **Requires** `br_netfilter` kernel module loaded
3. **Requires** `net.bridge.bridge-nf-call-iptables = 1` (bridge traffic through iptables)
4. **Requires** `net.ipv4.ip_forward = 1` (routing enabled)

**What Installation Configures:**
- Loads `br_netfilter` module persistently (`/etc/modules-load.d/br_netfilter.conf`)
- Creates `/etc/sysctl.d/99-vless-network.conf` with all required settings
- Configures `/etc/docker/daemon.json` with optimal settings
- Docker automatically manages iptables NAT rules (no manual intervention)

**Verification:**
```bash
# All three must return 1
lsmod | grep br_netfilter
sysctl net.ipv4.ip_forward
sysctl net.bridge.bridge-nf-call-iptables

# Docker should create this rule automatically after docker-compose up
sudo iptables -t nat -L POSTROUTING -n -v | grep "MASQUERADE.*172\."

# Test from container
docker exec xray-server ping -c 2 8.8.8.8
```

**Manual Fix (if needed):**
```bash
# Load module
sudo modprobe br_netfilter
echo "br_netfilter" | sudo tee /etc/modules-load.d/br_netfilter.conf

# Enable sysctl settings
sudo tee /etc/sysctl.d/99-vless-network.conf << EOF
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sudo sysctl -p /etc/sysctl.d/99-vless-network.conf

# Restart Docker to apply
sudo systemctl restart docker
cd /opt/vless && docker-compose restart
```

### VPN Conflicts with Other Services (NEW)
**Issue:** Multiple VPN services (VLESS, Outline, OpenVPN, etc.) on same server create conflicting NAT rules
**Symptoms:**
- Client connects but cannot access internet (despite system settings correct)
- Multiple duplicate MASQUERADE rules in iptables
- Example: `172.18.0.0/16` appears 10 times, `172.19.0.0/16` appears 5 times

**Root Cause:** Other VPN services manually add iptables NAT rules that conflict with Docker-managed rules

**Diagnostic Tool:**
```bash
# Run comprehensive diagnostic
sudo /opt/vless/scripts/diagnose-vpn-conflicts.sh

# Or from repo directory
sudo ./scripts/diagnose-vpn-conflicts.sh
```

The tool will:
- Check system configuration (kernel modules, sysctl settings)
- Analyze Docker networks and subnets
- Identify conflicting manual NAT rules
- Check for duplicate MASQUERADE rules
- Test container connectivity
- Provide actionable recommendations

**Automatic Cleanup (Recommended):**
```bash
# During installation (automatic)
sudo bash scripts/install.sh
# Installation will detect and offer to remove conflicting rules

# For existing installation
source /opt/vless/scripts/lib/colors.sh
source /opt/vless/scripts/lib/utils.sh
source /opt/vless/scripts/lib/network.sh
clean_conflicting_nat_rules

# Restart services
sudo systemctl restart docker
cd /opt/vless && docker-compose restart
```

**Manual Cleanup:**
```bash
# List conflicting rules (manual rules via external interface for Docker subnets)
sudo iptables -t nat -L POSTROUTING -n -v --line-numbers | grep -E "MASQUERADE.*ens1.*172\."

# Remove rules in REVERSE order (highest number first)
# Example: if you have rules 7-20, remove them like this:
for i in {20..7}; do sudo iptables -t nat -D POSTROUTING $i; done

# Verify only Docker-managed rules remain (with br-XXXXX interface)
sudo iptables -t nat -L POSTROUTING -n -v | grep "172\."
```

**Prevention:**
- Use different Docker subnets for each VPN service
- Let Docker manage its own NAT rules automatically
- Never manually add iptables rules for Docker subnets

**See also:** docs/VPN-CONFLICTS-SOLUTIONS.md for complete guide

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

### Fake Site Configuration
**Network Setup:**
- Fake site container (`vless-fake-site`) connects to the same Docker network as xray-server (`vless-network`)
- Network is marked as `external: true` in docker-compose.fake.yml to use existing network
- Fallback destination in config.json uses container name: `vless-fake-site:80`
- No external port mapping needed - fake site is only accessible within Docker network
- This ensures fallback mechanism works correctly regardless of selected subnet

**Troubleshooting:**
```bash
# Check if fake site is in the correct network
docker network inspect vless-reality_vless-network

# Test connectivity from xray-server to fake-site
docker exec xray-server wget -O- http://vless-fake-site:80/health

# Restart fake site if network connection fails
cd /opt/vless
docker-compose -f docker-compose.fake.yml down
docker-compose -f docker-compose.fake.yml up -d
```

### REALITY Invalid Connection - No Internet Access (CRITICAL)
**Issue:** Client shows "Connected" but cannot access internet, logs show "REALITY: processed invalid connection"
**Root Cause:** X25519 key pair mismatch between server (privateKey) and client (publicKey)
**Solution:**
1. Generate new X25519 keys: `docker run --rm teddysun/xray:24.11.30 xray x25519`
2. Update privateKey in `/opt/vless/config/config.json`
3. Update PRIVATE_KEY and PUBLIC_KEY in `/opt/vless/.env`
4. Restart: `cd /opt/vless && docker-compose restart`
5. Update all client configurations with new PUBLIC_KEY

**Diagnosis:**
```bash
# Check for invalid connection errors
sudo tail -100 /opt/vless/logs/error.log | grep "invalid connection"

# Verify key correspondence
docker exec xray-server cat /etc/xray/config.json | jq -r '.inbounds[0].streamSettings.realitySettings.privateKey'
docker run --rm teddysun/xray:24.11.30 xray x25519 -i <PRIVATE_KEY_FROM_ABOVE>
# Compare output with PUBLIC_KEY in .env
```

**Prevention:**
- Use `scripts/security/rotate-keys.sh` for safe key rotation
- Always backup before changing keys
- Validate key pairs after generation

**See also:**
- TROUBLESHOOTING.md: Section "REALITY: processed invalid connection"
- PRD.md: Section 13.1 "Известные проблемы"

### Xray Version Compatibility
**Issue:** Version mismatch between server and client causes connection failures
**Fixed Version:** teddysun/xray:24.11.30 (pinned in docker-compose.yml.tpl)
**Previously Used:** teddysun/xray:latest (caused compatibility issues)

**Why version 24.11.30:**
- Compatible with most iOS clients (v2rayTun, Shadowrocket)
- Stable REALITY protocol implementation
- No breaking changes in cryptographic handshake

**If upgrading Xray:**
- Test with one client before mass deployment
- Check release notes for breaking changes
- Update both server and client versions together
- Monitor logs for "processed invalid connection" errors

### Geosite Rules Incompatibility
**Issue:** Xray 24.11.30 doesn't include win-spy/win-update geosite categories
**Error:** "failed to load geosite: WIN-SPY" or "failed to load geosite: WIN-UPDATE"
**Solution:** These rules have been removed from templates (config.json.tpl, config_with_dns.json.tpl)

**Compatible geosite rules:**
- ✅ `geosite:category-ads-all` - Ad blocking (works)
- ✅ `geosite:cn` - Chinese domains (works)
- ✅ `geosite:geolocation-!cn` - Non-Chinese domains (works)
- ❌ `geosite:win-spy` - Windows telemetry (not available in 24.11.30)
- ❌ `geosite:win-update` - Windows Update (not available in 24.11.30)

**Migration:**
If manually upgrading from older configs, remove win-spy/win-update rules from routing section.

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