#!/bin/bash
#
# Sudoers Configuration Display Module
# Part of VLESS+Reality VPN Deployment System
#
# Purpose: Display instructions for configuring sudoers to allow non-root users
#          to execute VLESS management commands via sudo
# Usage: source this file from install.sh
#
# TASK-1.6: Sudoers configuration display (1h)
#
# IMPORTANT: This module DOES NOT modify /etc/sudoers automatically.
#            It only displays instructions for manual configuration (per Q-002).
#

set -euo pipefail

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

# Color codes for output
# Only define if not already set (to avoid conflicts when sourced after install.sh)
[[ -z "${RED:-}" ]] && RED='\033[0;31m'
[[ -z "${GREEN:-}" ]] && GREEN='\033[0;32m'
[[ -z "${YELLOW:-}" ]] && YELLOW='\033[1;33m'
[[ -z "${BLUE:-}" ]] && BLUE='\033[0;34m'
[[ -z "${CYAN:-}" ]] && CYAN='\033[0;36m'
[[ -z "${MAGENTA:-}" ]] && MAGENTA='\033[0;35m'
[[ -z "${NC:-}" ]] && NC='\033[0m' # No Color

# VLESS commands that will be installed
readonly VLESS_COMMANDS=(
    "familytraffic"
    "familytraffic-user"
    "familytraffic-start"
    "familytraffic-stop"
    "familytraffic-restart"
    "familytraffic-status"
    "familytraffic-logs"
    "familytraffic-update"
    "familytraffic-uninstall"
)

# Sudoers file location
readonly SUDOERS_FILE="/etc/sudoers.d/familytraffic"

# =============================================================================
# FUNCTION: display_sudoers_instructions
# =============================================================================
# Description: Display comprehensive instructions for configuring sudoers
# Called by: install.sh main() at Step 10
# Returns: 0 always (informational only)
# =============================================================================
display_sudoers_instructions() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                                              ║${NC}"
    echo -e "${BLUE}║           SUDOERS CONFIGURATION (OPTIONAL)                   ║${NC}"
    echo -e "${BLUE}║                                                              ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Section 1: Why Configure Sudoers?
    display_why_sudoers

    # Section 2: Current Situation
    display_current_situation

    # Section 3: Option 1 - Passwordless Sudo (Recommended for Convenience)
    display_passwordless_option

    # Section 4: Option 2 - Regular Sudo (More Secure)
    display_regular_sudo_option

    # Section 5: How to Apply Configuration
    display_application_steps

    # Section 6: Testing
    display_testing_instructions

    # Section 7: Security Considerations
    display_security_warnings

    # Section 8: Troubleshooting
    display_troubleshooting

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    return 0
}

# =============================================================================
# FUNCTION: display_why_sudoers
# =============================================================================
# Description: Explain why sudoers configuration is beneficial
# =============================================================================
display_why_sudoers() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Why Configure Sudoers?${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "VLESS management commands require root privileges to:"
    echo "  • Manage Docker containers (start/stop/restart)"
    echo "  • Modify configuration files in /opt/familytraffic"
    echo "  • Update Xray configuration and reload services"
    echo "  • Manage user accounts and generate keys"
    echo ""
    echo "By default, you must use 'sudo' with every command:"
    echo -e "  ${YELLOW}sudo vless add-user alice${NC}"
    echo -e "  ${YELLOW}sudo vless status${NC}"
    echo ""
    echo "Configuring sudoers allows:"
    echo -e "  ${GREEN}✓${NC} Non-root users to execute VLESS commands"
    echo -e "  ${GREEN}✓${NC} Optional passwordless execution for convenience"
    echo -e "  ${GREEN}✓${NC} Specific command whitelisting for security"
    echo ""
}

# =============================================================================
# FUNCTION: display_current_situation
# =============================================================================
# Description: Show current state and available commands
# =============================================================================
display_current_situation() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Installed Commands${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "The following commands have been installed:"
    echo ""

    for cmd in "${VLESS_COMMANDS[@]}"; do
        # Check if command exists and is executable
        if [[ -x "/usr/local/bin/${cmd}" ]]; then
            echo -e "  ${GREEN}✓${NC} /usr/local/bin/${cmd}"
        else
            echo -e "  ${YELLOW}⚠${NC} /usr/local/bin/${cmd} ${YELLOW}(will be created during orchestration)${NC}"
        fi
    done

    echo ""
}

# =============================================================================
# FUNCTION: display_passwordless_option
# =============================================================================
# Description: Show passwordless sudo configuration (convenience option)
# =============================================================================
display_passwordless_option() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Option 1: Passwordless Sudo (Recommended for Convenience)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "This configuration allows members of the 'sudo' group to run VLESS"
    echo "commands without entering a password."
    echo ""
    echo -e "${YELLOW}Configuration file content:${NC}"
    echo ""
    echo "┌────────────────────────────────────────────────────────────────┐"
    echo "│ # /etc/sudoers.d/familytraffic                                  │"
    echo "│ # Allow sudo group to run VLESS commands without password     │"
    echo "│ #                                                              │"
    echo "│ # Created: $(date +"%Y-%m-%d")                                             │"
    echo "│                                                                │"
    echo "│ %sudo ALL=(ALL) NOPASSWD: /usr/local/bin/familytraffic*       │"
    echo "└────────────────────────────────────────────────────────────────┘"
    echo ""
    echo -e "${GREEN}Pros:${NC}"
    echo "  ✓ No password required for VLESS commands"
    echo "  ✓ Convenient for frequent operations"
    echo "  ✓ Suitable for personal VPS or trusted environments"
    echo ""
    echo -e "${YELLOW}Cons:${NC}"
    echo "  ⚠ Less secure (any sudo user can run commands without password)"
    echo "  ⚠ Not recommended for shared systems"
    echo ""
}

# =============================================================================
# FUNCTION: display_regular_sudo_option
# =============================================================================
# Description: Show regular sudo configuration (security option)
# =============================================================================
display_regular_sudo_option() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Option 2: Regular Sudo with Password (More Secure)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "This configuration requires password authentication for each command."
    echo "Provides better security through password verification."
    echo ""
    echo -e "${YELLOW}Configuration file content:${NC}"
    echo ""
    echo "┌────────────────────────────────────────────────────────────────┐"
    echo "│ # /etc/sudoers.d/familytraffic                                  │"
    echo "│ # Allow sudo group to run VLESS commands with password        │"
    echo "│ #                                                              │"
    echo "│ # Created: $(date +"%Y-%m-%d")                                             │"
    echo "│                                                                │"
    echo "│ %sudo ALL=(ALL) /usr/local/bin/familytraffic*                 │"
    echo "└────────────────────────────────────────────────────────────────┘"
    echo ""
    echo -e "${GREEN}Pros:${NC}"
    echo "  ✓ More secure (password required)"
    echo "  ✓ Better audit trail"
    echo "  ✓ Suitable for shared or production systems"
    echo ""
    echo -e "${YELLOW}Cons:${NC}"
    echo "  ⚠ Must enter password for each command"
    echo "  ⚠ Less convenient for frequent operations"
    echo ""
}

# =============================================================================
# FUNCTION: display_application_steps
# =============================================================================
# Description: Show step-by-step instructions for applying configuration
# =============================================================================
display_application_steps() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}How to Apply Sudoers Configuration${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}Method 1: Using visudo (Recommended - Safer)${NC}"
    echo ""
    echo "1. Open sudoers configuration with visudo:"
    echo -e "   ${MAGENTA}sudo visudo -f ${SUDOERS_FILE}${NC}"
    echo ""
    echo "2. Add ONE of the configurations above (Option 1 or Option 2)"
    echo ""
    echo "3. Save and exit (Ctrl+O, Enter, Ctrl+X in nano)"
    echo "   visudo will validate syntax before saving"
    echo ""
    echo "4. Verify file permissions:"
    echo -e "   ${MAGENTA}ls -la ${SUDOERS_FILE}${NC}"
    echo "   Should show: -r--r----- 1 root root"
    echo ""
    echo ""
    echo -e "${YELLOW}Method 2: Using echo and tee (Faster, but use with caution)${NC}"
    echo ""
    echo "For Option 1 (passwordless):"
    echo -e "   ${MAGENTA}echo '%sudo ALL=(ALL) NOPASSWD: /usr/local/bin/familytraffic*' | \\${NC}"
    echo -e "   ${MAGENTA}    sudo tee ${SUDOERS_FILE} > /dev/null${NC}"
    echo ""
    echo "For Option 2 (with password):"
    echo -e "   ${MAGENTA}echo '%sudo ALL=(ALL) /usr/local/bin/familytraffic*' | \\${NC}"
    echo -e "   ${MAGENTA}    sudo tee ${SUDOERS_FILE} > /dev/null${NC}"
    echo ""
    echo "Then set correct permissions:"
    echo -e "   ${MAGENTA}sudo chmod 440 ${SUDOERS_FILE}${NC}"
    echo ""
}

# =============================================================================
# FUNCTION: display_testing_instructions
# =============================================================================
# Description: Show how to test the sudoers configuration
# =============================================================================
display_testing_instructions() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Testing Your Configuration${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "1. Verify sudoers file syntax:"
    echo -e "   ${MAGENTA}sudo visudo -c -f ${SUDOERS_FILE}${NC}"
    echo "   Expected output: 'parsed OK'"
    echo ""
    echo "2. Test sudo access without executing:"
    echo -e "   ${MAGENTA}sudo -l | grep familytraffic${NC}"
    echo "   Should show the VLESS commands you can execute"
    echo ""
    echo "3. Test a safe command:"
    echo -e "   ${MAGENTA}sudo familytraffic status${NC}"
    echo "   (Option 1: no password | Option 2: password required)"
    echo ""
    echo "4. Verify as non-root user:"
    echo -e "   ${MAGENTA}su - yourusername${NC}"
    echo -e "   ${MAGENTA}sudo familytraffic status${NC}"
    echo ""
}

# =============================================================================
# FUNCTION: display_security_warnings
# =============================================================================
# Description: Display important security considerations
# =============================================================================
display_security_warnings() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Security Considerations${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${RED}⚠ IMPORTANT SECURITY NOTES:${NC}"
    echo ""
    echo "1. Only grant sudo access to trusted users"
    echo "   • Users with sudo access can manage the entire VPN system"
    echo "   • They can add/remove users, view configurations, access logs"
    echo ""
    echo "2. Passwordless sudo (Option 1) is convenient but less secure"
    echo "   • Suitable for: Personal VPS, single-user systems"
    echo "   • NOT suitable for: Shared servers, production environments"
    echo ""
    echo "3. File permissions are critical"
    echo "   • ${SUDOERS_FILE} must be owned by root"
    echo "   • Permissions must be 440 or 400 (read-only for root/sudo group)"
    echo "   • Never make sudoers files world-writable"
    echo ""
    echo "4. Always use visudo for editing"
    echo "   • visudo validates syntax before saving"
    echo "   • Prevents configuration errors that could lock you out"
    echo ""
    echo "5. Audit sudo usage"
    echo "   • Check sudo logs: ${MAGENTA}sudo grep familytraffic /var/log/auth.log${NC}"
    echo "   • Monitor for unauthorized access attempts"
    echo ""
    echo "6. Wildcard usage"
    echo "   • /usr/local/bin/familytraffic* matches ALL commands starting with 'familytraffic'"
    echo "   • Be careful not to place other scripts with 'familytraffic' prefix"
    echo ""
}

# =============================================================================
# FUNCTION: display_troubleshooting
# =============================================================================
# Description: Common issues and solutions
# =============================================================================
display_troubleshooting() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Troubleshooting${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}Problem: 'command not found' when running familytraffic commands${NC}"
    echo "Solution:"
    echo "  • Check PATH: ${MAGENTA}echo \$PATH${NC}"
    echo "  • /usr/local/bin should be in PATH"
    echo "  • Verify commands exist: ${MAGENTA}ls -la /usr/local/bin/familytraffic*${NC}"
    echo ""
    echo -e "${YELLOW}Problem: 'permission denied' even with sudo${NC}"
    echo "Solution:"
    echo "  • Verify you're in sudo group: ${MAGENTA}groups${NC}"
    echo "  • Check sudoers syntax: ${MAGENTA}sudo visudo -c -f ${SUDOERS_FILE}${NC}"
    echo "  • Check file permissions: ${MAGENTA}ls -la ${SUDOERS_FILE}${NC}"
    echo "  • Try with full path: ${MAGENTA}sudo /usr/local/bin/familytraffic status${NC}"
    echo ""
    echo -e "${YELLOW}Problem: Still prompted for password with NOPASSWD option${NC}"
    echo "Solution:"
    echo "  • Check sudoers rule order (more specific rules first)"
    echo "  • Look for conflicting rules: ${MAGENTA}sudo -l${NC}"
    echo "  • Verify group membership: ${MAGENTA}groups \$USER${NC}"
    echo ""
    echo -e "${YELLOW}Problem: 'syntax error' when validating sudoers file${NC}"
    echo "Solution:"
    echo "  • Use visudo instead of direct editing"
    echo "  • Check for typos in the configuration"
    echo "  • Ensure no extra spaces or special characters"
    echo "  • Compare with examples above"
    echo ""
}

# =============================================================================
# FUNCTION: offer_automatic_configuration
# =============================================================================
# Description: Optionally offer to create sudoers file automatically
# Note: Currently not used (per Q-002: manual step only)
# Kept for potential future use if requirements change
# =============================================================================
offer_automatic_configuration() {
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Would you like to automatically configure sudoers?${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "This will create ${SUDOERS_FILE} with passwordless sudo."
    echo ""

    local response
    read -rp "Create sudoers configuration now? [y/N]: " response
    response=${response,,}  # Convert to lowercase

    if [[ "$response" == "y" || "$response" == "yes" ]]; then
        echo ""
        echo "Creating sudoers configuration..."

        # Create sudoers file
        cat > /tmp/familytraffic_sudoers << 'EOF'
# VLESS Management Commands - Sudoers Configuration
# Allows members of sudo group to execute VLESS commands without password
# Created by VLESS installer

%sudo ALL=(ALL) NOPASSWD: /usr/local/bin/vless*
EOF

        # Install with proper permissions
        if sudo install -m 0440 -o root -g root /tmp/familytraffic_sudoers "${SUDOERS_FILE}"; then
            rm -f /tmp/familytraffic_sudoers
            echo -e "${GREEN}✓ Sudoers configuration created successfully${NC}"
            echo ""

            # Validate
            if sudo visudo -c -f "${SUDOERS_FILE}" &>/dev/null; then
                echo -e "${GREEN}✓ Configuration validated successfully${NC}"
            else
                echo -e "${RED}✗ Configuration validation failed${NC}"
                echo "  Removing invalid configuration..."
                sudo rm -f "${SUDOERS_FILE}"
                return 1
            fi
        else
            echo -e "${RED}✗ Failed to create sudoers configuration${NC}"
            rm -f /tmp/familytraffic_sudoers
            return 1
        fi
    else
        echo ""
        echo "Skipped automatic configuration."
        echo "You can configure manually later using the instructions above."
    fi

    return 0
}

# =============================================================================
# MODULE INITIALIZATION
# =============================================================================

# Export function for use by install.sh
export -f display_sudoers_instructions

# Optionally export other functions if needed
export -f display_why_sudoers
export -f display_current_situation
export -f display_passwordless_option
export -f display_regular_sudo_option
export -f display_application_steps
export -f display_testing_instructions
export -f display_security_warnings
export -f display_troubleshooting
export -f offer_automatic_configuration
