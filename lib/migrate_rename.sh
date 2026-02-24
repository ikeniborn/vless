#!/bin/bash
# lib/migrate_rename.sh
# Migration script: rename /opt/vless → /opt/familytraffic
# Part of familyTraffic VPN v5.33
#
# Handles upgrade path from old vless installations:
#   - Moves /opt/vless/ → /opt/familytraffic/ (with backwards-compat symlink)
#   - Creates compat symlink /usr/local/bin/vless → familytraffic
#
# Usage: source lib/migrate_rename.sh  (or execute directly)

set -euo pipefail

migrate_rename() {
    # Migrate /opt/vless → /opt/familytraffic if old install exists
    if [ -d /opt/vless ] && [ ! -d /opt/familytraffic ]; then
        echo "  [migrate] Migrating /opt/vless → /opt/familytraffic..."
        cp -a /opt/vless /opt/familytraffic
        rm -rf /opt/vless
        ln -s /opt/familytraffic /opt/vless
        echo "  [migrate] Migration: /opt/vless → /opt/familytraffic (symlink left for compat)"
    elif [ -L /opt/vless ]; then
        echo "  [migrate] /opt/vless is already a symlink (migration previously completed)"
    elif [ -d /opt/vless ] && [ -d /opt/familytraffic ]; then
        echo "  [migrate] Both /opt/vless and /opt/familytraffic exist — skipping migration"
    fi

    # Create backwards-compat symlink: vless → familytraffic
    if [ -f /usr/local/bin/familytraffic ] && [ ! -L /usr/local/bin/vless ]; then
        ln -sf /usr/local/bin/familytraffic /usr/local/bin/vless
        echo "  [migrate] Compat symlink created: vless → familytraffic"
    fi
}

# Run migration when executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    migrate_rename
fi
