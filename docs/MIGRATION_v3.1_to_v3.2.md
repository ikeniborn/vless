# Migration Guide: VLESS Reality VPN v3.1 → v3.2

**Document Version**: 1.0
**Date**: 2025-10-04
**Target Audience**: System administrators upgrading from v3.1

---

## Overview

Version 3.2 introduces **Public Proxy Mode**, allowing SOCKS5 and HTTP proxies to be accessible from the public internet without requiring a VPN connection. This is a **significant architectural change** from v3.1's localhost-only proxy binding.

### Key Changes

| Feature | v3.1 | v3.2 |
|---------|------|------|
| **Proxy Binding** | `127.0.0.1` (localhost only) | `0.0.0.0` (public internet) |
| **Password Length** | 16 characters | 32 characters |
| **Fail2ban** | Not included | Auto-configured (5 retries → 1h ban) |
| **UFW Rate Limiting** | Not configured | 10 connections/min per IP |
| **Docker Healthchecks** | Not configured | Every 30s with auto-restart |
| **Config Files** | Use `127.0.0.1` | Use `SERVER_IP` (external IP) |
| **Installation Mode** | Single mode | Dual mode (VLESS-only or Public Proxy) |

---

## Breaking Changes

### 1. Proxy Configuration Format

**Impact**: All proxy configuration files now use the server's external IP instead of `127.0.0.1`.

**Before (v3.1)**:
```
socks5://username:password@127.0.0.1:1080
http://username:password@127.0.0.1:8118
```

**After (v3.2)**:
```
socks5://username:password@203.0.113.45:1080
http://username:password@203.0.113.45:8118
```

**Action Required**: Regenerate all client configurations for existing users.

### 2. Password Length Increase

**Impact**: New users receive 32-character passwords (vs 16 in v3.1). Existing users keep their 16-character passwords until reset.

**Before (v3.1)**:
```
proxy_password: a1b2c3d4e5f67890
```

**After (v3.2)**:
```
proxy_password: a1b2c3d4e5f67890a1b2c3d4e5f67890
```

**Action Required**: Optional - reset existing user passwords for enhanced security:
```bash
vless reset-proxy-password <username>
```

### 3. New Dependencies

**Impact**: v3.2 requires additional packages if Public Proxy Mode is enabled.

**New Dependencies**:
- `fail2ban` (brute-force protection)
- `netcat-openbsd` (Docker healthchecks)

**Action Required**: Installer handles this automatically. Manual installation not required.

---

## Migration Paths

### Path A: Upgrade Without Enabling Public Proxy (Recommended for Most Users)

This path maintains v3.1 behavior (VLESS-only mode) while benefiting from v3.2 improvements.

**Advantages**:
- No security exposure changes
- Faster migration
- No client reconfigurations needed

**Steps**:

1. **Backup Current Installation**
   ```bash
   sudo cp -r /opt/vless /opt/vless.v3.1.backup.$(date +%Y%m%d_%H%M%S)
   ```

2. **Pull v3.2 Code**
   ```bash
   cd /path/to/vless-reality-vpn
   git pull origin master  # Assumes v3.2 is on master branch
   ```

3. **Run Installer**
   ```bash
   sudo ./install.sh
   ```

4. **During Installation**
   - Old installation will be detected
   - Choose option 2 (Update: preserve users/keys)
   - When prompted "Enable public proxy access? [y/N]", choose **N**

5. **Verify Services**
   ```bash
   docker ps | grep vless
   vless status
   ```

**Result**: System upgraded to v3.2 codebase but proxy behavior identical to v3.1 (localhost-only).

---

### Path B: Upgrade WITH Public Proxy Mode (Advanced Users)

This path enables internet-accessible proxies with full security hardening.

⚠️ **WARNING**: This exposes ports 1080 and 8118 to the internet. Review [README.md Security Warnings](README.md#security-warnings-v32-public-proxy-mode) first.

**Steps**:

1. **Backup Current Installation**
   ```bash
   sudo cp -r /opt/vless /opt/vless.v3.1.backup.$(date +%Y%m%d_%H%M%S)
   ```

2. **Pull v3.2 Code**
   ```bash
   cd /path/to/vless-reality-vpn
   git pull origin master
   ```

3. **Run Installer**
   ```bash
   sudo ./install.sh
   ```

4. **During Installation**
   - Old installation will be detected
   - Choose option 2 (Update: preserve users/keys)
   - When prompted "Enable public proxy access? [y/N]", choose **y**
   - Confirm public proxy warning (second prompt)

5. **Post-Installation Security Verification**
   ```bash
   # Verify fail2ban jails are active
   sudo fail2ban-client status vless-socks5
   sudo fail2ban-client status vless-http

   # Verify UFW rules
   sudo ufw status numbered | grep -E "1080|8118"

   # Verify healthchecks
   docker inspect vless-reality --format='{{.State.Health.Status}}'
   ```

6. **Regenerate Client Configurations**

   **Important**: v3.1 configs use `127.0.0.1`. You MUST regenerate configs for v3.2 public access.

   ```bash
   # List all users
   vless list-users

   # For each user, regenerate configs
   vless show-proxy alice    # Displays new credentials
   ```

7. **Distribute New Configurations**

   Send updated configuration files to users:
   ```bash
   # Configuration files location
   ls -la /opt/vless/data/clients/<username>/

   # Files to send:
   # - socks5_config.txt      (new URI with external IP)
   # - http_config.txt        (new URI with external IP)
   # - vscode_settings.json   (updated proxy settings)
   # - docker_daemon.json     (updated proxy settings)
   # - bash_exports.sh        (updated proxy exports)
   ```

8. **Optional: Reset User Passwords for Enhanced Security**
   ```bash
   # Upgrade from 16-char to 32-char passwords
   for user in $(vless list-users | grep "^- " | awk '{print $2}'); do
       echo "Resetting password for $user..."
       vless reset-proxy-password "$user"
   done
   ```

---

## Rollback Procedure

If you encounter issues with v3.2, you can rollback to v3.1 backup.

### Quick Rollback

```bash
# Stop v3.2 services
cd /opt/vless
docker compose down

# Restore v3.1 backup
sudo rm -rf /opt/vless
sudo mv /opt/vless.v3.1.backup.YYYYMMDD_HHMMSS /opt/vless

# Start services
cd /opt/vless
docker compose up -d

# Verify
vless status
```

### Clean Reinstall (if rollback fails)

```bash
# Complete removal
sudo /opt/vless/scripts/uninstall.sh

# Reinstall from v3.1 branch (if available)
cd /path/to/vless-reality-vpn
git checkout v3.1  # Assumes v3.1 tagged branch exists
sudo ./install.sh
```

---

## Testing Checklist

After migration, verify the following:

### Basic Functionality
- [ ] All containers running (`docker ps | grep vless`)
- [ ] Service commands work (`vless status`, `vless logs`)
- [ ] User list matches pre-migration (`vless list-users`)

### v3.2 Features (if Public Proxy enabled)
- [ ] Fail2ban jails active (`sudo fail2ban-client status vless-socks5`)
- [ ] UFW rules present (`sudo ufw status | grep -E "1080|8118"`)
- [ ] Healthcheck passing (`docker inspect vless-reality --format='{{.State.Health.Status}}'`)
- [ ] External IP detection (`grep SERVER_IP /opt/vless/.env`)

### Client Connectivity
- [ ] VLESS connection works (test with existing client)
- [ ] SOCKS5 proxy accessible (`curl --socks5 user:pass@SERVER_IP:1080 https://ifconfig.me`)
- [ ] HTTP proxy accessible (`curl --proxy http://user:pass@SERVER_IP:8118 https://ifconfig.me`)

### Security Validation
- [ ] Run integration tests: `sudo /path/to/vless/tests/integration/test_public_proxy.sh`
- [ ] Run security tests: `sudo /path/to/vless/tests/integration/test_security.sh`

---

## Troubleshooting

### Issue 1: "SERVER_IP_NOT_DETECTED" in .env file

**Symptom**: Config files contain `SERVER_IP_NOT_DETECTED` instead of actual IP.

**Cause**: Server cannot reach external IP detection services.

**Solution**:
```bash
# Manually set SERVER_IP in .env file
sudo nano /opt/vless/.env

# Replace:
SERVER_IP=SERVER_IP_NOT_DETECTED

# With your actual server IP:
SERVER_IP=203.0.113.45

# Regenerate configs
for user in $(vless list-users | grep "^- " | awk '{print $2}'); do
    vless show-proxy "$user"
done
```

### Issue 2: Fail2ban Not Banning IPs

**Symptom**: Failed authentication attempts don't trigger bans.

**Diagnosis**:
```bash
# Check fail2ban is running
sudo systemctl status fail2ban

# Check jail status
sudo fail2ban-client status vless-socks5

# Check logs
sudo tail -f /var/log/fail2ban.log
```

**Solution**:
```bash
# Restart fail2ban
sudo systemctl restart fail2ban

# Verify filter and jail files exist
ls -la /etc/fail2ban/filter.d/vless-proxy.conf
ls -la /etc/fail2ban/jail.d/vless-proxy.conf
```

### Issue 3: Proxy Connections Rejected Immediately

**Symptom**: Proxy connections fail even with correct credentials.

**Diagnosis**:
```bash
# Check UFW isn't blocking
sudo ufw status numbered

# Check if ports are open
sudo ss -tulnp | grep -E "1080|8118"

# Check Xray logs
docker logs vless-reality --tail 50
```

**Solution**:
```bash
# Ensure UFW rules exist
sudo ufw limit 1080/tcp comment 'VLESS SOCKS5'
sudo ufw limit 8118/tcp comment 'VLESS HTTP'
sudo ufw reload

# Restart containers
cd /opt/vless
docker compose restart
```

---

## FAQ

**Q1: Can I run v3.2 in VLESS-only mode permanently?**
Yes. Choose 'N' during installation. v3.2 will behave identically to v3.1 (no public proxy exposure).

**Q2: Do I need to update all client devices after migration?**
- **Path A (VLESS-only)**: No, existing clients continue working.
- **Path B (Public Proxy)**: Yes, proxy configs must be updated with new URIs.

**Q3: What happens to existing user passwords?**
They remain unchanged (16 characters). New users get 32-character passwords. Optional: reset existing passwords for uniformity.

**Q4: Can I switch from VLESS-only to Public Proxy mode later?**
Yes, but requires reinstallation. Backup current setup, run installer, choose 'y' for public proxy.

**Q5: How do I monitor for brute-force attacks?**
```bash
# Real-time fail2ban bans
sudo tail -f /var/log/fail2ban.log

# Check currently banned IPs
sudo fail2ban-client status vless-socks5

# Review Xray authentication failures
vless logs | grep "authentication failed"
```

**Q6: Does v3.2 support IPv6?**
Not currently. SERVER_IP detection uses IPv4 only.

---

## Support

- **Issue Tracker**: [GitHub Issues](https://github.com/your-username/vless-reality-vpn/issues)
- **Documentation**: [README.md](README.md)
- **Security Concerns**: Open a security advisory (not a public issue)

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-10-04 | Initial migration guide (v3.1 → v3.2) |
