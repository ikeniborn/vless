# mtproxy_manager

> **Module:** `lib` | **File:** `lib/mtproxy_manager.sh` | **Version:** `7.0.0`

MTProxy management system for Telegram proxy functionality. Handles MTProxy configuration via mtg v2 (nineseconds/mtg), supervisord lifecycle inside the familytraffic single container, UFW rules, and nginx cloak-port.

**Updated:** 2026-03-12

---

## Overview

Version 7.0 migrates from a standalone Docker container (`familytraffic_mtproxy`) to running mtg v2 directly inside the `familytraffic` container managed by supervisord. Legacy container-based functions are retained for backward compatibility.

**Key changes from v6.x:**
- Default port changed from `8443` to `2053` (avoids conflict with Xray on `127.0.0.1:8443`)
- New `generate_mtg_toml()` replaces standalone Docker image configuration
- mtg v2 Fake TLS requires an `ee`-prefixed secret
- Active probing protection via nginx cloak-port `4443` (loopback-only, not opened in UFW)

---

## Constants

| Constant | Default | Description |
|----------|---------|-------------|
| `MTPROXY_PORT` | `2053` | Public MTProxy port (Fake TLS) |
| `MTPROXY_STATS_PORT` | `8888` | Legacy stats endpoint port |
| `MTPROXY_CONTAINER` | `familytraffic_mtproxy` | Legacy standalone container name |
| `FAMILYTRAFFIC_CONTAINER` | `familytraffic` | Main container (supervisord-managed mtg) |
| `MTG_CONFIG_FILE` | `${MTPROXY_CONFIG_DIR}/mtg.toml` | mtg v2 configuration file |
| `MTG_CLOAK_PORT` | `4443` | Internal nginx cloak-port for active probing protection |

---

## Functions

### mtproxy_init

Initialize MTProxy directory structure and base configuration.

**Parameters:**

| # | Name | Default | Description |
|---|------|---------|-------------|
| `$1` | `port` | `8443` | MTProxy port (legacy config) |
| `$2` | `workers` | `2` | Worker count (legacy config) |

**Returns:** `0` on success, `1` on failure

**Example:**
```bash
mtproxy_init 2053
```

**Creates:**
- `${MTPROXY_CONFIG_DIR}/` — configuration directory
- `${MTPROXY_DATA_DIR}/` — data directory
- `${MTPROXY_LOGS_DIR}/` — logs directory
- `${MTPROXY_SECRETS_JSON}` — empty secrets.json (if not exists)
- `proxy-multi.conf` — Telegram DC addresses

---

### mtproxy_start

Start MTProxy. Uses supervisorctl inside the `familytraffic` container (v7.0). Falls back to Docker container if supervisorctl is unavailable.

**Returns:** `0` on success, `1` on failure

**Example:**
```bash
mtproxy_start
```

---

### mtproxy_stop

Stop MTProxy. Uses supervisorctl inside the `familytraffic` container (v7.0). Falls back to Docker container stop.

**Returns:** `0` on success, `1` on failure

**Example:**
```bash
mtproxy_stop
```

---

### mtproxy_restart

Restart MTProxy via supervisorctl or legacy container.

**Returns:** `0` on success, `1` on failure

**Example:**
```bash
mtproxy_restart
```

---

### mtproxy_status

Show MTProxy status. Displays supervisord status (v7.0) or legacy container status.

**Returns:** `0` on success, `1` on failure

**Example:**
```bash
mtproxy_status
```

---

### mtproxy_get_stats

Retrieve MTProxy statistics from the stats endpoint (legacy container feature).

**Returns:** `0` on success, `1` on failure

**Example:**
```bash
mtproxy_get_stats
```

---

### generate_mtproxy_config

Generate `mtproxy_config.json` via heredoc. **Legacy function — kept for compatibility with v6.x deployments.**

**Parameters:**

| # | Name | Default | Description |
|---|------|---------|-------------|
| `$1` | `port` | `8443` | MTProxy port |
| `$2` | `workers` | `2` | Worker count |

**Returns:** `0` on success, `1` on failure

**Example:**
```bash
generate_mtproxy_config 2053 2
```

---

### generate_mtproxy_secret_file

Generate `proxy-secret` file from `secrets.json`. **Legacy function — kept for compatibility.**

Supports both v6.0 (single secret) and v6.1 (multi-user, one secret per line) formats.

**Returns:** `0` on success, `1` on failure

**Example:**
```bash
generate_mtproxy_secret_file
```

---

### generate_proxy_multi_conf

Generate `proxy-multi.conf` with Telegram Data Center addresses. **Legacy function — kept for compatibility.**

**Returns:** `0` on success, `1` on failure

**Example:**
```bash
generate_proxy_multi_conf
```

---

### validate_mtproxy_config

Validate `mtproxy_config.json` structure using `jq`. **Legacy function — kept for compatibility.**

**Returns:** `0` if valid, `1` if invalid

**Example:**
```bash
validate_mtproxy_config
```

---

### mtproxy_is_installed

Check if MTProxy is installed (v7.0: verifies config directory exists).

**Returns:** `0` if installed, `1` if not installed

**Example:**
```bash
mtproxy_is_installed && echo "installed"
```

---

### mtproxy_is_running

Check if MTProxy is running (v7.0: checks supervisord or legacy container).

**Returns:** `0` if running, `1` if not running

**Example:**
```bash
mtproxy_is_running && echo "running"
```

---

### generate_mtg_toml *(v7.0)*

Generate `mtg.toml` configuration for mtg v2 (`nineseconds/mtg`).

**Parameters:**

| # | Name | Default | Description |
|---|------|---------|-------------|
| `$1` | `masquerade_domain` | from `.env` | Domain for Fake TLS masquerade (e.g., `proxy.example.com`) |

**Returns:** `0` on success, `1` on failure

**Notes:**
- Reads the first `ee`-type secret from `secrets.json`
- If no `ee`-secret exists, you must generate one first: `mtproxy add-secret --type ee --domain <domain>`
- Fake TLS secret must start with `"ee"` prefix
- `cloak.port` is set to `4443` (internal nginx port for active probing protection — do NOT open in UFW)
- Creates backup of existing `mtg.toml` before overwriting

**Example:**
```bash
generate_mtg_toml "proxy.example.com"
```

**Generated file (`mtg.toml`):**
```toml
debug = false
secret = "ee<hex>"

bind-to = "0.0.0.0:2053"

[network.timeout]
  tcp = "5s"

[cloak]
  port = 4443
```

---

### mtg_supervisord_start *(v7.0)*

Start mtg process inside the `familytraffic` container via `supervisorctl start mtg`.

**Returns:** `0` on success, `1` on failure

**Example:**
```bash
mtg_supervisord_start
```

---

### mtg_supervisord_stop *(v7.0)*

Stop mtg process inside the `familytraffic` container via `supervisorctl stop mtg`.

**Returns:** `0` on success, `1` on failure

**Example:**
```bash
mtg_supervisord_stop
```

---

### mtg_supervisord_restart *(v7.0)*

Restart mtg process inside the `familytraffic` container via `supervisorctl restart mtg`.

**Returns:** `0` on success, `1` on failure

**Example:**
```bash
mtg_supervisord_restart
```

---

### mtg_supervisord_status *(v7.0)*

Show mtg supervisord status from the `familytraffic` container.

**Returns:** `0` on success, `1` on failure

**Example:**
```bash
mtg_supervisord_status
```

---

### mtg_ufw_allow *(v7.0)*

Open port `2053/tcp` in UFW for MTProxy Fake TLS public traffic. No-op if UFW is absent or inactive, or if the rule already exists.

**Returns:** `0` on success, `1` on failure

**Example:**
```bash
mtg_ufw_allow
```

---

### mtg_ufw_deny *(v7.0)*

Close port `2053/tcp` in UFW when MTProxy is disabled. No-op if UFW is absent, inactive, or the rule does not exist.

**Returns:** `0` on success, `1` on failure

**Example:**
```bash
mtg_ufw_deny
```

---

## Usage

```bash
source lib/mtproxy_manager.sh

# Full setup (v7.0 workflow)
mtproxy_init 2053
generate_mtg_toml "proxy.example.com"
mtg_ufw_allow
mtg_supervisord_start
mtproxy_status
```

## Dependencies

- `jq` — JSON processing
- `docker` — container management (legacy fallback + supervisorctl exec)
- `curl` — stats endpoint access (legacy)
- `ufw` — firewall management (optional)
- `lib/mtproxy_secret_manager.sh` — secret generation
