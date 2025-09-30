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

# Main function to configure all network settings for VLESS service
configure_network_for_vless() {
    local docker_subnet="$1"
    local server_port="${2:-443}"

    print_header "Configuring Network for VLESS Service"

    print_info "Network configuration approach:"
    print_info "  • Enable kernel modules and sysctl settings"
    print_info "  • Configure Docker daemon"
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

    # Step 4: Configure firewall (if UFW is active)
    configure_firewall "$server_port"

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
