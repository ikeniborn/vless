#!/bin/bash

# Network configuration library for VLESS VPN service
# Configures kernel modules and sysctl settings for Docker bridge networking
# Docker automatically manages iptables NAT rules - no manual intervention needed

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

# Load br_netfilter kernel module (required for bridge traffic to pass through iptables)
load_br_netfilter() {
    print_step "Loading br_netfilter kernel module..."

    # Check if already loaded
    if lsmod | grep -q "^br_netfilter"; then
        print_success "br_netfilter module already loaded"
    else
        # Load module
        if modprobe br_netfilter 2>/dev/null; then
            print_success "br_netfilter module loaded"
        else
            print_error "Failed to load br_netfilter module"
            return 1
        fi
    fi

    # Make it persistent across reboots
    local modules_conf="/etc/modules-load.d/br_netfilter.conf"
    if [ ! -f "$modules_conf" ] || ! grep -q "^br_netfilter" "$modules_conf"; then
        print_step "Making br_netfilter load persistent..."
        mkdir -p /etc/modules-load.d
        echo "br_netfilter" > "$modules_conf"
        print_success "br_netfilter will load on boot"
    else
        print_success "br_netfilter already configured to load on boot"
    fi

    return 0
}

# Enable IP forwarding and bridge netfilter
enable_ip_forwarding() {
    print_step "Configuring IP forwarding..."

    # Check current runtime status
    local ip_forward=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
    local bridge_iptables=$(cat /proc/sys/net/bridge/bridge-nf-call-iptables 2>/dev/null || echo "0")
    local bridge_ip6tables=$(cat /proc/sys/net/bridge/bridge-nf-call-ip6tables 2>/dev/null || echo "0")

    # Enable IP forwarding if not already enabled
    if [ "$ip_forward" != "1" ]; then
        if sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1; then
            print_success "IP forwarding enabled (runtime)"
        else
            print_error "Failed to enable IP forwarding"
            return 1
        fi
    else
        print_success "IP forwarding already enabled (runtime)"
    fi

    # Enable bridge netfilter for iptables (CRITICAL for Docker NAT to work)
    if [ "$bridge_iptables" != "1" ]; then
        if sysctl -w net.bridge.bridge-nf-call-iptables=1 >/dev/null 2>&1; then
            print_success "Bridge netfilter for iptables enabled (runtime)"
        else
            print_warning "Failed to enable bridge netfilter for iptables"
        fi
    else
        print_success "Bridge netfilter for iptables already enabled"
    fi

    if [ "$bridge_ip6tables" != "1" ]; then
        if sysctl -w net.bridge.bridge-nf-call-ip6tables=1 >/dev/null 2>&1; then
            print_success "Bridge netfilter for ip6tables enabled (runtime)"
        else
            print_warning "Failed to enable bridge netfilter for ip6tables"
        fi
    else
        print_success "Bridge netfilter for ip6tables already enabled"
    fi

    # Make settings persistent
    make_sysctl_persistent

    return 0
}

# Make sysctl settings persistent across reboots
make_sysctl_persistent() {
    print_step "Making network settings persistent..."

    local sysctl_conf="/etc/sysctl.d/99-vless-network.conf"

    # Create sysctl config file for VLESS
    cat > "$sysctl_conf" << 'EOF'
# Network configuration for VLESS VPN service
# Required for Docker bridge networking and VPN functionality

# Enable IP forwarding (allows router functionality)
net.ipv4.ip_forward = 1

# Enable bridge netfilter (CRITICAL: allows iptables to process bridge traffic)
# Without this, Docker's automatic NAT rules won't work
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

    print_success "Created persistent sysctl configuration: $sysctl_conf"

    # Also update /etc/sysctl.conf for compatibility
    local main_sysctl="/etc/sysctl.conf"
    if [ -f "$main_sysctl" ]; then
        if ! grep -q "^net.ipv4.ip_forward.*=.*1" "$main_sysctl"; then
            if grep -q "^net.ipv4.ip_forward" "$main_sysctl"; then
                sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' "$main_sysctl"
            else
                echo "" >> "$main_sysctl"
                echo "# Enable IP forwarding for VLESS VPN" >> "$main_sysctl"
                echo "net.ipv4.ip_forward = 1" >> "$main_sysctl"
            fi
            print_success "Updated $main_sysctl for IP forwarding"
        fi
    fi

    return 0
}

# Configure Docker daemon with optimal settings
configure_docker_daemon() {
    print_step "Configuring Docker daemon..."

    local daemon_json="/etc/docker/daemon.json"
    local needs_restart=0

    # Create or update daemon.json
    if [ ! -f "$daemon_json" ]; then
        print_step "Creating Docker daemon configuration..."
        mkdir -p /etc/docker
        cat > "$daemon_json" << 'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "userland-proxy": false,
    "live-restore": true
}
EOF
        needs_restart=1
        print_success "Docker daemon configuration created"
    else
        print_success "Docker daemon configuration exists"
    fi

    # Restart Docker if needed
    if [ $needs_restart -eq 1 ]; then
        print_step "Restarting Docker daemon..."
        if systemctl restart docker; then
            print_success "Docker daemon restarted"
            sleep 2  # Give Docker time to initialize
        else
            print_error "Failed to restart Docker daemon"
            return 1
        fi
    fi

    return 0
}

# Configure UFW to allow VPN port (if UFW is active)
# This function sets the DEFAULT_FORWARD_POLICY and adds port rules
# For Docker bridge networking, use configure_ufw_for_docker() to add explicit FORWARD rules
configure_firewall() {
    local server_port="${1:-443}"

    if ! command_exists "ufw"; then
        print_info "UFW is not installed, skipping firewall configuration"
        return 0
    fi

    # Check if UFW is active
    local ufw_status=$(ufw status 2>/dev/null | head -1)
    if ! echo "$ufw_status" | grep -q "active"; then
        print_info "UFW is not active, skipping firewall configuration"
        return 0
    fi

    print_step "Configuring UFW firewall..."

    # Allow VPN port
    if ! ufw status numbered | grep -q "$server_port/tcp"; then
        print_step "Adding UFW rule for port $server_port/tcp..."
        ufw allow "$server_port/tcp" comment "VLESS VPN Service" 2>/dev/null
        print_success "UFW rule added for port $server_port/tcp"
    else
        print_success "UFW rule for port $server_port/tcp already exists"
    fi

    # Set forward policy to ACCEPT
    local ufw_default="/etc/default/ufw"
    if [ -f "$ufw_default" ]; then
        if ! grep -q '^DEFAULT_FORWARD_POLICY="ACCEPT"' "$ufw_default"; then
            print_step "Configuring UFW forward policy..."
            sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' "$ufw_default"
            print_success "UFW forward policy set to ACCEPT"

            # Reload UFW
            print_step "Reloading UFW..."
            ufw reload 2>/dev/null
            print_success "UFW reloaded"
        else
            print_success "UFW forward policy already set to ACCEPT"
        fi
    fi

    return 0
}

# Remove UFW rules for Docker bridge networking
# Used during uninstallation or reconfiguration
# Only removes rules for the specified Docker subnet
remove_ufw_docker_rules() {
    local docker_subnet="${1:-}"

    # If no subnet provided, try to load from .env
    if [ -z "$docker_subnet" ]; then
        if [ -f "/opt/vless/.env" ]; then
            docker_subnet=$(grep '^DOCKER_SUBNET=' /opt/vless/.env 2>/dev/null | cut -d'=' -f2)
        fi
    fi

    if [ -z "$docker_subnet" ]; then
        print_error "Docker subnet not specified and could not be determined from .env"
        print_info "Usage: remove_ufw_docker_rules <subnet>"
        return 1
    fi

    # Check if UFW is installed
    if ! command_exists "ufw"; then
        print_info "UFW is not installed, no rules to remove"
        return 0
    fi

    # Check if UFW is active
    local ufw_status=$(ufw status 2>/dev/null | head -1)
    if ! echo "$ufw_status" | grep -q "active"; then
        print_info "UFW is not active, no rules to remove"
        return 0
    fi

    print_step "Removing UFW rules for Docker subnet: $docker_subnet..."

    # Find and delete rules containing the subnet
    # UFW rule numbers change after each deletion, so we delete in reverse order
    local rule_numbers=$(ufw status numbered 2>/dev/null | grep "$docker_subnet" | grep -oE '^\[[0-9]+\]' | tr -d '[]' | sort -rn)

    if [ -z "$rule_numbers" ]; then
        print_info "No UFW rules found for subnet $docker_subnet"
        return 0
    fi

    local removed=0
    for rule_num in $rule_numbers; do
        print_step "Removing UFW rule #$rule_num..."
        if echo "y" | ufw delete "$rule_num" >/dev/null 2>&1; then
            ((removed++))
            print_success "Removed rule #$rule_num"
        else
            print_warning "Failed to remove rule #$rule_num"
        fi
    done

    if [ $removed -gt 0 ]; then
        print_success "Removed $removed UFW rule(s) for $docker_subnet"
    else
        print_info "No rules were removed"
    fi

    return 0
}

# Configure UFW for Docker bridge networking
# Adds explicit FORWARD rules to allow Docker subnet traffic through UFW
# This is CRITICAL when UFW is active - without these rules, containers have no internet access
# even if DEFAULT_FORWARD_POLICY="ACCEPT" is set
configure_ufw_for_docker() {
    local docker_subnet="$1"

    # Validate input
    if [ -z "$docker_subnet" ]; then
        print_error "Docker subnet parameter is required"
        return 1
    fi

    # Validate subnet format (basic check for 172.X.0.0/16)
    if ! echo "$docker_subnet" | grep -qE '^172\.[0-9]{1,3}\.0\.0/1[0-9]$'; then
        print_error "Invalid Docker subnet format: $docker_subnet"
        print_info "Expected format: 172.X.0.0/16"
        return 1
    fi

    # Check if UFW is installed
    if ! command_exists "ufw"; then
        print_info "UFW is not installed, skipping Docker bridge configuration"
        return 0
    fi

    # Check if UFW is active
    local ufw_status=$(ufw status 2>/dev/null | head -1)
    if ! echo "$ufw_status" | grep -q "active"; then
        print_info "UFW is not active, skipping Docker bridge configuration"
        return 0
    fi

    print_step "Configuring UFW for Docker bridge network..."
    print_info "Adding FORWARD rules for subnet: $docker_subnet"

    # Check if rules already exist
    local existing_rules=$(ufw status numbered 2>/dev/null | grep -c "$docker_subnet" || echo "0")

    if [ "$existing_rules" -ge 2 ]; then
        print_success "UFW FORWARD rules for $docker_subnet already exist"
        return 0
    fi

    # Add UFW route rules for bidirectional traffic
    # These rules allow Docker bridge traffic to be forwarded through UFW
    print_step "Adding UFW route allow from $docker_subnet..."
    if ufw route allow from "$docker_subnet" 2>/dev/null; then
        print_success "UFW route allow from $docker_subnet added"
    else
        print_error "Failed to add UFW route allow from $docker_subnet"
        return 1
    fi

    print_step "Adding UFW route allow to $docker_subnet..."
    if ufw route allow to "$docker_subnet" 2>/dev/null; then
        print_success "UFW route allow to $docker_subnet added"
    else
        print_warning "Failed to add UFW route allow to $docker_subnet"
        # Don't fail - inbound rule is most critical
    fi

    # Verify rules were added
    print_step "Verifying UFW rules..."
    local new_rules=$(ufw status numbered 2>/dev/null | grep -c "$docker_subnet" || echo "0")

    if [ "$new_rules" -ge 1 ]; then
        print_success "UFW FORWARD rules configured successfully"
        print_info "Docker containers in $docker_subnet can now access internet through UFW"
        return 0
    else
        print_error "UFW rules verification failed"
        return 1
    fi
}

# Main function to configure all network settings for VLESS service
configure_network_for_vless() {
    local docker_subnet="$1"
    local server_port="${2:-443}"

    print_header "Configuring Network for VLESS Service"

    print_info "Network configuration approach:"
    print_info "  • Enable kernel modules and sysctl settings"
    print_info "  • Configure Docker daemon"
    print_info "  • Clean up conflicting manual NAT rules"
    print_info "  • Docker automatically manages iptables NAT rules"
    print_info "  • No manual iptables manipulation needed"
    echo ""

    # Step 1: Load br_netfilter module
    if ! load_br_netfilter; then
        print_error "Failed to load br_netfilter module"
        return 1
    fi

    # Step 2: Enable IP forwarding and bridge netfilter
    if ! enable_ip_forwarding; then
        print_error "Failed to enable IP forwarding"
        return 1
    fi

    # Step 3: Configure Docker daemon
    if ! configure_docker_daemon; then
        print_error "Failed to configure Docker daemon"
        return 1
    fi

    # Step 4: Clean up conflicting manual NAT rules (from other VPN services)
    clean_conflicting_nat_rules

    # Step 5: Configure firewall (if UFW is active)
    configure_firewall "$server_port"

    # Step 6: Configure UFW for Docker bridge (if UFW is active)
    # This adds explicit FORWARD rules to allow Docker subnet traffic through UFW
    # Without this, containers may have no internet access even with correct NAT configuration
    configure_ufw_for_docker "$docker_subnet"

    echo ""
    print_success "Network configuration completed successfully"
    print_info "Docker will automatically create NAT rules when containers start"

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

    # Check bridge netfilter
    local bridge_iptables=$(cat /proc/sys/net/bridge/bridge-nf-call-iptables 2>/dev/null || echo "0")
    if [ "$bridge_iptables" = "1" ]; then
        print_success "Bridge netfilter (iptables): enabled"
    else
        print_error "Bridge netfilter (iptables): disabled"
        ((errors++))
    fi

    # Check br_netfilter module
    if lsmod | grep -q "^br_netfilter"; then
        print_success "br_netfilter module: loaded"
    else
        print_error "br_netfilter module: not loaded"
        ((errors++))
    fi

    # Check Docker service
    if systemctl is-active --quiet docker; then
        print_success "Docker service: running"
    else
        print_error "Docker service: not running"
        ((errors++))
    fi

    # Check port availability
    if netstat -tuln 2>/dev/null | grep -q ":$server_port "; then
        print_success "Port $server_port: listening"
    else
        print_info "Port $server_port: not listening yet (service may not be started)"
    fi

    # Check Docker network (after containers start)
    if docker network ls 2>/dev/null | grep -q "vless-network"; then
        print_success "Docker network: exists"

        # Check if Docker created NAT rules
        if command_exists iptables && iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -q "$docker_subnet"; then
            print_success "Docker NAT rules: configured automatically"
        fi
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

# Clean up conflicting manual NAT rules
# Removes duplicate MASQUERADE rules that conflict with Docker-managed rules
clean_conflicting_nat_rules() {
    print_step "Checking for conflicting NAT rules..."

    # Get external interface
    local external_if=$(get_external_interface 2>/dev/null)
    if [ -z "$external_if" ]; then
        print_warning "Could not detect external interface, skipping NAT cleanup"
        return 0
    fi

    # Check if iptables is available
    if ! command_exists iptables; then
        print_info "iptables not found, skipping NAT cleanup"
        return 0
    fi

    # Count manual MASQUERADE rules for Docker subnets (172.x.0.0/16) via external interface
    local manual_rules=$(iptables -t nat -L POSTROUTING -n -v --line-numbers 2>/dev/null | \
        grep -E "MASQUERADE.*\*[[:space:]]+${external_if}[[:space:]]+172\.[0-9]+\.0\.0/1[0-9]" | \
        wc -l)

    if [ "$manual_rules" -eq 0 ]; then
        print_success "No conflicting manual NAT rules found"
        return 0
    fi

    print_warning "Found $manual_rules manual NAT rule(s) that may conflict with Docker"
    print_info "These rules are typically added by other VPN services or manual configuration"
    echo ""

    if ! confirm_action "Remove conflicting manual NAT rules?" "y"; then
        print_info "Keeping existing rules (may cause routing conflicts)"
        return 0
    fi

    # Remove duplicate rules (iterate in reverse to maintain line numbers)
    local removed=0
    while read -r line_num; do
        if iptables -t nat -D POSTROUTING "$line_num" 2>/dev/null; then
            ((removed++))
            print_success "Removed manual rule #$line_num"
        else
            print_warning "Failed to remove rule #$line_num"
        fi
        # After deletion, all subsequent line numbers shift down by 1
        # So we only delete the first matching rule in each iteration
    done < <(iptables -t nat -L POSTROUTING -n -v --line-numbers 2>/dev/null | \
        grep -E "MASQUERADE.*\*[[:space:]]+${external_if}[[:space:]]+172\.[0-9]+\.0\.0/1[0-9]" | \
        awk '{print $1}' | sort -rn)

    if [ $removed -gt 0 ]; then
        print_success "Removed $removed conflicting NAT rule(s)"
        print_info "Docker will recreate necessary rules automatically"
    else
        print_info "No rules were removed"
    fi

    return 0
}

# Detect other VPN services that may conflict with VLESS
# Returns 0 if no conflicts detected, 1 if potential conflicts found
detect_other_vpn_services() {
    print_step "Checking for other VPN services..."

    local conflicts_found=0
    local warnings=()

    # Check for VPN-related Docker containers
    print_info "Scanning Docker containers..."
    local vpn_containers=$(docker ps -a --format '{{.Names}}' 2>/dev/null | \
        grep -iE 'outline|openvpn|wireguard|shadowsocks|v2ray|xray|trojan' | \
        grep -v 'xray-server' || true)

    if [ -n "$vpn_containers" ]; then
        print_warning "Found other VPN containers:"
        echo "$vpn_containers" | while read container; do
            local status=$(docker ps --filter "name=$container" --format '{{.Status}}' 2>/dev/null || echo "stopped")
            echo "  - $container ($status)"
        done
        warnings+=("Other VPN Docker containers detected")
        conflicts_found=1
    fi

    # Check for existing manual NAT rules
    if command_exists iptables; then
        local external_if=$(get_external_interface 2>/dev/null)
        if [ -n "$external_if" ]; then
            local manual_nat_count=$(iptables -t nat -L POSTROUTING -n 2>/dev/null | \
                grep -c -E "MASQUERADE.*${external_if}.*172\.[0-9]+\.0\.0/1[0-9]" || echo "0")

            if [ "$manual_nat_count" -gt 0 ]; then
                print_warning "Found $manual_nat_count manual NAT rule(s) for Docker subnets"
                print_info "These rules may have been added by other VPN services"
                warnings+=("Manual NAT rules detected (count: $manual_nat_count)")
                conflicts_found=1
            fi
        fi
    fi

    # Check for VPN-related systemd services
    print_info "Checking systemd services..."
    local vpn_services=$(systemctl list-units --type=service --state=running 2>/dev/null | \
        grep -iE 'openvpn|wireguard|outline|ipsec|strongswan|l2tp' | \
        awk '{print $1}' || true)

    if [ -n "$vpn_services" ]; then
        print_warning "Found active VPN services:"
        echo "$vpn_services" | while read service; do
            echo "  - $service"
        done
        warnings+=("Active VPN systemd services detected")
        conflicts_found=1
    fi

    # Check Docker networks with 172.x subnets
    local docker_networks=$(docker network ls --format '{{.Name}}' 2>/dev/null | \
        grep -v 'bridge\|host\|none' || true)

    if [ -n "$docker_networks" ]; then
        local subnet_conflicts=0
        while read network; do
            local subnet=$(docker network inspect "$network" 2>/dev/null | \
                jq -r '.[0].IPAM.Config[0].Subnet // ""' 2>/dev/null || true)

            if [[ "$subnet" =~ ^172\. ]]; then
                ((subnet_conflicts++))
            fi
        done <<< "$docker_networks"

        if [ $subnet_conflicts -gt 0 ]; then
            print_info "Found $subnet_conflicts Docker network(s) using 172.x.x.x subnets"
        fi
    fi

    echo ""

    # Summary
    if [ $conflicts_found -eq 0 ]; then
        print_success "No VPN service conflicts detected"
        return 0
    else
        print_warning "Potential conflicts detected with other VPN services"
        echo ""
        print_info "This may cause routing issues. Recommendations:"
        echo "  • Stop conflicting VPN services before installation"
        echo "  • Or proceed with installation and clean up NAT rules automatically"
        echo "  • Use 'diagnose-vpn-conflicts.sh' for detailed analysis"
        echo ""

        return 1
    fi
}

# Display network configuration summary
display_network_summary() {
    local docker_subnet="$1"
    local docker_gateway="$2"
    local server_port="${3:-443}"

    print_header "Network Configuration Summary"

    echo "Docker Network:"
    echo "  Subnet:          $docker_subnet"
    echo "  Gateway:         $docker_gateway"
    echo ""
    echo "VLESS Service:"
    echo "  Port:            $server_port"
    echo ""
    echo "System:"
    echo "  IP Forward:      $(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 'unknown')"
    echo "  Bridge Netfilter: $(cat /proc/sys/net/bridge/bridge-nf-call-iptables 2>/dev/null || echo 'unknown')"
    echo "  br_netfilter:    $(lsmod | grep -q '^br_netfilter' && echo 'loaded' || echo 'not loaded')"
    echo "  Interface:       $(get_external_interface 2>/dev/null || echo 'auto-detect')"
    echo ""
    echo "NAT Management:"
    echo "  Docker automatically creates and manages iptables NAT rules"
    echo "  No manual intervention required"
    echo ""
}
