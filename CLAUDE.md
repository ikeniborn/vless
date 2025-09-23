# VLESS+Reality VPN Management System - Project Memory

## Project Overview

The VLESS+Reality VPN Management System is a comprehensive, production-ready VPN solution that combines:
- **VLESS Protocol**: Latest generation proxy protocol with minimal overhead
- **Reality Obfuscation**: Advanced traffic camouflage mimicking legitimate HTTPS websites
- **Management System**: Complete user lifecycle and system administration
- **Security Hardening**: Automated security configurations and monitoring
- **Backup & Maintenance**: Comprehensive backup and system maintenance utilities

## Architecture & Structure

### Core System Layout
```
/opt/vless/                    # Main system directory
   config/                    # Configuration files
      config.json           # Main Xray configuration
      environment.conf      # Environment variables
      monitoring/           # Monitoring configurations
   scripts/                  # Management scripts (symlinks to modules)
   users/                    # User database and configurations
   certs/                    # SSL/TLS certificates
   logs/                     # System logs
   backup/                   # Backup storage
```

### Project Repository Structure
```
vless/
   install.sh                     # Main installation script (interactive menu)
   requirements.txt               # Python dependencies
   modules/                       # Core system modules
      common_utils.sh           # Logging, validation, utilities
      user_management.sh        # High-level user operations
      user_database.sh          # Database operations
      monitoring.sh             # System monitoring & alerts
      backup_restore.sh         # Backup/recovery system
      security_hardening.sh     # Security configurations
      docker_setup.sh           # Container management
      config_templates.sh       # Configuration generation
      cert_management.sh        # Certificate handling
      container_management.sh   # Docker operations
      logging_setup.sh          # Log management
      maintenance_utils.sh      # System maintenance
      system_update.sh          # Update management
      ufw_config.sh            # Firewall configuration
      qr_generator.py          # QR code generation
      phase4_integration.sh    # Phase 4 integration
   config/                       # Configuration templates
      docker-compose.yml       # Docker services
      xray_config_template.json # Xray configuration template
      vless-vpn.service        # SystemD service file
   docs/                        # Documentation
      installation.md         # Detailed installation guide
      user_guide.md           # Complete user manual
      api_reference.md        # Module API documentation
      troubleshooting.md      # Common issues & solutions
   tests/                      # Test suites
       run_all_tests.sh        # Master test runner
       results/                # Test results
```

## Key Design Decisions

### 1. Modular Architecture
- **Separation of Concerns**: Each module handles specific functionality
- **Reusability**: Modules can be used independently
- **Maintainability**: Easy to update individual components
- **Testing**: Each module can be tested in isolation

### 2. Phase-Based Installation
- **Phase 1**: Core Infrastructure (directories, dependencies, utilities)
- **Phase 2**: VLESS Server Implementation (Xray, Reality, containers)
- **Phase 3**: User Management System (database, CRUD operations)
- **Phase 4**: Security & Monitoring (hardening, alerts, logging)
- **Phase 5**: Backup and Maintenance (advanced backup strategies, system maintenance)

### 3. Security-First Design
- **Process Isolation**: EPERM prevention through signal handlers
- **Privilege Separation**: Minimal privilege requirements
- **Input Validation**: All user inputs validated
- **Secure Defaults**: Security-hardened default configurations
- **Audit Trail**: Comprehensive logging of all operations

### 4. Error Handling Strategy
- **Graceful Degradation**: System continues operation despite component failures
- **Comprehensive Logging**: All errors logged with context
- **Recovery Mechanisms**: Automatic service restart and backup recovery
- **User Feedback**: Clear error messages and resolution guidance

## Module Dependencies

### Core Dependencies Flow
```
common_utils.sh (base utilities)
   logging_setup.sh
   user_database.sh
      user_management.sh
   config_templates.sh
      cert_management.sh
   docker_setup.sh
      container_management.sh
   monitoring.sh
   backup_restore.sh
   security_hardening.sh
   maintenance_utils.sh
   system_update.sh
```

### External Dependencies
- **System**: Docker, Python 3.8+, SQLite3, UFW/firewalld
- **Python**: qrcode, Pillow, requests
- **Network**: Xray-core, OpenSSL, Let's Encrypt (optional)

## Database Schema

### User Database (SQLite)
```sql
-- Users table
CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT UNIQUE NOT NULL,
    uuid TEXT UNIQUE NOT NULL,
    name TEXT,
    flow TEXT DEFAULT 'xtls-rprx-vision',
    quota_gb INTEGER DEFAULT 100,
    used_gb REAL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP,
    status TEXT DEFAULT 'active',
    last_activity TIMESTAMP,
    description TEXT
);

-- Traffic logs table
CREATE TABLE traffic_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_email TEXT NOT NULL,
    bytes_in BIGINT DEFAULT 0,
    bytes_out BIGINT DEFAULT 0,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_email) REFERENCES users(email)
);

-- Activity logs table
CREATE TABLE activity_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_email TEXT,
    action TEXT NOT NULL,
    details TEXT,
    ip_address TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

## Configuration Management

### Environment Variables
```bash
# Core Server Settings
VLESS_PORT=443                    # VLESS service port
REALITY_DOMAIN="www.microsoft.com" # Reality camouflage domain
REALITY_PORT=443                  # Reality target port
SERVER_NAME="your-domain.com"     # Server domain name

# Security Settings
SSL_EMAIL="admin@yourdomain.com"  # Certificate email
ENABLE_FIREWALL=true              # Enable UFW firewall
AUTO_UPDATE=true                  # Enable automatic updates

# Monitoring Settings
ENABLE_MONITORING=true            # Enable system monitoring
LOG_LEVEL="INFO"                  # Logging level
ALERT_EMAIL="alerts@yourdomain.com" # Alert email address

# Backup Settings
BACKUP_RETENTION_DAYS=30          # Backup retention period
ENABLE_REMOTE_BACKUP=false        # Enable remote backup storage
```

### Xray Configuration Template
```json
{
  "log": {
    "loglevel": "info",
    "access": "/opt/vless/logs/access.log",
    "error": "/opt/vless/logs/error.log"
  },
  "inbounds": [{
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
        "dest": "www.microsoft.com:443",
        "serverNames": ["www.microsoft.com"],
        "privateKey": "",
        "shortIds": [""]
      }
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  }]
}
```

## Testing Requirements

### Test Categories
1. **Unit Tests**: Individual module functionality
2. **Integration Tests**: Module interaction testing
3. **Security Tests**: Security hardening verification
4. **Performance Tests**: Load and stress testing
5. **End-to-End Tests**: Complete system workflow

### Test Execution
```bash
# Run all tests
./tests/run_all_tests.sh

# Individual test categories
./tests/test_phase1_integration.sh  # Core infrastructure
./tests/test_phase2_integration.sh  # VLESS server
./tests/test_phase3_integration.sh  # User management
./tests/test_phase4_security.sh     # Security & monitoring
./tests/test_phase5_integration.sh  # Backup and maintenance
```

### Test Coverage Areas
- Module function execution
- Error handling and recovery
- Security policy compliance
- Performance benchmarks
- User workflow validation

## Security Considerations

### Threat Model
- **Network Attacks**: DDoS, port scanning, traffic analysis
- **System Intrusion**: Privilege escalation, malware installation
- **Data Breaches**: User data exposure, configuration theft
- **Service Disruption**: Resource exhaustion, service failures

### Security Measures
1. **Network Security**
   - Reality obfuscation for traffic camouflage
   - Firewall rules and port management
   - DDoS protection and rate limiting

2. **System Security**
   - Privilege separation and process isolation
   - Regular security updates
   - File permission hardening
   - Intrusion detection system

3. **Data Security**
   - Database encryption at rest
   - Secure configuration storage
   - Backup encryption
   - Audit logging

4. **Operational Security**
   - Admin authentication and authorization
   - Command rate limiting
   - Activity monitoring and alerting
   - Secure remote management

## Installation Modes (v1.1.0)

### Mode Selection
The system now supports three installation modes optimized for different use cases:

```bash
# Interactive mode selection
sudo ./install.sh

# Environment variable mode selection
sudo INSTALLATION_MODE=minimal ./install.sh
sudo INSTALLATION_MODE=balanced ./install.sh
sudo INSTALLATION_MODE=full ./install.sh

# Quick installation (minimal mode)
sudo QUICK_MODE=true ./install.sh
```

### Mode Configurations

#### Minimal Mode
- **Purpose**: Core VPN functionality only
- **Phases**: 1, 2, 3 (Infrastructure, VLESS, User Management)
- **Resource Usage**: 60% reduction in monitoring overhead
- **Features**: Basic VLESS+Reality, user management, minimal logging
- **Security**: Essential firewall only, no SSH hardening
- **Use Case**: Resource-constrained environments, container deployments

#### Balanced Mode
- **Purpose**: VPN with essential security features
- **Phases**: 1, 2, 3, 4 (+ Security and Monitoring)
- **Resource Usage**: Optimized monitoring with 5-minute intervals
- **Features**: Full VPN + selective security hardening
- **Security**: Configurable SSH hardening, UFW firewall, basic monitoring
- **Use Case**: Production servers, most common deployment

#### Full Mode
- **Purpose**: Complete feature set with all capabilities
- **Phases**: 1, 2, 3, 4, 5 (+ Backup and Maintenance)
- **Resource Usage**: Comprehensive monitoring with 1-minute intervals
- **Features**: All features including advanced backup strategies and maintenance utilities
- **Security**: Full security suite, comprehensive monitoring
- **Use Case**: Advanced deployments, development environments

### Safety Features

#### SSH Hardening Safety
```bash
# Automatic SSH key validation
check_ssh_keys()                    # Verify SSH keys before hardening
show_current_ssh_connections()      # Display current SSH sessions
apply_selective_ssh_hardening()     # Safe SSH configuration
create_restore_point()              # Backup before changes
```

#### System Validation
```bash
# Pre-operation safety checks
validate_system_state "ssh_hardening"
validate_system_state "firewall_config"
validate_system_state "service_restart"
```

#### Confirmation System
```bash
# Enhanced confirmations with timeout
confirm_action "Apply SSH hardening?" "n" 30
safe_service_restart "sshd" 30 false
```

## Common Operations

### User Management
```bash
# Create user
./scripts/user_management.sh add username --quota=100 --expires="2024-12-31"

# List users
./scripts/user_management.sh list

# Generate configuration
./scripts/user_management.sh config username

# Generate QR code
./scripts/user_management.sh qr username

# Delete user
./scripts/user_management.sh delete username
```

### System Monitoring
```bash
# System status
./scripts/monitoring.sh status

# Service health check
./scripts/monitoring.sh check xray

# View metrics
./scripts/monitoring.sh metrics

# Resource usage
./scripts/monitoring.sh resources
```

### Backup Operations
```bash
# Create backup
./scripts/backup_restore.sh backup

# Schedule backups
./scripts/backup_restore.sh schedule daily

# Restore from backup
./scripts/backup_restore.sh restore /path/to/backup.tar.gz
```

### System Maintenance
```bash
# System health check
./scripts/maintenance_utils.sh health_check

# Update system packages
./scripts/system_update.sh update

# Clean expired users
./scripts/user_management.sh cleanup

# Optimize database
./scripts/maintenance_utils.sh optimize_db
```

## Development Patterns

### Code Standards
1. **Shell Scripting**
   - Use `set -euo pipefail` for error handling
   - Validate all inputs before processing
   - Use readonly variables for constants
   - Implement proper signal handling

2. **Python Code**
   - Follow PEP 8 style guidelines
   - Use type hints for function parameters
   - Implement proper exception handling
   - Use async/await for I/O operations

3. **Error Handling**
   - Return appropriate exit codes
   - Log errors with context information
   - Provide user-friendly error messages
   - Implement recovery mechanisms

### Logging Standards
```bash
# Log levels and usage
log_debug "Detailed debugging information"
log_info "General information messages"
log_warn "Warning conditions"
log_error "Error conditions"
log_success "Success confirmations"
```

### Function Naming Conventions
- **Verbs for actions**: `add_user`, `remove_user`, `start_service`
- **Adjectives for checks**: `validate_email`, `check_service`
- **Nouns for getters**: `get_user_info`, `list_users`

## Maintenance Procedures

### Regular Maintenance
1. **Daily**
   - Check service status
   - Monitor resource usage
   - Review security logs

2. **Weekly**
   - Update system packages
   - Rotate log files
   - Verify backups

3. **Monthly**
   - Security audit
   - Performance review
   - Clean expired users

### Emergency Procedures
1. **Service Failure**: Restart services, check logs, restore from backup
2. **Security Breach**: Isolate system, audit logs, update credentials
3. **Resource Exhaustion**: Scale resources, optimize configuration
4. **Data Corruption**: Restore from backup, verify integrity

## Performance Optimization

### System Tuning
- Network buffer optimization
- File descriptor limits
- Connection pooling
- CPU affinity settings

### Monitoring Metrics
- CPU usage and load average
- Memory consumption and swap usage
- Disk I/O and space utilization
- Network throughput and connection count

### Scaling Considerations
- Horizontal scaling with multiple servers
- Load balancing and failover
- Database sharding for large user bases
- CDN integration for global distribution

## Future Enhancements

### Planned Features
1. **Web Dashboard**: Browser-based administration interface
2. **API Gateway**: RESTful API for third-party integrations
3. **Multi-server Support**: Centralized management of multiple servers
4. **Advanced Analytics**: Detailed usage analytics and reporting
5. **Mobile App**: Native mobile administration application

### Technical Debt
1. **Code Refactoring**: Improve module organization and reduce duplication
2. **Test Coverage**: Increase automated test coverage to 90%+
3. **Documentation**: Add inline code documentation and examples
4. **Performance**: Optimize database queries and system calls

---

## Quick Reference Commands

### Installation
```bash
git clone https://github.com/yourusername/vless.git
cd vless
sudo ./install.sh
```

### System Status
```bash
sudo systemctl status xray docker
sudo /opt/vless/scripts/monitoring.sh status
```

### User Operations
```bash
sudo /opt/vless/scripts/user_management.sh add username
sudo /opt/vless/scripts/user_management.sh config username
sudo /opt/vless/scripts/user_management.sh list
```

### Backup & Recovery
```bash
sudo /opt/vless/scripts/backup_restore.sh backup
sudo /opt/vless/scripts/backup_restore.sh restore /path/to/backup
```

### Troubleshooting
```bash
sudo journalctl -u xray -f
sudo /opt/vless/scripts/system_check.sh
sudo /opt/vless/scripts/diagnostic_report.sh
```

## Recent Updates

### v1.2.0 - Phase 5 Simplification

#### Major Changes
1. **Telegram Bot Removal**: Removed Telegram bot integration for simplified deployment
   - Eliminated `telegram_bot.py` and `telegram_bot_manager.sh` modules
   - Removed Python telegram-bot dependencies
   - Simplified configuration management
   - Reduced system complexity and resource usage

2. **Phase 5 Redefinition**: Transformed from "Advanced Features" to "Backup and Maintenance"
   - Enhanced backup strategies with multiple retention policies
   - Advanced system maintenance utilities
   - Automated cleanup and optimization tools
   - Simplified deployment for production environments

3. **Configuration Cleanup**: Removed bot-related configurations
   - Eliminated TELEGRAM_BOT_TOKEN and TELEGRAM_ADMIN_ID variables
   - Removed bot_config.env template
   - Streamlined environment variable management

4. **Installation Mode Updates**: Updated all modes to reflect Phase 5 changes
   - Full mode now includes advanced backup and maintenance features
   - Reduced complexity while maintaining core functionality
   - Enhanced focus on system reliability and maintenance

### v1.1.0 - Phase 4-5 Optimizations

#### Installation Modes
1. **Three Installation Profiles**: Minimal, Balanced, and Full modes for different use cases
   - **Minimal**: Core VPN only (Phases 1-3), 60% less resource usage
   - **Balanced**: VPN + essential security (Phases 1-4), selective features
   - **Full**: All features (Phases 1-5), complete functionality

2. **Smart Phase Management**: Automatic phase skipping based on installation mode
   - Phase 4 skipped in minimal mode
   - Phase 5 selective execution in balanced mode
   - Interactive configuration in full mode

#### Safety Utilities Module
1. **SSH Hardening Safety**: Comprehensive protection against SSH lockouts
   - SSH key validation before disabling password auth
   - Current connection analysis and warnings
   - Automatic rollback on configuration failure
   - Restore point creation for quick recovery

2. **Enhanced Confirmations**: Interactive safety system with timeout protection
   - User confirmation for critical operations
   - Quick mode bypassing for automation
   - Default action handling with timeout

3. **System State Validation**: Pre-operation safety checks
   - Firewall conflict detection
   - Service status verification
   - Resource availability checks

#### Performance Optimizations
1. **Monitoring Profiles**: 60% reduction in monitoring overhead
   - **Minimal**: 30min health checks, 1hr resource monitoring
   - **Balanced**: 5min health checks, 10min resource monitoring
   - **Intensive**: 1min health checks, 2min resource monitoring

2. **Backup Strategy Optimization**: Profile-based backup with compression
   - **Minimal**: Config + database, 7 days retention, gzip
   - **Essential**: + users + certs, 14 days retention, gzip
   - **Full**: All components + logs, 30 days retention, xz

3. **Resource Management**: Optimized memory and CPU usage
   - Reduced background process overhead
   - Configurable monitoring intervals
   - Optional tool installation

#### Test Suite Enhancement
1. **Comprehensive Test Coverage**: New optimization test suite
   - Installation modes testing
   - Safety utilities validation
   - SSH hardening safety verification
   - Monitoring optimization tests
   - Backup strategy validation

2. **Mock System Architecture**: Sophisticated testing framework
   - Isolated test environments
   - System behavior simulation
   - Safety mechanism validation

### v1.0.1 - Installation Fixes

#### Critical Issues Resolved
1. **Multiple Sourcing Protection**: Include guard pattern for `common_utils.sh`
2. **System User Creation**: Early vless:vless user creation
3. **Python Dependencies**: Robust installation with fallback strategies
4. **UFW Validation**: Flexible regex patterns for different output formats
5. **Quick Mode Support**: Unattended installation capability

### v1.2.1 - Time Synchronization Enhancement

#### System Time Management
1. **Automatic Time Synchronization**: Prevents APT repository errors from incorrect system time
   - Detects time drift before package operations
   - Automatic NTP synchronization with multiple fallback servers
   - Supports systemd-timesyncd, ntpdate, sntp, chronyd
   - Web service fallback (worldtimeapi.org) as last resort

2. **APT Error Recovery**: Intelligent detection and recovery from time-related APT errors
   - Pattern matching for "not valid yet", "invalid for another" errors
   - Automatic retry with time synchronization
   - Configurable retry attempts and timeouts

3. **Configuration Options**:
   - `TIME_SYNC_ENABLED`: Enable/disable automatic time sync (default: true)
   - `TIME_TOLERANCE_SECONDS`: Maximum acceptable drift (default: 300)
   - `TIME_SYNC_SERVERS`: Custom NTP server list

4. **Functions Added to common_utils.sh**:
   - `check_system_time_validity()`: Validates system time against NTP sources (line 296)
   - `sync_system_time()`: Multi-method time synchronization (line 376)
   - `detect_time_related_apt_errors()`: APT error pattern detection (line 484)
   - `safe_apt_update()`: APT update with automatic time sync retry (line 514)

5. **Implementation Status** (2025-09-23):
   - ✅ All time sync functions implemented in common_utils.sh
   - ✅ All direct `apt-get update` calls replaced with `safe_apt_update()`
   - ✅ Comprehensive test suite created for time sync functionality
   - ✅ Integration verified across all modules

---

**Last Updated**: 2025-09-23
**Version**: 1.2.1
**Maintainer**: VLESS Development Team