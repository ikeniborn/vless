# MTProxy Documentation

**Status:** IMPLEMENTED (v5.33)
**Binary:** mtg v2.2.3 (nineseconds/mtg)
**Last Updated:** 2026-03-23

---

## Overview

MTProxy allows Telegram clients to connect through the VPN server using the MTProto
proxy protocol. It runs as a supervised process inside the `familytraffic` container
(alongside Nginx, Xray, and Certbot).

**Key characteristics:**
- FakeTLS mode — mirrors a real TLS certificate (www.google.com) to bypass DPI
- Active probing protection — invalid connections are forwarded to Nginx (real LE cert)
- IPv4-only configuration — avoids IPv6 connectivity failures on single-stack VPS
- UDP DNS — bypasses DoH (required because mtg v2.1.x used HTTP/1.1 which Quad9 rejects)
- Tolerates clock skew up to 3 minutes (ISP may block UDP/123 NTP)

---

## Architecture

```
Client (Telegram)
  └─ TCP:2053 ──► mtg v2 (FakeTLS) ──► Telegram DCs (direct)
                       │
                       └─ Active probe ──► Nginx:443 (LE cert, real HTTPS)
```

mtg runs inside the single `familytraffic` container, managed by supervisord.
There is no separate MTProxy container.

**Port:** `2053/tcp` (public, binds to `0.0.0.0`)

---

## Configuration

**File:** `/opt/familytraffic/config/mtproxy/mtg.toml`

```toml
debug = false
secret = "ee<38-hex-chars>"       # FakeTLS secret (ee prefix)

bind-to = "0.0.0.0:2053"

# prefer-ip MUST be at top level (not under [network])
prefer-ip = "prefer-ipv4"

# Tolerate ISP-blocked NTP (UDP/123); default 5s is too strict
tolerate-time-skewness = "3m"

[network]
  # UDP DNS bypasses DoH; DoH in mtg <2.1.12 uses HTTP/1.1 which Quad9 rejects
  dns = "udp://8.8.8.8"

[network.timeout]
  tcp = "5s"

[cloak]
  # Active probing protection: forward probes to Nginx (real TLS cert)
  port = <MTG_CLOAK_PORT>
```

**Generator:** `lib/mtproxy_manager.sh::generate_mtg_toml()`

---

## Client Connection Link

```
tg://proxy?server=<SERVER_IP>&port=2053&secret=<SECRET>
```

The `secret` field encodes both the FakeTLS domain and the authentication secret:
- Format: `ee` + 32-hex-byte secret + hex-encoded fake domain (www.google.com)
- Example: `eead8dc205ed7dfb22839c374a201d4d9b7777772e676f6f676c652e636f6d`
  - `ee` — FakeTLS prefix
  - `ad8dc205ed7dfb22839c374a201d4d9b` — 32-byte hex secret
  - `7777772e676f6f676c652e636f6d` — hex("www.google.com")

**Show current link:**
```bash
sudo familytraffic-mtproxy show-link
```

---

## CLI Commands

```bash
# Setup (called from install.sh or manually)
sudo familytraffic-mtproxy setup

# Show status
sudo familytraffic-mtproxy status

# Show connection link
sudo familytraffic-mtproxy show-link

# View logs
sudo familytraffic-mtproxy logs

# Reload (after TOML changes)
docker exec familytraffic supervisorctl restart mtg
```

---

## Known Issues & Fixes

### DoH failure: `cannot find any ips for tcp:www.google.com`

**Cause:** mtg v2.1.7 used HTTP/1.1 for DoH. Quad9 (9.9.9.9) requires HTTP/2 per
RFC 8484 §5.2 and returns `400 Bad Request`.

**Fix:** Use `dns = "udp://8.8.8.8"` under `[network]` (requires mtg >= 2.1.12)
**OR** upgrade to mtg v2.2.3 (both fix is applied).

---

### prefer-ip in wrong TOML section

**Cause:** `prefer-ip` placed under `[network]` — silently ignored.

**Fix:** Must be at **top level** of the TOML file. Not under any section header.

---

### Clock skew: `timestamp is too old Xm Xs`

**Cause:** Server clock drifts when ISP blocks UDP/123 (NTP). Default
`tolerate-time-skewness = 5s` is too strict for >5s drift.

**Detection:**
```bash
# Enable debug mode temporarily
docker exec familytraffic supervisorctl stop mtg
# Edit /opt/familytraffic/config/mtproxy/mtg.toml: set debug = true
docker exec familytraffic supervisorctl start mtg
docker exec familytraffic supervisorctl tail -f mtg
```

**Fix:** Set `tolerate-time-skewness = "3m"` at top level.

**Fix NTP (if UDP/123 is blocked):**
```bash
# Check if chrony can sync
chronyc tracking
# Try NTP over TCP or HTTP-based time sync if UDP/123 blocked
```

---

## Dockerfile

MTProxy binary is fetched at build time from GitHub releases:

```dockerfile
ARG MTG_VERSION=2.2.3
ARG MTG_ARCH=amd64

FROM alpine:latest AS mtg-src
RUN apk add --no-cache curl && \
    curl -fL \
    "https://github.com/9seconds/mtg/releases/download/v${MTG_VERSION}/mtg-${MTG_VERSION}-linux-${MTG_ARCH}.tar.gz" \
    | tar -xz --strip-components=1 -C /tmp && \
    install -m 755 /tmp/mtg /usr/bin/mtg
```

To update the binary without rebuilding the image:
```bash
# Download new binary
curl -fL "https://github.com/9seconds/mtg/releases/download/v2.2.3/mtg-2.2.3-linux-amd64.tar.gz" \
  | tar -xz --strip-components=1 -C /tmp
chmod +x /tmp/mtg

# Copy into running container
docker cp /tmp/mtg familytraffic:/usr/bin/mtg

# Restart mtg process
docker exec familytraffic supervisorctl restart mtg
```

---

## References

- **mtg v2 source:** https://github.com/9seconds/mtg
- **mtg releases:** https://github.com/9seconds/mtg/releases
- **MTProto protocol:** https://core.telegram.org/mtproto
- **Config generator:** `lib/mtproxy_manager.sh`
- **Project CLAUDE.md:** `CLAUDE.md`

---

## Document History

| Version | Date | Notes |
|---------|------|-------|
| 2.0 | 2026-03-23 | Rewritten to reflect actual implementation (mtg v2.2.3) |
| 1.1 | 2025-11-08 | Planning doc v6.0+v6.1 (superseded) |
| 1.0 | 2025-11-07 | Initial planning doc (superseded) |
