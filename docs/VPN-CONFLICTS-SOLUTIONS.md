# VPN Conflicts Resolution Guide

This guide explains how to diagnose and resolve conflicts when running VLESS+Reality alongside other VPN services on the same server (such as Outline VPN, OpenVPN, WireGuard, etc.).

## Problem Overview

When multiple VPN services run on the same server, they can create conflicting iptables NAT rules that interfere with each other's routing. Common symptoms include:

- **Clients connect but cannot access internet** - Traffic routing is broken due to conflicting MASQUERADE rules
- **Duplicate NAT rules** - Multiple MASQUERADE rules for the same Docker subnet (as shown in diagnostic output)
- **Manual iptables rules interfering with Docker** - Other VPN services add manual rules that conflict with Docker-managed rules

**Example from real diagnostic output:**
```
Found 14 potentially conflicting manual rule(s)
Subnet 172.18.0.0/16 appears 10 times
Subnet 172.19.0.0/16 appears 5 times
```

## Understanding Docker NAT Management

### How Docker NAT Works

Docker automatically manages iptables NAT rules for bridge networks:

1. **Automatic MASQUERADE rules**: Docker creates rules like:
   ```
   -A POSTROUTING -s 172.X.0.0/16 ! -o br-XXXXX -j MASQUERADE
   ```
   These rules are created automatically when containers start and removed when they stop.

2. **Required kernel settings**:
   - `net.ipv4.ip_forward = 1` - Enables IP routing
   - `net.bridge.bridge-nf-call-iptables = 1` - **CRITICAL**: Allows bridge traffic through iptables
   - `br_netfilter` module loaded - Required for bridge netfilter to work

3. **No manual intervention needed**: Docker handles everything automatically if kernel settings are correct.

### Common Conflict Scenario

```bash
# GOOD: Docker-managed rule (automatic)
2  19877 1193K MASQUERADE  0  --  *  !br-24c7f5beb905  172.19.0.0/16  0.0.0.0/0

# BAD: Manual rules added by other VPN services (conflict)
7   0  0  MASQUERADE  0  --  *  ens1  172.18.0.0/16  0.0.0.0/0  (duplicate 1)
8   0  0  MASQUERADE  0  --  *  ens1  172.18.0.0/16  0.0.0.0/0  (duplicate 2)
9   0  0  MASQUERADE  0  --  *  ens1  172.19.0.0/16  0.0.0.0/0  (duplicate 3)
... (multiple duplicates)
```

Multiple rules for the same subnet cause routing confusion and can break connectivity.

## Diagnostic Tool

Run the diagnostic tool to analyze your server's network configuration:

```bash
# From repository directory
sudo ./scripts/diagnose-vpn-conflicts.sh

# Or if VLESS is already installed
sudo /opt/vless/scripts/diagnose-vpn-conflicts.sh
```

The tool will:
1. ✅ Check system configuration (IP forwarding, kernel modules, sysctl settings)
2. 🔍 Detect network interfaces
3. 🐳 Analyze Docker networks and their subnets
4. 📋 List all NAT rules and identify conflicts
5. ⚠️  Check for duplicate MASQUERADE rules
6. 🌐 Test connectivity from containers
7. 💡 Provide actionable recommendations

**Example output:**
```
Step 4: NAT Rules Analysis
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ℹ [Docker-managed rules (automatic)]
  2: 19877 1193K MASQUERADE  0  --  *  !br-24c7f5beb905  172.19.0.0/16  0.0.0.0/0

ℹ [Manual rules via external interface (may conflict)]
  7-20: Multiple MASQUERADE rules for 172.18.0.0/16 and 172.19.0.0/16

⚠ Found 14 potentially conflicting manual rule(s)
```

## Automatic Cleanup (Recommended)

### During Installation

The VLESS installation script automatically detects and offers to remove conflicting NAT rules:

```bash
sudo bash scripts/install.sh
```

During installation, the script will:
- Detect manual NAT rules for Docker subnets (172.x.0.0/16) via external interface
- Ask for confirmation to remove them
- Clean up conflicting rules before starting VLESS service

### For Existing Installation

If VLESS is already installed and you encounter conflicts:

1. **Source the network library**:
   ```bash
   source /opt/vless/scripts/lib/colors.sh
   source /opt/vless/scripts/lib/utils.sh
   source /opt/vless/scripts/lib/network.sh
   ```

2. **Run cleanup function**:
   ```bash
   clean_conflicting_nat_rules
   ```
   The function will:
   - Detect all manual MASQUERADE rules for Docker subnets via external interface
   - Show you the count and details
   - Ask for confirmation
   - Remove rules in reverse order (to maintain line number integrity)

3. **Restart services**:
   ```bash
   sudo systemctl restart docker
   cd /opt/vless && docker-compose restart
   ```

## Manual Cleanup

If you prefer manual control, follow these steps:

### Step 1: Identify Conflicting Rules

```bash
# List NAT rules with line numbers
sudo iptables -t nat -L POSTROUTING -n -v --line-numbers

# Filter manual rules for Docker subnets via external interface (e.g., ens1)
sudo iptables -t nat -L POSTROUTING -n -v --line-numbers | grep -E "MASQUERADE.*ens1.*172\."
```

Example output showing conflicts:
```
7   0   0 MASQUERADE  0    --  *      ens1    172.18.0.0/16        0.0.0.0/0
8   0   0 MASQUERADE  0    --  *      ens1    172.18.0.0/16        0.0.0.0/0
9   0   0 MASQUERADE  0    --  *      ens1    172.19.0.0/16        0.0.0.0/0
...
```

### Step 2: Remove Conflicting Rules

**IMPORTANT**: Remove rules in **reverse order** (highest line number first) to avoid line number shifts:

```bash
# Example: Remove rules #20, #19, #18, ... #7
sudo iptables -t nat -D POSTROUTING 20
sudo iptables -t nat -D POSTROUTING 19
sudo iptables -t nat -D POSTROUTING 18
# ... continue in reverse order ...
sudo iptables -t nat -D POSTROUTING 7
```

Or use a loop (be careful!):
```bash
# Remove all manual rules for 172.x subnets via ens1 (adjust interface name)
for i in $(sudo iptables -t nat -L POSTROUTING -n --line-numbers | \
           grep -E "MASQUERADE.*ens1.*172\." | \
           awk '{print $1}' | sort -rn); do
    sudo iptables -t nat -D POSTROUTING $i
    echo "Removed rule #$i"
done
```

### Step 3: Verify Cleanup

```bash
# Check remaining rules
sudo iptables -t nat -L POSTROUTING -n -v

# Should only see Docker-managed rules (with br-XXXXX interface)
# Example of correct rules:
# -A POSTROUTING -s 172.19.0.0/16 ! -o br-24c7f5beb905 -j MASQUERADE
```

### Step 4: Restart Services

```bash
# Restart Docker to recreate its rules
sudo systemctl restart docker

# Restart VLESS service
cd /opt/vless && docker-compose restart
```

### Step 5: Verify Connectivity

```bash
# Test from container
docker exec xray-server ping -c 2 8.8.8.8
docker exec xray-server nslookup google.com 8.8.8.8

# Both commands should succeed
```

## Prevention and Best Practices

### 1. Use Docker-Managed Rules Only

- ❌ **DO NOT** manually add iptables NAT rules for Docker subnets
- ✅ Let Docker manage its own iptables rules automatically
- ✅ Only configure kernel settings (sysctl) and firewall policies

### 2. Isolate VPN Services

If running multiple VPN services:

- ✅ **Use different Docker subnets** for each service
  - VLESS: 172.19.0.0/16
  - Outline: 172.20.0.0/16
  - Custom VPN: 172.21.0.0/16

- ✅ **Use different ports**
  - VLESS: 443
  - Outline: 9000-9999
  - Other VPN: Custom port

- ✅ **Separate Docker networks**
  - Each VPN service should have its own Docker network

### 3. Verify Kernel Settings

Ensure these settings are enabled **system-wide** (not per-service):

```bash
# Check current settings
sysctl net.ipv4.ip_forward                         # should return 1
sysctl net.bridge.bridge-nf-call-iptables          # should return 1
lsmod | grep br_netfilter                          # should show module loaded

# Verify persistent configuration (already done by VLESS installation)
cat /etc/sysctl.d/99-vless-network.conf
```

### 4. Use Firewall Policies, Not Rules

Instead of adding individual iptables rules:

- ✅ **Configure UFW forward policy** (done by VLESS installation):
  ```bash
  # Check UFW forward policy
  grep DEFAULT_FORWARD_POLICY /etc/default/ufw
  # Should be: DEFAULT_FORWARD_POLICY="ACCEPT"
  ```

- ✅ **Use port-specific rules only**:
  ```bash
  sudo ufw allow 443/tcp comment "VLESS VPN"
  ```

## Troubleshooting

### Issue: Internet Not Working After Cleanup

**Cause**: Docker rules not recreated properly

**Solution**:
```bash
# Restart Docker daemon
sudo systemctl restart docker

# Wait for Docker to initialize (2-3 seconds)
sleep 3

# Restart VLESS containers
cd /opt/vless && docker-compose down
docker-compose up -d

# Verify rules are created
sudo iptables -t nat -L POSTROUTING -n -v | grep "172\."
```

### Issue: Rules Reappear After Reboot

**Cause**: Other VPN service is adding rules on startup

**Solutions**:

1. **Identify which service is adding rules**:
   ```bash
   # Check systemd services
   systemctl list-units --type=service | grep -E "vpn|outline|openvpn"

   # Check Docker containers
   docker ps -a
   ```

2. **Stop conflicting service temporarily**:
   ```bash
   sudo systemctl stop <vpn-service>
   ```

3. **Reconfigure other VPN service**:
   - Update its configuration to use different subnet
   - Disable its iptables management (if possible)
   - Check its documentation for NAT rule configuration

### Issue: Docker Not Creating Rules

**Cause**: Missing kernel modules or sysctl settings

**Solution**:
```bash
# Load br_netfilter module
sudo modprobe br_netfilter
echo "br_netfilter" | sudo tee /etc/modules-load.d/br_netfilter.conf

# Enable bridge netfilter
sudo sysctl -w net.bridge.bridge-nf-call-iptables=1
sudo sysctl -w net.ipv4.ip_forward=1

# Make persistent
sudo tee /etc/sysctl.d/99-vless-network.conf << EOF
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

# Apply settings
sudo sysctl -p /etc/sysctl.d/99-vless-network.conf

# Restart Docker
sudo systemctl restart docker
```

## Technical Details

### Why Manual Rules Cause Problems

1. **Multiple MASQUERADE rules for same subnet** create ambiguity:
   - Packets may be processed by wrong rule
   - Source NAT translation becomes unpredictable
   - Return traffic routing fails

2. **Interface-specific rules (e.g., -o ens1)** conflict with Docker's dynamic rules:
   - Docker uses bridge interfaces (br-XXXXX) that change
   - Static interface rules don't adapt to Docker network changes
   - Traffic may bypass Docker's connection tracking

3. **Order matters in iptables**:
   - First matching rule wins
   - Manual rules often inserted before Docker rules
   - Breaks Docker's routing logic

### Docker's NAT Rule Pattern

Correct Docker-managed rule structure:
```
-A POSTROUTING -s <docker-subnet> ! -o <docker-bridge> -j MASQUERADE
```

Key components:
- **-s <docker-subnet>**: Source is container network (e.g., 172.19.0.0/16)
- **! -o <docker-bridge>**: NOT going to Docker bridge (going outside)
- **-j MASQUERADE**: NAT the source IP to host IP

This rule says: "For traffic from containers going outside Docker network, translate source IP to host IP."

## References

- **CLAUDE.md**: Section "Network Configuration and VPN Routing"
- **scripts/lib/network.sh**: Function `clean_conflicting_nat_rules()`
- **scripts/lib/network.sh**: Function `configure_network_for_vless()`
- **scripts/diagnose-vpn-conflicts.sh**: Full diagnostic tool

## Getting Help

If problems persist after following this guide:

1. **Run diagnostic tool** and save output:
   ```bash
   sudo /opt/vless/scripts/diagnose-vpn-conflicts.sh > diagnostic-report.txt
   ```

2. **Check VLESS logs**:
   ```bash
   sudo tail -50 /opt/vless/logs/error.log
   ```

3. **Check Docker logs**:
   ```bash
   cd /opt/vless && docker-compose logs --tail 50
   ```

4. **Report issue** with diagnostic output at project repository

## Quick Reference Commands

```bash
# Run diagnostic
sudo /opt/vless/scripts/diagnose-vpn-conflicts.sh

# Automated cleanup
source /opt/vless/scripts/lib/{colors,utils,network}.sh
clean_conflicting_nat_rules

# Manual cleanup (example for rules 7-20)
for i in {20..7}; do sudo iptables -t nat -D POSTROUTING $i; done

# Restart services
sudo systemctl restart docker
cd /opt/vless && docker-compose restart

# Verify connectivity
docker exec xray-server ping -c 2 8.8.8.8
docker exec xray-server nslookup google.com 8.8.8.8

# Check NAT rules
sudo iptables -t nat -L POSTROUTING -n -v --line-numbers
```
