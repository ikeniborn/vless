# VLESS Reality VPN Deployment System

**Version**: 3.3
**Status**: Production Ready
**License**: MIT

---

## Overview

Production-grade CLI-based VLESS+Reality VPN deployment system enabling users to install, configure, and manage Reality protocol servers in under 5 minutes. Features automated dependency installation, Docker orchestration, comprehensive user management, **dual proxy server support (SOCKS5 + HTTP) with mandatory TLS encryption** for public access (v3.3), Let's Encrypt certificate automation, and defense-in-depth security hardening including fail2ban integration.

---

## Features

### Core Capabilities

- **One-Command Installation**: Complete setup in < 5 minutes
- **Automated Dependency Management**: Docker, UFW, certbot, jq, qrencode auto-install
- **Reality Protocol**: TLS 1.3 masquerading for undetectable VPN traffic
- **Dual Proxy Support (v3.3)**: SOCKS5 (port 1080) + HTTP (port 8118) proxies with:
  - **Mandatory TLS 1.3 encryption** for public access
  - **Let's Encrypt certificates** with auto-renewal
  - **Domain-based URIs** (socks5s://, https://)
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
- **Public Proxy Mode (v3.3)**: Internet-accessible SOCKS5/HTTP proxies with production-grade security:
  - **TLS 1.3 Encryption**: Mandatory encryption via Let's Encrypt certificates
  - **Certificate Auto-Renewal**: Automated certificate renewal (cron-based, twice daily)
  - **Fail2ban Integration**: Automatic IP banning after 5 failed authentication attempts (1-hour ban)
  - **UFW Rate Limiting**: 10 connections per minute per IP
  - **Enhanced Passwords**: 32-character random passwords (2^128 entropy)
  - **Docker Healthchecks**: Automated container health monitoring
  - **Domain Validation**: DNS checks before certificate issuance
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
# 4. Enable public proxy access? [y/N] ← v3.3: TLS-encrypted SOCKS5 + HTTP proxies
#    - Choose 'y' for internet-accessible proxies (requires domain, Let's Encrypt cert)
#    - Choose 'N' for VLESS-only mode (default, no domain required)
# 5. If 'y': Enter domain name (e.g., vpn.example.com)
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

## Security Notes (v3.3 Public Proxy Mode)

✅ **v3.3 NOW PRODUCTION-READY**: Public proxy mode now uses mandatory TLS 1.3 encryption via Let's Encrypt certificates.

### When to Use Public Proxy Mode

✅ **Recommended for:**
- Private VPS with trusted users only
- Development and testing environments
- Users who cannot install VPN clients (restrictive networks, mobile devices)
- Scenarios requiring proxy WITHOUT VPN connection

❌ **NOT recommended for:**
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
