# VLESS Reality VPN Deployment System

**Version**: 3.2
**Status**: Production Ready
**License**: MIT

---

## Overview

Production-grade CLI-based VLESS+Reality VPN deployment system enabling users to install, configure, and manage Reality protocol servers in under 5 minutes. Features automated dependency installation, Docker orchestration, comprehensive user management, **dual proxy server support (SOCKS5 + HTTP)** with optional public internet access, and defense-in-depth security hardening including fail2ban integration.

---

## Features

### Core Capabilities

- **One-Command Installation**: Complete setup in < 5 minutes
- **Automated Dependency Management**: Docker, UFW, jq, qrencode auto-install
- **Reality Protocol**: TLS 1.3 masquerading for undetectable VPN traffic
- **Dual Proxy Support**: SOCKS5 (port 1080) + HTTP (port 8118) proxies with public internet access option (v3.2)
- **User Management**: Create/remove users in < 5 seconds with UUID generation
- **Multi-Format Config Export**: 5 proxy config formats (SOCKS5, HTTP, VSCode, Docker, Bash)
- **QR Code Generation**: 400x400px PNG + ANSI terminal variants
- **Service Operations**: Start/stop/restart with zero-downtime reloads
- **Security Hardening**: CIS Docker Benchmark compliance, defense-in-depth
- **Automated Updates**: Configuration-preserving system updates
- **Comprehensive Logging**: ERROR/WARN/INFO filtering with real-time streaming

### Security Features

- Defense-in-depth firewall (UFW + iptables)
- Container security (capability dropping, read-only root, no-new-privileges)
- **Public Proxy Mode** (v3.2): Optional internet-accessible SOCKS5/HTTP proxies with advanced protection:
  - **Fail2ban Integration**: Automatic IP banning after 5 failed authentication attempts (1-hour ban)
  - **UFW Rate Limiting**: 10 connections per minute per IP
  - **Enhanced Passwords**: 32-character random passwords (2^128 entropy vs 2^64 in v3.1)
  - **Docker Healthchecks**: Automated container health monitoring
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
# 4. Enable public proxy access? [y/N] ← v3.2: Public SOCKS5 + HTTP proxies
#    - Choose 'y' for internet-accessible proxies (fail2ban, rate limiting enabled)
#    - Choose 'N' for VLESS-only mode (default, safer)
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
#   - socks5_config.txt, http_config.txt (Proxy URIs)
#   - vscode_settings.json, docker_daemon.json, bash_exports.sh
```

---

## Security Warnings (v3.2 Public Proxy Mode)

⚠️ **IMPORTANT**: If you enable public proxy access during installation, please review these security considerations:

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

### Automatic Security Measures (v3.2)

When you enable public proxy mode, the installer automatically configures:

1. **Fail2ban Protection**
   - Monitors Xray authentication logs
   - Bans IP after 5 failed attempts
   - Ban duration: 1 hour
   - Check status: `sudo fail2ban-client status vless-socks5`

2. **UFW Rate Limiting**
   - Limits connections to 10 per minute per IP
   - Applies to ports 1080 (SOCKS5) and 8118 (HTTP)
   - Prevents connection flood attacks

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

### Migration from v3.1 to v3.2

See [MIGRATION_v3.1_to_v3.2.md](MIGRATION_v3.1_to_v3.2.md) for detailed upgrade instructions.

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

# NEW: Proxy credential management
vless show-proxy <username>            # Show SOCKS5/HTTP credentials
vless reset-proxy-password <username>  # Reset proxy password (regenerates configs)
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

### Proxy Usage Examples (NEW)

After connecting to VPN, use the proxies:

```bash
# Terminal: SOCKS5 proxy
curl --socks5 alice:password@127.0.0.1:1080 https://ifconfig.me

# Terminal: HTTP proxy
curl --proxy http://alice:password@127.0.0.1:8118 https://ifconfig.me

# Bash: Set environment variables
source /opt/vless/data/clients/alice/bash_exports.sh
curl https://ifconfig.me  # Uses proxy automatically

# VSCode: Copy proxy settings
cp /opt/vless/data/clients/alice/vscode_settings.json .vscode/settings.json

# Docker: Configure daemon
sudo cp /opt/vless/data/clients/alice/docker_daemon.json /etc/docker/daemon.json
sudo systemctl restart docker
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

- **Development Time**: 182 hours (176h base + 6h proxy integration)
- **Modules**: 14
- **Functions**: ~138 (120 base + 18 proxy-related)
- **Test Cases**: ~130 (100 base + 30 proxy tests)
- **Lines of Code**: ~6,500 (6,000 base + 500 proxy)
- **Status**: Production Ready
- **Latest Update**: v3.1 - Dual Proxy Support (SOCKS5 + HTTP)

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
│   ├── xray_config.json    # 3 inbounds (VLESS + SOCKS5 + HTTP)
│   └── users.json          # v1.1 with proxy_password field
└── data/clients/<user>/
    ├── vless_config.json   # VLESS config
    ├── socks5_config.txt   # NEW: SOCKS5 URI
    ├── http_config.txt     # NEW: HTTP URI
    ├── vscode_settings.json # NEW: VSCode proxy
    ├── docker_daemon.json  # NEW: Docker proxy
    └── bash_exports.sh     # NEW: Bash env vars
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
