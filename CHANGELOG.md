# CHANGELOG

All notable changes to the VLESS Reality VPN Deployment System will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [4.1] - 2025-10-14

### Changed - Heredoc Config Generation

**Migration Type:** Non-Breaking (automatic migration)

**Primary Feature:** Replaced template-based configuration with heredoc-based inline generation

#### Configuration Generation
- **CHANGED**: All config files now generated inline via bash heredoc
  - `lib/stunnel_setup.sh`: stunnel.conf via `create_stunnel_config()` heredoc
  - `lib/orchestrator.sh`: xray_config.json and docker-compose.yml via heredoc
  - `lib/user_management.sh`: Client configs via heredoc
- **REMOVED**: `templates/` directory eliminated (stunnel.conf.template, etc.)
- **REMOVED**: `envsubst` dependency (GNU gettext package no longer required)

#### Proxy URI Schemes
- **FIXED**: Proxy URIs now correctly use TLS-aware schemes (v4.0 bug fix)
  - SOCKS5: `socks5://` → `socks5s://` (TLS over SOCKS5)
  - HTTP: `http://` → `https://` (HTTPS proxy)
  - Applies to all 5 client config formats (socks5_config.txt, http_config.txt, vscode_settings.json, docker_daemon.json, bash_exports.sh)

#### Testing
- **ADDED**: `tests/test_stunnel_heredoc.sh` - Comprehensive heredoc generation validation (12 test cases)
  - Config generation without templates/
  - Domain variable substitution
  - Security settings (TLS 1.3, strong ciphers)
  - File permissions (600 for configs)
  - Template variable absence verification

#### Benefits
- ✅ **Unified Architecture**: All configs use same generation method (heredoc)
- ✅ **Simplified Dependencies**: Fewer system packages required
- ✅ **Easier Maintenance**: Config logic and generation in same file
- ✅ **No Template/Script Split**: Single source of truth for each config
- ✅ **Correct URI Schemes**: Fixed v4.0 plaintext proxy bug

### Migration from v4.0

**Automatic Migration:**
- No user action required
- Existing installations continue to work
- Config regeneration uses heredoc on next user operation

**Manual Verification (Optional):**
```bash
# Verify stunnel config regeneration
sudo cat /opt/vless/config/stunnel.conf | head -n 5
# Should show: "# stunnel TLS Termination Configuration"
# Should show: "# Generated: [timestamp]"

# Verify correct proxy URI schemes
sudo cat /opt/vless/data/clients/YOUR_USER/socks5_config.txt
# Should show: socks5s://user:pass@domain:1080 (NOT socks5://)

sudo cat /opt/vless/data/clients/YOUR_USER/http_config.txt
# Should show: https://user:pass@domain:8118 (NOT http://)

# Regenerate configs if needed (updates URI schemes)
sudo vless regenerate YOUR_USER
```

**Breaking Changes:** None - backward compatible

---

## [4.0] - 2025-10-10

### Added - stunnel TLS Termination

**Migration Type:** Breaking (requires certificate setup for proxy mode)

**Primary Feature:** Dedicated stunnel container for TLS 1.3 termination on proxy ports

#### TLS Termination Architecture
- **ADDED**: stunnel container (`dweomer/stunnel:latest`) for TLS termination
  - Listens on ports 1080 (SOCKS5) and 8118 (HTTP) with TLS 1.3
  - Forwards plaintext to Xray on localhost ports 10800 (SOCKS5) and 18118 (HTTP)
  - Separation of concerns: stunnel = TLS layer, Xray = proxy logic
- **ADDED**: `lib/stunnel_setup.sh` module with 3 functions:
  - `create_stunnel_config()` - Generate stunnel.conf from template
  - `validate_stunnel_config()` - Syntax and certificate validation
  - `setup_stunnel_container()` - Docker service integration
- **ADDED**: `templates/stunnel.conf.template` - stunnel configuration template
  - TLS 1.3 only (`sslVersion = TLSv1.3`)
  - Strong cipher suites (`TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256`)
  - Let's Encrypt certificate integration
  - Separate service definitions for SOCKS5 and HTTP

#### Xray Configuration Changes
- **CHANGED**: SOCKS5 inbound (Xray)
  - Port: 1080 (public) → 10800 (localhost)
  - Listen: `0.0.0.0` → `127.0.0.1`
  - Security: TLS → none (stunnel handles TLS)
- **CHANGED**: HTTP inbound (Xray)
  - Port: 8118 (public) → 18118 (localhost)
  - Listen: `0.0.0.0` → `127.0.0.1`
  - Security: TLS → none (stunnel handles TLS)
- **REMOVED**: TLS streamSettings from proxy inbounds (delegated to stunnel)

#### Template-Based Configuration
- **ADDED**: Template system for all config files
  - `templates/xray_config.json.template`
  - `templates/stunnel.conf.template`
  - `templates/docker-compose.yml.template`
- **ADDED**: Variable substitution via `envsubst`
  - `${DOMAIN}`, `${VLESS_PORT}`, `${DEST_SITE}`, etc.

#### UFW Integration
- **ADDED**: Optional host-level firewall rules for proxy ports
  - `sudo ufw allow 1080/tcp comment 'VLESS SOCKS5 Proxy'`
  - `sudo ufw allow 8118/tcp comment 'VLESS HTTP Proxy'`
  - `sudo ufw limit 1080/tcp` - Rate limiting (10 conn/min)
  - `sudo ufw limit 8118/tcp`

#### Benefits
- ✅ **Mature TLS Stack**: stunnel has 20+ years production stability
- ✅ **Simpler Xray Config**: Xray focuses on proxy logic, no TLS complexity
- ✅ **Better Debugging**: Separate logs for TLS (stunnel) vs proxy (Xray)
- ✅ **Easier Certificate Management**: stunnel uses Let's Encrypt certs directly
- ✅ **Defense-in-Depth**: stunnel + Xray + UFW layered security

### Migration from v3.x

**Prerequisites:**
- Domain name with DNS A record pointing to server IP (required for Let's Encrypt)
- Port 80 accessible (for certificate challenges)

**Automatic Migration:**
```bash
# Update to v4.0 (preserves users and keys)
sudo vless update

# If proxies enabled, system will:
# 1. Install certbot and stunnel
# 2. Prompt for domain name
# 3. Obtain Let's Encrypt certificate
# 4. Generate stunnel.conf from template
# 5. Update docker-compose.yml with stunnel service
# 6. Regenerate Xray config (localhost-only proxy inbounds)
# 7. Restart services
```

**Manual Migration:**

If you prefer manual migration or encounter issues:

```bash
# 1. Backup existing configuration
sudo vless backup create

# 2. Install certbot
sudo apt-get update
sudo apt-get install -y certbot

# 3. Obtain certificate (replace with your domain)
sudo certbot certonly --standalone -d vpn.example.com \
  --email your@email.com --agree-tos --non-interactive

# 4. Update .env with domain
echo "DOMAIN=vpn.example.com" | sudo tee -a /opt/vless/.env

# 5. Regenerate configs
cd /opt/vless
sudo bash lib/stunnel_setup.sh
sudo bash lib/orchestrator.sh

# 6. Restart services
sudo docker-compose down
sudo docker-compose up -d

# 7. Regenerate all user configs (updates URIs to TLS)
for user in $(sudo vless list-users | tail -n +2); do
  sudo vless regenerate "$user"
done
```

**Verification:**
```bash
# Check stunnel container
sudo docker ps | grep stunnel

# Check stunnel logs
sudo docker logs vless-stunnel

# Verify TLS on proxy ports
sudo netstat -tlnp | grep -E ':(1080|8118)'
# Should show: 0.0.0.0:1080 (stunnel) and 0.0.0.0:8118 (stunnel)

# Test SOCKS5 proxy with TLS
curl -s --socks5 user:pass@vpn.example.com:1080 https://ifconfig.me

# Test HTTP proxy with TLS
curl -s --proxy https://user:pass@vpn.example.com:8118 https://ifconfig.me
```

**Breaking Changes:**
- ⚠️ **Proxy ports changed in Xray**: 1080→10800 (SOCKS5), 8118→18118 (HTTP)
  - External access now via stunnel on original ports (1080, 8118)
  - Old client configs will NOT work (regeneration required)
- ⚠️ **Domain required**: Public proxy mode now requires valid domain name
  - Plaintext proxy mode deprecated (security risk)
- ⚠️ **Certificate dependency**: Let's Encrypt certificates required for TLS
  - Auto-renewal configured via cron (twice daily)

**Rollback to v3.x:**
```bash
# 1. Restore backup
sudo vless backup restore /tmp/vless_backup_TIMESTAMP.tar.gz

# 2. Downgrade Xray config (restore v3.x ports)
# Edit /opt/vless/config/xray_config.json:
# - SOCKS5: listen 127.0.0.1:10800 → 0.0.0.0:1080, add TLS streamSettings
# - HTTP: listen 127.0.0.1:18118 → 0.0.0.0:8118, add TLS streamSettings

# 3. Remove stunnel from docker-compose.yml

# 4. Restart
sudo docker-compose down
sudo docker-compose up -d
```

---

## [3.6] - 2025-10-06

### Changed - Server-Level IP Whitelisting

**Migration Type:** Breaking (per-user → server-level IP whitelisting)

#### IP Whitelist Architecture
- **CHANGED**: IP whitelisting moved from per-user to server-level
  - **Reason**: HTTP/SOCKS5 protocols don't provide user identifiers in Xray routing context
  - **Impact**: Single IP whitelist applies to all proxy users
- **ADDED**: `lib/proxy_whitelist.sh` - Server-level IP management module
- **ADDED**: `config/proxy_allowed_ips.json` - Server-level IP whitelist storage
- **ADDED**: `scripts/migrate_proxy_ips.sh` - v3.5 → v3.6 migration script

#### New Commands
- **ADDED**: `vless show-proxy-ips` - Display server-level IP whitelist
- **ADDED**: `vless set-proxy-ips <ip1,ip2,...>` - Set allowed source IPs
- **ADDED**: `vless add-proxy-ip <ip>` - Add IP to whitelist
- **ADDED**: `vless remove-proxy-ip <ip>` - Remove IP from whitelist
- **ADDED**: `vless reset-proxy-ips` - Reset to localhost-only (127.0.0.1)

#### Removed Commands
- **REMOVED**: `vless show-allowed-ips <user>` (per-user command)
- **REMOVED**: `vless set-allowed-ips <user> <ips>` (per-user command)
- **REMOVED**: `vless add-allowed-ip <user> <ip>` (per-user command)
- **REMOVED**: `vless remove-allowed-ip <user> <ip>` (per-user command)

#### Routing Rules
- **CHANGED**: Xray routing rules now server-level
  - Rule applies to both `socks5-proxy` and `http-proxy` inboundTags
  - `source` field contains server-level IP list
  - No `user` field (not supported for proxy protocols)
  - Match → `direct` outbound, No match → `blackhole` outbound

### Migration from v3.5

**Automatic Migration:**
```bash
# Run migration script
sudo /opt/vless/scripts/migrate_proxy_ips.sh

# Script performs:
# 1. Collect all unique IPs from users' allowed_ips fields
# 2. Create proxy_allowed_ips.json with collected IPs
# 3. Regenerate Xray routing rules (server-level)
# 4. Reload Xray container (< 3 seconds downtime)
# 5. Optionally clean up old allowed_ips fields in users.json
```

**Manual Migration:**
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
- ❌ Per-user IP whitelisting no longer supported
- ❌ `allowed_ips` field in users.json deprecated (still present for legacy)
- ✅ Server-level IP whitelist applies to ALL proxy users
- ✅ Individual user IP restrictions not possible (use separate VPN instances)

**Acceptance Criteria:**
- [x] Server-level IP whitelist commands work
- [x] Routing rules enforce server-level IP filtering
- [x] Migration script preserves all unique IPs from v3.5
- [x] Backward compatibility: Legacy allowed_ips field ignored (no errors)
- [x] Zero downtime: IP list updates apply via container reload

---

## [3.5] - 2025-10-04

### Added - Per-User IP Whitelisting (Deprecated in v3.6)

> **Note:** This feature was replaced with server-level IP whitelisting in v3.6 due to protocol limitations.

#### Features (v3.5 only)
- **ADDED**: Per-user IP-based access control for proxy servers
- **ADDED**: `allowed_ips` field in users.json (array of IP/CIDR)
- **ADDED**: Commands for per-user IP management:
  - `vless show-allowed-ips <user>`
  - `vless set-allowed-ips <user> <ip1,ip2,...>`
  - `vless add-allowed-ip <user> <ip>`
  - `vless remove-allowed-ip <user> <ip>`

---

## [3.4] - 2025-10-02

### Added - Optional TLS for Public Proxy Mode

**Migration Type:** Non-Breaking (TLS optional in v3.4, mandatory in v4.0+)

#### TLS Support
- **ADDED**: Optional Let's Encrypt TLS encryption for public proxy mode
  - Installation prompt: "Enable TLS encryption? [Y/n]"
  - YES → Install certbot, obtain certificate, configure TLS
  - NO → Plaintext mode (development/localhost only)
- **ADDED**: `lib/certbot_setup.sh` - Let's Encrypt integration module
  - Certificate issuance automation
  - Auto-renewal cron job (twice daily)
  - Domain validation
- **ADDED**: TLS streamSettings for proxy inbounds (when TLS enabled)
  - SOCKS5: TLS 1.3 on port 1080
  - HTTP: TLS 1.3 on port 8118

#### Proxy Modes
- **TLS Mode** (Production):
  - URI schemes: `socks5s://`, `https://`
  - Requires: Domain name + Let's Encrypt certificate
  - Security: TLS 1.3, fail2ban, rate limiting
- **Plaintext Mode** (Development):
  - URI schemes: `socks5://`, `http://`
  - Requires: No domain, no certificates
  - ⚠️ **WARNING**: Credentials transmitted in plaintext!

### Migration from v3.3

**Enable TLS (Recommended):**
```bash
# 1. Ensure domain DNS points to server
dig +short vpn.example.com
# Should return server IP

# 2. Update installation (enables TLS prompt)
sudo vless update

# 3. Follow prompts:
# - "Enable TLS encryption? [Y/n]" → Y
# - "Enter domain:" → vpn.example.com
# - "Enter email:" → admin@example.com

# 4. Regenerate user configs
for user in $(sudo vless list-users | tail -n +2); do
  sudo vless regenerate "$user"
done

# 5. Verify TLS
curl -s --socks5 user:pass@vpn.example.com:1080 https://ifconfig.me
```

**Keep Plaintext (Not Recommended):**
```bash
# During update, choose "N" for TLS encryption
# Existing plaintext configs continue to work
```

---

## [3.3] - 2025-09-28

### Changed - Mandatory TLS Encryption for Public Proxies

**Migration Type:** Breaking (plaintext → TLS mandatory)

#### TLS Enforcement
- **CHANGED**: Public proxy mode now requires TLS encryption (mandatory)
  - Let's Encrypt certificates auto-configured during installation
  - Domain name required for public proxy mode
  - Plaintext mode deprecated (security risk)
- **CHANGED**: Proxy passwords strengthened
  - Length: 16 characters → 32 characters
  - Entropy: 64 bits → 128 bits
  - Format: Hexadecimal (openssl rand -hex 16)

#### Client Configuration
- **CHANGED**: Proxy URI schemes updated
  - SOCKS5: `socks5://` → `socks5s://` (TLS)
  - HTTP: `http://` → `https://` (TLS)
- **ADDED**: Git proxy configuration support (`git_config.txt`)
- **UPDATED**: All 6 config formats updated for TLS:
  - socks5_config.txt, http_config.txt
  - vscode_settings.json, docker_daemon.json
  - bash_exports.sh, git_config.txt

#### Security Hardening
- **ADDED**: Certificate auto-renewal cron job (twice daily)
- **ADDED**: fail2ban protection for all proxy modes (localhost + public)
  - Monitors Xray authentication logs
  - Bans IP after 5 failed attempts (1-hour ban)
  - Jails: `vless-socks5`, `vless-http`
- **ADDED**: UFW rate limiting for public proxy ports
  - 10 connections per minute per IP
  - Applies to ports 1080, 8118

### Migration from v3.2

**Prerequisites:**
- Domain name with DNS A record
- Port 80 accessible (for Let's Encrypt challenges)

**Migration Steps:**
```bash
# 1. Update installation
sudo vless update

# 2. System prompts for domain (if proxies enabled)
# Enter: vpn.example.com

# 3. System obtains Let's Encrypt certificate
# 4. System regenerates all configs with TLS
# 5. Restart services
sudo vless restart

# 6. Update client applications with new configs
# Old plaintext configs will NOT work

# 7. Test TLS connections
curl -s --socks5 user:pass@vpn.example.com:1080 https://ifconfig.me
curl -s --proxy https://user:pass@vpn.example.com:8118 https://ifconfig.me
```

**Breaking Changes:**
- ❌ Plaintext proxy URIs no longer supported (`socks5://`, `http://`)
- ❌ Domain required for public proxy mode (no workaround)
- ❌ All existing client configs must be regenerated
- ✅ Enhanced security: TLS 1.3, 32-char passwords, fail2ban

**Acceptance Criteria:**
- [x] All proxy connections encrypted with TLS 1.3
- [x] Let's Encrypt certificates auto-renew
- [x] fail2ban blocks brute-force attempts
- [x] UFW rate limiting active on proxy ports
- [x] All 6 config formats use TLS URI schemes

---

## [3.2] - 2025-09-24

### Added - Localhost-Only Proxy Mode (Deprecated)

> **Note:** Plaintext localhost mode deprecated in v3.3 (TLS mandatory)

#### Features (v3.2 only)
- **ADDED**: SOCKS5 and HTTP proxy servers (localhost binding)
  - SOCKS5: 127.0.0.1:1080
  - HTTP: 127.0.0.1:8118
  - Plaintext (no TLS) - development only
- **ADDED**: Proxy password field in users.json (v1.1)
  - 16-character hexadecimal passwords
  - Auto-generated on user creation
- **ADDED**: Multi-format config export (6 formats):
  - socks5_config.txt, http_config.txt
  - vscode_settings.json, docker_daemon.json
  - bash_exports.sh
- **ADDED**: Proxy credential management commands:
  - `vless show-proxy <user>`
  - `vless reset-proxy-password <user>`

---

## [3.1] - 2025-09-20

### Added - Dual Proxy Support Foundation

#### Features
- **ADDED**: Xray inbound configuration for SOCKS5 and HTTP
  - Localhost binding (127.0.0.1)
  - Password authentication
  - Plaintext (no TLS in v3.1)
- **ADDED**: Docker network isolation
  - Separate bridge network (vless_reality_net)
  - Automatic subnet detection
  - Multi-VPN coexistence support

---

## [3.0] - 2025-09-15

### Added - Production-Ready VPN Core

#### Features
- **ADDED**: VLESS + Reality protocol implementation
  - X25519 key pair generation
  - TLS 1.3 masquerading
  - DPI resistance
- **ADDED**: User management system
  - UUID generation (uuidgen)
  - JSON-based user storage (users.json v1.0)
  - QR code generation (PNG + ANSI)
- **ADDED**: Service operations
  - start, stop, restart, status, logs
  - Zero-downtime config reloads
- **ADDED**: Nginx fake-site fallback
  - Proxies invalid connections to dest site
  - Enhances DPI resistance
- **ADDED**: UFW firewall integration
  - Docker forwarding support
  - Port rule management
  - Subnet conflict detection

---

## Version History Summary

| Version | Date | Primary Feature | Migration Type |
|---------|------|----------------|----------------|
| **4.1** | 2025-10-14 | Heredoc config generation | Non-Breaking |
| **4.0** | 2025-10-10 | stunnel TLS termination | Breaking |
| **3.6** | 2025-10-06 | Server-level IP whitelisting | Breaking |
| **3.5** | 2025-10-04 | Per-user IP whitelisting | Non-Breaking |
| **3.4** | 2025-10-02 | Optional TLS for proxies | Non-Breaking |
| **3.3** | 2025-09-28 | Mandatory TLS for proxies | Breaking |
| **3.2** | 2025-09-24 | Localhost-only proxy mode | Non-Breaking |
| **3.1** | 2025-09-20 | Dual proxy support foundation | Non-Breaking |
| **3.0** | 2025-09-15 | Production-ready VPN core | Initial Release |

---

## Upgrade Path

### From v3.x to v4.1 (Recommended)

**Direct upgrade** (preserves all user data and keys):

```bash
# 1. Backup current installation
sudo vless backup create

# 2. Update to latest version
sudo vless update

# 3. Follow prompts for:
# - Domain name (if proxy mode enabled)
# - Let's Encrypt email
# - Certificate issuance

# 4. Verify services
sudo vless status

# 5. Regenerate all user configs (updates URI schemes to v4.1)
for user in $(sudo vless list-users | tail -n +2); do
  sudo vless regenerate "$user"
done

# 6. Test proxy connections
curl -s --socks5 user:pass@domain:1080 https://ifconfig.me
curl -s --proxy https://user:pass@domain:8118 https://ifconfig.me
```

### Rollback Procedures

**v4.1 → v4.0:**
```bash
# No breaking changes - configs compatible
# Only heredoc generation method changed
```

**v4.0 → v3.6:**
```bash
# 1. Restore backup
sudo vless backup restore /tmp/vless_backup_TIMESTAMP.tar.gz

# 2. Reconfigure Xray for direct TLS (remove stunnel)
# 3. Update docker-compose.yml (remove stunnel service)
# 4. Restart services
```

**v3.6 → v3.5:**
```bash
# Convert server-level IP whitelist to per-user
# NOT RECOMMENDED - v3.5 architecture has protocol limitations
```

---

## Support

- **Documentation**: [README.md](README.md), [CLAUDE.md](CLAUDE.md), [PRD.md](PRD.md)
- **Issues**: GitHub Issues
- **Migration Guides**: See individual version sections above
