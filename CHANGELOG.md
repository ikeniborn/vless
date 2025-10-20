# CHANGELOG

All notable changes to the VLESS Reality VPN Deployment System will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [5.8] - 2025-10-20

### Added - Reverse Proxy Cookie/URL Rewriting & Complex Auth Support

**Migration Type:** Non-breaking (automatic for new proxies, manual fix for existing)

**Primary Feature:** Advanced cookie and URL rewriting for complex authentication scenarios (OAuth2, Google Auth, session-based auth, CSRF protection)

#### Changes

**lib/nginx_config_generator.sh (v5.8.0)**
- **ADDED**: Cookie domain rewriting (`proxy_cookie_domain`)
  - Rewrites cookies from target site domain to proxy domain
  - Required for: session persistence, OAuth2 state cookies, authentication cookies
  - Example: `proxy_cookie_domain kinozal.tv kinozal-dev.ikeniborn.ru;`

- **ADDED**: Cookie path and flags configuration
  - `proxy_cookie_path / /;` - preserve cookie paths
  - `proxy_cookie_flags ~ secure httponly samesite=lax;` - modern security standards
  - SameSite=lax by default (prevents CSRF, allows same-site navigation)

- **ADDED**: URL rewriting in HTML/JS/CSS (`sub_filter`)
  - Replaces target site URLs with proxy domain URLs in responses
  - Covers: https://, http://, protocol-relative URLs
  - Applies to: text/html, text/css, text/javascript, application/javascript
  - Example: `sub_filter 'https://kinozal.tv' 'https://kinozal-dev.ikeniborn.ru';`

- **ADDED**: Origin header rewriting for CORS
  - Sets Origin to target site for proper CORS handling
  - Required for: POST/PUT/DELETE requests, API calls, AJAX
  - Example: `proxy_set_header Origin "https://kinozal.tv";`

- **UPDATED**: File header comments
  - Version: 5.8.0
  - Date: 2025-10-20
  - Added feature description: "Cookie/URL rewriting for complex auth"

**lib/reverseproxy_db.sh (v5.8.0)**
- **ADDED**: `get_next_available_port()` function
  - Checks occupied ports in both database AND nginx configs
  - Prevents port conflicts when adding multiple reverse proxies
  - Replaces naive `get_next_port()` (which only checked DB)
  - Returns first free port in range 9443-9452

- **EXPORTED**: New function in module exports
  - Added `export -f get_next_available_port`

**scripts/vless-setup-proxy**
- **UNCHANGED**: Uses existing `get_next_available_port()` from reverseproxy_db.sh
  - Wizard already calls this function (line 295)
  - No code changes needed (automatic benefit from improved function)

#### Technical Details

**Why These Changes:**

1. **Cookie Domain Rewriting**
   - Problem: Sites set cookies for their own domain (e.g., `Set-Cookie: session=xyz; Domain=kinozal.tv`)
   - Without rewrite: Browser won't send these cookies to proxy domain (kinozal-dev.ikeniborn.ru)
   - Solution: `proxy_cookie_domain` rewrites Domain attribute to match proxy domain
   - Impact: Session persistence, login state, OAuth2 state preservation

2. **URL Rewriting**
   - Problem: Sites embed absolute URLs in HTML/JS (e.g., `href="https://kinozal.tv/profile"`)
   - Without rewrite: Clicks navigate directly to target site (bypassing proxy)
   - Solution: `sub_filter` replaces target URLs with proxy URLs
   - Impact: User stays on proxy domain, maintains authenticated state

3. **Origin Header Rewriting**
   - Problem: Sites validate Origin header for CSRF protection
   - Without rewrite: Target site sees `Origin: https://kinozal-dev.ikeniborn.ru` and rejects
   - Solution: `proxy_set_header Origin` sets correct target domain
   - Impact: POST/PUT/DELETE requests work, APIs accept requests

4. **Port Conflict Prevention**
   - Problem: Wizard suggested port 9443 for 2nd proxy (already used by 1st)
   - Without fix: Nginx fails to start, both proxies down
   - Solution: Check both DB and actual configs before suggesting port
   - Impact: Reliable multi-proxy deployments

#### Migration Guide (For Existing Proxies)

**Affected:** Reverse proxies created BEFORE v5.8

**Symptoms:**
- Login works but session not preserved after page refresh
- Redirects navigate to target site instead of proxy domain
- POST/PUT/DELETE requests fail with CORS errors

**Fix (Apply to each existing proxy):**

1. Edit nginx config:
   ```bash
   sudo nano /opt/vless/config/reverse-proxy/<domain>.conf
   ```

2. Add after `proxy_busy_buffers_size 32k;` (inside `location /` block):
   ```nginx
   # v5.8: Cookie domain rewrite (CRITICAL for authorization)
   proxy_cookie_domain <target_site> <proxy_domain>;
   proxy_cookie_path / /;
   proxy_cookie_flags ~ secure httponly samesite=lax;

   # v5.8: URL rewriting in HTML (for absolute links)
   sub_filter 'https://<target_site>' 'https://<proxy_domain>';
   sub_filter 'http://<target_site>' 'https://<proxy_domain>';
   sub_filter_once off;
   sub_filter_types text/css text/javascript application/javascript;

   # v5.8: Origin header rewriting (for CORS)
   proxy_set_header Origin "https://<target_site>";
   ```

3. Replace `<target_site>` and `<proxy_domain>` with actual values

4. Test config: `docker exec vless_nginx_reverseproxy nginx -t`

5. Reload: `docker restart vless_nginx_reverseproxy`

**Example:**
```nginx
# For kinozal-dev.ikeniborn.ru → kinozal.tv
proxy_cookie_domain kinozal.tv kinozal-dev.ikeniborn.ru;
proxy_cookie_path / /;
proxy_cookie_flags ~ secure httponly samesite=lax;

sub_filter 'https://kinozal.tv' 'https://kinozal-dev.ikeniborn.ru';
sub_filter 'http://kinozal.tv' 'https://kinozal-dev.ikeniborn.ru';
sub_filter_once off;
sub_filter_types text/css text/javascript application/javascript;

proxy_set_header Origin "https://kinozal.tv";
```

#### Supported Authentication Scenarios (v5.8)

**Now Working:**
- ✅ Session-based authentication (cookie persistence)
- ✅ Form-based login (username/password)
- ✅ OAuth2 state cookies (basic support)
- ✅ Google Auth session cookies
- ✅ CSRF-protected POST requests
- ✅ Cookie-based JWT tokens
- ✅ Multi-step authentication flows

**Requires v5.9+ (Future):**
- ⚠️ Large cookies >4kb (OAuth2 Proxy)
- ⚠️ WebSocket-based auth
- ⚠️ Content Security Policy (CSP) rewriting
- ⚠️ Regex-based URL rewriting

#### Testing (v5.8)

**Verified scenarios:**
1. kinozal.tv reverse proxy (kinozal-dev.ikeniborn.ru)
   - ✅ Login form authentication
   - ✅ Session cookie preservation
   - ✅ Authenticated page access
   - ✅ POST requests (downloads, comments)

**Recommended testing for your proxy:**
```bash
# Test 1: Login and check cookies
curl -v -k -u "user:pass" "https://<proxy-domain>/login" -c cookies.txt

# Test 2: Use saved cookies for authenticated page
curl -k -b cookies.txt "https://<proxy-domain>/profile"

# Test 3: POST request (should work)
curl -k -b cookies.txt -X POST "https://<proxy-domain>/api/action" -d '{}'
```

#### Files Changed

- `lib/nginx_config_generator.sh` (v5.8.0)
- `lib/reverseproxy_db.sh` (v5.8.0)

#### Related Documents

- **REVERSE_PROXY_IMPROVEMENT_PLAN.md** - Comprehensive plan for v5.9-v6.0
  - Research findings on OAuth2, CSRF, WebSocket, CSP
  - 17 planned improvements across 4 priority tiers
  - Roadmap for enterprise-grade reverse proxy features

---

## [5.7] - 2025-10-20

### Fixed - SOCKS5 Outbound IP Configuration

**Migration Type:** Non-breaking (automatic, configuration change only)

**Primary Fix:** Change SOCKS5 outbound IP from 127.0.0.1 to 0.0.0.0

#### Changes

**lib/orchestrator.sh**
- **CHANGED**: SOCKS5 outbound listen address
  - Before: `"listen": "127.0.0.1"`
  - After: `"listen": "0.0.0.0"`
  - Reason: Allow SOCKS5 proxy to bind to all interfaces (required for Docker networking)

#### Technical Details

**Why This Change:**
- `127.0.0.1` restricts SOCKS5 to localhost only (not accessible from Docker network)
- `0.0.0.0` allows binding to all interfaces (required for HAProxy to connect)
- Xray internal port 10800 is NOT exposed publicly (docker-compose ports mapping controls this)

**Security Note:**
- No security impact: port 10800 remains localhost-only in docker-compose.yml
- HAProxy TLS termination still protects external connections on port 1080

---

## [5.6] - 2025-10-20

### Fixed - Installation Step Order for Xray Permissions

**Migration Type:** Non-breaking (installation script improvement)

**Primary Fix:** Reorder installation steps to fix Xray permission error on fresh installations

#### Issue

- **PROBLEM**: Xray container crashes on startup with "failed to read config: open config.json: permission denied"
- **ROOT CAUSE**: Installation creates /opt/vless/config/xray_config.json with root:root 600 permissions BEFORE starting containers
- **SYMPTOM**: Container user (nobody:nogroup or uid 65534) cannot read config file

#### Fixed Components

**HOTFIX_XRAY_PERMISSIONS.md**
- Added detailed troubleshooting guide
- Documented production resolution (service restart after permission fix)

**lib/orchestrator.sh**
- **CHANGED**: Installation step order
  - Step 12: Generate Xray config (root:root 600)
  - Step 13: **NEW** - Fix file permissions BEFORE container start
  - Step 14: Start Docker services
- **ADDED**: `fix_xray_config_permissions()` function call after config generation
- No longer relying on container startup to fix permissions

#### Installation Flow (v5.6)

**Before (v5.5 and earlier):**
```bash
1. Generate xray_config.json (root:root 600)
2. Start containers
3. Container fails to read config → crash
4. Wait for crash
5. Fix permissions
6. Restart containers
```

**After (v5.6):**
```bash
1. Generate xray_config.json (root:root 600)
2. Fix permissions IMMEDIATELY (root:root 644)
3. Start containers
4. Container reads config successfully → no crash
```

---

## [5.5] - 2025-10-20

### Added - Xray Permission Verification & Debug Logging

**Migration Type:** Non-breaking (monitoring improvement)

**Primary Feature:** Add permission verification and debug logging to prevent Xray crashes

#### Added Components

**lib/orchestrator.sh**
- **ADDED**: `fix_xray_config_permissions()` function
  - Checks /opt/vless/config/xray_config.json permissions
  - Sets correct permissions: 644 (root:root, readable by all)
  - Validates file exists and is readable
  - Logs before/after permissions

- **ADDED**: Debug logging for Xray startup
  - Logs Xray container status after startup
  - Logs first 20 lines of Xray logs for diagnostics
  - Helps identify permission issues early

#### Technical Details

**Permission Requirements:**
- Xray config must be readable by container user (nobody:nogroup, uid 65534)
- Recommended: 644 (root:root) - secure and readable
- Alternative: 777 (not recommended, used only as emergency fallback)

**Debug Output:**
```bash
[orchestrator] Xray container status: Up 2 seconds (healthy)
[orchestrator] Xray container logs (first 20 lines):
Xray 1.8.1 started successfully
```

---

## [5.4] - 2025-10-20

### Hotfix - Document Xray Container Permission Error

**Migration Type:** Non-breaking (documentation only)

**Primary Change:** Add hotfix documentation for Xray container permission error

#### Added Documentation

**HOTFIX_XRAY_PERMISSIONS.md** (NEW)
- Comprehensive troubleshooting guide for Xray permission errors
- Root cause analysis
- Step-by-step resolution instructions
- Production environment resolution example
- Prevention recommendations for future installations

#### Issue Details

**Problem:**
- Xray container crashes with "failed to read config: open config.json: permission denied"
- File created with 600 permissions (root:root only)
- Container runs as nobody:nogroup (uid 65534)

**Resolution:**
```bash
# Fix permissions
sudo chmod 644 /opt/vless/config/xray_config.json

# Restart services
docker-compose -f /opt/vless/docker-compose.yml restart vless_xray
```

---

## [5.3] - 2025-10-20

### Fixed - Remove Unused Xray HTTP Inbound + IPv6 Fix

**Migration Type:** Non-breaking (cleanup + bug fix)

**Primary Changes:**
1. Remove unused Xray HTTP inbound creation for reverse proxy
2. Update IPv6 nginx configuration fix

#### Fixed Components

**lib/nginx_config_generator.sh**
- **IMPROVED**: IPv6 unreachable error handling documentation
- Updated comments to reflect v5.2 IPv4-only resolution method

**scripts/vless-proxy**
- **REMOVED**: Unused call to `create_xray_http_inbound` function
- Reverse proxy doesn't need dedicated Xray inbound (uses existing HTTP outbound)

**scripts/vless-setup-proxy**
- **REMOVED**: Unused call to `create_xray_http_inbound` function
- Simplifies reverse proxy setup wizard

#### Technical Details

**Why Remove Xray HTTP Inbound Creation:**
- Reverse proxy uses Xray's **outbound** connections (not inbound)
- No need for dedicated inbound port for each reverse proxy
- Reduces complexity and potential port conflicts
- IPv4-only resolution (v5.2) already solves IPv6 unreachable errors

**Architecture Clarification:**
```
Client → HAProxy:443 (SNI) → Nginx:9443 → Xray HTTP Outbound → Target Site
```
No Xray inbound needed for reverse proxy traffic.

---

## [5.2] - 2025-10-20

### Fixed - IPv6 Connectivity & Added IP Monitoring

**Migration Type:** Non-breaking (automatic configuration regeneration + optional monitoring)

**Primary Fix:** IPv6-related "Network unreachable" errors in reverse proxy configurations

#### Issue

- **PROBLEM**: Nginx reverse proxy attempting IPv6 connections to target sites (e.g., claude.ai)
- **SYMPTOM**: Authentication failures, "connect() to [2607:6bc0::10]:443 failed (101: Network unreachable)"
- **ROOT CAUSE**: DNS resolver returns both IPv4 and IPv6 addresses, nginx tries IPv6 first
- **IMPACT**: Reverse proxy authentication fails, upstream temporarily disabled

#### Fixed Components

**1. Nginx Configuration Generator (lib/nginx_config_generator.sh)**

- **ADDED**: `resolve_target_ipv4()` function - resolves target site to IPv4 at config generation time
  - Tries `dig` (preferred), `getent`, then `host` command
  - Returns only IPv4 address (filters out IPv6)
  - Validates IP format with regex

- **CHANGED**: `generate_reverseproxy_nginx_config()` function
  - Now resolves target site to IPv4 **before** generating config
  - `proxy_pass https://$upstream_target` → `proxy_pass https://${target_ipv4}` (hardcoded IPv4)
  - Preserves correct `Host` header and SNI for target site
  - Updated resolver: `resolver 8.8.8.8 valid=300s; resolver_timeout 5s;`
  - Version updated: v4.3 → v5.2

- **FIXED**: Container names in `validate_nginx_config()` and `reload_nginx()`
  - `vless_nginx` → `vless_nginx_reverseproxy` (correct v4.3 container name)

**2. Reverse Proxy Database (lib/reverseproxy_db.sh)**

- **ADDED**: Database schema fields (v5.2)
  - `target_ipv4`: Current IPv4 address of target site
  - `target_ipv4_last_checked`: Timestamp of last IP resolution

- **CHANGED**: `add_proxy()` function
  - Now accepts optional `target_ipv4` parameter (9th argument)
  - Auto-resolves IPv4 if not provided
  - Stores IPv4 in database for monitoring

- **ADDED**: `update_target_ipv4()` function
  - Updates target_ipv4 and target_ipv4_last_checked fields
  - Used by IP monitoring script

**3. IP Monitoring System (NEW)**

**scripts/vless-monitor-reverse-proxy-ips** (NEW)
- Automated IP change detection and config regeneration
- Checks all reverse proxies from database
- Resolves current IPv4 for each target site
- Compares with nginx config `proxy_pass` IP
- Auto-regenerates config if IP changed
- Graceful nginx reload (zero downtime)
- Comprehensive logging to `/opt/vless/logs/reverse-proxy-ip-monitor.log`

**scripts/vless-install-ip-monitoring** (NEW)
- Installs cron job for automatic monitoring
- Schedule: Every 30 minutes + on system reboot (after 5 minutes)
- Creates `/etc/cron.d/vless-ip-monitoring`
- Includes test run during installation
- Uninstall command available

#### New Features

**Automatic IP Monitoring (v5.2)**
- Prevents service disruption from target site IP changes
- Runs every 30 minutes via cron
- Logs all IP changes for audit trail
- Updates database with current IPs
- Zero configuration after installation

#### Installation & Usage

**For New Installations:**
```bash
# IP monitoring installed automatically (future feature)
# For now, install manually after deployment:
sudo /opt/vless/scripts/vless-install-ip-monitoring install
```

**For Existing Installations:**
```bash
# 1. Update scripts (copy from development repo)
sudo cp /home/user/vless/lib/nginx_config_generator.sh /opt/vless/lib/
sudo cp /home/user/vless/lib/reverseproxy_db.sh /opt/vless/lib/
sudo cp /home/user/vless/scripts/vless-monitor-reverse-proxy-ips /opt/vless/scripts/
sudo cp /home/user/vless/scripts/vless-install-ip-monitoring /opt/vless/scripts/
sudo chmod +x /opt/vless/scripts/vless-*.sh

# 2. Update database with IPv4 field (one-time)
sudo jq --arg ip "$(dig +short target-site.com A @8.8.8.8 | head -1)" \
  --arg time "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  '.proxies[] |= . + {target_ipv4: $ip, target_ipv4_last_checked: $time}' \
  /opt/vless/config/reverse_proxies.json > /tmp/rp_updated.json
sudo mv /tmp/rp_updated.json /opt/vless/config/reverse_proxies.json
sudo chmod 600 /opt/vless/config/reverse_proxies.json

# 3. Regenerate nginx configs for all reverse proxies
# (will automatically use IPv4-only proxy_pass)
# Example:
sudo vless-proxy remove your-domain.com
sudo vless-proxy add  # Re-add with wizard

# 4. Install IP monitoring
sudo /opt/vless/scripts/vless-install-ip-monitoring install
```

**Manual Monitoring Commands:**
```bash
# Run monitoring now
sudo /opt/vless/scripts/vless-monitor-reverse-proxy-ips

# View monitoring logs
sudo tail -f /opt/vless/logs/reverse-proxy-ip-monitor.log

# Check cron job status
cat /etc/cron.d/vless-ip-monitoring

# Uninstall monitoring
sudo /opt/vless/scripts/vless-install-ip-monitoring uninstall
```

#### Technical Details

**IPv4 Resolution Method:**
1. Config generation time: Resolve target site to IPv4
2. Hardcode IPv4 in `proxy_pass` directive
3. Preserve original hostname in `Host` header and SNI
4. Monitor IP changes via cron (every 30 min)

**Before (v4.3):**
```nginx
location / {
    set $upstream_target target-site.com;
    proxy_pass https://$upstream_target;  # DNS resolver returns IPv6 first!
    resolver 8.8.8.8 ipv6=off;  # Does NOT prevent IPv6 usage
}
```

**After (v5.2):**
```nginx
location / {
    proxy_pass https://1.2.3.4;  # IPv4 hardcoded (resolved at generation time)
    resolver 8.8.8.8 valid=300s;
    resolver_timeout 5s;
    proxy_ssl_server_name on;
    proxy_ssl_name target-site.com;  # Correct SNI for target
    proxy_set_header Host target-site.com;  # Correct Host header
}
```

#### Affected Files

**Updated:**
- `lib/nginx_config_generator.sh` - IPv4 resolution + config generation
- `lib/reverseproxy_db.sh` - Database schema + IP tracking functions

**New:**
- `scripts/vless-monitor-reverse-proxy-ips` - IP monitoring daemon
- `scripts/vless-install-ip-monitoring` - Cron job installer

**Database:**
- `/opt/vless/config/reverse_proxies.json` - Added `target_ipv4`, `target_ipv4_last_checked` fields

**Logs:**
- `/opt/vless/logs/reverse-proxy-ip-monitor.log` - Monitoring activity log

**Cron:**
- `/etc/cron.d/vless-ip-monitoring` - Automated monitoring schedule

#### Migration Path

**Automatic (future):**
- New installations will include IP monitoring by default

**Manual (current):**
1. Copy updated scripts to `/opt/vless/`
2. Update database schema (add `target_ipv4` fields)
3. Regenerate nginx configs (automatic IPv4-only)
4. Install IP monitoring cron job
5. Test monitoring: `sudo /opt/vless/scripts/vless-monitor-reverse-proxy-ips`

#### Benefits

- ✅ **No more IPv6 unreachable errors** - only IPv4 used
- ✅ **Automatic IP change detection** - prevents outages from IP changes
- ✅ **Zero downtime updates** - graceful nginx reload
- ✅ **Comprehensive logging** - audit trail for all IP changes
- ✅ **Self-healing** - auto-regenerates configs when IPs change

#### Related Issues

- Fixes: Reverse proxy authentication failures on systems without IPv6 routing
- Prevents: Service disruption from target site IP changes (e.g., CDN rotation)

---

## [5.1] - 2025-10-20

### Fixed - HAProxy v4.3 Port Configuration

**Migration Type:** Non-breaking (configuration fix for existing installations)

**Primary Fix:** Xray VLESS inbound port alignment with HAProxy v4.3 architecture

#### Issue
- **PROBLEM**: Xray configured to listen on port 443 (external) instead of 8443 (internal)
- **IMPACT**: vless_xray container unhealthy, HAProxy backend down ("Connection refused")
- **ROOT CAUSE**: Installation scripts using old port configuration (pre-v4.3)

#### Fixed Components

**1. Production Configuration (/opt/vless/config/xray_config.json)**
- **FIXED**: Xray VLESS inbound port: 443 → 8443
- **FIXED**: Fallback container name: vless_nginx → vless_fake_site
- **REASON**: HAProxy v4.3 listens on 443 externally, forwards to Xray:8443 internally

**2. Installation Scripts (lib/)**
- **FIXED**: `lib/interactive_params.sh`
  - DEFAULT_VLESS_PORT: 443 → 8443
  - Added comment: "v4.3 HAProxy Architecture: Xray listens on internal port 8443, HAProxy on external 443"
  - Updated port selection prompt to explain internal vs external ports

- **FIXED**: `lib/orchestrator.sh`
  - Fallback destination: vless_nginx:80 → vless_fake_site:80
  - Aligns with docker-compose.yml container naming

#### Documentation Updates

**CLAUDE.md v5.1:**
- Updated version: 5.0 → 5.1
- Enhanced HAProxy Architecture description (external 443 → internal 8443)
- Added Issue 4 to Common Issues: "Xray Container Unhealthy - Wrong Port Configuration"
  - Detection commands
  - Root cause explanation
  - Step-by-step fix for existing installations
  - Permanent fix for future installations

**Architecture Diagram (already correct in docs/prd/04_architecture.md):**
```
Port 443 (HAProxy, external)
  → SNI Routing → Xray:8443 (internal, VLESS Reality)
```

#### Impact & Migration

**For New Installations:**
- ✅ Automatic - scripts now use correct ports

**For Existing Installations (manual fix):**
```bash
# 1. Fix Xray configuration
sudo sed -i 's/"port": 443,/"port": 8443,/' /opt/vless/config/xray_config.json
sudo sed -i 's/"dest": "vless_nginx:80"/"dest": "vless_fake_site:80"/' /opt/vless/config/xray_config.json

# 2. Restart Xray
docker restart vless_xray

# 3. Verify
docker ps --filter "name=vless_xray" --format "{{.Status}}"  # Should show (healthy)
docker logs vless_haproxy --tail 5 | grep "UP"                # Should show "xray is UP"
```

**Affected Files:**
- `/opt/vless/config/xray_config.json` (production)
- `lib/interactive_params.sh` (installation)
- `lib/orchestrator.sh` (installation)
- `CLAUDE.md` (documentation)
- `CHANGELOG.md` (this file)

**Related Issues:**
- See CLAUDE.md Section "Top-4 Common Issues" → Issue 4

---

## [5.0] - 2025-10-19

### Changed - Documentation Restructuring & Optimization

**Migration Type:** Non-breaking (documentation only)

**Primary Feature:** User-friendly documentation with optimized project memory

#### CLAUDE.md v5.0 Optimization
- **OPTIMIZED**: CLAUDE.md project memory file
  - **Size**: 60 KB → 28 KB (↓ 53%)
  - **Lines**: 1719 → 688 (↓ 60%)
  - **Removed**: ~800 lines of duplication with docs/prd/
  - **Improved**: Navigation, readability, maintainability

#### What Was Removed
- **REMOVED**: Section 17 (PRD Documentation Structure) - 216 lines
  - Replaced with concise Documentation Map (20 lines)
  - Full details in docs/prd/00_summary.md
- **REMOVED**: Section 13 (Technical Details) - 226 lines
  - Detailed configs moved to docs/prd/04_architecture.md
  - Kept only critical parameters and quick reference
- **REMOVED**: Section 10 (NFR) - 91 lines
  - Full list in docs/prd/03_nfr.md
  - Kept top-5 NFR in Quick Reference
- **REMOVED**: Section 12 (Testing Checklist) - 60 lines
  - Full test suite in docs/prd/05_testing.md
  - Kept quick checklist in Quick Reference

#### What Was Compressed
- **COMPRESSED**: Section 9 (Critical Requirements) - 346 → 150 lines
  - Kept top-5 CRITICAL requirements (FR-001, FR-004, FR-011, FR-012, FR-014)
  - Added links to docs/prd/02_functional_requirements.md for full details
- **COMPRESSED**: Section 7 (Critical Parameters) - 214 → 80 lines
  - Removed YAML/bash code examples
  - Kept concise tables with versions and ports
  - Added links to docs/prd/04_architecture.md
- **COMPRESSED**: Section 11 (Failure Points) - 159 → 60 lines
  - Kept top-3 common issues
  - Full troubleshooting in docs/prd/06_appendix.md
- **COMPRESSED**: Section 15 (Security & Debug) - 143 → 70 lines
  - Kept only quick debug commands
  - Full security details in docs/prd/06_appendix.md

#### New Structure
- **ADDED**: Section 10 (Quick Reference) - replaces sections 10-16
  - Top-5 NFR with acceptance criteria
  - Top-3 common issues with solutions
  - Quick debug commands
  - Security testing commands
- **ADDED**: Section 11 (Documentation Map) - replaces section 17
  - Navigation guide for all project documentation
  - PRD quick navigation by use case
  - Version history summary with key changes

#### Benefits
- **Faster Navigation**: Jump to details via links instead of scrolling
- **Single Source of Truth**: docs/prd/ contains all detailed information
- **Easier Maintenance**: Update once in docs/prd/, reference from CLAUDE.md
- **Better Readability**: Shorter sections, clearer structure
- **Reduced Context**: Smaller file loads faster in AI assistants

#### Backup
- Резервная копия: `CLAUDE.md.backup.20251019-104440` (58 KB)
- Для восстановления: `cp CLAUDE.md.backup.20251019-104440 CLAUDE.md`

#### README.md v5.0 Restructuring
- **REWRITTEN**: README.md from technical reference to user-friendly guide
  - **Approach**: "Explain how it works" for ordinary users
  - **Language**: Simple, non-technical Russian
  - **Structure**: What → How → Features → Quick Start → Examples → FAQ
  - **Visuals**: ASCII diagrams explaining Reality protocol masking
  - **Examples**: Real-world use cases (VPN, SOCKS5 proxy, reverse proxy)
  - **FAQ**: Common questions with clear answers

#### What Was Changed in README.md
- **REMOVED**: Technical jargon and implementation details
  - v4.1 detailed architecture descriptions
  - Code examples and technical configurations
  - stunnel/HAProxy implementation details
  - Developer-focused content

- **ADDED**: User-friendly explanations
  - "Как это работает?" section with ASCII diagrams
  - Visual explanation of Reality protocol masking
  - Simplified architecture (v5.0 HAProxy)
  - Real-world use case examples
  - Comprehensive FAQ section
  - VPS provider comparison table

- **MOVED**: Installation guide to separate document
  - **NEW**: `docs/installation.md` - Complete installation guide
  - Step-by-step instructions with screenshots
  - Troubleshooting section
  - Interactive prompts explained
  - Verification steps
  - Common issues and solutions

#### Documentation Structure (v5.0)
```
README.md               # User-friendly overview (what & how)
docs/installation.md    # Detailed installation guide
docs/prd/               # Technical documentation (for developers)
CLAUDE.md               # Project memory (AI assistant)
CHANGELOG.md            # Version history
```

#### Benefits of Restructuring
- **Better UX**: Users understand WHAT and HOW without technical depth
- **Clear separation**: User docs vs Developer docs
- **Easier onboarding**: Quick start in README, details in docs/installation.md
- **Improved searchability**: FAQ answers common questions directly
- **Reduced cognitive load**: Simpler language, visual diagrams

---

## [4.3] - 2025-10-18

### Changed - HAProxy Unified Architecture

**Migration Type:** Breaking (stunnel removed, HAProxy replaces all TLS/routing)

**Primary Feature:** Single HAProxy container for ALL TLS termination and routing

#### HAProxy Unified Architecture (v4.3)
- **REPLACED**: stunnel + HAProxy dual setup → Single unified HAProxy container
  - **v4.0-v4.2**: 2 containers (stunnel for TLS termination, HAProxy for SNI routing)
  - **v4.3**: 1 container (HAProxy handles both TLS termination AND SNI routing)
- **ADDED**: `lib/haproxy_config_manager.sh` - Unified HAProxy configuration module
  - `generate_haproxy_config()` - Generate haproxy.cfg via heredoc
  - `add_reverse_proxy_route()` - Dynamic ACL/backend management
  - `remove_reverse_proxy_route()` - Route removal with graceful reload
  - `list_haproxy_routes()` - Active routes listing
  - `reload_haproxy()` - Graceful reload (zero downtime, haproxy -sf)
  - `check_haproxy_status()` - Health monitoring
- **ADDED**: HAProxy configuration file `/opt/vless/config/haproxy.cfg`
  - 3 frontends: vless-reality (443), socks5-tls (1080), http-tls (8118)
  - Dynamic ACL section for reverse proxy routes
  - TLS 1.3 only, strong cipher suites
  - Stats page on localhost:9000

#### stunnel Removal
- **REMOVED**: stunnel container completely eliminated from docker-compose.yml
- **REMOVED**: `lib/stunnel_setup.sh` module (deprecated)
- **REMOVED**: `config/stunnel.conf` configuration file
- **REMOVED**: `tests/test_stunnel_heredoc.sh` (replaced with HAProxy tests)
- **UPDATED**: `lib/verification.sh` - Replaced stunnel checks with HAProxy verification
- **UPDATED**: `lib/orchestrator.sh` - Removed setup_stunnel() function

#### Subdomain-Based Reverse Proxy (v4.3 KEY FEATURE)
- **CHANGED**: Reverse proxy access format: `https://subdomain.example.com` (NO port number!)
  - **v4.2**: `https://domain:8443` (port required)
  - **v4.3**: `https://domain` (NO port, cleaner URLs)
- **CHANGED**: Backend port range: 8443-8452 → 9443-9452 (localhost-only)
  - Nginx binds to 127.0.0.1:9443-9452 (NOT exposed to internet)
  - Public access via HAProxy frontend 443 (SNI routing)
- **ADDED**: HAProxy SNI routing for reverse proxy subdomains
  - Dynamic ACL creation: `acl is_subdomain req.ssl_sni -i subdomain.example.com`
  - NO TLS decryption for reverse proxy (passthrough to Nginx)
  - Multi-layer fail2ban protection (HAProxy + Nginx filters)

#### Port Reassignment
- **CHANGED**: Xray VLESS Reality: 443 → 8443 (internal, HAProxy handles 443)
- **CHANGED**: Nginx reverse proxy backends: 8443-8452 → 9443-9452 (localhost-only)
- **UNCHANGED**: SOCKS5/HTTP external ports remain 1080/8118 (now via HAProxy TLS termination)
- **UNCHANGED**: Xray plaintext ports remain 10800/18118 (localhost-only)

#### Certificate Management
- **ADDED**: `lib/certificate_manager.sh` - HAProxy certificate management
  - `create_haproxy_combined_cert()` - Concatenate fullchain + privkey → combined.pem
  - `validate_haproxy_cert()` - Certificate validation for HAProxy
  - `reload_haproxy_after_cert_update()` - Graceful reload post-renewal
- **ADDED**: Combined certificate format `/opt/vless/certs/combined.pem`
  - HAProxy requires fullchain + privkey in single PEM file
  - Auto-generated on certificate acquisition and renewal
  - Permissions: 600, owner: root
- **ADDED**: `lib/certbot_manager.sh` - Certbot Nginx service management
  - `create_certbot_nginx_config()` - Temporary Nginx for ACME challenges
  - `start_certbot_nginx()` / `stop_certbot_nginx()` - On-demand service
  - `acquire_certificate()` - Automated certificate acquisition workflow
- **UPDATED**: Certificate renewal workflow (vless-cert-renew)
  - Regenerates combined.pem after Let's Encrypt renewal
  - Triggers HAProxy graceful reload (NOT full restart)
  - Zero downtime certificate updates

#### fail2ban Integration
- **ADDED**: HAProxy fail2ban filters and jails
  - `/etc/fail2ban/filter.d/haproxy-sni.conf` - HAProxy-specific patterns
  - `/etc/fail2ban/jail.d/haproxy.conf` - Protection for ports 443, 1080, 8118
  - Multi-layer protection: HAProxy filter + existing Nginx filters
- **ADDED**: `lib/fail2ban_config.sh` HAProxy functions
  - `create_haproxy_filter()` - Filter creation for HAProxy logs
  - `setup_haproxy_jail()` - Jail configuration
  - `setup_haproxy_fail2ban()` - Full HAProxy fail2ban setup
- **ADDED**: CLI commands for HAProxy fail2ban management
  - `vless fail2ban setup-haproxy` - Configure HAProxy protection
  - `vless fail2ban status-haproxy` - Check HAProxy jail status

#### CLI Updates
- **UPDATED**: `vless-setup-proxy` (reverse proxy setup)
  - Subdomain-based prompts (instead of port selection)
  - Automatic port allocation from 9443-9452 range
  - DNS validation required before certificate acquisition
  - HAProxy SNI route addition (replaced UFW port opening)
  - Success message: `https://subdomain.example.com` (NO port!)
- **UPDATED**: `vless-proxy` commands
  - `show`: Displays subdomain URL without port
  - `list`: Shows all reverse proxies with v4.3 architecture note
  - `remove`: HAProxy route removal (replaced UFW port removal)
- **UPDATED**: `vless-status`
  - HAProxy status section added (3 frontends info)
  - Active routes listing (parsed from haproxy.cfg)
  - Version header: 4.3.0

#### Testing
- **ADDED**: `tests/integration/v4.3/` - Comprehensive v4.3 test suite
  - `test_01_vless_reality_haproxy.sh` - VLESS Reality via HAProxy (8 checks)
  - `test_02_proxy_haproxy.sh` - SOCKS5/HTTP via HAProxy TLS termination (8 checks)
  - `test_03_reverse_proxy_subdomain.sh` - Subdomain-based reverse proxy (8 checks)
  - `run_all_tests.sh` - Automated test runner
  - DEV_MODE support for config validation without production environment
- **ADDED**: `tests/integration/v4.3/README.md` - Test suite documentation

#### Documentation Updates
- **UPDATED**: `docs/prd/04_architecture.md` - Added Section 4.7 HAProxy Unified Architecture
- **UPDATED**: `docs/prd/02_functional_requirements.md`
  - FR-HAPROXY-001: HAProxy Unified Architecture (CRITICAL)
  - FR-REVERSE-PROXY-001: Subdomain-Based Reverse Proxy (v4.3)
- **UPDATED**: `docs/prd/03_nfr.md` - NFR-RPROXY-002: Reverse Proxy Performance (v4.3)
- **UPDATED**: `docs/prd/05_testing.md` - v4.3 automated test suite documentation
- **UPDATED**: `docs/prd/06_appendix.md` - Implementation details for v4.3
- **UPDATED**: `docs/prd/00_summary.md` - Executive summary with v4.3 status
- **REWRITTEN**: `docs/REVERSE_PROXY_GUIDE.md` - Complete rewrite for v4.3 subdomain access
- **REWRITTEN**: `docs/REVERSE_PROXY_API.md` - Updated for v4.3 architecture
- **UPDATED**: `CLAUDE.md` - Project memory updated to v4.3

#### Benefits
- ✅ **Simplified Architecture**: 1 container instead of 2 (stunnel REMOVED)
- ✅ **Subdomain-Based Access**: `https://domain` (NO port number!)
- ✅ **SNI Routing Security**: NO TLS decryption for reverse proxy
- ✅ **Unified Management**: All TLS and routing in single HAProxy config
- ✅ **Graceful Reload**: Zero-downtime route updates (haproxy -sf)
- ✅ **Dynamic ACL Management**: Add/remove reverse proxy routes without restart
- ✅ **Single Log Stream**: Unified HAProxy logs for all frontends
- ✅ **Better Performance**: Industry-standard load balancer (20+ years production)
- ✅ **Easier Troubleshooting**: One config file, one container, clear separation

### Migration from v4.1.1 / v4.1 / v4.0

**Prerequisites:**
- Existing VLESS installation (v4.0, v4.1, or v4.1.1)
- Domain name with valid DNS A record (if using reverse proxy)
- Backup recommended: `sudo vless backup create`

**Automatic Migration:**
```bash
# Update to v4.3 (preserves users, keys, reverse proxies)
sudo vless update

# Migration automatically:
# 1. Removes stunnel container
# 2. Creates HAProxy container
# 3. Generates haproxy.cfg from scratch
# 4. Creates combined.pem certificates (if proxies enabled)
# 5. Updates Xray config (port 8443, localhost-only proxies)
# 6. Updates Nginx configs (ports 9443-9452)
# 7. Migrates reverse proxy routes to HAProxy ACLs
# 8. Restarts services with zero user data loss

# Verify migration
sudo vless status
# Should show: HAProxy Unified v4.3, stunnel: NOT FOUND (expected)
```

**Manual Verification:**
```bash
# 1. Check HAProxy container
sudo docker ps | grep haproxy
# Expected: vless_haproxy, status: Up

# 2. Verify stunnel removed
sudo docker ps -a | grep stunnel
# Expected: NO OUTPUT (stunnel completely removed)

# 3. Check HAProxy config
sudo cat /opt/vless/config/haproxy.cfg | head -20
# Expected: 3 frontends (vless-reality, socks5-tls, http-tls)

# 4. Check combined.pem (if proxies enabled)
sudo ls -lh /opt/vless/certs/combined.pem
# Expected: File exists, 600 permissions, ~4-8 KB size

# 5. Verify ports
sudo ss -tulnp | grep -E ':(443|1080|8118|8443|9443)'
# Expected:
#   443  - haproxy (SNI routing)
#   1080 - haproxy (SOCKS5 TLS termination)
#   8118 - haproxy (HTTP TLS termination)
#   8443 - xray (localhost, VLESS Reality backend)
#   9443 - nginx (localhost, reverse proxy backend 1)

# 6. Test VLESS connection (use existing client config)
# Should work without changes

# 7. Test SOCKS5/HTTP proxies (use existing credentials)
curl -s --socks5 user:pass@domain:1080 https://ifconfig.me
curl -s --proxy https://user:pass@domain:8118 https://ifconfig.me

# 8. Test reverse proxy (if configured)
# OLD: https://subdomain.example.com:8443 (DEPRECATED)
# NEW: https://subdomain.example.com (NO port!)
curl -I https://subdomain.example.com
```

**Rollback to v4.1.1 (if needed):**
```bash
# 1. Restore backup
sudo vless backup restore /tmp/vless_backup_TIMESTAMP.tar.gz

# 2. Manually add stunnel container back to docker-compose.yml
# 3. Recreate lib/stunnel_setup.sh (from v4.1.1 release)
# 4. Restart services
sudo docker compose down
sudo docker compose up -d
```

**Breaking Changes:**
- ❌ **stunnel container removed** - No longer exists in docker-compose.yml
- ❌ **Reverse proxy port access deprecated** - `https://domain:8443` NO LONGER WORKS
  - Use subdomain access instead: `https://domain` (NO port)
- ❌ **Xray VLESS port changed** - 443 → 8443 (internal, HAProxy handles 443)
  - Client configs UNCHANGED (still connect to port 443, HAProxy forwards)
- ❌ **Nginx backend ports changed** - 8443-8452 → 9443-9452 (localhost-only)
  - NOT exposed to internet, accessed via HAProxy SNI routing
- ✅ **Backward Compatible**: Existing VLESS client configs work without changes
- ✅ **Backward Compatible**: SOCKS5/HTTP proxy credentials unchanged
- ✅ **Data Preserved**: All users, keys, passwords, reverse proxies migrated automatically

**Acceptance Criteria:**
- [x] HAProxy container running and handling all 3 ports (443, 1080, 8118)
- [x] stunnel container removed from docker-compose.yml
- [x] Reverse proxy accessible via subdomain (NO port)
- [x] VLESS Reality working via HAProxy passthrough (port 443)
- [x] SOCKS5/HTTP proxies working via HAProxy TLS termination (ports 1080/8118)
- [x] Certificate renewal triggers HAProxy graceful reload
- [x] fail2ban protecting HAProxy (ports 443, 1080, 8118)
- [x] Zero user data loss during migration
- [x] Downtime < 30 seconds during update

---

## [4.1.1] - 2025-10-16

### Fixed - Container Verification Logic

**Migration Type:** Non-Breaking (bug fix)

**Primary Fix:** Improved container health verification and error detection

#### Container Health Checks
- **FIXED**: Nginx container verification now correctly distinguishes between critical errors and informational warnings
  - Read-only filesystem warnings (expected with security hardening) no longer cause installation failure
  - Only critical errors (`nginx: [emerg]`) now fail verification
  - Uses `docker inspect` instead of `grep` for more reliable status checks
- **FIXED**: Xray container verification enhanced with health status monitoring
- **ADDED**: stunnel container verification with healthcheck status (v4.0+)
- **ADDED**: Nginx healthcheck endpoint (`/health`) with automated monitoring
  - Checks every 30s with 10s timeout
  - 3 retries before marking unhealthy
  - 10s startup grace period

#### Pre-flight Checks
- **ADDED**: Verification of critical files before container deployment
  - Checks for xray_config.json, nginx config, docker-compose.yml, .env, keys
  - Checks for stunnel.conf if TLS proxy enabled
  - Clear error messages listing missing files
  - Prevents containers from starting with incomplete configuration

#### Verification Improvements
- **CHANGED**: Container status checks now use `docker inspect` (more reliable than `docker ps | grep`)
- **ADDED**: Health status monitoring for containers with healthcheck (Xray, stunnel)
- **ADDED**: Log analysis for critical errors only (ignores expected security warnings)
- **IMPROVED**: Error messages now include container status and actionable guidance

#### Benefits
- ✅ **No False Positives**: Security warnings no longer fail installation
- ✅ **Earlier Error Detection**: Pre-flight checks catch configuration issues before deployment
- ✅ **Better Diagnostics**: Health status provides real-time container health information
- ✅ **More Reliable**: docker inspect eliminates race conditions with grep-based checks

### Migration from v4.1

**Automatic Migration:**
- No user action required
- Existing installations will benefit from improved verification on next update/restart

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
| **4.3** | 2025-10-18 | HAProxy Unified Architecture | Breaking |
| **4.1.1** | 2025-10-16 | Container verification improvements | Non-Breaking |
| **4.1** | 2025-10-14 | Heredoc config generation | Non-Breaking |
| **4.0** | 2025-10-10 | stunnel TLS termination (deprecated v4.3) | Breaking |
| **3.6** | 2025-10-06 | Server-level IP whitelisting | Breaking |
| **3.5** | 2025-10-04 | Per-user IP whitelisting | Non-Breaking |
| **3.4** | 2025-10-02 | Optional TLS for proxies | Non-Breaking |
| **3.3** | 2025-09-28 | Mandatory TLS for proxies | Breaking |
| **3.2** | 2025-09-24 | Localhost-only proxy mode | Non-Breaking |
| **3.1** | 2025-09-20 | Dual proxy support foundation | Non-Breaking |
| **3.0** | 2025-09-15 | Production-ready VPN core | Initial Release |

---

## Upgrade Path

### From v3.x / v4.0 / v4.1 to v4.3 (Recommended)

**Direct upgrade** (preserves all user data and keys):

```bash
# 1. Backup current installation
sudo vless backup create

# 2. Update to latest version (v4.3)
sudo vless update

# 3. Migration automatically:
# - Removes stunnel container (if v4.0-v4.1)
# - Creates HAProxy unified container
# - Generates haproxy.cfg
# - Creates combined.pem certificates
# - Migrates reverse proxy routes to HAProxy ACLs
# - Updates all configs (zero user data loss)

# 4. Verify services
sudo vless status
# Should show: HAProxy Unified v4.3

# 5. Test connections (existing configs work without changes)
# VLESS Reality (port 443)
# SOCKS5 proxy (port 1080)
curl -s --socks5 user:pass@domain:1080 https://ifconfig.me
# HTTP proxy (port 8118)
curl -s --proxy https://user:pass@domain:8118 https://ifconfig.me
# Reverse proxy (subdomain, NO port)
curl -I https://subdomain.example.com
```

### Rollback Procedures

**v4.3 → v4.1.1:**
```bash
# 1. Restore backup
sudo vless backup restore /tmp/vless_backup_TIMESTAMP.tar.gz

# 2. Manually add stunnel container back to docker-compose.yml
# 3. Recreate lib/stunnel_setup.sh (from v4.1.1 release)
# 4. Reconfigure Xray ports (8443 → 443, 9443-9452 → 8443-8452)
# 5. Restart services
sudo docker compose down
sudo docker compose up -d

# NOTE: Reverse proxy URLs will change back to port-based access
# OLD v4.3: https://subdomain.example.com (NO port)
# NEW v4.1.1: https://subdomain.example.com:8443 (port required)
```

**v4.1.1 → v4.1 or v4.1 → v4.0:**
```bash
# No breaking changes - configs compatible
# Only minor verification improvements in v4.1.1
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
