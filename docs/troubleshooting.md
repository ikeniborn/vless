# VLESS+Reality VPN Management System - Troubleshooting Guide

This comprehensive troubleshooting guide helps diagnose and resolve common issues with the VLESS+Reality VPN Management System.

## Table of Contents

- [Quick Diagnostics](#quick-diagnostics)
- [Installation Issues](#installation-issues)
- [Service Problems](#service-problems)
- [Connection Issues](#connection-issues)
- [Performance Problems](#performance-problems)
- [Certificate Issues](#certificate-issues)
- [User Management Problems](#user-management-problems)
- [Telegram Bot Issues](#telegram-bot-issues)
- [System Resource Issues](#system-resource-issues)
- [Network Configuration Problems](#network-configuration-problems)
- [Log Analysis](#log-analysis)
- [Emergency Recovery](#emergency-recovery)
- [Getting Support](#getting-support)

## Quick Diagnostics

### System Health Check

Before diving into specific issues, run the comprehensive system health check:

```bash
# Quick system status
sudo /opt/vless/scripts/status.sh

# Comprehensive health check
sudo /opt/vless/scripts/maintenance_utils.sh check_system_health

# Generate detailed diagnostics
sudo /opt/vless/scripts/maintenance_utils.sh generate_diagnostics
```

### Service Status Check

```bash
# Check all critical services
sudo systemctl status vless-vpn
sudo systemctl status docker
sudo systemctl status nginx
sudo systemctl status vless-telegram-bot

# Quick service overview
sudo /opt/vless/scripts/monitoring.sh status --detailed
```

### Basic Connectivity Test

```bash
# Test network connectivity
sudo /opt/vless/scripts/monitoring.sh test_connectivity

# Test VPN port
telnet localhost 443

# Test certificate validity
sudo /opt/vless/scripts/cert_management.sh status
```

## Installation Issues

### Installation Fails During Dependency Installation

**Symptoms:**
- Installation stops during package installation
- Package manager errors
- Missing dependencies

**Diagnostic Commands:**
```bash
# Check package manager status
sudo apt update
sudo apt list --upgradable

# Check for broken packages
sudo apt --fix-broken install
sudo dpkg --configure -a

# Check disk space
df -h
```

**Solutions:**

1. **Update Package Lists:**
   ```bash
   sudo apt update && sudo apt upgrade -y
   sudo apt autoremove -y
   ```

2. **Fix Broken Packages:**
   ```bash
   sudo apt --fix-broken install
   sudo dpkg --reconfigure -a
   ```

3. **Clear Package Cache:**
   ```bash
   sudo apt clean
   sudo apt autoclean
   ```

4. **Retry Installation:**
   ```bash
   sudo ./install.sh --force
   ```

### Docker Installation Fails

**Symptoms:**
- Docker service won't start
- Permission denied errors
- Container runtime errors

**Diagnostic Commands:**
```bash
# Check Docker status
sudo systemctl status docker
sudo docker --version

# Check Docker daemon logs
sudo journalctl -u docker -n 50

# Test Docker functionality
sudo docker run hello-world
```

**Solutions:**

1. **Manual Docker Installation:**
   ```bash
   # Remove existing Docker
   sudo apt remove docker docker-engine docker.io containerd runc

   # Install Docker manually
   curl -fsSL https://get.docker.com -o get-docker.sh
   sudo sh get-docker.sh

   # Add user to docker group
   sudo usermod -aG docker $USER
   newgrp docker
   ```

2. **Fix Docker Permissions:**
   ```bash
   sudo chown root:docker /var/run/docker.sock
   sudo chmod 666 /var/run/docker.sock
   ```

3. **Restart Docker Service:**
   ```bash
   sudo systemctl restart docker
   sudo systemctl enable docker
   ```

### Permission Denied During Installation

**Symptoms:**
- "Permission denied" errors
- Cannot create directories
- Cannot write configuration files

**Solutions:**

1. **Run with Proper Privileges:**
   ```bash
   # Ensure running as root or with sudo
   sudo ./install.sh
   ```

2. **Check File Permissions:**
   ```bash
   # Make installation script executable
   chmod +x install.sh
   chmod +x modules/*.sh
   ```

3. **Fix Directory Permissions:**
   ```bash
   sudo chown -R root:root /opt/vless/
   sudo chmod -R 755 /opt/vless/scripts/
   ```

### Certificate Generation Fails

**Symptoms:**
- Let's Encrypt certificate generation fails
- Domain validation errors
- Certificate authority errors

**Diagnostic Commands:**
```bash
# Check domain DNS resolution
nslookup your-domain.com
dig your-domain.com A

# Test HTTP connectivity
curl -I http://your-domain.com

# Check firewall
sudo ufw status
```

**Solutions:**

1. **Verify Domain Configuration:**
   ```bash
   # Ensure domain points to server IP
   nslookup your-domain.com
   curl -4 ifconfig.co  # Compare with your server IP
   ```

2. **Check Firewall Settings:**
   ```bash
   # Ensure ports 80 and 443 are open
   sudo ufw allow 80
   sudo ufw allow 443
   sudo ufw reload
   ```

3. **Manual Certificate Generation:**
   ```bash
   # Generate certificates manually
   sudo /opt/vless/scripts/cert_management.sh generate --manual
   ```

4. **Use Self-Signed Certificates (temporary):**
   ```bash
   sudo /opt/vless/scripts/cert_management.sh self_signed
   ```

## Service Problems

### VPN Service Won't Start

**Symptoms:**
- `systemctl start vless-vpn` fails
- Service shows "failed" status
- Users cannot connect

**Diagnostic Commands:**
```bash
# Check service status and logs
sudo systemctl status vless-vpn -l
sudo journalctl -u vless-vpn -n 50
sudo journalctl -u vless-vpn --since "1 hour ago"

# Check Xray configuration
sudo /opt/vless/scripts/configure.sh validate

# Check Docker containers
sudo docker ps -a
sudo docker logs vless-xray
```

**Solutions:**

1. **Restart Docker Service:**
   ```bash
   sudo systemctl restart docker
   sudo systemctl restart vless-vpn
   ```

2. **Check Configuration:**
   ```bash
   # Validate Xray configuration
   sudo /opt/vless/scripts/configure.sh validate

   # Regenerate configuration if needed
   sudo /opt/vless/scripts/configure.sh regenerate
   ```

3. **Check Port Conflicts:**
   ```bash
   # Check if port is already in use
   sudo netstat -tlnp | grep :443
   sudo lsof -i :443

   # Stop conflicting services
   sudo systemctl stop nginx
   sudo systemctl stop apache2
   ```

4. **Rebuild Container:**
   ```bash
   # Stop and remove container
   sudo docker stop vless-xray
   sudo docker rm vless-xray

   # Restart service
   sudo systemctl restart vless-vpn
   ```

### Service Starts But Users Can't Connect

**Symptoms:**
- Service shows as "running"
- Network connectivity exists
- User configurations are correct
- Connection attempts fail

**Diagnostic Commands:**
```bash
# Check active connections
sudo /opt/vless/scripts/monitoring.sh connections

# Test connectivity from server
sudo /opt/vless/scripts/monitoring.sh test_connectivity

# Check firewall rules
sudo ufw status numbered
sudo iptables -L -n
```

**Solutions:**

1. **Verify Firewall Configuration:**
   ```bash
   # Check UFW status
   sudo ufw status verbose

   # Allow VPN port if not already allowed
   sudo ufw allow 443/tcp
   sudo ufw reload
   ```

2. **Check Network Configuration:**
   ```bash
   # Verify server is listening on correct port
   sudo netstat -tlnp | grep :443

   # Test port from external source
   telnet your-server-ip 443
   ```

3. **Verify User Configuration:**
   ```bash
   # Check if user exists and is active
   sudo /opt/vless/scripts/user_management.sh info username

   # Regenerate user configuration
   sudo /opt/vless/scripts/user_management.sh config username
   ```

### Container Issues

**Symptoms:**
- Docker containers not running
- Container restart loops
- Resource allocation issues

**Diagnostic Commands:**
```bash
# Check container status
sudo docker ps -a

# Check container logs
sudo docker logs vless-xray

# Check container resource usage
sudo docker stats

# Check Docker system information
sudo docker system df
sudo docker system info
```

**Solutions:**

1. **Restart Containers:**
   ```bash
   # Restart all VPN-related containers
   sudo docker restart vless-xray
   sudo docker restart vless-nginx
   ```

2. **Check Resource Limits:**
   ```bash
   # Check available system resources
   free -h
   df -h

   # Increase container resource limits if needed
   sudo docker update --memory=1g --cpus=2 vless-xray
   ```

3. **Rebuild Containers:**
   ```bash
   # Stop and remove problematic containers
   sudo docker stop vless-xray
   sudo docker rm vless-xray

   # Recreate containers
   sudo systemctl restart vless-vpn
   ```

## Connection Issues

### Users Cannot Connect to VPN

**Symptoms:**
- Client shows connection errors
- Authentication failures
- Timeout errors

**Diagnostic Process:**

1. **Verify User Configuration:**
   ```bash
   # Check if user exists and is active
   sudo /opt/vless/scripts/user_management.sh info username

   # Verify user configuration
   sudo /opt/vless/scripts/user_management.sh verify username

   # Generate fresh configuration
   sudo /opt/vless/scripts/user_management.sh config username
   ```

2. **Test Server Connectivity:**
   ```bash
   # Test VPN port connectivity
   telnet your-domain.com 443
   nc -zv your-domain.com 443

   # Check from different network
   curl -I https://your-domain.com
   ```

3. **Check Firewall and Network:**
   ```bash
   # Verify firewall rules
   sudo ufw status
   sudo iptables -L -n | grep 443

   # Check if service is listening
   sudo ss -tlnp | grep :443
   ```

**Common Solutions:**

1. **Regenerate User Configuration:**
   ```bash
   sudo /opt/vless/scripts/user_management.sh update username --reset-uuid
   sudo /opt/vless/scripts/user_management.sh config username
   ```

2. **Update Reality Configuration:**
   ```bash
   sudo /opt/vless/scripts/cert_management.sh reality_keys
   sudo /opt/vless/scripts/user_management.sh update_all --reality-keys
   ```

3. **Check Client Configuration:**
   - Verify server address is correct
   - Ensure port is set to 443 (or your custom port)
   - Check UUID format is valid
   - Verify Reality settings match server

### Intermittent Connection Drops

**Symptoms:**
- Connections work initially but drop frequently
- Unstable connection quality
- High latency or packet loss

**Diagnostic Commands:**
```bash
# Monitor active connections
sudo /opt/vless/scripts/monitoring.sh connections --detailed

# Check system resources
sudo /opt/vless/scripts/monitoring.sh monitor --interval 30

# Analyze network performance
sudo /opt/vless/scripts/monitoring.sh network_analysis
```

**Solutions:**

1. **Optimize Network Settings:**
   ```bash
   # Enable BBR congestion control
   echo 'net.core.default_qdisc=fq' | sudo tee -a /etc/sysctl.conf
   echo 'net.ipv4.tcp_congestion_control=bbr' | sudo tee -a /etc/sysctl.conf
   sudo sysctl -p
   ```

2. **Increase Connection Limits:**
   ```bash
   # Edit Xray configuration to increase limits
   sudo nano /opt/vless/config/xray_config.json
   # Add or modify:
   # "policy": {
   #   "levels": {
   #     "0": {
   #       "connIdle": 300,
   #       "downlinkOnly": 1,
   #       "handshake": 4,
   #       "uplinkOnly": 1
   #     }
   #   }
   # }
   ```

3. **Check System Resources:**
   ```bash
   # Monitor CPU and memory usage
   sudo /opt/vless/scripts/monitoring.sh monitor

   # Optimize system if needed
   sudo /opt/vless/scripts/maintenance_utils.sh optimize_system
   ```

### DNS Resolution Issues

**Symptoms:**
- Cannot resolve domain names through VPN
- DNS queries fail or timeout
- Incorrect DNS responses

**Solutions:**

1. **Configure DNS in Xray:**
   ```bash
   # Edit Xray configuration
   sudo nano /opt/vless/config/xray_config.json
   # Add DNS configuration:
   # "dns": {
   #   "servers": [
   #     "8.8.8.8",
   #     "1.1.1.1",
   #     "localhost"
   #   ]
   # }
   ```

2. **Check Server DNS Configuration:**
   ```bash
   # Verify server DNS settings
   cat /etc/resolv.conf
   nslookup google.com

   # Update DNS if needed
   echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
   echo "nameserver 1.1.1.1" | sudo tee -a /etc/resolv.conf
   ```

## Performance Problems

### High CPU Usage

**Symptoms:**
- Server CPU usage consistently high
- Slow VPN performance
- System becomes unresponsive

**Diagnostic Commands:**
```bash
# Monitor CPU usage
top -p $(pgrep xray)
htop

# Check process details
sudo /opt/vless/scripts/monitoring.sh system_report

# Analyze performance patterns
sudo /opt/vless/scripts/monitoring.sh performance_analysis
```

**Solutions:**

1. **Optimize Xray Configuration:**
   ```bash
   # Reduce logging level
   sudo nano /opt/vless/config/xray_config.json
   # Change loglevel to "error" or "none"
   ```

2. **Limit Concurrent Connections:**
   ```bash
   # Set connection limits per user
   sudo /opt/vless/scripts/configure.sh set_limits --max-connections 10
   ```

3. **Upgrade Server Resources:**
   - Consider upgrading to a more powerful VPS
   - Add more CPU cores
   - Increase available RAM

### High Memory Usage

**Symptoms:**
- RAM usage consistently high
- Swap usage increasing
- Out of memory errors

**Diagnostic Commands:**
```bash
# Check memory usage
free -h
sudo /opt/vless/scripts/monitoring.sh memory_analysis

# Check process memory usage
ps aux --sort=-%mem | head -10
```

**Solutions:**

1. **Configure Memory Limits:**
   ```bash
   # Set Docker container memory limits
   sudo docker update --memory=512m vless-xray
   ```

2. **Optimize System:**
   ```bash
   # Clear caches
   sudo /opt/vless/scripts/maintenance_utils.sh cleanup

   # Optimize system settings
   sudo /opt/vless/scripts/maintenance_utils.sh optimize_system
   ```

3. **Monitor Memory Leaks:**
   ```bash
   # Monitor memory usage over time
   sudo /opt/vless/scripts/monitoring.sh monitor --memory --interval 60
   ```

### Slow Connection Speeds

**Symptoms:**
- VPN connection slower than expected
- High latency
- Poor throughput

**Diagnostic Process:**

1. **Test Connection Speed:**
   ```bash
   # Server-side speed test
   sudo /opt/vless/scripts/monitoring.sh speed_test

   # Network performance test
   sudo /opt/vless/scripts/monitoring.sh network_benchmark
   ```

2. **Optimize Network Configuration:**
   ```bash
   # Enable network optimizations
   sudo /opt/vless/scripts/maintenance_utils.sh optimize_network

   # Configure TCP settings
   echo 'net.ipv4.tcp_window_scaling = 1' | sudo tee -a /etc/sysctl.conf
   echo 'net.core.rmem_max = 67108864' | sudo tee -a /etc/sysctl.conf
   echo 'net.core.wmem_max = 67108864' | sudo tee -a /etc/sysctl.conf
   sudo sysctl -p
   ```

## Certificate Issues

### SSL/TLS Certificate Problems

**Symptoms:**
- Certificate expired warnings
- SSL handshake failures
- Certificate validation errors

**Diagnostic Commands:**
```bash
# Check certificate status
sudo /opt/vless/scripts/cert_management.sh status

# Test certificate validity
openssl s_client -connect your-domain.com:443 -servername your-domain.com

# Check certificate expiration
echo | openssl s_client -connect your-domain.com:443 2>/dev/null | openssl x509 -noout -dates
```

**Solutions:**

1. **Renew Certificates:**
   ```bash
   # Manual certificate renewal
   sudo /opt/vless/scripts/cert_management.sh renew

   # Force certificate regeneration
   sudo /opt/vless/scripts/cert_management.sh generate --force
   ```

2. **Setup Automatic Renewal:**
   ```bash
   # Configure automatic renewal
   sudo /opt/vless/scripts/cert_management.sh auto_renew

   # Test renewal process
   sudo /opt/vless/scripts/cert_management.sh test_renewal
   ```

### Let's Encrypt Rate Limits

**Symptoms:**
- Certificate generation fails with rate limit errors
- "too many certificates" errors
- Cannot obtain new certificates

**Solutions:**

1. **Use Staging Environment:**
   ```bash
   # Test with Let's Encrypt staging
   sudo /opt/vless/scripts/cert_management.sh generate --staging
   ```

2. **Use Alternative Certificate Method:**
   ```bash
   # Generate self-signed certificate temporarily
   sudo /opt/vless/scripts/cert_management.sh self_signed

   # Or use existing certificate
   sudo /opt/vless/scripts/cert_management.sh import --cert /path/to/cert.pem --key /path/to/key.pem
   ```

### Reality Key Issues

**Symptoms:**
- Reality handshake failures
- Connection refused with Reality
- Invalid Reality configuration

**Solutions:**

1. **Regenerate Reality Keys:**
   ```bash
   # Generate new Reality key pair
   sudo /opt/vless/scripts/cert_management.sh reality_keys

   # Update all user configurations
   sudo /opt/vless/scripts/user_management.sh update_all --reality-keys
   ```

2. **Verify Reality Configuration:**
   ```bash
   # Check Reality target accessibility
   curl -I https://www.microsoft.com

   # Test Reality configuration
   sudo /opt/vless/scripts/configure.sh test_reality
   ```

## User Management Problems

### Cannot Add New Users

**Symptoms:**
- User creation fails
- Database errors
- User limit reached

**Diagnostic Commands:**
```bash
# Check user database status
sudo /opt/vless/scripts/user_management.sh list --detailed

# Check available space for user data
df -h /opt/vless/data/

# Verify user database integrity
sudo /opt/vless/scripts/user_management.sh verify_database
```

**Solutions:**

1. **Check User Limits:**
   ```bash
   # Check current user count
   sudo /opt/vless/scripts/user_management.sh list | wc -l

   # Increase user limit if needed
   sudo nano /opt/vless/config/vless.env
   # Set MAX_USERS=1000
   ```

2. **Clean Up User Database:**
   ```bash
   # Remove inactive users
   sudo /opt/vless/scripts/user_management.sh cleanup --inactive

   # Repair database if corrupted
   sudo /opt/vless/scripts/user_management.sh repair_database
   ```

### User Configuration Generation Fails

**Symptoms:**
- QR code generation errors
- Invalid configuration output
- Missing configuration parameters

**Solutions:**

1. **Regenerate User Configuration:**
   ```bash
   # Force configuration regeneration
   sudo /opt/vless/scripts/user_management.sh config username --force

   # Update user with fresh UUID
   sudo /opt/vless/scripts/user_management.sh update username --reset-uuid
   ```

2. **Check Configuration Templates:**
   ```bash
   # Verify configuration templates
   sudo /opt/vless/scripts/configure.sh validate_templates

   # Regenerate templates if corrupted
   sudo /opt/vless/scripts/configure.sh generate_templates
   ```

## Telegram Bot Issues

### Bot Not Responding

**Symptoms:**
- Bot doesn't respond to commands
- Bot appears offline
- Commands timeout

**Diagnostic Commands:**
```bash
# Check bot service status
sudo systemctl status vless-telegram-bot

# Check bot logs
sudo journalctl -u vless-telegram-bot -n 50

# Test bot token
curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getMe"
```

**Solutions:**

1. **Restart Bot Service:**
   ```bash
   sudo systemctl restart vless-telegram-bot
   sudo systemctl enable vless-telegram-bot
   ```

2. **Verify Bot Configuration:**
   ```bash
   # Check bot token validity
   sudo /opt/vless/scripts/telegram_bot_manager.sh test_token

   # Reconfigure bot
   sudo /opt/vless/scripts/telegram_bot_manager.sh setup
   ```

3. **Check Network Connectivity:**
   ```bash
   # Test Telegram API connectivity
   curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates"
   ```

### Bot Commands Not Working

**Symptoms:**
- Specific commands fail
- Permission denied errors
- Incomplete command responses

**Solutions:**

1. **Check Admin Permissions:**
   ```bash
   # Verify admin user list
   sudo /opt/vless/scripts/telegram_bot_manager.sh list_admins

   # Add user as admin
   sudo /opt/vless/scripts/telegram_bot_manager.sh add_admin YOUR_TELEGRAM_ID
   ```

2. **Update Bot Commands:**
   ```bash
   # Refresh bot command list
   sudo /opt/vless/scripts/telegram_bot_manager.sh update_commands

   # Test specific command
   sudo /opt/vless/scripts/telegram_bot_manager.sh test_command status
   ```

### Bot Performance Issues

**Symptoms:**
- Slow bot responses
- Bot timeouts
- High resource usage

**Solutions:**

1. **Optimize Bot Configuration:**
   ```bash
   # Adjust bot settings
   sudo nano /opt/vless/config/bot.env
   # Increase timeout values
   # Reduce polling frequency
   ```

2. **Check System Resources:**
   ```bash
   # Monitor bot resource usage
   sudo /opt/vless/scripts/monitoring.sh process_monitor telegram_bot

   # Optimize if needed
   sudo /opt/vless/scripts/maintenance_utils.sh optimize_system
   ```

## System Resource Issues

### Disk Space Problems

**Symptoms:**
- "No space left on device" errors
- Cannot create new files
- System operations fail

**Diagnostic Commands:**
```bash
# Check disk usage
df -h
du -sh /opt/vless/*

# Find large files
find /opt/vless -type f -size +100M -exec ls -lh {} \;

# Check log file sizes
sudo du -sh /opt/vless/logs/*
```

**Solutions:**

1. **Clean Up Log Files:**
   ```bash
   # Rotate and compress logs
   sudo /opt/vless/scripts/maintenance_utils.sh cleanup_logs

   # Set log retention policy
   sudo /opt/vless/scripts/maintenance_utils.sh setup_log_rotation --retention 7d
   ```

2. **Clean Up Old Backups:**
   ```bash
   # Remove old backups
   sudo /opt/vless/scripts/backup_restore.sh cleanup_old_backups --older-than 30d

   # Configure backup retention
   sudo /opt/vless/scripts/backup_restore.sh set_retention --days 30
   ```

3. **System Cleanup:**
   ```bash
   # General system cleanup
   sudo /opt/vless/scripts/maintenance_utils.sh cleanup --all

   # Docker cleanup
   sudo docker system prune -f
   sudo docker image prune -f
   ```

### Network Port Conflicts

**Symptoms:**
- Port already in use errors
- Service binding failures
- Connection refused errors

**Diagnostic Commands:**
```bash
# Check port usage
sudo netstat -tlnp | grep :443
sudo lsof -i :443

# Check for conflicting services
sudo systemctl list-units --type=service --state=running | grep -E "(nginx|apache|httpd)"
```

**Solutions:**

1. **Stop Conflicting Services:**
   ```bash
   # Stop web servers that might conflict
   sudo systemctl stop nginx
   sudo systemctl stop apache2
   sudo systemctl disable nginx
   sudo systemctl disable apache2
   ```

2. **Change VPN Port:**
   ```bash
   # Configure different port
   sudo /opt/vless/scripts/configure.sh --port 8443

   # Update firewall
   sudo ufw allow 8443/tcp
   sudo ufw delete allow 443/tcp
   ```

## Network Configuration Problems

### Firewall Blocking Connections

**Symptoms:**
- External connections fail
- Port appears closed from outside
- Internal connections work fine

**Diagnostic Commands:**
```bash
# Check UFW status
sudo ufw status verbose

# Check iptables rules
sudo iptables -L -n
sudo iptables -t nat -L -n

# Test port from external source
telnet your-server-ip 443
nc -zv your-server-ip 443
```

**Solutions:**

1. **Configure UFW Properly:**
   ```bash
   # Reset UFW and reconfigure
   sudo ufw --force reset
   sudo /opt/vless/scripts/ufw_config.sh setup

   # Allow specific ports
   sudo ufw allow 22/tcp
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   sudo ufw enable
   ```

2. **Check Cloud Provider Security Groups:**
   - Log into your cloud provider dashboard
   - Check security group settings
   - Ensure ports 80, 443, and 22 are open
   - Allow traffic from 0.0.0.0/0 for HTTP/HTTPS

### DNS Resolution Problems

**Symptoms:**
- Cannot resolve domain names
- Slow DNS queries
- Incorrect DNS responses

**Solutions:**

1. **Fix Server DNS:**
   ```bash
   # Configure reliable DNS servers
   sudo nano /etc/resolv.conf
   # Add:
   # nameserver 8.8.8.8
   # nameserver 1.1.1.1

   # Test DNS resolution
   nslookup google.com
   dig @8.8.8.8 google.com
   ```

2. **Configure Xray DNS:**
   ```bash
   # Add DNS configuration to Xray
   sudo nano /opt/vless/config/xray_config.json
   # Add DNS section with reliable servers
   ```

## Log Analysis

### Understanding Log Files

**Log Locations:**
- System logs: `/opt/vless/logs/system.log`
- Xray logs: `/opt/vless/logs/xray.log`
- Access logs: `/opt/vless/logs/access.log`
- Error logs: `/opt/vless/logs/error.log`
- Bot logs: `/opt/vless/logs/telegram_bot.log`

### Common Log Analysis Commands

```bash
# Real-time log monitoring
sudo tail -f /opt/vless/logs/xray.log

# Search for errors
sudo grep -i error /opt/vless/logs/*.log

# Search for specific user activity
sudo grep "username" /opt/vless/logs/access.log

# Analyze connection patterns
sudo /opt/vless/scripts/monitoring.sh analyze_logs --pattern connections

# Export logs for analysis
sudo /opt/vless/scripts/maintenance_utils.sh export_logs --since "24 hours ago"
```

### Log Analysis for Common Issues

1. **Connection Failures:**
   ```bash
   # Look for handshake failures
   sudo grep -i "handshake\|failed\|rejected" /opt/vless/logs/xray.log

   # Check authentication issues
   sudo grep -i "auth\|uuid\|invalid" /opt/vless/logs/xray.log
   ```

2. **Performance Issues:**
   ```bash
   # Look for timeout errors
   sudo grep -i "timeout\|slow\|delay" /opt/vless/logs/*.log

   # Check resource usage patterns
   sudo /opt/vless/scripts/monitoring.sh log_analysis --performance
   ```

3. **Certificate Issues:**
   ```bash
   # Check certificate-related errors
   sudo grep -i "cert\|tls\|ssl" /opt/vless/logs/*.log

   # Look for Reality configuration issues
   sudo grep -i "reality\|handshake" /opt/vless/logs/xray.log
   ```

## Emergency Recovery

### System Recovery Procedures

#### Complete Service Recovery

If the VPN service is completely non-functional:

```bash
# 1. Stop all services
sudo systemctl stop vless-vpn
sudo systemctl stop vless-telegram-bot
sudo docker stop $(sudo docker ps -q)

# 2. Check system integrity
sudo /opt/vless/scripts/maintenance_utils.sh check_system_health

# 3. Restore from backup if available
sudo /opt/vless/scripts/backup_restore.sh list_backups
sudo /opt/vless/scripts/backup_restore.sh restore --backup latest

# 4. Restart services
sudo systemctl start docker
sudo systemctl start vless-vpn
sudo systemctl start vless-telegram-bot
```

#### Configuration Recovery

If configuration is corrupted:

```bash
# 1. Backup current configuration
sudo cp -r /opt/vless/config /opt/vless/config.backup.$(date +%Y%m%d_%H%M%S)

# 2. Regenerate configuration
sudo /opt/vless/scripts/configure.sh regenerate

# 3. Restore user data
sudo /opt/vless/scripts/user_management.sh restore_users

# 4. Test configuration
sudo /opt/vless/scripts/configure.sh validate

# 5. Restart services
sudo systemctl restart vless-vpn
```

#### Database Recovery

If user database is corrupted:

```bash
# 1. Stop VPN service
sudo systemctl stop vless-vpn

# 2. Backup corrupted database
sudo cp /opt/vless/data/users.db /opt/vless/data/users.db.corrupted

# 3. Restore from backup
sudo /opt/vless/scripts/backup_restore.sh restore_users_only

# 4. Verify database integrity
sudo /opt/vless/scripts/user_management.sh verify_database

# 5. Restart service
sudo systemctl start vless-vpn
```

### Disaster Recovery

#### Complete System Rebuild

If the system needs to be completely rebuilt:

```bash
# 1. Create emergency backup (if possible)
sudo /opt/vless/scripts/backup_restore.sh create_emergency_backup

# 2. Download backup to safe location
sudo cp /opt/vless/backups/emergency_backup_*.tar.gz /home/user/

# 3. Reinstall system
sudo ./install.sh --fresh-install

# 4. Restore from backup
sudo /opt/vless/scripts/backup_restore.sh restore --backup /home/user/emergency_backup_*.tar.gz

# 5. Verify restoration
sudo /opt/vless/scripts/maintenance_utils.sh check_system_health
```

## Getting Support

### Collecting Diagnostic Information

Before seeking support, collect comprehensive diagnostic information:

```bash
# Generate support bundle
sudo /opt/vless/scripts/maintenance_utils.sh generate_support_bundle

# The bundle will include:
# - System configuration
# - Service status
# - Log files (sanitized)
# - Network configuration
# - Resource usage
# - Error analysis
```

### Information to Include in Support Requests

1. **System Information:**
   - Operating system version
   - Server specifications (CPU, RAM, disk)
   - Network configuration
   - Installation date and method

2. **Problem Description:**
   - Detailed symptoms
   - When the problem started
   - Steps that reproduce the issue
   - Error messages (exact text)

3. **Diagnostic Output:**
   - Support bundle
   - Relevant log excerpts
   - Configuration files (with sensitive data removed)
   - Network test results

### Self-Help Resources

1. **Documentation:**
   - [Installation Guide](installation.md)
   - [User Guide](user_guide.md)
   - [API Reference](api_reference.md)

2. **Diagnostic Tools:**
   ```bash
   # Comprehensive system check
   sudo /opt/vless/scripts/maintenance_utils.sh check_system_health

   # Performance analysis
   sudo /opt/vless/scripts/monitoring.sh performance_analysis

   # Network connectivity test
   sudo /opt/vless/scripts/monitoring.sh test_connectivity
   ```

3. **Common Fixes:**
   ```bash
   # Try these common fixes first
   sudo systemctl restart vless-vpn
   sudo /opt/vless/scripts/maintenance_utils.sh cleanup
   sudo /opt/vless/scripts/configure.sh validate
   sudo /opt/vless/scripts/user_management.sh verify_database
   ```

### Support Channels

- **GitHub Issues**: Report bugs and request features
- **Documentation**: Comprehensive guides and examples
- **Community Forums**: User discussions and community support

### Creating Effective Bug Reports

1. **Use descriptive titles**
2. **Include system information**
3. **Provide step-by-step reproduction**
4. **Attach diagnostic logs**
5. **Describe expected vs actual behavior**

---

This troubleshooting guide covers the most common issues you may encounter with the VLESS+Reality VPN Management System. Always start with the quick diagnostics section and work through the relevant sections based on your specific symptoms. Remember to backup your system before making significant changes, and don't hesitate to seek community support when needed.