# Troubleshooting Guide

Comprehensive troubleshooting guide for the VLESS+Reality VPN Management System.

## Table of Contents

1. [General Troubleshooting](#general-troubleshooting)
2. [Installation Issues](#installation-issues)
3. [Service Problems](#service-problems)
4. [Connection Issues](#connection-issues)
5. [User Management Problems](#user-management-problems)
6. [Performance Issues](#performance-issues)
7. [Security Concerns](#security-concerns)
8. [Telegram Bot Issues](#telegram-bot-issues)
9. [Configuration Problems](#configuration-problems)
10. [System Recovery](#system-recovery)
11. [Log Analysis](#log-analysis)
12. [Getting Help](#getting-help)

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

### Problem: Installation Script Fails

#### Symptom
Installation script exits with errors or hangs indefinitely.

#### Common Causes
- Insufficient permissions
- Network connectivity issues
- Package repository problems
- Disk space shortage

#### Solutions

1. **Permission Issues**
   ```bash
   # Ensure running as root
   sudo su -
   ./install.sh

   # Or fix script permissions
   chmod +x install.sh
   chown root:root install.sh
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
Required packages fail to install during setup.

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
   # UFW
   sudo ufw allow 443/tcp
   sudo ufw reload

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

## Telegram Bot Issues

### Problem: Bot Not Responding

#### Diagnostic Commands
```bash
sudo systemctl status telegram-bot
sudo journalctl -u telegram-bot -f
```

#### Solutions

1. **Check Bot Configuration**
   ```bash
   # Verify bot token
   sudo /opt/vless/scripts/telegram_bot_manager.sh verify-token

   # Test bot connectivity
   sudo /opt/vless/scripts/telegram_bot_manager.sh test-connection
   ```

2. **Restart Bot Service**
   ```bash
   sudo systemctl restart telegram-bot
   sudo journalctl -u telegram-bot -f
   ```

3. **Update Bot Dependencies**
   ```bash
   sudo pip3 install -r /opt/vless/requirements.txt --upgrade
   ```

### Problem: Bot Commands Not Working

#### Solutions

1. **Check Admin Authorization**
   ```bash
   # Verify admin user IDs
   sudo /opt/vless/scripts/telegram_bot_manager.sh list-admins

   # Add admin user
   sudo /opt/vless/scripts/telegram_bot_manager.sh add-admin TELEGRAM_USER_ID
   ```

2. **Check Bot Permissions**
   ```bash
   # Verify bot has necessary permissions
   sudo /opt/vless/scripts/telegram_bot_manager.sh check-permissions
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
   sudo systemctl stop telegram-bot
   ```

2. **Restore from Backup**
   ```bash
   sudo /opt/vless/scripts/backup_restore.sh restore /opt/vless/backup/latest.tar.gz
   ```

3. **Restart Services**
   ```bash
   sudo systemctl start docker
   sudo systemctl start xray
   sudo systemctl start telegram-bot
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
- **Telegram Bot**: `journalctl -u telegram-bot`

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