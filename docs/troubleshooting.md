# Troubleshooting Guide

Comprehensive troubleshooting guide for the VLESS+Reality VPN Management System.

## Table of Contents

1. [General Troubleshooting](#general-troubleshooting)
2. [Installation Issues](#installation-issues)
   - [System Time Synchronization Errors](#system-time-synchronization-errors)
   - [Enhanced Time Synchronization (v1.2.3)](#enhanced-time-synchronization-v123)
3. [Service Problems](#service-problems)
4. [Connection Issues](#connection-issues)
5. [User Management Problems](#user-management-problems)
6. [Performance Issues](#performance-issues)
7. [Security Concerns](#security-concerns)
8. [Configuration Problems](#configuration-problems)
9. [System Recovery](#system-recovery)
10. [Log Analysis](#log-analysis)
11. [Getting Help](#getting-help)

## General Troubleshooting

### First Steps

Before diving into specific issues, always start with these basic troubleshooting steps:

1. **Check System Status**
   ```bash
   sudo systemctl status xray
   sudo systemctl status docker
   sudo docker ps
   ```

2. **Verify Log Files**
   ```bash
   sudo journalctl -u xray -f
   sudo journalctl -u docker -f
   tail -f /opt/vless/logs/*.log
   ```

3. **Test Network Connectivity**
   ```bash
   ping 8.8.8.8
   curl -I https://www.google.com
   netstat -tlnp | grep :443
   ```

4. **Check Disk Space**
   ```bash
   df -h
   du -sh /opt/vless/*
   ```

5. **Verify Permissions**
   ```bash
   ls -la /opt/vless/
   sudo find /opt/vless -type f -not -perm -644
   ```

## Installation Issues

### System Time Synchronization Errors

**Problem**: APT repository updates fail with errors like:
```
E: Release file for http://security.ubuntu.com/ubuntu/dists/noble-security/InRelease is not valid yet (invalid for another 1h 13min 37s)
```

**Cause**: System time is incorrect or out of sync with actual time, causing APT to reject repository files.

**Solution**: The system now includes automatic time synchronization. If you encounter this issue:

1. **Automatic Fix** (built-in):
   - The installation script automatically detects and fixes time issues
   - Time is synced using NTP before APT operations

2. **Manual Fix**:
   ```bash
   # Check current system time
   date

   # Sync time manually
   sudo timedatectl set-ntp true
   sudo systemctl restart systemd-timesyncd

   # Or use ntpdate
   sudo apt-get install ntpdate
   sudo ntpdate pool.ntp.org

   # Verify time is correct
   date
   ```

3. **Disable Time Check** (not recommended):
   ```bash
   export TIME_SYNC_ENABLED=false
   sudo ./install.sh
   ```

4. **Set Custom Tolerance**:
   ```bash
   # Allow 10 minutes of time drift
   export TIME_TOLERANCE_SECONDS=600
   sudo ./install.sh
   ```

**Prevention**: Enable automatic time synchronization:
```bash
sudo timedatectl set-ntp true
sudo timedatectl set-timezone UTC
```

### Enhanced Time Synchronization (v1.2.3)

**Overview**: The system now includes an advanced time synchronization engine with comprehensive service management and multiple fallback layers.

#### Using the Enhanced Time Sync Function

The new `enhanced_time_sync()` function provides robust time synchronization with automatic service management:

```bash
# Direct function call (from common_utils.sh)
enhanced_time_sync

# Through APT operations (automatic)
safe_apt_update  # Automatically calls enhanced_time_sync if needed

# Manual time sync with specific service
TIME_SERVICE_PREFERENCE="chrony" enhanced_time_sync
```

#### Common Time Sync Issues and Solutions

1. **Large Time Offset (>45 minutes)**

   **Problem**: System time severely out of sync, causing APT and SSL certificate errors.

   **Automatic Solution**: The enhanced time sync automatically handles large offsets:
   ```bash
   # The system automatically:
   # 1. Detects large time drift
   # 2. Configures chrony for aggressive correction (makestep 1000 -1)
   # 3. Restarts time services safely
   # 4. Falls back to web APIs if NTP fails
   # 5. Validates time actually changed
   ```

   **Manual Solution**:
   ```bash
   # Force immediate time sync for large offsets
   sudo chrony sources -v
   sudo chronyc makestep

   # Or use web API fallback
   curl -s "http://worldtimeapi.org/api/timezone/Etc/UTC" | grep -o '"unixtime":[0-9]*' | cut -d: -f2 | xargs -I {} sudo date -s "@{}"
   ```

2. **Time Service Not Running**

   **Problem**: No time synchronization services available.

   **Detection**:
   ```bash
   # Check which services are available
   systemctl status systemd-timesyncd
   systemctl status chronyd
   systemctl status ntp
   ```

   **Solution**: The system automatically detects and starts available services:
   ```bash
   # Automatic service detection and restart
   enhanced_time_sync

   # Manual service management
   sudo systemctl enable --now systemd-timesyncd
   # Or for chrony
   sudo systemctl enable --now chronyd
   ```

3. **Network Time Sources Unreachable**

   **Problem**: NTP servers not accessible due to firewall or network issues.

   **Automatic Fallback**: System uses web APIs as fallback:
   ```bash
   # Primary: worldtimeapi.org
   # Secondary: worldclockapi.com
   # Tertiary: timeapi.io
   # Last resort: Manual date setting
   ```

   **Manual Configuration**:
   ```bash
   # Configure custom NTP servers
   export TIME_SYNC_SERVERS="pool.ntp.org time.google.com time.cloudflare.com"
   enhanced_time_sync

   # Or use specific regional servers
   export TIME_SYNC_SERVERS="us.pool.ntp.org europe.pool.ntp.org"
   ```

4. **Chrony Configuration Issues**

   **Problem**: Chrony not configured for large offset corrections.

   **Automatic Fix**: System validates and repairs chrony configuration:
   ```bash
   # The system automatically adds to /etc/chrony/chrony.conf:
   # makestep 1000 -1  # Allow large time steps
   # logchange 0.1      # Log time changes
   ```

   **Manual Fix**:
   ```bash
   # Check chrony configuration
   sudo chronyc tracking
   sudo chronyc sources -v

   # Add large offset support
   echo "makestep 1000 -1" | sudo tee -a /etc/chrony/chrony.conf
   sudo systemctl restart chronyd
   ```

#### APT Repository Time-Related Errors

**Common Error Messages**:
```
E: Release file for http://archive.ubuntu.com/ubuntu/dists/noble/InRelease is not valid yet (invalid for another 2h 15min 30s)
W: GPG error: http://security.ubuntu.com/ubuntu focal-security InRelease: The following signatures were invalid: KEYEXPIRED
```

**Automatic Recovery**: The `safe_apt_update()` function automatically:
1. Detects time-related APT errors
2. Runs enhanced time synchronization
3. Retries the APT operation
4. Reports success or provides detailed error information

**Manual Recovery Process**:
```bash
# Step 1: Check current time vs. actual time
date
curl -s "http://worldtimeapi.org/api/timezone/Etc/UTC" | grep datetime

# Step 2: Sync time using enhanced function
enhanced_time_sync

# Step 3: Verify time is now correct
date

# Step 4: Clear APT cache and retry
sudo apt clean
sudo apt update
```

#### Advanced Configuration Options

**Environment Variables**:
```bash
# Time sync configuration
export TIME_SYNC_ENABLED=true                    # Enable automatic sync (default: true)
export TIME_TOLERANCE_SECONDS=300                # Max drift before sync (default: 300)
export TIME_SYNC_SERVERS="custom.ntp.server"     # Custom NTP servers
export TIME_SERVICE_PREFERENCE="chrony"          # Prefer specific service

# Web API configuration
export WEB_API_TIMEOUT=10                        # API timeout seconds (default: 10)
export ENABLE_WEB_FALLBACK=true                  # Enable web API fallback (default: true)
```

**Debug Mode**:
```bash
# Enable detailed time sync logging
export LOG_LEVEL="DEBUG"
enhanced_time_sync

# View detailed time sync operations
grep "time_sync" /opt/vless/logs/system.log | tail -20
```

#### Manual Recovery Procedures

1. **Complete Time Service Reset**:
   ```bash
   # Stop all time services
   sudo systemctl stop systemd-timesyncd chronyd ntp

   # Reset system time manually
   sudo date -s "$(curl -s 'http://worldtimeapi.org/api/timezone/Etc/UTC' | grep -o '"datetime":"[^"]*' | cut -d'"' -f4 | cut -d'T' -f1-2 | tr 'T' ' ')"

   # Restart preferred time service
   sudo systemctl start systemd-timesyncd
   sudo systemctl enable systemd-timesyncd
   ```

2. **Hardware Clock Synchronization**:
   ```bash
   # Sync system clock to hardware clock
   sudo hwclock --systohc

   # Or sync hardware clock to system clock
   sudo hwclock --hctosys

   # Check hardware clock
   sudo hwclock --show
   ```

3. **Time Zone Issues**:
   ```bash
   # Check current timezone
   timedatectl status

   # Set correct timezone
   sudo timedatectl set-timezone UTC
   # Or for specific region
   sudo timedatectl set-timezone America/New_York

   # List available timezones
   timedatectl list-timezones | grep -i america
   ```

#### Testing Time Synchronization

**Validation Commands**:
```bash
# Test time sync function
enhanced_time_sync --test

# Verify NTP connectivity
chronyc sources -v
ntpdate -q pool.ntp.org

# Check time drift
chronyc tracking | grep "System time"

# Test web API fallback
curl -s "http://worldtimeapi.org/api/timezone/Etc/UTC" | grep unixtime
```

**Troubleshooting Checklist**:
- [ ] System date/time displayed correctly: `date`
- [ ] Time service running: `systemctl status systemd-timesyncd`
- [ ] NTP servers reachable: `chronyc sources -v`
- [ ] Hardware clock synchronized: `sudo hwclock --show`
- [ ] APT operations successful: `sudo apt update`
- [ ] SSL certificates valid: `curl -I https://google.com`

### Problem: Installation Script Fails

#### Symptom
Installation script exits with errors, hangs indefinitely, or shows "multiple sourcing" errors.

#### Common Causes
- Insufficient permissions
- Multiple sourcing of common utilities
- Network connectivity issues
- Package repository problems
- Disk space shortage
- Python dependency conflicts

#### Solutions

1. **Permission and Sourcing Issues**
   ```bash
   # Ensure running as root
   sudo su -
   ./install.sh

   # Or fix script permissions
   chmod +x install.sh
   chown root:root install.sh

   # The script now includes include guards to prevent multiple sourcing
   # If you still see sourcing errors, restart your shell session
   exec bash
   ```

2. **Network Issues**
   ```bash
   # Test internet connectivity
   ping 8.8.8.8

   # Check DNS resolution
   nslookup google.com

   # Configure alternative DNS
   echo "nameserver 8.8.8.8" >> /etc/resolv.conf
   ```

3. **Package Repository Issues**
   ```bash
   # Ubuntu/Debian
   sudo apt update
   sudo apt install -f

   # CentOS/RHEL
   sudo dnf clean all
   sudo dnf update
   ```

4. **Disk Space Issues**
   ```bash
   # Check available space
   df -h

   # Clean temporary files
   sudo apt autoremove
   sudo apt autoclean

   # Clean Docker
   sudo docker system prune -a
   ```

### Problem: Dependencies Installation Fails

#### Symptom
Required packages fail to install during setup, especially Python packages with "externally managed environment" errors.

#### Solutions

1. **Update Package Lists**
   ```bash
   # Ubuntu/Debian
   sudo apt update && sudo apt upgrade

   # CentOS/RHEL
   sudo dnf update
   ```

2. **Install Missing Dependencies Manually**
   ```bash
   # Core dependencies
   sudo apt install curl wget git unzip python3 python3-pip

   # Docker
   curl -fsSL https://get.docker.com -o get-docker.sh
   sudo sh get-docker.sh
   ```

3. **Enhanced Python Dependency Installation**
   ```bash
   # The script now uses multiple fallback methods for Python packages
   # If automatic installation fails, try manual installation:

   # Method 1: Standard installation
   sudo python3 -m pip install -r requirements.txt

   # Method 2: For externally managed environments
   sudo python3 -m pip install -r requirements.txt --break-system-packages

   # Method 3: User installation
   python3 -m pip install -r requirements.txt --user

   # Method 4: Individual package installation
   sudo python3 -m pip install python-telegram-bot qrcode[pil] requests aiohttp --break-system-packages
   ```

3. **Alternative Package Sources**
   ```bash
   # Add universe repository (Ubuntu)
   sudo add-apt-repository universe

   # Enable EPEL (CentOS/RHEL)
   sudo dnf install epel-release
   ```

### Problem: Docker Installation Fails

#### Solutions

1. **Remove Existing Docker**
   ```bash
   sudo systemctl stop docker
   sudo apt remove docker docker-engine docker.io containerd runc
   sudo apt autoremove
   ```

2. **Clean Installation**
   ```bash
   curl -fsSL https://get.docker.com -o get-docker.sh
   sudo sh get-docker.sh
   sudo systemctl enable docker
   sudo systemctl start docker
   ```

3. **Verify Installation**
   ```bash
   sudo docker --version
   sudo docker run hello-world
   ```

## Service Problems

### Problem: Xray Service Won't Start

#### Symptom
Xray service fails to start or crashes immediately.

#### Diagnostic Commands
```bash
sudo systemctl status xray
sudo journalctl -u xray -f
sudo /usr/local/bin/xray -test -config /opt/vless/config/config.json
```

#### Common Solutions

1. **Configuration Errors**
   ```bash
   # Test configuration
   sudo /usr/local/bin/xray -test -config /opt/vless/config/config.json

   # Regenerate configuration
   sudo /opt/vless/scripts/config_templates.sh generate
   ```

2. **Port Conflicts**
   ```bash
   # Check port usage
   sudo netstat -tlnp | grep :443

   # Kill conflicting processes
   sudo fuser -k 443/tcp

   # Change port in configuration
   sudo nano /opt/vless/config/config.json
   ```

3. **Permission Issues**
   ```bash
   # Fix file permissions
   sudo chown -R xray:xray /opt/vless/config/
   sudo chmod 600 /opt/vless/config/config.json
   ```

4. **Missing Certificates**
   ```bash
   # Generate new certificates
   sudo /opt/vless/scripts/cert_management.sh generate

   # Check certificate status
   sudo /opt/vless/scripts/cert_management.sh status
   ```

### Problem: Docker Containers Not Running

#### Diagnostic Commands
```bash
sudo docker ps -a
sudo docker logs xray-container
sudo docker inspect xray-container
```

#### Solutions

1. **Restart Containers**
   ```bash
   sudo docker-compose down
   sudo docker-compose up -d
   ```

2. **Check Container Logs**
   ```bash
   sudo docker logs xray-container
   sudo docker logs telegram-bot
   ```

3. **Rebuild Containers**
   ```bash
   sudo docker-compose down
   sudo docker-compose build --no-cache
   sudo docker-compose up -d
   ```

### Problem: Services Running but Not Accessible

#### Solutions

1. **Firewall Configuration**
   ```bash
   # UFW (now with improved validation)
   sudo ufw allow 443/tcp
   sudo ufw reload

   # Check UFW status with verbose output
   sudo ufw status verbose

   # If UFW validation fails, reset and reconfigure
   sudo ufw --force reset
   sudo ufw default deny incoming
   sudo ufw default allow outgoing
   sudo ufw allow ssh
   sudo ufw allow 443/tcp
   sudo ufw --force enable

   # firewalld
   sudo firewall-cmd --permanent --add-port=443/tcp
   sudo firewall-cmd --reload
   ```

2. **Check Listening Ports**
   ```bash
   sudo netstat -tlnp | grep :443
   sudo ss -tlnp | grep :443
   ```

3. **Test Local Connectivity**
   ```bash
   curl -v https://localhost:443
   telnet localhost 443
   ```

## Connection Issues

### Problem: Clients Cannot Connect

#### Symptom
VPN clients fail to establish connection or connect but have no internet access.

#### Diagnostic Steps

1. **Server-side Checks**
   ```bash
   # Check Xray status
   sudo systemctl status xray

   # Monitor connections
   sudo journalctl -u xray -f

   # Check listening ports
   sudo netstat -tlnp | grep xray
   ```

2. **Network Connectivity**
   ```bash
   # Test external connectivity
   curl -I https://www.google.com

   # Check DNS resolution
   nslookup google.com

   # Test port accessibility
   nmap -p 443 your-server-ip
   ```

#### Solutions

1. **Configuration Issues**
   ```bash
   # Regenerate client configuration
   sudo /opt/vless/scripts/user_management.sh config username

   # Verify server configuration
   sudo /usr/local/bin/xray -test -config /opt/vless/config/config.json
   ```

2. **Firewall Problems**
   ```bash
   # Check firewall rules
   sudo ufw status verbose

   # Allow VLESS port
   sudo ufw allow 443/tcp
   sudo ufw reload
   ```

3. **Reality Configuration**
   ```bash
   # Update Reality domain
   sudo /opt/vless/scripts/config_templates.sh update-reality-domain "www.microsoft.com"

   # Regenerate Reality keys
   sudo /opt/vless/scripts/config_templates.sh generate-reality-keys
   ```

### Problem: Slow Connection Speed

#### Diagnostic Steps
```bash
# Check server resources
top
htop
iotop

# Monitor network usage
iftop
nethogs

# Check connection count
sudo netstat -an | grep :443 | wc -l
```

#### Solutions

1. **Resource Optimization**
   ```bash
   # Adjust buffer sizes
   echo 'net.core.rmem_max = 134217728' >> /etc/sysctl.conf
   echo 'net.core.wmem_max = 134217728' >> /etc/sysctl.conf
   sudo sysctl -p
   ```

2. **Connection Limits**
   ```bash
   # Increase file descriptor limits
   echo '* soft nofile 65536' >> /etc/security/limits.conf
   echo '* hard nofile 65536' >> /etc/security/limits.conf
   ```

3. **Server Configuration**
   ```bash
   # Optimize Xray configuration
   sudo /opt/vless/scripts/config_templates.sh optimize-performance
   ```

## User Management Problems

### Problem: Cannot Create Users

#### Symptom
User creation commands fail or users don't appear in the database.

#### Diagnostic Commands
```bash
sudo /opt/vless/scripts/user_management.sh list
sudo sqlite3 /opt/vless/users/users.db ".tables"
sudo journalctl -u xray | grep -i error
```

#### Solutions

1. **Database Issues**
   ```bash
   # Check database integrity
   sudo sqlite3 /opt/vless/users/users.db "PRAGMA integrity_check;"

   # Recreate database
   sudo /opt/vless/scripts/user_database.sh init
   ```

2. **Permission Problems**
   ```bash
   # Fix database permissions
   sudo chown xray:xray /opt/vless/users/users.db
   sudo chmod 660 /opt/vless/users/users.db
   ```

3. **Configuration Regeneration**
   ```bash
   # Regenerate Xray configuration
   sudo /opt/vless/scripts/config_templates.sh generate
   sudo systemctl restart xray
   ```

### Problem: User Configurations Invalid

#### Solutions

1. **Validate Configuration**
   ```bash
   # Test configuration syntax
   sudo /usr/local/bin/xray -test -config /opt/vless/config/config.json
   ```

2. **Regenerate User Configuration**
   ```bash
   # Remove and recreate user
   sudo /opt/vless/scripts/user_management.sh remove username
   sudo /opt/vless/scripts/user_management.sh add username
   ```

## Performance Issues

### Problem: High CPU Usage

#### Diagnostic Commands
```bash
top -p $(pgrep xray)
htop
sar -u 1 10
```

#### Solutions

1. **Check Configuration**
   ```bash
   # Optimize Xray settings
   sudo /opt/vless/scripts/config_templates.sh optimize-performance
   ```

2. **Limit Connections**
   ```bash
   # Set connection limits per user
   sudo /opt/vless/scripts/user_management.sh set-global-limit 1000
   ```

### Problem: High Memory Usage

#### Solutions

1. **Monitor Memory Usage**
   ```bash
   free -h
   ps aux --sort=-%mem | head
   ```

2. **Adjust System Settings**
   ```bash
   # Configure swap
   sudo fallocate -l 2G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

### Problem: Disk Space Issues

#### Solutions

1. **Clean Log Files**
   ```bash
   # Rotate logs
   sudo logrotate -f /etc/logrotate.conf

   # Clean old logs
   sudo find /opt/vless/logs -name "*.log" -mtime +30 -delete
   ```

2. **Clean Docker**
   ```bash
   sudo docker system prune -a
   sudo docker volume prune
   ```

## Security Concerns

### Problem: Suspicious Activity Detected

#### Immediate Actions

1. **Monitor Active Connections**
   ```bash
   sudo netstat -an | grep :443
   sudo ss -tuln | grep :443
   ```

2. **Check Failed Authentication Attempts**
   ```bash
   sudo journalctl -u xray | grep -i "fail\|error\|reject"
   ```

3. **Review User Activity**
   ```bash
   sudo /opt/vless/scripts/monitoring.sh user-activity
   ```

#### Security Hardening

1. **Update System**
   ```bash
   sudo /opt/vless/scripts/system_update.sh
   ```

2. **Run Security Audit**
   ```bash
   sudo /opt/vless/scripts/security_hardening.sh audit
   ```

3. **Enable Additional Protection**
   ```bash
   sudo /opt/vless/scripts/security_hardening.sh enable-fail2ban
   sudo /opt/vless/scripts/security_hardening.sh enable-geo-blocking
   ```

### Problem: Certificate Issues

#### Solutions

1. **Regenerate Certificates**
   ```bash
   sudo /opt/vless/scripts/cert_management.sh renew
   ```

2. **Check Certificate Validity**
   ```bash
   sudo /opt/vless/scripts/cert_management.sh status
   ```


## Configuration Problems

### Problem: Invalid Xray Configuration

#### Solutions

1. **Test Configuration**
   ```bash
   sudo /usr/local/bin/xray -test -config /opt/vless/config/config.json
   ```

2. **Regenerate Configuration**
   ```bash
   # Backup current configuration
   sudo cp /opt/vless/config/config.json /opt/vless/config/config.json.bak

   # Generate new configuration
   sudo /opt/vless/scripts/config_templates.sh generate
   ```

3. **Restore from Backup**
   ```bash
   sudo /opt/vless/scripts/backup_restore.sh restore --config-only
   ```

### Problem: Reality Configuration Issues

#### Solutions

1. **Update Reality Settings**
   ```bash
   # Change Reality domain
   sudo /opt/vless/scripts/config_templates.sh set-reality-domain "www.apple.com"

   # Regenerate Reality keys
   sudo /opt/vless/scripts/config_templates.sh generate-reality-keys
   ```

2. **Test Reality Configuration**
   ```bash
   # Test Reality connectivity
   curl -H "Host: www.microsoft.com" https://your-server-ip:443
   ```

## System Recovery

### Emergency Recovery Procedures

#### Complete System Recovery

1. **Stop All Services**
   ```bash
   sudo systemctl stop xray
   sudo systemctl stop docker
      ```

2. **Restore from Backup**
   ```bash
   sudo /opt/vless/scripts/backup_restore.sh restore /opt/vless/backup/latest.tar.gz
   ```

3. **Restart Services**
   ```bash
   sudo systemctl start docker
   sudo systemctl start xray
      ```

#### Partial Recovery

1. **Configuration Only**
   ```bash
   sudo /opt/vless/scripts/backup_restore.sh restore --config-only
   sudo systemctl restart xray
   ```

2. **User Database Only**
   ```bash
   sudo /opt/vless/scripts/backup_restore.sh restore --users-only
   sudo /opt/vless/scripts/config_templates.sh generate
   ```

### Factory Reset

1. **Complete Uninstall**
   ```bash
   sudo /opt/vless/scripts/uninstall.sh --complete
   ```

2. **Clean Installation**
   ```bash
   cd /path/to/vless
   sudo ./install.sh --clean
   ```

## Log Analysis

### Important Log Locations

- **Xray Logs**: `journalctl -u xray`
- **Docker Logs**: `journalctl -u docker`
- **System Logs**: `/opt/vless/logs/system.log`
- **User Activity**: `/opt/vless/logs/user_activity.log`
- **Security Logs**: `/opt/vless/logs/security.log`

### Log Analysis Commands

1. **Search for Errors**
   ```bash
   sudo journalctl -u xray | grep -i error
   sudo grep -i "error\|fail\|critical" /opt/vless/logs/*.log
   ```

2. **Monitor Real-time Logs**
   ```bash
   sudo journalctl -u xray -f
   sudo tail -f /opt/vless/logs/system.log
   ```

3. **Analyze Connection Patterns**
   ```bash
   sudo grep "new connection" /opt/vless/logs/user_activity.log | tail -100
   ```

### Log Rotation and Cleanup

1. **Configure Log Rotation**
   ```bash
   sudo /opt/vless/scripts/logging_setup.sh configure-rotation
   ```

2. **Clean Old Logs**
   ```bash
   sudo find /opt/vless/logs -name "*.log" -mtime +30 -delete
   sudo journalctl --vacuum-time=30d
   ```

## Recent Installation Fixes (v1.0.1)

### Fixed Issues

1. **Multiple Sourcing Prevention**
   - Added include guard to `common_utils.sh`
   - Prevents "already loaded" errors during installation
   - Improves script reliability and performance

2. **Enhanced Python Dependency Handling**
   - Multiple fallback installation methods
   - Support for externally managed Python environments
   - Automatic timeout handling and error recovery
   - Better error reporting and debugging

3. **Improved UFW Firewall Validation**
   - Handles different UFW output formats
   - Better parsing of status information
   - Enhanced error handling for edge cases
   - Debug logging for troubleshooting

4. **System User Creation**
   - Dedicated `create_vless_system_user()` function
   - Proper group and user creation with security restrictions
   - Better isolation and permission management
   - Comprehensive error handling

5. **Quick Mode Installation**
   - Added `QUICK_MODE` support for unattended installation
   - Skips interactive prompts automatically
   - Maintains full functionality while enabling automation
   - Environment variable based configuration

### Using Quick Mode

```bash
# Enable quick mode for automated installation
sudo ./install.sh --quick

# Or set environment variable
export QUICK_MODE=true
sudo ./install.sh
```

## Getting Help

### Self-Diagnosis Tools

1. **System Health Check**
   ```bash
   sudo /opt/vless/scripts/system_check.sh
   ```

2. **Generate Diagnostic Report**
   ```bash
   sudo /opt/vless/scripts/diagnostic_report.sh
   ```

### Information to Collect

When seeking help, always include:

1. **System Information**
   ```bash
   uname -a
   lsb_release -a
   ```

2. **Service Status**
   ```bash
   sudo systemctl status xray
   sudo docker ps
   ```

3. **Recent Logs**
   ```bash
   sudo journalctl -u xray --since "1 hour ago"
   ```

4. **Configuration Test**
   ```bash
   sudo /usr/local/bin/xray -test -config /opt/vless/config/config.json
   ```

### Contact Information

- **Documentation**: Check all documentation files in `/docs/`
- **Issue Tracker**: GitHub Issues for bug reports
- **Community Forum**: Community support and discussions
- **Professional Support**: Commercial support options

### Best Practices for Troubleshooting

1. **Always backup before making changes**
2. **Test changes in isolation**
3. **Keep detailed logs of actions taken**
4. **Verify fixes with multiple tests**
5. **Document solutions for future reference**

---

**Remember**: Most issues can be resolved by checking logs, verifying configurations, and ensuring all services are running properly. When in doubt, start with the basic troubleshooting steps and work systematically through potential causes.