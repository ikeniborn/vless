#!/bin/bash
# VLESS Phase 4 Quick Access Script
# Quick access to Phase 4 security, monitoring, and maintenance features
# Author: Claude Code
# Version: 1.0

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load common utilities
source "${SCRIPT_DIR}/modules/common_utils.sh"

# Quick help function
show_help() {
    print_header "VLESS Phase 4 Quick Access"

    echo "Usage: $0 <command> [options]"
    echo
    echo "Available commands:"
    echo
    print_section "Installation & Management"
    echo "  install         - Install all Phase 4 components"
    echo "  status          - Show Phase 4 installation status"
    echo "  update          - Update Phase 4 configurations"
    echo "  remove          - Remove all Phase 4 components"
    echo
    print_section "Security & Hardening"
    echo "  security        - Apply security hardening"
    echo "  security-status - Show security status"
    echo "  security-remove - Remove security hardening"
    echo
    print_section "Logging"
    echo "  logging         - Setup logging system"
    echo "  logging-status  - Show logging status"
    echo "  logging-test    - Test logging functionality"
    echo "  logs [type]     - View logs (access, error, auth, system, monitoring)"
    echo "  log-analyze     - Run log analysis"
    echo
    print_section "Monitoring"
    echo "  monitoring      - Setup monitoring system"
    echo "  mon-status      - Show monitoring status"
    echo "  mon-check       - Run system health check"
    echo "  mon-report      - Generate monitoring report"
    echo "  alerts          - Show active alerts"
    echo
    print_section "Maintenance"
    echo "  maintenance     - Show maintenance menu"
    echo "  cleanup         - Clean temporary files and logs"
    echo "  validate        - Validate configurations"
    echo "  report          - Generate system health report"
    echo "  backup-users    - Backup user database"
    echo "  diagnostics     - Run system diagnostics"
    echo
    print_section "Service Management"
    echo "  service-install - Install SystemD service"
    echo "  service-start   - Start VLESS VPN service"
    echo "  service-stop    - Stop VLESS VPN service"
    echo "  service-restart - Restart VLESS VPN service"
    echo "  service-status  - Show service status"
    echo
    echo "Examples:"
    echo "  $0 install                  # Install all Phase 4 components"
    echo "  $0 security                 # Apply security hardening"
    echo "  $0 mon-check                # Check system health"
    echo "  $0 logs error               # View error logs"
    echo "  $0 cleanup                  # Clean temporary files"
    echo "  $0 service-restart          # Restart VPN service"
}

# Execute command
execute_command() {
    local command="$1"
    shift

    case "$command" in
        # Installation & Management
        "install")
            source "${SCRIPT_DIR}/modules/phase4_integration.sh"
            install_phase4
            ;;
        "status")
            source "${SCRIPT_DIR}/modules/phase4_integration.sh"
            show_phase4_status
            ;;
        "update")
            source "${SCRIPT_DIR}/modules/phase4_integration.sh"
            update_configurations
            ;;
        "remove")
            source "${SCRIPT_DIR}/modules/phase4_integration.sh"
            remove_phase4
            ;;

        # Security & Hardening
        "security")
            source "${SCRIPT_DIR}/modules/security_hardening.sh"
            apply_security_hardening
            ;;
        "security-status")
            source "${SCRIPT_DIR}/modules/security_hardening.sh"
            show_security_status
            ;;
        "security-remove")
            source "${SCRIPT_DIR}/modules/security_hardening.sh"
            remove_security_hardening
            ;;

        # Logging
        "logging")
            source "${SCRIPT_DIR}/modules/logging_setup.sh"
            setup_logging
            ;;
        "logging-status")
            source "${SCRIPT_DIR}/modules/logging_setup.sh"
            show_logging_status
            ;;
        "logging-test")
            source "${SCRIPT_DIR}/modules/logging_setup.sh"
            test_logging_system
            ;;
        "logs")
            show_logs "${1:-main}"
            ;;
        "log-analyze")
            if command -v vless-log-analyzer >/dev/null 2>&1; then
                vless-log-analyzer stats
            else
                print_error "Log analyzer not installed. Run logging setup first."
            fi
            ;;

        # Monitoring
        "monitoring")
            source "${SCRIPT_DIR}/modules/monitoring.sh"
            setup_monitoring
            ;;
        "mon-status")
            source "${SCRIPT_DIR}/modules/monitoring.sh"
            show_monitoring_status
            ;;
        "mon-check")
            source "${SCRIPT_DIR}/modules/monitoring.sh"
            check_system_health
            check_services
            ;;
        "mon-report")
            source "${SCRIPT_DIR}/modules/monitoring.sh"
            generate_monitoring_report "${1:-24}" "${2:-}"
            ;;
        "alerts")
            show_active_alerts
            ;;

        # Maintenance
        "maintenance")
            source "${SCRIPT_DIR}/modules/maintenance_utils.sh"
            maintenance_menu
            ;;
        "cleanup")
            source "${SCRIPT_DIR}/modules/maintenance_utils.sh"
            cleanup_temp_files
            cleanup_old_logs "${1:-30}"
            ;;
        "validate")
            source "${SCRIPT_DIR}/modules/maintenance_utils.sh"
            validate_configurations
            ;;
        "report")
            source "${SCRIPT_DIR}/modules/maintenance_utils.sh"
            generate_system_report "${1:-}"
            ;;
        "backup-users")
            source "${SCRIPT_DIR}/modules/maintenance_utils.sh"
            backup_user_database
            ;;
        "diagnostics")
            source "${SCRIPT_DIR}/modules/maintenance_utils.sh"
            run_system_diagnostics
            ;;

        # Service Management
        "service-install")
            source "${SCRIPT_DIR}/modules/phase4_integration.sh"
            install_systemd_service
            ;;
        "service-start")
            sudo systemctl start vless-vpn
            print_success "VLESS VPN service started"
            ;;
        "service-stop")
            sudo systemctl stop vless-vpn
            print_success "VLESS VPN service stopped"
            ;;
        "service-restart")
            sudo systemctl restart vless-vpn
            print_success "VLESS VPN service restarted"
            ;;
        "service-status")
            systemctl status vless-vpn --no-pager
            ;;

        # Help
        "help"|"-h"|"--help")
            show_help
            ;;

        *)
            print_error "Unknown command: $command"
            echo
            echo "Run '$0 help' for available commands"
            exit 1
            ;;
    esac
}

# Show logs function
show_logs() {
    local log_type="$1"
    local log_file=""

    case "$log_type" in
        "main"|"vless")
            log_file="/var/log/vless/vless.log"
            ;;
        "access")
            log_file="/var/log/vless/access.log"
            ;;
        "error")
            log_file="/var/log/vless/error.log"
            ;;
        "auth")
            log_file="/var/log/vless/auth.log"
            ;;
        "system")
            log_file="/var/log/vless/system.log"
            ;;
        "monitoring")
            log_file="/var/log/vless/monitoring.log"
            ;;
        "docker")
            log_file="/var/log/vless/docker.log"
            ;;
        *)
            print_error "Unknown log type: $log_type"
            echo "Available types: main, access, error, auth, system, monitoring, docker"
            return 1
            ;;
    esac

    if [[ -f "$log_file" ]]; then
        print_header "Showing $log_type logs"
        echo "File: $log_file"
        echo "Last 50 lines (press Ctrl+C to exit):"
        echo "----------------------------------------"
        tail -n 50 -f "$log_file"
    else
        print_error "Log file not found: $log_file"
        print_info "Make sure logging system is installed and running"
    fi
}

# Show active alerts
show_active_alerts() {
    local alert_dir="/tmp/vless-alerts"

    print_header "Active VLESS Alerts"

    if [[ ! -d "$alert_dir" ]]; then
        print_info "No alert directory found. Monitoring may not be configured."
        return 0
    fi

    local alert_files=($(find "$alert_dir" -name "*" -type f 2>/dev/null || true))

    if [[ ${#alert_files[@]} -eq 0 ]]; then
        print_success "No active alerts"
        return 0
    fi

    echo "Active alerts:"
    for alert_file in "${alert_files[@]}"; do
        local alert_name=$(basename "$alert_file")
        local alert_time=$(cat "$alert_file" 2>/dev/null || echo "unknown")
        local alert_age=$(($(date +%s) - alert_time))

        printf "%-30s " "$alert_name:"
        if [[ $alert_age -lt 300 ]]; then
            echo -e "${RED}Active for ${alert_age}s${NC}"
        elif [[ $alert_age -lt 3600 ]]; then
            echo -e "${YELLOW}Active for $((alert_age/60))m${NC}"
        else
            echo -e "${YELLOW}Active for $((alert_age/3600))h${NC}"
        fi
    done

    echo
    print_info "To clear alerts, fix the underlying issues or use monitoring reset commands"
}

# Main execution
main() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    # Check if running as root for certain commands
    local command="$1"
    local requires_root=(
        "install" "remove" "security" "security-remove" "logging"
        "monitoring" "service-install" "service-start" "service-stop"
        "service-restart" "cleanup" "backup-users"
    )

    for root_cmd in "${requires_root[@]}"; do
        if [[ "$command" == "$root_cmd" ]] && [[ $EUID -ne 0 ]]; then
            print_error "This command requires root privileges. Please run with sudo."
            exit 1
        fi
    done

    execute_command "$@"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi