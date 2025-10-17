# VLESS v4.2 - Certificate Auto-Renewal Guide

**Version:** 4.2.0
**Last Updated:** 2025-10-17
**Status:** Production Ready

---

## 🎯 Overview

VLESS v4.2 includes **comprehensive automatic certificate renewal** for both VLESS Reality and Reverse Proxy certificates.

### What's Automated

✅ **Certificate Monitoring** - Daily checks for expiring certificates
✅ **Auto-Renewal** - Certificates < 30 days automatically renewed
✅ **Service Reload** - Xray + Nginx reloaded after renewal
✅ **Database Updates** - reverse_proxies.json updated with new expiry dates
✅ **Email Alerts** - Critical certificate warnings (optional)

---

## 📋 Table of Contents

1. [Architecture](#architecture)
2. [Setup Guide](#setup-guide)
3. [Cron Jobs](#cron-jobs)
4. [Manual Operations](#manual-operations)
5. [Monitoring](#monitoring)
6. [Troubleshooting](#troubleshooting)

---

## Architecture

### Certificate Renewal Flow

```
Certbot Timer/Cron
  ↓
certbot renew
  ↓
Deploy Hook: /opt/vless/lib/letsencrypt_deploy_hook.sh
  ↓
Delegates to: /usr/local/bin/vless-cert-renew
  ↓
┌─────────────────────────────────────────────────┐
│ Step 1: Restart Xray (VLESS Reality)           │
│ Step 2: Reload Nginx (Reverse Proxy)           │
│ Step 3: Update Database (reverse_proxies.json) │
└─────────────────────────────────────────────────┘
  ↓
Logs: /opt/vless/logs/certbot-renew.log
```

### Components

| Component | Purpose | Location |
|-----------|---------|----------|
| **certbot** | Certificate acquisition & renewal | System service |
| **deploy hook** | Triggers post-renewal actions | `/opt/vless/lib/letsencrypt_deploy_hook.sh` |
| **vless-cert-renew** | Unified renewal handler | `/usr/local/bin/vless-cert-renew` |
| **cert_renewal_monitor** | Proactive monitoring | `/opt/vless/lib/cert_renewal_monitor.sh` |
| **reverse_proxies.json** | Certificate metadata | `/opt/vless/config/reverse_proxies.json` |

---

## Setup Guide

### 1. Verify certbot Installation

```bash
# Check certbot
certbot --version

# Should show systemd timer (Ubuntu/Debian default)
systemctl status certbot.timer
```

**Output:**
```
● certbot.timer - Run certbot twice daily
     Loaded: loaded (/lib/systemd/system/certbot.timer; enabled)
     Active: active (waiting)
```

### 2. Configure Deploy Hook

**This is done automatically during reverse proxy setup**, but you can verify:

```bash
# Check deploy hook exists
ls -l /opt/vless/lib/letsencrypt_deploy_hook.sh

# Check it's executable
test -x /opt/vless/lib/letsencrypt_deploy_hook.sh && echo "OK"

# Check vless-cert-renew
ls -l /usr/local/bin/vless-cert-renew
```

### 3. Test Deploy Hook

```bash
# Simulate certbot environment
export RENEWED_DOMAINS="proxy.example.com"

# Run deploy hook
sudo /opt/vless/lib/letsencrypt_deploy_hook.sh

# Check logs
sudo tail -f /var/log/letsencrypt/deploy-hook.log
```

**Expected output:**
```
[2025-10-17 12:00:00] [deploy-hook] Certificate renewed for: proxy.example.com
[2025-10-17 12:00:00] [deploy-hook] Delegating to vless-cert-renew...
[2025-10-17 12:00:01] [cert-renew] ✅ Xray restarted successfully
[2025-10-17 12:00:02] [cert-renew] ✅ Nginx reverse proxy reloaded successfully
[2025-10-17 12:00:03] [cert-renew] ✅ Database updated for proxy.example.com
[2025-10-17 12:00:04] [deploy-hook] ✅ Deploy hook completed successfully
```

### 4. Setup Monitoring Cron Jobs

```bash
# Setup automatic monitoring
sudo /opt/vless/lib/cert_renewal_monitor.sh --setup-cron
```

**This configures:**
- **Daily check (2 AM)**: Auto-renew certificates < 30 days
- **Weekly report (Mon 9 AM)**: Email status report

**Verify cron jobs:**
```bash
sudo crontab -l | grep cert_renewal_monitor
```

**Output:**
```
# VLESS v4.2 - Certificate Renewal Monitoring
# Daily auto-renewal check (2 AM)
0 2 * * * /opt/vless/lib/cert_renewal_monitor.sh --auto-renew >> /var/log/vless/cert_cron.log 2>&1

# Weekly status report (Monday 9 AM)
0 9 * * 1 /opt/vless/lib/cert_renewal_monitor.sh --report >> /var/log/vless/cert_cron.log 2>&1
```

### 5. Configure Email Alerts (Optional)

```bash
# Install mail utility
sudo apt-get install mailutils

# Configure email alerts
export EMAIL_ALERTS=true
export EMAIL_TO=admin@example.com

# Test email
echo "Test email from VLESS cert monitor" | mail -s "Test" admin@example.com
```

**Add to cron environment:**
```bash
sudo crontab -e

# Add at top:
EMAIL_ALERTS=true
EMAIL_TO=admin@example.com

# Existing cron jobs below...
```

---

## Cron Jobs

### Certbot System Timer

**Default Ubuntu/Debian setup:**
```bash
# Check timer
systemctl status certbot.timer

# View timer details
systemctl list-timers certbot.timer
```

**Runs twice daily:**
- 12:00 AM
- 12:00 PM

### Manual Cron (Backup)

If systemd timer fails, add manual cron:

```bash
sudo crontab -e

# Add:
0 0,12 * * * certbot renew --quiet --deploy-hook '/opt/vless/lib/letsencrypt_deploy_hook.sh' >> /var/log/letsencrypt/letsencrypt.log 2>&1
```

### Monitoring Cron

**Configured via `--setup-cron`:**

```bash
# Daily auto-renewal (2 AM)
0 2 * * * /opt/vless/lib/cert_renewal_monitor.sh --auto-renew

# Weekly report (Monday 9 AM)
0 9 * * 1 /opt/vless/lib/cert_renewal_monitor.sh --report
```

---

## Manual Operations

### Check All Certificates

```bash
# Via vless-proxy CLI
sudo vless-proxy check-certs

# Via monitoring script
sudo /opt/vless/lib/cert_renewal_monitor.sh --check
```

**Output:**
```
ДОМЕН                    ИСТЕКАЕТ                  DAYS LEFT    STATUS
─────────────────────────────────────────────────────────────────────
proxy.example.com        2026-01-15T12:00:00Z      85           OK
news.example.com         2025-11-20T10:30:00Z      25           RENEW_SOON
social.example.com       2025-10-22T08:15:00Z      5            CRITICAL
```

### Manual Renewal

```bash
# Single domain
sudo vless-proxy renew-cert proxy.example.com

# All domains
sudo certbot renew --force-renewal

# With deploy hook
sudo certbot renew --force-renewal --deploy-hook '/opt/vless/lib/letsencrypt_deploy_hook.sh'
```

### Generate Status Report

```bash
# Detailed report
sudo /opt/vless/lib/cert_renewal_monitor.sh --report

# Saves to: /tmp/cert_status_report_YYYYMMDD.txt
```

### Auto-Renew Expiring Certificates

```bash
# Check and auto-renew certificates < 30 days
sudo /opt/vless/lib/cert_renewal_monitor.sh --auto-renew
```

---

## Monitoring

### Log Files

```bash
# Deploy hook log
sudo tail -f /var/log/letsencrypt/deploy-hook.log

# Main renewal log
sudo tail -f /opt/vless/logs/certbot-renew.log

# Certbot log
sudo tail -f /var/log/letsencrypt/letsencrypt.log

# Monitoring cron log
sudo tail -f /var/log/vless/cert_cron.log
```

### Database Check

```bash
# View certificate expiry dates in database
sudo cat /opt/vless/config/reverse_proxies.json | jq '.proxies[] | {domain, certificate_expires, last_renewed}'
```

**Output:**
```json
{
  "domain": "proxy.example.com",
  "certificate_expires": "2026-01-15T12:00:00Z",
  "last_renewed": "2025-10-17T12:00:00Z"
}
```

### Real-Time Monitoring

```bash
# Watch certificate status (updates every 2s)
watch -n 2 'sudo vless-proxy check-certs'
```

---

## Troubleshooting

### Issue 1: Deploy Hook Not Called

**Symptoms:**
- Certificate renewed but services not reloaded
- Database not updated

**Check:**
```bash
# Verify deploy hook configured
sudo certbot certificates | grep "deploy"

# Check hook exists and executable
ls -l /opt/vless/lib/letsencrypt_deploy_hook.sh
```

**Fix:**
```bash
# Recreate deploy hook
sudo /opt/vless/lib/letsencrypt_integration.sh create-deploy-hook

# Test manually
export RENEWED_DOMAINS="proxy.example.com"
sudo /opt/vless/lib/letsencrypt_deploy_hook.sh
```

### Issue 2: Nginx Reload Fails

**Symptoms:**
```
❌ Failed to reload nginx reverse proxy
```

**Check:**
```bash
# Container running?
docker ps | grep vless_nginx_reverseproxy

# Nginx config valid?
docker exec vless_nginx_reverseproxy nginx -t
```

**Fix:**
```bash
# Restart container
docker-compose -f /opt/vless/docker-compose.yml restart nginx

# Check logs
docker logs vless_nginx_reverseproxy
```

### Issue 3: Database Update Fails

**Symptoms:**
```
⚠️  Failed to update database for proxy.example.com
```

**Check:**
```bash
# Database exists?
ls -l /opt/vless/config/reverse_proxies.json

# Valid JSON?
jq . /opt/vless/config/reverse_proxies.json

# Domain exists?
sudo /opt/vless/lib/reverseproxy_db.sh get proxy.example.com
```

**Fix:**
```bash
# Manual database update
sudo /opt/vless/lib/reverseproxy_db.sh update-cert proxy.example.com \
  "$(date -u -d '+90 days' +'%Y-%m-%dT%H:%M:%SZ')" \
  "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
```

### Issue 4: Certbot Renewal Fails

**Symptoms:**
```
❌ Failed to obtain certificate
```

**Common causes:**
1. Port 80 blocked
2. DNS not pointing to server
3. Rate limit exceeded

**Check:**
```bash
# Port 80 open?
sudo ufw status | grep 80

# DNS correct?
dig +short proxy.example.com

# Rate limit?
sudo grep "rate limit" /var/log/letsencrypt/letsencrypt.log
```

**Fix:**
```bash
# Open port 80 temporarily
sudo ufw allow 80/tcp

# Wait for DNS propagation (up to 24h)

# Rate limit: wait 1 hour or use staging
certbot renew --cert-name proxy.example.com --staging
```

---

## Best Practices

### 1. Regular Testing

```bash
# Weekly: Test renewal flow
sudo certbot renew --dry-run

# Monthly: Full status report
sudo /opt/vless/lib/cert_renewal_monitor.sh --report
```

### 2. Monitor Logs

```bash
# Setup log rotation
sudo tee /etc/logrotate.d/vless-certbot <<EOF
/var/log/letsencrypt/*.log
/opt/vless/logs/certbot-renew.log
{
    weekly
    rotate 4
    compress
    missingok
    notifempty
}
EOF
```

### 3. Backup Database

```bash
# Before major operations
sudo cp /opt/vless/config/reverse_proxies.json \
       /opt/vless/data/backups/reverse_proxies_$(date +%Y%m%d).json
```

### 4. Alert Thresholds

- **OK**: > 30 days - No action
- **WARNING**: 14-30 days - Monitor
- **CRITICAL**: < 14 days - Manual check
- **EXPIRED**: < 0 days - Immediate action

---

## Summary

✅ **Automatic Certificate Renewal Configured**

- **certbot**: Renews certificates automatically (systemd timer)
- **Deploy Hook**: Reloads services after renewal
- **vless-cert-renew**: Handles Xray + Nginx + Database
- **cert_renewal_monitor**: Proactive monitoring + auto-renew
- **Cron Jobs**: Daily checks + weekly reports

**Next Steps:**
1. ✅ Verify all components working
2. ✅ Test with `--dry-run`
3. ✅ Setup email alerts (optional)
4. ✅ Monitor logs for first renewal

**Support:**
- Logs: `/var/log/letsencrypt/` + `/opt/vless/logs/`
- Database: `/opt/vless/config/reverse_proxies.json`
- CLI: `sudo vless-proxy check-certs`

---

**Version:** 4.2.0 | **Status:** Production Ready | **Author:** VLESS Development Team
