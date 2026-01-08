# Playbook: Certificate Renewal Failed

**Issue ID:** `cert_renewal_failed`
**Category:** Certificates
**Severity:** HIGH

---

## Symptoms

- Certbot cron job failing
- Certificate expired warnings in browser
- `/var/log/letsencrypt/letsencrypt.log` shows errors
- HTTPS connections fail with certificate errors

---

## Diagnostic Commands

### 1. Test Certificate Renewal (Dry Run)

```bash
sudo certbot renew --dry-run
```

**Expected:** "Congratulations, all simulated renewals succeeded"
**Common errors:** Port 80 blocked, DNS validation failed

### 2. Check Certbot Logs

```bash
sudo tail -50 /var/log/letsencrypt/letsencrypt.log | grep -i 'error\|fail'
```

**Look for:**
- Connection refused on port 80
- DNS lookup failed
- Rate limit exceeded
- Authorization failed

### 3. Check Certificate Expiration

```bash
DOMAIN="your-domain.com"  # Replace with actual domain
sudo openssl x509 -in /etc/letsencrypt/live/$DOMAIN/cert.pem -noout -dates
```

**Shows:** notBefore and notAfter dates
**Alert if:** notAfter < 30 days

### 4. Verify DNS Points to Server

```bash
dig +short your-domain.com
curl -4 ifconfig.me
```

**Expected:** Both commands return the same IP
**Common error:** DNS changed, points to different IP

### 5. Check Port 80 Accessibility

```bash
sudo ss -tulnp | grep :80
curl http://your-domain.com/.well-known/acme-challenge/test
```

**Expected:** Port 80 open and certbot_nginx responding

---

## Common Causes & Fixes

### Cause 1: Port 80 Blocked

**Explanation:**
Let's Encrypt HTTP-01 challenge requires port 80 to be publicly accessible. If UFW or cloud firewall blocks it, validation fails.

**Fix:**

```bash
# 1. Allow port 80 in UFW
sudo ufw allow 80/tcp

# 2. Reload UFW
sudo ufw reload

# 3. Verify port 80 accessible
sudo ss -tulnp | grep :80

# Expected: vless_certbot_nginx listening on port 80

# 4. Test from external
curl -I http://your-domain.com

# Expected: HTTP 200 or 404 (not connection refused)

# 5. Retry renewal
sudo certbot renew --dry-run
```

**Cloud firewall (if applicable):**
- AWS Security Groups: Allow inbound TCP 80
- GCP Firewall Rules: Allow tcp:80
- Digital Ocean: Add firewall rule for port 80

---

### Cause 2: DNS Changed - Domain No Longer Points to Server

**Explanation:**
DNS A record must point to server's public IP. If DNS changed, Let's Encrypt can't reach the server for validation.

**Diagnostic:**

```bash
# Get domain IP
dig +short your-domain.com

# Get server IP
curl -4 ifconfig.me

# Compare - should match
```

**Fix:**

```bash
# Update DNS A record to point to server IP
# (requires access to domain registrar or DNS provider)

# After DNS update, wait for propagation (up to 48 hours)
# Check propagation:
dig +short your-domain.com @8.8.8.8  # Google DNS
dig +short your-domain.com @1.1.1.1  # Cloudflare DNS
```

**Temporary workaround (if DNS can't be fixed immediately):**

```bash
# Use DNS-01 challenge instead of HTTP-01
# (requires DNS provider API support)
sudo certbot certonly --manual --preferred-challenges dns -d your-domain.com
```

---

### Cause 3: Certbot Rate Limit Exceeded

**Explanation:**
Let's Encrypt enforces rate limits: 50 certificates per registered domain per week, 5 failed validation attempts per hour.

**Diagnostic:**

```bash
# Check certbot logs for rate limit errors
sudo grep -i 'rate limit' /var/log/letsencrypt/letsencrypt.log
```

**Fix:**

```bash
# Wait for rate limit to reset:
# - Failed validations: 1 hour
# - Certificate issuance: 1 week

# Alternative: Use staging environment for testing
sudo certbot renew --dry-run --staging

# Once ready, get real certificate
sudo certbot renew --force-renewal
```

---

### Cause 4: Certbot_nginx Container Not Running

**Explanation:**
`vless_certbot_nginx` container must be running during HTTP-01 challenge to serve ACME challenge files.

**Diagnostic:**

```bash
docker ps | grep vless_certbot_nginx
```

**Fix:**

```bash
# Start certbot_nginx container
docker start vless_certbot_nginx

# Verify running
docker ps | grep vless_certbot_nginx

# Test port 80 response
curl -I http://your-domain.com

# Retry renewal
sudo certbot renew --dry-run
```

---

## Prevention

1. **Monitor certbot cron job:**
   ```bash
   grep CRON /var/log/syslog | grep certbot
   ```

2. **Set up alerting** for certificate expiration (< 30 days):
   ```bash
   # Add to crontab
   0 0 * * * /path/to/check-cert-expiry.sh
   ```

3. **Keep DNS records stable** - avoid changing IP frequently

4. **Test renewals monthly:**
   ```bash
   sudo certbot renew --dry-run
   ```

5. **Ensure port 80 always open** for HTTP-01 challenge

---

## Related Issues

- **port_conflict** - If port 80 occupied by another service
- **container_unhealthy** - If certbot_nginx container failing
