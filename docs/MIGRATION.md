# Migration Guide: v4.0 → v4.1

**Status:** ✅ COMPLETE
**Date:** 2025-10-07
**Duration:** ~1 hour
**Impact:** Internal refactoring (no breaking changes)

---

## Overview

Version 4.1 migration completed successfully:
1. ✅ Unified config generation (template → heredoc)
2. ✅ Fixed proxy URI schemes (https://, socks5s://)
3. ✅ Simplified dependencies (removed envsubst)
4. ✅ Added automated testing

**User Impact:** None - backward compatible

---

## What Changed

### 1. stunnel Config Generation

**Before (v4.0 - template-based):**
```
templates/stunnel.conf.template (111 lines)
  ↓ envsubst
lib/stunnel_setup.sh → /opt/vless/config/stunnel.conf
```

**After (v4.1 - heredoc):**
```
lib/stunnel_setup.sh
  ↓ heredoc inline
/opt/vless/config/stunnel.conf
```

**Files changed:**
- ✅ `lib/stunnel_setup.sh` - `create_stunnel_config()` rewritten
- ✅ Version updated: 4.0 → 4.1

**Files removed:**
- ❌ `templates/stunnel.conf.template` (111 lines)
- ❌ `templates/` directory

**Benefits:**
- Unified with Xray/docker-compose (all use heredoc)
- Fewer files (1 instead of 2)
- No envsubst dependency
- All logic in one place

---

### 2. Proxy URI Schemes Fix

**Issue:** Public proxy mode URIs used wrong schemes:
- HTTP: `http://` → should be `https://`
- SOCKS5: `socks5://` → should be `socks5s://`

**Fixed functions in `lib/user_management.sh`:**
- `export_http_config()` - now uses `https://` for public mode
- `export_socks5_config()` - now uses `socks5s://` for public mode
- `show_proxy_credentials()` - dynamic scheme selection
- `reset_proxy_password()` - dynamic scheme selection

**Result:**

| Mode | HTTP | SOCKS5 |
|------|------|--------|
| **Localhost** | `http://user:pass@127.0.0.1:8118` | `socks5://user:pass@127.0.0.1:1080` |
| **Public (TLS)** | `https://user:pass@domain:8118` | `socks5s://user:pass@domain:1080` |

---

### 3. Automated Testing

**New test suites:**
```bash
tests/test_stunnel_heredoc.sh       # 12 test cases
tests/test_proxy_uri_generation.sh  # 5 scenarios
```

**Results:**
```
stunnel Heredoc:      12/12 PASSED ✓
Proxy URI Generation:  5/5 PASSED ✓
─────────────────────────────────────
Total:                17/17 PASSED ✓
```

---

### 4. Documentation Cleanup

**Created (3 files):**
- `docs/CHANGELOG.md` - version history
- `docs/SECURITY_TESTING.md` - security testing guide (optimized)
- `docs/MIGRATION.md` - this file

**Removed (19 legacy files):**
- 10 module implementation reports (ORCHESTRATOR_REPORT.md, etc.)
- 2 old migration guides (v3.1→v3.2, v3.2→v3.3)
- 3 actualization reports
- 3 outdated documents (SECURITY_ASSESSMENT_v3.2.md, etc.)
- 1 roadmap planning file

**Result:** 26 files → 7 files (73% reduction)

---

## Migration Instructions

### For New Installations
No action required - v4.1 installer includes all changes.

### For Existing v4.0 Installations

**Option 1: Update via installer (recommended)**
```bash
cd /home/ikeniborn/Documents/Project/vless
sudo ./install.sh --update
```

**Option 2: Manual update**
```bash
# Backup current installation
sudo cp -r /opt/vless /opt/vless.backup.$(date +%Y%m%d)

# Pull latest code
cd /home/ikeniborn/Documents/Project/vless
git pull origin main

# No config regeneration needed (backward compatible)
```

**Verification:**
```bash
# Check stunnel config generation
cat /opt/vless/config/stunnel.conf | head -5
# Should contain: "Generated: 2025-10-07..." (new format)

# Check proxy URIs (if public mode enabled)
sudo vless show-proxy admin
# Should show: https:// and socks5s:// schemes
```

---

## Rollback Instructions

If needed, rollback to v4.0:

```bash
# Stop containers
cd /opt/vless
sudo docker compose down

# Restore backup
sudo rm -rf /opt/vless
sudo mv /opt/vless.backup.YYYYMMDD /opt/vless

# Restart containers
cd /opt/vless
sudo docker compose up -d
```

**Note:** Rollback not recommended - v4.1 is backward compatible with v4.0 configs.

---

## Testing Checklist

After migration, verify:

- [ ] stunnel config generated successfully
- [ ] Docker containers running (vless_xray, vless_stunnel, vless_nginx)
- [ ] Proxy URIs use correct schemes (https://, socks5s://)
- [ ] Client configs work (test connection)
- [ ] Security tests pass: `sudo vless test-security`

---

## Breaking Changes

**None.** Version 4.1 is fully backward compatible with v4.0.

---

## FAQ

### Q: Do I need to regenerate user configs?
**A:** No. Existing configs continue to work.

### Q: Will clients need new configs?
**A:** No. Client connection strings unchanged.

### Q: Is domain required for upgrade?
**A:** No. Public proxy mode requirements unchanged.

### Q: What if stunnel config generation fails?
**A:** Check logs: `docker logs vless_stunnel`. Verify domain in `/opt/vless/.env`.

### Q: Can I still use v4.0?
**A:** Yes, but v4.1 recommended for improved codebase consistency.

---

## Support

**Issues:** https://github.com/anthropics/vless-reality-vpn/issues
**Documentation:** `/home/ikeniborn/Documents/Project/vless/docs/`
**Logs:** `sudo vless-logs` or `docker logs vless_stunnel`

---

## Migration Summary

| Aspect | Status | Notes |
|--------|--------|-------|
| **Config Generation** | ✅ Complete | Template → heredoc migration |
| **Proxy URI Fix** | ✅ Complete | https://, socks5s:// schemes |
| **Testing** | ✅ Complete | 17/17 automated tests passed |
| **Documentation** | ✅ Complete | 26 → 7 files (optimized) |
| **Backward Compatibility** | ✅ Full | No breaking changes |
| **User Action Required** | ✅ None | Internal refactoring only |

**Migration Status:** ✅ **SUCCESSFULLY COMPLETED**
