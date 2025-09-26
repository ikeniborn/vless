# Remote Server Setup Guide

This guide explains how to deploy VLESS+Reality VPN on a remote server.

## Prerequisites

- Ubuntu 20.04+ or Debian 11+ server
- Root or sudo access
- Port 443 available
- Public IP address

## Quick Setup

### Step 1: Clone the Repository

```bash
# Clone the repository to your server
git clone https://github.com/yourusername/vless.git
cd vless

# Make the script executable
chmod +x vless-manager.sh
```

### Step 2: Configure Environment

**IMPORTANT:** You must create the `.env` file before running installation.

```bash
# Copy the example configuration
cp .env.example .env

# Edit the configuration file
nano .env
```

Update the following values in `.env`:

1. **PROJECT_PATH**: Set to your installation directory (e.g., `/home/ubuntu/vless`)
2. **SERVER_IP**: Replace `YOUR_SERVER_PUBLIC_IP` with your server's actual public IP
3. **LOG_FILE**: Update path to match your PROJECT_PATH

Example `.env` configuration:
```env
PROJECT_PATH=/home/ubuntu/vless
SERVER_IP=203.0.113.42  # Your actual server IP
LOG_FILE=/home/ubuntu/vless/logs/xray.log
USERS_DB=/home/ubuntu/vless/data/users.db
KEYS_DIR=/home/ubuntu/vless/data/keys
```

### Step 3: Run Installation

```bash
# Run the installation
sudo ./vless-manager.sh install
```

The installation will:
- Check system requirements
- Install Docker and Docker Compose
- Generate X25519 keys
- Create server configuration
- Initialize user database

### Step 4: Start the Service

```bash
# Start the VPN service
sudo ./vless-manager.sh start

# Check service status
sudo ./vless-manager.sh status
```

## User Management

### Add a User

```bash
sudo ./vless-manager.sh add-user john
```

This will:
- Create a new user with UUID and shortId
- Generate client configuration files
- Display connection details and QR code

### List Users

```bash
sudo ./vless-manager.sh list-users
```

### Remove a User

```bash
sudo ./vless-manager.sh remove-user john
```

## Troubleshooting

### Service Won't Start

If you see errors about missing configuration files:

1. Check that `.env` file exists and is configured:
   ```bash
   cat .env | grep SERVER_IP
   ```

2. Ensure the SERVER_IP is set to your actual public IP:
   ```bash
   curl -s https://ipv4.icanhazip.com/
   ```

3. Re-run the installation:
   ```bash
   sudo ./vless-manager.sh install
   ```

### Container Keeps Restarting

Check the logs:
```bash
sudo ./vless-manager.sh logs --lines 50
```

Common issues:
- Missing configuration files → Run `sudo ./vless-manager.sh install`
- Port 443 already in use → Stop other services using port 443
- Invalid configuration → Check `.env` file settings

### Permission Denied Errors

Ensure proper ownership:
```bash
sudo chown -R $USER:$USER /home/ubuntu/vless
sudo chmod 755 vless-manager.sh
```

## Security Recommendations

1. **Firewall Configuration**
   ```bash
   # Allow only necessary ports
   sudo ufw allow 22/tcp   # SSH
   sudo ufw allow 443/tcp  # VLESS
   sudo ufw enable
   ```

2. **File Permissions**
   ```bash
   # Protect sensitive files
   chmod 600 .env
   chmod 700 data/
   chmod 700 config/
   ```

3. **Regular Updates**
   ```bash
   # Update system packages
   sudo apt update && sudo apt upgrade -y

   # Update Docker images
   docker pull teddysun/xray:latest
   sudo ./vless-manager.sh restart
   ```

## Backup and Restore

### Backup Configuration

```bash
# Create backup directory
mkdir -p ~/vless-backup

# Backup important files
cp -r config/ ~/vless-backup/
cp -r data/ ~/vless-backup/
cp .env ~/vless-backup/
```

### Restore Configuration

```bash
# Restore from backup
cp -r ~/vless-backup/config/ ./
cp -r ~/vless-backup/data/ ./
cp ~/vless-backup/.env ./

# Set correct permissions
chmod 600 .env
chmod -R 700 config/ data/

# Restart service
sudo ./vless-manager.sh restart
```

## Common Commands Reference

```bash
# Service management
sudo ./vless-manager.sh start      # Start service
sudo ./vless-manager.sh stop       # Stop service
sudo ./vless-manager.sh restart    # Restart service
sudo ./vless-manager.sh status     # Check status

# User management
sudo ./vless-manager.sh add-user USERNAME     # Add user
sudo ./vless-manager.sh remove-user USERNAME  # Remove user
sudo ./vless-manager.sh list-users           # List all users
sudo ./vless-manager.sh show-user USERNAME   # Show user details

# Maintenance
sudo ./vless-manager.sh logs               # View logs
sudo ./vless-manager.sh logs --follow      # Follow logs
sudo ./vless-manager.sh uninstall          # Uninstall service
```

## Support

For issues or questions:
1. Check the logs: `sudo ./vless-manager.sh logs`
2. Review this documentation
3. Check the main README.md
4. Open an issue on GitHub