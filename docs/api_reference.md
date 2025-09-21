# VLESS+Reality VPN Management System - API Reference

This comprehensive API reference covers all available commands, scripts, and programmatic interfaces for the VLESS+Reality VPN Management System.

## Table of Contents

- [Command Line Interface](#command-line-interface)
- [Script Reference](#script-reference)
- [REST API](#rest-api)
- [Telegram Bot API](#telegram-bot-api)
- [Configuration Files](#configuration-files)
- [Exit Codes and Return Values](#exit-codes-and-return-values)
- [Environment Variables](#environment-variables)
- [Examples and Use Cases](#examples-and-use-cases)

## Command Line Interface

### Main Installation Script

#### `install.sh`

Primary installation script for the VLESS+Reality VPN Management System.

**Syntax:**
```bash
sudo ./install.sh [OPTIONS]
```

**Options:**
| Option | Description | Default |
|--------|-------------|---------|
| `-h, --help` | Show help message | |
| `-v, --verbose` | Enable verbose output | false |
| `-d, --dry-run` | Perform dry run without making changes | false |
| `-f, --force` | Force installation (skip confirmations) | false |
| `-c, --config FILE` | Use custom configuration file | |
| `--skip-deps` | Skip dependency installation | false |
| `--skip-docker` | Skip Docker installation | false |
| `--skip-security` | Skip security hardening | false |
| `--phase PHASE` | Run specific installation phase | |
| `--container-only` | Install only Docker components | false |
| `--dev-mode` | Enable development mode | false |

**Examples:**
```bash
# Standard installation
sudo ./install.sh

# Verbose installation with custom config
sudo ./install.sh --verbose --config /path/to/config.env

# Dry run to preview changes
sudo ./install.sh --dry-run

# Force installation skipping confirmations
sudo ./install.sh --force

# Run specific phase only
sudo ./install.sh --phase install_dependencies
```

**Exit Codes:**
- `0` - Success
- `1` - General error
- `2` - Invalid arguments
- `3` - Permission denied
- `4` - Environment validation failed
- `5` - Installation phase failed

## Script Reference

### User Management

#### `user_management.sh`

Comprehensive user management script for VPN users.

**Location:** `/opt/vless/scripts/user_management.sh`

**Syntax:**
```bash
sudo /opt/vless/scripts/user_management.sh COMMAND [OPTIONS]
```

**Commands:**

##### `add` - Add New User
```bash
sudo /opt/vless/scripts/user_management.sh add [USERNAME] [OPTIONS]
```

**Options:**
| Option | Description | Example |
|--------|-------------|---------|
| `--email EMAIL` | User email address | `--email user@example.com` |
| `--expire DURATION` | Account expiration | `--expire 30d` |
| `--limit SIZE` | Traffic limit | `--limit 100GB` |
| `--notes TEXT` | Additional notes | `--notes "VIP user"` |

**Examples:**
```bash
# Interactive user creation
sudo /opt/vless/scripts/user_management.sh add

# Quick user creation
sudo /opt/vless/scripts/user_management.sh add john

# User with options
sudo /opt/vless/scripts/user_management.sh add john \
  --email john@example.com \
  --expire 30d \
  --limit 50GB
```

##### `list` - List Users
```bash
sudo /opt/vless/scripts/user_management.sh list [OPTIONS]
```

**Options:**
| Option | Description |
|--------|-------------|
| `--detailed` | Show detailed information |
| `--active` | Show only active users |
| `--expired` | Show only expired users |
| `--format FORMAT` | Output format (table, json, csv) |
| `--export FILE` | Export to file |

**Examples:**
```bash
# Basic list
sudo /opt/vless/scripts/user_management.sh list

# Detailed list
sudo /opt/vless/scripts/user_management.sh list --detailed

# Export to JSON
sudo /opt/vless/scripts/user_management.sh list --format json --export users.json
```

##### `remove` - Remove User
```bash
sudo /opt/vless/scripts/user_management.sh remove USERNAME [OPTIONS]
```

**Options:**
| Option | Description |
|--------|-------------|
| `--force` | Skip confirmation |
| `--backup` | Backup user data before removal |

##### `update` - Update User
```bash
sudo /opt/vless/scripts/user_management.sh update USERNAME [OPTIONS]
```

**Options:**
| Option | Description | Example |
|--------|-------------|---------|
| `--email EMAIL` | Update email | `--email new@example.com` |
| `--expire DURATION` | Update expiration | `--expire +30d` |
| `--limit SIZE` | Update traffic limit | `--limit 200GB` |
| `--enable` | Enable user account | |
| `--disable` | Disable user account | |

##### `config` - Generate Configuration
```bash
sudo /opt/vless/scripts/user_management.sh config USERNAME [OPTIONS]
```

**Options:**
| Option | Description |
|--------|-------------|
| `--format FORMAT` | Output format (json, uri, qr) |
| `--output FILE` | Save to file |

##### `info` - Get User Information
```bash
sudo /opt/vless/scripts/user_management.sh info USERNAME [OPTIONS]
```

**Options:**
| Option | Description |
|--------|-------------|
| `--stats` | Include usage statistics |
| `--history` | Include connection history |

##### `bulk_add` - Bulk User Creation
```bash
sudo /opt/vless/scripts/user_management.sh bulk_add FILE [OPTIONS]
```

**File Format (CSV):**
```csv
username,email,expire_days,limit_gb,notes
john,john@example.com,30,50,Regular user
jane,jane@example.com,60,100,VIP user
admin,admin@example.com,365,unlimited,Administrator
```

### QR Code Generation

#### `qr_generator.py`

Generate QR codes for user configurations.

**Location:** `/opt/vless/scripts/qr_generator.py`

**Syntax:**
```bash
sudo /opt/vless/scripts/qr_generator.py USERNAME [OPTIONS]
```

**Options:**
| Option | Description | Default |
|--------|-------------|---------|
| `--output FILE` | Output file path | Display to terminal |
| `--format FORMAT` | Image format (png, jpg, svg) | png |
| `--size SIZE` | QR code size in pixels | 300 |
| `--border SIZE` | Border size | 4 |

**Examples:**
```bash
# Display QR code in terminal
sudo /opt/vless/scripts/qr_generator.py john

# Save QR code as image
sudo /opt/vless/scripts/qr_generator.py john --output john_qr.png

# Generate SVG format
sudo /opt/vless/scripts/qr_generator.py john --format svg --output john_qr.svg
```

### System Monitoring

#### `monitoring.sh`

System and VPN monitoring script.

**Location:** `/opt/vless/scripts/monitoring.sh`

**Syntax:**
```bash
sudo /opt/vless/scripts/monitoring.sh COMMAND [OPTIONS]
```

**Commands:**

##### `status` - System Status
```bash
sudo /opt/vless/scripts/monitoring.sh status [OPTIONS]
```

**Options:**
| Option | Description |
|--------|-------------|
| `--detailed` | Show detailed status |
| `--json` | Output in JSON format |

##### `monitor` - Real-time Monitoring
```bash
sudo /opt/vless/scripts/monitoring.sh monitor [OPTIONS]
```

**Options:**
| Option | Description | Default |
|--------|-------------|---------|
| `--interval SECONDS` | Update interval | 5 |
| `--cpu` | Monitor CPU only | false |
| `--memory` | Monitor memory only | false |
| `--disk` | Monitor disk only | false |
| `--network` | Monitor network only | false |

##### `connections` - Active Connections
```bash
sudo /opt/vless/scripts/monitoring.sh connections [OPTIONS]
```

**Options:**
| Option | Description |
|--------|-------------|
| `--user USERNAME` | Filter by user |
| `--detailed` | Show detailed connection info |

##### `report` - Generate Report
```bash
sudo /opt/vless/scripts/monitoring.sh report [OPTIONS]
```

**Options:**
| Option | Description | Default |
|--------|-------------|---------|
| `--period DURATION` | Report period | 24h |
| `--format FORMAT` | Output format (text, json, html, pdf) | text |
| `--output FILE` | Save to file | |

##### `alerts` - Configure Alerts
```bash
sudo /opt/vless/scripts/monitoring.sh alerts [OPTIONS]
```

**Options:**
| Option | Description | Default |
|--------|-------------|---------|
| `--cpu-threshold PERCENT` | CPU alert threshold | 80 |
| `--memory-threshold PERCENT` | Memory alert threshold | 85 |
| `--disk-threshold PERCENT` | Disk alert threshold | 90 |
| `--enable` | Enable alerting | |
| `--disable` | Disable alerting | |

### Backup and Restore

#### `backup_restore.sh`

Backup and restore operations.

**Location:** `/opt/vless/scripts/backup_restore.sh`

**Syntax:**
```bash
sudo /opt/vless/scripts/backup_restore.sh COMMAND [OPTIONS]
```

**Commands:**

##### `create_full_backup` - Full System Backup
```bash
sudo /opt/vless/scripts/backup_restore.sh create_full_backup [OPTIONS]
```

**Options:**
| Option | Description | Default |
|--------|-------------|---------|
| `--output PATH` | Backup location | `/opt/vless/backups/` |
| `--compress` | Compress backup | true |
| `--encrypt` | Encrypt backup | false |
| `--retention DURATION` | Retention period | 30d |

##### `create_config_backup` - Configuration Backup
```bash
sudo /opt/vless/scripts/backup_restore.sh create_config_backup [OPTIONS]
```

##### `create_users_backup` - Users Backup
```bash
sudo /opt/vless/scripts/backup_restore.sh create_users_backup [OPTIONS]
```

##### `restore` - Restore from Backup
```bash
sudo /opt/vless/scripts/backup_restore.sh restore [OPTIONS]
```

**Options:**
| Option | Description |
|--------|-------------|
| `--backup FILE` | Backup file to restore |
| `--verify` | Verify backup before restore |
| `--force` | Force restore without confirmation |

##### `list_backups` - List Available Backups
```bash
sudo /opt/vless/scripts/backup_restore.sh list_backups [OPTIONS]
```

##### `schedule_backups` - Schedule Automatic Backups
```bash
sudo /opt/vless/scripts/backup_restore.sh schedule_backups [OPTIONS]
```

**Options:**
| Option | Description | Example |
|--------|-------------|---------|
| `--daily` | Daily backup | |
| `--weekly` | Weekly backup | |
| `--time TIME` | Backup time | `--time "02:00"` |
| `--retention DURATION` | Retention period | `--retention 30d` |

### Certificate Management

#### `cert_management.sh`

SSL/TLS and Reality certificate management.

**Location:** `/opt/vless/scripts/cert_management.sh`

**Syntax:**
```bash
sudo /opt/vless/scripts/cert_management.sh COMMAND [OPTIONS]
```

**Commands:**

##### `status` - Certificate Status
```bash
sudo /opt/vless/scripts/cert_management.sh status
```

##### `generate` - Generate Certificates
```bash
sudo /opt/vless/scripts/cert_management.sh generate [OPTIONS]
```

**Options:**
| Option | Description |
|--------|-------------|
| `--domain DOMAIN` | Domain name |
| `--email EMAIL` | Contact email |
| `--force` | Force regeneration |

##### `renew` - Renew Certificates
```bash
sudo /opt/vless/scripts/cert_management.sh renew [OPTIONS]
```

##### `auto_renew` - Setup Automatic Renewal
```bash
sudo /opt/vless/scripts/cert_management.sh auto_renew
```

##### `reality_keys` - Generate Reality Keys
```bash
sudo /opt/vless/scripts/cert_management.sh reality_keys
```

### System Maintenance

#### `maintenance_utils.sh`

System maintenance and utilities.

**Location:** `/opt/vless/scripts/maintenance_utils.sh`

**Syntax:**
```bash
sudo /opt/vless/scripts/maintenance_utils.sh COMMAND [OPTIONS]
```

**Commands:**

##### `enable_maintenance_mode` - Enable Maintenance Mode
```bash
sudo /opt/vless/scripts/maintenance_utils.sh enable_maintenance_mode
```

##### `disable_maintenance_mode` - Disable Maintenance Mode
```bash
sudo /opt/vless/scripts/maintenance_utils.sh disable_maintenance_mode
```

##### `cleanup` - System Cleanup
```bash
sudo /opt/vless/scripts/maintenance_utils.sh cleanup [OPTIONS]
```

**Options:**
| Option | Description |
|--------|-------------|
| `--logs` | Clean log files |
| `--temp` | Clean temporary files |
| `--cache` | Clean cache files |
| `--all` | Clean everything |

##### `optimize_system` - System Optimization
```bash
sudo /opt/vless/scripts/maintenance_utils.sh optimize_system
```

##### `check_system_health` - Health Check
```bash
sudo /opt/vless/scripts/maintenance_utils.sh check_system_health
```

##### `generate_diagnostics` - Generate Diagnostics
```bash
sudo /opt/vless/scripts/maintenance_utils.sh generate_diagnostics [OPTIONS]
```

**Options:**
| Option | Description |
|--------|-------------|
| `--output FILE` | Output file |
| `--include-logs` | Include log files |

### System Updates

#### `system_update.sh`

System and component updates.

**Location:** `/opt/vless/scripts/system_update.sh`

**Syntax:**
```bash
sudo /opt/vless/scripts/system_update.sh COMMAND [OPTIONS]
```

**Commands:**

##### `check_updates` - Check for Updates
```bash
sudo /opt/vless/scripts/system_update.sh check_updates
```

##### `apply_updates` - Apply Updates
```bash
sudo /opt/vless/scripts/system_update.sh apply_updates [OPTIONS]
```

**Options:**
| Option | Description |
|--------|-------------|
| `--security-only` | Apply security updates only |
| `--dry-run` | Show what would be updated |
| `--auto-reboot` | Automatically reboot if needed |

##### `update_xray` - Update Xray Core
```bash
sudo /opt/vless/scripts/system_update.sh update_xray [OPTIONS]
```

##### `rollback` - Rollback Updates
```bash
sudo /opt/vless/scripts/system_update.sh rollback [OPTIONS]
```

### Telegram Bot Management

#### `telegram_bot_manager.sh`

Telegram bot management script.

**Location:** `/opt/vless/scripts/telegram_bot_manager.sh`

**Syntax:**
```bash
sudo /opt/vless/scripts/telegram_bot_manager.sh COMMAND [OPTIONS]
```

**Commands:**

##### `setup` - Initial Bot Setup
```bash
sudo /opt/vless/scripts/telegram_bot_manager.sh setup
```

##### `start` - Start Bot Service
```bash
sudo /opt/vless/scripts/telegram_bot_manager.sh start
```

##### `stop` - Stop Bot Service
```bash
sudo /opt/vless/scripts/telegram_bot_manager.sh stop
```

##### `restart` - Restart Bot Service
```bash
sudo /opt/vless/scripts/telegram_bot_manager.sh restart
```

##### `add_admin` - Add Admin User
```bash
sudo /opt/vless/scripts/telegram_bot_manager.sh add_admin TELEGRAM_ID
```

##### `remove_admin` - Remove Admin User
```bash
sudo /opt/vless/scripts/telegram_bot_manager.sh remove_admin TELEGRAM_ID
```

##### `notifications` - Configure Notifications
```bash
sudo /opt/vless/scripts/telegram_bot_manager.sh notifications [COMMAND] [OPTIONS]
```

**Notification Commands:**
| Command | Description |
|---------|-------------|
| `enable` | Enable notifications |
| `disable` | Disable notifications |
| `test` | Test notification system |

## REST API

The system provides a REST API for programmatic access. The API is available at `http://localhost:8080/api/` by default.

### Authentication

#### Login
```http
POST /api/auth/login
Content-Type: application/json

{
  "username": "admin",
  "password": "your_password"
}
```

**Response:**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expires_in": 3600,
  "user_id": "admin"
}
```

#### Refresh Token
```http
POST /api/auth/refresh
Authorization: Bearer YOUR_TOKEN
```

#### Logout
```http
POST /api/auth/logout
Authorization: Bearer YOUR_TOKEN
```

### User Management API

#### List Users
```http
GET /api/users
Authorization: Bearer YOUR_TOKEN
```

**Query Parameters:**
| Parameter | Description | Example |
|-----------|-------------|---------|
| `limit` | Number of users to return | `?limit=50` |
| `offset` | Offset for pagination | `?offset=100` |
| `status` | Filter by status | `?status=active` |
| `format` | Response format | `?format=json` |

**Response:**
```json
{
  "users": [
    {
      "username": "john",
      "email": "john@example.com",
      "status": "active",
      "created_at": "2023-12-01T10:00:00Z",
      "expires_at": "2024-01-01T10:00:00Z",
      "traffic_limit": "50GB",
      "traffic_used": "15.5GB"
    }
  ],
  "total": 150,
  "limit": 50,
  "offset": 0
}
```

#### Create User
```http
POST /api/users
Authorization: Bearer YOUR_TOKEN
Content-Type: application/json

{
  "username": "newuser",
  "email": "newuser@example.com",
  "expire_days": 30,
  "traffic_limit": "100GB",
  "notes": "VIP user"
}
```

**Response:**
```json
{
  "success": true,
  "user": {
    "username": "newuser",
    "uuid": "550e8400-e29b-41d4-a716-446655440000",
    "email": "newuser@example.com",
    "status": "active",
    "created_at": "2023-12-01T10:00:00Z",
    "expires_at": "2024-01-01T10:00:00Z",
    "config": {
      "vless_uri": "vless://550e8400-e29b-41d4-a716-446655440000@domain.com:443...",
      "qr_code": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA..."
    }
  }
}
```

#### Get User Details
```http
GET /api/users/{username}
Authorization: Bearer YOUR_TOKEN
```

#### Update User
```http
PUT /api/users/{username}
Authorization: Bearer YOUR_TOKEN
Content-Type: application/json

{
  "email": "updated@example.com",
  "expire_days": 60,
  "traffic_limit": "200GB"
}
```

#### Delete User
```http
DELETE /api/users/{username}
Authorization: Bearer YOUR_TOKEN
```

#### Get User Configuration
```http
GET /api/users/{username}/config
Authorization: Bearer YOUR_TOKEN
```

**Query Parameters:**
| Parameter | Description | Values |
|-----------|-------------|---------|
| `format` | Configuration format | `json`, `uri`, `qr` |

### System API

#### System Status
```http
GET /api/system/status
Authorization: Bearer YOUR_TOKEN
```

**Response:**
```json
{
  "status": "running",
  "uptime": "5 days, 14 hours",
  "version": "1.0.0",
  "services": {
    "vless_vpn": "running",
    "docker": "running",
    "nginx": "running",
    "telegram_bot": "running"
  },
  "metrics": {
    "cpu_usage": 25.5,
    "memory_usage": 45.2,
    "disk_usage": 60.1,
    "active_connections": 12
  }
}
```

#### System Metrics
```http
GET /api/system/metrics
Authorization: Bearer YOUR_TOKEN
```

**Query Parameters:**
| Parameter | Description | Example |
|-----------|-------------|---------|
| `period` | Time period | `?period=24h` |
| `metric` | Specific metric | `?metric=cpu` |

#### Create Backup
```http
POST /api/system/backup
Authorization: Bearer YOUR_TOKEN
Content-Type: application/json

{
  "type": "full",
  "compress": true,
  "encrypt": false
}
```

#### List Backups
```http
GET /api/system/backups
Authorization: Bearer YOUR_TOKEN
```

#### Restore Backup
```http
POST /api/system/restore
Authorization: Bearer YOUR_TOKEN
Content-Type: application/json

{
  "backup_file": "backup_20231201_120000.tar.gz",
  "verify": true
}
```

### Configuration API

#### Get Configuration
```http
GET /api/config
Authorization: Bearer YOUR_TOKEN
```

#### Update Configuration
```http
PUT /api/config
Authorization: Bearer YOUR_TOKEN
Content-Type: application/json

{
  "vless_port": 8443,
  "domain": "vpn.example.com",
  "security_level": "high"
}
```

## Telegram Bot API

The Telegram bot provides a comprehensive interface for VPN management.

### Bot Commands

#### Administrative Commands

##### `/start`
Initialize bot and display welcome message.

**Usage:** `/start`

**Response:**
```
🚀 Welcome to VLESS+Reality VPN Manager!

I can help you manage your VPN server remotely.
Use /help to see all available commands.

Current Status:
• VPN Service: ✅ Running
• Active Users: 5
• Active Connections: 3
```

##### `/help`
Display command reference.

**Usage:** `/help [command]`

**Examples:**
```
/help
/help adduser
/help status
```

##### `/status`
Show system status and metrics.

**Usage:** `/status [--detailed]`

**Response:**
```
🖥️ System Status

🟢 VPN Service: Running
📊 CPU: 25% | RAM: 45% | Disk: 60%
🌐 Active Connections: 8
⏱️ Uptime: 12 days, 5 hours

[📈 Detailed Stats] [🔄 Refresh]
```

#### User Management Commands

##### `/adduser`
Add new VPN user.

**Usage:** `/adduser <username> [options]`

**Examples:**
```
/adduser john
/adduser john --email john@example.com --expire 30d
```

##### `/removeuser`
Remove VPN user.

**Usage:** `/removeuser <username>`

**Example:** `/removeuser john`

##### `/listusers`
List all VPN users.

**Usage:** `/listusers [--status active|inactive|all]`

##### `/userinfo`
Get detailed user information.

**Usage:** `/userinfo <username>`

##### `/qr`
Generate QR code for user.

**Usage:** `/qr <username>`

##### `/config`
Get user configuration.

**Usage:** `/config <username> [--format json|uri]`

#### System Management Commands

##### `/backup`
Create system backup.

**Usage:** `/backup [--type full|config|users]`

##### `/restore`
Restore from backup.

**Usage:** `/restore`

**Note:** This command will show available backups for selection.

##### `/maintenance`
Maintenance mode management.

**Usage:**
```
/maintenance on  - Enable maintenance mode
/maintenance off - Disable maintenance mode
```

##### `/update`
Check for and apply updates.

**Usage:** `/update [--check|--apply|--security]`

##### `/logs`
View system logs.

**Usage:** `/logs [--lines 50] [--service vless|docker|nginx]`

##### `/restart`
Restart VPN service.

**Usage:** `/restart [--service vless|docker|all]`

#### Monitoring Commands

##### `/stats`
Detailed system statistics.

**Usage:** `/stats [--period 1h|24h|7d|30d]`

##### `/connections`
Show active VPN connections.

**Usage:** `/connections [--user username]`

##### `/traffic`
Traffic usage statistics.

**Usage:** `/traffic [--user username] [--period 24h]`

##### `/alerts`
Configure system alerts.

**Usage:** `/alerts [--cpu 80] [--memory 85] [--enable|--disable]`

##### `/health`
Perform system health check.

**Usage:** `/health`

### Bot Configuration

#### Environment Variables
Configure the bot through `/opt/vless/config/bot.env`:

```bash
# Bot Configuration
BOT_TOKEN=your_bot_token_here
BOT_USERNAME=your_bot_username

# Admin Users (comma-separated Telegram IDs)
ADMIN_USERS=12345678,87654321

# Notification Settings
ENABLE_NOTIFICATIONS=true
NOTIFICATION_INTERVAL=3600
QUIET_HOURS=22:00-08:00

# Alert Thresholds
ALERT_THRESHOLD_CPU=80
ALERT_THRESHOLD_MEMORY=85
ALERT_THRESHOLD_DISK=90

# Security Settings
ENABLE_RATE_LIMITING=true
MAX_REQUESTS_PER_MINUTE=30
SESSION_TIMEOUT=3600

# Features
ENABLE_USER_MANAGEMENT=true
ENABLE_SYSTEM_COMMANDS=true
ENABLE_BACKUP_COMMANDS=true
ENABLE_MONITORING=true
```

## Configuration Files

### Main Configuration Files

#### `/opt/vless/config/vless.env`
Main VPN configuration file.

```bash
# Server Configuration
DOMAIN=vpn.example.com
EMAIL=admin@example.com
VLESS_PORT=443

# Security Configuration
SECURITY_LEVEL=high
ENABLE_FIREWALL=true
REALITY_TARGET=www.microsoft.com

# Performance Settings
MAX_CONNECTIONS=1000
BUFFER_SIZE=4096

# Logging
LOG_LEVEL=info
LOG_RETENTION=30d

# Backup Configuration
BACKUP_RETENTION=90d
BACKUP_ENCRYPTION=true
```

#### `/opt/vless/config/xray_config.json`
Xray core configuration file.

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
          "privateKey": "PRIVATE_KEY_PLACEHOLDER",
          "shortIds": ["SHORT_ID_PLACEHOLDER"]
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

#### `/opt/vless/config/monitoring.env`
Monitoring configuration.

```bash
# Monitoring Settings
ENABLE_MONITORING=true
METRICS_INTERVAL=60
METRICS_RETENTION=30d

# Alert Thresholds
CPU_THRESHOLD=80
MEMORY_THRESHOLD=85
DISK_THRESHOLD=90
CONNECTION_THRESHOLD=500

# Notification Settings
ENABLE_EMAIL_ALERTS=false
ENABLE_TELEGRAM_ALERTS=true
ALERT_COOLDOWN=3600
```

## Exit Codes and Return Values

### Standard Exit Codes

| Code | Description |
|------|-------------|
| `0` | Success |
| `1` | General error |
| `2` | Invalid arguments or usage |
| `3` | Permission denied |
| `4` | File not found |
| `5` | Service not running |
| `6` | Configuration error |
| `7` | Network error |
| `8` | Authentication failed |
| `9` | Resource unavailable |
| `10` | Timeout |

### Script-Specific Exit Codes

#### User Management (`user_management.sh`)
| Code | Description |
|------|-------------|
| `20` | User already exists |
| `21` | User not found |
| `22` | Invalid username format |
| `23` | User limit exceeded |
| `24` | User database error |

#### Backup/Restore (`backup_restore.sh`)
| Code | Description |
|------|-------------|
| `30` | Backup creation failed |
| `31` | Backup not found |
| `32` | Restore failed |
| `33` | Backup corruption detected |
| `34` | Insufficient disk space |

#### Certificate Management (`cert_management.sh`)
| Code | Description |
|------|-------------|
| `40` | Certificate generation failed |
| `41` | Certificate not found |
| `42` | Certificate expired |
| `43` | Domain validation failed |
| `44` | ACME challenge failed |

## Environment Variables

### System Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `VLESS_ROOT` | Installation root directory | `/opt/vless` |
| `VLESS_CONFIG_DIR` | Configuration directory | `/opt/vless/config` |
| `VLESS_LOG_DIR` | Log directory | `/opt/vless/logs` |
| `VLESS_DATA_DIR` | Data directory | `/opt/vless/data` |
| `VLESS_BACKUP_DIR` | Backup directory | `/opt/vless/backups` |

### Runtime Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DEBUG` | Enable debug mode | `false` |
| `VERBOSE` | Enable verbose output | `false` |
| `DRY_RUN` | Enable dry run mode | `false` |
| `FORCE` | Force operations | `false` |
| `LOG_LEVEL` | Logging level | `info` |

### Configuration Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `DOMAIN` | Server domain | `vpn.example.com` |
| `EMAIL` | Contact email | `admin@example.com` |
| `VLESS_PORT` | VPN service port | `443` |
| `SECURITY_LEVEL` | Security level | `high` |
| `BOT_TOKEN` | Telegram bot token | `123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11` |

## Examples and Use Cases

### Common Administrative Tasks

#### 1. Bulk User Management
```bash
# Create multiple users from CSV file
cat > users.csv << EOF
username,email,expire_days,limit_gb
user1,user1@example.com,30,50
user2,user2@example.com,60,100
user3,user3@example.com,90,200
EOF

sudo /opt/vless/scripts/user_management.sh bulk_add users.csv

# Generate configurations for all users
for user in user1 user2 user3; do
  sudo /opt/vless/scripts/user_management.sh config $user > ${user}_config.json
  sudo /opt/vless/scripts/qr_generator.py $user --output ${user}_qr.png
done
```

#### 2. Automated Monitoring Setup
```bash
# Setup comprehensive monitoring
sudo /opt/vless/scripts/monitoring.sh setup_alerts \
  --cpu-threshold 80 \
  --memory-threshold 85 \
  --disk-threshold 90 \
  --enable

# Schedule daily reports
echo "0 6 * * * /opt/vless/scripts/monitoring.sh report --period 24h --format html --output /opt/vless/reports/daily_$(date +%Y%m%d).html" | sudo crontab -

# Setup real-time monitoring dashboard
sudo /opt/vless/scripts/monitoring.sh monitor --interval 30 > /dev/null 2>&1 &
```

#### 3. Backup and Disaster Recovery
```bash
# Setup automated backups
sudo /opt/vless/scripts/backup_restore.sh schedule_backups \
  --daily --time "02:00" --retention 30d

sudo /opt/vless/scripts/backup_restore.sh schedule_backups \
  --weekly --day sunday --time "03:00" --retention 12w

# Test backup and restore procedure
sudo /opt/vless/scripts/backup_restore.sh create_full_backup
LATEST_BACKUP=$(sudo /opt/vless/scripts/backup_restore.sh list_backups | head -1)
sudo /opt/vless/scripts/backup_restore.sh verify --backup "$LATEST_BACKUP"
```

#### 4. Security Hardening
```bash
# Apply comprehensive security hardening
sudo /opt/vless/scripts/security_hardening.sh apply_all

# Setup fail2ban for SSH protection
sudo /opt/vless/scripts/security_hardening.sh setup_fail2ban

# Configure advanced firewall rules
sudo /opt/vless/scripts/ufw_config.sh advanced_setup
```

#### 5. Performance Optimization
```bash
# Optimize system for VPN performance
sudo /opt/vless/scripts/maintenance_utils.sh optimize_system

# Configure network optimizations
echo 'net.core.default_qdisc=fq' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv4.tcp_congestion_control=bbr' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Monitor performance
sudo /opt/vless/scripts/monitoring.sh performance_test
```

### API Integration Examples

#### 1. Python API Client
```python
import requests
import json

class VLESSAPIClient:
    def __init__(self, base_url, username, password):
        self.base_url = base_url
        self.token = self._login(username, password)

    def _login(self, username, password):
        response = requests.post(f"{self.base_url}/api/auth/login",
                               json={"username": username, "password": password})
        return response.json()["token"]

    def create_user(self, username, email, expire_days=30, traffic_limit="50GB"):
        headers = {"Authorization": f"Bearer {self.token}"}
        data = {
            "username": username,
            "email": email,
            "expire_days": expire_days,
            "traffic_limit": traffic_limit
        }
        response = requests.post(f"{self.base_url}/api/users",
                               json=data, headers=headers)
        return response.json()

    def get_user_config(self, username):
        headers = {"Authorization": f"Bearer {self.token}"}
        response = requests.get(f"{self.base_url}/api/users/{username}/config",
                              headers=headers)
        return response.json()

# Usage
client = VLESSAPIClient("https://vpn.example.com", "admin", "password")
user = client.create_user("newuser", "newuser@example.com")
config = client.get_user_config("newuser")
```

#### 2. Bash API Client
```bash
#!/bin/bash

# API Configuration
API_BASE="https://vpn.example.com/api"
USERNAME="admin"
PASSWORD="your_password"

# Login and get token
TOKEN=$(curl -s -X POST "$API_BASE/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}" \
  | jq -r '.token')

# Create user
create_user() {
  local username=$1
  local email=$2

  curl -s -X POST "$API_BASE/users" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$username\",\"email\":\"$email\"}"
}

# Get user configuration
get_user_config() {
  local username=$1

  curl -s -X GET "$API_BASE/users/$username/config" \
    -H "Authorization: Bearer $TOKEN"
}

# Usage
create_user "testuser" "test@example.com"
get_user_config "testuser"
```

---

This API reference provides comprehensive documentation for all available commands, scripts, and interfaces in the VLESS+Reality VPN Management System. Use this reference to integrate the system into your workflows and automate VPN management tasks.