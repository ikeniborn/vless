# VLESS Reality VPN Deployment System

**Version**: 3.5
**Status**: Production Ready
**License**: MIT

---

## Overview

Production-grade CLI-based VLESS+Reality VPN deployment system enabling users to install, configure, and manage Reality protocol servers in under 5 minutes. Features automated dependency installation, Docker orchestration, comprehensive user management, **dual proxy server support (SOCKS5 + HTTP) with optional TLS encryption** for public access (v3.4), Let's Encrypt certificate automation, and defense-in-depth security hardening including fail2ban integration.

---

## Features

### Core Capabilities

- **One-Command Installation**: Complete setup in < 5 minutes
- **Automated Dependency Management**: Docker, UFW, certbot, jq, qrencode auto-install
- **Reality Protocol**: TLS 1.3 masquerading for undetectable VPN traffic
- **Dual Proxy Support (v3.4)**: SOCKS5 (port 1080) + HTTP (port 8118) proxies with:
  - **Optional TLS 1.3 encryption** for public access (recommended)
  - **Let's Encrypt certificates** with auto-renewal (when TLS enabled)
  - **Flexible deployment**: TLS (socks5s://, https://) or plaintext (socks5://, http://)
- **IP Whitelist Management (v3.5)**: Per-user IP-based access control with:
  - **Xray routing rules** for application-level filtering
  - **Multiple IP formats**: Individual IPs, CIDR ranges, IPv4/IPv6
  - **Default security**: Localhost-only access for new users
  - **Zero downtime**: Updates apply immediately via container reload
- **User Management**: Create/remove users in < 5 seconds with UUID generation
- **Multi-Format Config Export**: 6 proxy config formats (SOCKS5, HTTP, VSCode, Docker, Bash, Git)
- **QR Code Generation**: 400x400px PNG + ANSI terminal variants
- **Service Operations**: Start/stop/restart with zero-downtime reloads
- **Security Hardening**: CIS Docker Benchmark compliance, defense-in-depth
- **Automated Updates**: Configuration-preserving system updates with breaking change warnings
- **Comprehensive Logging**: ERROR/WARN/INFO filtering with real-time streaming

### Security Features

- Defense-in-depth firewall (UFW + iptables)
- Container security (capability dropping, read-only root, no-new-privileges)
- **Public Proxy Mode (v3.4)**: Internet-accessible SOCKS5/HTTP proxies with production-grade security:
  - **Optional TLS 1.3 Encryption**: Encryption via Let's Encrypt certificates (recommended for production)
  - **Plaintext Mode**: Available for development/testing (⚠️ credentials not encrypted)
  - **Certificate Auto-Renewal**: Automated certificate renewal when TLS enabled (cron-based, twice daily)
  - **Fail2ban Integration**: Automatic IP banning after 5 failed authentication attempts (1-hour ban, all modes)
  - **UFW Rate Limiting**: 10 connections per minute per IP (public proxy only)
  - **Enhanced Passwords**: 32-character random passwords (2^128 entropy)
  - **Docker Healthchecks**: Automated container health monitoring
  - **Domain Validation**: DNS checks before certificate issuance (TLS mode only)
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
# 4. Enable public proxy access? [y/N] ← v3.4: SOCKS5 + HTTP proxies
#    - Choose 'y' for internet-accessible proxies
#    - Choose 'N' for VLESS-only mode (default)
# 5. If 'y': Enable TLS encryption for proxy? [Y/n] ← v3.4: NEW
#    - Choose 'Y' for TLS (requires domain, Let's Encrypt cert) - RECOMMENDED
#    - Choose 'n' for plaintext (development/testing ONLY) - ⚠️ INSECURE
# 6. If TLS enabled: Enter domain name (e.g., vpn.example.com)
# 7. If TLS enabled: Enter email for Let's Encrypt notifications
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

# IP Whitelist Management (v3.5)
vless show-allowed-ips <username>                  # Show allowed source IPs
vless set-allowed-ips <username> <ip1,ip2,...>     # Set allowed IPs (comma-separated)
vless add-allowed-ip <username> <ip>               # Add IP to whitelist
vless remove-allowed-ip <username> <ip>            # Remove IP from whitelist
vless reset-allowed-ips <username>                 # Reset to localhost only
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
vless security audit          # Security audit
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

## IP Whitelist Management (v3.5)

**New in v3.5**: Per-user IP-based access control for proxy servers. Restrict proxy access to specific source IP addresses using Xray routing rules.

### Overview

IP whitelisting allows you to control which source IP addresses can connect to the proxy server using each user's credentials. This provides an additional security layer on top of password authentication.

**Key Features:**
- **Per-user granularity**: Each user has their own allowed IP list
- **Multiple IP formats**: Supports individual IPs, CIDR ranges, IPv4/IPv6
- **Default security**: New users default to localhost-only access (`127.0.0.1`)
- **Application-level filtering**: Xray routing rules enforce restrictions
- **Zero downtime**: IP list updates apply immediately via container reload

### Use Cases

1. **Fixed client IPs**: Restrict access to specific office/home IPs
2. **VPN-only access**: Allow only VPN-connected clients (`10.0.0.0/8`)
3. **Multi-location teams**: Whitelist multiple office locations
4. **Development/staging**: Restrict test accounts to developer IPs
5. **Compliance requirements**: Enforce IP-based access policies

### Quick Start

```bash
# Show default IPs for user (127.0.0.1 by default)
sudo vless show-allowed-ips alice

# Allow access from specific IP
sudo vless set-allowed-ips alice 203.0.113.45

# Allow access from multiple IPs and CIDR ranges
sudo vless set-allowed-ips alice 127.0.0.1,203.0.113.45,10.0.0.0/24,192.168.1.100

# Add additional IP to existing list
sudo vless add-allowed-ip alice 198.51.100.10

# Remove specific IP
sudo vless remove-allowed-ip alice 203.0.113.45

# Reset to localhost only
sudo vless reset-allowed-ips alice
```

### Supported IP Formats

```bash
# Individual IPv4
vless set-allowed-ips alice 192.168.1.100

# IPv4 CIDR range
vless set-allowed-ips alice 10.0.0.0/24          # 10.0.0.1 - 10.0.0.254
vless set-allowed-ips alice 172.16.0.0/16        # 172.16.0.1 - 172.16.255.254

# IPv6
vless set-allowed-ips alice 2001:db8::1

# IPv6 CIDR range
vless set-allowed-ips alice 2001:db8::/32

# Multiple IPs (comma-separated)
vless set-allowed-ips alice 127.0.0.1,203.0.113.45,10.0.0.0/24
```

### Common Scenarios

#### Scenario 1: Home + Office Access

```bash
# User works from home (static IP) and office (fixed IP range)
sudo vless set-allowed-ips alice 203.0.113.45,198.51.100.0/24

# Verify
sudo vless show-allowed-ips alice
```

#### Scenario 2: VPN-Only Access

```bash
# Only allow connections after VPN connection (via VLESS)
# Assuming your VPN assigns 10.x.x.x addresses
sudo vless set-allowed-ips alice 10.0.0.0/8

# Now user must:
# 1. Connect to VLESS VPN first (gets IP like 10.8.0.2)
# 2. Then use SOCKS5/HTTP proxy through the VPN tunnel
```

#### Scenario 3: Multi-Region Team

```bash
# Allow access from 3 office locations
sudo vless set-allowed-ips dev-team \
  198.51.100.0/24,\      # US office
  203.0.113.0/24,\       # EU office
  192.0.2.0/24           # Asia office
```

#### Scenario 4: Development Account (Localhost Only)

```bash
# Restrict test account to localhost (default behavior)
sudo vless reset-allowed-ips test-user

# Output: Allowed IPs reset to 127.0.0.1 (localhost only)
```

#### Scenario 5: Dynamic IP Workaround

```bash
# For users with dynamic IPs, use larger CIDR range
# Example: ISP assigns IPs in 203.0.112.0/22 range
sudo vless set-allowed-ips alice 203.0.112.0/22

# Or: Allow entire country IP blocks (use caution!)
# Consult IP geolocation databases for country ranges
```

### How It Works

IP whitelisting uses **Xray routing rules** to filter proxy connections at the application level:

1. **User connects** to SOCKS5/HTTP proxy with credentials
2. **Xray matches** the user (email format: `alice@vless.local`)
3. **Xray checks** source IP against user's `allowed_ips` array
4. **If match**: Connection routed to `direct` outbound (allowed)
5. **If no match**: Connection routed to `blackhole` outbound (blocked)

**Technical Details:**
- Routing rules stored in `xray_config.json` (auto-generated)
- IP list stored in `users.json` (field: `allowed_ips`)
- Changes applied via Xray container reload (< 3 seconds)
- Evaluation order: Per-user rules first, catch-all block last

### Viewing Current Configuration

```bash
# Check user's allowed IPs
sudo vless show-allowed-ips alice

# Output:
# ═══════════════════════════════════════════════════════
#   ALLOWED IPS: alice
# ═══════════════════════════════════════════════════════
#
# User: alice
#
# Allowed Source IPs:
#   • 127.0.0.1
#   • 203.0.113.45
#   • 10.0.0.0/24
#
# ═══════════════════════════════════════════════════════
#
# These IPs can connect to the proxy server using this user's credentials.
# Connections from other IPs will be blocked.

# View routing rules in Xray config
sudo jq '.routing.rules' /opt/vless/config/xray_config.json
```

### Best Practices

1. **Start restrictive**: Begin with localhost-only (`127.0.0.1`), add IPs as needed
2. **Use CIDR notation**: For IP ranges (office networks, VPN subnets)
3. **Document IP sources**: Maintain a spreadsheet mapping IPs to locations/users
4. **Review quarterly**: Remove stale IPs from departing employees/changed locations
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

### Troubleshooting

**Problem: Connection blocked after setting allowed IPs**
```bash
# Check current IP list
sudo vless show-allowed-ips alice

# Verify your source IP
curl -s https://ifconfig.me

# Add your IP if missing
sudo vless add-allowed-ip alice $(curl -s https://ifconfig.me)

# Check Xray logs for blocks
sudo vless logs xray | grep "rejected"
```

**Problem: User reports intermittent access**
```bash
# Likely cause: Dynamic IP changing
# Solution 1: Use CIDR range for ISP block
sudo vless set-allowed-ips alice 203.0.112.0/22

# Solution 2: VPN-only mode
sudo vless set-allowed-ips alice 10.0.0.0/8
```

**Problem: Need to temporarily disable IP filtering**
```bash
# Allow all IPs (NOT recommended for production)
# Use 0.0.0.0/0 for IPv4, ::/0 for IPv6
sudo vless set-allowed-ips alice 0.0.0.0/0

# Better: Use localhost + user's current IP
sudo vless set-allowed-ips alice 127.0.0.1,$(curl -s https://ifconfig.me)
```

### Technical Implementation

**Files Modified:**
- `lib/user_management.sh`: IP management functions (`set_allowed_ips`, `add_allowed_ip`, etc.)
- `lib/orchestrator.sh`: Routing rule generation (`generate_routing_json`)
- `cli/vless`: CLI command handlers
- `data/users.json`: User data with `allowed_ips` field

**Example `users.json` entry:**
```json
{
  "username": "alice",
  "uuid": "12345678-1234-1234-1234-123456789012",
  "proxy_password": "a1b2c3d4e5f67890a1b2c3d4e5f67890",
  "allowed_ips": ["127.0.0.1", "203.0.113.45", "10.0.0.0/24"],
  "created": "2025-10-06T12:00:00Z"
}
```

**Example Xray routing rule:**
```json
{
  "type": "field",
  "inboundTag": ["socks5-proxy", "http-proxy"],
  "user": ["alice@vless.local"],
  "source": ["127.0.0.1", "203.0.113.45", "10.0.0.0/24"],
  "outboundTag": "direct"
}
```

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

```bash
# Install bats
npm install -g bats

# Run tests
bats tests/unit/              # Unit tests
sudo bats tests/integration/  # Integration tests
sudo bats tests/performance/  # Performance tests
```

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
