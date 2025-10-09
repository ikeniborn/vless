# Changelog - VLESS Reality VPN

**Current Version:** 4.1
**Release Date:** 2025-10-07
**Type:** Refactoring + Bug Fix

---

## v4.1 (2025-10-07) - Heredoc Migration + URI Fix

### Overview

Version 4.1 completes codebase unification and fixes critical proxy URI scheme bug.

**Key Changes:**
1. ✅ **Config Generation Unification** - stunnel migrated from template to heredoc
2. ✅ **Proxy URI Scheme Fix** - https:// and socks5s:// for public mode
3. ✅ **Simplified Dependencies** - removed envsubst requirement
4. ✅ **Automated Testing** - added test coverage

---

### 🔧 REFACTOR: stunnel Config Generation

**Problem:**
- stunnel used template-based generation (envsubst)
- Xray and docker-compose used heredoc
- Inconsistent approaches complicated maintenance

**Solution:**
- Migrated stunnel to heredoc (matching Xray/docker-compose)
- Removed `templates/` directory
- Removed envsubst dependency

**Files Changed:**
- `lib/stunnel_setup.sh` - `create_stunnel_config()` rewritten
- `templates/stunnel.conf.template` - deleted
- `templates/` - directory removed

**Before (v4.0 - template):**
```bash
readonly STUNNEL_TEMPLATE="${TEMPLATE_DIR}/stunnel.conf.template"

create_stunnel_config() {
    envsubst '${DOMAIN}' < "$STUNNEL_TEMPLATE" > "$STUNNEL_CONFIG"
}
```

**After (v4.1 - heredoc):**
```bash
create_stunnel_config() {
    local domain="$1"
    cat > "$STUNNEL_CONFIG" <<EOF
cert = /certs/live/$domain/fullchain.pem
key = /certs/live/$domain/privkey.pem
...
EOF
}
```

**Benefits:**
- ✅ Unified with Xray/docker-compose approach
- ✅ Fewer files (1 instead of 2)
- ✅ No envsubst dependency
- ✅ All logic in one place

**Testing:** 12/12 automated tests passed

**Rationale:**
For stunnel config (111 lines, 1 variable), heredoc benefits outweigh template separation. Consistency across codebase more important than visual separation.

---

### 🐛 BUGFIX: Proxy URI Schemes

**Problem:**
Proxy config generation used wrong URI schemes for public mode with TLS:
- HTTP proxy: `http://` instead of `https://`
- SOCKS5 proxy: `socks5://` instead of `socks5s://`

Client applications couldn't connect to proxy via TLS.

**Solution:**
Updated `lib/user_management.sh` functions:

**1. export_http_config() (line 994)**
```bash
# Before
scheme="http"  # HTTP CONNECT protocol

# After
scheme="https"  # HTTPS proxy with TLS
```

**2. export_socks5_config() (line 1000)**
```bash
# Before
scheme="socks5"  # SOCKS5 protocol

# After
scheme="socks5s"  # SOCKS5 with TLS
```

**3. show_proxy_credentials() (lines 694-760)**
- Rewrote for dynamic scheme selection based on mode
- Reads `ENABLE_PUBLIC_PROXY` and `DOMAIN` from .env
- Dynamically selects: `http/https` and `socks5/socks5s`
- Dynamically selects host: `127.0.0.1` or `${DOMAIN}`

**4. reset_proxy_password() (lines 889-934)**
- Updated for correct URI display after password reset

**Result:**

**Localhost mode (ENABLE_PUBLIC_PROXY=false):**
```
HTTP:   http://username:password@127.0.0.1:8118
SOCKS5: socks5://username:password@127.0.0.1:1080
```

**Public mode with TLS (ENABLE_PUBLIC_PROXY=true):**
```
HTTP:   https://username:password@domain:8118
SOCKS5: socks5s://username:password@domain:1080
```

**Testing:** 5/5 automated test scenarios passed

**Backward Compatibility:** Full - other functions already used correct schemes

---

### 📦 Dependency Changes

**Removed:**
- envsubst (GNU gettext) - no longer required

**Current dependencies:**
- bash 4.0+
- jq 1.5+
- openssl
- docker 20.10+
- docker compose v2.0+

---

### 🧪 Testing

**New test suites:**
1. `tests/test_stunnel_heredoc.sh` - 12 test cases
   - Config generation validation
   - Variable substitution
   - File permissions
   - Docker compatibility

2. `tests/test_proxy_uri_generation.sh` - 5 scenarios
   - Localhost mode URIs
   - Public mode TLS URIs
   - VSCode config
   - Docker config
   - Bash config

**Results:**
```
stunnel Heredoc Test:      12/12 PASSED ✓
Proxy URI Generation Test:  5/5 PASSED ✓
─────────────────────────────────────────
Total:                     17/17 PASSED ✓
```

---

### 📚 Documentation

**Created:**
- `CHANGELOG.md` - this file
- `docs/SECURITY_TESTING.md` - optimized security guide
- `docs/MIGRATION.md` - v4.0→v4.1 migration notes

**Updated:**
- `PRD.md` - marked template approach as deprecated for stunnel
- `CLAUDE.md` - updated architecture description

**Removed (legacy):**
- 19 obsolete documentation files (module reports, old migrations, etc.)

---

## v4.0 (2025-10-06) - stunnel Integration

### Key Features

**PRIMARY:** stunnel-based TLS termination architecture

**Changes:**
- Separated TLS termination (stunnel) from proxy logic (Xray)
- Xray inbounds changed to plaintext localhost (10800, 18118)
- stunnel handles TLS 1.3 on public ports (1080, 8118)
- Template-based configuration generation

**Architecture:**
```
Client → stunnel (TLS 1.3, ports 1080/8118)
       → Xray (plaintext, localhost 10800/18118)
       → Internet
```

**Benefits:**
1. Mature TLS stack (stunnel 20+ years production)
2. Simpler Xray configuration
3. Better debugging (separate logs)
4. Easier certificate management

**Migration:** v3.x installations automatically migrated

---

## v3.6 (2025-10-06) - Server-Level IP Whitelist

**PRIMARY:** Migrated from per-user to server-level IP whitelisting

**Breaking Change:** HTTP/SOCKS5 protocols don't provide user identifiers in Xray routing context. The `user` field only works for VLESS protocol.

**New file:** `proxy_allowed_ips.json` in `/opt/vless/config/`

**Default:** `["127.0.0.1"]` (localhost-only)

**CLI commands (5):**
```bash
vless show-proxy-ips
vless set-proxy-ips <ips>
vless add-proxy-ip <ip>
vless remove-proxy-ip <ip>
vless reset-proxy-ips
```

---

## v3.5 (2025-10-06) - Per-User IP Whitelisting

⚠️ **DEPRECATED in v3.6** - See migration notes

**Feature:** Per-user IP-based access control using Xray routing rules

**Issue:** Protocol limitation - doesn't work for HTTP/SOCKS5

---

## v3.4 (2025-10-05) - Optional TLS

**Feature:** Made TLS encryption optional for proxy mode

**Modes:**
- TLS Mode (production) - socks5s://, https://
- Plaintext Mode (dev/testing) - socks5://, http://
- Localhost Mode - 127.0.0.1 only

**Rationale:** Allow development without domain requirements

---

## v3.3 (2025-10-05) - Mandatory TLS Encryption

⚠️ **CRITICAL SECURITY FIX**

**Feature:** Mandatory TLS 1.3 encryption for public proxies

**Changes:**
- Let's Encrypt integration
- Automatic certificate renewal (certbot)
- Fail2ban protection
- UFW rate limiting (10 conn/min)
- 32-character passwords

**Migration:** All v3.2 configs invalidated (security)

---

## v3.2 (2025-10-04) - Public Proxy Support

⚠️ **SECURITY ISSUE: No encryption** - Fixed in v3.3

**Feature:** SOCKS5 and HTTP proxies accessible from internet

**Changes:**
- Binding: `127.0.0.1` → `0.0.0.0`
- Password length: 16 → 32 characters
- Fail2ban auto-configuration

**Issue:** Plaintext credentials exposure (fixed in v3.3)

---

## v3.1 (2025-10-03) - Dual Proxy Support

**Feature:** SOCKS5 (1080) + HTTP (8118) proxies

**Mode:** Localhost-only (127.0.0.1)
**Requirement:** VPN connection required first
**Security:** No TLS (localhost assumption)

**Config files generated (6):**
- socks5_config.txt
- http_config.txt
- vscode_settings.json
- docker_daemon.json
- bash_exports.sh
- git_config.txt

---

## v3.0 (2025-10-01) - Base VLESS Reality VPN

**Initial release**

**Features:**
- VLESS protocol with Reality masquerading
- TLS 1.3 via Reality protocol
- X25519 key generation
- Docker Compose deployment
- UFW firewall integration
- QR code generation

---

## Breaking Changes Summary

| Version | Breaking Changes | Migration Required |
|---------|------------------|-------------------|
| v4.1 | None | No (backward compatible) |
| v4.0 | Xray inbound ports changed (internal) | Automatic |
| v3.6 | Per-user IP whitelisting removed | Migration script provided |
| v3.3 | All proxy configs invalidated (TLS) | Regenerate all configs |
| v3.2 | None | No |

---

## Upgrade Path

### v4.0 → v4.1
**Impact:** None (internal refactoring only)
**Action:** None required

### v3.x → v4.1
**Impact:** Architecture change (stunnel)
**Action:** Run installer update, no config regeneration needed

### v3.2 → v3.3 → v4.1
**Impact:** High (TLS mandatory)
**Action:**
1. Obtain domain + email
2. Update installation
3. Regenerate all user configs
4. Distribute new configs to users

---

## Future Roadmap

Planned features (not committed):
- [ ] Web UI for management
- [ ] Multi-node load balancing
- [ ] Custom certificate support (beyond Let's Encrypt)
- [ ] Advanced routing rules
- [ ] Bandwidth quotas per user

---

**Report Issues:** https://github.com/anthropics/vless-reality-vpn/issues
**Documentation:** See `docs/` directory
