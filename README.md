# VLESS+Reality VPN Management System

A comprehensive, enterprise-grade VLESS+Reality VPN management system with advanced automation, monitoring, and Telegram bot integration for seamless remote administration.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Telegram Bot](#telegram-bot)
- [API Reference](#api-reference)
- [Monitoring](#monitoring)
- [Backup & Recovery](#backup--recovery)
- [Security](#security)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Overview

The VLESS+Reality VPN Management System is a production-ready solution that provides secure, high-performance VPN services using the latest VLESS protocol with Reality technology. Built with enterprise requirements in mind, it features comprehensive automation, monitoring, backup capabilities, and a full-featured Telegram bot for remote management.

### Key Benefits

- **High Performance**: VLESS protocol with Reality technology for optimal speed and security
- **Enterprise Ready**: Comprehensive logging, monitoring, and backup systems
- **Remote Management**: Full-featured Telegram bot for administration
- **Automated Operations**: Self-healing, automated updates, and maintenance
- **Security First**: Advanced security hardening and certificate management
- **Scalable**: Docker-based architecture for easy scaling and deployment

## Features

### Core VPN Features
- **VLESS Protocol**: Latest generation VPN protocol for optimal performance
- **Reality Technology**: Advanced anti-detection and traffic camouflage
- **Multi-User Support**: Comprehensive user management with individual configurations
- **QR Code Generation**: Instant client configuration via QR codes
- **Certificate Management**: Automated SSL/TLS certificate handling

### Management & Automation
- **Telegram Bot Integration**: Complete remote management via Telegram
- **Web Dashboard**: Browser-based administration interface
- **Automated Backups**: Scheduled backups with configurable retention
- **System Monitoring**: Real-time performance and health monitoring
- **Automated Updates**: Safe system and core updates with rollback
- **Maintenance Mode**: Graceful service management during maintenance

### Security & Reliability
- **Security Hardening**: Comprehensive system security configuration
- **Firewall Management**: Automated UFW configuration and management
- **Process Isolation**: Secure containerized service deployment
- **Audit Logging**: Comprehensive activity and security logging
- **Health Monitoring**: Proactive system health checking and alerts

## Quick Start

### Prerequisites

- Ubuntu 20.04 LTS or newer (recommended)
- Root or sudo access
- At least 1GB RAM and 10GB storage
- Public IP address or domain name
- Open ports: 80, 443, and your chosen VPN port

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/your-username/vless-reality-vpn.git
   cd vless-reality-vpn
   ```

2. **Run the installation script:**
   ```bash
   sudo ./install.sh
   ```

3. **Follow the interactive setup process** to configure your VPN server.

4. **Start using your VPN** - configuration files and QR codes will be provided.

### Quick Commands

```bash
# Check system status
sudo /opt/vless/scripts/status.sh

# Add a new user
sudo /opt/vless/scripts/user_management.sh add username

# Generate QR code for user
sudo /opt/vless/scripts/qr_generator.py username

# Create system backup
sudo /opt/vless/scripts/backup_restore.sh create_full_backup
```

## Installation

### System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| OS | Ubuntu 20.04 | Ubuntu 22.04 LTS |
| RAM | 1GB | 2GB+ |
| Storage | 10GB | 20GB+ |
| CPU | 1 core | 2+ cores |
| Network | 100Mbps | 1Gbps+ |

### Installation Options

#### Standard Installation
```bash
sudo ./install.sh
```

#### Custom Installation
```bash
# Verbose installation with custom config
sudo ./install.sh --verbose --config /path/to/config.env

# Skip certain components
sudo ./install.sh --skip-docker --skip-security

# Dry run to preview changes
sudo ./install.sh --dry-run
```

#### Installation Phases

The installation process consists of several phases:

1. **Environment Validation** - System compatibility and requirements check
2. **Foundation Setup** - Directory structure and basic configuration
3. **Dependency Installation** - Required packages and tools
4. **Docker Setup** - Container platform configuration
5. **Core Installation** - Xray core and VLESS configuration
6. **Security Hardening** - System security and firewall setup
7. **Service Configuration** - System services and automation
8. **Telegram Bot Setup** - Optional bot configuration
9. **Testing & Validation** - System testing and verification

## Configuration

### Main Configuration

Primary configuration is managed through environment files:

- `/opt/vless/config/vless.env` - Main VPN configuration
- `/opt/vless/config/bot.env` - Telegram bot configuration
- `/opt/vless/config/monitoring.env` - Monitoring settings

### Environment Variables

```bash
# VPN Configuration
VLESS_PORT=443
VLESS_UUID=$(uuidgen)
DOMAIN=your-domain.com
EMAIL=your-email@domain.com

# Security Settings
ENABLE_FIREWALL=true
SECURITY_LEVEL=high
LOG_LEVEL=info

# Telegram Bot (Optional)
BOT_TOKEN=your-bot-token
ADMIN_USER_ID=your-telegram-id
```

### Network Configuration

```bash
# Configure port and protocol
sudo /opt/vless/scripts/configure.sh --port 443 --protocol vless

# Update domain settings
sudo /opt/vless/scripts/configure.sh --domain your-domain.com

# Regenerate certificates
sudo /opt/vless/scripts/cert_management.sh renew
```

## Usage

### User Management

#### Adding Users
```bash
# Interactive user creation
sudo /opt/vless/scripts/user_management.sh add

# Quick user creation
sudo /opt/vless/scripts/user_management.sh add username

# Bulk user creation
sudo /opt/vless/scripts/user_management.sh bulk_add users.txt
```

#### Managing Users
```bash
# List all users
sudo /opt/vless/scripts/user_management.sh list

# Get user details
sudo /opt/vless/scripts/user_management.sh info username

# Remove user
sudo /opt/vless/scripts/user_management.sh remove username

# Disable/enable user
sudo /opt/vless/scripts/user_management.sh disable username
sudo /opt/vless/scripts/user_management.sh enable username
```

#### Configuration Generation
```bash
# Generate client configuration
sudo /opt/vless/scripts/user_management.sh config username

# Generate QR code
sudo /opt/vless/scripts/qr_generator.py username

# Generate all formats
sudo /opt/vless/scripts/user_management.sh export username
```

### System Management

#### Service Control
```bash
# Start/stop/restart VPN service
sudo systemctl start vless-vpn
sudo systemctl stop vless-vpn
sudo systemctl restart vless-vpn

# Check service status
sudo systemctl status vless-vpn

# View service logs
sudo journalctl -u vless-vpn -f
```

#### Monitoring
```bash
# System status overview
sudo /opt/vless/scripts/status.sh

# Detailed system report
sudo /opt/vless/scripts/monitoring.sh generate_report

# Real-time monitoring
sudo /opt/vless/scripts/monitoring.sh monitor --realtime
```

## Telegram Bot

The integrated Telegram bot provides complete remote management capabilities.

### Setup

1. **Create a Telegram Bot:**
   - Message @BotFather on Telegram
   - Use `/newbot` command
   - Save the bot token

2. **Configure Bot:**
   ```bash
   sudo /opt/vless/scripts/telegram_bot_manager.sh setup
   ```

3. **Add Admin Users:**
   ```bash
   sudo /opt/vless/scripts/telegram_bot_manager.sh add_admin YOUR_TELEGRAM_ID
   ```

### Bot Commands

#### Administrative Commands
- `/start` - Initialize bot and show welcome
- `/status` - System status and performance metrics
- `/users` - User management interface
- `/backup` - Backup and restore operations
- `/maintenance` - System maintenance tools
- `/settings` - Bot and system configuration
- `/help` - Command reference and help

#### Quick Commands
- `/adduser <username>` - Add new VPN user
- `/removeuser <username>` - Remove VPN user
- `/qr <username>` - Generate QR code for user
- `/config <username>` - Get user configuration
- `/stats` - Usage statistics and metrics

#### Management Operations
```
User: /adduser john
Bot:  User 'john' created successfully!
     =ñ QR Code: [QR_CODE_IMAGE]
     =Ë Configuration: [CONFIG_TEXT]

User: /status
Bot: =¥ System Status:
     " CPU: 15% " RAM: 45% " Disk: 23%
     " VPN Service:  Running
     " Active Connections: 12
     " Uptime: 5 days, 14 hours
```

## API Reference

### REST API Endpoints

The system provides a REST API for programmatic access:

#### Authentication
```bash
# Get API token
curl -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "your-password"}'
```

#### User Management
```bash
# List users
curl -H "Authorization: Bearer TOKEN" \
  http://localhost:8080/api/users

# Add user
curl -X POST -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"username": "newuser", "email": "user@example.com"}' \
  http://localhost:8080/api/users

# Get user configuration
curl -H "Authorization: Bearer TOKEN" \
  http://localhost:8080/api/users/username/config
```

#### System Operations
```bash
# System status
curl -H "Authorization: Bearer TOKEN" \
  http://localhost:8080/api/system/status

# Create backup
curl -X POST -H "Authorization: Bearer TOKEN" \
  http://localhost:8080/api/system/backup

# System metrics
curl -H "Authorization: Bearer TOKEN" \
  http://localhost:8080/api/system/metrics
```

### Command Line Scripts

#### User Management (`user_management.sh`)
```bash
# Add user with options
./user_management.sh add --username john --email john@example.com --expire 30d

# Export user data
./user_management.sh export --user john --format json

# Import users from file
./user_management.sh import --file users.json
```

#### Backup Operations (`backup_restore.sh`)
```bash
# Create full backup
./backup_restore.sh create_full_backup --retention 7d

# Restore from backup
./backup_restore.sh restore --backup backup_20231201_120000.tar.gz

# Schedule automated backups
./backup_restore.sh schedule --daily --time "02:00" --retention 30d
```

#### Monitoring (`monitoring.sh`)
```bash
# Monitor system resources
./monitoring.sh monitor --interval 60 --alert-cpu 80 --alert-memory 85

# Generate performance report
./monitoring.sh report --period 7d --format pdf

# Setup alerts
./monitoring.sh setup_alerts --email admin@example.com --telegram @admin
```

## Monitoring

### Real-time Monitoring

The system provides comprehensive monitoring capabilities:

#### System Metrics
- **CPU Usage**: Real-time CPU utilization and load averages
- **Memory Usage**: RAM and swap utilization with alerts
- **Disk Usage**: Storage utilization and I/O metrics
- **Network**: Bandwidth usage and connection statistics

#### VPN Metrics
- **Active Connections**: Current user connections and sessions
- **Traffic Statistics**: Data transfer and bandwidth utilization
- **Service Health**: Xray core status and performance
- **User Activity**: Connection logs and usage patterns

#### Alerting
```bash
# Configure alert thresholds
sudo /opt/vless/scripts/monitoring.sh setup_alerts \
  --cpu-threshold 80 \
  --memory-threshold 85 \
  --disk-threshold 90 \
  --telegram-alerts

# Test alerts
sudo /opt/vless/scripts/monitoring.sh test_alerts
```

### Performance Dashboard

Access the web dashboard at `https://your-domain.com/dashboard`

**Dashboard Features:**
- Real-time system metrics and graphs
- User connection monitoring
- Traffic analysis and reporting
- System health overview
- Alert management interface

## Backup & Recovery

### Automated Backups

The system supports multiple backup strategies:

#### Backup Types
- **Full System Backup**: Complete system state and configuration
- **Configuration Backup**: Server settings and user configurations
- **User Data Backup**: User accounts and access credentials only

#### Backup Scheduling
```bash
# Setup daily backups at 2 AM
sudo /opt/vless/scripts/backup_restore.sh schedule \
  --daily --time "02:00" --retention 30d

# Setup weekly backups with longer retention
sudo /opt/vless/scripts/backup_restore.sh schedule \
  --weekly --day sunday --time "03:00" --retention 90d
```

#### Manual Backups
```bash
# Create immediate full backup
sudo /opt/vless/scripts/backup_restore.sh create_full_backup

# Create configuration-only backup
sudo /opt/vless/scripts/backup_restore.sh create_config_backup

# Create user data backup
sudo /opt/vless/scripts/backup_restore.sh create_users_backup
```

### Recovery Operations

#### System Restore
```bash
# List available backups
sudo /opt/vless/scripts/backup_restore.sh list_backups

# Restore from specific backup
sudo /opt/vless/scripts/backup_restore.sh restore \
  --backup backup_20231201_120000.tar.gz

# Restore with verification
sudo /opt/vless/scripts/backup_restore.sh restore \
  --backup backup_20231201_120000.tar.gz --verify
```

#### Disaster Recovery
```bash
# Emergency restore (fresh system)
sudo /opt/vless/scripts/backup_restore.sh emergency_restore \
  --backup backup_20231201_120000.tar.gz \
  --force --rebuild-containers
```

## Security

### Security Features

The system implements comprehensive security measures:

#### System Hardening
- **Firewall Configuration**: Automated UFW setup with minimal open ports
- **SSH Hardening**: Secure SSH configuration and key-based authentication
- **Service Isolation**: Docker containers with limited privileges
- **Regular Updates**: Automated security updates with safe rollback
- **Audit Logging**: Comprehensive logging of all system activities

#### VPN Security
- **VLESS Protocol**: Latest generation protocol with advanced encryption
- **Reality Technology**: Traffic obfuscation and anti-detection
- **Certificate Management**: Automated SSL/TLS certificate handling
- **User Isolation**: Individual user configurations and access controls

### Security Configuration

#### Enable Security Hardening
```bash
# Apply security hardening
sudo /opt/vless/scripts/security_hardening.sh apply_all

# Configure firewall
sudo /opt/vless/scripts/ufw_config.sh setup

# Setup SSH security
sudo /opt/vless/scripts/security_hardening.sh ssh_harden
```

#### Security Monitoring
```bash
# Security audit
sudo /opt/vless/scripts/security_hardening.sh audit

# Check for security updates
sudo /opt/vless/scripts/system_update.sh check_security_updates

# Monitor failed login attempts
sudo /opt/vless/scripts/monitoring.sh security_monitor
```

## Troubleshooting

### Common Issues

#### Installation Problems

**Issue**: Installation fails during dependency installation
```bash
# Solution: Update package lists and retry
sudo apt update && sudo apt upgrade -y
sudo ./install.sh --force
```

**Issue**: Docker installation fails
```bash
# Solution: Manual Docker installation
sudo ./install.sh --skip-docker
# Then install Docker manually and run:
sudo ./modules/docker_setup.sh
```

#### Service Issues

**Issue**: VPN service won't start
```bash
# Check service status
sudo systemctl status vless-vpn

# Check logs
sudo journalctl -u vless-vpn -n 50

# Restart service
sudo systemctl restart vless-vpn
```

**Issue**: Users can't connect
```bash
# Verify configuration
sudo /opt/vless/scripts/user_management.sh verify username

# Check firewall
sudo ufw status
sudo /opt/vless/scripts/ufw_config.sh verify

# Test connectivity
sudo /opt/vless/scripts/monitoring.sh test_connectivity
```

#### Performance Issues

**Issue**: High CPU usage
```bash
# Check system resources
sudo /opt/vless/scripts/monitoring.sh system_report

# Optimize system
sudo /opt/vless/scripts/maintenance_utils.sh optimize_system

# Check for resource leaks
sudo /opt/vless/scripts/monitoring.sh analyze_performance
```

### Diagnostic Tools

#### System Diagnostics
```bash
# Comprehensive system check
sudo /opt/vless/scripts/maintenance_utils.sh check_system_health

# Generate diagnostic report
sudo /opt/vless/scripts/maintenance_utils.sh generate_diagnostics

# Network connectivity test
sudo /opt/vless/scripts/monitoring.sh test_network
```

#### Log Analysis
```bash
# Analyze system logs
sudo /opt/vless/scripts/monitoring.sh analyze_logs

# Check error patterns
sudo /opt/vless/scripts/monitoring.sh error_analysis

# Export logs for support
sudo /opt/vless/scripts/maintenance_utils.sh export_logs
```

### Getting Help

#### Documentation
- [Installation Guide](docs/installation.md) - Detailed installation instructions
- [User Guide](docs/user_guide.md) - Complete user management guide
- [API Reference](docs/api_reference.md) - API documentation and examples
- [Security Guide](docs/security_guide.md) - Security best practices

#### Support Channels
- **GitHub Issues**: Report bugs and feature requests
- **Documentation**: Comprehensive guides and tutorials
- **Community**: Discussion forums and user community

#### Support Information Collection
```bash
# Generate support bundle
sudo /opt/vless/scripts/maintenance_utils.sh generate_support_bundle

# System information export
sudo /opt/vless/scripts/monitoring.sh export_system_info
```

## Contributing

We welcome contributions to improve the VLESS+Reality VPN Management System.

### Development Setup
```bash
# Clone repository
git clone https://github.com/your-username/vless-reality-vpn.git
cd vless-reality-vpn

# Setup development environment
./scripts/dev-setup.sh

# Run tests
./tests/run_all_tests.sh
```

### Contribution Guidelines
1. Fork the repository
2. Create a feature branch
3. Make your changes with appropriate tests
4. Ensure all tests pass
5. Submit a pull request with detailed description

### Code Standards
- Follow bash scripting best practices
- Include comprehensive error handling
- Add appropriate logging and comments
- Include tests for new functionality
- Update documentation for changes

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

### Third-Party Components
- **Xray Core**: MPL-2.0 License
- **Docker**: Apache License 2.0
- **Python Libraries**: Various open-source licenses (see requirements.txt)

---

## Quick Reference

### Essential Commands
```bash
# System Status
sudo /opt/vless/scripts/status.sh

# Add User
sudo /opt/vless/scripts/user_management.sh add username

# Generate QR Code
sudo /opt/vless/scripts/qr_generator.py username

# Create Backup
sudo /opt/vless/scripts/backup_restore.sh create_full_backup

# View Logs
sudo journalctl -u vless-vpn -f

# System Health Check
sudo /opt/vless/scripts/maintenance_utils.sh check_system_health
```

### Configuration Files
- `/opt/vless/config/vless.env` - Main configuration
- `/opt/vless/config/xray_config.json` - Xray configuration
- `/opt/vless/config/bot.env` - Telegram bot settings
- `/opt/vless/logs/` - System logs directory

### Important Directories
- `/opt/vless/` - Main installation directory
- `/opt/vless/scripts/` - Management scripts
- `/opt/vless/config/` - Configuration files
- `/opt/vless/data/` - User data and certificates
- `/opt/vless/backups/` - Backup storage
- `/opt/vless/logs/` - Log files

For detailed information and advanced configuration options, please refer to the documentation in the `docs/` directory.