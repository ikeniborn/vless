#!/bin/bash

# Phase 4 Integration Module for VLESS+Reality VPN
# This module orchestrates all Phase 4 security components:
# UFW firewall, security hardening, certificate management, and monitoring
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

# Phase 4 modules
readonly UFW_MODULE="${SCRIPT_DIR}/ufw_config.sh"
readonly SECURITY_MODULE="${SCRIPT_DIR}/security_hardening.sh"
readonly CERT_MODULE="${SCRIPT_DIR}/cert_management.sh"
readonly MONITORING_MODULE="${SCRIPT_DIR}/monitoring.sh"

# Configuration
readonly PHASE4_LOG="/opt/vless/logs/phase4_integration.log"
readonly PHASE4_CONFIG="/opt/vless/config/phase4.conf"

# Phase 4 installation log
phase4_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] PHASE4: $*" | tee -a "$PHASE4_LOG"
}

# Check if all Phase 4 modules exist
check_phase4_modules() {
    log_info "Checking Phase 4 modules"

    local modules=(
        "$UFW_MODULE"
        "$SECURITY_MODULE"
        "$CERT_MODULE"
        "$MONITORING_MODULE"
    )

    local missing_modules=()

    for module in "${modules[@]}"; do
        if [[ ! -f "$module" ]]; then
            missing_modules+=("$(basename "$module")")
        elif [[ ! -x "$module" ]]; then
            chmod +x "$module"
        fi
    done

    if [[ ${#missing_modules[@]} -gt 0 ]]; then
        log_error "Missing Phase 4 modules: ${missing_modules[*]}"
        return 1
    fi

    log_info "All Phase 4 modules found"
    return 0
}

# Create Phase 4 configuration directory
create_phase4_config() {
    log_info "Creating Phase 4 configuration"

    mkdir -p "$(dirname "$PHASE4_CONFIG")"
    mkdir -p "$(dirname "$PHASE4_LOG")"

    cat > "$PHASE4_CONFIG" << EOF
# VLESS VPN Phase 4 Security Configuration
# Generated: $(date)

[ufw]
enabled=true
default_deny_incoming=true
default_allow_outgoing=true
vless_ports=443
ssh_ports=22,2222

[security]
ssh_hardening=true
fail2ban=true
auto_updates=true
security_monitoring=true

[certificates]
domain=vless.local
validity_days=365
auto_renewal=true
monitoring=true

[monitoring]
enabled=true
cpu_threshold=80
memory_threshold=85
disk_threshold=90
alerts=true
reports=true

[integration]
phase4_completed=false
installation_date=
last_update=
EOF

    log_info "Phase 4 configuration created: $PHASE4_CONFIG"
}

# Execute UFW configuration
configure_firewall() {
    log_info "Phase 4.1: Configuring UFW Firewall"
    phase4_log "Starting UFW firewall configuration"

    if [[ ! -f "$UFW_MODULE" ]]; then
        log_error "UFW module not found: $UFW_MODULE"
        return 1
    fi

    # Run UFW configuration
    if "$UFW_MODULE" configure; then
        phase4_log "UFW firewall configured successfully"
        log_info "✓ UFW firewall configuration completed"
    else
        phase4_log "UFW firewall configuration failed"
        log_error "UFW firewall configuration failed"
        return 1
    fi

    return 0
}

# Execute security hardening
harden_security() {
    log_info "Phase 4.2: Implementing Security Hardening"
    phase4_log "Starting security hardening"

    if [[ ! -f "$SECURITY_MODULE" ]]; then
        log_error "Security module not found: $SECURITY_MODULE"
        return 1
    fi

    # Run security hardening
    if "$SECURITY_MODULE" harden; then
        phase4_log "Security hardening completed successfully"
        log_info "✓ Security hardening completed"
    else
        phase4_log "Security hardening failed"
        log_error "Security hardening failed"
        return 1
    fi

    return 0
}

# Setup certificate management
setup_certificates() {
    log_info "Phase 4.3: Setting up Certificate Management"
    phase4_log "Starting certificate management setup"

    if [[ ! -f "$CERT_MODULE" ]]; then
        log_error "Certificate module not found: $CERT_MODULE"
        return 1
    fi

    # Generate initial certificates
    local domain="${1:-vless.local}"
    if "$CERT_MODULE" generate "$domain"; then
        phase4_log "Initial certificates generated for domain: $domain"
        log_info "✓ Initial certificates generated"
    else
        phase4_log "Certificate generation failed"
        log_error "Certificate generation failed"
        return 1
    fi

    # Setup certificate monitoring
    if "$CERT_MODULE" monitor; then
        phase4_log "Certificate monitoring configured"
        log_info "✓ Certificate monitoring configured"
    else
        phase4_log "Certificate monitoring setup failed"
        log_warn "Certificate monitoring setup failed"
    fi

    return 0
}

# Setup system monitoring
setup_monitoring() {
    log_info "Phase 4.4: Setting up System Monitoring"
    phase4_log "Starting system monitoring setup"

    if [[ ! -f "$MONITORING_MODULE" ]]; then
        log_error "Monitoring module not found: $MONITORING_MODULE"
        return 1
    fi

    # Install monitoring system
    if "$MONITORING_MODULE" install; then
        phase4_log "System monitoring installed successfully"
        log_info "✓ System monitoring installed"
    else
        phase4_log "System monitoring installation failed"
        log_error "System monitoring installation failed"
        return 1
    fi

    return 0
}

# Run Phase 4 tests
run_phase4_tests() {
    log_info "Running Phase 4 Integration Tests"
    phase4_log "Starting Phase 4 integration tests"

    local test_script="${SCRIPT_DIR}/../tests/test_phase4_security.sh"

    if [[ ! -f "$test_script" ]]; then
        log_error "Phase 4 test script not found: $test_script"
        return 1
    fi

    if [[ ! -x "$test_script" ]]; then
        chmod +x "$test_script"
    fi

    # Run tests
    if "$test_script"; then
        phase4_log "Phase 4 integration tests passed"
        log_info "✓ Phase 4 integration tests passed"
        return 0
    else
        phase4_log "Phase 4 integration tests failed"
        log_error "Phase 4 integration tests failed"
        return 1
    fi
}

# Update Phase 4 configuration status
update_phase4_status() {
    local status="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ -f "$PHASE4_CONFIG" ]]; then
        sed -i "s/^phase4_completed=.*/phase4_completed=$status/" "$PHASE4_CONFIG"
        sed -i "s/^last_update=.*/last_update=$timestamp/" "$PHASE4_CONFIG"

        if [[ "$status" == "true" ]] && ! grep -q "installation_date=" "$PHASE4_CONFIG" | grep -v "installation_date=$"; then
            sed -i "s/^installation_date=.*/installation_date=$timestamp/" "$PHASE4_CONFIG"
        fi
    fi

    phase4_log "Phase 4 status updated: $status"
}

# Complete Phase 4 implementation
implement_phase4() {
    log_info "Starting Phase 4: Security and Firewall Configuration"
    log_info "======================================================"

    # Ensure running as root for security operations
    if ! validate_root; then
        log_error "Phase 4 implementation requires root privileges"
        return 1
    fi

    # Check modules exist
    if ! check_phase4_modules; then
        log_error "Phase 4 modules check failed"
        return 1
    fi

    # Create configuration
    create_phase4_config

    # Log start
    phase4_log "Phase 4 implementation started"

    local phase4_success=true

    # Execute Phase 4 components in order
    log_info "Executing Phase 4 components..."

    # Phase 4.1: UFW Configuration
    if ! configure_firewall; then
        phase4_success=false
        log_error "Phase 4.1 (UFW) failed"
    fi

    # Phase 4.2: Security Hardening
    if $phase4_success && ! harden_security; then
        phase4_success=false
        log_error "Phase 4.2 (Security Hardening) failed"
    fi

    # Phase 4.3: Certificate Management
    if $phase4_success && ! setup_certificates "${1:-vless.local}"; then
        phase4_success=false
        log_error "Phase 4.3 (Certificate Management) failed"
    fi

    # Phase 4.4: System Monitoring
    if $phase4_success && ! setup_monitoring; then
        phase4_success=false
        log_error "Phase 4.4 (System Monitoring) failed"
    fi

    # Run integration tests
    if $phase4_success; then
        log_info "Running Phase 4 integration tests..."
        if ! run_phase4_tests; then
            phase4_success=false
            log_error "Phase 4 integration tests failed"
        fi
    fi

    # Update status and report results
    if $phase4_success; then
        update_phase4_status "true"
        phase4_log "Phase 4 implementation completed successfully"

        log_info ""
        log_info "✓ Phase 4 Implementation Completed Successfully!"
        log_info "=============================================="
        log_info ""
        log_info "Security Components Installed:"
        log_info "- UFW Firewall (configured for VLESS ports)"
        log_info "- SSH Hardening (fail2ban, secure config)"
        log_info "- Certificate Management (auto-renewal)"
        log_info "- System Monitoring (alerts & reports)"
        log_info ""
        log_info "Important Security Notes:"
        log_info "- Review SSH access before closing session"
        log_info "- Check UFW rules: sudo ufw status verbose"
        log_info "- Monitor logs: tail -f $PHASE4_LOG"
        log_info "- Security reports: ${MONITORING_MODULE} report"
        log_info ""
        log_info "Configuration: $PHASE4_CONFIG"
        log_info "Logs: $PHASE4_LOG"

        return 0
    else
        update_phase4_status "false"
        phase4_log "Phase 4 implementation failed"

        log_error ""
        log_error "✗ Phase 4 Implementation Failed"
        log_error "================================"
        log_error ""
        log_error "Please check the logs for details:"
        log_error "- Phase 4 Log: $PHASE4_LOG"
        log_error "- System Logs: journalctl -xe"
        log_error ""
        log_error "You may need to:"
        log_error "- Review module-specific logs"
        log_error "- Check system requirements"
        log_error "- Verify network connectivity"
        log_error "- Ensure sufficient privileges"

        return 1
    fi
}

# Show Phase 4 status
show_phase4_status() {
    log_info "Phase 4 Status Report"
    log_info "===================="

    if [[ -f "$PHASE4_CONFIG" ]]; then
        log_info "Configuration file: $PHASE4_CONFIG"
        log_info ""

        # Parse configuration
        local phase4_completed
        phase4_completed=$(grep "^phase4_completed=" "$PHASE4_CONFIG" | cut -d'=' -f2)

        if [[ "$phase4_completed" == "true" ]]; then
            log_info "✓ Phase 4 Status: COMPLETED"

            local install_date
            install_date=$(grep "^installation_date=" "$PHASE4_CONFIG" | cut -d'=' -f2)
            if [[ -n "$install_date" ]]; then
                log_info "Installation Date: $install_date"
            fi

            local last_update
            last_update=$(grep "^last_update=" "$PHASE4_CONFIG" | cut -d'=' -f2)
            if [[ -n "$last_update" ]]; then
                log_info "Last Update: $last_update"
            fi
        else
            log_info "✗ Phase 4 Status: NOT COMPLETED"
        fi

        log_info ""
        log_info "Component Status:"

        # Check UFW
        if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
            log_info "✓ UFW Firewall: Active"
        else
            log_info "✗ UFW Firewall: Inactive or not installed"
        fi

        # Check fail2ban
        if command -v fail2ban-client >/dev/null 2>&1 && fail2ban-client ping 2>/dev/null | grep -q "pong"; then
            log_info "✓ Fail2ban: Running"
        else
            log_info "✗ Fail2ban: Not running or not installed"
        fi

        # Check certificates
        if [[ -f "/opt/vless/certs/server.crt" ]]; then
            log_info "✓ Certificates: Present"
        else
            log_info "✗ Certificates: Not found"
        fi

        # Check monitoring
        if [[ -f "/usr/local/bin/vless-monitor" ]]; then
            log_info "✓ Monitoring: Installed"
        else
            log_info "✗ Monitoring: Not installed"
        fi

    else
        log_info "✗ Phase 4 configuration not found"
        log_info "Run '$0 implement' to start Phase 4 implementation"
    fi

    log_info ""
    log_info "Log file: $PHASE4_LOG"
}

# Validate Phase 4 implementation
validate_phase4() {
    log_info "Validating Phase 4 Implementation"
    log_info "================================="

    local validation_errors=0

    # Check configuration file
    if [[ ! -f "$PHASE4_CONFIG" ]]; then
        log_error "Phase 4 configuration file not found"
        ((validation_errors++))
    fi

    # Validate each module
    local modules=(
        "$UFW_MODULE:UFW Configuration"
        "$SECURITY_MODULE:Security Hardening"
        "$CERT_MODULE:Certificate Management"
        "$MONITORING_MODULE:System Monitoring"
    )

    for module_info in "${modules[@]}"; do
        local module_path="${module_info%:*}"
        local module_name="${module_info#*:}"

        if [[ ! -f "$module_path" ]]; then
            log_error "$module_name module not found: $module_path"
            ((validation_errors++))
        elif [[ ! -x "$module_path" ]]; then
            log_error "$module_name module not executable: $module_path"
            ((validation_errors++))
        else
            # Test module syntax
            if ! bash -n "$module_path"; then
                log_error "$module_name module has syntax errors"
                ((validation_errors++))
            fi
        fi
    done

    # Run integration tests
    if ! run_phase4_tests; then
        log_error "Phase 4 integration tests failed"
        ((validation_errors++))
    fi

    # Report validation results
    if [[ $validation_errors -eq 0 ]]; then
        log_info "✓ Phase 4 validation passed"
        return 0
    else
        log_error "✗ Phase 4 validation failed with $validation_errors errors"
        return 1
    fi
}

# Main script execution
main() {
    case "${1:-}" in
        "implement"|"")
            implement_phase4 "${2:-vless.local}"
            ;;
        "status")
            show_phase4_status
            ;;
        "validate")
            validate_phase4
            ;;
        "test")
            run_phase4_tests
            ;;
        "firewall")
            configure_firewall
            ;;
        "security")
            harden_security
            ;;
        "certificates")
            setup_certificates "${2:-vless.local}"
            ;;
        "monitoring")
            setup_monitoring
            ;;
        "help"|"-h"|"--help")
            cat << EOF
Phase 4 Integration Module for VLESS+Reality VPN

Usage: $0 [command] [options]

Commands:
    implement [domain]    Complete Phase 4 implementation (default)
    status               Show Phase 4 status
    validate             Validate Phase 4 implementation
    test                 Run Phase 4 integration tests
    firewall             Configure UFW firewall only
    security             Run security hardening only
    certificates [domain] Setup certificate management only
    monitoring           Setup system monitoring only
    help                 Show this help message

Examples:
    $0 implement                    # Full Phase 4 implementation
    $0 implement example.com        # Implementation with custom domain
    $0 status                       # Show current status
    $0 validate                     # Validate implementation
    $0 test                         # Run integration tests

Phase 4 Components:
    4.1: UFW Firewall Configuration
    4.2: Security Hardening (SSH, fail2ban, updates)
    4.3: Certificate Management (generation, renewal, monitoring)
    4.4: System Monitoring (resources, alerts, reports)

This module orchestrates all security components for a complete
security baseline implementation.

Requires: root privileges
Logs: $PHASE4_LOG
Config: $PHASE4_CONFIG
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