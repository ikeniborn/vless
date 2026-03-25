# test_mtproxy_integration

> **Module:** `tests` | **File:** `lib/tests/test_mtproxy_integration.sh`

============================================================================
MTProxy Integration Test Suite
Part of familyTraffic VPN Deployment System (v5.33)
Purpose: Integration tests for MTProxy supervisord lifecycle, port 2053,
         cloak-port 4443, and UFW rules.
DEV_MODE: auto-detected when /opt/familytraffic/ is absent or DEV_MODE=true.
          Container-dependent tests are skipped in DEV_MODE.
          Static checks (supervisord.conf content) always run.
Usage:
  # DEV_MODE (no Docker required):
  DEV_MODE=true sudo bash lib/tests/test_mtproxy_integration.sh
  # Full integration (requires running familytraffic container):
  sudo bash lib/tests/test_mtproxy_integration.sh
Version: 1.0.0
Date: 2026-03-12
============================================================================

---

