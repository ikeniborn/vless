#!/bin/bash
# ======================================================================================
# VLESS+Reality VPN Management System - Logging Infrastructure Module
# ======================================================================================
# This module sets up centralized logging with rotation, levels, and analysis utilities.
# It configures logrotate and provides log management functions.
#
# Author: Claude Code
# Version: 1.0
# Last Modified: 2025-09-21
# ======================================================================================

set -euo pipefail

# Import common utilities
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SOURCE_DIR}/common_utils.sh"

# Logging configuration
readonly LOGROTATE_CONFIG_DIR="/etc/logrotate.d"
readonly VLESS_LOGROTATE_CONFIG="${LOGROTATE_CONFIG_DIR}/vless"
readonly RSYSLOG_CONFIG_DIR="/etc/rsyslog.d"
readonly VLESS_RSYSLOG_CONFIG="${RSYSLOG_CONFIG_DIR}/49-vless.conf"

# ======================================================================================
# LOGROTATE CONFIGURATION
# ======================================================================================

# Function: create_logrotate_config
# Description: Create logrotate configuration for VLESS logs
create_logrotate_config() {
    log_info "Creating logrotate configuration for VLESS logs..."

    cat > "$VLESS_LOGROTATE_CONFIG" << 'EOF'
# VLESS+Reality VPN Management System Log Rotation
# Rotate logs daily, keep 7 days, compress old logs

/opt/vless/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    sharedscripts
    postrotate
        # Signal any processes that need to reopen log files
        if [ -f /opt/vless/logs/vless.pid ]; then
            kill -USR1 $(cat /opt/vless/logs/vless.pid) 2>/dev/null || true
        fi
        # Restart rsyslog if it's managing our logs
        systemctl reload rsyslog 2>/dev/null || true
    endscript
}

# Rotate Docker logs if they exist
/opt/vless/logs/docker/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    maxsize 100M
}

# Rotate Xray logs
/opt/vless/logs/xray/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    maxsize 50M
    sharedscripts
    postrotate
        # Send SIGUSR1 to Xray for log rotation
        docker exec vless-xray pkill -USR1 xray 2>/dev/null || true
    endscript
}

# Rotate access logs
/opt/vless/logs/access/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    maxsize 200M
}

# Rotate security logs
/opt/vless/logs/security/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    copytruncate
}
EOF

    chmod 644 "$VLESS_LOGROTATE_CONFIG"
    log_success "Logrotate configuration created: $VLESS_LOGROTATE_CONFIG"
}

# Function: test_logrotate_config
# Description: Test the logrotate configuration
test_logrotate_config() {
    log_info "Testing logrotate configuration..."

    if logrotate -d "$VLESS_LOGROTATE_CONFIG" &>/dev/null; then
        log_success "Logrotate configuration is valid"
        return 0
    else
        log_error "Logrotate configuration has errors"
        return 1
    fi
}

# ======================================================================================
# RSYSLOG CONFIGURATION
# ======================================================================================

# Function: create_rsyslog_config
# Description: Create rsyslog configuration for centralized logging
create_rsyslog_config() {
    log_info "Creating rsyslog configuration for VLESS..."

    cat > "$VLESS_RSYSLOG_CONFIG" << 'EOF'
# VLESS+Reality VPN Management System - Rsyslog Configuration
# Centralized logging configuration for VLESS components

# Create log directories
$CreateDirs on

# VLESS application logs
:programname, isequal, "vless"                /opt/vless/logs/vless.log
:programname, startswith, "vless-"            /opt/vless/logs/vless.log

# Docker container logs for VLESS
:programname, isequal, "dockerd"              /opt/vless/logs/docker/docker.log
:programname, startswith, "docker/"           /opt/vless/logs/docker/containers.log

# Security-related logs
:msg, contains, "VLESS"                       /opt/vless/logs/security/vless-security.log
:msg, contains, "Failed password"             /opt/vless/logs/security/auth-failures.log
:msg, contains, "authentication failure"      /opt/vless/logs/security/auth-failures.log

# UFW firewall logs
:msg, contains, "[UFW "                       /opt/vless/logs/security/firewall.log

# Stop processing these messages
:programname, isequal, "vless"                stop
:programname, startswith, "vless-"            stop

# Rate limiting for security logs
$SystemLogRateLimitInterval 10
$SystemLogRateLimitBurst 50
EOF

    chmod 644 "$VLESS_RSYSLOG_CONFIG"
    log_success "Rsyslog configuration created: $VLESS_RSYSLOG_CONFIG"
}

# Function: restart_rsyslog
# Description: Restart rsyslog service to apply new configuration
restart_rsyslog() {
    log_info "Restarting rsyslog service..."

    if systemctl restart rsyslog; then
        log_success "Rsyslog service restarted successfully"
        return 0
    else
        log_error "Failed to restart rsyslog service"
        return 1
    fi
}

# ======================================================================================
# LOG DIRECTORY STRUCTURE
# ======================================================================================

# Function: create_log_directories
# Description: Create organized log directory structure
create_log_directories() {
    local log_dirs=(
        "$LOG_DIR"
        "$LOG_DIR/docker"
        "$LOG_DIR/xray"
        "$LOG_DIR/access"
        "$LOG_DIR/security"
        "$LOG_DIR/backup"
        "$LOG_DIR/maintenance"
        "$LOG_DIR/user-management"
        "$LOG_DIR/telegram-bot"
    )

    log_info "Creating log directory structure..."

    for dir in "${log_dirs[@]}"; do
        create_directory "$dir" "755" "root:root"
    done

    log_success "Log directory structure created"
}

# ======================================================================================
# LOG MANAGEMENT UTILITIES
# ======================================================================================

# Function: setup_log_levels
# Description: Configure log level environment
setup_log_levels() {
    local env_file="/opt/vless/config/logging.env"

    log_info "Setting up log level configuration..."

    cat > "$env_file" << 'EOF'
# VLESS Logging Configuration
# Log levels: 0=DEBUG, 1=INFO, 2=WARN, 3=ERROR

# Default log level for all components
VLESS_LOG_LEVEL=1

# Component-specific log levels
VLESS_DOCKER_LOG_LEVEL=1
VLESS_XRAY_LOG_LEVEL=1
VLESS_SECURITY_LOG_LEVEL=1
VLESS_USER_MGMT_LOG_LEVEL=1
VLESS_TELEGRAM_BOT_LOG_LEVEL=1

# Log file settings
VLESS_LOG_MAX_SIZE=10485760  # 10MB
VLESS_LOG_RETENTION_DAYS=7
VLESS_LOG_COMPRESSION=true

# Performance logging
VLESS_PERFORMANCE_LOGGING=false
VLESS_ACCESS_LOGGING=true
EOF

    chmod 600 "$env_file"
    log_success "Log level configuration created: $env_file"
}

# Function: create_log_analysis_script
# Description: Create script for log analysis and monitoring
create_log_analysis_script() {
    local analysis_script="/opt/vless/bin/analyze-logs.sh"

    create_directory "/opt/vless/bin" "755" "root:root"

    cat > "$analysis_script" << 'EOF'
#!/bin/bash
# VLESS Log Analysis Utility
# Analyze logs for patterns, errors, and security issues

set -euo pipefail

# Source common utilities
source /opt/vless/modules/common_utils.sh

# Default values
LOG_DIR="/opt/vless/logs"
HOURS_BACK=24
SHOW_ERRORS=false
SHOW_WARNINGS=false
SHOW_SECURITY=false
SHOW_STATS=false

# Function: show_usage
show_usage() {
    cat << 'USAGE'
Usage: analyze-logs.sh [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -t, --hours HOURS   Analyze logs from last N hours (default: 24)
    -e, --errors        Show error analysis
    -w, --warnings      Show warning analysis
    -s, --security      Show security events
    -a, --stats         Show statistics summary
    --all              Show all analysis types

EXAMPLES:
    analyze-logs.sh --errors --hours 6
    analyze-logs.sh --security --stats
    analyze-logs.sh --all --hours 48
USAGE
}

# Function: analyze_errors
analyze_errors() {
    echo "=== ERROR ANALYSIS (Last $HOURS_BACK hours) ==="
    find "$LOG_DIR" -name "*.log" -mtime -1 -exec grep -l "ERROR" {} \; | while read -r logfile; do
        echo "Errors in $(basename "$logfile"):"
        grep "ERROR" "$logfile" | tail -20
        echo ""
    done
}

# Function: analyze_warnings
analyze_warnings() {
    echo "=== WARNING ANALYSIS (Last $HOURS_BACK hours) ==="
    find "$LOG_DIR" -name "*.log" -mtime -1 -exec grep -l "WARN" {} \; | while read -r logfile; do
        echo "Warnings in $(basename "$logfile"):"
        grep "WARN" "$logfile" | tail -10
        echo ""
    done
}

# Function: analyze_security
analyze_security() {
    echo "=== SECURITY ANALYSIS (Last $HOURS_BACK hours) ==="
    local security_log="$LOG_DIR/security/vless-security.log"
    local auth_log="$LOG_DIR/security/auth-failures.log"
    local fw_log="$LOG_DIR/security/firewall.log"

    if [[ -f "$security_log" ]]; then
        echo "Security Events:"
        tail -50 "$security_log"
        echo ""
    fi

    if [[ -f "$auth_log" ]]; then
        echo "Authentication Failures:"
        tail -20 "$auth_log"
        echo ""
    fi

    if [[ -f "$fw_log" ]]; then
        echo "Firewall Events:"
        tail -30 "$fw_log"
        echo ""
    fi
}

# Function: show_statistics
show_statistics() {
    echo "=== LOG STATISTICS (Last $HOURS_BACK hours) ==="

    # Count log entries by level
    echo "Log Levels:"
    find "$LOG_DIR" -name "*.log" -mtime -1 -exec grep -h "\[.*\]" {} \; | \
        sed -n 's/.*\[\([^]]*\)\].*/\1/p' | sort | uniq -c | sort -nr
    echo ""

    # Disk usage
    echo "Log Directory Disk Usage:"
    du -sh "$LOG_DIR"/* 2>/dev/null | sort -hr
    echo ""

    # Active connections (if available)
    if command -v ss >/dev/null; then
        echo "Current Network Connections:"
        ss -tuln | grep -E ":(443|80|8080|1080)" || echo "No VLESS-related ports active"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -t|--hours)
            HOURS_BACK="$2"
            shift 2
            ;;
        -e|--errors)
            SHOW_ERRORS=true
            shift
            ;;
        -w|--warnings)
            SHOW_WARNINGS=true
            shift
            ;;
        -s|--security)
            SHOW_SECURITY=true
            shift
            ;;
        -a|--stats)
            SHOW_STATS=true
            shift
            ;;
        --all)
            SHOW_ERRORS=true
            SHOW_WARNINGS=true
            SHOW_SECURITY=true
            SHOW_STATS=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# If no specific analysis requested, show stats
if [[ "$SHOW_ERRORS" = false && "$SHOW_WARNINGS" = false && "$SHOW_SECURITY" = false && "$SHOW_STATS" = false ]]; then
    SHOW_STATS=true
fi

# Run requested analysis
[[ "$SHOW_ERRORS" = true ]] && analyze_errors
[[ "$SHOW_WARNINGS" = true ]] && analyze_warnings
[[ "$SHOW_SECURITY" = true ]] && analyze_security
[[ "$SHOW_STATS" = true ]] && show_statistics
EOF

    chmod 755 "$analysis_script"
    log_success "Log analysis script created: $analysis_script"
}

# ======================================================================================
# PERFORMANCE MONITORING
# ======================================================================================

# Function: setup_log_monitoring
# Description: Setup automated log monitoring and alerts
setup_log_monitoring() {
    local monitor_script="/opt/vless/bin/log-monitor.sh"

    cat > "$monitor_script" << 'EOF'
#!/bin/bash
# VLESS Log Monitoring - Automated log analysis and alerting

set -euo pipefail

# Source common utilities
source /opt/vless/modules/common_utils.sh

LOG_DIR="/opt/vless/logs"
ALERT_THRESHOLD_ERRORS=10
ALERT_THRESHOLD_WARNINGS=50
CHECK_INTERVAL=300  # 5 minutes

# Function: check_error_rate
check_error_rate() {
    local error_count
    error_count=$(find "$LOG_DIR" -name "*.log" -mmin -5 -exec grep -c "ERROR" {} + 2>/dev/null | awk '{sum+=$1} END {print sum+0}')

    if [[ $error_count -gt $ALERT_THRESHOLD_ERRORS ]]; then
        log_warn "High error rate detected: $error_count errors in last 5 minutes"
        return 1
    fi
    return 0
}

# Function: check_disk_usage
check_disk_usage() {
    local usage_percent
    usage_percent=$(df "$LOG_DIR" | tail -1 | awk '{print $5}' | sed 's/%//')

    if [[ $usage_percent -gt 80 ]]; then
        log_warn "Log directory disk usage high: ${usage_percent}%"
        return 1
    fi
    return 0
}

# Function: check_log_files
check_log_files() {
    local large_files
    large_files=$(find "$LOG_DIR" -name "*.log" -size +100M)

    if [[ -n "$large_files" ]]; then
        log_warn "Large log files detected (>100MB):"
        echo "$large_files"
        return 1
    fi
    return 0
}

# Main monitoring loop
log_info "Starting log monitoring (PID: $$)"
echo $$ > "$LOG_DIR/log-monitor.pid"

while true; do
    check_error_rate
    check_disk_usage
    check_log_files
    sleep $CHECK_INTERVAL
done
EOF

    chmod 755 "$monitor_script"
    log_success "Log monitoring script created: $monitor_script"
}

# ======================================================================================
# MAIN SETUP FUNCTIONS
# ======================================================================================

# Function: setup_logging_infrastructure
# Description: Complete logging infrastructure setup
setup_logging_infrastructure() {
    log_info "Setting up VLESS logging infrastructure..."

    # Create log directories
    create_log_directories

    # Setup log rotation
    create_logrotate_config
    test_logrotate_config

    # Setup centralized logging
    create_rsyslog_config
    restart_rsyslog

    # Setup log levels and configuration
    setup_log_levels

    # Create analysis and monitoring utilities
    create_log_analysis_script
    setup_log_monitoring

    log_success "Logging infrastructure setup completed"
}

# Function: verify_logging_setup
# Description: Verify that logging setup is working correctly
verify_logging_setup() {
    log_info "Verifying logging setup..."

    local checks_passed=0
    local total_checks=5

    # Check log directories exist
    if [[ -d "$LOG_DIR" ]]; then
        log_success "Log directory exists: $LOG_DIR"
        ((checks_passed++))
    else
        log_error "Log directory missing: $LOG_DIR"
    fi

    # Check logrotate config
    if [[ -f "$VLESS_LOGROTATE_CONFIG" ]]; then
        log_success "Logrotate configuration exists"
        ((checks_passed++))
    else
        log_error "Logrotate configuration missing"
    fi

    # Check rsyslog config
    if [[ -f "$VLESS_RSYSLOG_CONFIG" ]]; then
        log_success "Rsyslog configuration exists"
        ((checks_passed++))
    else
        log_error "Rsyslog configuration missing"
    fi

    # Test log writing
    local test_log="$LOG_DIR/test.log"
    if echo "Test log entry $(date)" > "$test_log"; then
        log_success "Log writing test passed"
        rm -f "$test_log"
        ((checks_passed++))
    else
        log_error "Log writing test failed"
    fi

    # Check rsyslog service
    if systemctl is-active --quiet rsyslog; then
        log_success "Rsyslog service is running"
        ((checks_passed++))
    else
        log_error "Rsyslog service is not running"
    fi

    # Report results
    log_info "Logging verification: $checks_passed/$total_checks checks passed"

    if [[ $checks_passed -eq $total_checks ]]; then
        log_success "All logging infrastructure checks passed"
        return 0
    else
        log_error "Some logging infrastructure checks failed"
        return 1
    fi
}

# ======================================================================================
# MAIN EXECUTION
# ======================================================================================

# Function: main
# Description: Main function for logging setup
main() {
    log_info "Initializing VLESS logging infrastructure..."

    # Validate environment
    validate_root

    # Setup logging infrastructure
    setup_logging_infrastructure

    # Verify setup
    verify_logging_setup

    log_success "VLESS logging infrastructure setup completed successfully"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi