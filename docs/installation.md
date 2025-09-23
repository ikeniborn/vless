# Installation Guide

Complete installation guide for the VLESS+Reality VPN Management System.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [System Preparation](#system-preparation)
3. [Installation Methods](#installation-methods)
4. [Phase-by-Phase Installation](#phase-by-phase-installation)
5. [Post-Installation Configuration](#post-installation-configuration)
6. [Verification](#verification)
7. [Troubleshooting](#troubleshooting)

## Prerequisites

### Hardware Requirements

#### Minimum Requirements
- **CPU**: 1 core (x86_64 architecture)
- **RAM**: 1GB available memory
- **Storage**: 20GB free disk space
- **Network**: Stable internet connection (100Mbps+)

#### Recommended Requirements
- **CPU**: 2+ cores (x86_64 architecture)
- **RAM**: 2GB+ available memory
- **Storage**: 50GB+ SSD storage
- **Network**: High-speed connection (1Gbps+)

### Software Requirements

#### Supported Operating Systems
- **Ubuntu**: 20.04 LTS, 22.04 LTS (recommended)
- **Debian**: 11 (Bullseye), 12 (Bookworm)
- **CentOS**: 8+, Stream 9
- **RHEL**: 8+, 9+
- **Rocky Linux**: 8+, 9+

#### Required Permissions
- Root access or sudo privileges
- Ability to install packages
- Network configuration permissions
- Firewall management access

#### Network Requirements
- **Public IP Address**: Required for external access
- **Domain Name**: Optional but recommended
- **Ports**: 443 (HTTPS), 80 (HTTP), custom ports as needed
- **DNS**: Proper DNS resolution capabilities

## System Preparation

### 1. Update System Packages

```bash
# Ubuntu/Debian
sudo apt update && sudo apt upgrade -y

# CentOS/RHEL/Rocky
sudo dnf update -y
# or for older systems
sudo yum update -y
```

### 2. Install Essential Dependencies

```bash
# Ubuntu/Debian
sudo apt install -y curl wget git unzip software-properties-common

# CentOS/RHEL/Rocky
sudo dnf install -y curl wget git unzip epel-release
```

### 3. Configure Firewall (Optional but Recommended)

```bash
# Ubuntu/Debian - UFW
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable

# CentOS/RHEL/Rocky - firewalld
sudo systemctl enable firewalld
sudo systemctl start firewalld
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload
```

### 4. Set System Timezone

```bash
# Set to UTC (recommended for servers)
sudo timedatectl set-timezone UTC

# Or set to your local timezone
sudo timedatectl set-timezone America/New_York
```

## Installation Methods

### Method 1: Interactive Installation with Mode Selection (Recommended)

The interactive installation now provides three installation modes optimized for different use cases:

#### Installation Mode Selection
```bash
sudo ./install.sh
```

**Available Modes**:
- **Minimal**: Core VPN functionality only (Phases 1-3)
- **Balanced**: VPN + essential security features (Phases 1-4)
- **Full**: All features including backup and maintenance utilities (Phases 1-5)

#### Mode Characteristics

**Minimal Mode**:
- Resource usage: 60% reduction in monitoring overhead
- Features: Basic VLESS+Reality, user management, minimal logging
- Use case: Resource-constrained environments, container deployments

**Balanced Mode** (Default):
- Resource usage: Optimized monitoring with 5-minute intervals
- Features: Full VPN + selective security hardening
- Use case: Production servers, most common deployment

**Full Mode**:
- Resource usage: Comprehensive monitoring with 1-minute intervals
- Features: All capabilities including backup automation, maintenance utilities
- Use case: Advanced deployments, development environments

```bash
# Clone the repository
git clone https://github.com/yourusername/vless.git
cd vless

# Make installation script executable
chmod +x install.sh

# Run interactive installation
sudo ./install.sh
```

### Method 2: Direct Mode Installation

Install directly with a specific mode without interactive selection:

```bash
# Minimal installation (VPN only)
sudo INSTALLATION_MODE=minimal ./install.sh

# Balanced installation (VPN + security)
sudo INSTALLATION_MODE=balanced ./install.sh

# Full installation (all features)
sudo INSTALLATION_MODE=full ./install.sh
```

### Method 3: Quick Installation (Unattended)

For automated deployments, you can use the quick installation mode that skips interactive prompts and uses sensible defaults (minimal mode):

```bash
# Quick installation (minimal mode)
sudo QUICK_MODE=true ./install.sh

# Or set environment variables for custom configuration
export VLESS_PORT=443
export REALITY_DOMAIN="www.microsoft.com"
export REALITY_PORT=443
export SSL_EMAIL="admin@yourdomain.com"
export ENABLE_FIREWALL=true

# Run quick installation with custom settings
sudo ./install.sh --quick
```

**Quick Mode Features:**
- Skips all interactive prompts
- Installs all phases automatically
- Uses default configurations when environment variables are not set
- Provides comprehensive logging for troubleshooting
- Includes enhanced error handling and recovery mechanisms

### Method 3: Docker Installation

Deploy using Docker containers for isolated environment.

```bash
# Clone repository
git clone https://github.com/yourusername/vless.git
cd vless

# Deploy with Docker Compose
sudo docker-compose up -d
```

## Phase-by-Phase Installation

The installation process is divided into five phases for modular deployment and easier troubleshooting.

### Phase 1: Core Infrastructure Setup

**Purpose**: Establishes the foundation system components.

**Components Installed**:
- System directories (`/opt/vless/`)
- VLESS system user and group creation
- Base dependencies (Docker, Python3, etc.)
- Python dependencies with robust error handling
- Core utilities and logging system
- Initial configuration templates

**Installation Steps**:
1. System compatibility verification
2. VLESS system user and group creation
3. Dependency installation (with enhanced error handling)
4. Python dependencies installation (multiple fallback methods)
5. Directory structure creation
6. Permission configuration
7. Core utility setup

**Recent Improvements (v1.0.1)**:
- Added include guard to prevent multiple sourcing errors
- Enhanced Python dependency installation with multiple fallback methods
- Improved UFW firewall validation to handle different output formats
- Added system user creation for better security isolation
- Added Quick Mode support for unattended installations

**Expected Duration**: 5-10 minutes

**Verification**:
```bash
# Check system directories
ls -la /opt/vless/

# Verify dependencies
docker --version
python3 --version

# Test logging system
sudo /opt/vless/scripts/common_utils.sh test
```

### Phase 2: VLESS Server Implementation

**Purpose**: Deploys the core VLESS+Reality server infrastructure.

**Components Installed**:
- Xray-core server
- Reality configuration
- TLS certificate management
- Docker containers
- Network configuration

**Installation Steps**:
1. Xray-core installation
2. Reality protocol configuration
3. TLS certificate generation
4. Docker container deployment
5. Network interface setup

**Expected Duration**: 10-15 minutes

**Verification**:
```bash
# Check Xray service
sudo systemctl status xray

# Verify container status
sudo docker ps

# Test network connectivity
curl -I https://your-server-ip
```

### Phase 3: User Management System

**Purpose**: Implements comprehensive user management capabilities.

**Components Installed**:
- User database system
- Configuration generation tools
- QR code generator
- User quota management
- Configuration templates

**Installation Steps**:
1. User database initialization
2. Management script deployment
3. Configuration template setup
4. QR code generator installation
5. Quota system configuration

**Expected Duration**: 5-10 minutes

**Verification**:
```bash
# Test user management
sudo /opt/vless/scripts/user_management.sh list

# Verify QR generator
python3 /opt/vless/modules/qr_generator.py --test

# Check database
sqlite3 /opt/vless/users/users.db ".tables"
```

### Phase 4: Security and Monitoring

**Purpose**: Hardens system security and implements monitoring.

**Components Installed**:
- Security hardening configurations
- System monitoring tools
- Log management system
- Firewall rules
- Intrusion detection

**Installation Steps**:
1. Security policy implementation
2. Monitoring system deployment
3. Log rotation configuration
4. Firewall rule application
5. Security scanning setup

**Expected Duration**: 10-15 minutes

**Verification**:
```bash
# Check security status
sudo /opt/vless/scripts/security_hardening.sh status

# Verify monitoring
sudo /opt/vless/scripts/monitoring.sh check

# Review security logs
sudo journalctl -u vless --since "1 hour ago"
```

### Phase 5: Backup and Maintenance Utilities

**Purpose**: Deploys backup automation and maintenance utilities.

**Components Installed**:
- Automated backup system
- Maintenance utilities
- System monitoring enhancements
- Log management automation
- Performance optimization tools

**Installation Steps**:
1. Backup system deployment
2. Maintenance utilities setup
3. Enhanced monitoring configuration
4. Log rotation automation
5. Performance tuning activation

**Expected Duration**: 10-15 minutes

**Verification**:
```bash
# Test backup system
sudo /opt/vless/scripts/backup_restore.sh test

# Check maintenance utilities
sudo /opt/vless/scripts/maintenance_utils.sh status

# Verify log management
sudo /opt/vless/scripts/logging_setup.sh check
```

## Post-Installation Configuration

### 1. Configure Environment Variables

Edit the main configuration file:

```bash
sudo nano /opt/vless/config/environment.conf
```

Key configurations:
```bash
# Server settings
VLESS_PORT=443
REALITY_DOMAIN="www.microsoft.com"
REALITY_PORT=443
SERVER_NAME="your-domain.com"

# Security settings
SSL_EMAIL="admin@yourdomain.com"
ENABLE_FIREWALL=true
AUTO_UPDATE=true

# Backup settings
BACKUP_RETENTION_DAYS=30
ENABLE_AUTOMATED_BACKUP=true

# Monitoring
ENABLE_MONITORING=true
LOG_LEVEL="INFO"
ALERT_EMAIL="alerts@yourdomain.com"
```

### 2. Create Administrative User

```bash
# Create first admin user
sudo /opt/vless/scripts/user_management.sh add admin --role=admin

# Generate configuration
sudo /opt/vless/scripts/user_management.sh config admin
```

### 3. Configure Automated Backups

If you enabled automated backups in Phase 5:

```bash
# Configure backup schedule
sudo /opt/vless/scripts/backup_restore.sh schedule daily

# Test backup system
sudo /opt/vless/scripts/backup_restore.sh backup --test
```

### 4. Set Up Monitoring Alerts

```bash
# Configure email alerts
sudo /opt/vless/scripts/monitoring.sh setup-alerts

# Set monitoring intervals
sudo /opt/vless/scripts/monitoring.sh configure
```

### 5. Configure Automated Backups

```bash
# Set up daily backups
sudo /opt/vless/scripts/backup_restore.sh schedule

# Test backup system
sudo /opt/vless/scripts/backup_restore.sh backup --test
```

## Verification

### 1. System Health Check

Run the comprehensive system check:

```bash
sudo /opt/vless/scripts/system_check.sh
```

### 2. Service Status Verification

```bash
# Check all services
sudo systemctl status xray
sudo systemctl status docker

# View service logs
sudo journalctl -u xray -f
```

### 3. Network Connectivity Test

```bash
# Test external connectivity
curl -I https://your-server-ip:443

# Test VLESS connection
/opt/vless/scripts/test_connection.sh
```

### 4. User Management Test

```bash
# Create test user
sudo /opt/vless/scripts/user_management.sh add testuser

# Generate configuration
sudo /opt/vless/scripts/user_management.sh config testuser

# Verify user in database
sudo /opt/vless/scripts/user_management.sh list
```

### 5. Security Verification

```bash
# Run security audit
sudo /opt/vless/scripts/security_hardening.sh audit

# Check firewall status
sudo ufw status
# or
sudo firewall-cmd --list-all
```

## Troubleshooting

### Common Installation Issues

#### 1. Permission Denied Errors

**Problem**: Installation fails with permission errors or multiple sourcing errors.

**Solution**:
```bash
# Ensure running as root or with sudo
sudo su -
./install.sh

# Or fix file permissions
chmod +x install.sh
sudo chown root:root install.sh
```

**Note**: The installation script now includes an include guard in `common_utils.sh` to prevent multiple sourcing errors that could cause permission issues.

#### 2. Package Installation Failures

**Problem**: Dependencies fail to install, especially Python packages.

**Solution**:
```bash
# Update package repositories
sudo apt update
# or
sudo dnf clean all && sudo dnf update

# Install missing dependencies manually
sudo apt install curl wget git python3 python3-pip
```

**Enhanced Python Dependency Handling**:
The installation script now includes robust Python dependency installation with multiple fallback methods:

1. **Standard Installation**: Uses `pip install -r requirements.txt`
2. **Externally Managed Environments**: Uses `--break-system-packages` flag
3. **User Installation**: Falls back to `--user` installation
4. **Timeout Handling**: 5-minute timeout with error recovery
5. **Network Resilience**: Automatic retry with different approaches

If Python installation still fails, try manual installation:
```bash
# Manually install Python dependencies
sudo python3 -m pip install python-telegram-bot qrcode[pil] requests aiohttp --break-system-packages
```

#### 3. Docker Installation Issues

**Problem**: Docker service fails to start.

**Solution**:
```bash
# Restart Docker service
sudo systemctl restart docker

# Check Docker status
sudo systemctl status docker

# Reinstall Docker if necessary
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
```

#### 4. Port Conflicts

**Problem**: Required ports are already in use.

**Solution**:
```bash
# Check port usage
sudo netstat -tlnp | grep :443

# Kill conflicting processes
sudo systemctl stop nginx
sudo systemctl stop apache2

# Or configure alternative ports
export VLESS_PORT=8443
```

#### 5. Certificate Issues

**Problem**: SSL certificate generation fails.

**Solution**:
```bash
# Manual certificate generation
sudo /opt/vless/scripts/cert_management.sh generate

# Check certificate status
sudo /opt/vless/scripts/cert_management.sh status

# Use alternative CA
export CERT_CA="letsencrypt"
```

#### 6. Firewall Configuration Issues

**Problem**: UFW firewall validation fails with unexpected output formats.

**Solution**:
The installation script now includes improved UFW validation that handles different output formats:

```bash
# Check UFW status manually
sudo ufw status verbose

# If UFW shows unexpected format, restart it
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 443/tcp
sudo ufw --force enable
```

#### 7. System User Creation Issues

**Problem**: VLESS system user creation fails.

**Solution**:
The installation script now includes a dedicated `create_vless_system_user()` function that:

- Creates the `vless` group if it doesn't exist
- Creates the `vless` user with proper permissions
- Sets up correct home directory and shell restrictions
- Provides detailed logging for troubleshooting

```bash
# Manually create VLESS user if needed
sudo groupadd -r vless
sudo useradd -r -g vless -s /bin/false -d /opt/vless -c "VLESS VPN Service" vless
```

### Installation Logs

All installation activities are logged to:
- **Main log**: `/opt/vless/logs/installation.log`
- **Error log**: `/opt/vless/logs/installation_errors.log`
- **System log**: `journalctl -u vless-installer`

### Getting Help

If you encounter issues not covered here:

1. **Check the logs**: Review installation and service logs
2. **Verify requirements**: Ensure all prerequisites are met
3. **Run diagnostics**: Use built-in diagnostic tools
4. **Consult documentation**: Check the troubleshooting guide
5. **Seek support**: Contact support or community forums

### Recovery Options

#### 1. Partial Installation Recovery

```bash
# Resume installation from specific phase
sudo ./install.sh --resume --phase=3
```

#### 2. Complete Reinstallation

```bash
# Uninstall existing installation
sudo /opt/vless/scripts/uninstall.sh

# Clean installation
sudo ./install.sh --clean
```

#### 3. Backup Recovery

```bash
# Restore from backup
sudo /opt/vless/scripts/backup_restore.sh restore /path/to/backup
```

---

**Next Steps**: After successful installation, proceed to the [User Guide](user_guide.md) for system usage instructions.