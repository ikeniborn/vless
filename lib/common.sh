#!/usr/bin/env bash
# Common utility functions for familytraffic

# Write temp file content to target preserving inode (required for Docker bind mounts).
# Docker file bind mounts are tied to the file's inode. Using 'mv' replaces the
# directory entry with a new inode, so the container keeps seeing stale content.
# 'cat src > dst' writes into the existing file, preserving its inode.
#
# Usage: write_preserving_inode "$temp_file" "$target_file"
write_preserving_inode() {
    local src="$1" dst="$2"
    if [[ ! -f "$src" ]]; then
        echo "write_preserving_inode: source not found: $src" >&2
        return 1
    fi
    cat "$src" > "$dst" && rm -f "$src"
}
