# User Guide

Complete user manual for the VLESS+Reality VPN Management System.

## Table of Contents

1. [Getting Started](#getting-started)
2. [Installation Modes](#installation-modes)
3. [Safety Features](#safety-features)
4. [User Management](#user-management)
5. [Client Configuration](#client-configuration)
6. [Monitoring and Analytics](#monitoring-and-analytics)
7. [Backup and Recovery](#backup-and-recovery)
8. [Advanced Configuration](#advanced-configuration)
9. [Best Practices](#best-practices)

## Getting Started

### First Time Setup

After installation, you'll need to perform initial configuration:

1. **Access the System**
   ```bash
   # Switch to root user
   sudo su -

   # Navigate to system directory
   cd /opt/vless
   ```

2. **Create Your First User**
   ```bash
   # Create an admin user
   ./scripts/user_management.sh add admin --role=admin

   # Create a regular user
   ./scripts/user_management.sh add john_doe
   ```

3. **Generate Client Configuration**
   ```bash
   # Generate configuration for user
   ./scripts/user_management.sh config john_doe

   # Generate QR code for mobile apps
   ./scripts/user_management.sh qr john_doe
   ```

### System Overview

The VLESS+Reality VPN system provides:
- **Secure VPN Access**: Using VLESS protocol with Reality obfuscation
- **User Management**: Complete user lifecycle management
- **Monitoring**: Real-time system and user monitoring
- **Backup**: Automated backup and recovery capabilities
- **Maintenance**: Comprehensive system maintenance utilities

### Command Line Interface

All system operations can be performed via command line scripts located in `/opt/vless/scripts/`:

- `user_management.sh` - User operations
- `monitoring.sh` - System monitoring
- `backup_restore.sh` - Backup operations
- `security_hardening.sh` - Security management
- `maintenance_utils.sh` - System maintenance

## Installation Modes

The system supports three installation modes optimized for different use cases. Understanding your installation mode helps you use the appropriate features and troubleshoot issues.

### Checking Your Installation Mode

```bash
# Check current installation configuration
source /opt/vless/config/environment.conf
echo "Installation Mode: ${INSTALLATION_MODE:-unknown}"
echo "Backup Profile: ${BACKUP_PROFILE:-default}"
echo "Monitoring Profile: ${MONITORING_PROFILE:-default}"
```

### Mode-Specific Features

#### Minimal Mode
```bash
# Available commands in minimal mode
/opt/vless/scripts/user_management.sh    # User operations
/opt/vless/scripts/monitoring.sh status  # Basic status check
```

#### Balanced Mode
```bash
# Additional commands in balanced mode
/opt/vless/scripts/security_hardening.sh  # Security management
/opt/vless/scripts/monitoring.sh metrics  # System metrics
/opt/vless/scripts/backup_restore.sh      # Backup operations
```

#### Full Mode
```bash
# All commands available
/opt/vless/scripts/backup_restore.sh        # Backup operations
/opt/vless/scripts/maintenance_utils.sh     # Maintenance tools
# Plus all minimal and balanced mode features
```

## Safety Features

The system includes comprehensive safety mechanisms to prevent operational issues and system lockouts.

### SSH Hardening Safety

Before applying SSH hardening, the system automatically:

1. **Validates SSH Keys**: Ensures you have SSH key authentication configured
2. **Shows Current Connections**: Displays active SSH sessions
3. **Creates Restore Points**: Backs up current configuration
4. **Tests Configuration**: Validates SSH config before applying

```bash
# Manual SSH safety check
source /opt/vless/modules/safety_utils.sh
check_ssh_keys
show_current_ssh_connections
create_restore_point "before_ssh_hardening"
```

### System State Validation

Critical operations include automatic validation:

```bash
# Check system state before operations
validate_system_state "ssh_hardening"
validate_system_state "firewall_config"
validate_system_state "service_restart"
```

### Confirmation System

Interactive confirmations with timeout protection:

```bash
# Enhanced confirmation (30-second timeout, default 'no')
confirm_action "Apply security hardening?" "n" 30

# Safe service restart with confirmation
safe_service_restart "sshd" 30 false
```

### Rollback and Recovery

**Automatic Restore Points**:
- Created before major configuration changes
- Stored in `/opt/vless/restore_points/`
- Include restore scripts for quick recovery

```bash
# List available restore points
ls -la /opt/vless/restore_points/

# Execute restore (example)
sudo /opt/vless/restore_points/20250923_143022_ssh_hardening/restore.sh
```

**Manual Rollback**:
```bash
# Backup current firewall rules
backup_current_firewall_rules

# Create comprehensive restore point
create_restore_point "manual_backup"
```

## User Management

### Adding Users

#### Basic User Creation
```bash
# Create a standard user
./scripts/user_management.sh add username

# Create user with specific quota (in GB)
./scripts/user_management.sh add username --quota=50

# Create user with expiration date
./scripts/user_management.sh add username --expires="2024-12-31"

# Create admin user
./scripts/user_management.sh add username --role=admin
```

#### Advanced User Creation
```bash
# Create user with custom settings
./scripts/user_management.sh add username \
  --quota=100 \
  --expires="2024-12-31" \
  --max-connections=5 \
  --description="John Doe - Marketing Team"
```

### Managing Existing Users

#### View Users
```bash
# List all users
./scripts/user_management.sh list

# Show detailed user information
./scripts/user_management.sh info username

# Show user statistics
./scripts/user_management.sh stats username
```

#### Modify Users
```bash
# Update user quota
./scripts/user_management.sh modify username --quota=200

# Extend expiration date
./scripts/user_management.sh modify username --expires="2025-06-30"

# Change user role
./scripts/user_management.sh modify username --role=admin

# Update description
./scripts/user_management.sh modify username --description="Updated info"
```

#### User Status Management
```bash
# Disable user temporarily
./scripts/user_management.sh disable username

# Enable disabled user
./scripts/user_management.sh enable username

# Reset user traffic usage
./scripts/user_management.sh reset-traffic username

# Reset user password/key
./scripts/user_management.sh reset-key username
```

#### Remove Users
```bash
# Delete user (with confirmation)
./scripts/user_management.sh delete username

# Force delete without confirmation
./scripts/user_management.sh delete username --force

# Delete expired users
./scripts/user_management.sh cleanup-expired
```

### User Quotas and Limits

#### Traffic Quotas
```bash
# Set monthly quota (in GB)
./scripts/user_management.sh modify username --quota=50

# Set unlimited quota
./scripts/user_management.sh modify username --quota=unlimited

# Check quota usage
./scripts/user_management.sh quota username
```

#### Connection Limits
```bash
# Set maximum simultaneous connections
./scripts/user_management.sh modify username --max-connections=3

# View current connections
./scripts/user_management.sh connections username
```

#### Time-based Restrictions
```bash
# Set account expiration
./scripts/user_management.sh modify username --expires="2024-12-31"

# Set access schedule (optional feature)
./scripts/user_management.sh modify username --schedule="09:00-17:00"
```

## Client Configuration

### Generating Configuration Files

#### Standard Configuration
```bash
# Generate JSON configuration
./scripts/user_management.sh config username

# Generate configuration with custom server name
./scripts/user_management.sh config username --server="vpn.yourdomain.com"

# Generate configuration for specific client
./scripts/user_management.sh config username --client="v2rayN"
```

#### QR Code Generation
```bash
# Generate QR code for mobile apps
./scripts/user_management.sh qr username

# Save QR code to file
./scripts/user_management.sh qr username --output="/tmp/username_qr.png"

# Generate QR with custom size
./scripts/user_management.sh qr username --size=512
```

### Client-Specific Configurations

#### v2rayN (Windows)
```bash
# Generate v2rayN configuration
./scripts/user_management.sh config username --client="v2rayN"
```

Configuration will include:
- Server address and port
- User ID and encryption
- Reality settings
- Transport configuration

#### v2rayNG (Android)
```bash
# Generate QR code for scanning
./scripts/user_management.sh qr username --client="v2rayNG"
```

#### iOS Clients (Shadowrocket, FairVPN)
```bash
# Generate iOS-compatible configuration
./scripts/user_management.sh config username --client="iOS"
```

#### Qv2ray (Linux/macOS)
```bash
# Generate Qv2ray configuration
./scripts/user_management.sh config username --client="qv2ray"
```

### Manual Client Setup

If automatic configuration generation isn't available for your client, use these settings:

```json
{
  "protocol": "vless",
  "settings": {
    "vnext": [
      {
        "address": "YOUR_SERVER_IP",
        "port": 443,
        "users": [
          {
            "id": "USER_UUID",
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
      "shortId": "SHORT_ID",
      "publicKey": "PUBLIC_KEY"
    }
  }
}
```


## Monitoring and Analytics

### System Monitoring

#### Real-time Status
```bash
# System overview
./scripts/monitoring.sh status

# Detailed system info
./scripts/monitoring.sh info

# Resource usage
./scripts/monitoring.sh resources
```

#### Service Monitoring
```bash
# Check all services
./scripts/monitoring.sh services

# Check specific service
./scripts/monitoring.sh check xray

# Service logs
./scripts/monitoring.sh logs xray
```

### Traffic Analytics

#### User Traffic
```bash
# All users traffic summary
./scripts/monitoring.sh traffic

# Specific user traffic
./scripts/monitoring.sh traffic username

# Traffic by date range
./scripts/monitoring.sh traffic --from="2024-01-01" --to="2024-01-31"
```

#### System Performance
```bash
# Performance metrics
./scripts/monitoring.sh performance

# Network statistics
./scripts/monitoring.sh network

# Connection statistics
./scripts/monitoring.sh connections
```

### Alerts and Notifications

#### Configure Alerts
```bash
# Setup email alerts
./scripts/monitoring.sh setup-alerts --email="admin@domain.com"

# Configure thresholds
./scripts/monitoring.sh set-threshold cpu 80
./scripts/monitoring.sh set-threshold memory 90
./scripts/monitoring.sh set-threshold disk 85
```

#### Alert Types
- High CPU usage
- Memory exhaustion
- Disk space low
- Service failures
- Security events
- User quota exceeded

## Backup and Recovery

### Creating Backups

#### Manual Backup
```bash
# Full system backup
./scripts/backup_restore.sh backup

# Configuration-only backup
./scripts/backup_restore.sh backup --config-only

# User data backup
./scripts/backup_restore.sh backup --users-only
```

#### Automated Backups
```bash
# Schedule daily backups
./scripts/backup_restore.sh schedule daily

# Schedule weekly backups
./scripts/backup_restore.sh schedule weekly

# Set backup retention
./scripts/backup_restore.sh retention 30
```

### Restoring from Backup

#### Full Restoration
```bash
# Restore complete system
./scripts/backup_restore.sh restore /path/to/backup.tar.gz

# Restore with verification
./scripts/backup_restore.sh restore /path/to/backup.tar.gz --verify
```

#### Selective Restoration
```bash
# Restore only configuration
./scripts/backup_restore.sh restore /path/to/backup.tar.gz --config-only

# Restore only user data
./scripts/backup_restore.sh restore /path/to/backup.tar.gz --users-only
```

### Backup Storage

#### Local Storage
Backups are stored in `/opt/vless/backup/` by default.

#### Remote Storage (Optional)
```bash
# Configure remote backup storage
./scripts/backup_restore.sh configure-remote \
  --type="s3" \
  --bucket="your-backup-bucket" \
  --region="us-east-1"

# Upload backup to remote storage
./scripts/backup_restore.sh upload backup_file.tar.gz
```

## Advanced Configuration

### Custom Reality Settings

#### Configure Reality Domain
```bash
# Set custom reality domain
./scripts/config_management.sh set reality-domain "www.cloudflare.com"

# Set multiple reality domains
./scripts/config_management.sh set reality-domains \
  "www.microsoft.com,www.apple.com,www.google.com"
```

#### Reality Fingerprint
```bash
# Set browser fingerprint
./scripts/config_management.sh set fingerprint chrome

# Available fingerprints: chrome, firefox, safari, edge
```

### Network Configuration

#### Port Configuration
```bash
# Change VLESS port
./scripts/config_management.sh set port 8443

# Add alternative ports
./scripts/config_management.sh add-port 2053
```

#### Multi-Domain Setup
```bash
# Add multiple server domains
./scripts/config_management.sh add-domain "vpn1.yourdomain.com"
./scripts/config_management.sh add-domain "vpn2.yourdomain.com"
```

### Performance Tuning

#### Connection Limits
```bash
# Set global connection limits
./scripts/config_management.sh set max-connections 1000

# Set per-user limits
./scripts/config_management.sh set user-max-connections 10
```

#### Buffer Sizes
```bash
# Optimize buffer sizes for performance
./scripts/config_management.sh set read-buffer 32768
./scripts/config_management.sh set write-buffer 32768
```

### Security Hardening

#### Additional Security Measures
```bash
# Enable additional security features
./scripts/security_hardening.sh enable fail2ban
./scripts/security_hardening.sh enable port-knocking
./scripts/security_hardening.sh enable geo-blocking

# Configure allowed countries
./scripts/security_hardening.sh set allowed-countries "US,CA,GB"
```

## Best Practices

### User Management
1. **Regular Cleanup**: Remove expired and unused accounts
2. **Quota Management**: Set appropriate quotas based on usage patterns
3. **Access Control**: Use admin roles for administrative users
4. **Documentation**: Maintain user descriptions and contact information

### Security
1. **Regular Updates**: Keep system and dependencies updated
2. **Monitor Logs**: Review security and access logs regularly
3. **Backup Verification**: Test backup restoration procedures
4. **Access Restriction**: Limit admin access to trusted users only

### Performance
1. **Resource Monitoring**: Monitor CPU, memory, and network usage
2. **Connection Limits**: Set appropriate connection limits
3. **Log Rotation**: Configure log rotation to prevent disk space issues
4. **Regular Maintenance**: Perform routine system maintenance

### Troubleshooting
1. **Log Analysis**: Check system and service logs for errors
2. **Network Testing**: Verify network connectivity and port accessibility
3. **Service Status**: Ensure all required services are running
4. **Configuration Validation**: Verify configuration file syntax

---

**Next Steps**: For technical details and API documentation, see the [API Reference](api_reference.md). For troubleshooting assistance, consult the [Troubleshooting Guide](troubleshooting.md).