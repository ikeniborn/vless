# VLESS+Reality VPN Management System - Project Memory

## Project Overview
- **Name**: VLESS+Reality VPN Management System
- **Purpose**: Automated VPN server management with VLESS+Reality protocol for censorship resistance
- **Architecture**: Modular bash scripts + Python Telegram bot + Docker infrastructure
- **Target OS**: Ubuntu/Debian and RHEL-based Linux distributions

## Directory Structure
- **Main directory**: `/home/ikeniborn/Documents/Project/vless/`
- **Configuration storage**: `/opt/vless/` (production configs, logs, backups)
- **Modules**: `modules/` - all bash and Python modules
- **Tests**: `tests/` - comprehensive test suite
- **Documentation**: `docs/` - user and API documentation
- **Config templates**: `config/` - Docker, Xray, and bot configurations

## Key Components

### Installation and Core (Phase 1)
- **Main installer**: `install.sh` - orchestrates entire installation
- **Common utilities**: `modules/common_utils.sh` - logging, validation, system checks
- **Logging system**: `modules/logging_setup.sh` - centralized logging with rotation
- **Use 4-space indentation** in all bash scripts
- **Always check root permissions** before system modifications
- **Color output**: Use RED for errors, YELLOW for warnings, GREEN for success

### Docker Infrastructure (Phase 2)
- **Docker setup**: `modules/docker_setup.sh` - installs and configures Docker
- **Container management**: `modules/container_management.sh` - lifecycle operations
- **Xray config**: `config/xray_config_template.json` - VLESS+Reality template
- **Docker Compose**: `config/docker-compose.yml` - service definitions
- **Use host networking** for Reality protocol performance
- **Always validate Docker installation** before container operations

### User Management (Phase 3)
- **User CRUD**: `modules/user_management.sh` - add/remove/list users
- **QR generator**: `modules/qr_generator.py` - creates QR codes for clients
- **Config templates**: `modules/config_templates.sh` - multi-client support
- **Database**: `modules/user_database.sh` - JSON-based user storage
- **Store user data** in `/opt/vless/users/users.json`
- **Generate unique UUIDs** for each user
- **Support multiple VPN clients**: Xray, V2Ray, Clash, sing-box

### Security (Phase 4)
- **UFW config**: `modules/ufw_config.sh` - firewall management
- **Hardening**: `modules/security_hardening.sh` - SSH and system security
- **Certificates**: `modules/cert_management.sh` - TLS certificate handling
- **Monitoring**: `modules/monitoring.sh` - system health checks
- **Open port 443** for VLESS+Reality
- **Backup UFW rules** before modifications
- **Enable fail2ban** for brute-force protection

### Advanced Features (Phase 5)
- **Telegram bot**: `modules/telegram_bot.py` - remote management interface
- **Bot manager**: `modules/telegram_bot_manager.sh` - bot service control
- **Backup/Restore**: `modules/backup_restore.sh` - data protection
- **Maintenance**: `modules/maintenance_utils.sh` - system optimization
- **Updates**: `modules/system_update.sh` - safe system updates
- **Bot config**: Store in `config/bot_config.env`
- **Admin whitelist required** for bot access
- **Daily automated backups** to `/opt/vless/backups/`

## Testing Framework
- **Master runner**: `tests/run_all_tests.sh` - executes all tests
- **Result aggregator**: `tests/test_results_aggregator.sh` - analyzes results
- **Phase tests**: Separate integration tests for each implementation phase
- **Always run tests** before deployment
- **Use dry-run mode** for safe testing

## Critical Paths
- **Installation flow**: `install.sh` ’ Phase modules ’ Docker ’ User setup ’ Security ’ Bot
- **User addition**: Validate ’ Generate UUID ’ Update Xray config ’ Reload service ’ Generate QR
- **Backup process**: Stop services ’ Backup configs ’ Backup users ’ Create archive ’ Restart

## Command Patterns

### Installation
```bash
sudo ./install.sh [--verbose] [--dry-run] [--help]
```

### User Management
```bash
./install.sh manage users  # Interactive menu
./install.sh add-user USERNAME
./install.sh remove-user USERNAME
```

### Telegram Bot
```bash
sudo ./deploy_telegram_bot.sh  # Interactive setup
sudo systemctl status vless-vpn-bot
```

### Testing
```bash
cd tests && ./run_all_tests.sh
```

## Environment Variables
- `VLESS_HOME=/opt/vless` - Main configuration directory
- `VLESS_LOG_LEVEL=INFO` - Logging verbosity
- `VLESS_BOT_TOKEN` - Telegram bot API token
- `VLESS_ADMIN_IDS` - Comma-separated admin Telegram IDs

## Error Handling
- **Always use `set -euo pipefail`** in bash scripts
- **Implement rollback** for critical operations
- **Log all errors** to `/opt/vless/logs/error.log`
- **Return specific exit codes**: 0=success, 1=general error, 2=dependency error, 3=permission error

## Security Best Practices
- **Run containers with minimal privileges**
- **Use read-only mounts** where possible
- **Validate all user input**
- **Sanitize paths** to prevent directory traversal
- **Encrypt sensitive data** in backups
- **Rotate logs daily**, keep 7 days

## VLESS+Reality Protocol
- **Purpose**: Mask VPN traffic as regular HTTPS
- **Port**: 443 (standard HTTPS)
- **UUID-based authentication**: Each user has unique identifier
- **Reality settings**: Use multiple server names for camouflage
- **Client support**: Xray-core based clients recommended

## Docker Configuration
- **Network mode**: Host (for Reality protocol)
- **Restart policy**: unless-stopped
- **Resource limits**: Set CPU and memory constraints
- **Volumes**: `/opt/vless` mounted for persistence
- **Health checks**: Every 30 seconds

## Telegram Bot Commands
- `/start` - Initialize bot
- `/status` - System status
- `/adduser <name>` - Add VPN user
- `/removeuser <name>` - Remove user
- `/users` - List all users
- `/qr <username>` - Generate QR code
- `/backup` - Create backup
- `/help` - Show commands

## File Permissions
- **Config files**: 600 (root only)
- **Scripts**: 755 (executable)
- **Logs**: 644 (readable)
- **Backups**: 600 (root only)
- **User database**: 600 (root only)

## Monitoring Thresholds
- **CPU Warning**: >80% usage
- **Memory Warning**: >90% usage
- **Disk Warning**: >85% usage
- **Connection limit**: 1000 concurrent users
- **Log size limit**: 100MB per file

## Backup Strategy
- **Frequency**: Daily at 3 AM
- **Retention**: 7 daily, 4 weekly
- **Components**: Configs, users, certificates, logs
- **Compression**: tar.gz with timestamp
- **Validation**: Check archive integrity

## Update Process
1. Create system snapshot
2. Stop services gracefully
3. Backup current version
4. Apply updates
5. Validate configuration
6. Restart services
7. Run health checks
8. Rollback on failure

## Known Issues and Solutions
- **EPERM errors**: Use proper error handling in scripts
- **Docker permission**: Add user to docker group
- **UFW conflicts**: Always backup rules first
- **Port 443 in use**: Check existing services
- **Bot connection**: Verify token and network access

## Development Guidelines
- **Test all changes** in dry-run mode first
- **Document new functions** with comments
- **Follow existing code style** and patterns
- **Update tests** when adding features
- **Version control**: Commit logical units of work
- **Error messages**: Be specific and actionable

## Performance Optimization
- **Use bash built-ins** over external commands
- **Cache frequently used data**
- **Implement connection pooling**
- **Optimize Docker images** (multi-stage builds)
- **Compress logs** and old backups
- **Rate limit API calls**

## Integration Points
- **Systemd**: Service management and auto-start
- **Logrotate**: Automatic log rotation
- **Cron**: Scheduled backups and maintenance
- **UFW**: Firewall rule management
- **Docker**: Container orchestration
- **Telegram API**: Bot communication

## Quick Troubleshooting
- **Service not starting**: Check logs in `/opt/vless/logs/`
- **Connection issues**: Verify UFW rules and ports
- **Bot not responding**: Check token and admin IDs
- **User can't connect**: Validate UUID and client config
- **High resource usage**: Check monitoring metrics
- **Backup failure**: Verify disk space and permissions