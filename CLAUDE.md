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

### v1.2.7 - Module Loading System Fixes (2025-09-24)

#### Critical Module System Stabilization
1. **Readonly Variable Conflict Resolution**: Fixed shell script crashes from readonly variable redefinition
   - Added conditional `SCRIPT_DIR` checks across all modules to prevent readonly conflicts
   - Implemented safe variable assignment patterns: `if [[ -z "${SCRIPT_DIR:-}" ]]; then`
   - Fixed module loading failures that prevented successful installations
   - Enhanced module sourcing reliability across different execution contexts

2. **Module Sourcing Path Issues Resolution**: Enhanced path handling for robust module loading
   - Standardized SCRIPT_DIR detection pattern across all modules
   - Fixed relative path issues when modules are sourced from different directories
   - Improved parent script compatibility for nested module loading
   - Enhanced cross-module dependency resolution

3. **Service Startup Reliability**: Resolved Phase 2 installation failures
   - Fixed Docker service startup issues caused by module loading conflicts
   - Improved container management module stability
   - Enhanced error handling for service initialization
   - Streamlined Phase 2 execution flow for consistent results

4. **Enhanced Module System Architecture**:
   - **config_templates.sh**: Added conditional SCRIPT_DIR initialization
   - **container_management.sh**: Fixed path resolution for Docker operations
   - **docker_setup.sh**: Enhanced startup sequence reliability
   - **user_management.sh**: Resolved database file path conflicts
   - **user_database.sh**: Improved DEFAULT_DB_FILE handling
   - **system_update.sh**: Standardized module loading patterns

5. **Comprehensive Test Suite**: New module loading validation framework
   - 44 test cases across 4 test suites validating module loading fixes
   - Readonly variable conflict detection and prevention tests
   - SCRIPT_DIR handling validation across different execution contexts
   - Container management functionality verification
   - Cross-module dependency resolution testing

6. **Backward Compatibility**: Full compatibility with existing installations
   - No breaking changes to module interfaces or function signatures
   - Existing installations benefit automatically from improved reliability
   - Configuration files remain unchanged
   - All existing workflows continue to function normally

#### Key Technical Improvements
```bash
# Before v1.2.7 (caused readonly conflicts)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# After v1.2.7 (safe conditional assignment)
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
```

#### Testing and Validation
- ✅ Module loading fixes tested across 44 individual test cases
- ✅ Readonly variable conflicts eliminated
- ✅ SCRIPT_DIR handling working properly in all contexts
- ✅ Container management module functionality verified
- ✅ Phase 2 installation reliability significantly improved
- ✅ Cross-module sourcing working without conflicts

### v1.2.6 - Docker Services Automatic Startup Fix (2025-09-24)

#### Critical Docker Container Management Enhancement
1. **Automatic Service Startup**: Docker services now start immediately after installation
   - Eliminates manual intervention required for VLESS server activation
   - Integrated startup verification with health checks
   - Graceful handling of startup timeouts and failures
   - Enhanced user experience with immediate service availability

2. **Container Permission Management**: Enhanced UID/GID detection and mapping
   - `detect_container_user_mapping()`: Automatic host user detection (docker_setup.sh)
   - Dynamic UID/GID assignment for container compatibility
   - Proper file ownership management in shared volumes
   - Cross-platform compatibility for various host configurations

3. **Robust Error Recovery**: 3-attempt retry logic with exponential backoff
   - Automatic retry on container startup failures
   - Service validation before marking operations complete
   - Comprehensive error logging with actionable guidance
   - Fallback mechanisms for resource conflicts

4. **Health Check Integration**: Comprehensive service validation after startup
   - Container status verification (running, healthy states)
   - Port accessibility testing for VLESS service
   - Log output analysis for error detection
   - Performance metrics collection during startup

5. **Backward Compatibility**: Full compatibility with existing installations
   - No breaking changes to configuration files
   - Existing containers upgrade seamlessly
   - Manual startup commands still supported
   - Configuration migration handled automatically

6. **Enhanced Functions in docker_setup.sh**:
   - `start_containers_with_retry()`: Retry logic for service startup
   - `detect_container_user_mapping()`: Smart UID/GID detection
   - `verify_service_startup()`: Health check integration
   - `handle_startup_failure()`: Error recovery mechanisms

#### Testing and Validation
- ✅ Automatic container startup working correctly
- ✅ Permission mapping handles various host configurations
- ✅ Retry logic prevents transient startup failures
- ✅ Health checks validate service availability
- ✅ Error recovery provides clear resolution paths
- ✅ Full backward compatibility maintained

### v1.2.5 - Enhanced Chrony Synchronization with Multi-Server Support (2025-09-24)

#### Revolutionary Time Synchronization Fix
1. **Multi-Server NTP Configuration**: Eliminated single point of failure with 8 reliable NTP servers
   - pool.ntp.org, time.nist.gov, time.google.com, time.cloudflare.com
   - Regional pools (0-3.pool.ntp.org) for geographic redundancy
   - Automatic failover between servers for maximum reliability

2. **Chrony Synchronization Verification**: New `verify_chrony_sync_status()` function
   - Validates Stratum 1-9 (not 0) indicating valid synchronization
   - Checks for active servers marked with '*' or '+' in sources
   - Retry logic with configurable delays for sync confirmation
   - Proper tracking output parsing for sync status

3. **Retry Logic with Exponential Backoff**: New `sync_with_retry()` function
   - 3 attempts with exponential delays (5s, 10s, 15s)
   - Force mode activation for subsequent attempts
   - Comprehensive error recovery and logging

4. **Extended Wait Times and Verification**:
   - 20-second wait for chrony burst mode completion (was 8s)
   - 3-second service startup wait for stability
   - Verification before makestep ensures actual synchronization
   - Multiple fallback paths for reliability

5. **Helper Functions Added**:
   - `safe_execute_output()`: Command execution with output capture (line 586-611)
   - `verify_chrony_sync_status()`: Chrony sync verification (line 245-293)
   - `sync_with_retry()`: Retry logic implementation (line 296-326)
   - `force_hwclock_sync()`: Hardware clock synchronization (line 202-241)

6. **Testing and Validation**:
   - ✅ All functions properly defined and exported
   - ✅ Multiple NTP servers configured correctly
   - ✅ Synchronization verification working
   - ✅ Retry logic with exponential backoff functional
   - ✅ APT error detection patterns validated

### v1.2.4 - Fixed Package Installation Validation (2025-09-24)

#### Critical Installation Fix
1. **Package Detection Enhancement**: Fixed critical issue preventing Docker installation
   - New `is_package_installed()` function with multi-layered validation (lines 269-310)
   - Proper detection of data packages (ca-certificates, gnupg, lsb-release)
   - Maintains backward compatibility for command-based packages

2. **Improved install_package_if_missing Function**:
   - Uses package-appropriate validation methods
   - Graceful degradation on verification failures
   - Better error handling and logging
   - Resolves Phase 1 installation failures

3. **Testing Coverage**:
   - ✅ Data package detection (ca-certificates, gnupg, lsb-release)
   - ✅ Command-based package detection (curl, etc.)
   - ✅ Docker prerequisite validation
   - ✅ Full backward compatibility

#### Core Functions Added in common_utils.sh
- `is_package_installed()`: Intelligent package detection with fallbacks (line 269-310)

### v1.2.3 - Enhanced Time Synchronization with Service Management (2025-09-24)

#### Advanced Time Synchronization Engine
1. **Enhanced Time Sync Function**: New `enhanced_time_sync()` function with comprehensive service management
   - Intelligent service detection and management (systemd-timesyncd, chrony, ntp)
   - Automatic service restart and configuration validation
   - Multi-layered fallback system with web API integration
   - Enhanced error handling and recovery mechanisms

2. **Service Management Improvements**:
   - `restart_time_service()`: Safe time service restart with validation (line 203-241)
   - `validate_chrony_config()`: Chrony configuration validation and repair (line 244-276)
   - Service-specific configuration management for large time offsets
   - Automatic service selection based on system availability

3. **Enhanced Web API Integration**:
   - Robust JSON parsing with multiple time API formats
   - Improved error handling for network timeouts and failures
   - Enhanced validation of API responses before time setting
   - Fallback chain: worldtimeapi.org → worldclockapi.com → timeapi.io

4. **Comprehensive Testing Suite**:
   - ✅ 28 comprehensive test cases with 100% pass rate
   - ✅ Service management and restart validation
   - ✅ Chrony configuration modification and validation
   - ✅ Enhanced web API parsing and error handling
   - ✅ Multi-service time synchronization testing

5. **Production-Grade Reliability**:
   - Timeout protection for all external service calls
   - Graceful degradation when services are unavailable
   - Enhanced logging with detailed operation traces
   - Validation ensures meaningful time corrections (>30 seconds)

#### Core Functions Enhanced in common_utils.sh
- `enhanced_time_sync()`: Main time synchronization engine (line 453-540)
- `restart_time_service()`: Service management with validation
- `validate_chrony_config()`: Configuration validation and repair
- `sync_time_from_web_api()`: Enhanced web API fallback
- `validate_time_sync_result()`: Time change validation

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

### v1.2.2 - Enhanced Time Synchronization with Large Offset Support

#### Critical Time Sync Fix (2025-09-23)
1. **Enhanced Large Offset Correction**: Fixed APT "not valid yet" errors for offsets >45 minutes
   - Aggressive chrony configuration with `makestep 1000 -1`
   - Web API fallback for manual time setting when NTP fails
   - Validation ensures time actually changed (>30 seconds)
   - Multiple fallback layers for reliability

2. **New Helper Functions Added**:
   - `configure_chrony_for_large_offset()`: Configures chrony for aggressive corrections (line 242-276)
   - `sync_time_from_web_api()`: Web API fallback using multiple time services (line 279-339)
   - `validate_time_sync_result()`: Validates time changes are significant (line 342-367)

3. **Enhanced sync_system_time() Function**:
   - Before/after time capture for all sync methods
   - Validation after each sync attempt
   - Enhanced debug logging showing time differences
   - Chrony burst mode for faster synchronization
   - Web API fallback as ultimate time source

4. **Web Time API Support**:
   - worldtimeapi.org (primary)
   - worldclockapi.com (secondary)
   - timeapi.io (tertiary)
   - Manual date setting with `date -s` as last resort
   - Hardware clock update with `hwclock --systohc`

5. **Testing and Validation**:
   - ✅ 23 comprehensive test cases with 100% pass rate
   - ✅ Validation logic correctly handles 30-second threshold
   - ✅ Chrony configuration modification tested
   - ✅ Web API parsing for all three formats verified
   - ✅ Error pattern detection confirmed

### v1.2.1 - Time Synchronization Foundation

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

4. **Core Functions in common_utils.sh**:
   - `check_system_time_validity()`: Validates system time against NTP sources (line 296)
   - `sync_system_time()`: Multi-method time synchronization (line 376-239)
   - `detect_time_related_apt_errors()`: APT error pattern detection (line 370-389)
   - `safe_apt_update()`: APT update with automatic time sync retry (line 391-447)

---

**Last Updated**: 2025-09-24
**Version**: 1.2.7
**Maintainer**: VLESS Development Team