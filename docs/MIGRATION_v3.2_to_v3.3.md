# Migration Guide: VLESS Reality VPN v3.2 → v3.3

**Document Version**: 1.0
**Date**: 2025-10-06
**Target Audience**: System administrators upgrading from v3.2
**Security Notice**: ⚠️ **CRITICAL SECURITY UPDATE** - v3.2 Public Proxy Mode is NOT production-ready

---

## Executive Summary

Version 3.3 introduces **mandatory TLS encryption** for public proxy mode, addressing a critical security vulnerability in v3.2 where SOCKS5/HTTP credentials were transmitted in plaintext over the internet.

**Upgrade Priority**: 🔴 **CRITICAL** if using Public Proxy Mode
**Upgrade Priority**: 🟢 **LOW** if using VLESS-only Mode

---

## Overview

### Critical Security Issue in v3.2

**CVE-equivalent Severity**: HIGH

v3.2 Public Proxy Mode exposes SOCKS5 (port 1080) and HTTP (port 8118) proxies to the internet **without TLS encryption**, transmitting usernames and passwords in plaintext.

**Attack Vector**:
```bash
# Attacker intercepts traffic
tcpdump -i any port 1080 -A
# Result: Username and password visible in plaintext
```

**Impact**:
- 100% credential compromise via passive network sniffing
- Man-in-the-middle attacks trivial to execute
- Not suitable for production use

**v3.3 Solution**: Mandatory TLS encryption via Let's Encrypt certificates

---

## Key Changes

| Feature | v3.2 | v3.3 |
|---------|------|------|
| **SOCKS5 Encryption** | ❌ Plaintext | ✅ TLS 1.3 (socks5s://) |
| **HTTP Encryption** | ❌ Plaintext | ✅ TLS 1.3 (https://) |
| **Certificate Management** | N/A | Let's Encrypt (auto-renewal) |
| **Domain Requirement** | Not required | **Required** (for TLS cert) |
| **DNS Configuration** | Not required | **Required** (A record) |
| **Port 80 Access** | Not required | Temporary (ACME challenge) |
| **URI Schemes** | `socks5://`, `http://` | `socks5s://`, `https://` |
| **Client Configs** | 5 files (IP-based) | 6 files (domain-based + git) |
| **Security Status** | ⚠️ NOT PRODUCTION-READY | ✅ PRODUCTION-READY |

---

## Breaking Changes

### 1. TLS Encryption Mandatory for Public Proxy

**Impact**: v3.2 plaintext proxy configs will **NOT work** with v3.3.

**Before (v3.2 - INSECURE)**:
```
SOCKS5: socks5://user:pass@203.0.113.45:1080
HTTP:   http://user:pass@203.0.113.45:8118
```

**After (v3.3 - SECURE)**:
```
SOCKS5: socks5s://user:pass@vpn.example.com:1080
HTTP:   https://user:pass@vpn.example.com:8118
```

**Action Required**:
1. Configure DNS A record pointing to your server
2. Run v3.3 installer (acquires Let's Encrypt certificate)
3. Regenerate ALL client configurations

---

### 2. Domain Name Required

**Impact**: Public proxy mode now requires a fully-qualified domain name (FQDN).

**Requirements**:
- Valid domain name (e.g., `vpn.example.com`)
- DNS A record pointing to server public IP
- Port 80 accessible (temporary, for ACME HTTP-01 challenge)
- Valid email for Let's Encrypt notifications

**Action Required**:
```bash
# Configure DNS before installation
# Example: Create A record
vpn.example.com.  IN  A  203.0.113.45
```

---

### 3. Certificate Auto-Renewal

**Impact**: Let's Encrypt certificates expire after 90 days and must be auto-renewed.

**v3.3 Implementation**:
- Cron job runs twice daily (00:00, 12:00 UTC)
- Renewal triggered at 60 days (30-day grace period)
- Xray automatically restarts after renewal
- Email notifications on failures

**Action Required**: Ensure email is valid for renewal failure alerts.

---

### 4. Client Configuration Format Changes

**Impact**: All 6 client config files use domain instead of IP address.

**Changed Files**:
1. `socks5_config.txt`: `socks5://` → `socks5s://`, IP → domain
2. `http_config.txt`: `http://` → `https://`, IP → domain
3. `vscode_settings.json`: `http://` → `https://`, strict SSL enabled
4. `docker_daemon.json`: `http://` → `https://`
5. `bash_exports.sh`: `http://` → `https://`
6. `git_config.txt`: NEW - Git proxy instructions with TLS

**Action Required**: Distribute updated configs to all users.

---

## Pre-Migration Checklist

Before upgrading to v3.3, ensure:

- [ ] Domain name registered and accessible
- [ ] DNS A record configured (verify: `dig +short vpn.example.com`)
- [ ] Server public IP matches DNS A record
- [ ] Port 80 not occupied (check: `sudo ss -tulnp | grep :80`)
- [ ] Valid email address for Let's Encrypt notifications
- [ ] UFW firewall active (check: `sudo ufw status`)
- [ ] Backup of `/opt/vless/` created
- [ ] All users notified of upcoming config changes
- [ ] Maintenance window scheduled (est. 10-15 minutes downtime)

---

## Migration Path

### Step 1: Backup Current Installation

```bash
# Create timestamped backup
BACKUP_DIR="/opt/vless.v3.2.backup.$(date +%Y%m%d_%H%M%S)"
sudo cp -r /opt/vless "$BACKUP_DIR"

# Verify backup
ls -lh "$BACKUP_DIR"

# Backup includes:
# - config/xray_config.json
# - config/users.json (with proxy passwords)
# - data/clients/ (all user configs)
```

---

### Step 2: Update Code

```bash
cd /path/to/vless
git fetch origin
git checkout proxy-public  # v3.3 branch
git pull origin proxy-public
```

---

### Step 3: Stop Existing Services

```bash
# Stop containers
cd /opt/vless
sudo docker-compose down

# Verify stopped
sudo docker ps | grep vless
# Should return nothing
```

---

### Step 4: Configure DNS

**Before proceeding**, verify DNS is correctly configured:

```bash
# Get server public IP
SERVER_IP=$(curl -s ifconfig.me)
echo "Server IP: $SERVER_IP"

# Check DNS resolution
DOMAIN="vpn.example.com"  # Replace with your domain
DNS_IP=$(dig +short $DOMAIN A | head -1)
echo "DNS resolves to: $DNS_IP"

# Verify match
if [ "$SERVER_IP" == "$DNS_IP" ]; then
    echo "✅ DNS configured correctly"
else
    echo "❌ DNS mismatch - fix before continuing"
    exit 1
fi
```

---

### Step 5: Run v3.3 Installer

```bash
cd /path/to/vless
sudo ./install.sh
```

**Installer Workflow**:

1. **Detects v3.2 installation** → Offers update option
2. **Prompts for parameters**:
   - Destination site (default: google.com:443)
   - VLESS port (default: 443)
   - Docker subnet (auto-detected)
   - **Enable public proxy?** → Select **YES**
   - **Domain name**: Enter your FQDN
   - **Email**: Enter valid email for Let's Encrypt

3. **Certificate Acquisition** (new in v3.3):
   - DNS validation
   - Certbot installation
   - Opens port 80 (temporary)
   - ACME HTTP-01 challenge
   - Certificate download
   - Closes port 80
   - Sets up auto-renewal cron

4. **Preserves User Data**:
   - All users from v3.2 retained
   - Proxy passwords unchanged
   - UUIDs and shortIds preserved

5. **Updates Configuration**:
   - Xray config with TLS enabled
   - Docker volume mount for `/etc/letsencrypt`
   - UFW rules updated

---

### Step 6: Verify Installation

```bash
# Check containers
sudo docker ps
# Should show: vless-reality (Up), vless-fake-site (Up)

# Verify TLS
sudo /opt/vless/lib/verification.sh
# Should show:
# Verification 5.5/10: Testing Xray configuration... ✅
# Verification 5.6/10: Validating TLS encryption... ✅

# Check certificates
sudo ls -la /etc/letsencrypt/live/$DOMAIN/
# Should show: fullchain.pem, privkey.pem

# Verify expiry
sudo openssl x509 -in /etc/letsencrypt/live/$DOMAIN/cert.pem -noout -enddate
# Should show expiry ~90 days from now

# Test TLS handshake (SOCKS5)
openssl s_client -connect vpn.example.com:1080 -servername vpn.example.com
# Should complete TLS handshake

# Test TLS handshake (HTTP)
curl -I --proxy https://user:pass@vpn.example.com:8118 https://google.com
# Should return HTTP 200 (or redirects)
```

---

### Step 7: Regenerate Client Configurations

**CRITICAL**: All existing v3.2 configs are now invalid.

```bash
# List all users
sudo vless-user list

# Regenerate configs for each user
sudo vless-user regenerate alice
sudo vless-user regenerate bob
# ... repeat for all users

# Alternative: Regenerate all at once
for user in $(jq -r '.users[].username' /opt/vless/config/users.json); do
    sudo vless-user regenerate "$user"
done
```

**New Config Files per User** (6 total):
```
/opt/vless/data/clients/alice/
├── vless_config.json          # VLESS VPN config
├── vless_uri.txt              # VLESS connection string
├── qrcode.png                 # QR code for mobile
├── socks5_config.txt          # socks5s://alice:pass@vpn.example.com:1080
├── http_config.txt            # https://alice:pass@vpn.example.com:8118
├── vscode_settings.json       # VSCode proxy (https://)
├── docker_daemon.json         # Docker daemon proxy (https://)
├── bash_exports.sh            # Environment variables (https://)
└── git_config.txt             # NEW: Git proxy instructions
```

---

### Step 8: Distribute Updated Configs

**Methods**:

**Option A: Secure Copy (SCP)**
```bash
# From server
scp -r /opt/vless/data/clients/alice/ user@client-machine:/home/user/vless-configs/
```

**Option B: Display in Terminal**
```bash
# SOCKS5
sudo cat /opt/vless/data/clients/alice/socks5_config.txt

# HTTP
sudo cat /opt/vless/data/clients/alice/http_config.txt

# Git instructions
sudo cat /opt/vless/data/clients/alice/git_config.txt
```

**Option C: Generate Download Links** (advanced)
```bash
# Temporarily serve via nginx or python HTTP server
cd /opt/vless/data/clients/alice/
sudo python3 -m http.server 8000
# Access: http://server-ip:8000/socks5_config.txt
# IMPORTANT: Stop server after download!
```

---

### Step 9: Client-Side Configuration

**SOCKS5 Proxy (curl example)**:

```bash
# v3.2 (WILL FAIL on v3.3)
curl --socks5 alice:password@203.0.113.45:1080 https://ifconfig.me

# v3.3 (CORRECT)
curl --proxy socks5s://alice:password@vpn.example.com:1080 https://ifconfig.me
```

**HTTP Proxy (curl example)**:

```bash
# v3.2 (WILL FAIL on v3.3)
curl --proxy http://alice:password@203.0.113.45:8118 https://ifconfig.me

# v3.3 (CORRECT)
curl --proxy https://alice:password@vpn.example.com:8118 https://ifconfig.me
```

**Environment Variables (bash)**:

```bash
# Source the new config
source ~/vless-configs/bash_exports.sh

# Test
curl https://ifconfig.me
# Should return server IP (traffic routed through proxy)
```

**VSCode**:

```json
// v3.3 settings.json
{
  "http.proxy": "https://vpn.example.com:8118",
  "http.proxyAuthorization": "base64_encoded_credentials",
  "http.proxyStrictSSL": true  // NEW: Validate TLS certificate
}
```

**Git**:

```bash
# v3.3 (from git_config.txt)
git config --global http.proxy socks5s://alice:password@vpn.example.com:1080
git config --global https.proxy socks5s://alice:password@vpn.example.com:1080

# Test
git clone https://github.com/torvalds/linux.git
```

---

## Testing & Validation

### Test 1: TLS Encryption Verification

**Objective**: Confirm credentials are encrypted

```bash
# Capture traffic on server
sudo tcpdump -i any port 1080 -A -w /tmp/proxy_traffic.pcap

# From client, connect via proxy
curl --proxy socks5s://user:pass@vpn.example.com:1080 https://google.com

# Analyze capture
sudo tcpdump -r /tmp/proxy_traffic.pcap -A | grep "password"
# Result: Should NOT find plaintext password (encrypted by TLS)
```

**Expected**: TLS handshake visible, credentials encrypted

---

### Test 2: Certificate Validation

```bash
# Verify certificate chain
echo | openssl s_client -connect vpn.example.com:1080 -servername vpn.example.com 2>/dev/null | openssl x509 -noout -text

# Check:
# - Issuer: Let's Encrypt
# - Subject: CN=vpn.example.com
# - Validity: ~90 days
# - SAN: DNS:vpn.example.com
```

---

### Test 3: Auto-Renewal Dry Run

```bash
# Test renewal without actually renewing
sudo certbot renew --dry-run

# Expected output:
# - Congratulations, all simulated renewals succeeded
```

---

### Test 4: Client Compatibility

Test with each client config format:

- [ ] SOCKS5 via curl: `curl --proxy socks5s://...`
- [ ] HTTP via curl: `curl --proxy https://...`
- [ ] VSCode extension installation
- [ ] Docker pull through proxy
- [ ] Git clone through proxy
- [ ] Bash environment variables

---

## Rollback Procedure

If v3.3 upgrade fails or issues arise:

```bash
# Step 1: Stop v3.3 containers
cd /opt/vless
sudo docker-compose down

# Step 2: Remove v3.3 installation
sudo rm -rf /opt/vless

# Step 3: Restore v3.2 backup
BACKUP_DIR="/opt/vless.v3.2.backup.YYYYMMDD_HHMMSS"  # Use actual timestamp
sudo cp -r "$BACKUP_DIR" /opt/vless

# Step 4: Restart v3.2 containers
cd /opt/vless
sudo docker-compose up -d

# Step 5: Verify services
sudo docker ps
sudo vless-status

# Step 6: Notify users to revert to v3.2 configs
```

**Note**: Rollback to v3.2 means reverting to plaintext proxy (security risk).

---

## Troubleshooting

### Issue 1: DNS Resolution Failed

**Symptom**: Installer fails with "DNS resolution failed"

**Diagnosis**:
```bash
dig +short vpn.example.com
# Returns nothing or wrong IP
```

**Solution**:
1. Verify DNS A record is configured
2. Wait for DNS propagation (1-48 hours)
3. Test from multiple locations: `nslookup vpn.example.com 8.8.8.8`

---

### Issue 2: Let's Encrypt Rate Limit

**Symptom**: "too many certificates already issued"

**Diagnosis**:
```bash
# Let's Encrypt limits:
# - 5 failed validations per hour
# - 50 certificates per domain per week
```

**Solution**:
1. Wait 1 hour (for failed validation limit)
2. Wait 1 week (for certificate limit)
3. Use staging environment for testing:
   ```bash
   certbot certonly --staging -d vpn.example.com
   ```

---

### Issue 3: Port 80 Occupied

**Symptom**: "Port 80 already in use"

**Diagnosis**:
```bash
sudo ss -tulnp | grep :80
# Shows another process (nginx, apache, etc.)
```

**Solution**:
```bash
# Option 1: Temporarily stop conflicting service
sudo systemctl stop apache2  # or nginx

# Option 2: Use DNS-01 challenge (advanced)
# Requires DNS API access - see certbot documentation
```

---

### Issue 4: Certificate Not Loading

**Symptom**: Xray fails to start, logs show "certificate not found"

**Diagnosis**:
```bash
sudo docker logs vless-reality 2>&1 | grep -i cert
# Shows: "failed to load certificate"
```

**Solution**:
```bash
# Verify certificate files
ls -la /etc/letsencrypt/live/$DOMAIN/

# Check docker volume mount
grep "letsencrypt" /opt/vless/docker-compose.yml
# Should show: - /etc/letsencrypt:/etc/xray/certs:ro

# Restart containers
cd /opt/vless
sudo docker-compose restart
```

---

### Issue 5: TLS Handshake Failure

**Symptom**: Clients cannot connect, "TLS handshake failed"

**Diagnosis**:
```bash
openssl s_client -connect vpn.example.com:1080 -servername vpn.example.com
# Shows error
```

**Possible Causes**:
1. Certificate expired (check expiry date)
2. Domain mismatch (cert issued for different domain)
3. Client doesn't support TLS 1.3
4. Firewall blocking TLS handshake

**Solution**:
```bash
# Renew certificate if expired
sudo certbot renew --force-renewal

# Verify domain matches
sudo openssl x509 -in /etc/letsencrypt/live/$DOMAIN/cert.pem -noout -text | grep "Subject:"

# Check Xray logs
sudo docker logs vless-reality | tail -50
```

---

### Issue 6: Auto-Renewal Not Working

**Symptom**: Certificate expired, no auto-renewal occurred

**Diagnosis**:
```bash
# Check cron job
cat /etc/cron.d/certbot-vless-renew

# Check renewal logs
cat /opt/vless/logs/certbot-renew.log

# Test renewal manually
sudo certbot renew --dry-run
```

**Solution**:
```bash
# Manually renew
sudo certbot renew --force-renewal

# Verify cron job syntax
sudo crontab -l | grep certbot

# Ensure deploy hook is executable
ls -la /usr/local/bin/vless-cert-renew
sudo chmod 755 /usr/local/bin/vless-cert-renew
```

---

## Post-Migration Monitoring

### Week 1 Checklist

- [ ] All users successfully migrated to v3.3 configs
- [ ] No TLS handshake errors in logs
- [ ] Certificate expiry monitored (90 days initial validity)
- [ ] Auto-renewal cron job verified (runs twice daily)
- [ ] fail2ban logs checked for brute-force attempts
- [ ] Performance benchmarks within targets (<2ms latency overhead)

---

### Week 4 Checklist (Before First Auto-Renewal)

- [ ] Test dry-run renewal: `sudo certbot renew --dry-run`
- [ ] Verify email notifications working
- [ ] Check deploy hook executes correctly
- [ ] Monitor Xray restart after renewal (downtime <5s)

---

### Day 60 Checklist (First Actual Renewal)

- [ ] Certificate renewed automatically
- [ ] Xray restarted successfully
- [ ] No user-reported connection issues
- [ ] New certificate expiry +90 days

---

## FAQ

### Q1: Can I upgrade from v3.1 directly to v3.3?

**A**: No. You must upgrade v3.1 → v3.2 → v3.3 due to database schema changes in v3.2.

---

### Q2: Do I need a domain for VLESS-only mode?

**A**: No. Domain is only required if enabling Public Proxy Mode. VLESS-only mode works with IP addresses.

---

### Q3: Can I use a wildcard certificate?

**A**: Yes, but requires DNS-01 challenge (not HTTP-01). See Certbot documentation for DNS API setup.

---

### Q4: What happens if my domain expires?

**A**: TLS handshake will fail → users cannot connect. Renew domain BEFORE expiry. Certificate auto-renewal will also fail without valid domain.

---

### Q5: Can I use a custom CA instead of Let's Encrypt?

**A**: Yes, but requires manual certificate installation. Place certificates in `/etc/letsencrypt/live/$DOMAIN/` with filenames `fullchain.pem` and `privkey.pem`.

---

### Q6: How do I monitor certificate expiry?

**A**: Use monitoring tools or check manually:
```bash
sudo openssl x509 -in /etc/letsencrypt/live/$DOMAIN/cert.pem -noout -enddate
```

Set up email alerts or integrate with monitoring systems (Prometheus, Zabbix, etc.).

---

## Summary

v3.3 is a **critical security update** that addresses plaintext credential transmission in v3.2 Public Proxy Mode. Migration requires:

1. Domain name with DNS A record
2. Let's Encrypt certificate acquisition
3. Client config regeneration
4. User notification and reconfiguration

**Estimated Downtime**: 10-15 minutes
**Estimated Effort**: 30-60 minutes (admin time)
**User Impact**: 100% client reconfig required

**Security Improvement**: Plaintext credentials → TLS 1.3 encrypted

For assistance: GitHub Issues or project documentation.

---

**Document End**
