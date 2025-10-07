# VLESS Reality VPN Deployment System

**Version**: 4.0
**Status**: In Development
**License**: MIT

---

## Overview

Production-grade CLI-based VLESS+Reality VPN deployment system enabling users to install, configure, and manage Reality protocol servers in under 5 minutes. Features automated dependency installation, Docker orchestration, comprehensive user management, **dual proxy server support (SOCKS5 + HTTP) with stunnel TLS termination** (v4.0), template-based configuration architecture, multi-layer IP whitelisting (Xray + UFW), Let's Encrypt certificate automation, and defense-in-depth security hardening including fail2ban integration.

### What's New in v4.0

**Primary Feature:** stunnel-based TLS termination + template-based configuration architecture

**Key Changes:**
- **stunnel TLS Termination**: Dedicated stunnel container handles TLS 1.3 encryption, separating concerns from Xray
- **Template-Based Configs**: All configurations (Xray, stunnel, docker-compose) generated from templates
- **Simpler Xray Config**: Xray focuses on proxy logic (localhost plaintext inbounds), no TLS complexity
- **UFW Integration**: Optional host-level firewall rules for proxy ports (defense-in-depth)
- **Mature TLS Stack**: stunnel has 20+ years production stability
- **Better Debugging**: Separate logs for TLS (stunnel) vs proxy (Xray)

**Architecture:**
```
Client → stunnel (TLS 1.3, ports 1080/8118)
       → Xray (plaintext, localhost 10800/18118)
       → Internet
```

---

## Features

### Core Capabilities

- **One-Command Installation**: Complete setup in < 5 minutes
- **Automated Dependency Management**: Docker, UFW, certbot, jq, qrencode, tcpdump, nmap, fail2ban auto-install (tshark optional)
- **Reality Protocol**: TLS 1.3 masquerading for undetectable VPN traffic
- **Dual Proxy Support (v4.0)**: SOCKS5 (port 1080) + HTTP (port 8118) proxies with:
  - **stunnel TLS Termination**: Dedicated container for TLS 1.3 encryption
  - **Let's Encrypt certificates** with auto-renewal
  - **Always encrypted**: TLS mandatory for public proxy mode
  - **Client URIs**: `socks5s://user:pass@domain:1080` and `https://user:pass@domain:8118`
- **Multi-Layer IP Whitelisting (v4.0)**: Defense-in-depth access control with:
  - **Xray routing rules** (v3.6): Application-level filtering via proxy_allowed_ips.json
  - **UFW firewall rules** (v4.0 NEW): Host-level filtering for proxy ports
  - **Multiple IP formats**: Individual IPs, CIDR ranges, IPv4/IPv6
  - **Default security**: Localhost-only access for new users
  - **Zero downtime**: Updates apply immediately via container reload
- **Template-Based Configuration (v4.0 NEW)**: Clean separation of configs from scripts
  - **Xray config**: Generated from template with variable substitution
  - **stunnel config**: Template-based with domain variable
  - **docker-compose**: Dynamic service composition based on mode
- **User Management**: Create/remove users in < 5 seconds with UUID generation
- **Multi-Format Config Export**: 6 proxy config formats (SOCKS5, HTTP, VSCode, Docker, Bash, Git)
- **QR Code Generation**: 400x400px PNG + ANSI terminal variants
- **Service Operations**: Start/stop/restart with zero-downtime reloads
- **Security Hardening**: CIS Docker Benchmark compliance, defense-in-depth
- **Automated Updates**: Configuration-preserving system updates with breaking change warnings
- **Comprehensive Logging**: ERROR/WARN/INFO filtering with real-time streaming + separate stunnel logs

### Security Features

- **Multi-Layer Firewalling (v4.0)**: Defense-in-depth with UFW + Xray routing + stunnel
- Container security (capability dropping, read-only root, no-new-privileges)
- **Public Proxy Mode (v4.0)**: Internet-accessible SOCKS5/HTTP proxies with production-grade security:
  - **Mandatory TLS 1.3 Encryption**: stunnel handles TLS termination (always encrypted)
  - **Certificate Auto-Renewal**: Automated Let's Encrypt renewal (cron-based, twice daily)
  - **Fail2ban Integration**: Automatic IP banning after 5 failed authentication attempts (1-hour ban)
  - **UFW Rate Limiting**: 10 connections per minute per IP (host firewall)
  - **Xray IP Whitelist**: Application-level filtering (proxy_allowed_ips.json)
  - **Enhanced Passwords**: 32-character random passwords (2^128 entropy)
  - **Docker Healthchecks**: Automated container health monitoring (Xray + stunnel)
  - **Domain Validation**: DNS checks before certificate issuance
  - **Separation of Concerns**: stunnel (TLS) + Xray (auth) + UFW (firewall)
- **VLESS-Only Mode** (default): Traditional VPN-only deployment, no proxy exposure
- File permission hardening (least privilege principle: 600 for configs, 700 for scripts)
- Automated security auditing
- SSH rate limiting (brute force protection)
- Atomic operations with flock (race condition prevention)

---

## Quick Start

### Prerequisites

- Ubuntu 20.04+ or Debian 10+
- Root access
- Internet connection
- Minimum 1GB RAM, 10GB disk space
- **Domain name** (required for public proxy mode with TLS) with DNS A record pointing to server IP

### Installation (5 minutes)

```bash
# Clone repository
git clone https://github.com/your-username/vless-reality-vpn.git
cd vless-reality-vpn

# Run installation (creates /opt/vless during install)
sudo ./install.sh

# Follow interactive prompts:
# 1. Select destination site (google.com, microsoft.com, etc.)
# 2. Choose VLESS port (443 or custom)
# 3. Select Docker subnet (auto-detected)
# 4. Enable public proxy access? [y/N] ← v4.0: SOCKS5 + HTTP with stunnel TLS
#    - Choose 'y' for internet-accessible proxies (TLS always enabled)
#    - Choose 'N' for VLESS-only mode (default)
# 5. If 'y': Enter domain name (e.g., vpn.example.com) - REQUIRED for TLS
# 6. If 'y': Enter email for Let's Encrypt notifications
```

### Create First User (<5 seconds)

```bash
# Add user
sudo vless add-user alice

# Output shows:
# - VLESS connection QR code
# - Proxy password (if proxies enabled)
# - Connection details
# - Config files location: /opt/vless/data/clients/alice/
#   - vless_config.json, vless_uri.txt, qrcode.png (VLESS)
#   - socks5_config.txt, http_config.txt (Proxy URIs - TLS encrypted in v3.3)
#   - vscode_settings.json, docker_daemon.json, bash_exports.sh, git_config.txt
```

---

## Security Notes (v3.4 Public Proxy Mode)

**v3.4 introduces optional TLS encryption** for public proxy mode:
- **WITH TLS (v3.3/v3.4)**: Production-ready with Let's Encrypt certificates (recommended)
- **WITHOUT TLS (v3.4)**: Plaintext mode for development/testing ONLY

### Proxy Encryption Modes

#### 1. Public Proxy WITH TLS (Recommended)
✅ **Production-ready** - Credentials encrypted end-to-end
- Protocols: `socks5s://`, `https://`
- Requires: Domain name + Let's Encrypt certificate
- Security: TLS 1.3 encryption, fail2ban, rate limiting
- Use case: Private VPS with trusted users

#### 2. Public Proxy WITHOUT TLS (Plaintext - Development Only)
⚠️ **NOT PRODUCTION-READY** - Credentials transmitted in plaintext!
- Protocols: `socks5://`, `http://`
- Requires: No domain, no certificates
- Security: Fail2ban, rate limiting, password auth
- ⚠️ **WARNING**: Passwords visible to network observers!
- Use case: Localhost-only, trusted networks, development/testing

### When to Use Public Proxy Mode

✅ **TLS Mode Recommended for:**
- Private VPS with trusted users only
- Production deployments
- Users who cannot install VPN clients (restrictive networks, mobile devices)
- Scenarios requiring proxy WITHOUT VPN connection

❌ **Plaintext Mode ONLY for:**
- Development and testing environments
- Localhost-only access (no internet exposure)
- Trusted private networks (LAN)

❌ **NOT recommended for ANY public proxy:**
- Shared hosting environments
- Servers without DDoS protection
- Compliance-sensitive deployments (GDPR, HIPAA, etc.)
- Untrusted or open networks

### Automatic Security Measures

When you enable proxy mode (localhost-only or public), the installer automatically configures:

1. **Fail2ban Protection** (v3.3 - all proxy modes)
   - Monitors Xray authentication logs
   - Bans IP after 5 failed attempts (localhost via VPN, public from internet)
   - Ban duration: 1 hour
   - Protects against brute-force attacks in both modes
   - Check status: `sudo fail2ban-client status vless-socks5`

2. **UFW Rate Limiting** (public proxy mode only)
   - Limits connections to 10 per minute per IP
   - Applies to ports 1080 (SOCKS5) and 8118 (HTTP)
   - Prevents connection flood attacks from internet

3. **Enhanced Authentication**
   - 32-character passwords (vs 16 in v3.1)
   - Hexadecimal format (128-bit entropy)
   - Unique credentials per user

4. **Container Monitoring**
   - Docker healthchecks every 30 seconds
   - Auto-restart on failure (3 retries)

### Manual Security Hardening (Optional)

For maximum security, consider these additional steps:

```bash
# 1. Enable automatic security updates
sudo apt install unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades

# 2. Monitor fail2ban logs
sudo journalctl -u fail2ban -f

# 3. Review banned IPs weekly
sudo fail2ban-client status vless-socks5
sudo fail2ban-client status vless-http

# 4. Rotate credentials every 3-6 months
vless reset-proxy-password <username>

# 5. Monitor Xray logs for suspicious activity
vless logs | grep "authentication failed"
```

### Migration Notes

- **v3.2 → v3.3**: See [MIGRATION_v3.2_to_v3.3.md](docs/MIGRATION_v3.2_to_v3.3.md) - **CRITICAL** security update (plaintext → TLS)
- **v3.1 → v3.2**: See [MIGRATION_v3.1_to_v3.2.md](docs/MIGRATION_v3.1_to_v3.2.md) - Dual proxy support

---

## Documentation

- [Installation Guide](docs/INSTALLATION.md)
- [User Management](docs/USER_MANAGEMENT_REPORT.md)
- [Service Operations](docs/SERVICE_OPERATIONS_REPORT.md)
- [Security Hardening](docs/SECURITY_HARDENING_REPORT.md)
- [API Reference](docs/API.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)

---

## Usage

### User Management

```bash
# Basic user operations
vless add-user <username>              # Add new user (auto-generates proxy password)
vless remove-user <username>           # Remove user
vless list-users                       # List all users

# Proxy credential management
vless show-proxy <username>            # Show SOCKS5/HTTP credentials
vless reset-proxy-password <username>  # Reset proxy password (regenerates configs)
vless regenerate <username>            # Regenerate config files (v3.3 migration)

# Proxy IP Whitelist (v3.6 - Server-Level)
vless show-proxy-ips                               # Show allowed source IPs
vless set-proxy-ips <ip1,ip2,...>                  # Set allowed IPs (comma-separated)
vless add-proxy-ip <ip>                            # Add IP to whitelist
vless remove-proxy-ip <ip>                         # Remove IP from whitelist
vless reset-proxy-ips                              # Reset to localhost only
```

### Service Operations

```bash
vless start                   # Start service
vless stop                    # Stop service
vless restart                 # Restart service
vless status                  # Service status (NEW: shows proxy status)
vless logs [error|warn|info]  # View logs
```

### Maintenance

```bash
vless update                  # Update system
vless backup create           # Create backup
vless test-security           # Security & encryption testing (NEW)
vless test                    # Xray config validation
```

### Proxy Usage Examples

**Public Proxy Mode (v3.3 - TLS encrypted):**

```bash
# Terminal: SOCKS5 proxy (TLS)
curl --socks5 alice:password@vpn.example.com:1080 https://ifconfig.me

# Terminal: HTTP proxy (TLS)
curl --proxy https://alice:password@vpn.example.com:8118 https://ifconfig.me

# Bash: Set environment variables
source /opt/vless/data/clients/alice/bash_exports.sh
curl https://ifconfig.me  # Uses proxy automatically

# VSCode: Copy proxy settings (includes TLS validation)
cp /opt/vless/data/clients/alice/vscode_settings.json .vscode/settings.json

# Docker: Configure daemon
sudo cp /opt/vless/data/clients/alice/docker_daemon.json /etc/docker/daemon.json
sudo systemctl restart docker

# Git: Configure proxy (v3.3)
# See git_config.txt for detailed instructions
git config --global http.proxy socks5s://alice:password@vpn.example.com:1080
```

**VLESS-Only Mode (no proxy):**

Just use the VLESS connection from the QR code, no additional proxy configuration needed.

---

## Testing Proxy Setup

After creating a user, test that proxy servers are working correctly:

### 1. Get Proxy Credentials

```bash
# View generated proxy configurations
ls -la /opt/vless/data/clients/YOUR_USERNAME/

# Get SOCKS5 URI
cat /opt/vless/data/clients/YOUR_USERNAME/socks5_config.txt
# Example: socks5s://user:password@vpn.example.com:1080

# Get HTTP URI
cat /opt/vless/data/clients/YOUR_USERNAME/http_config.txt
# Example: https://user:password@vpn.example.com:8118
```

### 2. Test SOCKS5 Proxy (TLS)

```bash
# Test with curl (using credentials from socks5_config.txt)
curl -s --socks5 user:password@vpn.example.com:1080 https://ifconfig.me

# Should display your SERVER's public IP address
# If it shows your local IP, proxy is NOT working
```

### 3. Test HTTP Proxy (TLS)

```bash
# Test with curl (using credentials from http_config.txt)
curl -s --proxy https://user:password@vpn.example.com:8118 https://ifconfig.me

# Should display your SERVER's public IP address
```

### 4. Verify TLS Encryption

```bash
# Check that ports are listening with TLS
sudo netstat -tlnp | grep -E ':(1080|8118)'
# Should show: 0.0.0.0:1080 and 0.0.0.0:8118 (public mode)
# or: 127.0.0.1:1080 and 127.0.0.1:8118 (localhost mode)

# Check Xray logs for TLS handshakes
sudo vless logs xray | grep -i "tls"
```

### 5. Test from Different Locations

```bash
# From your local machine (replace with actual values):
PROXY_USER="your-username"
PROXY_PASS="your-password"
PROXY_DOMAIN="vpn.example.com"

# SOCKS5 test
curl -s --socks5 ${PROXY_USER}:${PROXY_PASS}@${PROXY_DOMAIN}:1080 https://ifconfig.me

# HTTP test
curl -s --proxy https://${PROXY_USER}:${PROXY_PASS}@${PROXY_DOMAIN}:8118 https://ifconfig.me

# Test with different site
curl -s --proxy https://${PROXY_USER}:${PROXY_PASS}@${PROXY_DOMAIN}:8118 https://api.ipify.org
```

### 6. Troubleshooting

**Problem: Connection refused**
```bash
# Check if containers are running
sudo docker ps | grep vless

# Check if ports are open in firewall (public mode)
sudo ufw status | grep -E '1080|8118'

# Check Xray logs
sudo vless logs xray --tail 50
```

**Problem: Authentication failed**
```bash
# Verify password is correct
cat /opt/vless/data/clients/YOUR_USERNAME/socks5_config.txt

# Check fail2ban didn't block your IP
sudo fail2ban-client status vless-socks5
sudo fail2ban-client status vless-http

# Unban if needed
sudo fail2ban-client set vless-socks5 unbanip YOUR_IP
```

**Problem: Shows local IP instead of server IP**
```bash
# Proxy not routing correctly - check Xray config
sudo cat /opt/vless/config/xray_config.json | jq '.inbounds[1,2]'

# Restart services
sudo vless restart
```

### 7. Integration Tests

```bash
# Test with environment variables (bash_exports.sh)
source /opt/vless/data/clients/YOUR_USERNAME/bash_exports.sh
curl -s https://ifconfig.me
# Should use proxy automatically

# Test with Git
git config --global http.proxy $(cat /opt/vless/data/clients/YOUR_USERNAME/socks5_config.txt)
git clone https://github.com/torvalds/linux.git --depth 1
# Should download through proxy

# Clean up
git config --global --unset http.proxy
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
```

**Expected Results:**
- ✓ Both SOCKS5 and HTTP proxies return **server's public IP**
- ✓ TLS handshakes visible in logs (public mode)
- ✓ No authentication errors
- ✓ Fail2ban shows 0 banned IPs initially

---

## Proxy IP Whitelist Management (v3.6)

**Updated in v3.6**: Server-level IP-based access control for proxy servers. Restrict proxy access to specific source IP addresses using Xray routing rules.

> **Migration Note**: v3.6 changes from per-user to server-level IP whitelisting due to protocol limitations. See [Migration Guide](#migration-from-v35-to-v36) below.

### Overview

Proxy IP whitelisting allows you to control which source IP addresses can connect to the SOCKS5/HTTP proxy servers. This provides an additional security layer on top of password authentication.

**Key Features:**
- **Server-level control**: Single IP whitelist applies to all proxy users
- **Multiple IP formats**: Supports individual IPs, CIDR ranges, IPv4/IPv6
- **Default security**: New installations default to localhost-only access (`127.0.0.1`)
- **Application-level filtering**: Xray routing rules enforce restrictions
- **Zero downtime**: IP list updates apply immediately via container reload

**Why Server-Level?**
- HTTP/SOCKS5 protocols don't provide user identifiers in Xray routing context
- Xray `user` field only works for VLESS protocol, not proxy protocols
- Server-level whitelisting works reliably for all proxy connections

### Use Cases

1. **Fixed client IPs**: Restrict access to specific office/home IPs
2. **VPN-only access**: Allow only VPN-connected clients (`10.0.0.0/8`)
3. **Multi-location teams**: Whitelist multiple office locations
4. **Private network**: Restrict to internal network ranges
5. **Compliance requirements**: Enforce IP-based access policies

### Quick Start

```bash
# Show current proxy IP whitelist
sudo vless show-proxy-ips

# Allow access from specific IP
sudo vless set-proxy-ips 203.0.113.45

# Allow access from multiple IPs and CIDR ranges
sudo vless set-proxy-ips 127.0.0.1,203.0.113.45,10.0.0.0/24,192.168.1.100

# Add additional IP to existing list
sudo vless add-proxy-ip 198.51.100.10

# Remove specific IP
sudo vless remove-proxy-ip 203.0.113.45

# Reset to localhost only
sudo vless reset-proxy-ips
```

### Supported IP Formats

```bash
# Individual IPv4
vless set-proxy-ips 192.168.1.100

# IPv4 CIDR range
vless set-proxy-ips 10.0.0.0/24          # 10.0.0.1 - 10.0.0.254
vless set-proxy-ips 172.16.0.0/16        # 172.16.0.1 - 172.16.255.254

# IPv6
vless set-proxy-ips 2001:db8::1

# IPv6 CIDR range
vless set-proxy-ips 2001:db8::/32

# Multiple IPs (comma-separated)
vless set-proxy-ips 127.0.0.1,203.0.113.45,10.0.0.0/24
```

### Common Scenarios

#### Scenario 1: Office Network Access

```bash
# Allow access only from office IP range
sudo vless set-proxy-ips 198.51.100.0/24

# Verify
sudo vless show-proxy-ips
```

#### Scenario 2: VPN-Only Access

```bash
# Only allow connections after VPN connection (via VLESS)
# Assuming your VPN assigns 10.x.x.x addresses
sudo vless set-proxy-ips 10.0.0.0/8

# Now all users must:
# 1. Connect to VLESS VPN first (gets IP like 10.8.0.2)
# 2. Then use SOCKS5/HTTP proxy through the VPN tunnel
```

#### Scenario 3: Multi-Location Organization

```bash
# Allow access from 3 office locations
sudo vless set-proxy-ips \
  198.51.100.0/24,\      # US office
  203.0.113.0/24,\       # EU office
  192.0.2.0/24           # Asia office
```

#### Scenario 4: Development Server (Localhost Only)

```bash
# Restrict to localhost (default behavior)
sudo vless reset-proxy-ips

# Output: Proxy IPs reset to 127.0.0.1 (localhost only)
```

#### Scenario 5: Dynamic IP Range

```bash
# For users with dynamic IPs from ISP range
# Example: ISP assigns IPs in 203.0.112.0/22 range
sudo vless set-proxy-ips 203.0.112.0/22
```

### How It Works

Proxy IP whitelisting uses **Xray routing rules** to filter connections at the application level:

1. **User connects** to SOCKS5/HTTP proxy with credentials
2. **Xray checks** source IP against server-level whitelist
3. **If match**: Connection routed to `direct` outbound (allowed)
4. **If no match**: Connection routed to `blackhole` outbound (blocked)

**Technical Details:**
- Routing rules stored in `xray_config.json` (auto-generated)
- IP whitelist stored in `proxy_allowed_ips.json`
- Changes applied via Xray container reload (< 3 seconds)
- Evaluation order: Whitelist rule first, catch-all block last

**Routing Rule Format:**
```json
{
  "type": "field",
  "inboundTag": ["socks5-proxy", "http-proxy"],
  "source": ["127.0.0.1", "203.0.113.45", "10.0.0.0/24"],
  "outboundTag": "direct"
}
```

### Viewing Current Configuration

```bash
# Check proxy IP whitelist
sudo vless show-proxy-ips

# Output:
# ═══════════════════════════════════════════════════════
#   PROXY IP WHITELIST (Server-Level)
# ═══════════════════════════════════════════════════════
#
# Allowed Source IPs:
#   • 127.0.0.1
#   • 203.0.113.45
#   • 10.0.0.0/24
#
# ═══════════════════════════════════════════════════════
#
# These IPs can connect to SOCKS5/HTTP proxy using ANY user credentials.
# Connections from other IPs will be blocked.

# View raw configuration
sudo cat /opt/vless/config/proxy_allowed_ips.json

# View routing rules in Xray config
sudo jq '.routing.rules' /opt/vless/config/xray_config.json
```

### Best Practices

1. **Start restrictive**: Begin with localhost-only (`127.0.0.1`), add IPs as needed
2. **Use CIDR notation**: For IP ranges (office networks, VPN subnets)
3. **Document IP sources**: Maintain a spreadsheet mapping IPs to locations
4. **Review quarterly**: Remove stale IPs when networks change
5. **Combine with fail2ban**: IP whitelist + password + fail2ban = defense-in-depth
6. **Test before deployment**: Verify new IPs before removing old ones
7. **Monitor logs**: Check Xray logs for blocked connection attempts

### Security Considerations

**IP Whitelist is NOT a replacement for strong passwords:**
- IPs can be spoofed (especially in cloud environments)
- IP whitelist adds a layer, but passwords remain critical
- Always use 32-character random passwords (auto-generated)

**When IP whitelisting is effective:**
- ✅ Fixed office/home IPs (residential ISPs, data centers)
- ✅ Private VPN subnets (10.x.x.x, 172.16.x.x, 192.168.x.x)
- ✅ Cloud provider IP ranges (AWS, GCP, Azure)

**When IP whitelisting is less effective:**
- ⚠️ Mobile users with dynamic IPs (use large CIDR or VPN-only mode)
- ⚠️ Users behind CGNAT (multiple users share same public IP)
- ⚠️ Compromised networks (attacker inside allowed network)

**Server-Level Impact:**
- All proxy users share the same IP whitelist
- Individual user IP restrictions not supported (protocol limitation)
- Use separate VPN instances for different IP requirements

### Troubleshooting

**Problem: Connection blocked after setting IPs**
```bash
# Check current whitelist
sudo vless show-proxy-ips

# Verify your source IP
curl -s https://ifconfig.me

# Add your IP if missing
sudo vless add-proxy-ip $(curl -s https://ifconfig.me)

# Check Xray logs for blocks
sudo vless logs xray | grep "rejected"
```

**Problem: Intermittent access issues**
```bash
# Likely cause: Dynamic IP changing
# Solution: Use CIDR range for ISP block
sudo vless set-proxy-ips 203.0.112.0/22
```

**Problem: Temporarily disable IP filtering**
```bash
# Allow all IPs (NOT recommended for production)
sudo vless set-proxy-ips 0.0.0.0/0

# Better: Use localhost + current IP
sudo vless set-proxy-ips 127.0.0.1,$(curl -s https://ifconfig.me)
```

### Migration from v3.5 to v3.6

**Automatic Migration:**

v3.6 includes a migration script that converts per-user IP whitelists to server-level:

```bash
# Run migration script
sudo /opt/vless/scripts/migrate_proxy_ips.sh

# Script will:
# 1. Collect all unique IPs from users' allowed_ips fields
# 2. Create proxy_allowed_ips.json with collected IPs
# 3. Regenerate routing rules (server-level)
# 4. Reload Xray
# 5. Optionally clean up old allowed_ips fields
```

**Manual Migration:**

If you prefer manual migration:

```bash
# 1. Check existing per-user IPs
sudo jq '.users[] | {user: .username, ips: .allowed_ips}' /opt/vless/data/users.json

# 2. Collect all unique IPs
UNIQUE_IPS=$(sudo jq -r '[.users[] | .allowed_ips[]] | unique | join(",")' /opt/vless/data/users.json)

# 3. Set server-level whitelist
sudo vless set-proxy-ips "$UNIQUE_IPS"

# 4. Verify
sudo vless show-proxy-ips
```

**Breaking Changes:**

- ❌ Per-user IP commands removed: `show-allowed-ips`, `set-allowed-ips`, `add-allowed-ip`, etc.
- ✅ New server-level commands: `show-proxy-ips`, `set-proxy-ips`, `add-proxy-ip`, etc.
- ❌ `allowed_ips` field in `users.json` no longer used
- ✅ New file: `/opt/vless/config/proxy_allowed_ips.json`

### Technical Implementation

**Files Added:**
- `lib/proxy_whitelist.sh`: Server-level IP management module
- `config/proxy_allowed_ips.json`: Server-level IP whitelist storage
- `scripts/migrate_proxy_ips.sh`: v3.5 → v3.6 migration script

**Files Modified:**
- `lib/orchestrator.sh`: Routing rule generation (server-level)
- `cli/vless`: CLI command handlers (server-level commands)
- `data/users.json`: `allowed_ips` field no longer used (legacy support)

**Configuration File (`proxy_allowed_ips.json`):**
```json
{
  "allowed_ips": ["127.0.0.1", "203.0.113.45", "10.0.0.0/24"],
  "metadata": {
    "created": "2025-10-06T12:00:00Z",
    "last_modified": "2025-10-06T14:30:00Z",
    "description": "Server-level IP whitelist for proxy access (v3.6)"
  }
}
```

**Xray Routing Rule (Server-Level):**
```json
{
  "type": "field",
  "inboundTag": ["socks5-proxy", "http-proxy"],
  "source": ["127.0.0.1", "203.0.113.45", "10.0.0.0/24"],
  "outboundTag": "direct"
}
```

Note: No `user` field - routing based solely on source IP (works for HTTP/SOCKS5)

---

## Architecture

- **Protocols**:
  - VLESS + Reality (Xray-core) - Primary VPN tunnel
  - SOCKS5 (port 1080) - Universal proxy protocol
  - HTTP (port 8118) - Web/IDE proxy protocol
- **Containers**: Docker + Docker Compose
- **Firewall**: UFW + iptables
- **Storage**: JSON files (users.json v1.1 with proxy_password field)
- **Modules**: 14 bash modules (~6,500 LOC)

---

## Testing

### Unit & Integration Tests

```bash
# Install bats
npm install -g bats

# Run tests
bats tests/unit/              # Unit tests
sudo bats tests/integration/  # Integration tests
sudo bats tests/performance/  # Performance tests
```

### Security Testing (NEW)

**Test encryption and security from client to internet:**

```bash
# Full security test (2-3 minutes) - validates complete encryption stack
sudo vless test-security

# Quick mode (1 minute) - skip packet capture
sudo vless test-security --quick

# Verbose mode (detailed output)
sudo vless test-security --verbose

# Development mode (<30 seconds) - test suite validation without installation
sudo vless test-security --dev-mode

# Combine flags
sudo vless test-security --quick --verbose --skip-pcap
```

**What it tests:**
- ✅ Reality Protocol TLS 1.3 (X25519 keys, masquerading, SNI)
- ✅ stunnel TLS termination (SOCKS5/HTTP proxies over TLS)
- ✅ Traffic encryption validation (tcpdump, plaintext detection)
- ✅ Certificate security (Let's Encrypt, expiration, permissions)
- ✅ DPI resistance (Deep Packet Inspection evasion)
- ✅ SSL/TLS vulnerabilities (weak ciphers, obsolete protocols)
- ✅ Proxy security (authentication, password strength, binding)
- ✅ Data leak detection (config exposure, logs, DNS)

**Requirements:**
- ✅ **Automatically installed**: tcpdump, nmap (required), tshark (optional)
- ✅ Already available: openssl, curl, jq (system dependencies)
- ⚠️ **Manual install** (if tshark auto-install fails): `sudo apt-get install tshark`

**Development Mode:**
For testing the security suite itself or running tests from source without installation:

```bash
# Run from source directory
cd /path/to/vless/source
sudo bash lib/security_tests.sh --dev-mode
```

**When to use `--dev-mode`:**
- ✅ Testing security test improvements (CI/CD pipelines)
- ✅ Validating bash syntax and logic changes
- ✅ Running tests without full VLESS installation
- ❌ **NOT** for production security audits (most tests will be skipped)

**Exit codes:**
- `0` - All tests passed (encryption secure)
- `1` - Tests failed (configuration issues)
- `2` - Prerequisites not met (missing tools)
- `3` - 🔥 **CRITICAL** security vulnerabilities (immediate action required)

**Documentation:**
- Full guide: `docs/SECURITY_TESTING_CLI.md`
- Quick start: `tests/integration/QUICK_START_RU.md`
- Troubleshooting: `docs/SECURITY_TESTING_RU.md`

---

## Statistics

- **Development Time**: 220 hours (182h v3.2 + 38h v3.3 TLS integration)
- **Modules**: 15 (including certbot_setup.sh)
- **Functions**: ~150 (138 v3.2 + 12 TLS-related)
- **Test Cases**: ~140 (130 v3.2 + 10 TLS tests)
- **Lines of Code**: ~7,200 (6,500 v3.2 + 700 TLS/migration)
- **Status**: Production Ready
- **Latest Update**: v3.3 - Mandatory TLS Encryption for Public Proxies (Let's Encrypt)

---

## Project Structure

```
vless/
├── install.sh              # Main installation script
├── lib/                    # Core modules (14 files)
│   ├── orchestrator.sh     # UPDATED: Proxy inbound generation
│   ├── user_management.sh  # UPDATED: Proxy password & config export
│   └── service_operations.sh # UPDATED: Proxy status display
├── docs/                   # Documentation (12 reports)
├── tests/                  # Test suites (unit, integration, performance)
├── workflow/               # Implementation summaries (EPIC-11)
└── README.md               # This file

Production (after install):
/opt/vless/
├── config/
│   ├── xray_config.json    # 3 inbounds (VLESS + SOCKS5 + HTTP) with TLS
│   └── users.json          # v1.1 with proxy_password field
├── .version                # v3.3: Version tracking for updates
└── data/clients/<user>/
    ├── vless_config.json   # VLESS config
    ├── socks5_config.txt   # SOCKS5 URI (socks5s:// for TLS in v3.3)
    ├── http_config.txt     # HTTP URI (https:// for TLS in v3.3)
    ├── vscode_settings.json # VSCode proxy (with TLS validation)
    ├── docker_daemon.json  # Docker proxy config
    ├── bash_exports.sh     # Bash env vars
    └── git_config.txt      # v3.3: Git proxy instructions
```

---

## License

MIT License - See LICENSE file for details

---

## Support

- **Issues**: GitHub Issues
- **Documentation**: docs/ directory
- **Email**: support@example.com

---

## Acknowledgments

- [XTLS/Xray-core](https://github.com/XTLS/Xray-core)
- [bats-core](https://github.com/bats-core/bats-core)
- All contributors
