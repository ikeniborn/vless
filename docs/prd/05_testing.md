# PRD v4.3 - Testing Requirements

**Навигация:** [Обзор](01_overview.md) | [Функциональные требования](02_functional_requirements.md) | [NFR](03_nfr.md) | [Архитектура](04_architecture.md) | [Тестирование](05_testing.md) | [Приложения](06_appendix.md) | [← Саммари](00_summary.md)

---

## 7. Testing Requirements

### 7.0 v4.3 Automated Test Suite (NEW)

**Test Suite Version:** 5.33.0 (Enhanced with External Proxy validation)
**Coverage:** 6 test cases (3 automated with v5.33 enhancements, 3 production-only)
**Location:** `tests/integration/v4.3/`

**Automated Tests (DEV_MODE Support):**

1. **Test 01: VLESS Reality through HAProxy** (`test_01_vless_reality_haproxy.sh`)
   - Duration: 30 minutes
   - Checks: 8 validation points
   - Coverage:
     - HAProxy container running and listening on port 443
     - HAProxy `vless-reality` frontend configuration
     - Xray `xray_reality` backend configuration
     - Xray container running on port 8443
     - Xray VLESS inbound with Reality security
     - Network connectivity HAProxy → Xray
     - HAProxy stats page accessibility
   - DEV_MODE: Partial (config validation only)

2. **Test 02: SOCKS5/HTTP Proxy through HAProxy + External Proxy Validation** (`test_02_proxy_haproxy.sh`)
   - Duration: 45 minutes (extended v5.33)
   - Checks: 14 validation points (expanded from 8)
   - Coverage:
     - HAProxy `socks5-tls` frontend (port 1080) with TLS termination
     - HAProxy `http-tls` frontend (port 8118) with TLS termination
     - Xray `xray_socks5` and `xray_http` backends
     - Xray SOCKS5 inbound (port 10800, localhost, password auth)
     - Xray HTTP inbound (port 18118, localhost, password auth)
     - HAProxy ports listening (1080, 8118)
     - Certificate files for TLS termination (combined.pem)
     - **External Proxy Support (v5.23-v5.33):**
       - TLS Server Name validation (FQDN format) - v5.33
       - TLS Server Name validation (IP format) - v5.33
       - Invalid input rejection ("y", "yes", "n", "no") - v5.33
       - Auto-activation workflow - v5.33
       - Auto-enable routing integration - v5.33
       - Database schema (external_proxy.json)
       - Xray outbound generation with TLS settings
   - DEV_MODE: Partial (config validation + validation functions)

3. **Test 03: Reverse Proxy Subdomain Access** (`test_03_reverse_proxy_subdomain.sh`)
   - Duration: 1 hour
   - Checks: 8 validation points
   - Coverage:
     - Reverse proxy database schema (v2.0)
     - Port range 9443-9452 (NOT 8443-8452)
     - HAProxy dynamic ACL section
     - HAProxy route management functions
     - Nginx config generator (port 9443-9452)
     - CLI tools integration (vless-setup-proxy, familytraffic-proxy)
     - Subdomain access format (https://domain, NO port)
     - Certificate requirement and DNS validation
   - DEV_MODE: Full (code validation, no runtime)

**Production-Only Tests (TODO):**

4. **Test 04: Certificate Acquisition & Renewal** (`test_04_certificate_management.sh`)
   - Duration: 1 hour
   - Requirements: Production environment with valid DNS
   - Coverage: DNS validation, certbot workflow, combined.pem creation, HAProxy graceful reload, auto-renewal cron

5. **Test 05: Multi-Domain Concurrent Access** (`test_05_multi_domain_concurrent.sh`)
   - Duration: 1 hour
   - Requirements: Production environment + configured domains
   - Coverage: VLESS, SOCKS5, HTTP, 2 reverse proxy subdomains (simultaneous access)

6. **Test 06: Migration from v4.0/v4.1** (`test_06_migration_compatibility.sh`)
   - Duration: 1 hour
   - Requirements: v4.0/v4.1 installation
   - Coverage: stunnel detection, HAProxy migration, data preservation, backward compatibility

**Usage:**

```bash
# Quick validation (Dev Mode)
cd tests/integration/v4.3
chmod +x *.sh
DEV_MODE=true ./run_all_tests.sh

# Individual test
./test_01_vless_reality_haproxy.sh

# Production testing (requires /opt/familytraffic/ installation)
sudo ./run_all_tests.sh
```

**Test Results Format:**
```
Test Summary:
  Passed:  X
  Failed:  Y
  Skipped: Z

Success Rate: XX%
```

**Related Documentation:** [v4.3 Test Suite README](../../../tests/integration/v4.3/README.md)

---

### 7.1 TLS Integration Tests (v4.3 HAProxy)

**Test Case 1: TLS Handshake - SOCKS5 (HAProxy Termination)**
```bash
# Verify TLS on SOCKS5 port (HAProxy frontend)
openssl s_client -connect server:1080 -showcerts

# Expected Output:
# - Certificate chain displayed
# - Issuer: Let's Encrypt
# - Subject: CN=vpn.example.com
# - Verify return code: 0 (ok)
# - Protocol: TLSv1.3
```

**Test Case 2: TLS Handshake - HTTP/HTTPS (HAProxy Termination)**
```bash
# Verify HTTPS on HTTP proxy port (HAProxy frontend)
curl -I --proxy https://user:pass@server:8118 https://google.com

# Expected Output:
# HTTP/1.1 200 OK
# (no SSL warnings)
```

**Test Case 3: Certificate Validation (combined.pem format)**
```bash
# Check combined.pem format for HAProxy
openssl x509 -in /opt/familytraffic/certs/combined.pem -noout -text

# Expected:
# - Issuer: Let's Encrypt
# - Validity: 90 days from issuance
# - Subject Alt Name: DNS:vpn.example.com

# Verify private key included
grep -q "BEGIN PRIVATE KEY" /opt/familytraffic/certs/combined.pem
echo $?  # Expected: 0 (found)
```

**Test Case 4: Auto-Renewal Dry-Run**
```bash
# Test renewal without actually renewing
sudo certbot renew --dry-run

# Expected Output:
# Congratulations, all simulated renewals succeeded
```

**Test Case 5: Deploy Hook Execution (HAProxy Reload)**
```bash
# Manually trigger deploy hook
sudo /usr/local/bin/familytraffic-cert-renew

# Expected:
# - combined.pem regenerated
# - HAProxy gracefully reloads (haproxy -sf <old_pid>)
# - Downtime < 5 seconds
# - docker logs shows reload
```

---

### 7.2 Client Integration Tests (NEW)

**Test Case 6: VSCode Extension via HTTPS Proxy**
```json
// VSCode settings.json
{
  "http.proxy": "https://alice:PASSWORD@server:8118",
  "http.proxyStrictSSL": true
}
```

**Steps:**
1. Apply settings.json
2. Open Extensions (Ctrl+Shift+X)
3. Search "Python"
4. Install extension

**Expected:**
- ✅ Extension installs successfully
- ✅ No SSL certificate warnings
- ✅ HAProxy logs show HTTPS connection (frontend http-tls)
- ✅ Xray logs show plaintext HTTP inbound traffic

**Test Case 7: Git Clone via SOCKS5s Proxy**
```bash
# Configure Git
git config --global http.proxy socks5s://alice:PASSWORD@server:1080

# Clone repository
git clone https://github.com/torvalds/linux.git

# Expected:
# - Clone succeeds
# - No TLS errors
# - HAProxy logs show SOCKS5 connection (frontend socks5-tls)
# - Xray logs show plaintext SOCKS5 inbound traffic
```

---

### 7.3 Security Tests (v4.3 HAProxy)

**Test Case 8: Wireshark Traffic Capture**
```bash
# Capture proxy traffic
sudo tcpdump -i any -w /tmp/proxy_traffic.pcap port 1080

# Analyze in Wireshark
wireshark /tmp/proxy_traffic.pcap

# Expected:
# - TLS 1.3 handshake visible (HAProxy termination)
# - Application Data encrypted
# - NO plaintext SOCKS5/HTTP
# - NO plaintext credentials
```

**Test Case 9: Nmap Service Detection (HAProxy)**
```bash
# Scan HAProxy ports
nmap -sV -p 443,1080,8118 server

# Expected Output:
# PORT     STATE SERVICE  VERSION
# 443/tcp  open  ssl/unknown  (SNI routing)
# 1080/tcp open  ssl/socks
# 8118/tcp open  ssl/http
```

**Test Case 10: Config Validation - HAProxy TLS**
```bash
# Verify HAProxy TLS configuration
docker exec familytraffic cat /usr/local/etc/haproxy/haproxy.cfg | grep -A 5 "frontend socks5-tls"

# Expected:
# frontend socks5-tls
#     bind *:1080 ssl crt /opt/familytraffic/certs/combined.pem
#     mode tcp
#     default_backend xray_socks5

docker exec familytraffic cat /usr/local/etc/haproxy/haproxy.cfg | grep -A 5 "frontend http-tls"

# Expected:
# frontend http-tls
#     bind *:8118 ssl crt /opt/familytraffic/certs/combined.pem
#     mode tcp
#     default_backend xray_http
```

---

### 7.4 Backward Compatibility Tests (v3.2 → v3.3+ → v4.3)

**Test Case 11: Old Configs Must Fail**
```bash
# Try connecting with old v3.2 plain config
curl --socks5 alice:PASSWORD@server:1080 https://ifconfig.me

# Expected:
# - Connection FAILS (plain SOCKS5 not accepted)
# - Error: "TLS handshake required"
```

**Test Case 12: New Configs Must Work (HAProxy TLS)**
```bash
# Connect with new v4.3 TLS config
curl --socks5 alice:PASSWORD@server:1080 --proxy-insecure https://ifconfig.me
# (Note: --proxy-insecure needed if testing with self-signed, NOT needed with Let's Encrypt)

# Expected:
# - Connection succeeds
# - Returns external IP
# - HAProxy terminates TLS
# - Xray receives plaintext SOCKS5
```

---

### 7.5 Reverse Proxy Tests (v4.3 - Subdomain-Based, HAProxy SNI Routing)

#### 7.5.1 Authentication Testing (HTTP Basic Auth)

**Test Case 13: Valid Credentials (Subdomain Access)**
```bash
# Test successful authentication (NO PORT NUMBER)
curl -u user:password https://myproxy.example.com

# Expected:
# - HTTP 200 OK
# - Content from target site (blocked-site.com)
# - No authentication errors
# - HAProxy SNI routing to Nginx:9443
```

**Test Case 14: Invalid Credentials**
```bash
# Test authentication rejection
curl -u user:wrongpass https://myproxy.example.com

# Expected:
# - HTTP 401 Unauthorized
# - WWW-Authenticate: Basic realm="Reverse Proxy"
# - fail2ban logs show auth failure (nginx filter)
```

**Test Case 15: No Credentials**
```bash
# Test missing authentication
curl https://myproxy.example.com

# Expected:
# - HTTP 401 Unauthorized
# - Prompt for credentials
```

**Test Case 16: Brute Force Protection (fail2ban with HAProxy + Nginx)**
```bash
# Simulate 5 failed attempts
for i in {1..5}; do
  curl -u user:wrongpass https://myproxy.example.com
  sleep 1
done

# Check fail2ban status (Nginx filter)
sudo fail2ban-client status vless-nginx-reverseproxy

# Expected:
# - IP banned after 5 failures
# - Ban duration: 1 hour
# - UFW blocks banned IP
# - Subsequent requests fail immediately
```

---

#### 7.5.2 TLS Configuration Testing (HAProxy SNI Routing)

**Test Case 17: TLS 1.3 Enforcement (Nginx Backend)**
```bash
# Verify TLS 1.3 required (Nginx backend)
openssl s_client -connect myproxy.example.com:443 -servername myproxy.example.com -tls1_3

# Expected:
# - HAProxy SNI routing to Nginx:9443
# - TLS 1.3 handshake succeeds
# - Protocol: TLSv1.3
# - Cipher: TLS_AES_256_GCM_SHA384 or TLS_CHACHA20_POLY1305_SHA256

# Test TLS 1.2 rejection
openssl s_client -connect myproxy.example.com:443 -servername myproxy.example.com -tls1_2

# Expected:
# - Handshake FAILS
# - Error: "no protocols available" or "unsupported protocol"
```

**Test Case 18: HSTS Header Validation (VULN-002 Mitigation)**
```bash
# Check HSTS header present
curl -I -u user:password https://myproxy.example.com

# Expected Headers:
# Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
# (MUST be present on all responses)

# Verify HSTS enforcement
# 1. First request with HTTPS
curl -v -u user:pass https://myproxy.example.com 2>&1 | grep -i "strict-transport"

# 2. Browser should auto-upgrade HTTP to HTTPS after first visit
```

**Test Case 19: Certificate Validation (Let's Encrypt)**
```bash
# Verify Let's Encrypt certificate
openssl x509 -in /etc/letsencrypt/live/myproxy.example.com/cert.pem -noout -text

# Expected:
# - Issuer: Let's Encrypt
# - Subject: CN=myproxy.example.com
# - Validity: 90 days
# - Subject Alternative Name: DNS:myproxy.example.com
```

---

#### 7.5.3 Host Header Validation Testing (VULN-001 Mitigation - CRITICAL)

**Test Case 20: Valid Host Header**
```bash
# Test with correct Host header
curl -H "Host: myproxy.example.com" -u user:pass https://myproxy.example.com

# Expected:
# - HTTP 200 OK
# - Content from target site
# - HAProxy SNI routing successful
```

**Test Case 21: Invalid Host Header (Attack Simulation)**
```bash
# Test Host Header Injection attempt
curl -H "Host: evil.com" -u user:pass https://myproxy.example.com

# Expected:
# - Connection CLOSED (HTTP 444)
# - NO response body
# - nginx error log: "Host header mismatch"

# Test with IP instead of domain
curl -H "Host: 1.2.3.4" -u user:pass https://1.2.3.4:443

# Expected:
# - Connection CLOSED (HTTP 444)
```

**Test Case 22: Host Header Validation in Nginx Config**
```bash
# Verify config has VULN-001 fix
grep -A 2 'if ($host !=' /opt/familytraffic/config/reverse-proxy/myproxy.example.com.conf

# Expected Output:
# if ($host != "myproxy.example.com") {
#     return 444;
# }
```

---

#### 7.5.4 Rate Limiting Testing (VULN-003/VULN-004 Mitigation)

**Test Case 23: Normal Traffic (Below Rate Limit)**
```bash
# Test 10 requests (below 20/second burst limit)
for i in {1..10}; do
  curl -s -u user:pass https://myproxy.example.com > /dev/null
done

# Expected:
# - All requests succeed (HTTP 200)
# - No rate limit errors
```

**Test Case 24: Burst Traffic (Above Rate Limit)**
```bash
# Test 50 rapid requests (exceeds 20/second burst limit)
for i in {1..50}; do
  curl -s -u user:pass https://myproxy.example.com > /dev/null &
done
wait

# Expected:
# - Some requests return HTTP 503 (Service Temporarily Unavailable)
# - nginx error log: "limiting requests, excess"
```

**Test Case 25: Connection Limit (Per IP)**
```bash
# Test 10 concurrent connections (exceeds 5 connection limit)
for i in {1..10}; do
  curl -u user:pass https://myproxy.example.com &
done
wait

# Expected:
# - Some connections rejected with HTTP 503
# - nginx error log: "limiting connections by zone"
```

**Test Case 26: Rate Limit Configuration Validation**
```bash
# Verify rate limiting config in HTTP context file
cat /opt/familytraffic/config/reverse-proxy-http-context.conf

# Expected:
# limit_req_zone $binary_remote_addr zone=reverseproxy:10m rate=10r/s;
# limit_conn_zone $binary_remote_addr zone=conn_limit_per_ip:10m;
# (Must be present)
```

---

#### 7.5.5 Domain Restriction Testing (Xray Routing Validation)

**Test Case 27: Target Site Accessibility**
```bash
# Test that target site is reachable
curl -u user:pass https://myproxy.example.com

# Expected:
# - Content from blocked-site.com
# - Response headers from target site

# Verify Host header forwarded correctly
curl -v -u user:pass https://myproxy.example.com 2>&1 | grep -i "host:"

# Expected in nginx logs:
# proxy_set_header Host blocked-site.com (hardcoded, NOT $host)
```

**Test Case 28: Non-Target Site Blocked (Domain Restriction)**
```bash
# Attempt to access different site (should NOT work)
# NOTE: Reverse proxy is site-specific, no arbitrary browsing allowed

# Verify Xray config only routes to target site
docker exec familytraffic cat /etc/xray/config.json | jq '.inbounds[] | select(.port==10800)'

# Expected:
# - Xray inbound configured for specific domain only
# - No wildcard routing
# - Connection to non-target sites should fail or timeout
```

**Test Case 29: Multiple Domain Support (Subdomain-Based)**
```bash
# If multiple reverse proxies configured (e.g., domain1, domain2)
# Test isolation between domains

# Domain 1 (NO PORT NUMBER)
curl -u user1:pass1 https://domain1.example.com  # Target: site1.com

# Domain 2 (NO PORT NUMBER)
curl -u user2:pass2 https://domain2.example.com  # Target: site2.com

# Expected:
# - Each domain serves ONLY its target site
# - No cross-domain access
# - HAProxy SNI routing to Nginx:9443 and Nginx:9444
# - Each uses separate Xray inbound (10080, 10081)
```

---

#### 7.5.6 Privacy and Logging Tests

**Test Case 30: No Access Logs (Privacy Requirement)**
```bash
# Verify access logging DISABLED
ls -la /opt/familytraffic/logs/nginx/reverse-proxy-access.log

# Expected:
# - File DOES NOT EXIST
# - nginx config: access_log off;

# Check nginx config for access_log directive
grep -r "access_log" /opt/familytraffic/config/reverse-proxy/*.conf

# Expected:
# access_log off;  # (NOT access_log /path/to/log)
```

**Test Case 31: Error Log Contains Auth Failures Only**
```bash
# Check error log after failed auth attempt
curl -u user:wrongpass https://myproxy.example.com
cat /opt/familytraffic/logs/nginx/reverse-proxy-error.log | tail -5

# Expected Log Entries:
# - Authentication failures (401)
# - Host header mismatches (444)
# - Rate limit events (503)
# - NO user URLs
# - NO IP addresses in privacy-sensitive context
```

---

#### 7.5.7 Container Health and Restart Tests

**Test Case 32: Nginx Health Check**
```bash
# Check container health status
docker ps --format "{{.Names}}: {{.Status}}" | grep familytraffic

# Expected:
# familytraffic: Up X minutes (healthy)

# Manually trigger health check
docker exec familytraffic nginx -t

# Expected:
# nginx: configuration file /etc/nginx/nginx.conf test is successful
```

**Test Case 33: Container Auto-Recovery**
```bash
# Simulate nginx crash
docker exec familytraffic killall nginx

# Wait 10 seconds
sleep 10

# Check status
docker ps | grep familytraffic

# Expected:
# - Container auto-restarted (Docker restart policy)
# - Status: Up <10 seconds
# - Reverse proxy accessible again
```

---

#### 7.5.8 Port Allocation and Management Tests (v4.3)

**Test Case 34: Dynamic Port Addition (Subdomain-Based)**
```bash
# Add new reverse proxy (subdomain-based, NO port in URL)
sudo vless-setup-proxy

# Follow prompts:
# - Domain: proxy2.example.com
# - Target: site2.com
# - Port: 9444 (auto-suggested, localhost-only)

# Verify HAProxy ACL added
grep "is_proxy2" /opt/familytraffic/config/haproxy.cfg

# Expected:
# - acl is_proxy2 req.ssl_sni -i proxy2.example.com
# - use_backend nginx_proxy2 if is_proxy2

# Verify nginx config created (localhost binding)
cat /opt/familytraffic/config/reverse-proxy/proxy2.example.com.conf | grep "listen"

# Expected:
# - listen 9444 ssl http2;  # (NOT 8444, port range changed in v4.3)

# Access without port number
curl -u user:pass https://proxy2.example.com

# Expected:
# - Works via HAProxy SNI routing (port 443 → Nginx:9444)
```

**Test Case 35: Port Conflict Detection**
```bash
# Attempt to create reverse proxy with occupied port
sudo vless-setup-proxy
# Enter port: 443 (VLESS port - should be rejected)

# Expected:
# - Error: "Port 443 already in use by VLESS service"
# - Prompt for alternative port
# - Port allocation suggestions (9443-9452, changed from 8443-8452)
```

**Test Case 36: Maximum Domain Limit**
```bash
# Check current reverse proxy count
jq '.reverse_proxies | length' /opt/familytraffic/config/reverse_proxies.json

# If count == 10, attempt to add 11th
sudo vless-setup-proxy

# Expected:
# - Error: "Maximum 10 reverse proxy domains reached"
# - Suggestion: "Use separate server for additional domains"
```

---

#### 7.5.9 Integration Tests (v4.3 HAProxy)

**Test Case 37: End-to-End Reverse Proxy Setup (Subdomain-Based)**
```bash
# Full workflow test
1. sudo vless-setup-proxy
   - Domain: test.example.com
   - Target: github.com
   - Port: 9443 (custom, localhost-only)

2. Wait for Let's Encrypt certificate (up to 60 seconds)

3. Test subdomain access (NO port number)
   curl -u $(jq -r '.reverse_proxies[0].username' /opt/familytraffic/config/reverse_proxies.json):PASSWORD https://test.example.com

# Expected:
# - DNS validated (dig test.example.com)
# - Certificate acquired (/etc/letsencrypt/live/test.example.com/)
# - HAProxy ACL added (req.ssl_sni -i test.example.com)
# - HAProxy backend added (nginx_test, port 9443)
# - Nginx config generated (listen 9443 ssl)
# - Xray inbound created (port 10080)
# - HAProxy gracefully reloaded (haproxy -sf)
# - HTTP 200 from github.com
# - Access via https://test.example.com (NO :9443 port!)
```

**Test Case 38: Reverse Proxy Removal (v4.3)**
```bash
# Remove reverse proxy
sudo familytraffic-proxy remove test.example.com

# Expected:
# - HAProxy ACL removed
# - HAProxy backend removed
# - HAProxy gracefully reloaded
# - Nginx config deleted
# - Xray inbound removed
# - fail2ban jail removed
# - reverse_proxies.json updated
# - Certificate retained (for manual renewal if re-enabled)
```

---

#### 7.5.10 Penetration Testing (Security Validation)

**Test Case 39: Nmap Service Detection (HAProxy SNI Routing)**
```bash
# Scan HAProxy port 443 (SNI routing)
nmap -sV -p 443 myproxy.example.com

# Expected Output:
# PORT     STATE SERVICE  VERSION
# 443/tcp  open  ssl/unknown  (SNI routing, HAProxy)

# Should NOT reveal:
# - "reverse proxy" in service name
# - Backend Nginx/Xray details
```

**Test Case 40: SSL/TLS Vulnerability Scan (testssl.sh)**
```bash
# Run comprehensive TLS test on subdomain
testssl.sh https://myproxy.example.com

# Expected:
# - TLS 1.3: YES
# - TLS 1.2: NO (disabled)
# - TLS 1.1/1.0: NO
# - HSTS: present (max-age=31536000)
# - Forward Secrecy: YES
# - Cipher suites: STRONG (AES-256-GCM, ChaCha20-Poly1305)
# - Certificate: Let's Encrypt, valid, no warnings
# - HAProxy SNI routing transparent to scanner
```

**Test Case 41: Web Vulnerability Scan (nikto)**
```bash
# Scan for common web vulnerabilities
nikto -h https://myproxy.example.com -ssl

# Expected:
# - No critical vulnerabilities
# - No information disclosure
# - No directory listing
# - No default credentials
# - Authentication required (401 without creds)
```

**Test Case 42: Security Headers Validation**
```bash
# Check security headers
curl -I -u user:pass https://myproxy.example.com

# Expected Headers:
# Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
# X-Frame-Options: DENY or SAMEORIGIN (if added)
# X-Content-Type-Options: nosniff (if added)

# Must NOT contain:
# Server: nginx/1.x.x (version disclosure)
# X-Powered-By: (any value)
```

---

#### 7.5.11 Performance and Load Tests

**Test Case 43: Latency Overhead Measurement (HAProxy SNI Routing)**
```bash
# Baseline: Direct access to target site
time curl -s https://blocked-site.com > /dev/null

# With Reverse Proxy (HAProxy SNI routing)
time curl -s -u user:pass https://myproxy.example.com > /dev/null

# Expected:
# - Latency overhead < 50ms (NFR-RPROXY-001)
# - Compare both times
# - HAProxy SNI routing adds minimal overhead
```

**Test Case 44: Throughput Test**
```bash
# Download large file through reverse proxy
curl -u user:pass https://myproxy.example.com/large-file.zip -o /dev/null

# Monitor throughput
# Expected:
# - Throughput: 100+ Mbps per domain (NFR-RPROXY-001)
# - No significant degradation vs direct access
```

**Test Case 45: Concurrent Connections Test**
```bash
# Simulate 100 concurrent users
ab -n 1000 -c 100 -A user:pass https://myproxy.example.com/

# Expected:
# - 95% requests succeed (< 5% rate limited)
# - Average response time < 500ms
# - No container crashes
# - Memory usage stable
# - HAProxy handles concurrent SNI routing
```

---

#### 7.5.12 Certificate Renewal Tests (v4.3 HAProxy)

**Test Case 46: Auto-Renewal Dry-Run (Reverse Proxy Certificates)**
```bash
# Test renewal for reverse proxy domain
sudo certbot renew --cert-name myproxy.example.com --dry-run

# Expected:
# - Simulated renewal succeeds
# - Deploy hook triggered (/usr/local/bin/familytraffic-cert-renew)
# - combined.pem regenerated (fullchain + privkey)
# - HAProxy gracefully reloaded (haproxy -sf <old_pid>)
# - Downtime < 5 seconds
```

**Test Case 47: Certificate Expiry Monitoring**
```bash
# Check certificate expiration dates
for cert in /etc/letsencrypt/live/*/cert.pem; do
  openssl x509 -in "$cert" -noout -enddate
done

# Expected:
# - All certificates valid for > 30 days
# - Expiry dates logged
# - Alert mechanism configured (certbot email notifications)
```

---

#### 7.5.13 HAProxy-Specific Tests (NEW v4.3)

**Test Case 48: HAProxy Stats Page**
```bash
# Access HAProxy stats page (localhost-only)
curl http://localhost:9000/stats

# Expected:
# - HTML stats page returned
# - Shows all frontends (vless-reality, socks5-tls, http-tls)
# - Shows all backends (xray_reality, xray_socks5, xray_http, nginx_*)
# - Session counts, error rates, health status
```

**Test Case 49: HAProxy Graceful Reload (Zero Downtime)**
```bash
# Add new reverse proxy (triggers reload)
sudo familytraffic-proxy add

# Monitor active connections during reload
watch -n 1 'docker exec familytraffic netstat -an | grep ESTABLISHED | wc -l'

# Expected:
# - Established connections maintained during reload
# - New connections handled immediately after reload
# - No connection drops
# - Downtime < 1 second
```

**Test Case 50: HAProxy SNI Routing Validation**
```bash
# Test SNI routing for multiple domains
curl -v --resolve domain1.example.com:443:SERVER_IP https://domain1.example.com 2>&1 | grep "SNI"
curl -v --resolve domain2.example.com:443:SERVER_IP https://domain2.example.com 2>&1 | grep "SNI"

# Expected:
# - SNI header sent correctly
# - HAProxy routes based on SNI
# - domain1 → Nginx:9443
# - domain2 → Nginx:9444
```

**Test Case 51: fail2ban HAProxy Filter**
```bash
# Trigger auth failures on SOCKS5 proxy (HAProxy frontend)
for i in {1..5}; do
  curl --socks5 user:wrongpass@server:1080 https://google.com 2>&1 | grep -i "auth"
  sleep 1
done

# Check fail2ban HAProxy jail
sudo fail2ban-client status familytraffic

# Expected:
# - IP banned after 5 failures
# - HAProxy logs parsed by fail2ban filter
# - UFW rule added to block IP
```

---

**Навигация:** [Обзор](01_overview.md) | [Функциональные требования](02_functional_requirements.md) | [NFR](03_nfr.md) | [Архитектура](04_architecture.md) | [Тестирование](05_testing.md) | [Приложения](06_appendix.md) | [← Саммари](00_summary.md)
