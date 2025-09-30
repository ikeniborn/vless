# Installation Checklist

Complete checklist for VLESS+Reality installation on servers with existing VPN services or Docker containers.

## Pre-Installation Checks

### 1. System Requirements
```bash
# Check root access
sudo -v

# Check disk space (minimum 5GB in /opt)
df -h /opt | tail -1 | awk '{print $4}'

# Check if ports are available
sudo netstat -tlnp | grep -E ":(443|80)"

# Check system resources
free -h
```

### 2. Existing VPN Services Check
```bash
# Check for other VPN containers
docker ps -a | grep -iE "vpn|outline|openvpn|wireguard|shadowsocks"

# Check for manual iptables NAT rules
sudo iptables -t nat -L POSTROUTING -n -v --line-numbers | grep MASQUERADE

# Check Docker networks
docker network ls
docker network inspect $(docker network ls -q) 2>/dev/null | jq -r '.[] | select(.IPAM.Config[0].Subnet // "" | startswith("172.")) | "\(.Name): \(.IPAM.Config[0].Subnet)"'
```

### 3. Critical Kernel Settings
```bash
# These MUST all return 1
lsmod | grep br_netfilter          # Should show module
sysctl net.ipv4.ip_forward         # Should return 1
sysctl net.bridge.bridge-nf-call-iptables  # Should return 1

# If any fails, installation will configure them
```

## Installation Steps

### 1. Get Latest Code
```bash
cd ~/vless
git pull origin master

# Verify latest commits are present
git log --oneline -5 | grep -E "NAT|diagnostic|restart"
```

Expected output should include:
- `fix: Add Docker restart during installation`
- `fix: Prevent diagnostic script from exiting`
- `fix: Add -v flag to iptables`

### 2. Run Installation
```bash
sudo bash scripts/install.sh
```

**During installation, verify these steps happen:**
- ✅ "Restarting Docker to clear old NAT rules..."
- ✅ "Docker restarted with clean NAT rules"
- ✅ Network configuration completes successfully
- ✅ Container starts and health check passes

### 3. Post-Installation Verification

**IMMEDIATE CHECK (run right after installation):**
```bash
# Wait 10 seconds for network to stabilize
sleep 10

# Run diagnostic
sudo /opt/vless/scripts/diagnose-vpn-conflicts.sh
```

**Expected Results:**
```
Step 1: System Configuration Check
  ✓ IP forwarding is enabled
  ✓ br_netfilter module is loaded
  ✓ bridge-nf-call-iptables is enabled

Step 4: NAT Rules Analysis
  ✓ No conflicting manual NAT rules detected
  (Docker-managed rules should exist for correct subnet)

Step 6: Docker Container Connectivity Test
  ✓ DNS resolution: OK
  ✓ Internet connectivity: OK
```

### 4. Detailed Connectivity Test
```bash
# Test from container
sudo docker exec xray-server ping -c 3 8.8.8.8
sudo docker exec xray-server nslookup google.com 8.8.8.8

# Check NAT rules
sudo iptables -t nat -L POSTROUTING -n -v | grep $(cat /opt/vless/.env | grep DOCKER_SUBNET | cut -d'=' -f2 | cut -d'/' -f1)

# Verify bridge exists
ip link show | grep br-
```

## Troubleshooting

### Issue: Container Has No Internet After Installation

**Symptoms:**
```
✗ DNS resolution: FAILED
✗ Internet connectivity: FAILED
```

**Diagnostic Steps:**

#### Step 1: Check if problem is temporary
```bash
# Wait 30 seconds and retry
sleep 30
sudo docker exec xray-server ping -c 2 8.8.8.8
```

If now works: Network needed time to initialize (normal after Docker restart)

#### Step 2: Check NAT rules match network
```bash
# Get container subnet
CONTAINER_SUBNET=$(docker network inspect vless-reality_vless-network | jq -r '.[0].IPAM.Config[0].Subnet')
echo "Container subnet: $CONTAINER_SUBNET"

# Check NAT rule exists for this subnet
sudo iptables -t nat -L POSTROUTING -n -v | grep "$CONTAINER_SUBNET"
```

If no NAT rule found: Docker restart didn't work properly

**Fix:**
```bash
cd /opt/vless
sudo docker-compose down
sudo docker-compose -f docker-compose.fake.yml down 2>/dev/null || true
sudo systemctl restart docker
sleep 5
sudo docker-compose up -d
```

#### Step 3: Check for stale bridge references
```bash
# List NAT rules and bridges
sudo iptables -t nat -L POSTROUTING -n -v | grep MASQUERADE | grep "172\."
ip link show | grep "^[0-9]*: br-"

# Compare: Every NAT rule's bridge (br-XXXXX) must exist in ip link output
```

If NAT points to non-existent bridge: Old rules remain

**Fix:**
```bash
# Manual cleanup
sudo systemctl restart docker
cd /opt/vless && sudo docker-compose up -d
```

#### Step 4: Check for conflicting manual rules
```bash
# Should return 0
sudo iptables -t nat -L POSTROUTING -n -v --line-numbers | \
    grep -E "MASQUERADE.*ens1.*172\." | wc -l
```

If > 0: Other VPN service is interfering

**Fix:**
```bash
source /opt/vless/scripts/lib/{colors,utils,network}.sh
clean_conflicting_nat_rules
```

#### Step 5: Verify FORWARD chain
```bash
# Check policy
sudo iptables -L FORWARD -n | head -1
# Should be: Chain FORWARD (policy ACCEPT)

# Check UFW
sudo cat /etc/default/ufw | grep DEFAULT_FORWARD_POLICY
# Should be: DEFAULT_FORWARD_POLICY="ACCEPT"
```

If DROP or REJECT: Firewall blocking

**Fix:**
```bash
# Update UFW
sudo sed -i 's/DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
sudo ufw reload
sudo systemctl restart docker
```

#### Step 6: Check container routing
```bash
# Container should be able to ping gateway
sudo docker exec xray-server ping -c 2 172.19.0.1

# Check container route table
sudo docker exec xray-server ip route
# Should show: default via 172.19.0.1 dev eth0
```

If gateway ping fails: Docker network problem

**Fix:**
```bash
cd /opt/vless
sudo docker-compose down
sudo docker network rm vless-reality_vless-network
sudo docker-compose up -d
```

### Issue: Conflicting Manual NAT Rules Detected

**Symptoms:**
```
⚠ Found X manual NAT rule(s) that may conflict with Docker
```

**Cause:** Another VPN service (Outline, OpenVPN, etc.) added manual iptables rules

**Solution:**
```bash
# Option 1: Automated cleanup
source /opt/vless/scripts/lib/{colors,utils,network}.sh
clean_conflicting_nat_rules

# Option 2: Manual removal (example for rules 7-20)
for i in {20..7}; do sudo iptables -t nat -D POSTROUTING $i; done

# After cleanup
sudo systemctl restart docker
cd /opt/vless && docker-compose restart
```

### Issue: Network Initialization Delay

**Symptoms:**
- First diagnostic shows FAILED
- Second diagnostic (30s later) shows OK

**Cause:** Docker network needs time to fully initialize after restart

**Solution:** This is NORMAL and expected. Wait 30-60 seconds after installation before testing.

## Post-Installation Best Practices

### 1. Save Diagnostic Output
```bash
sudo /opt/vless/scripts/diagnose-vpn-conflicts.sh > ~/vless-diagnostic-$(date +%Y%m%d).txt
```

### 2. Document Server State
```bash
cat > ~/vless-installation-info.txt << EOF
Installation Date: $(date)
Server IP: $(cat /opt/vless/.env | grep SERVER_IP)
Docker Subnet: $(cat /opt/vless/.env | grep DOCKER_SUBNET)
NAT Rules Count: $(sudo iptables -t nat -L POSTROUTING -n | grep MASQUERADE | grep 172 | wc -l)
Other VPN Services: $(docker ps | grep -iE "vpn|outline|openvpn" | wc -l)
EOF
```

### 3. Test Client Connection
After installation completes:
1. Copy connection string from installation output
2. Configure client (v2rayNG, Shadowrocket, etc.)
3. Test real connection from client device
4. Verify can access websites and external services

## Critical Success Criteria

Installation is successful ONLY when ALL these are true:

- ✅ Diagnostic script completes all 7 steps without hanging
- ✅ Step 6 shows "DNS resolution: OK" and "Internet connectivity: OK"
- ✅ Container can ping 8.8.8.8
- ✅ Container can resolve google.com
- ✅ NAT rule exists for correct Docker subnet
- ✅ No conflicting manual NAT rules (or successfully cleaned up)
- ✅ Client device can connect and access internet through VPN

## Emergency Rollback

If installation fails completely and cannot be fixed:

```bash
# Stop and remove everything
cd /opt/vless
sudo docker-compose down
sudo docker-compose -f docker-compose.fake.yml down 2>/dev/null || true
sudo docker network rm vless-reality_vless-network 2>/dev/null || true
sudo docker network rm vless-reality_fake-net 2>/dev/null || true

# Remove installation
sudo rm -rf /opt/vless

# Clean up symlinks
sudo rm -f /usr/local/bin/vless-*
sudo rm -f /usr/bin/vless-*

# Restart Docker to clean NAT rules
sudo systemctl restart docker
```

Then investigate issue before reinstalling.

## Support

If problems persist after following this checklist:

1. Run full diagnostic: `sudo /opt/vless/scripts/diagnose-vpn-conflicts.sh > diagnostic.txt`
2. Collect system info:
   ```bash
   docker ps -a > docker-containers.txt
   docker network ls > docker-networks.txt
   sudo iptables -t nat -L POSTROUTING -n -v --line-numbers > nat-rules.txt
   sudo iptables -L FORWARD -n -v > forward-rules.txt
   ```
3. Review CLAUDE.md "Common Issues and Solutions" section
4. Check docs/VPN-CONFLICTS-SOLUTIONS.md for detailed troubleshooting
