#!/bin/bash
# Logging Setup Module for VLESS VPN Project
# Centralized logging system with rsyslog, logrotate, and monitoring
# Author: Claude Code
# Version: 1.0

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load common utilities
source "${SCRIPT_DIR}/common_utils.sh"

# Configuration
readonly RSYSLOG_CONFIG_DIR="/etc/rsyslog.d"
readonly LOGROTATE_CONFIG_DIR="/etc/logrotate.d"
readonly VLESS_LOG_DIR="/var/log/vless"
readonly MAIN_LOG_FILE="$VLESS_LOG_DIR/vless.log"
readonly ACCESS_LOG_FILE="$VLESS_LOG_DIR/access.log"
readonly ERROR_LOG_FILE="$VLESS_LOG_DIR/error.log"
readonly AUTH_LOG_FILE="$VLESS_LOG_DIR/auth.log"
readonly SYSTEM_LOG_FILE="$VLESS_LOG_DIR/system.log"
readonly MONITORING_LOG_FILE="$VLESS_LOG_DIR/monitoring.log"
readonly JSON_LOG_DIR="$VLESS_LOG_DIR/json"

# Log levels
readonly LOG_LEVEL_DEBUG=7
readonly LOG_LEVEL_INFO=6
readonly LOG_LEVEL_NOTICE=5
readonly LOG_LEVEL_WARNING=4
readonly LOG_LEVEL_ERROR=3
readonly LOG_LEVEL_CRITICAL=2
readonly LOG_LEVEL_ALERT=1
readonly LOG_LEVEL_EMERGENCY=0

# Initialize logging system
init_logging_system() {
    print_header "Initializing VLESS Logging System"

    # Create log directories
    ensure_directory "$VLESS_LOG_DIR" "755" "syslog"
    ensure_directory "$JSON_LOG_DIR" "755" "syslog"

    # Create log files with proper permissions
    local log_files=(
        "$MAIN_LOG_FILE"
        "$ACCESS_LOG_FILE"
        "$ERROR_LOG_FILE"
        "$AUTH_LOG_FILE"
        "$SYSTEM_LOG_FILE"
        "$MONITORING_LOG_FILE"
    )

    for log_file in "${log_files[@]}"; do
        sudo touch "$log_file"
        sudo chown syslog:adm "$log_file"
        sudo chmod 640 "$log_file"
    done

    print_success "Logging directories and files initialized"
}

# Setup rsyslog configuration
setup_rsyslog() {
    print_section "Configuring Rsyslog for VLESS"

    # Create VLESS rsyslog configuration
    sudo tee "$RSYSLOG_CONFIG_DIR/49-vless.conf" > /dev/null << 'EOF'
# VLESS VPN Logging Configuration

# Create separate log files for different components
$template VLESSLogFormat,"%timegenerated% %HOSTNAME% %syslogtag% %msg%\n"
$template VLESSJSONFormat,"{ \"timestamp\": \"%timegenerated:::date-rfc3339%\", \"hostname\": \"%HOSTNAME%\", \"facility\": \"%syslogfacility-text%\", \"priority\": \"%syslogpriority-text%\", \"tag\": \"%syslogtag%\", \"message\": \"%msg%\" }\n"

# VLESS main application logs (local0)
local0.*                    /var/log/vless/vless.log;VLESSLogFormat
local0.*                    /var/log/vless/json/vless.json;VLESSJSONFormat
& stop

# VLESS access logs (local1)
local1.*                    /var/log/vless/access.log;VLESSLogFormat
local1.*                    /var/log/vless/json/access.json;VLESSJSONFormat
& stop

# VLESS error logs (local2)
local2.*                    /var/log/vless/error.log;VLESSLogFormat
local2.*                    /var/log/vless/json/error.json;VLESSJSONFormat
& stop

# VLESS authentication logs (local3)
local3.*                    /var/log/vless/auth.log;VLESSLogFormat
local3.*                    /var/log/vless/json/auth.json;VLESSJSONFormat
& stop

# VLESS system logs (local4)
local4.*                    /var/log/vless/system.log;VLESSLogFormat
local4.*                    /var/log/vless/json/system.json;VLESSJSONFormat
& stop

# VLESS monitoring logs (local5)
local5.*                    /var/log/vless/monitoring.log;VLESSLogFormat
local5.*                    /var/log/vless/json/monitoring.json;VLESSJSONFormat
& stop

# High frequency logs for performance (disable sync)
$ModLoad imfile
$WorkDirectory /var/spool/rsyslog
$PrivDropToUser syslog
$PrivDropToGroup syslog

# Docker container logs
$InputFileName /var/lib/docker/containers/*/*-json.log
$InputFileTag docker-vless:
$InputFileStateFile stat-docker-vless
$InputFileSeverity info
$InputFileFacility local6
$InputRunFileMonitor

# Process Docker logs
local6.*                    /var/log/vless/docker.log;VLESSLogFormat
& stop
EOF

    # Restart rsyslog to apply configuration
    sudo systemctl restart rsyslog

    # Verify rsyslog status
    if systemctl is-active --quiet rsyslog; then
        print_success "Rsyslog configured and restarted successfully"
    else
        print_error "Failed to restart rsyslog"
        return 1
    fi
}

# Setup logrotate configuration
setup_logrotate() {
    print_section "Configuring Log Rotation"

    # Create logrotate configuration for VLESS logs
    sudo tee "$LOGROTATE_CONFIG_DIR/vless" > /dev/null << 'EOF'
# VLESS VPN Log Rotation Configuration

# Main application logs
/var/log/vless/vless.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    sharedscripts
    postrotate
        /bin/kill -HUP `cat /var/run/rsyslogd.pid 2> /dev/null` 2> /dev/null || true
        # Send log rotation notification if Telegram is configured
        if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${ADMIN_TELEGRAM_ID:-}" ]; then
            curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                -d "chat_id=${ADMIN_TELEGRAM_ID}" \
                -d "text=📋 Log rotated: vless.log on $(hostname)" \
                >/dev/null 2>&1 || true
        fi
    endscript
}

# Access logs (higher frequency)
/var/log/vless/access.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    sharedscripts
    postrotate
        /bin/kill -HUP `cat /var/run/rsyslogd.pid 2> /dev/null` 2> /dev/null || true
    endscript
}

# Error logs (keep longer)
/var/log/vless/error.log {
    daily
    missingok
    rotate 60
    compress
    delaycompress
    notifempty
    sharedscripts
    postrotate
        /bin/kill -HUP `cat /var/run/rsyslogd.pid 2> /dev/null` 2> /dev/null || true
    endscript
}

# Authentication logs (security critical - keep longer)
/var/log/vless/auth.log {
    daily
    missingok
    rotate 90
    compress
    delaycompress
    notifempty
    sharedscripts
    postrotate
        /bin/kill -HUP `cat /var/run/rsyslogd.pid 2> /dev/null` 2> /dev/null || true
    endscript
}

# System logs
/var/log/vless/system.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    sharedscripts
    postrotate
        /bin/kill -HUP `cat /var/run/rsyslogd.pid 2> /dev/null` 2> /dev/null || true
    endscript
}

# Monitoring logs
/var/log/vless/monitoring.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    sharedscripts
    postrotate
        /bin/kill -HUP `cat /var/run/rsyslogd.pid 2> /dev/null` 2> /dev/null || true
    endscript
}

# Docker logs
/var/log/vless/docker.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    sharedscripts
    postrotate
        /bin/kill -HUP `cat /var/run/rsyslogd.pid 2> /dev/null` 2> /dev/null || true
    endscript
}

# JSON logs (for external processing)
/var/log/vless/json/*.json {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    sharedscripts
    postrotate
        /bin/kill -HUP `cat /var/run/rsyslogd.pid 2> /dev/null` 2> /dev/null || true
    endscript
}
EOF

    # Test logrotate configuration
    if sudo logrotate -d "$LOGROTATE_CONFIG_DIR/vless" >/dev/null 2>&1; then
        print_success "Logrotate configuration created and tested successfully"
    else
        print_error "Logrotate configuration test failed"
        return 1
    fi
}

# Create logging functions for applications
create_logging_functions() {
    print_section "Creating Logging Helper Functions"

    # Create logging helper script
    sudo tee "/usr/local/bin/vless-logger" > /dev/null << 'EOF'
#!/bin/bash
# VLESS Logging Helper Script

# Log levels
LOG_EMERGENCY=0
LOG_ALERT=1
LOG_CRITICAL=2
LOG_ERROR=3
LOG_WARNING=4
LOG_NOTICE=5
LOG_INFO=6
LOG_DEBUG=7

# Facilities
FACILITY_MAIN="local0"
FACILITY_ACCESS="local1"
FACILITY_ERROR="local2"
FACILITY_AUTH="local3"
FACILITY_SYSTEM="local4"
FACILITY_MONITORING="local5"

# Function to log messages
vless_log() {
    local facility="$1"
    local level="$2"
    local component="$3"
    local message="$4"
    local user_info="${5:-$(whoami)}"
    local client_ip="${6:-unknown}"

    # Create structured message
    local structured_msg="[component=$component] [user=$user_info] [client_ip=$client_ip] $message"

    # Log to syslog
    logger -p "${facility}.${level}" -t "vless" "$structured_msg"

    # Also log to journal with metadata
    systemd-cat -t "vless-$component" -p "$level" <<< "$structured_msg"
}

# Convenience functions for different log types
log_main() {
    vless_log "$FACILITY_MAIN" "info" "main" "$@"
}

log_access() {
    vless_log "$FACILITY_ACCESS" "info" "access" "$@"
}

log_error() {
    vless_log "$FACILITY_ERROR" "err" "error" "$@"
}

log_auth() {
    vless_log "$FACILITY_AUTH" "info" "auth" "$@"
}

log_system() {
    vless_log "$FACILITY_SYSTEM" "info" "system" "$@"
}

log_monitoring() {
    vless_log "$FACILITY_MONITORING" "info" "monitoring" "$@"
}

# Log user connections
log_user_connection() {
    local user_uuid="$1"
    local client_ip="$2"
    local action="$3"  # connect/disconnect
    local protocol="${4:-vless}"

    log_access "User $action: uuid=$user_uuid protocol=$protocol" "system" "$client_ip"
}

# Log authentication events
log_auth_event() {
    local event_type="$1"  # success/failure/attempt
    local user_uuid="$2"
    local client_ip="$3"
    local details="${4:-}"

    log_auth "Authentication $event_type: uuid=$user_uuid $details" "system" "$client_ip"
}

# Log system events
log_system_event() {
    local event_type="$1"  # startup/shutdown/restart/config_change
    local details="$2"

    log_system "System $event_type: $details" "system" "localhost"
}

# Log errors with severity
log_error_event() {
    local severity="$1"  # low/medium/high/critical
    local component="$2"
    local error_msg="$3"
    local context="${4:-}"

    case "$severity" in
        "critical")
            vless_log "$FACILITY_ERROR" "crit" "$component" "$error_msg $context"
            ;;
        "high")
            vless_log "$FACILITY_ERROR" "err" "$component" "$error_msg $context"
            ;;
        "medium")
            vless_log "$FACILITY_ERROR" "warning" "$component" "$error_msg $context"
            ;;
        "low")
            vless_log "$FACILITY_ERROR" "notice" "$component" "$error_msg $context"
            ;;
        *)
            vless_log "$FACILITY_ERROR" "err" "$component" "$error_msg $context"
            ;;
    esac
}

# Performance logging
log_performance() {
    local metric_name="$1"
    local metric_value="$2"
    local unit="${3:-}"

    log_monitoring "Performance metric: $metric_name=$metric_value$unit"
}

# Usage information
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "VLESS Logger - Centralized logging for VLESS VPN"
    echo ""
    echo "Usage examples:"
    echo "  vless_log local0 info main 'Server started'"
    echo "  log_main 'Configuration updated'"
    echo "  log_access 'User connected' user-uuid client-ip"
    echo "  log_error 'Connection failed' component-name"
    echo "  log_auth_event success user-uuid client-ip"
    echo "  log_system_event startup 'Server initialization complete'"
    echo "  log_error_event critical xray 'Service crashed'"
    echo "  log_performance 'active_connections' 150"
    exit 0
fi

# If script is sourced, just define functions
# If executed directly, allow direct logging
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 4 ]]; then
        echo "Usage: $0 <facility> <level> <component> <message> [user] [client_ip]"
        echo "Try: $0 --help for more information"
        exit 1
    fi
    vless_log "$@"
fi
EOF

    sudo chmod +x "/usr/local/bin/vless-logger"

    print_success "Logging helper functions created"
}

# Setup log monitoring and alerting
setup_log_monitoring() {
    print_section "Setting up Log Monitoring and Alerting"

    # Create log monitoring script
    sudo tee "/usr/local/bin/vless-log-monitor" > /dev/null << 'EOF'
#!/bin/bash
# VLESS Log Monitoring and Anomaly Detection

VLESS_LOG_DIR="/var/log/vless"
ERROR_LOG="$VLESS_LOG_DIR/error.log"
AUTH_LOG="$VLESS_LOG_DIR/auth.log"
ACCESS_LOG="$VLESS_LOG_DIR/access.log"
ALERT_STATE_FILE="/tmp/vless-alert-state"
MAX_ERRORS_PER_MINUTE=10
MAX_FAILED_AUTH_PER_MINUTE=5

# Function to send alert
send_alert() {
    local severity="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Log the alert
    logger -p local5.warning -t "vless-monitor" "ALERT[$severity]: $message"

    # Send Telegram notification if configured
    if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]] && [[ -n "${ADMIN_TELEGRAM_ID:-}" ]]; then
        local emoji=""
        case "$severity" in
            "CRITICAL") emoji="🔴" ;;
            "HIGH") emoji="🟠" ;;
            "MEDIUM") emoji="🟡" ;;
            "LOW") emoji="🔵" ;;
        esac

        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${ADMIN_TELEGRAM_ID}" \
            -d "text=${emoji} VLESS Alert [$severity]
${message}

Time: ${timestamp}
Host: $(hostname)" \
            >/dev/null 2>&1 || true
    fi
}

# Check for error spikes
check_error_spike() {
    if [[ ! -f "$ERROR_LOG" ]]; then
        return 0
    fi

    local recent_errors=$(tail -n 1000 "$ERROR_LOG" | grep "$(date '+%Y-%m-%d %H:%M')" | wc -l)

    if [[ $recent_errors -gt $MAX_ERRORS_PER_MINUTE ]]; then
        if [[ ! -f "$ALERT_STATE_FILE.error_spike" ]]; then
            send_alert "HIGH" "Error spike detected: $recent_errors errors in the last minute (threshold: $MAX_ERRORS_PER_MINUTE)"
            touch "$ALERT_STATE_FILE.error_spike"
        fi
    else
        rm -f "$ALERT_STATE_FILE.error_spike"
    fi
}

# Check for authentication failures
check_auth_failures() {
    if [[ ! -f "$AUTH_LOG" ]]; then
        return 0
    fi

    local recent_failures=$(tail -n 1000 "$AUTH_LOG" | grep "$(date '+%Y-%m-%d %H:%M')" | grep -i "fail\|error\|denied" | wc -l)

    if [[ $recent_failures -gt $MAX_FAILED_AUTH_PER_MINUTE ]]; then
        if [[ ! -f "$ALERT_STATE_FILE.auth_failures" ]]; then
            send_alert "MEDIUM" "Authentication failure spike: $recent_failures failed attempts in the last minute (threshold: $MAX_FAILED_AUTH_PER_MINUTE)"
            touch "$ALERT_STATE_FILE.auth_failures"
        fi
    else
        rm -f "$ALERT_STATE_FILE.auth_failures"
    fi
}

# Check for suspicious IP patterns
check_suspicious_ips() {
    if [[ ! -f "$ACCESS_LOG" ]]; then
        return 0
    fi

    # Find IPs with high connection frequency
    local suspicious_ips=$(tail -n 2000 "$ACCESS_LOG" | grep "$(date '+%Y-%m-%d %H')" | \
        grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | \
        sort | uniq -c | sort -nr | head -5 | \
        awk '$1 > 100 {print $2 " (" $1 " connections)"}')

    if [[ -n "$suspicious_ips" ]]; then
        if [[ ! -f "$ALERT_STATE_FILE.suspicious_ips" ]]; then
            send_alert "MEDIUM" "Suspicious IP activity detected:
$suspicious_ips"
            touch "$ALERT_STATE_FILE.suspicious_ips"
        fi
    else
        rm -f "$ALERT_STATE_FILE.suspicious_ips"
    fi
}

# Check log file sizes
check_log_sizes() {
    local max_size_mb=1000  # 1GB threshold

    for log_file in "$VLESS_LOG_DIR"/*.log; do
        if [[ -f "$log_file" ]]; then
            local size_mb=$(du -m "$log_file" | cut -f1)
            local filename=$(basename "$log_file")

            if [[ $size_mb -gt $max_size_mb ]]; then
                if [[ ! -f "$ALERT_STATE_FILE.large_log_${filename}" ]]; then
                    send_alert "LOW" "Large log file detected: $filename ($size_mb MB)"
                    touch "$ALERT_STATE_FILE.large_log_${filename}"
                fi
            else
                rm -f "$ALERT_STATE_FILE.large_log_${filename}"
            fi
        fi
    done
}

# Check disk space for logs
check_disk_space() {
    local usage=$(df "$VLESS_LOG_DIR" | awk 'NR==2 {gsub(/%/, "", $5); print $5}')

    if [[ $usage -gt 90 ]]; then
        if [[ ! -f "$ALERT_STATE_FILE.disk_space" ]]; then
            send_alert "HIGH" "Log partition disk usage critical: ${usage}%"
            touch "$ALERT_STATE_FILE.disk_space"
        fi
    elif [[ $usage -gt 80 ]]; then
        if [[ ! -f "$ALERT_STATE_FILE.disk_space_warning" ]]; then
            send_alert "MEDIUM" "Log partition disk usage high: ${usage}%"
            touch "$ALERT_STATE_FILE.disk_space_warning"
        fi
    else
        rm -f "$ALERT_STATE_FILE.disk_space" "$ALERT_STATE_FILE.disk_space_warning"
    fi
}

# Main monitoring function
run_monitoring() {
    check_error_spike
    check_auth_failures
    check_suspicious_ips
    check_log_sizes
    check_disk_space
}

# Cleanup old alert state files (older than 1 hour)
cleanup_alert_states() {
    find /tmp -name "vless-alert-state*" -mmin +60 -delete 2>/dev/null || true
}

# Main execution
case "${1:-monitor}" in
    "monitor")
        run_monitoring
        cleanup_alert_states
        ;;
    "test-alert")
        send_alert "LOW" "Test alert from VLESS log monitoring system"
        ;;
    "reset-alerts")
        rm -f "$ALERT_STATE_FILE".*
        echo "Alert states reset"
        ;;
    *)
        echo "Usage: $0 {monitor|test-alert|reset-alerts}"
        exit 1
        ;;
esac
EOF

    sudo chmod +x "/usr/local/bin/vless-log-monitor"

    # Create cron job for log monitoring
    sudo tee "/etc/cron.d/vless-log-monitor" > /dev/null << 'EOF'
# VLESS Log Monitoring Cron Job
# Run every 2 minutes

*/2 * * * * root /usr/local/bin/vless-log-monitor monitor >/dev/null 2>&1
EOF

    print_success "Log monitoring and alerting configured"
}

# Create log analysis tools
create_log_analysis_tools() {
    print_section "Creating Log Analysis Tools"

    # Create log analysis script
    sudo tee "/usr/local/bin/vless-log-analyzer" > /dev/null << 'EOF'
#!/bin/bash
# VLESS Log Analysis Tool

VLESS_LOG_DIR="/var/log/vless"

# Function to show usage statistics
show_usage_stats() {
    local time_range="${1:-24}"  # hours
    local start_time=$(date -d "${time_range} hours ago" '+%Y-%m-%d %H:%M')

    echo "=== VLESS Usage Statistics (Last ${time_range} hours) ==="
    echo "Start time: $start_time"
    echo

    # Connection statistics
    if [[ -f "$VLESS_LOG_DIR/access.log" ]]; then
        echo "Connection Statistics:"
        local total_connections=$(grep -c "User connect" "$VLESS_LOG_DIR/access.log" 2>/dev/null || echo "0")
        local unique_users=$(grep "User connect" "$VLESS_LOG_DIR/access.log" 2>/dev/null | \
            grep -oE 'uuid=[a-f0-9-]+' | sort | uniq | wc -l)
        local unique_ips=$(grep "User connect" "$VLESS_LOG_DIR/access.log" 2>/dev/null | \
            grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | sort | uniq | wc -l)

        echo "  Total connections: $total_connections"
        echo "  Unique users: $unique_users"
        echo "  Unique IP addresses: $unique_ips"
        echo
    fi

    # Error statistics
    if [[ -f "$VLESS_LOG_DIR/error.log" ]]; then
        echo "Error Statistics:"
        local total_errors=$(wc -l < "$VLESS_LOG_DIR/error.log" 2>/dev/null || echo "0")
        local critical_errors=$(grep -c "CRITICAL\|crit" "$VLESS_LOG_DIR/error.log" 2>/dev/null || echo "0")
        local warnings=$(grep -c "WARNING\|warning" "$VLESS_LOG_DIR/error.log" 2>/dev/null || echo "0")

        echo "  Total errors: $total_errors"
        echo "  Critical errors: $critical_errors"
        echo "  Warnings: $warnings"
        echo
    fi

    # Top users by connection count
    if [[ -f "$VLESS_LOG_DIR/access.log" ]]; then
        echo "Top 10 Users by Connection Count:"
        grep "User connect" "$VLESS_LOG_DIR/access.log" 2>/dev/null | \
            grep -oE 'uuid=[a-f0-9-]+' | sort | uniq -c | sort -nr | head -10 | \
            awk '{print "  " $2 ": " $1 " connections"}' || echo "  No data available"
        echo
    fi

    # Top source IPs
    if [[ -f "$VLESS_LOG_DIR/access.log" ]]; then
        echo "Top 10 Source IP Addresses:"
        grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' "$VLESS_LOG_DIR/access.log" 2>/dev/null | \
            sort | uniq -c | sort -nr | head -10 | \
            awk '{print "  " $2 ": " $1 " connections"}' || echo "  No data available"
        echo
    fi
}

# Function to show recent errors
show_recent_errors() {
    local count="${1:-20}"

    echo "=== Recent Errors (Last $count) ==="
    if [[ -f "$VLESS_LOG_DIR/error.log" ]]; then
        tail -n "$count" "$VLESS_LOG_DIR/error.log" | \
            while IFS= read -r line; do
                echo "  $line"
            done
    else
        echo "  No error log found"
    fi
    echo
}

# Function to show authentication events
show_auth_events() {
    local count="${1:-20}"

    echo "=== Recent Authentication Events (Last $count) ==="
    if [[ -f "$VLESS_LOG_DIR/auth.log" ]]; then
        tail -n "$count" "$VLESS_LOG_DIR/auth.log" | \
            while IFS= read -r line; do
                echo "  $line"
            done
    else
        echo "  No authentication log found"
    fi
    echo
}

# Function to search logs
search_logs() {
    local pattern="$1"
    local log_type="${2:-all}"

    echo "=== Search Results for: $pattern ==="

    case "$log_type" in
        "all")
            for log_file in "$VLESS_LOG_DIR"/*.log; do
                if [[ -f "$log_file" ]]; then
                    local filename=$(basename "$log_file")
                    local results=$(grep -n "$pattern" "$log_file" 2>/dev/null || true)
                    if [[ -n "$results" ]]; then
                        echo "--- $filename ---"
                        echo "$results" | head -20
                        echo
                    fi
                fi
            done
            ;;
        *)
            local log_file="$VLESS_LOG_DIR/${log_type}.log"
            if [[ -f "$log_file" ]]; then
                grep -n "$pattern" "$log_file" | head -20
            else
                echo "Log file not found: $log_file"
            fi
            ;;
    esac
}

# Function to generate detailed report
generate_report() {
    local output_file="${1:-/tmp/vless-report-$(date +%Y%m%d_%H%M%S).txt}"

    echo "Generating detailed VLESS report..."

    {
        echo "VLESS VPN System Report"
        echo "Generated: $(date)"
        echo "Hostname: $(hostname)"
        echo "======================================"
        echo

        show_usage_stats 24
        show_recent_errors 10
        show_auth_events 10

        echo "=== System Information ==="
        echo "Disk usage for logs:"
        du -sh "$VLESS_LOG_DIR"/* 2>/dev/null || echo "No logs found"
        echo

        echo "Log file sizes:"
        ls -lh "$VLESS_LOG_DIR"/*.log 2>/dev/null || echo "No log files found"
        echo

        echo "=== Recent System Events ==="
        if [[ -f "$VLESS_LOG_DIR/system.log" ]]; then
            tail -n 10 "$VLESS_LOG_DIR/system.log"
        else
            echo "No system log found"
        fi

    } > "$output_file"

    echo "Report generated: $output_file"
}

# Main menu
case "${1:-help}" in
    "stats")
        show_usage_stats "${2:-24}"
        ;;
    "errors")
        show_recent_errors "${2:-20}"
        ;;
    "auth")
        show_auth_events "${2:-20}"
        ;;
    "search")
        if [[ -z "${2:-}" ]]; then
            echo "Usage: $0 search <pattern> [log_type]"
            exit 1
        fi
        search_logs "$2" "${3:-all}"
        ;;
    "report")
        generate_report "$2"
        ;;
    "help"|*)
        echo "VLESS Log Analyzer"
        echo ""
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  stats [hours]     - Show usage statistics (default: 24 hours)"
        echo "  errors [count]    - Show recent errors (default: 20)"
        echo "  auth [count]      - Show recent auth events (default: 20)"
        echo "  search <pattern> [log_type] - Search logs for pattern"
        echo "  report [file]     - Generate detailed report"
        echo "  help              - Show this help"
        echo ""
        echo "Examples:"
        echo "  $0 stats 6        - Show last 6 hours statistics"
        echo "  $0 search 'error' access  - Search for 'error' in access.log"
        echo "  $0 report /tmp/my-report.txt"
        ;;
esac
EOF

    sudo chmod +x "/usr/local/bin/vless-log-analyzer"

    print_success "Log analysis tools created"
}

# Main setup function
setup_logging() {
    print_header "VLESS Logging System Setup"

    init_logging_system
    setup_rsyslog
    setup_logrotate
    create_logging_functions
    setup_log_monitoring
    create_log_analysis_tools

    print_success "VLESS logging system setup completed"

    # Test the logging system
    test_logging_system
}

# Test logging system
test_logging_system() {
    print_section "Testing Logging System"

    # Source the logging functions
    source "/usr/local/bin/vless-logger"

    # Test different log types
    log_system_event "startup" "Logging system test"
    log_main "Test log entry from setup script"
    log_monitoring "Performance metric: setup_duration=300s"

    # Verify logs are created
    sleep 2
    local test_passed=true

    if [[ -f "$MAIN_LOG_FILE" ]] && grep -q "Test log entry" "$MAIN_LOG_FILE"; then
        print_success "Main logging test passed"
    else
        print_error "Main logging test failed"
        test_passed=false
    fi

    if [[ -f "$SYSTEM_LOG_FILE" ]] && grep -q "Logging system test" "$SYSTEM_LOG_FILE"; then
        print_success "System logging test passed"
    else
        print_error "System logging test failed"
        test_passed=false
    fi

    if [[ -f "$MONITORING_LOG_FILE" ]] && grep -q "setup_duration" "$MONITORING_LOG_FILE"; then
        print_success "Monitoring logging test passed"
    else
        print_error "Monitoring logging test failed"
        test_passed=false
    fi

    if $test_passed; then
        print_success "All logging tests passed"
    else
        print_error "Some logging tests failed - check configuration"
        return 1
    fi
}

# Show logging status
show_logging_status() {
    print_header "VLESS Logging System Status"

    # Check service status
    printf "%-25s " "Rsyslog service:"
    if systemctl is-active --quiet rsyslog; then
        echo -e "${GREEN}Active${NC}"
    else
        echo -e "${RED}Inactive${NC}"
    fi

    # Check log files
    echo
    echo "Log Files Status:"
    local log_files=(
        "$MAIN_LOG_FILE:Main logs"
        "$ACCESS_LOG_FILE:Access logs"
        "$ERROR_LOG_FILE:Error logs"
        "$AUTH_LOG_FILE:Authentication logs"
        "$SYSTEM_LOG_FILE:System logs"
        "$MONITORING_LOG_FILE:Monitoring logs"
    )

    for item in "${log_files[@]}"; do
        local file_path="${item%:*}"
        local description="${item#*:}"

        printf "  %-30s " "$description:"
        if [[ -f "$file_path" ]]; then
            local size=$(du -h "$file_path" | cut -f1)
            echo -e "${GREEN}Exists${NC} ($size)"
        else
            echo -e "${RED}Missing${NC}"
        fi
    done

    # Check configuration files
    echo
    echo "Configuration Files:"
    printf "  %-30s " "Rsyslog config:"
    if [[ -f "$RSYSLOG_CONFIG_DIR/49-vless.conf" ]]; then
        echo -e "${GREEN}Configured${NC}"
    else
        echo -e "${RED}Missing${NC}"
    fi

    printf "  %-30s " "Logrotate config:"
    if [[ -f "$LOGROTATE_CONFIG_DIR/vless" ]]; then
        echo -e "${GREEN}Configured${NC}"
    else
        echo -e "${RED}Missing${NC}"
    fi

    printf "  %-30s " "Log monitoring:"
    if [[ -f "/usr/local/bin/vless-log-monitor" ]]; then
        echo -e "${GREEN}Configured${NC}"
    else
        echo -e "${RED}Missing${NC}"
    fi

    # Show recent log activity
    echo
    print_section "Recent Log Activity"
    if [[ -f "$MAIN_LOG_FILE" ]]; then
        echo "Last 5 entries from main log:"
        tail -n 5 "$MAIN_LOG_FILE" | sed 's/^/  /'
    else
        echo "No main log activity"
    fi
}

# Remove logging setup
remove_logging() {
    print_header "Removing VLESS Logging System"

    if ! prompt_yes_no "Are you sure you want to remove the logging system?" "n"; then
        print_info "Logging system removal cancelled"
        return 0
    fi

    # Remove configuration files
    sudo rm -f "$RSYSLOG_CONFIG_DIR/49-vless.conf"
    sudo rm -f "$LOGROTATE_CONFIG_DIR/vless"
    sudo rm -f "/usr/local/bin/vless-logger"
    sudo rm -f "/usr/local/bin/vless-log-monitor"
    sudo rm -f "/usr/local/bin/vless-log-analyzer"
    sudo rm -f "/etc/cron.d/vless-log-monitor"

    # Restart rsyslog
    sudo systemctl restart rsyslog

    # Optionally remove log files
    if prompt_yes_no "Do you want to remove all log files as well?" "n"; then
        sudo rm -rf "$VLESS_LOG_DIR"
    fi

    print_success "VLESS logging system removed"
}

# Export functions
export -f setup_logging show_logging_status remove_logging test_logging_system
export -f init_logging_system setup_rsyslog setup_logrotate
export -f create_logging_functions setup_log_monitoring create_log_analysis_tools

# Main execution if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-setup}" in
        "setup"|"install"|"configure")
            setup_logging
            ;;
        "status"|"show")
            show_logging_status
            ;;
        "test")
            test_logging_system
            ;;
        "remove"|"uninstall")
            remove_logging
            ;;
        *)
            echo "Usage: $0 {setup|status|test|remove}"
            echo "  setup   - Setup and configure logging system"
            echo "  status  - Show logging system status"
            echo "  test    - Test logging functionality"
            echo "  remove  - Remove logging system"
            exit 1
            ;;
    esac
fi