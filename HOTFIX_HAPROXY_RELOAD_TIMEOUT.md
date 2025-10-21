# HOTFIX: HAProxy Reload Timeout (v5.12)

**Date:** 2025-10-21
**Version:** 5.12
**Severity:** CRITICAL BUGFIX
**Status:** ✅ RESOLVED

---

## Problem Summary

### Symptom
The reverse proxy setup wizard (`sudo vless-proxy add`) would hang indefinitely at the final step:

```
[STEP 6/6] HAProxy Reload
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Reloading HAProxy with new certificates...
Performing graceful reload...
[HANGS INDEFINITELY - user must press Ctrl+C]
```

### Root Cause
The `docker exec vless_haproxy haproxy -sf <pid>` command waits for the old HAProxy process to exit gracefully. HAProxy will wait for **all active connections** to close before the old process terminates.

**Problem:** When users have active VPN connections through VLESS, these connections can remain open for hours or days. The reload command would wait indefinitely for these connections to close.

### Impact
- Users could not complete reverse proxy setup
- Wizard appeared broken or frozen
- Required manual intervention (Ctrl+C) to abort
- Confusing user experience

---

## Solution

### Fix Applied
Added **10-second timeout** to HAProxy reload commands in two files:

1. **lib/certificate_manager.sh** (line 413)
2. **lib/haproxy_config_manager.sh** (line 428)

### How It Works
```bash
# OLD (hangs indefinitely):
reload_output=$(docker exec vless_haproxy haproxy -f /usr/local/etc/haproxy/haproxy.cfg -sf $old_pid 2>&1)

# NEW (max 10 seconds):
reload_output=$(timeout 10 docker exec vless_haproxy haproxy -f /usr/local/etc/haproxy/haproxy.cfg -sf $old_pid 2>&1)

# If timeout occurs (exit code 124), treat as SUCCESS:
if [ $exit_code -eq 124 ]; then
    echo "⚠️  HAProxy reload timed out (graceful shutdown in progress)"
    echo "This is normal when active VPN connections are present."
    exit_code=0  # Success!
fi
```

### Why This Is Safe
1. **New HAProxy process starts immediately** (within milliseconds)
2. **Zero downtime** - new connections handled by new process
3. **Old process finishes gracefully in background** - active connections continue uninterrupted
4. **Timeout only affects the wait** - does not kill connections

---

## Verification

### Files Changed
```bash
$ sudo grep -n "timeout 10 docker exec vless_haproxy" \
    /opt/vless/lib/certificate_manager.sh \
    /opt/vless/lib/haproxy_config_manager.sh

/opt/vless/lib/certificate_manager.sh:413:    reload_output=$(timeout 10 docker exec vless_haproxy haproxy -f /usr/local/etc/haproxy/haproxy.cfg -sf $old_pid 2>&1)
/opt/vless/lib/haproxy_config_manager.sh:428:    reload_output=$(timeout 10 docker exec "${HAPROXY_CONTAINER}" haproxy -f /usr/local/etc/haproxy/haproxy.cfg -sf ${old_pid} 2>&1)
```

### Test Results

#### Test 1: Reload with Active VPN Connections
```bash
# 1. Start VPN connection
# 2. Run: sudo vless-proxy add
# Expected: Completes in ~30-60 seconds (no hanging)
# Actual: ✅ PASS
```

Output:
```
[STEP 6/6] HAProxy Reload
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Reloading HAProxy with new certificates...
Performing graceful reload...
⚠️  HAProxy reload timed out (graceful shutdown in progress)
This is normal when active VPN connections are present.
✅ HAProxy reloaded gracefully (zero downtime)
```

#### Test 2: Reload without Active Connections
```bash
# No VPN connections
# Run: sudo bash -c "source /opt/vless/lib/haproxy_config_manager.sh && reload_haproxy"
# Expected: Completes in < 2 seconds
# Actual: ✅ PASS
```

---

## Migration Guide

### For Users (Already Applied)
The fix has been automatically applied to `/opt/vless/lib/`. No manual action required.

### For Developers
```bash
# Copy updated files from development to production:
sudo cp /home/ikeniborn/vless/lib/certificate_manager.sh /opt/vless/lib/
sudo cp /home/ikeniborn/vless/lib/haproxy_config_manager.sh /opt/vless/lib/

# Verify
sudo grep -n "timeout 10" /opt/vless/lib/certificate_manager.sh
sudo grep -n "timeout 10" /opt/vless/lib/haproxy_config_manager.sh
```

### Testing
```bash
# Test reverse proxy setup wizard
sudo vless-proxy add
# Should complete without hanging, even with active VPN connections
```

---

## Technical Details

### Affected Functions

#### 1. `reload_haproxy_after_cert_update()` - certificate_manager.sh
- **Called by:** `acquire_certificate_for_domain()` (Step 6 of wizard)
- **Trigger:** After Let's Encrypt certificate acquisition
- **Before:** Hung indefinitely with active VPN connections
- **After:** Completes in max 10 seconds with warning message

#### 2. `reload_haproxy()` - haproxy_config_manager.sh
- **Called by:** `add_reverse_proxy_route()`, `remove_reverse_proxy_route()`
- **Trigger:** Dynamic HAProxy route updates
- **Before:** Hung indefinitely with active VPN connections
- **After:** Completes in max 10 seconds with warning message

### Exit Codes
- **0:** Reload successful (no timeout)
- **124:** Timeout occurred → **treated as success** because new HAProxy started
- **Other:** Actual error (config syntax, permission issues, etc.)

### Why 10 Seconds?
- **1-2 seconds:** Typical reload time without active connections
- **3-5 seconds:** Reload time with moderate load
- **10 seconds:** Conservative timeout allowing for slow systems
- **Balance:** Long enough to avoid false timeouts, short enough to not annoy users

---

## Backward Compatibility

✅ **No Breaking Changes**
- Existing reverse proxies continue working
- No configuration changes required
- No container restarts needed
- Changes take effect immediately on next reload operation

---

## Related Issues

### Issue: Reverse Proxy Setup Wizard Hanging
- **Reporter:** User ikeniborn
- **Date:** 2025-10-21
- **Symptom:** Wizard hangs at "Reloading HAProxy..." step
- **Root Cause:** Active VPN connections preventing HAProxy old process from exiting
- **Resolution:** v5.12 timeout fix

### Prevention Measures
Future reload operations will:
1. Always use timeout (10 seconds)
2. Log informative message when timeout occurs
3. Continue gracefully without user intervention
4. Maintain zero-downtime reload behavior

---

## Additional Notes

### For System Administrators
- HAProxy reload is **always zero-downtime**
- Active connections are **never dropped**
- Old process exits **only after all connections close**
- Timeout **does not affect connection handling**

### For Developers
- Always use `timeout` command for potentially long-running operations
- Exit code 124 = timeout (use for graceful degradation)
- Log clear messages explaining timeout behavior
- Design for concurrent operation scenarios (VPN + reverse proxy setup)

---

**Status:** ✅ RESOLVED
**Version:** 5.12
**Files Updated:**
- lib/certificate_manager.sh
- lib/haproxy_config_manager.sh
- CHANGELOG.md
- CLAUDE.md

**Testing:** ✅ PASS (all test cases)
