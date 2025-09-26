# VLESS+Reality VPN Service Manager

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-Linux-blue)](https://www.linux.org/)
[![Bash](https://img.shields.io/badge/bash-5.0%2B-green)](https://www.gnu.org/software/bash/)
[![Docker](https://img.shields.io/badge/docker-required-blue)](https://www.docker.com/)

A minimalistic, secure, and easy-to-use VPN service manager for deploying VLESS protocol with Reality transport. Designed for small-scale deployments supporting up to 10 concurrent users with a focus on simplicity and security.

## Features

- **VLESS Protocol** with Reality transport for enhanced security
- **Docker-based** deployment for consistency and portability
- **CLI-only interface** for server management
- **User management** with secure credential generation
- **Automated installation** with dependency checking
- **Minimal logging** for privacy
- **Multi-architecture support** (x86_64, ARM64)

## Table of Contents

- [System Requirements](#system-requirements)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Usage](#usage)
  - [Service Management](#service-management)
  - [User Management](#user-management)
  - [System Commands](#system-commands)
- [Configuration](#configuration)
- [Client Setup](#client-setup)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)
- [Development](#development)
- [License](#license)

## System Requirements

### Hardware Requirements
- **RAM**: Minimum 512 MB
- **Disk Space**: Minimum 1 GB free
- **Architecture**: x86_64 or ARM64

### Software Requirements
- **Operating System**:
  - Ubuntu 20.04 or newer
  - Debian 11 or newer
- **Network**: Port 443 must be available
- **Privileges**: Root or sudo access required

### Automatically Installed Dependencies
- Docker CE
- Docker Compose plugin
- Xray-core (via Docker container)

## Quick Start

```bash
# Clone the repository
git clone https://github.com/yourusername/vless.git
cd vless

# Run installation
sudo ./vless-manager.sh install

# Start the service
sudo ./vless-manager.sh start

# Add your first user
sudo ./vless-manager.sh add-user john_doe

# Show user configuration (for client setup)
sudo ./vless-manager.sh show-user john_doe
```

## Installation

### Step 1: Download the Project

```bash
# Clone via Git
git clone https://github.com/yourusername/vless.git
cd vless

# Or download the release
wget https://github.com/yourusername/vless/releases/download/v1.0.0/vless.tar.gz
tar -xzvf vless.tar.gz
cd vless
```

### Step 2: Run Installation

```bash
# Make the script executable
chmod +x vless-manager.sh

# Run the installation
sudo ./vless-manager.sh install
```

The installation process will:
1. Check system requirements
2. Install Docker and Docker Compose if needed
3. Create the necessary directory structure
4. Generate server configuration and keys
5. Prepare the environment

### Step 3: Start the Service

```bash
sudo ./vless-manager.sh start
```

## Usage

### Service Management

#### Start Service
```bash
sudo ./vless-manager.sh start
```
Starts the VPN service and verifies it's running properly.

#### Stop Service
```bash
sudo ./vless-manager.sh stop
```
Gracefully stops the VPN service.

#### Restart Service
```bash
sudo ./vless-manager.sh restart
```
Restarts the VPN service (useful after configuration changes).

#### Check Status
```bash
sudo ./vless-manager.sh status
```
Shows the current service status and health information.

#### View Logs
```bash
# View last 50 lines
sudo ./vless-manager.sh logs

# Follow logs in real-time
sudo ./vless-manager.sh logs --follow

# View specific number of lines
sudo ./vless-manager.sh logs --lines 100
```

### User Management

#### Add User
```bash
sudo ./vless-manager.sh add-user username
```
Creates a new VPN user with automatically generated secure credentials.

**Username requirements:**
- Length: 3-20 characters
- Allowed: letters, numbers, underscore, dash
- Cannot start/end with special characters
- Case-insensitive (stored in lowercase)
- Reserved names not allowed (e.g., root, admin)

#### Remove User
```bash
sudo ./vless-manager.sh remove-user username
```
Removes a user and their configurations.

#### List Users
```bash
sudo ./vless-manager.sh list-users
```
Displays all configured users with their status.

#### Show User Details
```bash
sudo ./vless-manager.sh show-user username
```
Shows detailed user information including:
- VLESS URL for easy import
- QR code for mobile clients
- Configuration file locations

### System Commands

#### View Help
```bash
./vless-manager.sh help
```
Displays comprehensive help information.

#### Uninstall Service
```bash
sudo ./vless-manager.sh uninstall
```
Completely removes the VPN service, including:
- Docker containers and images
- User configurations and data
- Logs and temporary files

**Note**: The main script is preserved for potential reinstallation.

## Configuration

### Environment Variables

The service uses a `.env` file for configuration. Example:

```bash
# Project paths
PROJECT_PATH=/opt/vless

# Network configuration
SERVER_IP=your.server.ip
XRAY_PORT=443

# Logging
LOG_LEVEL=warning  # Options: debug, info, warning, error, none
```

### Server Configuration

The server configuration is automatically generated during installation. Key settings:

- **Protocol**: VLESS with Reality
- **Port**: 443 (HTTPS)
- **Camouflage**: speed.cloudflare.com
- **Encryption**: None (handled by Reality)

### File Structure

```
vless/
├── vless-manager.sh      # Main management script
├── docker-compose.yml    # Docker services configuration
├── .env                  # Environment variables
├── config/
│   ├── server.json       # Xray server configuration
│   └── users/            # User configurations
│       └── username/
│           ├── config.json
│           └── vless.url
├── data/
│   ├── users.db          # User database
│   └── keys/             # Cryptographic keys
└── logs/
    └── xray.log          # Service logs
```

## Client Setup

### Supported Clients

- **Windows**: V2rayN, Qv2ray
- **macOS**: V2rayU, Qv2ray
- **Linux**: V2ray-core, Qv2ray
- **Android**: V2rayNG, SagerNet
- **iOS**: Shadowrocket, Quantumult X

### Import Methods

#### Method 1: VLESS URL (Recommended)

1. Get the VLESS URL:
   ```bash
   sudo ./vless-manager.sh show-user username
   ```
2. Copy the VLESS URL starting with `vless://`
3. Import it into your client application

#### Method 2: QR Code

1. Display user information:
   ```bash
   sudo ./vless-manager.sh show-user username
   ```
2. Scan the QR code with your mobile client

#### Method 3: Manual Configuration

1. Get the configuration file:
   ```bash
   cat config/users/username/config.json
   ```
2. Import or manually enter the settings in your client

### Client Configuration Parameters

- **Address**: Your server's IP address
- **Port**: 443
- **User ID**: Automatically generated UUID
- **Encryption**: none
- **Flow**: (leave empty)
- **Network**: tcp
- **Security**: reality
- **SNI**: speed.cloudflare.com
- **Public Key**: Shown in user details
- **Short ID**: Shown in user details

## Troubleshooting

### Common Issues

#### Installation Fails

**Problem**: Installation script fails with permission errors.

**Solution**:
```bash
# Ensure running with sudo
sudo ./vless-manager.sh install

# Check if user has sudo privileges
sudo -v
```

#### Service Won't Start

**Problem**: Service fails to start or immediately stops.

**Solution**:
```bash
# Check Docker status
sudo systemctl status docker

# Start Docker if not running
sudo systemctl start docker

# Check port availability
sudo lsof -i :443

# View detailed logs
sudo ./vless-manager.sh logs --lines 100
```

#### Cannot Add Users

**Problem**: User creation fails with "user limit reached" error.

**Solution**:
- Maximum 10 users supported
- Remove inactive users:
  ```bash
  sudo ./vless-manager.sh list-users
  sudo ./vless-manager.sh remove-user old_username
  ```

#### Client Cannot Connect

**Problem**: Client shows connection errors.

**Checklist**:
1. Verify service is running:
   ```bash
   sudo ./vless-manager.sh status
   ```
2. Check firewall allows port 443:
   ```bash
   sudo ufw status
   sudo ufw allow 443/tcp
   ```
3. Verify server IP is correct in client
4. Ensure credentials match exactly (case-sensitive)
5. Check system time synchronization:
   ```bash
   timedatectl status
   ```

### Debug Mode

For detailed troubleshooting, edit `.env` and set:
```bash
LOG_LEVEL=debug
```

Then restart the service:
```bash
sudo ./vless-manager.sh restart
sudo ./vless-manager.sh logs --follow
```

### Getting Help

1. Check the built-in help:
   ```bash
   ./vless-manager.sh help
   ```

2. Review logs for error messages:
   ```bash
   sudo ./vless-manager.sh logs --lines 200
   ```

3. Report issues: [GitHub Issues](https://github.com/yourusername/vless/issues)

## Security Considerations

### Best Practices

1. **Keep Software Updated**
   ```bash
   # Update system packages
   sudo apt update && sudo apt upgrade

   # Pull latest Docker images
   docker pull teddysun/xray:latest
   ```

2. **Secure Your Server**
   - Use SSH key authentication
   - Configure firewall (ufw/iptables)
   - Regular security updates
   - Monitor access logs

3. **User Management**
   - Use strong, unique usernames
   - Regularly audit user list
   - Remove unused accounts
   - Monitor user connections

4. **Backup Important Data**
   ```bash
   # Backup configuration and users
   tar -czf vless-backup-$(date +%Y%m%d).tar.gz config/ data/
   ```

### Security Features

- **No hardcoded credentials**: All secrets generated dynamically
- **Minimal logging**: Only essential information logged
- **Secure file permissions**: 600 for sensitive files, 700 for directories
- **Input validation**: All user inputs sanitized
- **Docker isolation**: Service runs in containerized environment

### Privacy

- Minimal logging by default (warning level)
- No user traffic logging
- No telemetry or analytics
- All data stored locally

## Development

### Running Tests

```bash
# Run all tests
cd tests
./run_all_tests.sh run

# Run specific test suite
./run_all_tests.sh run-suite integration

# Run with verbose output
./run_all_tests.sh run -v
```

### Project Structure

- `vless-manager.sh` - Main management script
- `tests/` - Comprehensive test suite
- `docs/` - Additional documentation
- `requests/` - Development requests and plans

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add/update tests
5. Submit a pull request

### Development Requirements

- Bash 5.0+
- Docker and Docker Compose
- Python 3 (for JSON validation)
- Standard Unix utilities

## Examples

### Example 1: Complete Setup for New Server

```bash
# 1. Update system
sudo apt update && sudo apt upgrade -y

# 2. Clone and install
git clone https://github.com/yourusername/vless.git
cd vless
sudo ./vless-manager.sh install

# 3. Start service
sudo ./vless-manager.sh start

# 4. Add users
sudo ./vless-manager.sh add-user alice
sudo ./vless-manager.sh add-user bob

# 5. Get configurations
sudo ./vless-manager.sh show-user alice
sudo ./vless-manager.sh show-user bob
```

### Example 2: Migration from Another Server

```bash
# On old server - backup
tar -czf vless-backup.tar.gz config/ data/

# Transfer to new server
scp vless-backup.tar.gz user@newserver:/tmp/

# On new server - restore
cd /opt/vless
tar -xzf /tmp/vless-backup.tar.gz
sudo ./vless-manager.sh restart
```

### Example 3: Automated User Management

```bash
#!/bin/bash
# Script to add multiple users

users=("john" "jane" "jack" "jill")

for user in "${users[@]}"; do
    sudo ./vless-manager.sh add-user "$user"
    echo "Added user: $user"
done

# List all users
sudo ./vless-manager.sh list-users
```

### Example 4: Monitoring Script

```bash
#!/bin/bash
# Simple monitoring script

while true; do
    clear
    echo "=== VLESS Service Status ==="
    sudo ./vless-manager.sh status
    echo
    echo "=== Active Users ==="
    sudo ./vless-manager.sh list-users
    echo
    echo "=== Recent Logs ==="
    sudo ./vless-manager.sh logs --lines 10
    sleep 60
done
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Xray-core](https://github.com/XTLS/Xray-core) - The core proxy implementation
- [Docker](https://www.docker.com/) - Containerization platform
- [teddysun/xray](https://hub.docker.com/r/teddysun/xray) - Docker image maintainer

## Support

For issues, questions, or contributions, please visit our [GitHub repository](https://github.com/yourusername/vless).

---

**Version**: 1.0.0
**Last Updated**: January 2025
**Maintainer**: VLESS VPN Team