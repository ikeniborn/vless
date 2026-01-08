# Certificate Renewal Hook v5.25 - Testing Guide

## Overview

This guide provides testing procedures for the enhanced certbot renewal hook (v5.25).

## Features to Test

### 1. Enhanced Logging
- Severity-based logging (DEBUG/INFO/WARNING/ERROR/CRITICAL)
- Verbose mode via `VLESS_RENEW_VERBOSE=1`
- Metrics tracking in JSON format
- Colored terminal output

### 2. Error Handling & Retry Logic
- Exponential backoff with jitter
- Automatic rollback on failures
- Graceful degradation (continue with other domains)
- Per-domain status tracking

### 3. Pre-Renewal Validation
- Certificate file validation
- HAProxy config validation
- Container health checks with auto-start
- Disk space validation
- Write permission validation

---

## Test Scenarios

### Test 1: Syntax Validation

```bash
# Validate bash syntax
bash -n /usr/local/bin/vless-cert-renew

# Expected: No output (success)
```

### Test 2: Normal Renewal (Happy Path)

**Prerequisites:**
- Valid Let's Encrypt certificate installed
- All containers running

**Steps:**
```bash
# Force renewal to trigger deploy hook
sudo certbot renew --force-renewal

# Or test in dry-run mode (won't trigger deploy hook)
sudo certbot renew --dry-run
```

**Expected Results:**
- ✅ All 6 phases complete successfully
- ✅ combined.pem created and backed up
- ✅ HAProxy reloaded without downtime
- ✅ Xray container restarted
- ✅ Metrics saved to `/opt/vless/logs/certbot-renew-metrics.json`
- ✅ Execution time < 15 seconds
- ✅ Exit code 0

**Verify:**
```bash
# Check logs
sudo tail -f /opt/vless/logs/certbot-renew.log

# Check metrics
sudo cat /opt/vless/logs/certbot-renew-metrics.json | jq '.'

# Verify HAProxy certificate
sudo docker exec vless_haproxy ls -lh /etc/letsencrypt/live/*/combined.pem

# Verify services still running
sudo docker ps | grep vless
```

---

### Test 3: Verbose Debug Mode

**Steps:**
```bash
# Enable verbose logging
VLESS_RENEW_VERBOSE=1 sudo certbot renew --force-renewal

# Or set log level directly
LOG_LEVEL=0 sudo certbot renew --force-renewal
```

**Expected Results:**
- ✅ DEBUG level logs shown
- ✅ Command execution details visible
- ✅ Retry attempts logged with delays
- ✅ Validation check details displayed

**Verify:**
```bash
# Check for DEBUG logs
sudo grep "\[DEBUG\]" /opt/vless/logs/certbot-renew.log | tail -20
```

---

### Test 4: Container Auto-Start (Health Check)

**Simulate:** Container stopped before renewal

**Steps:**
```bash
# Stop HAProxy container
sudo docker stop vless_haproxy

# Trigger renewal
RENEWED_DOMAINS="your-domain.com" sudo /usr/local/bin/vless-cert-renew

# Should see:
# [WARNING] Container not running: vless_haproxy, attempting to start...
# [INFO] ✅ Container started: vless_haproxy
```

**Expected Results:**
- ✅ Container automatically started
- ✅ Renewal continues after auto-start
- ✅ Exit code 0

**Verify:**
```bash
# Container should be running
sudo docker ps | grep vless_haproxy
```

---

### Test 5: HAProxy Reload Retry (Transient Failure)

**Note:** This test requires simulating a transient HAProxy failure (difficult to reproduce safely).

**Expected Behavior:**
- HAProxy reload fails on attempt 1
- Retry after 2s (with jitter)
- Retry after 4s (with jitter)
- If all retries fail:
  - Roll back all domains
  - Attempt reload with old certificates
  - Exit code 1

**Verify Retry Logic:**
```bash
# Check logs for retry attempts
sudo grep "Attempt .*/3" /opt/vless/logs/certbot-renew.log

# Check for rollback
sudo grep "Rolling back" /opt/vless/logs/certbot-renew.log
```

---

### Test 6: Disk Space Validation

**Simulate:** Low disk space

**Steps:**
```bash
# Check current disk space
df -h /etc/letsencrypt /opt/vless

# If disk space > 50 MB, test should pass
# To simulate failure, fill disk (NOT recommended on production)
```

**Expected Results:**
- ✅ Pre-validation checks disk space
- ✅ If < 50 MB: ERROR + exit code 1
- ✅ If 50-100 MB on /opt/vless: WARNING (continues)

---

### Test 7: Certificate File Validation

**Simulate:** Missing or corrupted certificate file

**Steps:**
```bash
# CAUTION: This will temporarily break certificates
# Create backup first
sudo cp -r /etc/letsencrypt/live /tmp/letsencrypt-backup

# Simulate missing file
sudo mv /etc/letsencrypt/live/your-domain.com/privkey.pem /tmp/privkey.pem.bak

# Trigger renewal
RENEWED_DOMAINS="your-domain.com" sudo /usr/local/bin/vless-cert-renew

# Restore
sudo mv /tmp/privkey.pem.bak /etc/letsencrypt/live/your-domain.com/privkey.pem
```

**Expected Results:**
- ❌ Pre-validation fails
- ❌ ERROR: "Certificate file missing: /etc/letsencrypt/live/.../privkey.pem"
- ❌ Exit code 1
- ✅ No changes made (aborted before Phase 2)

---

### Test 8: HAProxy Config Validation

**Simulate:** Invalid HAProxy configuration

**Steps:**
```bash
# Backup config
sudo cp /opt/vless/config/haproxy.cfg /tmp/haproxy.cfg.bak

# Introduce syntax error (e.g., invalid directive)
sudo bash -c 'echo "invalid_directive_xyz" >> /opt/vless/config/haproxy.cfg'

# Trigger renewal
RENEWED_DOMAINS="your-domain.com" sudo /usr/local/bin/vless-cert-renew

# Restore config
sudo cp /tmp/haproxy.cfg.bak /opt/vless/config/haproxy.cfg
```

**Expected Results:**
- ❌ Pre-validation fails
- ❌ ERROR: "HAProxy configuration validation failed"
- ❌ Exit code 1

---

### Test 9: Multiple Domains (Graceful Degradation)

**Prerequisites:** Multiple domains configured

**Simulate:** One domain has invalid certificate

**Expected Behavior:**
- Domain 1: SUCCESS (combined.pem created)
- Domain 2: FAILED (combined.pem creation fails, rolled back)
- Domain 3: SUCCESS
- HAProxy reload: SUCCESS (with domains 1 and 3)
- Final status: `partial_success`
- Exit code: 0 (don't fail if some succeeded)

**Verify:**
```bash
# Check metrics
sudo cat /opt/vless/logs/certbot-renew-metrics.json | jq '.status'
# Should show: "partial_success"

# Check failed domains
sudo grep "Failed domains:" /opt/vless/logs/certbot-renew.log
```

---

### Test 10: Metrics JSON Format

**Steps:**
```bash
# After renewal
sudo cat /opt/vless/logs/certbot-renew-metrics.json
```

**Expected Format:**
```json
{
  "timestamp": "2026-01-08T15:30:45Z",
  "domains": "vpn.example.com",
  "status": "success",
  "execution_time_seconds": 12,
  "error_message": "",
  "certbot_version": "2.7.4",
  "haproxy_version": "HAProxy version 2.8.3"
}
```

**Validate:**
```bash
# Valid JSON
sudo jq '.' /opt/vless/logs/certbot-renew-metrics.json

# Check fields
sudo jq '.status' /opt/vless/logs/certbot-renew-metrics.json
sudo jq '.execution_time_seconds' /opt/vless/logs/certbot-renew-metrics.json
```

---

### Test 11: Logrotate Configuration

**Steps:**
```bash
# Check logrotate config
cat /etc/logrotate.d/vless-certbot-renew

# Test logrotate
sudo logrotate -d /etc/logrotate.d/vless-certbot-renew

# Force rotation (test mode)
sudo logrotate -f /etc/logrotate.d/vless-certbot-renew
```

**Expected Results:**
- ✅ Config file exists
- ✅ Daily rotation for certbot-renew.log (30 days)
- ✅ Weekly rotation for metrics.json (12 weeks)
- ✅ Compressed archives created

**Verify:**
```bash
# Check rotated logs
ls -lh /opt/vless/logs/certbot-renew.log.*
ls -lh /opt/vless/logs/certbot-renew-metrics.json.*
```

---

### Test 12: Backward Compatibility

**Verify:** All v4.3 features still work

**Steps:**
```bash
# Check that legacy functions still work
sudo grep -A 5 "reload_nginx_reverseproxy" /usr/local/bin/vless-cert-renew
sudo grep -A 5 "update_database_cert_info" /usr/local/bin/vless-cert-renew

# Trigger renewal
sudo certbot renew --force-renewal
```

**Expected Results:**
- ✅ Nginx reverse proxy reloaded (if configured)
- ✅ Database updated with new expiry
- ✅ All v4.3 behaviors preserved

---

## Performance Benchmarks

| Scenario | Target | Measurement |
|----------|--------|-------------|
| Normal renewal | < 15s | Check metrics.json |
| With retry (1 failure) | < 25s | Check metrics.json |
| With retry (2 failures) | < 40s | Check metrics.json |
| Pre-validation only | < 5s | Time validation phase |

---

## Troubleshooting Test Failures

### Issue: "RENEWED_DOMAINS environment variable not set"

**Cause:** Script called directly, not via certbot

**Solution:** Set environment variable manually
```bash
RENEWED_DOMAINS="your-domain.com" sudo /usr/local/bin/vless-cert-renew
```

### Issue: "Certificate manager module not found"

**Cause:** `/opt/vless/lib/certificate_manager.sh` missing

**Solution:** Reinstall VLESS or copy library files
```bash
sudo cp lib/certificate_manager.sh /opt/vless/lib/
```

### Issue: Logs show "date: invalid date" errors

**Cause:** `date` command format incompatibility

**Solution:** Check date version and OS compatibility
```bash
date --version
```

---

## Rollback Procedure

If v5.25 causes issues:

```bash
# Revert to v5.24 (or previous version)
cd /path/to/vless
git checkout v5.24 scripts/vless-cert-renew
sudo cp scripts/vless-cert-renew /usr/local/bin/

# Verify
sudo bash -n /usr/local/bin/vless-cert-renew

# Test renewal
sudo certbot renew --dry-run
```

---

## Success Criteria

All tests pass with:
- ✅ Zero syntax errors
- ✅ Pre-validation prevents invalid renewals
- ✅ Retry logic handles transient failures
- ✅ Rollback works on critical failures
- ✅ Metrics tracked correctly
- ✅ Logrotate configured properly
- ✅ Backward compatible with v4.3
- ✅ Normal renewal < 15 seconds

---

## Notes

- Always test on a staging/test server first
- Keep backups before testing destructive scenarios
- Monitor logs during testing: `sudo tail -f /opt/vless/logs/certbot-renew.log`
- Verbose mode helps debug issues: `VLESS_RENEW_VERBOSE=1`

---

**Version:** v5.25
**Last Updated:** 2026-01-08
**Tested On:** Ubuntu 20.04+, Debian 10+
