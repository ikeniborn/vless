# PRD v4.1 - Testing Requirements

**Навигация:** [Обзор](01_overview.md) | [Функциональные требования](02_functional_requirements.md) | [NFR](03_nfr.md) | [Архитектура](04_architecture.md) | [Тестирование](05_testing.md) | [Приложения](06_appendix.md) | [← Саммари](00_summary.md)

---

## 7. Testing Requirements

### 7.1 TLS Integration Tests (NEW)

**Test Case 1: TLS Handshake - SOCKS5**
```bash
# Verify TLS on SOCKS5 port
openssl s_client -connect server:1080 -showcerts

# Expected Output:
# - Certificate chain displayed
# - Issuer: Let's Encrypt
# - Subject: CN=vpn.example.com
# - Verify return code: 0 (ok)
```

**Test Case 2: TLS Handshake - HTTP/HTTPS**
```bash
# Verify HTTPS on HTTP proxy port
curl -I --proxy https://user:pass@server:8118 https://google.com

# Expected Output:
# HTTP/1.1 200 OK
# (no SSL warnings)
```

**Test Case 3: Certificate Validation**
```bash
# Check certificate validity
openssl x509 -in /etc/letsencrypt/live/${DOMAIN}/cert.pem -noout -text

# Expected:
# - Issuer: Let's Encrypt
# - Validity: 90 days from issuance
# - Subject Alt Name: DNS:vpn.example.com
```

**Test Case 4: Auto-Renewal Dry-Run**
```bash
# Test renewal without actually renewing
sudo certbot renew --dry-run

# Expected Output:
# Congratulations, all simulated renewals succeeded
```

**Test Case 5: Deploy Hook Execution**
```bash
# Manually trigger deploy hook
sudo /usr/local/bin/vless-cert-renew

# Expected:
# - Xray restarts successfully
# - Downtime < 5 seconds
# - docker logs shows restart
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
- ✅ Xray logs show HTTPS connection

**Test Case 7: Git Clone via SOCKS5s Proxy**
```bash
# Configure Git
git config --global http.proxy socks5s://alice:PASSWORD@server:1080

# Clone repository
git clone https://github.com/torvalds/linux.git

# Expected:
# - Clone succeeds
# - No TLS errors
# - Xray logs show SOCKS5 connection
```

---

### 7.3 Security Tests (v3.3)

**Test Case 8: Wireshark Traffic Capture**
```bash
# Capture proxy traffic
sudo tcpdump -i any -w /tmp/proxy_traffic.pcap port 1080

# Analyze in Wireshark
wireshark /tmp/proxy_traffic.pcap

# Expected:
# - TLS 1.3 handshake visible
# - Application Data encrypted
# - NO plaintext SOCKS5/HTTP
# - NO plaintext credentials
```

**Test Case 9: Nmap Service Detection**
```bash
# Scan proxy ports
nmap -sV -p 1080,8118 server

# Expected Output:
# PORT     STATE SERVICE  VERSION
# 1080/tcp open  ssl/socks
# 8118/tcp open  ssl/http
```

**Test Case 10: Config Validation - No Plain Proxy**
```bash
# Ensure no plain proxy on public interface
jq '.inbounds[] | select(.listen=="0.0.0.0") | {tag, security: .streamSettings.security}' /opt/vless/config/xray_config.json

# Expected:
# {"tag": "socks5-tls", "security": "tls"}
# {"tag": "http-tls", "security": "tls"}
# (NO entries with "security": null or missing)
```

---

### 7.4 Backward Compatibility Tests (v3.2 → v3.3)

**Test Case 11: Old Configs Must Fail**
```bash
# Try connecting with old v3.2 plain config
curl --socks5 alice:PASSWORD@server:1080 https://ifconfig.me

# Expected:
# - Connection FAILS (plain SOCKS5 not accepted)
# - Error: "TLS handshake required"
```

**Test Case 12: New Configs Must Work**
```bash
# Connect with new v3.3 TLS config
curl --socks5 alice:PASSWORD@server:1080 --proxy-insecure https://ifconfig.me
# (Note: --proxy-insecure needed if testing with self-signed, NOT needed with Let's Encrypt)

# Expected:
# - Connection succeeds
# - Returns external IP
```

---

### 7.5 Reverse Proxy Tests (v4.2 - NEW)

#### 7.5.1 Authentication Testing (HTTP Basic Auth)

**Test Case 13: Valid Credentials**
```bash
# Test successful authentication
curl -u user:password https://myproxy.example.com:8443

# Expected:
# - HTTP 200 OK
# - Content from target site (blocked-site.com)
# - No authentication errors
```

**Test Case 14: Invalid Credentials**
```bash
# Test authentication rejection
curl -u user:wrongpass https://myproxy.example.com:8443

# Expected:
# - HTTP 401 Unauthorized
# - WWW-Authenticate: Basic realm="Reverse Proxy"
# - fail2ban logs show auth failure
```

**Test Case 15: No Credentials**
```bash
# Test missing authentication
curl https://myproxy.example.com:8443

# Expected:
# - HTTP 401 Unauthorized
# - Prompt for credentials
```

**Test Case 16: Brute Force Protection (fail2ban)**
```bash
# Simulate 5 failed attempts
for i in {1..5}; do
  curl -u user:wrongpass https://myproxy.example.com:8443
  sleep 1
done

# Check fail2ban status
sudo fail2ban-client status vless-reverse-proxy-8443

# Expected:
# - IP banned after 5 failures
# - Ban duration: 1 hour
# - UFW blocks banned IP
# - Subsequent requests fail immediately
```

---

#### 7.5.2 TLS Configuration Testing

**Test Case 17: TLS 1.3 Enforcement**
```bash
# Verify TLS 1.3 required
openssl s_client -connect myproxy.example.com:8443 -tls1_3

# Expected:
# - TLS 1.3 handshake succeeds
# - Protocol: TLSv1.3
# - Cipher: TLS_AES_256_GCM_SHA384 or TLS_CHACHA20_POLY1305_SHA256

# Test TLS 1.2 rejection
openssl s_client -connect myproxy.example.com:8443 -tls1_2

# Expected:
# - Handshake FAILS
# - Error: "no protocols available" or "unsupported protocol"
```

**Test Case 18: HSTS Header Validation (VULN-002 Mitigation)**
```bash
# Check HSTS header present
curl -I -u user:password https://myproxy.example.com:8443

# Expected Headers:
# Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
# (MUST be present on all responses)

# Verify HSTS enforcement
# 1. First request with HTTPS
curl -v -u user:pass https://myproxy.example.com:8443 2>&1 | grep -i "strict-transport"

# 2. Browser should auto-upgrade HTTP to HTTPS after first visit
```

**Test Case 19: Certificate Validation**
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
curl -H "Host: myproxy.example.com" -u user:pass https://myproxy.example.com:8443

# Expected:
# - HTTP 200 OK
# - Content from target site
```

**Test Case 21: Invalid Host Header (Attack Simulation)**
```bash
# Test Host Header Injection attempt
curl -H "Host: evil.com" -u user:pass https://myproxy.example.com:8443

# Expected:
# - Connection CLOSED (HTTP 444)
# - NO response body
# - nginx error log: "Host header mismatch"

# Test with IP instead of domain
curl -H "Host: 1.2.3.4" -u user:pass https://1.2.3.4:8443

# Expected:
# - Connection CLOSED (HTTP 444)
```

**Test Case 22: Host Header Validation in Nginx Config**
```bash
# Verify config has VULN-001 fix
grep -A 2 'if ($host !=' /opt/vless/config/reverse-proxy/myproxy.example.com_8443.conf

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
  curl -s -u user:pass https://myproxy.example.com:8443 > /dev/null
done

# Expected:
# - All requests succeed (HTTP 200)
# - No rate limit errors
```

**Test Case 24: Burst Traffic (Above Rate Limit)**
```bash
# Test 50 rapid requests (exceeds 20/second burst limit)
for i in {1..50}; do
  curl -s -u user:pass https://myproxy.example.com:8443 > /dev/null &
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
  curl -u user:pass https://myproxy.example.com:8443 &
done
wait

# Expected:
# - Some connections rejected with HTTP 503
# - nginx error log: "limiting connections by zone"
```

**Test Case 26: Rate Limit Configuration Validation**
```bash
# Verify rate limiting config in HTTP context file
cat /opt/vless/config/reverse-proxy-http-context.conf

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
curl -u user:pass https://myproxy.example.com:8443

# Expected:
# - Content from blocked-site.com
# - Response headers from target site

# Verify Host header forwarded correctly
curl -v -u user:pass https://myproxy.example.com:8443 2>&1 | grep -i "host:"

# Expected in nginx logs:
# proxy_set_header Host blocked-site.com (hardcoded, NOT $host)
```

**Test Case 28: Non-Target Site Blocked (Domain Restriction)**
```bash
# Attempt to access different site (should NOT work)
# NOTE: Reverse proxy is site-specific, no arbitrary browsing allowed

# Verify Xray config only routes to target site
docker exec vless_xray cat /etc/xray/config.json | jq '.inbounds[] | select(.port==10080)'

# Expected:
# - Xray inbound configured for specific domain only
# - No wildcard routing
# - Connection to non-target sites should fail or timeout
```

**Test Case 29: Multiple Domain Support**
```bash
# If multiple reverse proxies configured (e.g., domain1:8443, domain2:8444)
# Test isolation between domains

# Domain 1
curl -u user1:pass1 https://domain1.example.com:8443  # Target: site1.com

# Domain 2
curl -u user2:pass2 https://domain2.example.com:8444  # Target: site2.com

# Expected:
# - Each domain serves ONLY its target site
# - No cross-domain access
# - Each uses separate Xray inbound (10080, 10081)
```

---

#### 7.5.6 Privacy and Logging Tests

**Test Case 30: No Access Logs (Privacy Requirement)**
```bash
# Verify access logging DISABLED
ls -la /opt/vless/logs/nginx/reverse-proxy-access.log

# Expected:
# - File DOES NOT EXIST
# - nginx config: access_log off;

# Check nginx config for access_log directive
grep -r "access_log" /opt/vless/config/reverse-proxy/*.conf

# Expected:
# access_log off;  # (NOT access_log /path/to/log)
```

**Test Case 31: Error Log Contains Auth Failures Only**
```bash
# Check error log after failed auth attempt
curl -u user:wrongpass https://myproxy.example.com:8443
cat /opt/vless/logs/nginx/reverse-proxy-error.log | tail -5

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
docker ps --format "{{.Names}}: {{.Status}}" | grep vless_nginx_reverseproxy

# Expected:
# vless_nginx_reverseproxy: Up X minutes (healthy)

# Manually trigger health check
docker exec vless_nginx_reverseproxy nginx -t

# Expected:
# nginx: configuration file /etc/nginx/nginx.conf test is successful
```

**Test Case 33: Container Auto-Recovery**
```bash
# Simulate nginx crash
docker exec vless_nginx_reverseproxy killall nginx

# Wait 10 seconds
sleep 10

# Check status
docker ps | grep vless_nginx_reverseproxy

# Expected:
# - Container auto-restarted (Docker restart policy)
# - Status: Up <10 seconds
# - Reverse proxy accessible again
```

---

#### 7.5.8 Port Allocation and Management Tests

**Test Case 34: Dynamic Port Addition**
```bash
# Add new reverse proxy (port 8444)
sudo vless-setup-proxy

# Follow prompts:
# - Domain: proxy2.example.com
# - Target: site2.com
# - Port: 8444 (auto-suggested)

# Verify port added to docker-compose.yml
grep -A 5 "nginx:" /opt/vless/docker-compose.yml | grep "8444"

# Expected:
# - "8444:8444"

# Verify nginx config created
ls /opt/vless/config/reverse-proxy/proxy2.example.com_8444.conf

# Expected:
# - Config file exists with correct port and domain
```

**Test Case 35: Port Conflict Detection**
```bash
# Attempt to create reverse proxy with occupied port
sudo vless-setup-proxy
# Enter port: 443 (VLESS port - should be rejected)

# Expected:
# - Error: "Port 443 already in use by VLESS service"
# - Prompt for alternative port
# - Port allocation suggestions (8443-8452)
```

**Test Case 36: Maximum Domain Limit**
```bash
# Check current reverse proxy count
jq '.reverse_proxies | length' /opt/vless/config/reverse_proxies.json

# If count == 10, attempt to add 11th
sudo vless-setup-proxy

# Expected:
# - Error: "Maximum 10 reverse proxy domains reached"
# - Suggestion: "Use separate server for additional domains"
```

---

#### 7.5.9 Integration Tests

**Test Case 37: End-to-End Reverse Proxy Setup**
```bash
# Full workflow test
1. sudo vless-setup-proxy
   - Domain: test.example.com
   - Target: github.com
   - Port: 9443 (custom)

2. Wait for Let's Encrypt certificate (up to 60 seconds)

3. Test access
   curl -u $(jq -r '.reverse_proxies[0].username' /opt/vless/config/reverse_proxies.json):PASSWORD https://test.example.com:9443

# Expected:
# - DNS validated (dig test.example.com)
# - Certificate acquired (/etc/letsencrypt/live/test.example.com/)
# - Nginx config generated
# - Xray inbound created (port 10080)
# - Docker Compose updated (port 9443 exposed)
# - nginx container reloaded
# - HTTP 200 from github.com
```

**Test Case 38: Reverse Proxy Removal**
```bash
# Remove reverse proxy
sudo vless-proxy remove test.example.com

# Expected:
# - Nginx config deleted
# - Xray inbound removed
# - Docker Compose port removed
# - fail2ban jail removed
# - reverse_proxies.json updated
# - Certificate retained (for manual renewal if re-enabled)
```

---

#### 7.5.10 Penetration Testing (Security Validation)

**Test Case 39: Nmap Service Detection**
```bash
# Scan reverse proxy port
nmap -sV -p 8443 myproxy.example.com

# Expected Output:
# PORT     STATE SERVICE  VERSION
# 8443/tcp open  ssl/http nginx

# Should NOT reveal:
# - "reverse proxy" in service name
# - Backend Xray details
```

**Test Case 40: SSL/TLS Vulnerability Scan (testssl.sh)**
```bash
# Run comprehensive TLS test
testssl.sh https://myproxy.example.com:8443

# Expected:
# - TLS 1.3: YES
# - TLS 1.2: NO (disabled)
# - TLS 1.1/1.0: NO
# - HSTS: present (max-age=31536000)
# - Forward Secrecy: YES
# - Cipher suites: STRONG (AES-256-GCM, ChaCha20-Poly1305)
# - Certificate: Let's Encrypt, valid, no warnings
```

**Test Case 41: Web Vulnerability Scan (nikto)**
```bash
# Scan for common web vulnerabilities
nikto -h https://myproxy.example.com:8443 -ssl

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
curl -I -u user:pass https://myproxy.example.com:8443

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

**Test Case 43: Latency Overhead Measurement**
```bash
# Baseline: Direct access to target site
time curl -s https://blocked-site.com > /dev/null

# With Reverse Proxy
time curl -s -u user:pass https://myproxy.example.com:8443 > /dev/null

# Expected:
# - Latency overhead < 50ms (NFR-RPROXY-001)
# - Compare both times
```

**Test Case 44: Throughput Test**
```bash
# Download large file through reverse proxy
curl -u user:pass https://myproxy.example.com:8443/large-file.zip -o /dev/null

# Monitor throughput
# Expected:
# - Throughput: 100+ Mbps per domain (NFR-RPROXY-001)
# - No significant degradation vs direct access
```

**Test Case 45: Concurrent Connections Test**
```bash
# Simulate 100 concurrent users
ab -n 1000 -c 100 -A user:pass https://myproxy.example.com:8443/

# Expected:
# - 95% requests succeed (< 5% rate limited)
# - Average response time < 500ms
# - No container crashes
# - Memory usage stable
```

---

#### 7.5.12 Certificate Renewal Tests

**Test Case 46: Auto-Renewal Dry-Run (Reverse Proxy Certificates)**
```bash
# Test renewal for reverse proxy domain
sudo certbot renew --cert-name myproxy.example.com --dry-run

# Expected:
# - Simulated renewal succeeds
# - Deploy hook triggered (/usr/local/bin/vless-cert-renew)
# - nginx container reloaded
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

**Навигация:** [Обзор](01_overview.md) | [Функциональные требования](02_functional_requirements.md) | [NFR](03_nfr.md) | [Архитектура](04_architecture.md) | [Тестирование](05_testing.md) | [Приложения](06_appendix.md) | [← Саммари](00_summary.md)
