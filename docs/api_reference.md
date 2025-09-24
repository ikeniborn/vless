# API Reference

Complete API documentation for the VLESS+Reality VPN Management System modules and functions.

## Table of Contents

1. [Module Overview](#module-overview)
2. [Common Utilities](#common-utilities)
3. [Safety Utilities](#safety-utilities)
4. [User Management](#user-management)
5. [Monitoring System](#monitoring-system)
6. [Backup and Restore](#backup-and-restore)
7. [Security Hardening](#security-hardening)
8. [Configuration Management](#configuration-management)
9. [Database Operations](#database-operations)
10. [Container Management](#container-management)

## Module Overview

The system is built with a modular architecture where each module provides specific functionality:

```
modules/
├── common_utils.sh          # Core utilities and logging
├── safety_utils.sh          # Safety checks and confirmations
├── user_management.sh       # High-level user operations
├── user_database.sh         # User database operations
├── monitoring.sh            # System monitoring and alerts
├── backup_restore.sh        # Backup and recovery system
├── security_hardening.sh    # Security configurations
├── docker_setup.sh          # Container management
├── config_templates.sh      # Configuration generation
├── cert_management.sh       # Certificate handling
├── container_management.sh  # Docker operations
├── logging_setup.sh         # Log management
├── maintenance_utils.sh     # System maintenance
├── system_update.sh         # Update management
└── ufw_config.sh           # Firewall configuration
```

## Common Utilities

**File**: `modules/common_utils.sh`

Core logging, error handling, and utility functions used across all modules.

**Recent Improvements (v1.2.7):**
- Enhanced module loading system with conditional SCRIPT_DIR initialization
- Fixed readonly variable conflicts across all modules
- Improved module sourcing reliability and cross-module compatibility
- Added comprehensive test suite for module loading validation

**Previous Improvements (v1.0.1):**
- Added include guard to prevent multiple sourcing
- Enhanced signal handling for process isolation
- Added system user creation functionality
- Improved error handling and logging

### Module Loading System (v1.2.7)

All modules now implement safe variable initialization patterns to prevent readonly conflicts:

```bash
# Safe SCRIPT_DIR initialization pattern
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
```

**Key Features:**
- Conditional variable assignment prevents readonly conflicts
- Enhanced cross-module compatibility
- Improved parent script sourcing support
- Comprehensive test coverage with 44 test cases

### Logging Functions

#### `log_info(message)`
Logs informational messages with timestamp and blue color formatting.

**Parameters:**
- `message` (string): Message to log

**Example:**
```bash
log_info "Starting user creation process"
```

#### `log_error(message)`
Logs error messages with timestamp and red color formatting.

**Parameters:**
- `message` (string): Error message to log

**Example:**
```bash
log_error "Failed to create user directory"
```

#### `log_warn(message)`
Logs warning messages with timestamp and yellow color formatting.

**Parameters:**
- `message` (string): Warning message to log

#### `log_success(message)`
Logs success messages with timestamp and green color formatting.

**Parameters:**
- `message` (string): Success message to log

#### `log_debug(message)`
Logs debug messages when debug mode is enabled.

**Parameters:**
- `message` (string): Debug message to log

### Validation Functions

#### `validate_not_empty(value, field_name)`
Validates that a value is not empty.

**Parameters:**
- `value` (string): Value to validate
- `field_name` (string): Name of the field for error reporting

**Returns:**
- `0`: Validation successful
- `1`: Validation failed

#### `validate_uuid(uuid)`
Validates UUID format using regex pattern.

**Parameters:**
- `uuid` (string): UUID to validate

**Returns:**
- `0`: Valid UUID format
- `1`: Invalid UUID format

#### `validate_email(email)`
Validates email address format.

**Parameters:**
- `email` (string): Email address to validate

**Returns:**
- `0`: Valid email format
- `1`: Invalid email format

#### `validate_ip(ip_address)`
Validates IPv4 address format.

**Parameters:**
- `ip_address` (string): IP address to validate

**Returns:**
- `0`: Valid IP format
- `1`: Invalid IP format

### System Functions

#### `generate_uuid()`
Generates a random UUID v4.

**Returns:**
- UUID string in format: `xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`

#### `get_system_info()`
Retrieves system information including OS, kernel, and hardware details.

**Returns:**
- JSON formatted system information

#### `check_root_privileges()`
Verifies if script is running with root privileges.

**Returns:**
- `0`: Running as root
- `1`: Not running as root

#### `setup_signal_handlers()`
Sets up signal handlers for graceful script termination.

**Signals Handled:**
- `SIGTERM`: Graceful termination
- `SIGINT`: Interrupt (Ctrl+C)
- `SIGUSR1`: Custom signal for reload

#### `create_vless_system_user()`
Creates VLESS system user and group for security isolation.

**Purpose:**
- Creates `vless` group with restricted permissions
- Creates `vless` user with no shell access
- Sets up proper home directory (`/opt/vless`)
- Ensures secure service isolation

**Returns:**
- `0`: User and group created successfully
- `1`: Creation failed

**Security Features:**
- Uses `-r` flag for system user/group
- Sets shell to `/bin/false` for security
- Assigns restricted permissions
- Logs all operations for audit trail

**Example:**
```bash
if create_vless_system_user; then
    log_success "VLESS user created successfully"
else
    log_error "Failed to create VLESS user"
fi
```

## Safety Utilities

**Module:** `safety_utils.sh`

Provides comprehensive safety checks, confirmations, and rollback mechanisms for critical operations.

### Core Functions

#### confirm_action()
Interactive confirmation with timeout protection.

**Syntax:** `confirm_action <message> [default] [timeout]`

**Parameters:**
- `message` - Confirmation prompt text
- `default` - Default action (y/n, defaults to 'y')
- `timeout` - Timeout in seconds (defaults to 30)

**Returns:** 0 if confirmed, 1 if declined or timeout

**Example:**
```bash
if confirm_action "Apply SSH hardening?" "n" 30; then
    apply_ssh_hardening
else
    log_info "SSH hardening cancelled"
fi
```

#### validate_system_state()
Validates system state before critical operations.

**Syntax:** `validate_system_state <operation>`

**Parameters:**
- `operation` - Operation type (ssh_hardening, firewall_config, service_restart)

**Returns:** 0 if validation passes, 1 if issues found

**Example:**
```bash
if validate_system_state "ssh_hardening"; then
    proceed_with_hardening
else
    log_error "System validation failed"
fi
```

#### create_restore_point()
Creates a system restore point before major changes.

**Syntax:** `create_restore_point <description>`

**Parameters:**
- `description` - Description of the restore point

**Returns:** 0 on success, 1 on failure

**Example:**
```bash
create_restore_point "before_ssh_hardening"
# Returns path to restore script for quick recovery
```

#### check_ssh_keys()
Validates SSH key configuration for current user.

**Syntax:** `check_ssh_keys`

**Returns:** 0 if SSH keys found, 1 if not configured

#### safe_service_restart()
Safely restarts services with user confirmation.

**Syntax:** `safe_service_restart <service> [timeout] [force]`

**Parameters:**
- `service` - Service name to restart
- `timeout` - Operation timeout (defaults to 30)
- `force` - Skip confirmation if true

**Example:**
```bash
safe_service_restart "sshd" 30 false
```

### Installation Profile Functions

#### configure_installation_profile()
Configures environment based on installation mode.

**Syntax:** `configure_installation_profile`

**Uses:** `INSTALLATION_MODE` environment variable

**Modes:**
- `minimal` - Core VPN only, minimal resources
- `balanced` - VPN + security, optimized resources
- `full` - All features, comprehensive monitoring

### SSH Hardening Safety

#### apply_selective_ssh_hardening()
Applies SSH hardening with safety checks and rollback.

**Syntax:** `apply_selective_ssh_hardening <setting1> [setting2] ...`

**Parameters:**
- `settings` - Array of SSH configuration settings

**Safety Features:**
- Automatic configuration backup
- SSH configuration validation
- Service restart with rollback on failure

#### show_current_ssh_connections()
Displays current SSH connections for safety analysis.

**Syntax:** `show_current_ssh_connections`

### Firewall Safety

#### check_existing_firewall()
Detects existing firewall services to prevent conflicts.

**Syntax:** `check_existing_firewall [--verbose]`

**Returns:** 0 if firewall found, 1 if none detected

#### backup_current_firewall_rules()
Backs up current firewall configuration before changes.

**Syntax:** `backup_current_firewall_rules`

### Test Functions

#### test_ssh_connectivity()
Tests SSH port accessibility.

**Syntax:** `test_ssh_connectivity [port]`

**Parameters:**
- `port` - SSH port to test (defaults to 22)

**Returns:** 0 if accessible, 1 if not

**Notes:**
- All safety functions respect `QUICK_MODE` environment variable
- Restore points include automatic recovery scripts
- System validation prevents common configuration errors
- Interactive confirmations have reasonable timeouts

## User Management

**File**: `modules/user_management.sh`

High-level user management interface providing user lifecycle operations.

### User Operations

#### `add_user(email, name, flow, auto_uuid, custom_uuid)`
Creates a new user with automatic configuration generation.

**Parameters:**
- `email` (string): User email/identifier (required)
- `name` (string): Display name (optional)
- `flow` (string): VLESS flow type (optional, default: "xtls-rprx-vision")
- `auto_uuid` (boolean): Auto-generate UUID (optional, default: true)
- `custom_uuid` (string): Custom UUID if auto_uuid is false

**Returns:**
- `0`: User created successfully
- `1`: Creation failed

**Example:**
```bash
add_user "john@example.com" "John Doe" "xtls-rprx-vision" true
```

#### `remove_user(email)`
Removes a user and cleans up associated configurations.

**Parameters:**
- `email` (string): User email/identifier

**Returns:**
- `0`: User removed successfully
- `1`: Removal failed

#### `list_users(format, filter)`
Lists users with optional filtering and formatting.

**Parameters:**
- `format` (string): Output format (json, table, csv)
- `filter` (string): Filter criteria (active, expired, disabled)

**Returns:**
- Formatted user list

#### `get_user_info(email)`
Retrieves detailed information for a specific user.

**Parameters:**
- `email` (string): User email/identifier

**Returns:**
- JSON formatted user information

#### `update_user_quota(email, quota_gb)`
Updates user data quota limit.

**Parameters:**
- `email` (string): User email/identifier
- `quota_gb` (number): Quota limit in GB

**Returns:**
- `0`: Quota updated successfully
- `1`: Update failed

#### `generate_user_config(email, client_type)`
Generates client configuration for specified user.

**Parameters:**
- `email` (string): User email/identifier
- `client_type` (string): Client type (v2rayN, v2rayNG, iOS, qv2ray)

**Returns:**
- Base64 encoded configuration string

### User Status Management

#### `enable_user(email)`
Enables a disabled user account.

#### `disable_user(email)`
Disables a user account temporarily.

#### `reset_user_traffic(email)`
Resets user traffic usage statistics.

#### `extend_user_expiry(email, days)`
Extends user account expiration date.

## Monitoring System

**File**: `modules/monitoring.sh`

Real-time system monitoring, health checks, and alerting system.

### Health Check Functions

#### `check_xray_service()`
Monitors Xray service status and performance.

**Returns:**
- JSON object with service status, memory usage, CPU usage, and connection count

#### `check_docker_containers()`
Monitors Docker container status and resource usage.

**Returns:**
- Array of container status objects

#### `check_system_resources()`
Monitors system CPU, memory, and disk usage.

**Returns:**
- JSON object with resource utilization metrics

#### `check_network_connectivity()`
Tests network connectivity to external services.

**Returns:**
- JSON object with connectivity test results

### Monitoring Commands

#### `start_monitoring(interval)`
Starts continuous monitoring with specified interval.

**Parameters:**
- `interval` (number): Monitoring interval in seconds (default: 60)

#### `stop_monitoring()`
Stops the monitoring service.

#### `get_metrics(timeframe)`
Retrieves historical metrics for specified timeframe.

**Parameters:**
- `timeframe` (string): Time range (1h, 24h, 7d, 30d)

**Returns:**
- JSON formatted metrics data

### Alert System

#### `configure_alerts(email, webhook_url, thresholds)`
Configures alert notifications and thresholds.

**Parameters:**
- `email` (string): Alert email address
- `webhook_url` (string): Webhook URL for notifications
- `thresholds` (object): Alert threshold values

#### `send_alert(type, message, severity)`
Sends alert notification via configured channels.

**Parameters:**
- `type` (string): Alert type (system, security, user)
- `message` (string): Alert message
- `severity` (string): Severity level (low, medium, high, critical)

## Backup and Restore

**File**: `modules/backup_restore.sh`

Comprehensive backup and disaster recovery system.

### Backup Operations

#### `create_backup(type, compression, encryption)`
Creates system backup with specified options.

**Parameters:**
- `type` (string): Backup type (full, config, users, logs)
- `compression` (string): Compression method (gzip, xz, none)
- `encryption` (boolean): Enable backup encryption

**Returns:**
- Backup file path and checksum

**Example:**
```bash
create_backup "full" "gzip" true
```

#### `schedule_backup(frequency, time, retention)`
Schedules automated backups.

**Parameters:**
- `frequency` (string): Backup frequency (daily, weekly, monthly)
- `time` (string): Backup time (HH:MM format)
- `retention` (number): Number of backups to retain

#### `verify_backup(backup_file)`
Verifies backup integrity and completeness.

**Parameters:**
- `backup_file` (string): Path to backup file

**Returns:**
- `0`: Backup is valid
- `1`: Backup is corrupted

### Restore Operations

#### `restore_backup(backup_file, restore_type)`
Restores system from backup file.

**Parameters:**
- `backup_file` (string): Path to backup file
- `restore_type` (string): Restore scope (full, config, users)

**Returns:**
- `0`: Restore successful
- `1`: Restore failed

#### `list_backups(location)`
Lists available backup files.

**Parameters:**
- `location` (string): Backup location (local, remote)

**Returns:**
- Array of backup file information

### Remote Storage

#### `configure_remote_storage(type, credentials)`
Configures remote backup storage.

**Parameters:**
- `type` (string): Storage type (s3, ftp, sftp)
- `credentials` (object): Storage credentials and configuration

#### `upload_backup(backup_file, remote_path)`
Uploads backup to remote storage.

#### `download_backup(remote_path, local_path)`
Downloads backup from remote storage.

## Security Hardening

**File**: `modules/security_hardening.sh`

System security configuration and hardening procedures.

### Security Configuration

#### `apply_security_policies()`
Applies comprehensive security hardening policies.

**Includes:**
- SSH hardening
- Firewall configuration
- Service hardening
- Kernel parameter tuning
- File permission fixes

#### `configure_firewall(rules, default_policy)`
Configures firewall rules and policies.

**Parameters:**
- `rules` (array): Firewall rule definitions
- `default_policy` (string): Default policy (accept, drop, reject)

#### `setup_intrusion_detection()`
Sets up intrusion detection and prevention system.

#### `configure_fail2ban(services, ban_time)`
Configures fail2ban for service protection.

**Parameters:**
- `services` (array): Services to protect
- `ban_time` (number): Ban duration in seconds

### Security Auditing

#### `run_security_audit()`
Performs comprehensive security audit.

**Returns:**
- Security audit report with recommendations

#### `check_vulnerabilities()`
Scans for known vulnerabilities.

#### `verify_security_compliance()`
Verifies compliance with security standards.


## Configuration Management

**File**: `modules/config_templates.sh`

Configuration file generation and template management.

### Template Functions

#### `generate_xray_config(users, port, domain)`
Generates Xray server configuration.

**Parameters:**
- `users` (array): User configuration objects
- `port` (number): Server port
- `domain` (string): Reality domain

**Returns:**
- JSON formatted Xray configuration

#### `generate_client_config(user, server_info, client_type)`
Generates client-specific configuration.

**Parameters:**
- `user` (object): User information
- `server_info` (object): Server connection details
- `client_type` (string): Target client application

**Returns:**
- Client configuration in appropriate format

#### `update_reality_settings(domain, port, public_key)`
Updates Reality obfuscation settings.

### Configuration Validation

#### `validate_xray_config(config_file)`
Validates Xray configuration syntax.

#### `validate_client_config(config_string)`
Validates client configuration format.

## Database Operations

**File**: `modules/user_database.sh`

User database management and operations.

### Database Functions

#### `init_user_database(db_path)`
Initializes user database with required tables.

#### `add_user_to_db(user_data)`
Adds user record to database.

#### `update_user_in_db(email, updates)`
Updates user record in database.

#### `remove_user_from_db(email)`
Removes user record from database.

#### `get_user_from_db(email)`
Retrieves user record from database.

#### `list_users_from_db(filter_criteria)`
Lists users with optional filtering.

### Traffic Management

#### `record_traffic_usage(email, bytes_in, bytes_out)`
Records user traffic usage.

#### `get_traffic_stats(email, timeframe)`
Retrieves traffic statistics for user.

#### `reset_traffic_counters(email)`
Resets traffic usage counters.

## Installation Functions

**File**: `install.sh`

Specialized installation functions with enhanced error handling and recovery mechanisms.

### Python Dependency Management

#### `install_python_dependencies()`
Installs Python dependencies with multiple fallback methods and robust error handling.

**Features:**
- **Multiple Installation Methods**: Standard, externally managed, user installation
- **Timeout Handling**: 5-minute timeout with automatic retry
- **Error Recovery**: Automatic fallback to alternative methods
- **Network Resilience**: Handles network failures gracefully
- **Environment Detection**: Detects externally managed Python environments

**Installation Sequence:**
1. **Standard Installation**: `pip install -r requirements.txt`
2. **Externally Managed**: `pip install --break-system-packages`
3. **User Installation**: `pip install --user`
4. **Individual Packages**: Falls back to package-by-package installation

**Parameters:**
- None (uses `requirements.txt` from script directory)

**Returns:**
- `0`: Dependencies installed successfully
- `1`: Installation failed after all methods

**Error Handling:**
- Validates `requirements.txt` exists
- Ensures `pip3` is available
- Upgrades pip before installation
- Provides detailed error reporting
- Logs all attempts for troubleshooting

**Example:**
```bash
if install_python_dependencies; then
    log_success "Python dependencies ready"
else
    log_error "Failed to install Python dependencies"
    exit 1
fi
```

**Supported Environments:**
- Ubuntu 20.04+ with standard Python
- Ubuntu 23.04+ with externally managed Python
- Debian with various Python configurations
- CentOS/RHEL with pip3
- Rocky Linux and derivatives

### Quick Mode Support

#### `QUICK_MODE` Environment Variable
Controls unattended installation behavior throughout the system.

**Usage:**
```bash
# Enable quick mode
export QUICK_MODE=true
sudo ./install.sh

# Or use command line flag
sudo ./install.sh --quick
```

**Behavior:**
- **Prompt Skipping**: All interactive prompts are bypassed
- **Default Values**: Uses sensible defaults for all configurations
- **Error Handling**: Enhanced error reporting without user interaction
- **Logging**: Comprehensive logging for troubleshooting
- **Validation**: All validation checks still performed

**Implementation Pattern:**
```bash
# Skip prompt in quick install mode
if [[ "${QUICK_MODE:-false}" != "true" ]]; then
    read -p "Press Enter to continue..."
fi
```

## Container Management

**File**: `modules/container_management.sh`

Docker container lifecycle management.

### Container Operations

#### `deploy_containers()`
Deploys all required containers.

#### `start_containers(service_name)`
Starts specified containers.

#### `stop_containers(service_name)`
Stops specified containers.

#### `restart_containers(service_name)`
Restarts specified containers.

#### `remove_containers(service_name)`
Removes specified containers.

### Container Monitoring

#### `get_container_status(container_name)`
Retrieves container status and metrics.

#### `get_container_logs(container_name, lines)`
Retrieves container logs.

#### `monitor_container_health()`
Monitors container health status.

---

## Error Codes

The system uses standardized error codes for consistent error handling:

**General Codes:**
- `0`: Success
- `1`: General error
- `2`: Invalid arguments
- `3`: Permission denied
- `4`: File not found
- `5`: Service unavailable

**User Management:**
- `10`: User not found
- `11`: User already exists
- `12`: Invalid user data
- `13`: User creation failed
- `14`: User deletion failed

**Network and Connectivity:**
- `20`: Network error
- `21`: Connection timeout
- `22`: DNS resolution failed
- `23`: Port unavailable

**Configuration:**
- `30`: Configuration error
- `31`: Invalid configuration
- `32`: Configuration validation failed
- `33`: Template generation failed

**Database Operations:**
- `40`: Database error
- `41`: Database corruption
- `42`: Database connection failed
- `43`: Database query failed

**Security:**
- `50`: Security violation
- `51`: Authentication failed
- `52`: Authorization denied
- `53`: Certificate error

**Installation Specific:**
- `60`: Dependency installation failed
- `61`: Python package installation failed
- `62`: System user creation failed
- `63`: Firewall configuration failed
- `64`: Service initialization failed

## Data Formats

### User Object Format
```json
{
  "email": "user@example.com",
  "uuid": "550e8400-e29b-41d4-a716-446655440000",
  "name": "User Name",
  "flow": "xtls-rprx-vision",
  "quota_gb": 100,
  "used_gb": 15.5,
  "created_at": "2024-01-01T00:00:00Z",
  "expires_at": "2024-12-31T23:59:59Z",
  "status": "active",
  "last_activity": "2024-01-15T12:00:00Z"
}
```

### System Status Format
```json
{
  "status": "healthy",
  "uptime": 86400,
  "services": {
    "xray": "running",
    "docker": "running"
  },
  "resources": {
    "cpu_usage": 25.5,
    "memory_usage": 60.2,
    "disk_usage": 45.8
  },
  "network": {
    "connections_active": 150,
    "traffic_in_mbps": 25.6,
    "traffic_out_mbps": 30.2
  }
}
```

## Recent API Changes (v1.0.1)

### New Functions

1. **`create_vless_system_user()`** in `common_utils.sh`
   - Dedicated system user creation
   - Enhanced security isolation
   - Comprehensive error handling

2. **`install_python_dependencies()`** in `install.sh`
   - Robust Python package installation
   - Multiple fallback methods
   - Environment detection and adaptation

### Enhanced Functions

1. **Include Guard in `common_utils.sh`**
   - Prevents multiple sourcing errors
   - Improves performance and reliability
   - Uses `COMMON_UTILS_LOADED` variable

2. **UFW Validation Improvements**
   - Better output format handling
   - Enhanced error detection
   - Debug logging for troubleshooting

3. **Quick Mode Support**
   - `QUICK_MODE` environment variable
   - Automated installation capability
   - Maintains full functionality

### Deprecated Patterns

- **Multiple Sourcing**: No longer needed due to include guard
- **Manual Python Installation**: Replaced by robust `install_python_dependencies()`
- **Interactive-only Installation**: Quick mode now available

### Migration Notes

When updating existing scripts:

1. **Remove manual user creation** - use `create_vless_system_user()` instead
2. **Replace Python installation logic** - use `install_python_dependencies()` function
3. **Add Quick Mode support** - check `QUICK_MODE` variable for prompts
4. **Update error handling** - use new error codes for better diagnostics

---

**Note**: This API reference covers the core functionality including recent v1.0.1 improvements. Some advanced features may have additional parameters or return values. Always refer to the inline documentation in the source files for the most up-to-date information.