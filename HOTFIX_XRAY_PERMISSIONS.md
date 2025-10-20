# HOTFIX: Xray Container Permission Error (v5.3+)

**Date:** 2025-10-21
**Severity:** CRITICAL
**Status:** ✅ RESOLVED

---

## Problem Summary

After fresh installation, `vless_xray` container enters crash loop with error:
```
Failed to start: permission denied - /etc/xray/config.json
```

**Root Cause:** File `/opt/vless/config/xray_config.json` has permissions `600` (root-only), but container runs as `user: nobody` (UID 65534) and cannot read the file.

---

## Symptoms

1. `docker ps` shows `vless_xray` status: `Restarting (23)`
2. Container not in Docker network `vless_reality_net`
3. HAProxy cannot resolve `vless_xray` address
4. VPN clients cannot connect
5. SOCKS5/HTTP proxies fail
6. Reverse proxy setup fails with HAProxy reload errors

---

## Immediate Fix (Manual)

```bash
# Fix file permissions
sudo chmod 644 /opt/vless/config/xray_config.json

# Restart container
docker restart vless_xray

# Verify
docker ps --filter "name=vless_xray" --format "{{.Status}}"
# Should show: Up X seconds (healthy)

# Restart HAProxy to see Xray in network
docker restart vless_haproxy
```

---

## Root Cause Analysis

### What Should Happen

`lib/orchestrator.sh::set_permissions()` (lines 1489-1493) contains:
```bash
# EXCEPTION: Xray config must be world-readable for xray container user (uid=nobody/65534)
if [[ -f "${XRAY_CONFIG}" ]]; then
    chmod 644 "${XRAY_CONFIG}" 2>/dev/null || true
fi
```

This code exists since commit `6537f17` (2025-10-20).

### Why It Failed

One of:
1. `${XRAY_CONFIG}` variable not defined during `set_permissions()`
2. File doesn't exist yet when `set_permissions()` runs
3. Silent failure (`|| true`) hides the error
4. Some later script overwrites permissions back to `600`

### Investigation Needed

Check if:
1. Variable scope issue - `XRAY_CONFIG` not exported?
2. Timing issue - file created AFTER `set_permissions()`?
   (orchestrator.sh line 156: `create_xray_config` → line 261: `set_permissions`)
3. Another script modifies permissions after install?

---

## Permanent Fix Options

### Option 1: Add Debug Logging
```bash
# In lib/orchestrator.sh::set_permissions()
if [[ -f "${XRAY_CONFIG}" ]]; then
    chmod 644 "${XRAY_CONFIG}" 2>/dev/null || {
        log_error "Failed to set permissions on ${XRAY_CONFIG}"
        return 1
    }
    log_success "✓ xray_config.json: 644 (readable by container)"
else
    log_warning "⚠ XRAY_CONFIG not found: ${XRAY_CONFIG}"
fi
```

### Option 2: Add Post-Install Verification
```bash
# At end of orchestrator.sh::main()
verify_file_permissions() {
    local ISSUES=0

    [[ $(stat -c '%a' "${XRAY_CONFIG}") != "644" ]] && {
        log_error "xray_config.json has wrong permissions"
        ((ISSUES++))
    }

    [[ $(stat -c '%a' "${CONFIG_DIR}/haproxy.cfg") != "644" ]] && {
        log_error "haproxy.cfg has wrong permissions"
        ((ISSUES++))
    }

    return $ISSUES
}
```

### Option 3: Fail-Safe in create_xray_config()
```bash
# In lib/orchestrator.sh::create_xray_config()
# After writing file:
chmod 644 "${XRAY_CONFIG}" || {
    log_error "Failed to set permissions on ${XRAY_CONFIG}"
    return 1
}
```

---

## Testing Required

After implementing fix:

```bash
# Clean install test
sudo rm -rf /opt/vless
sudo bash install.sh

# Verify
docker ps --filter "name=vless_xray"
# Should show: Up X seconds (healthy)

sudo ls -la /opt/vless/config/xray_config.json
# Should show: -rw-r--r-- (644)
```

---

## Related Files

- `/opt/vless/config/xray_config.json` - affected file
- `lib/orchestrator.sh` - contains `set_permissions()` and `create_xray_config()`
- `docker-compose.yml` - Xray service runs as `user: nobody`
- Commit `6537f17` - original fix (2025-10-20)

---

## Prevention

Add to CI/CD:
1. Automated permission checks after install
2. Test installation on clean VM
3. Verify all containers start successfully

---

**Fixed in Production:** ✅ 2025-10-21 (manual chmod)
**Permanent Fix Status:** ⏳ PENDING (needs code changes + testing)
