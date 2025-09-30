#!/bin/bash

# Network configuration library for VLESS VPN service
# Handles IP forwarding, NAT, and Docker bridge network setup

# Load colors if not already loaded
if [ -z "$NC" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"
fi

# Find available Docker subnet
# Returns subnet in format "172.X.0.0/16:172.X.0.1" where X is not used
# All status messages go to stderr, result goes to stdout
find_available_docker_subnet() {
    print_step "Searching for available Docker subnet..." >&2

    # Get list of all Docker networks and their subnets
    local used_subnets=$(docker network inspect $(docker network ls -q) 2>/dev/null | \
        jq -r '.[].IPAM.Config[]?.Subnet // empty' | \
        grep -E '^172\.[0-9]+\.' | \
        sed 's/172\.\([0-9]*\)\..*/\1/' | \
        sort -n)

    # Try to find free subnet in range 172.16-172.31 (private range)
    for i in {16..31}; do
        if ! echo "$used_subnets" | grep -qw "$i"; then
            local subnet="172.${i}.0.0/16"
            local gateway="172.${i}.0.1"

            print_success "Found available subnet: $subnet" >&2
            echo "$subnet:$gateway"
            return 0
        fi
    done

    # If 172.16-31 are all taken, try 172.32-254
    print_warning "Standard Docker range (172.16-31.x.x) is full, checking extended range..." >&2
    for i in {32..254}; do
        if ! echo "$used_subnets" | grep -qw "$i"; then
            local subnet="172.${i}.0.0/16"
            local gateway="172.${i}.0.1"

            print_success "Found available subnet: $subnet" >&2
            echo "$subnet:$gateway"
            return 0
        fi
    done

    print_error "No available subnets found in 172.x.x.x range" >&2
    return 1
}

# Enable IP forwarding on the host
enable_ip_forwarding() {
    print_step "Enabling IP forwarding..."

    # Check current status
    local current_forward=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")

    if [ "$current_forward" = "1" ]; then
        print_success "IP forwarding is already enabled"
        return 0
    fi

    # Enable temporarily
    if sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1; then
        print_success "IP forwarding enabled temporarily"
    else
        print_error "Failed to enable IP forwarding temporarily"
        return 1
    fi

    # Make it persistent
    local sysctl_conf="/etc/sysctl.conf"
    if [ -f "$sysctl_conf" ]; then
        if grep -q "^net.ipv4.ip_forward" "$sysctl_conf"; then
            # Update existing entry
            sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' "$sysctl_conf"
        else
            # Add new entry
            echo "net.ipv4.ip_forward = 1" >> "$sysctl_conf"
        fi
        print_success "IP forwarding configured persistently in $sysctl_conf"
    else
        print_warning "Could not find $sysctl_conf, IP forwarding is temporary only"
    fi

    return 0
}

# Configure NAT using iptables
configure_nat_iptables() {
    local docker_subnet="${1:-172.20.0.0/16}"
    local external_interface="${2:-}"

    print_step "Configuring NAT with iptables..."

    # Auto-detect external interface if not provided
    if [ -z "$external_interface" ]; then
        external_interface=$(ip route | grep default | awk '{print $5}' | head -1)
        if [ -z "$external_interface" ]; then
            print_error "Could not detect external network interface"
            return 1
        fi
        print_info "Detected external interface: $external_interface"
    fi

    # Check if iptables is available
    if ! command_exists "iptables"; then
        print_error "iptables is not installed"
        return 1
    fi

    # Add MASQUERADE rule for Docker subnet (skip check, just add)
    # Note: -C (check) doesn't work reliably with subnet format, so we just add the rule
    # Duplicate rules are handled by iptables automatically
    if iptables -t nat -A POSTROUTING -s "$docker_subnet" -o "$external_interface" -j MASQUERADE 2>/dev/null; then
        print_success "Added NAT MASQUERADE rule for $docker_subnet"
    else
        # If failed, check if rule already exists by listing
        # Extract network part from CIDR for grep (escape dots for regex)
        local subnet_pattern=$(echo "$docker_subnet" | sed 's/\./\\./g')
        if iptables -t nat -L POSTROUTING -n | grep -q "MASQUERADE.*${subnet_pattern}"; then
            print_success "NAT MASQUERADE rule already exists"
        else
            print_error "Failed to add NAT MASQUERADE rule"
            return 1
        fi
    fi

    # Allow forwarding for Docker subnet
    # Add FORWARD rules (iptables will handle duplicates)
    if iptables -A FORWARD -s "$docker_subnet" -j ACCEPT 2>/dev/null; then
        print_success "Added FORWARD rule for outgoing traffic"
    else
        print_info "FORWARD rule for outgoing traffic may already exist"
    fi

    if iptables -A FORWARD -d "$docker_subnet" -j ACCEPT 2>/dev/null; then
        print_success "Added FORWARD rule for incoming traffic"
    else
        print_info "FORWARD rule for incoming traffic may already exist"
    fi

    # Save iptables rules (distribution-specific)
    if command_exists "netfilter-persistent"; then
        netfilter-persistent save
        print_success "iptables rules saved with netfilter-persistent"
    elif command_exists "iptables-save"; then
        # Try to save to /etc/iptables/rules.v4 (create directory if needed)
        if [ ! -d "/etc/iptables" ]; then
            mkdir -p /etc/iptables 2>/dev/null || true
        fi

        if [ -d "/etc/iptables" ]; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null && \
                print_success "iptables rules saved to /etc/iptables/rules.v4"
        else
            # Fallback to /etc/iptables.rules
            iptables-save > /etc/iptables.rules 2>/dev/null && \
                print_success "iptables rules saved to /etc/iptables.rules"
        fi
    else
        print_warning "Could not save iptables rules persistently"
        print_info "Rules will be lost after reboot. Consider installing iptables-persistent"
    fi

    return 0
}

# Configure UFW for Docker bridge network
configure_ufw_for_docker() {
    local docker_subnet="${1:-172.20.0.0/16}"
    local server_port="${2:-443}"

    if ! command_exists "ufw"; then
        print_info "UFW is not installed, skipping UFW configuration"
        return 0
    fi

    print_step "Configuring UFW for Docker bridge network..."

    # Check if UFW is active
    local ufw_status=$(ufw status 2>/dev/null | head -1)
    if ! echo "$ufw_status" | grep -q "active"; then
        print_info "UFW is not active, skipping UFW configuration"
        return 0
    fi

    # 1. Allow incoming connections on server port
    if ! ufw status numbered | grep -q "$server_port/tcp"; then
        print_step "Adding UFW rule for port $server_port/tcp..."
        ufw allow "$server_port/tcp" comment "VLESS VPN Service" 2>/dev/null
        print_success "UFW rule added for port $server_port/tcp"
    else
        print_success "UFW rule for port $server_port/tcp already exists"
    fi

    # 2. Configure DEFAULT_FORWARD_POLICY
    local ufw_default="/etc/default/ufw"
    if [ -f "$ufw_default" ]; then
        print_step "Configuring UFW forward policy..."

        if grep -q "^DEFAULT_FORWARD_POLICY=" "$ufw_default"; then
            # Update existing policy
            sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' "$ufw_default"
            print_success "UFW forward policy set to ACCEPT"
        else
            # Add new policy
            echo 'DEFAULT_FORWARD_POLICY="ACCEPT"' >> "$ufw_default"
            print_success "UFW forward policy added"
        fi
    fi

    # 3. Add NAT rules to /etc/ufw/before.rules
    local before_rules="/etc/ufw/before.rules"
    if [ -f "$before_rules" ]; then
        print_step "Adding NAT rules to UFW before.rules..."

        # Check if NAT rules already exist
        if grep -q "# NAT table rules for Docker" "$before_rules"; then
            print_success "NAT rules already exist in before.rules"
        else
            # Backup before.rules
            cp "$before_rules" "${before_rules}.backup.$(date +%Y%m%d-%H%M%S)"

            # Add NAT rules at the beginning of the file
            local external_interface=$(ip route | grep default | awk '{print $5}' | head -1)

            cat > /tmp/ufw_nat_rules << EOF
# NAT table rules for Docker VLESS bridge network
*nat
:POSTROUTING ACCEPT [0:0]

# Forward traffic from Docker subnet to external interface
-A POSTROUTING -s $docker_subnet -o $external_interface -j MASQUERADE

COMMIT
# End of NAT table rules

EOF
            # Insert NAT rules before existing rules
            cat /tmp/ufw_nat_rules "$before_rules" > /tmp/before.rules.new
            mv /tmp/before.rules.new "$before_rules"
            rm -f /tmp/ufw_nat_rules

            print_success "NAT rules added to UFW before.rules"
        fi
    fi

    # 4. Reload UFW to apply changes
    print_step "Reloading UFW..."
    if ufw reload 2>/dev/null; then
        print_success "UFW reloaded successfully"
    else
        print_warning "Failed to reload UFW, changes may not be applied"
    fi

    return 0
}

# Main function to configure all network settings for VLESS service
configure_network_for_vless() {
    local docker_subnet="$1"
    local server_port="${2:-443}"

    print_header "Configuring Network for VLESS Service"

    # Step 1: Enable IP forwarding
    if ! enable_ip_forwarding; then
        print_error "Failed to enable IP forwarding"
        return 1
    fi

    # Step 2: Configure NAT with iptables
    if ! configure_nat_iptables "$docker_subnet"; then
        print_error "Failed to configure NAT with iptables"
        return 1
    fi

    # Step 3: Configure UFW if installed and active
    configure_ufw_for_docker "$docker_subnet" "$server_port"

    print_success "Network configuration completed successfully"
    return 0
}

# Verify network configuration
verify_network_configuration() {
    local docker_subnet="$1"
    local server_port="${2:-443}"

    print_step "Verifying network configuration..."

    local errors=0

    # Check IP forwarding
    local ip_forward=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)
    if [ "$ip_forward" = "1" ]; then
        print_success "IP forwarding: enabled"
    else
        print_error "IP forwarding: disabled"
        ((errors++))
    fi

    # Check iptables NAT rule
    if iptables -t nat -L POSTROUTING -n | grep -q "MASQUERADE.*$docker_subnet"; then
        print_success "iptables NAT rule: configured"
    else
        print_warning "iptables NAT rule: not found (may use UFW instead)"
    fi

    # Check port availability
    if netstat -tuln | grep -q ":$server_port "; then
        print_success "Port $server_port: listening"
    else
        print_info "Port $server_port: not listening yet (service may not be started)"
    fi

    # Check Docker network
    if docker network ls | grep -q "vless-network"; then
        print_success "Docker network: exists"
    else
        print_info "Docker network: not created yet (will be created by docker-compose)"
    fi

    if [ $errors -eq 0 ]; then
        print_success "Network configuration verification passed"
        return 0
    else
        print_error "Network configuration verification failed with $errors error(s)"
        return 1
    fi
}

# Get external network interface name
get_external_interface() {
    local interface=$(ip route | grep default | awk '{print $5}' | head -1)

    if [ -z "$interface" ]; then
        print_error "Could not detect external network interface"
        return 1
    fi

    echo "$interface"
    return 0
}

# Display network configuration summary
display_network_summary() {
    local docker_subnet="$1"
    local docker_gateway="$2"
    local server_port="${3:-443}"

    print_header "Network Configuration Summary"

    echo "Docker Network:"
    echo "  Subnet:    $docker_subnet"
    echo "  Gateway:   $docker_gateway"
    echo ""
    echo "VLESS Service:"
    echo "  Port:      $server_port"
    echo ""
    echo "System:"
    echo "  IP Forward: $(sysctl -n net.ipv4.ip_forward)"
    echo "  Interface:  $(get_external_interface 2>/dev/null || echo 'auto-detect')"
    echo ""
}