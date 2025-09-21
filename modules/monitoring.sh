#!/bin/bash

# System Monitoring Module for VLESS+Reality VPN
# This module provides comprehensive monitoring of system resources,
# VPN connections, and security events with alerting capabilities
# Version: 1.0

set -euo pipefail

# Import common utilities and process isolation
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_utils.sh" 2>/dev/null || {
    echo "Error: Cannot find common_utils.sh"
    exit 1
}

# Import process isolation module
source "${SCRIPT_DIR}/process_isolation/process_safe.sh" 2>/dev/null || {
    log_warn "Process isolation module not found, using standard execution"
}

# Setup signal handlers if process isolation is available
if command -v setup_signal_handlers >/dev/null 2>&1; then
    setup_signal_handlers
fi

# Configuration
readonly MONITORING_DIR="/opt/vless/monitoring"
readonly MONITORING_LOG="/opt/vless/logs/monitoring.log"
readonly ALERTS_LOG="/opt/vless/logs/alerts.log"
readonly METRICS_DIR="${MONITORING_DIR}/metrics"
readonly REPORTS_DIR="${MONITORING_DIR}/reports"

# Thresholds for alerting
readonly CPU_THRESHOLD=80
readonly MEMORY_THRESHOLD=85
readonly DISK_THRESHOLD=90
readonly LOAD_THRESHOLD=2.0
readonly CONNECTION_THRESHOLD=100

# Create monitoring directories
create_monitoring_dirs() {
    log_info "Creating monitoring directories"

    mkdir -p "${MONITORING_DIR}"
    mkdir -p "${METRICS_DIR}"
    mkdir -p "${REPORTS_DIR}"
    mkdir -p "$(dirname "${MONITORING_LOG}")"
    mkdir -p "$(dirname "${ALERTS_LOG}")"

    chmod 700 "${MONITORING_DIR}"
    chmod 700 "${METRICS_DIR}"
    chmod 700 "${REPORTS_DIR}"

    log_info "Monitoring directories created"
}

# Log monitoring events
log_monitoring() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${MONITORING_LOG}"
}

# Log alerts
log_alert() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" >> "${ALERTS_LOG}"
    log_monitoring "ALERT [$level]: $*"
}

# Get system information
get_system_info() {
    echo "System Information:"
    echo "=================="
    echo "Hostname: $(hostname)"
    echo "Uptime: $(uptime -p 2>/dev/null || uptime | awk '{print $3,$4}')"
    echo "Kernel: $(uname -r)"
    echo "OS: $(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo "Architecture: $(uname -m)"
    echo ""
}

# Monitor CPU usage
monitor_cpu() {
    local cpu_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' | cut -d'%' -f1)

    # If top format is different, try alternative method
    if [[ -z "$cpu_usage" ]] || ! [[ "$cpu_usage" =~ ^[0-9.]+$ ]]; then
        cpu_usage=$(awk '{u=$2+$4; t=$2+$4+$5; if (NR==1){u1=u; t1=t;} else print ($2+$4-u1) * 100 / (t-t1) "%"; }' \
                   <(grep 'cpu ' /proc/stat; sleep 1; grep 'cpu ' /proc/stat) 2>/dev/null | sed 's/%//' || echo "0")
    fi

    # Extract numeric value
    cpu_usage=$(echo "$cpu_usage" | grep -o '[0-9.]*' | head -1)
    cpu_usage=${cpu_usage:-0}

    echo "CPU Usage: ${cpu_usage}%"

    # Check threshold
    if (( $(echo "$cpu_usage > $CPU_THRESHOLD" | bc -l 2>/dev/null || echo "0") )); then
        log_alert "WARNING" "High CPU usage detected: ${cpu_usage}%"
    fi

    # Log metric
    echo "$(date '+%Y-%m-%d %H:%M:%S'),cpu,$cpu_usage" >> "${METRICS_DIR}/cpu.csv"
}

# Monitor memory usage
monitor_memory() {
    local memory_info
    memory_info=$(free -m)

    local total_mem used_mem available_mem memory_usage
    total_mem=$(echo "$memory_info" | awk '/^Mem:/ {print $2}')
    used_mem=$(echo "$memory_info" | awk '/^Mem:/ {print $3}')
    available_mem=$(echo "$memory_info" | awk '/^Mem:/ {print $7}')

    # Calculate memory usage percentage
    if [[ $total_mem -gt 0 ]]; then
        memory_usage=$(( (used_mem * 100) / total_mem ))
    else
        memory_usage=0
    fi

    echo "Memory Usage: ${memory_usage}% (${used_mem}MB used / ${total_mem}MB total)"
    echo "Memory Available: ${available_mem}MB"

    # Check threshold
    if [[ $memory_usage -gt $MEMORY_THRESHOLD ]]; then
        log_alert "WARNING" "High memory usage detected: ${memory_usage}%"
    fi

    # Log metric
    echo "$(date '+%Y-%m-%d %H:%M:%S'),memory,$memory_usage" >> "${METRICS_DIR}/memory.csv"
}

# Monitor disk usage
monitor_disk() {
    echo "Disk Usage:"
    echo "==========="

    df -h | grep -vE '^tmpfs|^udev|^Filesystem' | while read -r filesystem size used avail percent mountpoint; do
        echo "  $mountpoint: $used used / $size total ($percent)"

        # Extract percentage number
        local usage_percent
        usage_percent=$(echo "$percent" | sed 's/%//')

        # Check threshold
        if [[ $usage_percent -gt $DISK_THRESHOLD ]]; then
            log_alert "WARNING" "High disk usage on $mountpoint: $percent"
        fi

        # Log metric for root filesystem
        if [[ "$mountpoint" == "/" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S'),disk,$usage_percent" >> "${METRICS_DIR}/disk.csv"
        fi
    done
}

# Monitor system load
monitor_load() {
    local load_avg
    load_avg=$(uptime | awk '{print $(NF-2)}' | sed 's/,//')

    echo "Load Average: $load_avg"

    # Check threshold (compare with bc if available)
    if command -v bc >/dev/null 2>&1; then
        if (( $(echo "$load_avg > $LOAD_THRESHOLD" | bc -l) )); then
            log_alert "WARNING" "High system load detected: $load_avg"
        fi
    else
        # Fallback comparison for systems without bc
        if (( $(echo "$load_avg" | cut -d'.' -f1) >= ${LOAD_THRESHOLD%.*} )); then
            log_alert "WARNING" "High system load detected: $load_avg"
        fi
    fi

    # Log metric
    echo "$(date '+%Y-%m-%d %H:%M:%S'),load,$load_avg" >> "${METRICS_DIR}/load.csv"
}

# Monitor network interfaces
monitor_network() {
    echo "Network Interfaces:"
    echo "=================="

    ip -s link show | awk '
    /^[0-9]+: / {
        interface = $2
        gsub(/:/, "", interface)
    }
    /RX:.*bytes/ {
        rx_bytes = $2
        rx_packets = $3
    }
    /TX:.*bytes/ {
        tx_bytes = $2
        tx_packets = $3
        if (interface != "lo") {
            printf "  %s: RX: %s bytes (%s packets), TX: %s bytes (%s packets)\n",
                   interface, rx_bytes, rx_packets, tx_bytes, tx_packets
        }
    }'

    # Monitor active connections
    local connection_count
    connection_count=$(ss -tuln | grep -c "LISTEN" 2>/dev/null || echo "0")
    echo "  Active listening ports: $connection_count"

    # Check connection threshold
    if [[ $connection_count -gt $CONNECTION_THRESHOLD ]]; then
        log_alert "WARNING" "High number of listening connections: $connection_count"
    fi

    # Log metric
    echo "$(date '+%Y-%m-%d %H:%M:%S'),connections,$connection_count" >> "${METRICS_DIR}/connections.csv"
}

# Monitor VPN-specific metrics
monitor_vpn_connections() {
    echo "VPN Connection Monitoring:"
    echo "========================="

    # Check if Xray container is running
    if command -v docker >/dev/null 2>&1; then
        local xray_status
        xray_status=$(docker ps --filter "name=xray" --format "table {{.Names}}\t{{.Status}}" 2>/dev/null || echo "Docker not available")

        if [[ "$xray_status" != "Docker not available" ]] && [[ -n "$xray_status" ]]; then
            echo "  Xray Container Status:"
            echo "    $xray_status"

            # Check if container is running
            if echo "$xray_status" | grep -q "Up"; then
                log_monitoring "Xray container is running"

                # Get container resource usage
                local container_stats
                container_stats=$(docker stats --no-stream --format "table {{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null | tail -1)
                if [[ -n "$container_stats" ]]; then
                    echo "    Resource Usage: $container_stats"
                fi
            else
                log_alert "CRITICAL" "Xray container is not running"
            fi
        else
            echo "  No Xray container found"
        fi
    else
        echo "  Docker not available"
    fi

    # Monitor Reality/VLESS connections (port 443)
    local reality_connections
    reality_connections=$(ss -tuln | grep ":443" | wc -l 2>/dev/null || echo "0")
    echo "  Reality port (443) listeners: $reality_connections"

    # Check for established connections on VPN ports
    local established_conns
    established_conns=$(ss -tn | grep ":443" | grep "ESTAB" | wc -l 2>/dev/null || echo "0")
    echo "  Established VPN connections: $established_conns"

    # Log VPN metrics
    echo "$(date '+%Y-%m-%d %H:%M:%S'),vpn_connections,$established_conns" >> "${METRICS_DIR}/vpn.csv"
}

# Monitor security events
monitor_security() {
    echo "Security Monitoring:"
    echo "=================="

    # Check for failed login attempts
    local failed_logins
    failed_logins=$(grep "Failed password" /var/log/auth.log 2>/dev/null | tail -10 | wc -l || echo "0")
    echo "  Recent failed logins (last 10): $failed_logins"

    if [[ $failed_logins -gt 5 ]]; then
        log_alert "WARNING" "Multiple failed login attempts detected: $failed_logins"
    fi

    # Check UFW blocks
    if [[ -f /var/log/ufw.log ]]; then
        local ufw_blocks
        ufw_blocks=$(grep "$(date '+%b %d')" /var/log/ufw.log 2>/dev/null | grep "BLOCK" | wc -l || echo "0")
        echo "  UFW blocks today: $ufw_blocks"

        if [[ $ufw_blocks -gt 50 ]]; then
            log_alert "INFO" "High number of UFW blocks today: $ufw_blocks"
        fi
    fi

    # Check fail2ban status
    if command -v fail2ban-client >/dev/null 2>&1; then
        local fail2ban_status
        fail2ban_status=$(fail2ban-client status 2>/dev/null | grep "Number of jail" || echo "fail2ban not responding")
        echo "  Fail2ban: $fail2ban_status"
    fi
}

# Monitor system processes
monitor_processes() {
    echo "Process Monitoring:"
    echo "=================="

    # Top CPU consuming processes
    echo "  Top CPU processes:"
    ps aux --sort=-%cpu | head -6 | tail -5 | awk '{printf "    %s: %s%% CPU\n", $11, $3}'

    # Top memory consuming processes
    echo "  Top memory processes:"
    ps aux --sort=-%mem | head -6 | tail -5 | awk '{printf "    %s: %s%% Memory\n", $11, $4}'

    # Check for zombie processes
    local zombie_count
    zombie_count=$(ps aux | awk '$8 ~ /^Z/ {count++} END {print count+0}')
    if [[ $zombie_count -gt 0 ]]; then
        log_alert "WARNING" "Zombie processes detected: $zombie_count"
        echo "  Zombie processes: $zombie_count"
    fi
}

# Generate system status report
generate_status_report() {
    local report_file="${REPORTS_DIR}/status_report_$(date +%Y%m%d_%H%M%S).txt"

    log_info "Generating system status report: $report_file"

    {
        echo "VLESS VPN System Status Report"
        echo "=============================="
        echo "Generated: $(date)"
        echo ""

        get_system_info
        monitor_cpu
        echo ""
        monitor_memory
        echo ""
        monitor_disk
        echo ""
        monitor_load
        echo ""
        monitor_network
        echo ""
        monitor_vpn_connections
        echo ""
        monitor_security
        echo ""
        monitor_processes

    } > "$report_file"

    log_monitoring "Status report generated: $report_file"
    echo "Report saved to: $report_file"

    # Cleanup old reports (keep last 30)
    find "$REPORTS_DIR" -name "status_report_*.txt" -type f | \
        sort -r | tail -n +31 | xargs rm -f 2>/dev/null || true
}

# Display current system status
show_system_status() {
    log_info "Current System Status"
    log_info "===================="

    get_system_info
    monitor_cpu
    echo ""
    monitor_memory
    echo ""
    monitor_disk
    echo ""
    monitor_load
    echo ""
    monitor_network
    echo ""
    monitor_vpn_connections
    echo ""
    monitor_security
    echo ""
    monitor_processes
}

# Setup monitoring alerts
setup_monitoring_alerts() {
    log_info "Setting up monitoring alerts"

    # Create monitoring script
    cat > /usr/local/bin/vless-monitor << 'EOF'
#!/bin/bash
# VLESS VPN Monitoring Script

MONITORING_LOG="/opt/vless/logs/monitoring.log"
ALERTS_LOG="/opt/vless/logs/alerts.log"
METRICS_DIR="/opt/vless/monitoring/metrics"

# Ensure directories exist
mkdir -p "$(dirname "$MONITORING_LOG")"
mkdir -p "$METRICS_DIR"

# Import monitoring functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "/home/ikeniborn/Documents/Project/vless/modules/monitoring.sh" ]]; then
    source "/home/ikeniborn/Documents/Project/vless/modules/monitoring.sh"
elif [[ -f "/opt/vless/modules/monitoring.sh" ]]; then
    source "/opt/vless/modules/monitoring.sh"
else
    echo "Monitoring module not found"
    exit 1
fi

# Run monitoring checks
log_monitoring "Starting monitoring cycle"

monitor_cpu >/dev/null
monitor_memory >/dev/null
monitor_disk >/dev/null
monitor_load >/dev/null
monitor_network >/dev/null
monitor_vpn_connections >/dev/null
monitor_security >/dev/null

log_monitoring "Monitoring cycle completed"
EOF

    chmod +x /usr/local/bin/vless-monitor

    # Create cron job for regular monitoring
    cat > /etc/cron.d/vless-monitoring << 'EOF'
# VLESS VPN System Monitoring
*/5 * * * * root /usr/local/bin/vless-monitor
0 6 * * * root /home/ikeniborn/Documents/Project/vless/modules/monitoring.sh report
EOF

    log_info "Monitoring alerts configured"
    log_info "Monitoring runs every 5 minutes"
    log_info "Daily reports generated at 6:00 AM"
}

# View recent alerts
show_recent_alerts() {
    local count="${1:-20}"

    log_info "Recent Alerts (last $count):"
    log_info "============================"

    if [[ -f "$ALERTS_LOG" ]]; then
        tail -n "$count" "$ALERTS_LOG"
    else
        log_info "No alerts found"
    fi
}

# View monitoring metrics
show_metrics() {
    local metric="${1:-all}"
    local hours="${2:-24}"

    log_info "Monitoring Metrics (last $hours hours):"
    log_info "======================================"

    case "$metric" in
        "cpu"|"all")
            if [[ -f "${METRICS_DIR}/cpu.csv" ]]; then
                echo "CPU Usage:"
                tail -n $((hours * 12)) "${METRICS_DIR}/cpu.csv" 2>/dev/null | \
                    awk -F',' '{sum+=$3; count++} END {if(count>0) printf "  Average: %.1f%%\n", sum/count}'
            fi
            ;;
    esac

    case "$metric" in
        "memory"|"all")
            if [[ -f "${METRICS_DIR}/memory.csv" ]]; then
                echo "Memory Usage:"
                tail -n $((hours * 12)) "${METRICS_DIR}/memory.csv" 2>/dev/null | \
                    awk -F',' '{sum+=$3; count++} END {if(count>0) printf "  Average: %.1f%%\n", sum/count}'
            fi
            ;;
    esac

    case "$metric" in
        "disk"|"all")
            if [[ -f "${METRICS_DIR}/disk.csv" ]]; then
                echo "Disk Usage:"
                tail -n $((hours * 12)) "${METRICS_DIR}/disk.csv" 2>/dev/null | \
                    awk -F',' '{sum+=$3; count++} END {if(count>0) printf "  Average: %.1f%%\n", sum/count}'
            fi
            ;;
    esac

    case "$metric" in
        "vpn"|"all")
            if [[ -f "${METRICS_DIR}/vpn.csv" ]]; then
                echo "VPN Connections:"
                tail -n $((hours * 12)) "${METRICS_DIR}/vpn.csv" 2>/dev/null | \
                    awk -F',' '{sum+=$3; count++; if($3>max) max=$3} END {if(count>0) printf "  Average: %.1f, Peak: %d\n", sum/count, max}'
            fi
            ;;
    esac
}

# Install monitoring system
install_monitoring() {
    log_info "Installing monitoring system"

    create_monitoring_dirs
    setup_monitoring_alerts

    log_info "Monitoring system installed successfully"
    log_info "Logs: $MONITORING_LOG"
    log_info "Alerts: $ALERTS_LOG"
    log_info "Metrics: $METRICS_DIR"
    log_info "Reports: $REPORTS_DIR"
}

# Main script execution
main() {
    case "${1:-}" in
        "status"|"")
            show_system_status
            ;;
        "report")
            generate_status_report
            ;;
        "install")
            install_monitoring
            ;;
        "alerts")
            show_recent_alerts "${2:-20}"
            ;;
        "metrics")
            show_metrics "${2:-all}" "${3:-24}"
            ;;
        "setup")
            setup_monitoring_alerts
            ;;
        "help"|"-h"|"--help")
            cat << EOF
Monitoring Module for VLESS+Reality VPN

Usage: $0 [command] [options]

Commands:
    status                    Show current system status (default)
    report                    Generate detailed status report
    install                   Install monitoring system
    alerts [count]            Show recent alerts (default: 20)
    metrics [type] [hours]    Show metrics (cpu|memory|disk|vpn|all, default: all, 24h)
    setup                     Setup monitoring alerts only
    help                      Show this help message

Examples:
    $0 status                 # Show current system status
    $0 report                 # Generate detailed report
    $0 alerts 50              # Show last 50 alerts
    $0 metrics cpu 12         # Show CPU metrics for last 12 hours
    $0 install                # Install complete monitoring system

Monitoring provides real-time system status, alerting for threshold
violations, and historical metrics collection for performance analysis.

Thresholds:
  CPU: ${CPU_THRESHOLD}%
  Memory: ${MEMORY_THRESHOLD}%
  Disk: ${DISK_THRESHOLD}%
  Load: ${LOAD_THRESHOLD}
  Connections: ${CONNECTION_THRESHOLD}
EOF
            ;;
        *)
            log_error "Unknown command: $1"
            log_info "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi