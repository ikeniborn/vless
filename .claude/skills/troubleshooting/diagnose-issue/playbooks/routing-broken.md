# Playbook: Routing Broken

**Issue ID:** `routing_broken`
**Category:** Routing
**Severity:** HIGH

---

## Symptoms

- 503 Service Unavailable for reverse proxy subdomain
- HAProxy stats show backend down
- Reverse proxy domains not accessible
- VLESS Reality works but reverse proxy doesn't

---

## Diagnostic Commands

### 1. Check HAProxy Stats

```bash
curl http://127.0.0.1:9000/stats | grep -E 'UP|DOWN'
```

**Expected:** All backends show "UP"
**Common error:** nginx_reverseproxy backend shows "DOWN"

### 2. Check HAProxy Logs

```bash
docker logs vless_haproxy --tail 50 | grep -i 'error\|refused\|timeout'
```

**Look for:**
- Connection refused to backend
- Backend timeout
- No backend available

### 3. Check Dynamic Reverse Proxy Routes

```bash
grep 'DYNAMIC_REVERSE_PROXY_ROUTES' /opt/vless/config/haproxy.cfg
```

**Expected:** Section exists with ACL rules for reverse proxy domains
**Common error:** Section missing or empty

### 4. Check Nginx Reverse Proxy Container

```bash
docker ps | grep vless_nginx_reverseproxy
docker logs vless_nginx_reverseproxy --tail 30
```

**Expected:** Container running and healthy
**Common error:** Container in restart loop or crashed

### 5. Test Nginx Backend Directly

```bash
curl -I http://127.0.0.1:9443
```

**Expected:** HTTP 200 or 404 from nginx
**Common error:** Connection refused (nginx not listening)

---

## Common Causes & Fixes

### Cause 1: HAProxy Config Not Reloaded After Adding Domain

**Explanation:**
Dynamic ACLs require HAProxy graceful reload to take effect. Simply adding domain to config without reload won't work.

**Fix:**

```bash
# 1. Validate HAProxy config first
docker exec vless_haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg

# Expected: "Configuration file is valid"

# 2. Graceful reload HAProxy
docker exec vless_haproxy kill -HUP $(docker exec vless_haproxy cat /var/run/haproxy.pid)

# Alternative method:
docker exec vless_haproxy sh -c 'kill -HUP $(cat /var/run/haproxy.pid)'

# 3. Wait 2 seconds for reload
sleep 2

# 4. Test routing
curl -I https://your-reverse-proxy-domain.com

# Expected: HTTP 200 or 301 (not 503)

# 5. Verify in HAProxy stats
curl http://127.0.0.1:9000/stats | grep your-domain
```

---

### Cause 2: Nginx Reverse Proxy Backend Not Running

**Explanation:**
`vless_nginx_reverseproxy` container crashed or unhealthy. HAProxy can't forward traffic to down backend.

**Diagnostic:**

```bash
docker ps | grep vless_nginx_reverseproxy
docker logs vless_nginx_reverseproxy --tail 30 | grep -i error
```

**Fix:**

```bash
# 1. Check nginx config syntax
docker exec vless_nginx_reverseproxy nginx -t

# Expected: "syntax is ok" and "test is successful"

# 2. If syntax error, fix nginx config files in:
# /opt/vless/config/reverse-proxy/

# 3. Restart nginx container
docker restart vless_nginx_reverseproxy

# 4. Wait for health check
sleep 5

# 5. Verify healthy
docker ps | grep vless_nginx_reverseproxy

# Expected: (healthy)

# 6. Test backend directly
curl -I http://127.0.0.1:9443

# Expected: HTTP response from nginx
```

---

### Cause 3: Missing Dynamic ACL in HAProxy Config

**Explanation:**
`DYNAMIC_REVERSE_PROXY_ROUTES` section missing or corrupted in haproxy.cfg.

**Diagnostic:**

```bash
grep -A 5 'DYNAMIC_REVERSE_PROXY_ROUTES' /opt/vless/config/haproxy.cfg
```

**Fix:**

```bash
# 1. Regenerate HAProxy config
sudo vless-proxy add your-domain.com https://upstream-backend:port

# This command:
# - Adds ACL to haproxy.cfg
# - Generates nginx reverse proxy config
# - Reloads HAProxy
# - Creates rate limit zone

# 2. Verify ACL added
grep -A 10 'DYNAMIC_REVERSE_PROXY_ROUTES' /opt/vless/config/haproxy.cfg | grep your-domain

# Expected: ACL rule for your domain

# 3. Test routing
curl -I https://your-domain.com
```

---

### Cause 4: Nginx Rate Limit Zone Missing (Crash Loop)

**Explanation:**
Each reverse proxy domain needs its own `limit_req_zone` directive in nginx http_context.conf. If missing, nginx fails to start.

**Diagnostic:**

```bash
docker logs vless_nginx_reverseproxy --tail 20 | grep 'limit_req_zone\|emerg'
```

**Fix:**

```bash
# 1. Set domain variable
DOMAIN="your-domain.com"

# 2. Generate zone name
ZONE_NAME="reverseproxy_${DOMAIN//[.-]/_}"

# 3. Add rate limit zone to http_context.conf
sudo bash -c "cat >> /opt/vless/config/reverse-proxy/http_context.conf << EOF

# Rate limit zone for: ${DOMAIN}
limit_req_zone \\\$binary_remote_addr zone=${ZONE_NAME}:10m rate=100r/s;
EOF"

# 4. Validate nginx config
docker exec vless_nginx_reverseproxy nginx -t

# Expected: "syntax is ok"

# 5. Restart nginx
docker restart vless_nginx_reverseproxy

# 6. Verify healthy
docker ps | grep vless_nginx_reverseproxy
```

---

### Cause 5: TLS Certificate Missing for Reverse Proxy Domain

**Explanation:**
HAProxy requires combined.pem (fullchain + privkey) for TLS termination. If certificate missing or expired, routing fails.

**Diagnostic:**

```bash
DOMAIN="your-reverse-proxy-domain.com"
ls -lh /etc/letsencrypt/live/$DOMAIN/combined.pem
```

**Fix:**

```bash
# 1. Obtain certificate for reverse proxy domain
sudo certbot certonly --standalone -d your-reverse-proxy-domain.com

# 2. Create combined.pem
sudo bash -c "cat /etc/letsencrypt/live/$DOMAIN/fullchain.pem \
                  /etc/letsencrypt/live/$DOMAIN/privkey.pem \
                  > /etc/letsencrypt/live/$DOMAIN/combined.pem"

# 3. Set permissions
sudo chmod 644 /etc/letsencrypt/live/$DOMAIN/combined.pem

# 4. Reload HAProxy
docker exec vless_haproxy kill -HUP $(docker exec vless_haproxy cat /var/run/haproxy.pid)

# 5. Test HTTPS
curl -I https://your-reverse-proxy-domain.com
```

---

## Prevention

1. **Always use vless-proxy CLI:**
   ```bash
   sudo vless-proxy add domain.com https://backend:port
   ```
   This ensures all configs (HAProxy ACL, nginx reverse proxy, rate limit zones) are generated correctly.

2. **Monitor HAProxy stats regularly:**
   ```bash
   curl http://127.0.0.1:9000/stats | grep -E 'DOWN|MAINT'
   ```

3. **Set up health checks** for all backends in HAProxy config

4. **Validate configs before reload:**
   ```bash
   haproxy -c -f /opt/vless/config/haproxy.cfg
   nginx -t
   ```

5. **Keep certificates up to date** with auto-renewal

---

## Related Issues

- **container_unhealthy** - If nginx_reverseproxy container failing
- **cert_renewal_failed** - If TLS certificate expired or missing
