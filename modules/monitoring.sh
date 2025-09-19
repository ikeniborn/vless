#!/bin/bash
# Monitoring Module for VLESS VPN Project
# System monitoring, alerting, and auto-recovery
# Author: Claude Code
# Version: 1.0

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load common utilities
source "${SCRIPT_DIR}/common_utils.sh"

# Configuration
readonly MONITORING_CONFIG_DIR="/etc/vless-monitoring"
readonly MONITORING_DATA_DIR="/var/lib/vless-monitoring"
readonly MONITORING_LOG="/var/log/vless/monitoring.log"
readonly ALERT_STATE_DIR="/tmp/vless-alerts"
readonly METRICS_FILE="$MONITORING_DATA_DIR/metrics.json"
readonly THRESHOLDS_FILE="$MONITORING_CONFIG_DIR/thresholds.conf"

# Default thresholds
readonly DEFAULT_CPU_WARNING=80
readonly DEFAULT_CPU_CRITICAL=95
readonly DEFAULT_RAM_WARNING=85
readonly DEFAULT_RAM_CRITICAL=95
readonly DEFAULT_DISK_WARNING=80
readonly DEFAULT_DISK_CRITICAL=90
readonly DEFAULT_LOAD_WARNING=3.0
readonly DEFAULT_LOAD_CRITICAL=5.0

# Initialize monitoring system
init_monitoring() {
    print_header "Initializing VLESS Monitoring System"

    # Create directories
    ensure_directory "$MONITORING_CONFIG_DIR" "755" "root"
    ensure_directory "$MONITORING_DATA_DIR" "755" "root"
    ensure_directory "$ALERT_STATE_DIR" "755" "root"

    # Create configuration files
    create_thresholds_config
    create_monitoring_config

    print_success "Monitoring system initialized"
}

# Create thresholds configuration
create_thresholds_config() {
    print_section "Creating Monitoring Thresholds Configuration"

    cat > "$THRESHOLDS_FILE" << EOF
# VLESS Monitoring Thresholds Configuration
# Format: METRIC_WARNING=value
#         METRIC_CRITICAL=value

# CPU Usage (percentage)
CPU_WARNING=$DEFAULT_CPU_WARNING
CPU_CRITICAL=$DEFAULT_CPU_CRITICAL

# RAM Usage (percentage)
RAM_WARNING=$DEFAULT_RAM_WARNING
RAM_CRITICAL=$DEFAULT_RAM_CRITICAL

# Disk Usage (percentage)
DISK_WARNING=$DEFAULT_DISK_WARNING
DISK_CRITICAL=$DEFAULT_DISK_CRITICAL

# Load Average (1-minute)
LOAD_WARNING=$DEFAULT_LOAD_WARNING
LOAD_CRITICAL=$DEFAULT_LOAD_CRITICAL

# Network Connections
CONNECTIONS_WARNING=1000
CONNECTIONS_CRITICAL=1500

# Response Time (milliseconds)
RESPONSE_TIME_WARNING=1000
RESPONSE_TIME_CRITICAL=3000

# Service Check Failures
SERVICE_FAILURES_WARNING=3
SERVICE_FAILURES_CRITICAL=5

# User Connection Count
USER_CONNECTIONS_WARNING=500
USER_CONNECTIONS_CRITICAL=800

# Alert Cooldown (seconds)
ALERT_COOLDOWN=300

# Telegram Settings
TELEGRAM_ENABLED=true
TELEGRAM_MENTION_ON_CRITICAL=true
EOF

    print_success "Thresholds configuration created"
}

# Load configuration
load_config() {
    if [[ -f "$THRESHOLDS_FILE" ]]; then
        source "$THRESHOLDS_FILE"
    else
        print_warning "Thresholds file not found, using defaults"
    fi
}

# Logging function for monitoring
log_monitoring() {
    local level="$1"
    local message="$2"
    local timestamp=$(get_timestamp)

    echo "[$timestamp] [$level] $message" | tee -a "$MONITORING_LOG"

    # Also log via system logger if available
    if command -v vless-logger >/dev/null 2>&1; then
        source /usr/local/bin/vless-logger
        log_monitoring "$message"
    fi
}

# Send alert function
send_alert() {
    local severity="$1"
    local title="$2"
    local message="$3"
    local metric="${4:-}"
    local value="${5:-}"

    local alert_id="${metric}_${severity}"
    local alert_file="$ALERT_STATE_DIR/$alert_id"
    local current_time=$(date +%s)

    # Check cooldown
    if [[ -f "$alert_file" ]]; then
        local last_alert=$(cat "$alert_file")
        local time_diff=$((current_time - last_alert))

        if [[ $time_diff -lt ${ALERT_COOLDOWN:-300} ]]; then
            return 0  # Skip alert due to cooldown
        fi
    fi

    # Update alert state
    echo "$current_time" > "$alert_file"

    # Log the alert
    log_monitoring "ALERT" "[$severity] $title: $message"

    # Send Telegram notification if configured
    if [[ "${TELEGRAM_ENABLED:-false}" == "true" ]] && \
       [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]] && \
       [[ -n "${ADMIN_TELEGRAM_ID:-}" ]]; then

        send_telegram_alert "$severity" "$title" "$message" "$metric" "$value"
    fi

    # Trigger auto-recovery if configured
    if [[ "$severity" == "CRITICAL" ]]; then
        trigger_auto_recovery "$metric" "$value"
    fi
}

# Send Telegram alert
send_telegram_alert() {
    local severity="$1"
    local title="$2"
    local message="$3"
    local metric="${4:-}"
    local value="${5:-}"

    local emoji=""
    case "$severity" in
        "CRITICAL") emoji="🔴" ;;
        "WARNING") emoji="🟡" ;;
        "INFO") emoji="🔵" ;;
        "RECOVERY") emoji="🟢" ;;
        *) emoji="ℹ️" ;;
    esac

    local hostname=$(hostname)
    local timestamp=$(get_timestamp)
    local mention=""

    if [[ "$severity" == "CRITICAL" ]] && [[ "${TELEGRAM_MENTION_ON_CRITICAL:-false}" == "true" ]]; then
        mention="@admin "
    fi

    local alert_text="${emoji} ${mention}VLESS Alert [$severity]

📋 $title
💻 Host: $hostname
🕐 Time: $timestamp

📊 Details:
$message"

    if [[ -n "$metric" ]] && [[ -n "$value" ]]; then
        alert_text+="\n📈 Metric: $metric = $value"
    fi

    # Add quick actions for critical alerts
    if [[ "$severity" == "CRITICAL" ]]; then
        alert_text+="\n\n🔧 Quick Actions:
• /restart - Restart services
• /status - Check system status
• /logs - View recent logs"
    fi

    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${ADMIN_TELEGRAM_ID}" \
        -d "text=$alert_text" \
        -d "parse_mode=HTML" \
        >/dev/null 2>&1 || log_monitoring "ERROR" "Failed to send Telegram alert"
}

# Clear alert state
clear_alert() {
    local metric="$1"
    local severity="$2"
    local alert_id="${metric}_${severity}"
    local alert_file="$ALERT_STATE_DIR/$alert_id"

    if [[ -f "$alert_file" ]]; then
        rm -f "$alert_file"
        send_alert "RECOVERY" "Alert Cleared" "Metric $metric has returned to normal levels" "$metric"
    fi
}

# Get system metrics
get_cpu_usage() {
    top -bn1 | grep "Cpu(s)" | awk '{print $2+$4}' | sed 's/%us,//'
}

get_ram_usage() {
    free | awk 'FNR==2{printf "%.0f", ($3/($3+$7))*100}'
}

get_disk_usage() {
    df -h / | awk 'NR==2 {gsub(/%/, "", $5); print $5}'
}

get_load_average() {
    uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//'
}

get_network_connections() {
    netstat -an | grep ESTABLISHED | wc -l
}

get_service_status() {
    local service="$1"
    if systemctl is-active --quiet "$service"; then
        echo "active"
    else
        echo "inactive"
    fi
}

get_docker_container_status() {
    local container="$1"
    docker ps --filter "name=$container" --format "table {{.Status}}" | tail -n +2 | head -1
}

get_xray_response_time() {
    local test_url="http://localhost:80"
    local response_time=$(curl -o /dev/null -s -w "%{time_total}" --max-time 5 "$test_url" 2>/dev/null || echo "timeout")

    if [[ "$response_time" == "timeout" ]]; then
        echo "9999"
    else
        echo "$response_time" | awk '{printf "%.0f", $1*1000}'
    fi
}

get_active_vpn_users() {
    # Parse Xray logs to count active connections
    local access_log="/var/log/vless/access.log"
    if [[ -f "$access_log" ]]; then
        # Count unique users in last 5 minutes
        local five_min_ago=$(date -d '5 minutes ago' '+%Y-%m-%d %H:%M')
        grep "$five_min_ago" "$access_log" 2>/dev/null | \
            grep -oE 'uuid=[a-f0-9-]+' | sort | uniq | wc -l || echo "0"
    else
        echo "0"
    fi
}

# Check system health
check_system_health() {
    load_config

    local cpu_usage=$(get_cpu_usage)
    local ram_usage=$(get_ram_usage)
    local disk_usage=$(get_disk_usage)
    local load_avg=$(get_load_average)
    local connections=$(get_network_connections)
    local response_time=$(get_xray_response_time)
    local active_users=$(get_active_vpn_users)

    # Store metrics
    store_metrics "$cpu_usage" "$ram_usage" "$disk_usage" "$load_avg" "$connections" "$response_time" "$active_users"

    # Check CPU usage
    if (( $(echo "$cpu_usage >= $CPU_CRITICAL" | bc -l) )); then
        send_alert "CRITICAL" "High CPU Usage" "CPU usage is at ${cpu_usage}% (critical threshold: ${CPU_CRITICAL}%)" "cpu" "$cpu_usage"
    elif (( $(echo "$cpu_usage >= $CPU_WARNING" | bc -l) )); then
        send_alert "WARNING" "Elevated CPU Usage" "CPU usage is at ${cpu_usage}% (warning threshold: ${CPU_WARNING}%)" "cpu" "$cpu_usage"
    else
        clear_alert "cpu" "WARNING"
        clear_alert "cpu" "CRITICAL"
    fi

    # Check RAM usage
    if [[ $ram_usage -ge $RAM_CRITICAL ]]; then
        send_alert "CRITICAL" "High Memory Usage" "RAM usage is at ${ram_usage}% (critical threshold: ${RAM_CRITICAL}%)" "ram" "$ram_usage"
    elif [[ $ram_usage -ge $RAM_WARNING ]]; then
        send_alert "WARNING" "Elevated Memory Usage" "RAM usage is at ${ram_usage}% (warning threshold: ${RAM_WARNING}%)" "ram" "$ram_usage"
    else
        clear_alert "ram" "WARNING"
        clear_alert "ram" "CRITICAL"
    fi

    # Check disk usage
    if [[ $disk_usage -ge $DISK_CRITICAL ]]; then
        send_alert "CRITICAL" "High Disk Usage" "Disk usage is at ${disk_usage}% (critical threshold: ${DISK_CRITICAL}%)" "disk" "$disk_usage"
    elif [[ $disk_usage -ge $DISK_WARNING ]]; then
        send_alert "WARNING" "Elevated Disk Usage" "Disk usage is at ${disk_usage}% (warning threshold: ${DISK_WARNING}%)" "disk" "$disk_usage"
    else
        clear_alert "disk" "WARNING"
        clear_alert "disk" "CRITICAL"
    fi

    # Check load average
    if (( $(echo "$load_avg >= $LOAD_CRITICAL" | bc -l) )); then
        send_alert "CRITICAL" "High System Load" "Load average is ${load_avg} (critical threshold: ${LOAD_CRITICAL})" "load" "$load_avg"
    elif (( $(echo "$load_avg >= $LOAD_WARNING" | bc -l) )); then
        send_alert "WARNING" "Elevated System Load" "Load average is ${load_avg} (warning threshold: ${LOAD_WARNING})" "load" "$load_avg"
    else
        clear_alert "load" "WARNING"
        clear_alert "load" "CRITICAL"
    fi

    # Check response time
    if [[ $response_time -ge $RESPONSE_TIME_CRITICAL ]]; then
        send_alert "CRITICAL" "High Response Time" "Service response time is ${response_time}ms (critical threshold: ${RESPONSE_TIME_CRITICAL}ms)" "response_time" "$response_time"
    elif [[ $response_time -ge $RESPONSE_TIME_WARNING ]]; then
        send_alert "WARNING" "Elevated Response Time" "Service response time is ${response_time}ms (warning threshold: ${RESPONSE_TIME_WARNING}ms)" "response_time" "$response_time"
    else
        clear_alert "response_time" "WARNING"
        clear_alert "response_time" "CRITICAL"
    fi
}

# Store metrics in JSON format
store_metrics() {
    local cpu="$1"
    local ram="$2"
    local disk="$3"
    local load="$4"
    local connections="$5"
    local response_time="$6"
    local active_users="$7"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local metrics_json=$(cat << EOF
{
  "timestamp": "$timestamp",
  "hostname": "$(hostname)",
  "metrics": {
    "cpu_usage": $cpu,
    "ram_usage": $ram,
    "disk_usage": $disk,
    "load_average": $load,
    "network_connections": $connections,
    "response_time": $response_time,
    "active_users": $active_users,
    "uptime": "$(cat /proc/uptime | awk '{print $1}')"
  },
  "services": {
    "vless-vpn": "$(get_service_status vless-vpn || echo 'unknown')",
    "docker": "$(get_service_status docker)",
    "xray": "$(get_docker_container_status xray 2>/dev/null || echo 'unknown')",
    "telegram-bot": "$(get_docker_container_status telegram-bot 2>/dev/null || echo 'unknown')"
  }
}
EOF
)

    # Store current metrics
    echo "$metrics_json" > "$METRICS_FILE"

    # Append to historical data (keep last 1440 entries = 24 hours if run every minute)
    local history_file="$MONITORING_DATA_DIR/metrics_history.jsonl"
    echo "$metrics_json" >> "$history_file"

    # Keep only last 1440 lines (24 hours of data)
    tail -n 1440 "$history_file" > "${history_file}.tmp" && mv "${history_file}.tmp" "$history_file"
}

# Check service availability
check_services() {
    local services=("docker" "vless-vpn")
    local failed_services=()

    for service in "${services[@]}"; do
        if ! systemctl is-active --quiet "$service"; then
            failed_services+=("$service")
            send_alert "CRITICAL" "Service Down" "Service $service is not running" "service" "$service"
        fi
    done

    # Check Docker containers
    local containers=("xray" "telegram-bot")
    for container in "${containers[@]}"; do
        if ! docker ps --filter "name=$container" --filter "status=running" --quiet | grep -q .; then
            failed_services+=("$container")
            send_alert "CRITICAL" "Container Down" "Docker container $container is not running" "container" "$container"
        fi
    done

    if [[ ${#failed_services[@]} -eq 0 ]]; then
        clear_alert "services" "CRITICAL"
        log_monitoring "INFO" "All services are running normally"
    else
        log_monitoring "ERROR" "Failed services: ${failed_services[*]}"
    fi
}

# Auto-recovery actions
trigger_auto_recovery() {
    local metric="$1"
    local value="$2"

    log_monitoring "INFO" "Triggering auto-recovery for metric: $metric (value: $value)"

    case "$metric" in
        "ram")
            # Clear system caches
            sync && echo 3 > /proc/sys/vm/drop_caches
            log_monitoring "INFO" "Cleared system caches for RAM recovery"
            ;;
        "disk")
            # Clean up logs and temporary files
            find /var/log -name "*.log" -mtime +7 -delete 2>/dev/null || true
            find /tmp -type f -mtime +1 -delete 2>/dev/null || true
            log_monitoring "INFO" "Cleaned up disk space"
            ;;
        "service"|"container")
            # Restart failed service/container
            if [[ "$value" == "vless-vpn" ]]; then
                systemctl restart vless-vpn
            elif [[ "$value" == "docker" ]]; then
                systemctl restart docker
            else
                # Try to restart the container
                cd /opt/vless && docker-compose restart "$value" 2>/dev/null || true
            fi
            log_monitoring "INFO" "Attempted to restart $value"
            ;;
    esac
}

# Generate monitoring report
generate_monitoring_report() {
    local hours="${1:-24}"
    local output_file="${2:-/tmp/monitoring-report-$(date +%Y%m%d_%H%M%S).txt}"

    print_section "Generating Monitoring Report"

    {
        echo "VLESS VPN Monitoring Report"
        echo "Generated: $(date)"
        echo "Period: Last $hours hours"
        echo "=========================================="
        echo

        # Current system status
        echo "Current System Status:"
        echo "----------------------"
        if [[ -f "$METRICS_FILE" ]]; then
            cat "$METRICS_FILE" | jq -r '
                "CPU Usage: " + (.metrics.cpu_usage | tostring) + "%",
                "RAM Usage: " + (.metrics.ram_usage | tostring) + "%",
                "Disk Usage: " + (.metrics.disk_usage | tostring) + "%",
                "Load Average: " + (.metrics.load_average | tostring),
                "Response Time: " + (.metrics.response_time | tostring) + "ms",
                "Active Users: " + (.metrics.active_users | tostring),
                "Uptime: " + (.metrics.uptime | tonumber / 86400 | floor | tostring) + " days"
            ' 2>/dev/null || echo "Metrics data unavailable"
        else
            echo "No current metrics available"
        fi
        echo

        # Service status
        echo "Service Status:"
        echo "---------------"
        echo "VLESS VPN: $(get_service_status vless-vpn 2>/dev/null || echo 'unknown')"
        echo "Docker: $(get_service_status docker)"
        echo "Xray Container: $(get_docker_container_status xray 2>/dev/null || echo 'unknown')"
        echo "Telegram Bot: $(get_docker_container_status telegram-bot 2>/dev/null || echo 'unknown')"
        echo

        # Recent alerts
        echo "Recent Alerts:"
        echo "--------------"
        if [[ -f "$MONITORING_LOG" ]]; then
            grep "ALERT" "$MONITORING_LOG" | tail -10 | while IFS= read -r line; do
                echo "  $line"
            done
        else
            echo "  No recent alerts"
        fi
        echo

        # Historical data summary (if available)
        echo "Historical Summary (Last $hours hours):"
        echo "--------------------------------------"
        local history_file="$MONITORING_DATA_DIR/metrics_history.jsonl"
        if [[ -f "$history_file" ]]; then
            local cutoff_time=$(date -d "$hours hours ago" -u +"%Y-%m-%dT%H:%M:%SZ")

            # Calculate averages
            awk -v cutoff="$cutoff_time" '
                BEGIN { count=0; cpu_sum=0; ram_sum=0; load_sum=0 }
                /"timestamp":/ && $0 > cutoff {
                    if (match($0, /"cpu_usage":\s*([0-9.]+)/, cpu)) cpu_sum += cpu[1]
                    if (match($0, /"ram_usage":\s*([0-9.]+)/, ram)) ram_sum += ram[1]
                    if (match($0, /"load_average":\s*([0-9.]+)/, load)) load_sum += load[1]
                    count++
                }
                END {
                    if (count > 0) {
                        printf "Average CPU: %.1f%%\n", cpu_sum/count
                        printf "Average RAM: %.1f%%\n", ram_sum/count
                        printf "Average Load: %.2f\n", load_sum/count
                        printf "Data points: %d\n", count
                    } else {
                        print "No historical data available for the specified period"
                    }
                }
            ' "$history_file" 2>/dev/null || echo "Error processing historical data"
        else
            echo "No historical data available"
        fi

    } > "$output_file"

    echo "Report generated: $output_file"
}

# Show current monitoring status
show_monitoring_status() {
    print_header "VLESS Monitoring System Status"

    # Check if monitoring is configured
    printf "%-30s " "Monitoring configured:"
    if [[ -f "$THRESHOLDS_FILE" ]]; then
        echo -e "${GREEN}Yes${NC}"
    else
        echo -e "${RED}No${NC}"
    fi

    # Current metrics
    echo
    print_section "Current System Metrics"

    if [[ -f "$METRICS_FILE" ]]; then
        echo "Last updated: $(jq -r '.timestamp' "$METRICS_FILE" 2>/dev/null || echo 'Unknown')"
        echo
        printf "%-20s %s\n" "CPU Usage:" "$(jq -r '.metrics.cpu_usage' "$METRICS_FILE" 2>/dev/null || echo 'N/A')%"
        printf "%-20s %s\n" "RAM Usage:" "$(jq -r '.metrics.ram_usage' "$METRICS_FILE" 2>/dev/null || echo 'N/A')%"
        printf "%-20s %s\n" "Disk Usage:" "$(jq -r '.metrics.disk_usage' "$METRICS_FILE" 2>/dev/null || echo 'N/A')%"
        printf "%-20s %s\n" "Load Average:" "$(jq -r '.metrics.load_average' "$METRICS_FILE" 2>/dev/null || echo 'N/A')"
        printf "%-20s %s\n" "Response Time:" "$(jq -r '.metrics.response_time' "$METRICS_FILE" 2>/dev/null || echo 'N/A')ms"
        printf "%-20s %s\n" "Active Users:" "$(jq -r '.metrics.active_users' "$METRICS_FILE" 2>/dev/null || echo 'N/A')"
    else
        echo "No metrics data available - run monitoring check first"
    fi

    # Active alerts
    echo
    print_section "Active Alerts"
    local alert_files=($(find "$ALERT_STATE_DIR" -name "*" -type f 2>/dev/null || true))

    if [[ ${#alert_files[@]} -gt 0 ]]; then
        for alert_file in "${alert_files[@]}"; do
            local alert_name=$(basename "$alert_file")
            local alert_time=$(cat "$alert_file")
            local alert_age=$(($(date +%s) - alert_time))
            echo "  $alert_name (active for ${alert_age}s)"
        done
    else
        echo "  No active alerts"
    fi

    # Recent monitoring events
    echo
    print_section "Recent Monitoring Events"
    if [[ -f "$MONITORING_LOG" ]]; then
        echo "Last 5 events:"
        tail -n 5 "$MONITORING_LOG" | sed 's/^/  /'
    else
        echo "  No monitoring log found"
    fi
}

# Setup monitoring cron job
setup_monitoring_cron() {
    print_section "Setting up Monitoring Cron Job"

    # Create cron job
    cat > "/etc/cron.d/vless-monitoring" << 'EOF'
# VLESS Monitoring Cron Jobs
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin

# Run system health check every minute
* * * * * root /usr/local/bin/vless-monitoring check >/dev/null 2>&1

# Run service check every 2 minutes
*/2 * * * * root /usr/local/bin/vless-monitoring services >/dev/null 2>&1

# Generate daily report at 6 AM
0 6 * * * root /usr/local/bin/vless-monitoring report > /tmp/daily-monitoring-report.txt 2>&1

# Cleanup old alert states every hour
0 * * * * root find /tmp/vless-alerts -type f -mmin +60 -delete 2>/dev/null || true
EOF

    # Create monitoring script wrapper
    cat > "/usr/local/bin/vless-monitoring" << 'EOF'
#!/bin/bash
# VLESS Monitoring Script Wrapper

SCRIPT_DIR="/opt/vless/modules"
MONITORING_SCRIPT="$SCRIPT_DIR/monitoring.sh"

if [[ -f "$MONITORING_SCRIPT" ]]; then
    case "${1:-help}" in
        "check"|"health")
            bash "$MONITORING_SCRIPT" check_system_health
            ;;
        "services")
            bash "$MONITORING_SCRIPT" check_services
            ;;
        "status")
            bash "$MONITORING_SCRIPT" show_monitoring_status
            ;;
        "report")
            bash "$MONITORING_SCRIPT" generate_monitoring_report "${2:-24}" "${3:-}"
            ;;
        "init"|"setup")
            bash "$MONITORING_SCRIPT" setup_monitoring
            ;;
        *)
            echo "Usage: $0 {check|services|status|report|init}"
            echo "  check    - Check system health"
            echo "  services - Check service status"
            echo "  status   - Show monitoring status"
            echo "  report   - Generate monitoring report"
            echo "  init     - Initialize monitoring system"
            ;;
    esac
else
    echo "Monitoring script not found: $MONITORING_SCRIPT"
    exit 1
fi
EOF

    chmod +x "/usr/local/bin/vless-monitoring"

    print_success "Monitoring cron jobs and wrapper script created"
}

# Main setup function
setup_monitoring() {
    print_header "Setting up VLESS Monitoring System"

    init_monitoring
    setup_monitoring_cron

    # Install dependencies
    if ! command -v bc >/dev/null 2>&1; then
        print_info "Installing bc for calculations"
        apt update -qq && apt install -y bc
    fi

    if ! command -v jq >/dev/null 2>&1; then
        print_info "Installing jq for JSON processing"
        apt update -qq && apt install -y jq
    fi

    print_success "VLESS monitoring system setup completed"

    # Run initial check
    print_info "Running initial system check..."
    check_system_health
    check_services

    show_monitoring_status
}

# Remove monitoring system
remove_monitoring() {
    print_header "Removing VLESS Monitoring System"

    if ! prompt_yes_no "Are you sure you want to remove the monitoring system?" "n"; then
        print_info "Monitoring system removal cancelled"
        return 0
    fi

    # Remove cron jobs
    rm -f "/etc/cron.d/vless-monitoring"
    rm -f "/usr/local/bin/vless-monitoring"

    # Remove configuration and data
    rm -rf "$MONITORING_CONFIG_DIR"
    rm -rf "$MONITORING_DATA_DIR"
    rm -rf "$ALERT_STATE_DIR"

    print_success "VLESS monitoring system removed"
}

# Export functions
export -f setup_monitoring show_monitoring_status remove_monitoring
export -f check_system_health check_services generate_monitoring_report
export -f init_monitoring create_thresholds_config load_config
export -f log_monitoring send_alert clear_alert trigger_auto_recovery

# Main execution if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-setup}" in
        "setup"|"install"|"init")
            setup_monitoring
            ;;
        "check"|"health")
            load_config
            check_system_health
            ;;
        "services")
            check_services
            ;;
        "status"|"show")
            show_monitoring_status
            ;;
        "report")
            generate_monitoring_report "${2:-24}" "${3:-}"
            ;;
        "remove"|"uninstall")
            remove_monitoring
            ;;
        *)
            echo "Usage: $0 {setup|check|services|status|report|remove}"
            echo "  setup    - Setup monitoring system"
            echo "  check    - Check system health"
            echo "  services - Check service status"
            echo "  status   - Show monitoring status"
            echo "  report   - Generate monitoring report"
            echo "  remove   - Remove monitoring system"
            exit 1
            ;;
    esac
fi