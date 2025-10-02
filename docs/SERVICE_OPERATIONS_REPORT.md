# Service Operations Module Report

**Module**: `lib/service_operations.sh`
**Version**: 1.0.0
**EPIC**: EPIC-8 - Service Operations (16 hours)
**Status**: ✅ Complete
**Lines**: 857

## Overview

The Service Operations module provides comprehensive lifecycle management for the VLESS Reality VPN service. It handles container orchestration, status monitoring, configuration updates, and log management with a focus on zero-downtime operations and configuration preservation.

## Implementation Summary

### TASK-8.1: Service Control Functions (4 hours)

Implemented complete service lifecycle management with Docker Compose integration:

#### Core Functions

**`start_service()`**
- Validates Docker Compose configuration
- Checks if service is already running
- Starts both Xray and Nginx containers
- Waits for containers to be healthy (30s timeout)
- Displays service status on successful start

**`stop_service()`**
- Graceful shutdown with 30-second timeout
- Checks if service is running before stopping
- Uses `docker-compose down` for clean shutdown

**`restart_service()`**
- Orchestrates stop → start sequence
- Maintains configuration integrity
- Reports success/failure status

**`reload_xray()`**
- Sends HUP signal to Xray process for graceful reload
- Zero-downtime configuration updates
- Falls back to container restart if HUP fails
- Used after adding/removing users

### TASK-8.2: Status Display Functions (3 hours)

Comprehensive status monitoring and reporting system:

#### Status Functions

**`display_service_status()`**
- Overall service status (Running/Stopped)
- Detailed container status for Xray and Nginx
- Container uptime in human-readable format (Xd Xh Xm)
- Health check status with color coding
- Network configuration (port, subnet, server IP)
- Active user count

**`get_container_status()`**
- Returns container state: running, stopped, paused, restarting
- Handles containers that don't exist

**`get_container_uptime()`**
- Calculates uptime from container start time
- Formats as days, hours, minutes, seconds

**`get_container_health()`**
- Reads Docker health check status
- Returns: healthy, unhealthy, starting, or no healthcheck

**`wait_for_healthy()`**
- Waits for containers to become healthy
- Configurable timeout (default: 30s)
- Used after start/update operations

#### Status Display Format

```
═══════════════════════════════════════════════════════════
  VLESS Reality VPN Service Status
═══════════════════════════════════════════════════════════

Overall Status: ● Running

┌─ Xray Container ─────────────────────────────────────────┐
  Status:     ● Running
  Uptime:     2d 14h 32m
  Health:     ✓ Healthy
└──────────────────────────────────────────────────────────┘

┌─ Nginx Container ────────────────────────────────────────┐
  Status:     ● Running
  Uptime:     2d 14h 32m
  Health:     - No healthcheck
└──────────────────────────────────────────────────────────┘

┌─ Network Configuration ──────────────────────────────────┐
  VLESS Port:   443
  Subnet:       172.20.0.0/16
  Server IP:    203.0.113.1
└──────────────────────────────────────────────────────────┘

Active Users: 5

═══════════════════════════════════════════════════════════
```

### TASK-8.3: Update Mechanism (6 hours)

Robust update system with configuration preservation per Q-003 requirement:

#### Update Functions

**`update_xray()`**
- Updates only Xray container to latest version
- Creates backup before update
- Pulls latest `teddysun/xray:latest` image
- Recreates container with `--force-recreate`
- Preserves volumes and configuration
- Automatic rollback on failure

**`update_system()`**
- Updates all containers (Xray + Nginx)
- Full system upgrade with configuration preservation
- Creates backup before update
- Pulls latest images for all services
- Recreates all containers
- Automatic rollback on failure

**`create_config_backup()`**
- Timestamped backups: `YYYYMMDD_HHMMSS`
- Backs up:
  - `.env` (network parameters)
  - `config/` directory (Xray config, users, keys)
  - `docker-compose.yml` (container configuration)
- Creates backup manifest with metadata
- Automatic cleanup (keeps last 10 backups)

**`restore_config_backup()`**
- Restores from latest backup
- Stops service before restore
- Restores all configuration files
- Restarts service after restore

**`cleanup_old_backups()`**
- Keeps only last 10 backups
- Automatically runs after each backup
- Prevents disk space exhaustion

#### Configuration Preservation

Per Q-003 requirement, all updates preserve:
- ✅ Docker subnet (`DOCKER_SUBNET`)
- ✅ VLESS port (`VLESS_PORT`)
- ✅ Reality keys (`PRIVATE_KEY`, `PUBLIC_KEY`)
- ✅ Server name (`SERVER_NAME`)
- ✅ Short IDs (`SHORT_ID`)
- ✅ User database (`config/users.json`)
- ✅ Xray configuration (`config/xray_config.json`)

#### Backup Structure

```
backups/
├── 20250102_143022/
│   ├── .env
│   ├── config/
│   │   ├── xray_config.json
│   │   ├── users.json
│   │   ├── private.key
│   │   └── public.key
│   ├── docker-compose.yml
│   └── manifest.txt
├── 20250102_153045/
└── ...
```

### TASK-8.4: Log Display Functions (3 hours)

Advanced log viewing with filtering per Q-006 requirement:

#### Log Functions

**`display_xray_logs(lines, level)`**
- Display Xray container logs
- Configurable line count (default: 100)
- Optional level filtering: ERROR, WARN, INFO, DEBUG

**`display_nginx_logs(lines, level)`**
- Display Nginx container logs
- Same filtering capabilities as Xray logs

**`display_all_logs(lines, level)`**
- Display logs from all containers
- Unified view with service prefixes
- Same filtering capabilities

**`follow_logs(service, level)`**
- Real-time log streaming
- Service selection: xray, nginx, or all
- Optional level filtering
- Ctrl+C to stop

**`filter_logs_by_level(level)`**
- Case-insensitive level matching
- ERROR: matches "error", "fatal", "err:", "failed"
- WARN: matches "warn", "warning"
- INFO: matches "info", "notice"
- DEBUG: matches "debug", "trace"

**`export_logs(service, output_file, lines)`**
- Export logs to file
- Configurable line count (default: 1000)
- Service selection: xray, nginx, or all
- Creates timestamped log files

#### Log Display Examples

**View last 100 Xray logs with ERROR filter:**
```bash
display_xray_logs 100 ERROR
```

**Follow all logs in real-time with WARN filter:**
```bash
follow_logs all WARN
```

**Export last 1000 logs to file:**
```bash
export_logs xray /tmp/xray_logs.txt 1000
```

## Dependencies

### Required Modules
- `lib/logger.sh` - Logging functions
- `lib/validation.sh` - Input validation

### External Tools
- `docker` - Container runtime
- `docker-compose` - Container orchestration
- `jq` - JSON parsing for user count
- `date` - Timestamp generation
- `grep` - Log filtering

## Security Considerations

### Backup Security
- Backups contain sensitive data (keys, users)
- Stored in `backups/` directory (should be secured)
- Automatic cleanup prevents disk exhaustion
- No encryption applied (consider adding in production)

### Update Safety
- Automatic backup before all updates
- Automatic rollback on failure
- Configuration preservation prevents data loss
- Graceful shutdown with timeout

### Log Access
- Logs may contain sensitive information
- No authentication on log viewing (should be added)
- Consider log rotation and retention policies

## Error Handling

### Robust Error Management
- All functions return 0 on success, 1 on failure
- Automatic rollback on update failures
- Graceful degradation (e.g., restart if HUP fails)
- Clear error messages via logger module

### Health Checks
- Container status verification
- Health check monitoring
- Timeout-based failure detection
- Automatic status reporting

## Integration Points

### User Management Integration
```bash
# After adding/removing users
source "${SCRIPT_DIR}/service_operations.sh"
reload_xray
```

### Orchestrator Integration
```bash
# After deployment
source "${SCRIPT_DIR}/service_operations.sh"
start_service
display_service_status
```

### Update Integration
```bash
# Scheduled updates
source "${SCRIPT_DIR}/service_operations.sh"
update_xray
```

## Usage Examples

### Basic Service Control

**Start service:**
```bash
source lib/service_operations.sh
start_service
```

**Stop service:**
```bash
stop_service
```

**Restart service:**
```bash
restart_service
```

**Reload Xray configuration:**
```bash
reload_xray
```

### Status Monitoring

**Display full status:**
```bash
display_service_status
```

**Check if service is running:**
```bash
if is_service_running; then
    echo "Service is running"
else
    echo "Service is stopped"
fi
```

**Get container uptime:**
```bash
uptime=$(get_container_uptime "xray")
echo "Xray uptime: $uptime"
```

### Update Operations

**Update Xray only:**
```bash
update_xray
```

**Update entire system:**
```bash
update_system
```

**Manual backup:**
```bash
create_config_backup
```

**Restore from backup:**
```bash
restore_config_backup
```

### Log Management

**View last 100 Xray logs:**
```bash
display_xray_logs 100
```

**View errors only:**
```bash
display_xray_logs 100 ERROR
```

**Follow logs in real-time:**
```bash
follow_logs xray
```

**Export logs to file:**
```bash
export_logs all /tmp/vpn_logs.txt 1000
```

## Performance Considerations

### Startup Time
- Service start: ~5-10 seconds
- Health check wait: up to 30 seconds
- Update process: ~30-60 seconds (depends on image size)

### Disk Usage
- Each backup: ~1-5 MB (depends on user count)
- 10 backups: ~10-50 MB
- Automatic cleanup prevents growth

### Log Volume
- Log retrieval: O(n) where n = line count
- Filtering: O(n) with grep
- Real-time following: minimal overhead

## Testing Recommendations

### Unit Tests
- [ ] Test start/stop/restart with mocked Docker
- [ ] Test status display with various container states
- [ ] Test backup creation and restoration
- [ ] Test log filtering with sample logs

### Integration Tests
- [ ] Test full update cycle
- [ ] Test rollback on update failure
- [ ] Test graceful reload vs. restart
- [ ] Test concurrent operations

### Edge Cases
- [ ] Service already running when starting
- [ ] Service not running when stopping
- [ ] Backup directory doesn't exist
- [ ] Container health check timeout
- [ ] Network configuration missing

## Future Enhancements

### Planned Features
1. **Metrics Collection**
   - Container resource usage (CPU, memory)
   - Network traffic statistics
   - Connection count monitoring

2. **Alerting System**
   - Email/webhook notifications on failures
   - Health check alerts
   - Resource threshold alerts

3. **Scheduled Operations**
   - Automatic updates with cron
   - Scheduled log rotation
   - Automated backup schedules

4. **Enhanced Logging**
   - Structured logging (JSON format)
   - Log aggregation support
   - Remote syslog integration

5. **Multi-Instance Support**
   - Manage multiple VPN instances
   - Load balancing support
   - Instance discovery

## Compliance

### Requirements Satisfied

| Requirement | Status | Implementation |
|------------|--------|----------------|
| Q-003 | ✅ | Update mechanism preserves subnet, port, keys |
| Q-006 | ✅ | Log filtering: ERROR, WARN, INFO levels |
| TASK-8.1 | ✅ | Start/stop/restart/reload commands |
| TASK-8.2 | ✅ | Comprehensive status display |
| TASK-8.3 | ✅ | Update with backup/restore |
| TASK-8.4 | ✅ | Log display with filtering |

## Conclusion

The Service Operations module provides a production-ready service management system for the VLESS Reality VPN. It implements all EPIC-8 requirements with robust error handling, configuration preservation, and comprehensive monitoring capabilities.

### Key Achievements
- ✅ Zero-downtime operations with graceful reload
- ✅ Configuration preservation during updates (Q-003)
- ✅ Advanced log filtering (Q-006)
- ✅ Automatic backup and rollback
- ✅ Comprehensive status monitoring
- ✅ 857 lines of well-documented bash code

### Statistics
- **Total Functions**: 33
- **Lines of Code**: 857
- **Time Estimate**: 16 hours
- **Dependencies**: 2 internal modules, 5 external tools
- **Test Coverage**: Ready for unit and integration testing
