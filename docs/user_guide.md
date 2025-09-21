# VLESS+Reality VPN Management System - User Guide

This comprehensive user guide provides detailed instructions for using and managing the VLESS+Reality VPN Management System.

## Table of Contents

- [Getting Started](#getting-started)
- [User Management](#user-management)
- [Client Configuration](#client-configuration)
- [System Administration](#system-administration)
- [Telegram Bot Usage](#telegram-bot-usage)
- [Monitoring and Maintenance](#monitoring-and-maintenance)
- [Advanced Configuration](#advanced-configuration)
- [Best Practices](#best-practices)

## Getting Started

### System Overview

The VLESS+Reality VPN Management System provides:
- High-performance VPN service using VLESS protocol with Reality technology
- Web-based administration dashboard
- Telegram bot for remote management
- Automated backup and monitoring
- Comprehensive user management

### First Steps After Installation

1. **Verify Installation**
   ```bash
   sudo /opt/vless/scripts/status.sh
   ```

2. **Check Service Status**
   ```bash
   sudo systemctl status vless-vpn
   ```

3. **Create Your First User**
   ```bash
   sudo /opt/vless/scripts/user_management.sh add admin
   ```

4. **Access Web Dashboard** (if enabled)
   - Navigate to: `https://your-domain.com/dashboard`
   - Login with admin credentials

## User Management

### Adding Users

#### Interactive User Creation
```bash
sudo /opt/vless/scripts/user_management.sh add
```
This will prompt for:
- Username (required)
- Email address (optional)
- Expiration date (optional)
- Traffic limit (optional)
- Additional notes (optional)

#### Quick User Creation
```bash
# Basic user
sudo /opt/vless/scripts/user_management.sh add john

# User with email
sudo /opt/vless/scripts/user_management.sh add john --email john@example.com

# User with expiration (30 days)
sudo /opt/vless/scripts/user_management.sh add john --expire 30d

# User with traffic limit (100GB)
sudo /opt/vless/scripts/user_management.sh add john --limit 100GB
```

#### Bulk User Creation
Create a file `users.txt` with user details:
```
john,john@example.com,30d,50GB
jane,jane@example.com,60d,100GB
admin,admin@example.com,365d,unlimited
```

Then import:
```bash
sudo /opt/vless/scripts/user_management.sh bulk_add users.txt
```

### Managing Existing Users

#### List All Users
```bash
# Basic list
sudo /opt/vless/scripts/user_management.sh list

# Detailed list with statistics
sudo /opt/vless/scripts/user_management.sh list --detailed

# Export user list
sudo /opt/vless/scripts/user_management.sh list --export users_export.json
```

#### Get User Information
```bash
# Basic user info
sudo /opt/vless/scripts/user_management.sh info john

# Detailed user statistics
sudo /opt/vless/scripts/user_management.sh stats john

# User connection history
sudo /opt/vless/scripts/user_management.sh history john
```

#### Modify User Settings
```bash
# Update email
sudo /opt/vless/scripts/user_management.sh update john --email newemail@example.com

# Extend expiration
sudo /opt/vless/scripts/user_management.sh update john --expire +30d

# Change traffic limit
sudo /opt/vless/scripts/user_management.sh update john --limit 200GB

# Reset user data usage
sudo /opt/vless/scripts/user_management.sh reset john --usage
```

#### Disable/Enable Users
```bash
# Temporarily disable user
sudo /opt/vless/scripts/user_management.sh disable john

# Re-enable user
sudo /opt/vless/scripts/user_management.sh enable john

# Check user status
sudo /opt/vless/scripts/user_management.sh status john
```

#### Remove Users
```bash
# Remove user (with confirmation)
sudo /opt/vless/scripts/user_management.sh remove john

# Force remove without confirmation
sudo /opt/vless/scripts/user_management.sh remove john --force

# Remove and backup user data
sudo /opt/vless/scripts/user_management.sh remove john --backup
```

### User Configuration Management

#### Generate Client Configurations
```bash
# Generate configuration for specific user
sudo /opt/vless/scripts/user_management.sh config john

# Generate QR code
sudo /opt/vless/scripts/qr_generator.py john

# Generate all formats (config + QR + links)
sudo /opt/vless/scripts/user_management.sh export john
```

#### Configuration Formats
The system supports multiple configuration formats:

1. **JSON Configuration**: Full client configuration in JSON format
2. **URI Format**: One-line configuration URI for easy sharing
3. **QR Code**: Visual QR code for mobile client scanning
4. **Config Files**: Platform-specific configuration files

#### Download Configuration Files
```bash
# Save configuration to file
sudo /opt/vless/scripts/user_management.sh config john > john_config.json

# Save QR code as image
sudo /opt/vless/scripts/qr_generator.py john --output john_qr.png

# Export user package (all formats)
sudo /opt/vless/scripts/user_management.sh package john --output john_package.zip
```

## Client Configuration

### Supported Clients

The VLESS+Reality configuration works with:

#### Desktop Clients
- **v2rayN** (Windows) - Recommended
- **v2rayNG** (Android) - Recommended
- **v2rayU** (macOS)
- **Qv2ray** (Cross-platform)
- **Clash** (with VLESS support)

#### Mobile Clients
- **v2rayNG** (Android)
- **Shadowrocket** (iOS)
- **QuantumultX** (iOS)
- **Clash** (iOS/Android)

### Client Setup Instructions

#### Windows (v2rayN)
1. Download and install v2rayN
2. Run as administrator
3. Right-click system tray icon → "Import bulk URL from clipboard"
4. Paste your configuration URI
5. Select the imported server and test connection

#### Android (v2rayNG)
1. Install v2rayNG from Google Play Store
2. Open the app
3. Tap "+" → "Import config from QR code"
4. Scan the QR code provided by the system
5. Tap the server entry to connect

#### iOS (Shadowrocket)
1. Install Shadowrocket from App Store
2. Open the app
3. Tap "+" → "Type" → "Subscribe"
4. Paste your configuration URI
5. Toggle the connection switch

#### Manual Configuration
For advanced users, manual configuration parameters:

```json
{
  "protocol": "vless",
  "settings": {
    "vnext": [
      {
        "address": "your-domain.com",
        "port": 443,
        "users": [
          {
            "id": "user-uuid",
            "encryption": "none",
            "flow": "xtls-rprx-vision"
          }
        ]
      }
    ]
  },
  "streamSettings": {
    "network": "tcp",
    "security": "reality",
    "realitySettings": {
      "serverName": "www.microsoft.com",
      "fingerprint": "chrome",
      "show": false,
      "publicKey": "reality-public-key",
      "shortId": "short-id"
    }
  }
}
```

### Connection Testing

#### Verify Client Connection
```bash
# Check active connections
sudo /opt/vless/scripts/monitoring.sh connections

# Monitor specific user
sudo /opt/vless/scripts/monitoring.sh user_activity john

# Test connection from server side
sudo /opt/vless/scripts/monitoring.sh test_user john
```

#### Troubleshoot Connection Issues
```bash
# Check server logs for user
sudo /opt/vless/scripts/monitoring.sh user_logs john

# Verify user configuration
sudo /opt/vless/scripts/user_management.sh verify john

# Test network connectivity
sudo /opt/vless/scripts/monitoring.sh test_connectivity
```

## System Administration

### Service Management

#### Start/Stop/Restart Services
```bash
# Control main VPN service
sudo systemctl start vless-vpn
sudo systemctl stop vless-vpn
sudo systemctl restart vless-vpn

# Control related services
sudo systemctl restart docker
sudo systemctl restart nginx
```

#### Service Status and Logs
```bash
# Check service status
sudo systemctl status vless-vpn

# View live logs
sudo journalctl -u vless-vpn -f

# View logs for specific time period
sudo journalctl -u vless-vpn --since "1 hour ago"

# Export logs
sudo journalctl -u vless-vpn --since "24 hours ago" > vless_logs.txt
```

### Configuration Management

#### Main Configuration Files
- `/opt/vless/config/vless.env` - Main VPN configuration
- `/opt/vless/config/xray_config.json` - Xray core configuration
- `/opt/vless/config/bot.env` - Telegram bot settings
- `/opt/vless/config/monitoring.env` - Monitoring configuration

#### Update Configuration
```bash
# Edit main configuration
sudo nano /opt/vless/config/vless.env

# Apply configuration changes
sudo /opt/vless/scripts/configure.sh reload

# Validate configuration
sudo /opt/vless/scripts/configure.sh validate
```

#### Common Configuration Changes

**Change VPN Port:**
```bash
sudo /opt/vless/scripts/configure.sh --port 8443
sudo systemctl restart vless-vpn
```

**Update Domain:**
```bash
sudo /opt/vless/scripts/configure.sh --domain new-domain.com
sudo /opt/vless/scripts/cert_management.sh renew
```

**Modify Security Settings:**
```bash
sudo /opt/vless/scripts/security_hardening.sh configure
```

### Certificate Management

#### SSL/TLS Certificates
```bash
# Check certificate status
sudo /opt/vless/scripts/cert_management.sh status

# Renew certificates
sudo /opt/vless/scripts/cert_management.sh renew

# Generate new certificates
sudo /opt/vless/scripts/cert_management.sh generate

# Setup automatic renewal
sudo /opt/vless/scripts/cert_management.sh auto_renew
```

#### Reality Key Management
```bash
# Generate new Reality keys
sudo /opt/vless/scripts/cert_management.sh reality_keys

# Rotate Reality configuration
sudo /opt/vless/scripts/cert_management.sh rotate_reality

# Update all user configurations with new keys
sudo /opt/vless/scripts/user_management.sh update_all --reality-keys
```

## Telegram Bot Usage

### Bot Setup and Configuration

#### Initial Bot Setup
1. Create bot with @BotFather on Telegram
2. Get bot token
3. Configure the bot:
   ```bash
   sudo /opt/vless/scripts/telegram_bot_manager.sh setup
   ```
4. Add yourself as admin:
   ```bash
   sudo /opt/vless/scripts/telegram_bot_manager.sh add_admin YOUR_TELEGRAM_ID
   ```

#### Bot Configuration
Edit bot settings:
```bash
sudo nano /opt/vless/config/bot.env
```

Key settings:
```bash
BOT_TOKEN=your_bot_token_here
ADMIN_USER_ID=your_telegram_id
ENABLE_NOTIFICATIONS=true
ALERT_THRESHOLD_CPU=80
ALERT_THRESHOLD_MEMORY=85
NOTIFICATION_INTERVAL=3600
```

### Bot Commands and Usage

#### Basic Commands
- `/start` - Initialize bot and show welcome message
- `/help` - Display all available commands
- `/status` - Show system status and metrics
- `/users` - User management interface
- `/settings` - Bot configuration options

#### User Management Commands
- `/adduser <username>` - Add new VPN user
- `/removeuser <username>` - Remove VPN user
- `/listusers` - Show all users with status
- `/userinfo <username>` - Get detailed user information
- `/qr <username>` - Generate and send QR code
- `/config <username>` - Get user configuration

#### System Management Commands
- `/backup` - Create system backup
- `/restore` - Restore from backup
- `/maintenance` - Enter/exit maintenance mode
- `/update` - Check for and apply updates
- `/logs` - View recent system logs
- `/restart` - Restart VPN service

#### Monitoring Commands
- `/stats` - Detailed system statistics
- `/connections` - Show active VPN connections
- `/traffic` - Traffic usage statistics
- `/alerts` - Configure system alerts
- `/health` - System health check

### Interactive Bot Interface

#### User Management Interface
```
User: /users
Bot: 👥 User Management

     Current Users: 5
     Active Connections: 3

     [➕ Add User] [📋 List Users]
     [📊 User Stats] [🔧 Settings]

User: [Clicks "Add User"]
Bot: ➕ Add New User

     Please enter username:

User: john
Bot: ✅ User 'john' created!

     📱 QR Code: [QR_CODE_IMAGE]
     📋 Config: [CONFIG_TEXT]

     [👥 Back to Users] [➕ Add Another]
```

#### System Status Interface
```
User: /status
Bot: 🖥️ System Status

     🟢 VPN Service: Running
     📊 CPU: 25% | RAM: 45% | Disk: 60%
     🌐 Active Connections: 8
     ⏱️ Uptime: 12 days, 5 hours

     [📈 Detailed Stats] [🔄 Refresh]
     [⚙️ Settings] [🛠️ Maintenance]
```

### Bot Notifications and Alerts

#### Automatic Notifications
The bot can send automatic notifications for:
- New user connections
- System alerts (high CPU, memory, disk usage)
- Service failures or restarts
- Backup completion
- Security events

#### Configure Notifications
```bash
# Enable all notifications
sudo /opt/vless/scripts/telegram_bot_manager.sh notifications enable

# Configure specific alerts
sudo /opt/vless/scripts/telegram_bot_manager.sh alerts \
  --cpu-threshold 80 \
  --memory-threshold 85 \
  --disk-threshold 90

# Set notification intervals
sudo /opt/vless/scripts/telegram_bot_manager.sh notifications \
  --interval 3600 --quiet-hours "22:00-08:00"
```

## Monitoring and Maintenance

### System Monitoring

#### Real-time Monitoring
```bash
# Monitor system in real-time
sudo /opt/vless/scripts/monitoring.sh monitor

# Monitor with specific intervals
sudo /opt/vless/scripts/monitoring.sh monitor --interval 30

# Monitor specific metrics
sudo /opt/vless/scripts/monitoring.sh monitor --cpu --memory --disk
```

#### Performance Metrics
```bash
# Generate performance report
sudo /opt/vless/scripts/monitoring.sh report

# Historical performance data
sudo /opt/vless/scripts/monitoring.sh history --period 7d

# Export metrics for analysis
sudo /opt/vless/scripts/monitoring.sh export --format csv --period 30d
```

#### Connection Monitoring
```bash
# Monitor active VPN connections
sudo /opt/vless/scripts/monitoring.sh connections

# User activity monitoring
sudo /opt/vless/scripts/monitoring.sh user_activity

# Traffic analysis
sudo /opt/vless/scripts/monitoring.sh traffic --detailed
```

### System Maintenance

#### Routine Maintenance
```bash
# Enter maintenance mode
sudo /opt/vless/scripts/maintenance_utils.sh enable_maintenance_mode

# Perform system optimization
sudo /opt/vless/scripts/maintenance_utils.sh optimize_system

# Clean up logs and temporary files
sudo /opt/vless/scripts/maintenance_utils.sh cleanup

# Exit maintenance mode
sudo /opt/vless/scripts/maintenance_utils.sh disable_maintenance_mode
```

#### Health Checks
```bash
# Comprehensive system health check
sudo /opt/vless/scripts/maintenance_utils.sh check_system_health

# Generate diagnostic report
sudo /opt/vless/scripts/maintenance_utils.sh generate_diagnostics

# Verify all components
sudo /opt/vless/scripts/maintenance_utils.sh verify_installation
```

#### Log Management
```bash
# Rotate logs
sudo /opt/vless/scripts/maintenance_utils.sh rotate_logs

# Archive old logs
sudo /opt/vless/scripts/maintenance_utils.sh archive_logs

# Clean up log files
sudo /opt/vless/scripts/maintenance_utils.sh cleanup_logs --older-than 30d
```

### Backup and Recovery

#### Manual Backups
```bash
# Create full system backup
sudo /opt/vless/scripts/backup_restore.sh create_full_backup

# Create configuration backup only
sudo /opt/vless/scripts/backup_restore.sh create_config_backup

# Create user data backup only
sudo /opt/vless/scripts/backup_restore.sh create_users_backup
```

#### Automated Backup Setup
```bash
# Setup daily backups at 2 AM
sudo /opt/vless/scripts/backup_restore.sh schedule_backups \
  --daily --time "02:00" --retention 30d

# Setup weekly backups on Sunday
sudo /opt/vless/scripts/backup_restore.sh schedule_backups \
  --weekly --day sunday --time "03:00" --retention 12w
```

#### Restore Operations
```bash
# List available backups
sudo /opt/vless/scripts/backup_restore.sh list_backups

# Restore from specific backup
sudo /opt/vless/scripts/backup_restore.sh restore \
  --backup backup_20231201_120000.tar.gz

# Verify backup before restore
sudo /opt/vless/scripts/backup_restore.sh verify \
  --backup backup_20231201_120000.tar.gz
```

### Update Management

#### System Updates
```bash
# Check for available updates
sudo /opt/vless/scripts/system_update.sh check_updates

# Apply system updates
sudo /opt/vless/scripts/system_update.sh apply_updates

# Apply security updates only
sudo /opt/vless/scripts/system_update.sh security_updates
```

#### Xray Core Updates
```bash
# Check for Xray core updates
sudo /opt/vless/scripts/system_update.sh check_xray_updates

# Update Xray core
sudo /opt/vless/scripts/system_update.sh update_xray

# Rollback to previous version
sudo /opt/vless/scripts/system_update.sh rollback_xray
```

## Advanced Configuration

### Custom Xray Configuration

#### Configuration Templates
Create custom configuration templates in `/opt/vless/config/templates/`:

```json
{
  "log": {
    "loglevel": "warning",
    "access": "/opt/vless/logs/access.log",
    "error": "/opt/vless/logs/error.log"
  },
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "www.microsoft.com:443",
          "xver": 0,
          "serverNames": ["www.microsoft.com"],
          "privateKey": "PRIVATE_KEY_HERE",
          "shortIds": ["SHORT_ID_HERE"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
```

#### Apply Custom Configuration
```bash
# Validate custom configuration
sudo /opt/vless/scripts/configure.sh validate --config custom_config.json

# Apply custom configuration
sudo /opt/vless/scripts/configure.sh apply --config custom_config.json

# Backup current config and apply new one
sudo /opt/vless/scripts/configure.sh apply --config custom_config.json --backup
```

### Network Optimization

#### TCP Optimization
```bash
# Apply network optimizations
sudo /opt/vless/scripts/maintenance_utils.sh optimize_network

# Configure TCP settings
echo 'net.core.default_qdisc=fq' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_congestion_control=bbr' >> /etc/sysctl.conf
sudo sysctl -p
```

#### Firewall Configuration
```bash
# Configure advanced firewall rules
sudo /opt/vless/scripts/ufw_config.sh advanced_setup

# Add custom firewall rules
sudo /opt/vless/scripts/ufw_config.sh add_rule --port 8080 --protocol tcp

# Configure port forwarding
sudo /opt/vless/scripts/ufw_config.sh port_forward --from 80 --to 8080
```

### Multi-Domain Setup

#### Configure Multiple Domains
```bash
# Add additional domain
sudo /opt/vless/scripts/configure.sh add_domain --domain vpn2.example.com

# Configure domain-specific certificates
sudo /opt/vless/scripts/cert_management.sh setup_domain --domain vpn2.example.com

# Update DNS records
sudo /opt/vless/scripts/configure.sh update_dns --domain vpn2.example.com
```

### Load Balancing

#### Configure Load Balancing
```bash
# Setup load balancer
sudo /opt/vless/scripts/configure.sh load_balancer --enable

# Add backend servers
sudo /opt/vless/scripts/configure.sh add_backend --server 192.168.1.100
sudo /opt/vless/scripts/configure.sh add_backend --server 192.168.1.101

# Configure health checks
sudo /opt/vless/scripts/configure.sh health_check --interval 30 --timeout 5
```

## Best Practices

### Security Best Practices

1. **Regular Updates**
   - Enable automatic security updates
   - Monitor for Xray core updates
   - Keep system packages current

2. **User Management**
   - Use strong, unique usernames
   - Set appropriate expiration dates
   - Monitor user activity regularly
   - Remove unused accounts promptly

3. **Access Control**
   - Limit admin access to trusted users
   - Use Telegram bot for remote management
   - Implement IP whitelisting for admin access
   - Enable two-factor authentication where possible

4. **Monitoring**
   - Set up alerts for unusual activity
   - Monitor resource usage trends
   - Review logs regularly
   - Implement automated health checks

### Performance Optimization

1. **Resource Management**
   - Monitor CPU and memory usage
   - Optimize Xray configuration for your use case
   - Use appropriate server specifications
   - Implement resource limits for users

2. **Network Optimization**
   - Enable BBR congestion control
   - Optimize TCP settings
   - Use CDN for static content
   - Monitor bandwidth usage

3. **Storage Management**
   - Implement log rotation
   - Clean up old backups regularly
   - Monitor disk usage
   - Use compression for backups

### Backup and Recovery Best Practices

1. **Backup Strategy**
   - Implement 3-2-1 backup rule
   - Test restore procedures regularly
   - Store backups in multiple locations
   - Encrypt sensitive backup data

2. **Recovery Planning**
   - Document recovery procedures
   - Test disaster recovery scenarios
   - Maintain emergency contact information
   - Keep offline copies of critical configurations

### Operational Best Practices

1. **Documentation**
   - Keep configuration changes documented
   - Maintain user management records
   - Document custom modifications
   - Update contact information regularly

2. **Change Management**
   - Test changes in staging environment
   - Implement gradual rollouts
   - Maintain rollback procedures
   - Schedule maintenance windows

3. **Monitoring and Alerting**
   - Set appropriate alert thresholds
   - Implement escalation procedures
   - Monitor key performance indicators
   - Review and adjust alerts regularly

---

This user guide provides comprehensive information for managing your VLESS+Reality VPN system. For additional help, refer to the troubleshooting guide or contact support through the appropriate channels.