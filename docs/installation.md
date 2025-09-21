# VLESS+Reality VPN Management System - Installation Guide

This comprehensive installation guide provides step-by-step instructions for installing and configuring the VLESS+Reality VPN Management System.

## Table of Contents

- [System Requirements](#system-requirements)
- [Pre-Installation Checklist](#pre-installation-checklist)
- [Installation Methods](#installation-methods)
- [Step-by-Step Installation](#step-by-step-installation)
- [Post-Installation Configuration](#post-installation-configuration)
- [Verification and Testing](#verification-and-testing)
- [Troubleshooting Installation Issues](#troubleshooting-installation-issues)
- [Advanced Installation Options](#advanced-installation-options)

## System Requirements

### Minimum Requirements

| Component | Specification |
|-----------|---------------|
| **Operating System** | Ubuntu 20.04 LTS or newer |
| **CPU** | 1 core (x86_64) |
| **RAM** | 1GB |
| **Storage** | 10GB free space |
| **Network** | Public IP address |
| **Bandwidth** | 100 Mbps |

### Recommended Requirements

| Component | Specification |
|-----------|---------------|
| **Operating System** | Ubuntu 22.04 LTS |
| **CPU** | 2+ cores (x86_64) |
| **RAM** | 2GB+ |
| **Storage** | 20GB+ SSD |
| **Network** | Static public IP or domain |
| **Bandwidth** | 1 Gbps+ |

### Supported Operating Systems

- ✅ **Ubuntu 20.04 LTS** (Recommended)
- ✅ **Ubuntu 22.04 LTS** (Recommended)
- ✅ **Ubuntu 24.04 LTS**
- ✅ **Debian 11** (Bullseye)
- ✅ **Debian 12** (Bookworm)
- ⚠️ **CentOS 8** (Limited support)
- ⚠️ **RHEL 8+** (Limited support)

### Network Requirements

#### Required Ports
- **Port 80** (HTTP) - For Let's Encrypt certificate generation
- **Port 443** (HTTPS) - Main VPN service port
- **Port 22** (SSH) - Administrative access
- **Custom VPN Port** - If different from 443

#### Firewall Considerations
- Ensure ports are open in cloud provider security groups
- UFW will be configured automatically during installation
- iptables rules will be managed by the system

#### Domain Requirements (Recommended)
- Domain name pointing to your server IP
- DNS A record configured
- Ability to modify DNS records for certificate validation

## Pre-Installation Checklist

### Server Preparation

1. **Update System Packages**
   ```bash
   sudo apt update && sudo apt upgrade -y
   sudo apt autoremove -y
   ```

2. **Install Essential Tools**
   ```bash
   sudo apt install -y curl wget git unzip software-properties-common
   ```

3. **Verify System Architecture**
   ```bash
   uname -m  # Should output x86_64
   ```

4. **Check Available Disk Space**
   ```bash
   df -h  # Ensure at least 10GB free space
   ```

5. **Verify Internet Connectivity**
   ```bash
   ping -c 4 google.com
   ```

### Network Configuration

1. **Verify Public IP Address**
   ```bash
   curl -4 ifconfig.co
   ```

2. **Test Port Connectivity** (if behind firewall)
   ```bash
   # Test from external machine
   telnet YOUR_SERVER_IP 443
   telnet YOUR_SERVER_IP 80
   ```

3. **Configure DNS** (if using domain)
   ```bash
   # Verify DNS propagation
   nslookup your-domain.com
   dig your-domain.com A
   ```

### Security Preparation

1. **Secure SSH Access**
   ```bash
   # Create SSH key pair (if not already done)
   ssh-keygen -t rsa -b 4096

   # Copy public key to server
   ssh-copy-id user@your-server-ip

   # Disable password authentication (recommended)
   sudo nano /etc/ssh/sshd_config
   # Set: PasswordAuthentication no
   sudo systemctl restart sshd
   ```

2. **Create Non-Root User** (if not already exists)
   ```bash
   sudo adduser vlessadmin
   sudo usermod -aG sudo vlessadmin
   ```

## Installation Methods

### Method 1: Automated Installation (Recommended)

The easiest way to install the system using the automated installation script.

```bash
# Download the repository
git clone https://github.com/your-username/vless-reality-vpn.git
cd vless-reality-vpn

# Make installation script executable
chmod +x install.sh

# Run installation
sudo ./install.sh
```

### Method 2: Interactive Installation

For users who want more control over the installation process.

```bash
# Run installation with interactive prompts
sudo ./install.sh --interactive
```

### Method 3: Custom Configuration Installation

For advanced users with specific configuration requirements.

```bash
# Create custom configuration file
cp config/example.env config/custom.env
nano config/custom.env

# Run installation with custom config
sudo ./install.sh --config config/custom.env
```

### Method 4: Manual Installation

For expert users who want complete control over each step.

```bash
# Run individual installation phases
sudo ./install.sh --phase validate_environment
sudo ./install.sh --phase setup_foundation
sudo ./install.sh --phase install_dependencies
# ... continue with other phases
```

## Step-by-Step Installation

### Step 1: Download and Prepare Installation

1. **Connect to Your Server**
   ```bash
   ssh user@your-server-ip
   ```

2. **Update System**
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

3. **Download Installation Files**
   ```bash
   # Method A: Clone from Git repository
   git clone https://github.com/your-username/vless-reality-vpn.git
   cd vless-reality-vpn

   # Method B: Download release archive
   wget https://github.com/your-username/vless-reality-vpn/archive/latest.tar.gz
   tar -xzf latest.tar.gz
   cd vless-reality-vpn-*
   ```

4. **Verify Installation Files**
   ```bash
   # Check file integrity
   ls -la install.sh modules/ config/

   # Verify script permissions
   chmod +x install.sh
   ```

### Step 2: Configure Installation Options

1. **Review Installation Script Options**
   ```bash
   ./install.sh --help
   ```

2. **Create Configuration File** (optional)
   ```bash
   # Copy example configuration
   cp config/example.env config/installation.env

   # Edit configuration
   nano config/installation.env
   ```

   Example configuration:
   ```bash
   # Domain Configuration
   DOMAIN=vpn.example.com
   EMAIL=admin@example.com

   # VPN Configuration
   VLESS_PORT=443
   ENABLE_REALITY=true

   # Security Settings
   ENABLE_FIREWALL=true
   SECURITY_LEVEL=high

   # Optional Components
   INSTALL_TELEGRAM_BOT=true
   INSTALL_WEB_DASHBOARD=true
   ENABLE_MONITORING=true
   ```

### Step 3: Run Installation

1. **Start Installation Process**
   ```bash
   # Basic installation
   sudo ./install.sh

   # Installation with custom configuration
   sudo ./install.sh --config config/installation.env

   # Verbose installation for troubleshooting
   sudo ./install.sh --verbose
   ```

2. **Monitor Installation Progress**
   The installation script will display progress for each phase:

   ```
   =====================================
   VLESS+Reality VPN Installation
   =====================================

   Phase 1/9: Environment Validation     [✓]
   Phase 2/9: Foundation Setup          [✓]
   Phase 3/9: Dependencies Installation [✓]
   Phase 4/9: Docker Setup              [✓]
   Phase 5/9: Core Installation         [⟳]
   Phase 6/9: Security Hardening        [ ]
   Phase 7/9: Service Configuration     [ ]
   Phase 8/9: Optional Components       [ ]
   Phase 9/9: Testing & Validation      [ ]
   ```

3. **Interactive Configuration**
   During installation, you may be prompted for:

   ```
   🌐 Domain Configuration
   Enter your domain name (or press Enter for IP-only setup): vpn.example.com
   Enter your email for Let's Encrypt certificates: admin@example.com

   🔧 VPN Configuration
   Choose VPN port [443]: 443
   Enable Reality technology? [Y/n]: Y

   🔒 Security Configuration
   Security level (basic/standard/high) [standard]: high
   Enable firewall? [Y/n]: Y

   🤖 Optional Components
   Install Telegram bot? [y/N]: y
   Install web dashboard? [y/N]: y
   Enable monitoring? [Y/n]: Y
   ```

### Step 4: Post-Installation Configuration

1. **Verify Installation**
   ```bash
   # Check installation status
   sudo /opt/vless/scripts/status.sh

   # Verify service status
   sudo systemctl status vless-vpn
   ```

2. **Configure Telegram Bot** (if installed)
   ```bash
   # Setup Telegram bot
   sudo /opt/vless/scripts/telegram_bot_manager.sh setup

   # Add admin user
   sudo /opt/vless/scripts/telegram_bot_manager.sh add_admin YOUR_TELEGRAM_ID
   ```

3. **Create First VPN User**
   ```bash
   # Create admin user
   sudo /opt/vless/scripts/user_management.sh add admin

   # Generate configuration
   sudo /opt/vless/scripts/user_management.sh config admin
   sudo /opt/vless/scripts/qr_generator.py admin
   ```

### Step 5: SSL/TLS Certificate Setup

1. **Automatic Certificate Generation** (with domain)
   ```bash
   # Certificates are generated automatically during installation
   # Verify certificate status
   sudo /opt/vless/scripts/cert_management.sh status
   ```

2. **Manual Certificate Setup** (if needed)
   ```bash
   # Generate certificates manually
   sudo /opt/vless/scripts/cert_management.sh generate

   # Setup automatic renewal
   sudo /opt/vless/scripts/cert_management.sh auto_renew
   ```

3. **Self-Signed Certificate** (for testing)
   ```bash
   # Generate self-signed certificate
   sudo /opt/vless/scripts/cert_management.sh self_signed
   ```

## Post-Installation Configuration

### Initial System Configuration

1. **Configure System Settings**
   ```bash
   # Set timezone
   sudo timedatectl set-timezone UTC

   # Configure NTP
   sudo systemctl enable systemd-timesyncd
   sudo systemctl start systemd-timesyncd
   ```

2. **Configure Log Rotation**
   ```bash
   # Setup log rotation
   sudo /opt/vless/scripts/maintenance_utils.sh setup_log_rotation
   ```

3. **Configure Automated Backups**
   ```bash
   # Setup daily backups
   sudo /opt/vless/scripts/backup_restore.sh schedule_backups \
     --daily --time "02:00" --retention 30d
   ```

### Security Hardening

1. **Apply Security Hardening**
   ```bash
   # Apply all security measures
   sudo /opt/vless/scripts/security_hardening.sh apply_all

   # Configure firewall
   sudo /opt/vless/scripts/ufw_config.sh setup
   ```

2. **Configure SSH Security**
   ```bash
   # Harden SSH configuration
   sudo /opt/vless/scripts/security_hardening.sh ssh_harden
   ```

3. **Setup Fail2Ban** (optional)
   ```bash
   # Install and configure Fail2Ban
   sudo /opt/vless/scripts/security_hardening.sh setup_fail2ban
   ```

### Monitoring Configuration

1. **Setup System Monitoring**
   ```bash
   # Configure monitoring
   sudo /opt/vless/scripts/monitoring.sh setup

   # Setup alerts
   sudo /opt/vless/scripts/monitoring.sh setup_alerts \
     --cpu-threshold 80 --memory-threshold 85
   ```

2. **Configure Performance Monitoring**
   ```bash
   # Enable performance logging
   sudo /opt/vless/scripts/monitoring.sh enable_performance_logging
   ```

## Verification and Testing

### System Verification

1. **Verify Service Status**
   ```bash
   # Check all services
   sudo systemctl status vless-vpn
   sudo systemctl status docker
   sudo systemctl status nginx

   # Verify Docker containers
   sudo docker ps
   ```

2. **Test Network Connectivity**
   ```bash
   # Test VPN port connectivity
   sudo /opt/vless/scripts/monitoring.sh test_connectivity

   # Test SSL certificate
   sudo /opt/vless/scripts/cert_management.sh test
   ```

3. **Verify File Permissions**
   ```bash
   # Check critical file permissions
   sudo /opt/vless/scripts/maintenance_utils.sh verify_permissions
   ```

### User Configuration Testing

1. **Create Test User**
   ```bash
   # Create test user
   sudo /opt/vless/scripts/user_management.sh add testuser

   # Generate configuration
   sudo /opt/vless/scripts/user_management.sh config testuser
   sudo /opt/vless/scripts/qr_generator.py testuser
   ```

2. **Test User Connection**
   ```bash
   # Monitor connections
   sudo /opt/vless/scripts/monitoring.sh connections

   # Test specific user
   sudo /opt/vless/scripts/monitoring.sh test_user testuser
   ```

### Telegram Bot Testing

1. **Test Bot Functionality**
   ```bash
   # Start bot
   sudo systemctl start vless-telegram-bot

   # Check bot status
   sudo systemctl status vless-telegram-bot
   ```

2. **Test Bot Commands**
   - Send `/start` to your bot
   - Test `/status` command
   - Test user management commands

### Performance Testing

1. **Run Performance Tests**
   ```bash
   # System performance test
   sudo /opt/vless/scripts/monitoring.sh performance_test

   # Load testing
   sudo /opt/vless/scripts/monitoring.sh load_test
   ```

2. **Benchmark Network Performance**
   ```bash
   # Network throughput test
   sudo /opt/vless/scripts/monitoring.sh network_benchmark
   ```

## Troubleshooting Installation Issues

### Common Installation Problems

#### 1. Permission Denied Errors
```bash
# Problem: Permission denied during installation
# Solution: Ensure running with sudo
sudo ./install.sh

# Check file permissions
chmod +x install.sh
chmod +x modules/*.sh
```

#### 2. Network Connectivity Issues
```bash
# Problem: Cannot download dependencies
# Solution: Check internet connectivity
ping -c 4 8.8.8.8
curl -I https://github.com

# Check DNS resolution
nslookup github.com
```

#### 3. Docker Installation Fails
```bash
# Problem: Docker installation fails
# Solution: Manual Docker installation
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Then retry installation
sudo ./install.sh --skip-docker
```

#### 4. Certificate Generation Fails
```bash
# Problem: Let's Encrypt certificate generation fails
# Solution: Check domain DNS and firewall
nslookup your-domain.com
sudo ufw status

# Test HTTP connectivity
curl -I http://your-domain.com

# Manual certificate generation
sudo /opt/vless/scripts/cert_management.sh generate --manual
```

#### 5. Service Startup Failures
```bash
# Problem: VPN service fails to start
# Solution: Check logs and configuration
sudo journalctl -u vless-vpn -n 50
sudo /opt/vless/scripts/configure.sh validate

# Restart services
sudo systemctl restart docker
sudo systemctl restart vless-vpn
```

### Installation Log Analysis

1. **View Installation Logs**
   ```bash
   # View installation log
   sudo tail -f /opt/vless/logs/installation.log

   # Check error logs
   sudo grep -i error /opt/vless/logs/installation.log
   ```

2. **Debug Mode Installation**
   ```bash
   # Run installation in debug mode
   sudo ./install.sh --verbose --debug

   # Enable detailed logging
   export DEBUG=1
   sudo -E ./install.sh
   ```

### System Diagnostics

1. **Run System Diagnostics**
   ```bash
   # Comprehensive system check
   sudo /opt/vless/scripts/maintenance_utils.sh check_system_health

   # Generate diagnostic report
   sudo /opt/vless/scripts/maintenance_utils.sh generate_diagnostics
   ```

2. **Check System Resources**
   ```bash
   # Check disk space
   df -h

   # Check memory usage
   free -h

   # Check system load
   uptime
   ```

## Advanced Installation Options

### Custom Installation Phases

Execute specific installation phases individually:

```bash
# Phase 1: Environment validation
sudo ./install.sh --phase validate_environment

# Phase 2: Foundation setup
sudo ./install.sh --phase setup_foundation

# Phase 3: Dependencies installation
sudo ./install.sh --phase install_dependencies

# Phase 4: Docker setup
sudo ./install.sh --phase setup_docker

# Phase 5: Core installation
sudo ./install.sh --phase install_core

# Phase 6: Security hardening
sudo ./install.sh --phase security_hardening

# Phase 7: Service configuration
sudo ./install.sh --phase configure_services

# Phase 8: Optional components
sudo ./install.sh --phase install_optional

# Phase 9: Testing and validation
sudo ./install.sh --phase validate_installation
```

### Installation with Custom Configuration

1. **Create Advanced Configuration File**
   ```bash
   cat > config/advanced.env << EOF
   # Network Configuration
   VLESS_PORT=8443
   REALITY_PORT=443
   ENABLE_GRPC=true

   # Performance Settings
   MAX_CONNECTIONS=1000
   BUFFER_SIZE=4096

   # Security Settings
   SECURITY_LEVEL=maximum
   ENABLE_DPI_BYPASS=true

   # Monitoring
   ENABLE_METRICS=true
   METRICS_PORT=9090

   # Backup Configuration
   BACKUP_RETENTION=90d
   BACKUP_COMPRESSION=true

   # Telegram Bot
   BOT_WEBHOOK_MODE=true
   BOT_WEBHOOK_PORT=8443
   EOF
   ```

2. **Run Installation with Advanced Configuration**
   ```bash
   sudo ./install.sh --config config/advanced.env --verbose
   ```

### Multi-Server Installation

For deploying across multiple servers:

1. **Prepare Master Configuration**
   ```bash
   # Create master configuration
   cat > config/master.env << EOF
   # Master server configuration
   ROLE=master
   CLUSTER_MODE=true
   CLUSTER_SECRET=your_secret_key

   # Database configuration for user sync
   ENABLE_DATABASE_SYNC=true
   DATABASE_HOST=master.example.com
   EOF
   ```

2. **Prepare Worker Configuration**
   ```bash
   # Create worker configuration
   cat > config/worker.env << EOF
   # Worker server configuration
   ROLE=worker
   CLUSTER_MODE=true
   CLUSTER_SECRET=your_secret_key
   MASTER_HOST=master.example.com

   # Sync configuration from master
   SYNC_USERS=true
   SYNC_CONFIG=true
   EOF
   ```

### Container-Only Installation

For Docker-only deployment:

```bash
# Install only Docker components
sudo ./install.sh --container-only

# Use Docker Compose
sudo docker-compose up -d

# Configure through container
sudo docker exec -it vless-vpn /opt/vless/scripts/configure.sh
```

### Development Installation

For development and testing:

```bash
# Install in development mode
sudo ./install.sh --dev-mode

# Enable debug logging
sudo ./install.sh --dev-mode --debug

# Skip production security measures
sudo ./install.sh --dev-mode --skip-security
```

---

This installation guide provides comprehensive instructions for installing the VLESS+Reality VPN Management System. Follow the appropriate method based on your requirements and technical expertise. For additional support, refer to the troubleshooting section or consult the user guide.