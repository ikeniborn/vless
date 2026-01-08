# Playbook: Container Unhealthy

**Issue ID:** `container_unhealthy`
**Category:** Container
**Severity:** CRITICAL

---

## Symptoms

- docker ps shows `(unhealthy)` for vless_xray or other container
- Health check failing repeatedly
- HAProxy logs show "Connection refused"
- Service unavailable despite container running

---

## Diagnostic Commands

### 1. Check Container Health Status

```bash
docker inspect vless_xray | jq '.[0].State.Health'
docker inspect vless_haproxy | jq '.[0].State.Health'
docker inspect vless_nginx_reverseproxy | jq '.[0].State.Health'
```

**Expected:** `"Status": "healthy"`
**If unhealthy:** Check FailingStreak and LastOutput

### 2. Check Container Logs

```bash
docker logs vless_xray --tail 50 | grep -i 'error\|fail\|fatal'
docker logs vless_haproxy --tail 50 | grep -i 'error\|fail\|fatal'
```

**Look for:**
- Port binding errors
- Configuration syntax errors
- Connection refused to backends

### 3. Verify Xray Listening Port

```bash
docker exec vless_xray netstat -tulnp | grep xray
```

**Expected:** Xray listening on port 8443 (internal)
**Common error:** Xray listening on 443 (wrong port)

### 4. Verify Xray Configuration

```bash
jq '.inbounds[] | select(.protocol=="vless") | .port' /opt/vless/config/xray_config.json
```

**Expected:** `8443`
**Common error:** `443` (needs fix)

### 5. Check Fallback Destination

```bash
jq '.inbounds[] | select(.protocol=="vless") | .settings.fallbacks[] | .dest' /opt/vless/config/xray_config.json
```

**Expected:** `"vless_fake_site:80"`
**Common error:** `"vless_nginx:80"` (wrong container name)

---

## Common Causes & Fixes

### Cause 1: Xray Wrong Port (443 instead of 8443)

**Explanation:**
v4.3+ architecture requires Xray on internal port 8443. HAProxy listens on public port 443 and forwards to Xray:8443. If Xray tries to bind to 443, it conflicts with HAProxy.

**Fix:**

```bash
# 1. Fix Xray config
sudo sed -i 's/"port": 443,/"port": 8443,/' /opt/vless/config/xray_config.json

# 2. Validate config
xray test -c /opt/vless/config/xray_config.json

# 3. Restart Xray
docker restart vless_xray

# 4. Wait 10 seconds for health check
sleep 10

# 5. Verify healthy
docker ps | grep vless_xray
```

**Expected:** Container should show `(healthy)` after restart

**Validation:**
```bash
docker exec vless_xray netstat -tulnp | grep :8443
```

---

### Cause 2: Wrong Fallback Destination

**Explanation:**
Fallback must point to `vless_fake_site:80`, not `vless_nginx:80`. Container name changed in v4.3+.

**Fix:**

```bash
# 1. Fix fallback destination
sudo sed -i 's/"dest": "vless_nginx:80"/"dest": "vless_fake_site:80"/' /opt/vless/config/xray_config.json

# 2. Validate config
xray test -c /opt/vless/config/xray_config.json

# 3. Restart Xray
docker restart vless_xray

# 4. Verify fallback works
curl -I http://vless_fake_site
```

**Expected:** Fallback site returns HTTP 200

---

### Cause 3: Missing Health Check Endpoint

**Explanation:**
Health check tries to connect but endpoint doesn't exist or is misconfigured.

**Fix:**

```bash
# 1. Check health check definition
docker inspect vless_xray | jq '.[0].Config.Healthcheck'

# 2. Manually test health check
docker exec vless_xray sh -c "command from healthcheck"

# 3. If health check command wrong, rebuild container
# (requires docker-compose.yml modification)
```

---

## Prevention

1. **Always use vless CLI commands** to modify configuration
2. **Run validation before restart:**
   ```bash
   xray test -c /opt/vless/config/xray_config.json
   ```
3. **Check HAProxy routing rules** match Xray internal port (8443)
4. **Monitor health checks:**
   ```bash
   docker ps --format "table {{.Names}}\t{{.Status}}"
   ```

---

## Related Issues

- **port_conflict** - If port 443 already in use by another service
- **routing_broken** - If HAProxy can't reach Xray backend
