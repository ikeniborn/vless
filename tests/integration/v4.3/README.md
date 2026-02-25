# VLESS v4.3 HAProxy Integration Test Suite

## Overview

Comprehensive test suite для валидации VLESS v4.3 HAProxy Unified Solution.

**Version:** 4.3.0
**Coverage:** 6 test cases
**Estimated Duration:** 4-5 hours (full production testing)

---

## Test Cases

### Test Case 1: VLESS Reality через HAProxy (30 min)
**File:** `test_01_vless_reality_haproxy.sh`

**What it tests:**
- HAProxy container running and listening on port 443
- HAProxy `vless-reality` frontend configuration
- Xray `xray_reality` backend configuration
- Xray container running on port 8443
- Xray VLESS inbound with Reality security
- Network connectivity HAProxy → Xray
- HAProxy stats page accessibility

**Dev Mode:** ✓ Partial (config validation only)

---

### Test Case 2: SOCKS5/HTTP Proxy через HAProxy (30 min)
**File:** `test_02_proxy_haproxy.sh`

**What it tests:**
- HAProxy `socks5-tls` frontend (port 1080) with TLS termination
- HAProxy `http-tls` frontend (port 8118) with TLS termination
- Xray `xray_socks5` and `xray_http` backends
- Xray SOCKS5 inbound (port 10800, localhost, password auth)
- Xray HTTP inbound (port 18118, localhost, password auth)
- HAProxy ports listening (1080, 8118)
- Certificate files for TLS termination

**Dev Mode:** ✓ Partial (config validation only)

---

### Test Case 3: Reverse Proxy Subdomain Access (1 hour)
**File:** `test_03_reverse_proxy_subdomain.sh`

**What it tests:**
- Reverse proxy database schema (v2.0)
- Port range 9443-9452 (not 8443-8452)
- HAProxy dynamic ACL section
- HAProxy route management functions
- Nginx config generator (port 9443-9452)
- CLI tools integration (vless-setup-proxy, familytraffic-proxy)
- Subdomain access format (https://domain, NO port)
- Certificate requirement and DNS validation

**Dev Mode:** ✓ Full (code validation, no runtime)

---

### Test Case 4: Certificate Acquisition & Renewal (1 hour)
**File:** `test_04_certificate_management.sh` *(TODO)*

**What it tests:**
- DNS validation for domain
- Certbot Nginx service (docker-compose profile)
- Certificate acquisition workflow
- combined.pem creation (fullchain + privkey)
- HAProxy graceful reload after cert update
- Certificate renewal dry-run
- Cron job for auto-renewal

**Dev Mode:** ✗ Requires production environment

---

### Test Case 5: Multi-Domain Concurrent Access (1 hour)
**File:** `test_05_multi_domain_concurrent.sh` *(TODO)*

**What it tests:**
- VLESS Reality connection
- SOCKS5 proxy connection
- HTTP proxy connection
- 2 reverse proxy subdomains
- All services simultaneously
- No conflicts or routing issues

**Dev Mode:** ✗ Requires production environment + configured domains

---

### Test Case 6: Migration from v4.0/v4.1 (1 hour)
**File:** `test_06_migration_compatibility.sh` *(TODO)*

**What it tests:**
- Detection of old stunnel setup
- Migration to HAProxy unified
- User data preservation
- Reality keys preservation
- Reverse proxy data preservation
- Backward compatibility
- Downtime < 1 minute

**Dev Mode:** ✗ Requires v4.0/v4.1 installation

---

## Usage

### Quick Validation (Dev Mode)

Run all available tests in development mode (config validation only):

```bash
cd tests/integration/v4.3
chmod +x *.sh
DEV_MODE=true ./run_all_tests.sh
```

### Individual Test

Run a specific test case:

```bash
# Test 1: VLESS Reality
./test_01_vless_reality_haproxy.sh

# Test 2: Proxy
./test_02_proxy_haproxy.sh

# Test 3: Reverse Proxy
./test_03_reverse_proxy_subdomain.sh
```

### Production Testing

Run full test suite on production installation:

```bash
# Must run on server with VLESS installed
sudo ./run_all_tests.sh
```

---

## Test Modes

### DEV MODE
- **Trigger:** `DEV_MODE=true` or `/opt/familytraffic/` not found
- **Coverage:** Config validation, code checks
- **Requirements:** Source code only
- **Limitations:** No runtime tests, no network tests

### PRODUCTION MODE
- **Trigger:** `/opt/familytraffic/` exists
- **Coverage:** Full runtime validation
- **Requirements:** VLESS installed, Docker running
- **Limitations:** None

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0    | All tests passed |
| 1    | One or more tests failed |

---

## Test Results Format

```
Test Summary:
  Passed:  X
  Failed:  Y
  Skipped: Z

Success Rate: XX%
```

---

## CI/CD Integration

Example GitHub Actions workflow:

```yaml
- name: Run VLESS v4.3 Tests
  run: |
    cd tests/integration/v4.3
    chmod +x *.sh
    DEV_MODE=true ./run_all_tests.sh
```

---

## Troubleshooting

### "HAProxy config not found"
- **Cause:** VLESS not installed
- **Solution:** Run in DEV_MODE or install VLESS first

### "Container not running"
- **Cause:** Docker containers not started
- **Solution:** `sudo vless-start`

### "Permission denied"
- **Cause:** Scripts not executable
- **Solution:** `chmod +x tests/integration/v4.3/*.sh`

---

## Contributing

When adding new tests:
1. Follow naming convention: `test_XX_description.sh`
2. Include header comment with test purpose and duration
3. Support DEV_MODE with graceful skipping
4. Use consistent color scheme and logging functions
5. Update this README with test description
6. Update `run_all_tests.sh` TESTS array

---

## Related Documentation

- [PLAN v4.3 HAProxy](../../../docs/prd/PLAN_v4.3_HAProxy.md)
- [PRD Architecture](../../../docs/prd/04_architecture.md)
- [CLAUDE.md Project Memory](../../../CLAUDE.md)

---

**Last Updated:** 2025-10-18
**Maintainer:** VLESS Development Team
