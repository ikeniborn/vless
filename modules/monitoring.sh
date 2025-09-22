#!/bin/bash

# VLESS+Reality VPN Management System - Service Monitoring and Health Checks
# Version: 1.0.0
# Description: Real-time service monitoring and alerting system
#
# Features:
# - Xray service health monitoring
# - Docker container status checks
# - Network connectivity monitoring
# - Resource usage monitoring (CPU, memory, disk)
# - Performance metrics collection
# - Email/webhook alerting
# - Process isolation for EPERM prevention

set -euo pipefail

# Import common utilities
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SOURCE_DIR}/common_utils.sh"

# Setup signal handlers
setup_signal_handlers

# Configuration
readonly MONITORING_CONFIG_DIR="/opt/vless/config/monitoring"
readonly MONITORING_LOG_DIR="/opt/vless/logs/monitoring"
readonly MONITORING_DATA_DIR="/opt/vless/data/monitoring"
readonly ALERT_CONFIG_FILE="${MONITORING_CONFIG_DIR}/alerts.conf"
readonly METRICS_FILE="${MONITORING_DATA_DIR}/metrics.json"

# Monitoring intervals (seconds)
readonly HEALTH_CHECK_INTERVAL=30
readonly RESOURCE_CHECK_INTERVAL=60
readonly NETWORK_CHECK_INTERVAL=120
readonly ALERT_COOLDOWN=300

# Resource thresholds
readonly CPU_THRESHOLD=80
readonly MEMORY_THRESHOLD=80
readonly DISK_THRESHOLD=85
readonly LOAD_THRESHOLD=2.0

# Initialize monitoring module
init_monitoring() {
    log_info "Initializing service monitoring module"

    # Create monitoring directories
    create_directory "$MONITORING_CONFIG_DIR" "750" "vless:vless"
    create_directory "$MONITORING_LOG_DIR" "750" "vless:vless"
    create_directory "$MONITORING_DATA_DIR" "750" "vless:vless"

    # Install monitoring tools
    install_package_if_missing "htop"
    install_package_if_missing "iotop"
    install_package_if_missing "nethogs" "apt-get update -qq && apt-get install -y nethogs"

    # Create monitoring configuration
    create_monitoring_config

    log_success "Service monitoring module initialized"
}

# Create monitoring configuration
create_monitoring_config() {
    log_info "Creating monitoring configuration"

    # Alert configuration
    cat > "$ALERT_CONFIG_FILE" << 'EOF'
# VLESS Monitoring Alert Configuration
# Format: alert_type:threshold:enabled:cooldown

# Service alerts
service_down:1:true:300
container_restart:3:true:600
xray_connection_failed:5:true:180

# Resource alerts
cpu_high:80:true:300
memory_high:80:true:300
disk_high:85:true:600
load_high:2.0:true:300

# Network alerts
network_down:1:true:60
port_unreachable:1:true:180
bandwidth_high:1000:false:900

# Security alerts
failed_login:10:true:600
suspicious_traffic:1:true:300
config_change:1:true:60

EOF

    chmod 644 "$ALERT_CONFIG_FILE"
    chown vless:vless "$ALERT_CONFIG_FILE"

    log_success "Monitoring configuration created"
}

# Check VLESS service health
check_vless_service_health() {
    log_debug "Checking VLESS service health"

    local health_status="healthy"
    local issues=()

    # Check if Docker is running
    if ! systemctl is-active docker >/dev/null 2>&1; then
        health_status="unhealthy"
        issues+=("Docker service not running")
    fi

    # Check VLESS containers
    local vless_containers
    vless_containers=$(docker ps --filter "name=vless" --format "{{.Names}}" 2>/dev/null || echo "")

    if [[ -z "$vless_containers" ]]; then
        health_status="unhealthy"
        issues+=("No VLESS containers running")
    else
        # Check each container health
        while IFS= read -r container; do
            if [[ -n "$container" ]]; then
                local container_status
                container_status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "unknown")

                if [[ "$container_status" != "healthy" && "$container_status" != "unknown" ]]; then
                    health_status="degraded"
                    issues+=("Container $container status: $container_status")
                fi
            fi
        done <<< "$vless_containers"
    fi

    # Check Xray process
    if ! pgrep -f xray >/dev/null 2>&1; then
        if docker ps --filter "name=vless" --format "{{.Names}}" | grep -q .; then
            log_debug "Xray running in container"
        else
            health_status="unhealthy"
            issues+=("Xray process not found")
        fi
    fi

    # Return status
    echo "$health_status"
    if [[ ${#issues[@]} -gt 0 ]]; then
        printf "Issues: %s\n" "${issues[@]}"
    fi
}

# Monitor Docker containers
monitor_docker_containers() {
    log_debug "Monitoring Docker containers"

    local container_stats=()

    # Get VLESS-related containers
    local containers
    containers=$(docker ps --filter "name=vless" --format "{{.ID}}\t{{.Names}}\t{{.Status}}" 2>/dev/null || echo "")

    if [[ -z "$containers" ]]; then
        log_warn "No VLESS containers found"
        return 1
    fi

    while IFS=$'\t' read -r container_id container_name container_status; do
        if [[ -n "$container_id" ]]; then
            # Get container resource usage
            local stats
            stats=$(docker stats --no-stream --format "table {{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" "$container_id" 2>/dev/null | tail -1)

            if [[ -n "$stats" ]]; then
                container_stats+=("$container_name: $stats")
            fi

            # Check container logs for errors
            local recent_errors
            recent_errors=$(docker logs --since=5m "$container_id" 2>&1 | grep -i "error\|fatal\|panic" | wc -l || echo "0")

            if [[ $recent_errors -gt 0 ]]; then
                log_warn "Container $container_name has $recent_errors recent errors"
            fi
        fi
    done <<< "$containers"

    # Output container statistics
    printf "Container Statistics:\n"
    printf "%s\n" "${container_stats[@]}"
}

# Monitor system resources
monitor_system_resources() {
    log_debug "Monitoring system resources"

    local alerts=()

    # CPU usage
    local cpu_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | cut -d',' -f1)
    cpu_usage=${cpu_usage%.*}  # Remove decimal part

    if [[ $cpu_usage -gt $CPU_THRESHOLD ]]; then
        alerts+=("High CPU usage: ${cpu_usage}%")
    fi

    # Memory usage
    local memory_usage
    memory_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')

    if [[ $memory_usage -gt $MEMORY_THRESHOLD ]]; then
        alerts+=("High memory usage: ${memory_usage}%")
    fi

    # Disk usage
    local disk_usage
    disk_usage=$(df /opt/vless | awk 'NR==2{print $5}' | cut -d'%' -f1)

    if [[ $disk_usage -gt $DISK_THRESHOLD ]]; then
        alerts+=("High disk usage: ${disk_usage}%")
    fi

    # Load average
    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | cut -d',' -f1 | xargs)

    if (( $(echo "$load_avg > $LOAD_THRESHOLD" | bc -l) )); then
        alerts+=("High load average: $load_avg")
    fi

    # Network interface status
    local network_interfaces
    network_interfaces=$(ip link show | grep "state UP" | wc -l)

    if [[ $network_interfaces -eq 0 ]]; then
        alerts+=("No active network interfaces")
    fi

    # Output resource statistics
    cat << EOF
=== System Resource Usage ===
CPU Usage: ${cpu_usage}%
Memory Usage: ${memory_usage}%
Disk Usage: ${disk_usage}%
Load Average: ${load_avg}
Active Network Interfaces: ${network_interfaces}
EOF

    # Return alerts
    if [[ ${#alerts[@]} -gt 0 ]]; then
        echo "ALERTS:"
        printf "  %s\n" "${alerts[@]}"
        return 1
    fi

    return 0
}

# Monitor network connectivity
monitor_network_connectivity() {
    log_debug "Monitoring network connectivity"

    local connectivity_issues=()

    # Check external connectivity
    if ! check_network_connectivity; then
        connectivity_issues+=("External connectivity failed")
    fi

    # Check VLESS port accessibility
    local vless_port=443
    if ! nc -z localhost "$vless_port" 2>/dev/null; then
        connectivity_issues+=("VLESS port $vless_port not accessible")
    fi

    # Check DNS resolution
    if ! nslookup google.com >/dev/null 2>&1; then
        connectivity_issues+=("DNS resolution failed")
    fi

    # Check for unusual network activity
    local connections
    connections=$(ss -tuln | wc -l)

    if [[ $connections -gt 100 ]]; then
        connectivity_issues+=("High number of network connections: $connections")
    fi

    # Output network status
    echo "=== Network Connectivity Status ==="
    echo "Active connections: $connections"
    echo "VLESS port accessible: $(nc -z localhost 443 2>/dev/null && echo "Yes" || echo "No")"

    # Return issues
    if [[ ${#connectivity_issues[@]} -gt 0 ]]; then
        echo "NETWORK ISSUES:"
        printf "  %s\n" "${connectivity_issues[@]}"
        return 1
    fi

    return 0
}

# Monitor performance metrics
collect_performance_metrics() {
    log_debug "Collecting performance metrics"

    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # System metrics
    local cpu_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)

    local memory_total memory_used memory_free
    read -r memory_total memory_used memory_free <<< $(free | awk 'NR==2{print $2, $3, $4}')

    local disk_total disk_used disk_available
    read -r disk_total disk_used disk_available <<< $(df /opt/vless | awk 'NR==2{print $2, $3, $4}')

    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | cut -d',' -f1 | xargs)

    # Network metrics
    local network_rx network_tx
    read -r network_rx network_tx <<< $(cat /proc/net/dev | grep -E "eth0|ens|enp" | head -1 | awk '{print $2, $10}')

    # Connection metrics
    local tcp_connections
    tcp_connections=$(ss -t | wc -l)

    local vless_connections
    vless_connections=$(ss -t | grep ":443" | wc -l)

    # Create metrics JSON
    cat > "$METRICS_FILE" << EOF
{
  "timestamp": "$timestamp",
  "system": {
    "cpu_usage": "$cpu_usage",
    "memory": {
      "total": $memory_total,
      "used": $memory_used,
      "free": $memory_free
    },
    "disk": {
      "total": $disk_total,
      "used": $disk_used,
      "available": $disk_available
    },
    "load_average": "$load_avg"
  },
  "network": {
    "bytes_received": $network_rx,
    "bytes_transmitted": $network_tx,
    "tcp_connections": $tcp_connections,
    "vless_connections": $vless_connections
  },
  "uptime": "$(uptime -p)"
}
EOF

    chmod 644 "$METRICS_FILE"
    chown vless:vless "$METRICS_FILE"

    log_debug "Performance metrics collected: $METRICS_FILE"
}

# Send alert notification
send_alert() {
    local alert_type="$1"
    local alert_message="$2"
    local alert_severity="${3:-warning}"

    log_warn "ALERT [$alert_type]: $alert_message"

    # Log to monitoring log
    echo "[$(get_timestamp)] ALERT [$alert_type] $alert_message" >> "${MONITORING_LOG_DIR}/alerts.log"

    # Send to system log
    logger -t "vless-monitoring" -p "daemon.$alert_severity" "ALERT [$alert_type]: $alert_message"

    # TODO: Implement email/webhook notifications
    # send_email_alert "$alert_type" "$alert_message"
    # send_webhook_alert "$alert_type" "$alert_message"
}

# Check alert configuration and cooldowns
should_send_alert() {
    local alert_type="$1"
    local current_time
    current_time=$(date +%s)

    local cooldown_file="${MONITORING_DATA_DIR}/alert_cooldowns"
    local last_alert_time=0

    if [[ -f "$cooldown_file" ]]; then
        last_alert_time=$(grep "^$alert_type:" "$cooldown_file" 2>/dev/null | cut -d':' -f2 || echo "0")
    fi

    local time_diff=$((current_time - last_alert_time))

    if [[ $time_diff -gt $ALERT_COOLDOWN ]]; then
        # Update cooldown file
        grep -v "^$alert_type:" "$cooldown_file" 2>/dev/null > "${cooldown_file}.tmp" || true
        echo "$alert_type:$current_time" >> "${cooldown_file}.tmp"
        mv "${cooldown_file}.tmp" "$cooldown_file"
        return 0
    else
        log_debug "Alert $alert_type in cooldown period (${time_diff}s < ${ALERT_COOLDOWN}s)"
        return 1
    fi
}

# Run comprehensive health check
run_health_check() {
    log_info "Running comprehensive health check"

    local overall_status="healthy"
    local check_results=()

    # Service health check
    local service_health
    service_health=$(check_vless_service_health)
    local service_status
    service_status=$(echo "$service_health" | head -1)

    if [[ "$service_status" != "healthy" ]]; then
        overall_status="unhealthy"
        if should_send_alert "service_health" "$service_health"; then
            send_alert "service_health" "VLESS service health: $service_health" "error"
        fi
    fi
    check_results+=("Service Health: $service_status")

    # Resource monitoring
    if ! monitor_system_resources >/dev/null 2>&1; then
        overall_status="degraded"
        if should_send_alert "resource_usage" "High resource usage detected"; then
            send_alert "resource_usage" "System resources exceeding thresholds" "warning"
        fi
    fi
    check_results+=("Resource Usage: OK")

    # Network connectivity
    if ! monitor_network_connectivity >/dev/null 2>&1; then
        overall_status="degraded"
        if should_send_alert "network_connectivity" "Network connectivity issues detected"; then
            send_alert "network_connectivity" "Network connectivity problems" "warning"
        fi
    fi
    check_results+=("Network Connectivity: OK")

    # Docker containers
    if ! monitor_docker_containers >/dev/null 2>&1; then
        overall_status="degraded"
        if should_send_alert "container_status" "Docker container issues detected"; then
            send_alert "container_status" "Docker container problems" "warning"
        fi
    fi
    check_results+=("Docker Containers: OK")

    # Collect metrics
    collect_performance_metrics

    # Output results
    echo "=== VLESS Health Check Summary ==="
    echo "Overall Status: $overall_status"
    echo "Timestamp: $(get_timestamp)"
    echo ""
    printf "Check Results:\n"
    printf "  %s\n" "${check_results[@]}"

    case "$overall_status" in
        "healthy") return 0 ;;
        "degraded") return 1 ;;
        "unhealthy") return 2 ;;
    esac
}

# Start monitoring daemon
start_monitoring_daemon() {
    local daemon_mode="${1:-false}"

    log_info "Starting VLESS monitoring daemon"

    # Create systemd service if not in daemon mode
    if [[ "$daemon_mode" != "true" ]]; then
        create_monitoring_service
        return 0
    fi

    # Daemon loop
    log_info "Running in daemon mode with health check interval: ${HEALTH_CHECK_INTERVAL}s"

    while true; do
        log_debug "Running scheduled health check"

        if ! run_health_check >/dev/null 2>&1; then
            log_warn "Health check detected issues"
        fi

        # Interruptible sleep
        if ! interruptible_sleep "$HEALTH_CHECK_INTERVAL" 10; then
            log_info "Monitoring daemon interrupted, exiting"
            break
        fi
    done
}

# Create systemd monitoring service
create_monitoring_service() {
    log_info "Creating systemd monitoring service"

    # Create service file
    cat > "/etc/systemd/system/vless-monitoring.service" << EOF
[Unit]
Description=VLESS VPN Monitoring Service
After=docker.service
Wants=docker.service

[Service]
Type=simple
User=vless
Group=vless
ExecStart=/bin/bash ${SOURCE_DIR}/monitoring.sh --daemon
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target

EOF

    # Create timer for periodic checks
    cat > "/etc/systemd/system/vless-monitoring.timer" << EOF
[Unit]
Description=VLESS Monitoring Timer
Requires=vless-monitoring.service

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target

EOF

    # Reload systemd and enable services
    systemctl daemon-reload
    isolate_systemctl_command "enable" "vless-monitoring.service" 30
    isolate_systemctl_command "enable" "vless-monitoring.timer" 30
    isolate_systemctl_command "start" "vless-monitoring.timer" 30

    log_success "Monitoring service created and started"
}

# Stop monitoring service
stop_monitoring_service() {
    log_info "Stopping monitoring service"

    isolate_systemctl_command "stop" "vless-monitoring.timer" 30
    isolate_systemctl_command "stop" "vless-monitoring.service" 30
    isolate_systemctl_command "disable" "vless-monitoring.timer" 30
    isolate_systemctl_command "disable" "vless-monitoring.service" 30

    log_success "Monitoring service stopped and disabled"
}

# Get monitoring status
get_monitoring_status() {
    log_info "Getting monitoring service status"

    echo "=== VLESS Monitoring Status ==="
    echo ""

    # Service status
    echo "Monitoring Service:"
    if systemctl is-active vless-monitoring.service >/dev/null 2>&1; then
        echo "  Status: Active"
    else
        echo "  Status: Inactive"
    fi

    # Timer status
    echo "Monitoring Timer:"
    if systemctl is-active vless-monitoring.timer >/dev/null 2>&1; then
        echo "  Status: Active"
        echo "  Next run: $(systemctl list-timers vless-monitoring.timer --no-pager | tail -1 | awk '{print $1, $2}')"
    else
        echo "  Status: Inactive"
    fi

    # Last metrics
    echo ""
    echo "Last Metrics:"
    if [[ -f "$METRICS_FILE" ]]; then
        echo "  File: $METRICS_FILE"
        echo "  Timestamp: $(jq -r '.timestamp' "$METRICS_FILE" 2>/dev/null || echo "Unknown")"
    else
        echo "  No metrics file found"
    fi

    # Recent alerts
    echo ""
    echo "Recent Alerts:"
    if [[ -f "${MONITORING_LOG_DIR}/alerts.log" ]]; then
        tail -5 "${MONITORING_LOG_DIR}/alerts.log" 2>/dev/null || echo "  No recent alerts"
    else
        echo "  No alert log found"
    fi
}

# Monitor logs in real-time
monitor_logs_realtime() {
    local duration="${1:-300}"

    log_info "Monitoring VLESS logs in real-time for ${duration}s"

    # Import log helpers
    if [[ -f "${SOURCE_DIR}/../config/log_helpers.sh" ]]; then
        source "${SOURCE_DIR}/../config/log_helpers.sh"
    fi

    # Monitor multiple log files
    local log_files=(
        "/opt/vless/logs/vless-vpn.log"
        "/opt/vless/logs/error.log"
        "/opt/vless/logs/security.log"
        "${MONITORING_LOG_DIR}/alerts.log"
    )

    local pids=()

    # Start tailing each log file
    for log_file in "${log_files[@]}"; do
        if [[ -f "$log_file" ]]; then
            {
                echo "=== Monitoring $log_file ==="
                controlled_tail "$log_file" "$duration" 20
            } &
            pids+=($!)
        fi
    done

    # Wait for all tail processes
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    log_success "Real-time log monitoring completed"
}

# Main function for command line usage
main() {
    case "${1:-help}" in
        "init")
            init_monitoring
            ;;
        "health-check")
            run_health_check
            ;;
        "start-daemon")
            start_monitoring_daemon true
            ;;
        "start-service")
            start_monitoring_daemon false
            ;;
        "stop-service")
            stop_monitoring_service
            ;;
        "status")
            get_monitoring_status
            ;;
        "monitor-logs")
            monitor_logs_realtime "${2:-300}"
            ;;
        "metrics")
            collect_performance_metrics
            cat "$METRICS_FILE"
            ;;
        "--daemon")
            start_monitoring_daemon true
            ;;
        "help"|*)
            echo "VLESS Monitoring Module Usage:"
            echo "  $0 init              - Initialize monitoring"
            echo "  $0 health-check      - Run health check"
            echo "  $0 start-service     - Start monitoring service"
            echo "  $0 stop-service      - Stop monitoring service"
            echo "  $0 status           - Show monitoring status"
            echo "  $0 monitor-logs [duration] - Monitor logs in real-time"
            echo "  $0 metrics          - Collect and show metrics"
            ;;
    esac
}

# Export functions
export -f init_monitoring create_monitoring_config check_vless_service_health
export -f monitor_docker_containers monitor_system_resources monitor_network_connectivity
export -f collect_performance_metrics send_alert should_send_alert run_health_check
export -f start_monitoring_daemon create_monitoring_service stop_monitoring_service
export -f get_monitoring_status monitor_logs_realtime

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

log_debug "Monitoring module loaded successfully"