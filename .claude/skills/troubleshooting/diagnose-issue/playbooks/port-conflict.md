# Playbook: Port Conflict

**Issue ID:** `port_conflict`
**Category:** Networking
**Severity:** CRITICAL

---

## Symptoms

- Installation fails with "port is already allocated"
- Error: "bind: address already in use"
- `docker-compose up` fails to start HAProxy
- Container exits immediately after start

---

## Diagnostic Commands

### 1. Check Port 443 (HTTPS/TLS)

```bash
sudo ss -tulnp | grep :443
```

**Expected:** Empty (port free) OR only `vless_haproxy`
**Common conflict:** nginx, apache2, another web server

### 2. Check Port 1080 (SOCKS5)

```bash
sudo ss -tulnp | grep :1080
```

**Expected:** Empty OR only `vless_haproxy`

### 3. Check Port 8118 (HTTP Proxy)

```bash
sudo ss -tulnp | grep :8118
```

**Expected:** Empty OR only `vless_haproxy`

### 4. Check Port 8443 (MTProxy public / Xray internal)

```bash
sudo ss -tulnp | grep :8443
```

**Expected:** Empty OR only `vless_mtproxy` (if MTProxy enabled)
**Note:** Xray uses 8443 internally (not bound to 0.0.0.0)

### 5. Alternative Method (lsof)

```bash
sudo lsof -i :443
sudo lsof -i :1080
sudo lsof -i :8118
```

**Output shows:** PID, process name, user

### 6. Check for Old VLESS Containers

```bash
docker ps -a | grep vless
```

**Look for:** Stopped or exited vless_* containers that might still hold ports

---

## Common Causes & Fixes

### Cause 1: Existing Web Server on Port 443

**Explanation:**
System-wide nginx or apache2 installed and running, conflicts with HAProxy.

**Fix for Nginx:**

```bash
# 1. Check nginx status
sudo systemctl status nginx

# 2. Stop nginx
sudo systemctl stop nginx

# 3. Disable nginx auto-start
sudo systemctl disable nginx

# 4. Verify port free
sudo ss -tulnp | grep :443

# Expected: Empty output
```

**Fix for Apache2:**

```bash
# 1. Check apache2 status
sudo systemctl status apache2

# 2. Stop apache2
sudo systemctl stop apache2

# 3. Disable apache2
sudo systemctl disable apache2

# 4. Verify port free
sudo ss -tulnp | grep :443
```

**Alternative (if web server needed for other purposes):**

```bash
# Change web server to listen on different port (e.g., 8080)
# OR use alternative ports for VLESS (8443, 2053)
```

---

### Cause 2: Old VLESS Installation Not Cleaned Up

**Explanation:**
Previous VLESS containers still exist (stopped or running), holding port bindings.

**Fix:**

```bash
# 1. List all VLESS containers (including stopped)
docker ps -a | grep vless

# 2. Stop all VLESS containers
docker stop $(docker ps -q --filter 'name=vless')

# 3. Remove all VLESS containers
docker rm $(docker ps -aq --filter 'name=vless')

# 4. Verify no vless containers
docker ps -a | grep vless

# Expected: Empty output
```

**Clean Docker network (if needed):**

```bash
# Remove VLESS network
docker network rm vless_reality_net

# Verify removal
docker network ls | grep vless
```

---

### Cause 3: UFW Blocking Docker (Edge Case)

**Explanation:**
UFW rules preventing Docker from binding ports (rare, but possible).

**Diagnostic:**

```bash
sudo ufw status verbose
```

**Fix:**

```bash
# Allow VLESS ports
sudo ufw allow 443/tcp
sudo ufw allow 1080/tcp
sudo ufw allow 8118/tcp
sudo ufw allow 8443/tcp  # If MTProxy enabled

# Reload UFW
sudo ufw reload

# Verify rules
sudo ufw status numbered
```

---

### Cause 4: Port Already in Use by Docker Container

**Explanation:**
Non-VLESS Docker container using the same port.

**Diagnostic:**

```bash
# Find container using port 443
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep 443
```

**Fix:**

```bash
# Option 1: Stop conflicting container
docker stop <container_name>

# Option 2: Reconfigure container to use different port
# (requires modifying that container's docker-compose.yml)
```

---

## Prevention

1. **Run installation script port check** before installation:
   ```bash
   sudo ss -tulnp | grep -E ':(443|1080|8118|8443)'
   ```
   Expected: All empty

2. **Use alternative ports** if 443 unavailable:
   - HAProxy HTTPS: 8443 or 2053
   - SOCKS5: 1081
   - HTTP Proxy: 8119

3. **Clean up old installations** before reinstalling:
   ```bash
   docker stop $(docker ps -q --filter 'name=vless')
   docker rm $(docker ps -aq --filter 'name=vless')
   ```

4. **Disable system web servers** if not needed:
   ```bash
   sudo systemctl disable nginx apache2
   ```

---

## Related Issues

- **container_unhealthy** - If port conflict causes container to fail health checks
- **ufw_blocks_docker** - If UFW rules prevent port binding
