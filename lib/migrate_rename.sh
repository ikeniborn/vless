#!/bin/bash
# lib/migrate_rename.sh
# Migration script: /opt/familytraffic → /opt/familytraffic (project rename v5.33)
# Part of familyTraffic VPN v5.33
#
# Handles upgrade path from old vless installations:
#   - Moves /opt/familytraffic/ → /opt/familytraffic/ (atomic mv + backwards-compat symlink)
#   - Creates compat symlink /usr/local/bin/vless → familytraffic
#
# WARN-7 fix: uses mv (atomic on same filesystem) instead of cp -a + rm -rf
# Usage: source lib/migrate_rename.sh  (or execute directly)

set -euo pipefail

# Literal old/new paths — must NOT be substituted by rename sed passes
OLD_INSTALL="/opt/familytraffic"
NEW_INSTALL="/opt/familytraffic"

migrate_rename() {
    # Case 1: old install exists, new does not → migrate
    if [ -d "${OLD_INSTALL}" ] && [ ! -d "${NEW_INSTALL}" ] && [ ! -L "${OLD_INSTALL}" ]; then
        echo "  [migrate] Migrating ${OLD_INSTALL} → ${NEW_INSTALL}..."
        # mv is atomic on same filesystem: no partial-state window if interrupted
        mv "${OLD_INSTALL}" "${NEW_INSTALL}"
        ln -s "${NEW_INSTALL}" "${OLD_INSTALL}"
        echo "  [migrate] Done: ${OLD_INSTALL} → ${NEW_INSTALL} (symlink left for compat)"

    # Case 2: old path is already a symlink → migration was done before
    elif [ -L "${OLD_INSTALL}" ]; then
        echo "  [migrate] ${OLD_INSTALL} is already a symlink — migration previously completed"

    # Case 3: both exist as real directories → skip, warn
    elif [ -d "${OLD_INSTALL}" ] && [ -d "${NEW_INSTALL}" ]; then
        echo "  [migrate] WARNING: Both ${OLD_INSTALL} and ${NEW_INSTALL} exist as directories" >&2
        echo "  [migrate] Skipping automatic migration — review manually" >&2

    # Case 4: neither exists → fresh install, nothing to migrate
    else
        : # no-op
    fi

    # Create backwards-compat CLI symlink: vless → familytraffic
    if [ -f /usr/local/bin/familytraffic ] && [ ! -e /usr/local/bin/vless ]; then
        ln -sf /usr/local/bin/familytraffic /usr/local/bin/vless
        echo "  [migrate] Compat symlink created: /usr/local/bin/vless → familytraffic"
    fi
}

# Run migration when executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    migrate_rename
fi
