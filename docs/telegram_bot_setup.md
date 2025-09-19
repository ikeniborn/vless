# VLESS VPN Telegram Bot Setup Guide

## Overview

The VLESS VPN Telegram Bot provides a convenient interface for managing your VPN server through Telegram. You can add/remove users, monitor system status, generate QR codes, and perform administrative tasks directly from Telegram.

## Features

### User Management
- ➕ Add new VPN users
- 🗑️ Delete existing users
- 👥 List all users with UUIDs
- 📋 Get user configurations (VLESS URLs)
- 📱 Generate QR codes for mobile apps

### System Management
- 📊 Check server status and resource usage
- 🔄 Restart VPN services
- 📋 View system logs
- 💾 Create and manage backups
- 📈 View usage statistics

### Security Features
- 🔐 Admin-only access control
- 🛡️ Input validation and sanitization
- 📝 Comprehensive logging
- ⚠️ Confirmation dialogs for destructive actions

## Prerequisites

1. **Telegram Bot Token**
   - Contact [@BotFather](https://t.me/BotFather) on Telegram
   - Create a new bot: `/newbot`
   - Get your bot token (format: `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`)

2. **Admin Telegram ID**
   - Contact [@userinfobot](https://t.me/userinfobot) to get your user ID
   - Your ID is a numeric value (e.g., `123456789`)

3. **System Requirements**
   - Docker and Docker Compose installed
   - Python 3.11+ (handled by Docker)
   - Access to the VLESS project directory

## Installation Steps

### 1. Clone/Setup Project

```bash
# Navigate to your project directory
cd /home/ikeniborn/Documents/Project/vless

# Ensure proper permissions
sudo chmod +x modules/*.sh
```

### 2. Configure Environment Variables

```bash
# Copy the example configuration
cp .env.example .env

# Edit the configuration file
nano .env
```

**Required Configuration:**
```bash
# Your bot token from BotFather
TELEGRAM_BOT_TOKEN=123456789:ABCdefGHIjklMNOpqrsTUVwxyz

# Your Telegram user ID
ADMIN_TELEGRAM_ID=123456789

# Your server information
SERVER_IP=1.2.3.4
DOMAIN=yourdomain.com
VLESS_PORT=443
```

### 3. Build and Start the Bot

```bash
# Using the bot manager script
./modules/telegram_bot_manager.sh build
./modules/telegram_bot_manager.sh start

# Or using Docker Compose directly
cd config
docker-compose up -d telegram-bot
```

### 4. Verify Installation

```bash
# Check bot status
./modules/telegram_bot_manager.sh status

# View logs
./modules/telegram_bot_manager.sh logs

# Test configuration
./modules/telegram_bot_manager.sh test
```

## Bot Commands

### User Management Commands

| Command | Description | Example |
|---------|-------------|---------|
| `/start` | Show welcome message and main menu | `/start` |
| `/help` | Display help information | `/help` |
| `/adduser <name>` | Create a new VPN user | `/adduser john` |
| `/deleteuser <uuid>` | Delete user by UUID | `/deleteuser a1b2c3d4-...` |
| `/listusers` | Show all users with UUIDs | `/listusers` |
| `/getconfig <uuid>` | Get VLESS URL for user | `/getconfig a1b2c3d4-...` |
| `/getqr <uuid>` | Get QR code for mobile apps | `/getqr a1b2c3d4-...` |

### System Management Commands

| Command | Description | Example |
|---------|-------------|---------|
| `/status` | Check server and container status | `/status` |
| `/restart` | Restart VPN services | `/restart` |
| `/logs` | View recent system logs | `/logs` |
| `/backup` | Create system backup | `/backup` |
| `/stats` | Show usage statistics | `/stats` |

## Usage Examples

### Adding a New User

1. Send `/adduser john` to the bot
2. Bot creates user and responds with UUID
3. Use inline buttons to get config or QR code
4. Share VLESS URL or QR code with the user

### Getting User Configuration

1. Send `/listusers` to see all users and their UUIDs
2. Copy the UUID of the desired user
3. Send `/getconfig <uuid>` to get the VLESS URL
4. Send `/getqr <uuid>` to get a QR code

### Managing the Server

1. Send `/status` to check system health
2. Send `/logs` to troubleshoot issues
3. Send `/backup` before making changes
4. Send `/restart` if services need restarting

## Management Scripts

The bot includes a management script for administrative tasks:

```bash
# Bot management commands
./modules/telegram_bot_manager.sh start       # Start the bot
./modules/telegram_bot_manager.sh stop        # Stop the bot
./modules/telegram_bot_manager.sh restart     # Restart the bot
./modules/telegram_bot_manager.sh status      # Check status
./modules/telegram_bot_manager.sh logs 100    # View last 100 logs
./modules/telegram_bot_manager.sh build       # Rebuild image
./modules/telegram_bot_manager.sh update      # Update and restart
./modules/telegram_bot_manager.sh test        # Test configuration
```

## Troubleshooting

### Common Issues

1. **Bot doesn't respond**
   ```bash
   # Check if container is running
   docker ps | grep telegram-bot

   # Check logs for errors
   ./modules/telegram_bot_manager.sh logs

   # Test configuration
   ./modules/telegram_bot_manager.sh test
   ```

2. **"Access denied" message**
   - Verify your Telegram ID is correct in `.env`
   - Check that `ADMIN_TELEGRAM_ID` is numeric
   - Restart the bot after configuration changes

3. **QR codes not generating**
   ```bash
   # Check if qrencode is installed in container
   docker exec vless-telegram-bot which qrencode

   # Rebuild the image if needed
   ./modules/telegram_bot_manager.sh build
   ```

4. **User management errors**
   ```bash
   # Check if user management script is accessible
   docker exec vless-telegram-bot ls -la /app/modules/

   # Check volume mounts
   docker inspect vless-telegram-bot | grep -A 10 Mounts
   ```

### Log Locations

- **Bot Logs**: `/opt/vless/logs/telegram_bot.log`
- **Docker Logs**: `docker logs vless-telegram-bot`
- **System Logs**: `journalctl -u docker`

### Configuration Validation

```bash
# Validate configuration
./modules/telegram_bot_manager.sh validate

# Test bot connection
./modules/telegram_bot_manager.sh test

# Show current configuration
./modules/telegram_bot_manager.sh config
```

## Security Considerations

1. **Token Security**
   - Never share your bot token
   - Use environment variables, not hardcoded values
   - Regenerate token if compromised

2. **Access Control**
   - Only authorized Telegram IDs can use the bot
   - Admin verification on every command
   - Confirmation dialogs for destructive actions

3. **Container Security**
   - Bot runs as non-root user
   - Limited container permissions
   - Read-only mounts where possible

4. **Network Security**
   - Bot communicates only with Telegram API
   - Internal Docker network isolation
   - No exposed ports for bot service

## Backup and Recovery

### Creating Backups

```bash
# Automatic backup (includes all configs)
./modules/telegram_bot_manager.sh backup

# Manual backup
tar -czf bot_backup.tar.gz config/ modules/ .env
```

### Restoration

```bash
# Stop services
./modules/telegram_bot_manager.sh stop

# Restore files
tar -xzf bot_backup.tar.gz

# Restart services
./modules/telegram_bot_manager.sh start
```

## Advanced Configuration

### Custom Log Levels

```bash
# In .env file
LOG_LEVEL=DEBUG          # Verbose logging
LOG_LEVEL=INFO           # Standard logging (default)
LOG_LEVEL=WARNING        # Minimal logging
LOG_LEVEL=ERROR          # Error only
```

### Resource Limits

Edit `docker-compose.yml` to adjust resource limits:

```yaml
deploy:
  resources:
    limits:
      memory: 512M       # Increase if needed
      cpus: '1.0'        # Adjust based on usage
```

### Monitoring Alerts

Configure thresholds in `.env`:

```bash
CPU_ALERT_THRESHOLD=85      # CPU usage alert %
MEMORY_ALERT_THRESHOLD=85   # Memory usage alert %
DISK_ALERT_THRESHOLD=90     # Disk usage alert %
```

## Support

For issues and questions:

1. Check the logs: `./modules/telegram_bot_manager.sh logs`
2. Validate configuration: `./modules/telegram_bot_manager.sh test`
3. Review this documentation
4. Check the project repository for updates

## Version Information

- **Bot Version**: 1.0
- **Python**: 3.11+
- **python-telegram-bot**: 20.7
- **Docker**: Compatible with Docker 20.10+
- **Docker Compose**: v2.0+