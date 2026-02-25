#!/bin/bash
#
# Old Installation Detection and Cleanup Module
# Part of familyTraffic VPN Deployment System
#
# Purpose: Detect and safely cleanup existing vless/familyTraffic installations with UFW backup
# Supports: Ubuntu 20.04+, Debian 10+
# Usage: source this file from install.sh (after dependencies.sh)
#
# Multi-level detection (from PLAN.md TASK-1.4):
#   Level 1: Docker containers (vless_*, xray*, nginx*)
#   Level 2: Docker networks (vless_*)
#   Level 3: Docker volumes (vless_*)
#   Level 4: /opt/familytraffic directory
#   Level 5: UFW rules (port 443, vless-related)
#   Level 6: Systemd services (vless*)
#   Level 7: Symlinks in /usr/local/bin (vless-*)
#
# Exit codes:
#   0 = success (detection/cleanup completed)
#   1 = error (detection/cleanup failed)
#

# Only set strict mode if not already set (to avoid issues when sourced)
[[ ! -o pipefail ]] && set -euo pipefail || true

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

# Detection results - populated by detect_old_installation()
OLD_CONTAINERS=()
OLD_NETWORKS=()
OLD_VOLUMES=()
OLD_UFW_RULES=()
OLD_SERVICES=()
OLD_SYMLINKS=()

# Ensure arrays are properly declared for export
declare -ga OLD_CONTAINERS OLD_NETWORKS OLD_VOLUMES OLD_UFW_RULES OLD_SERVICES OLD_SYMLINKS

OLD_INSTALL_FOUND=false
OLD_INSTALL_DIR="/opt/familytraffic"
BACKUP_BASE_DIR="/opt/familytraffic_backup"
UFW_BACKUP_DIR="/tmp/familytraffic_ufw_backup"

# Color codes (inherited from dependencies.sh but redefined for standalone use)
[[ -z "${RED:-}" ]] && RED='\033[0;31m'
[[ -z "${GREEN:-}" ]] && GREEN='\033[0;32m'
[[ -z "${YELLOW:-}" ]] && YELLOW='\033[1;33m'
[[ -z "${BLUE:-}" ]] && BLUE='\033[0;34m'
[[ -z "${NC:-}" ]] && NC='\033[0m'
[[ -z "${CYAN:-}" ]] && CYAN='\033[0;36m'

# Progress symbols
CHECK_MARK='\u2713'  # ✓
CROSS_MARK='\u2717'  # ✗
WARNING_MARK='\u26A0' # ⚠

# =============================================================================
# FUNCTION: detect_old_installation
# =============================================================================
# Description: Multi-level detection of existing VLESS installations
# Checks all 7 detection levels and populates global arrays
# Sets OLD_INSTALL_FOUND=true if ANY level finds something
# Returns: 0 on success (regardless of findings), 1 on error
# =============================================================================
detect_old_installation() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║      DETECTING EXISTING VLESS INSTALLATIONS (7 LEVELS)       ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local total_findings=0

    # -------------------------------------------------------------------------
    # LEVEL 1: Docker Containers
    # -------------------------------------------------------------------------
    echo -e "${CYAN}[Level 1/7] Checking Docker containers...${NC}"

    # Check if Docker is available (may not be installed yet)
    if command -v docker &>/dev/null && docker ps -a &>/dev/null 2>&1; then
        # Search for vless-related containers
        while IFS= read -r container; do
            [[ -n "$container" ]] && OLD_CONTAINERS+=("$container")
        done < <(docker ps -a --filter "name=vless" --format "{{.Names}}" 2>/dev/null || true)

        while IFS= read -r container; do
            [[ -n "$container" ]] && OLD_CONTAINERS+=("$container")
        done < <(docker ps -a --filter "name=xray" --format "{{.Names}}" 2>/dev/null || true)

        # Check for nginx containers that might be related to vless
        while IFS= read -r container; do
            # Only include nginx containers with vless in their name or labels
            if [[ "$container" == *"vless"* ]]; then
                OLD_CONTAINERS+=("$container")
            fi
        done < <(docker ps -a --filter "name=nginx" --format "{{.Names}}" 2>/dev/null || true)

        # Remove duplicates
        if [[ ${#OLD_CONTAINERS[@]} -gt 0 ]]; then
            mapfile -t OLD_CONTAINERS < <(printf '%s\n' "${OLD_CONTAINERS[@]}" | sort -u)
        fi

        if [[ ${#OLD_CONTAINERS[@]} -gt 0 ]]; then
            echo -e "${YELLOW}  ${WARNING_MARK} Found ${#OLD_CONTAINERS[@]} container(s):${NC}"
            for container in "${OLD_CONTAINERS[@]}"; do
                local status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
                echo -e "${YELLOW}    - $container ($status)${NC}"
            done
            ((total_findings += ${#OLD_CONTAINERS[@]}))
        else
            echo -e "${GREEN}  ${CHECK_MARK} No VLESS containers found${NC}"
        fi
    else
        echo -e "${CYAN}  Docker not available, skipping container check${NC}"
    fi
    echo ""

    # -------------------------------------------------------------------------
    # LEVEL 2: Docker Networks
    # -------------------------------------------------------------------------
    echo -e "${CYAN}[Level 2/7] Checking Docker networks...${NC}"

    if command -v docker &>/dev/null && docker network ls &>/dev/null 2>&1; then
        while IFS= read -r network; do
            [[ -n "$network" ]] && OLD_NETWORKS+=("$network")
        done < <(docker network ls --filter "name=vless" --format "{{.Name}}" 2>/dev/null | grep -v "^bridge$" | grep -v "^host$" | grep -v "^none$" || true)

        if [[ ${#OLD_NETWORKS[@]} -gt 0 ]]; then
            echo -e "${YELLOW}  ${WARNING_MARK} Found ${#OLD_NETWORKS[@]} network(s):${NC}"
            for network in "${OLD_NETWORKS[@]}"; do
                local subnet=$(docker network inspect "$network" --format='{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || echo "unknown")
                echo -e "${YELLOW}    - $network ($subnet)${NC}"
            done
            ((total_findings += ${#OLD_NETWORKS[@]}))
        else
            echo -e "${GREEN}  ${CHECK_MARK} No VLESS networks found${NC}"
        fi
    else
        echo -e "${CYAN}  Docker not available, skipping network check${NC}"
    fi
    echo ""

    # -------------------------------------------------------------------------
    # LEVEL 3: Docker Volumes
    # -------------------------------------------------------------------------
    echo -e "${CYAN}[Level 3/7] Checking Docker volumes...${NC}"

    if command -v docker &>/dev/null && docker volume ls &>/dev/null 2>&1; then
        while IFS= read -r volume; do
            [[ -n "$volume" ]] && OLD_VOLUMES+=("$volume")
        done < <(docker volume ls --filter "name=vless" --format "{{.Name}}" 2>/dev/null || true)

        if [[ ${#OLD_VOLUMES[@]} -gt 0 ]]; then
            echo -e "${YELLOW}  ${WARNING_MARK} Found ${#OLD_VOLUMES[@]} volume(s):${NC}"
            for volume in "${OLD_VOLUMES[@]}"; do
                local mountpoint=$(docker volume inspect "$volume" --format='{{.Mountpoint}}' 2>/dev/null || echo "unknown")
                echo -e "${YELLOW}    - $volume${NC}"
                echo -e "${CYAN}      Mountpoint: $mountpoint${NC}"
            done
            ((total_findings += ${#OLD_VOLUMES[@]}))
        else
            echo -e "${GREEN}  ${CHECK_MARK} No VLESS volumes found${NC}"
        fi
    else
        echo -e "${CYAN}  Docker not available, skipping volume check${NC}"
    fi
    echo ""

    # -------------------------------------------------------------------------
    # LEVEL 4: /opt/familytraffic Directory
    # -------------------------------------------------------------------------
    echo -e "${CYAN}[Level 4/7] Checking ${OLD_INSTALL_DIR} directory...${NC}"

    if [[ -d "$OLD_INSTALL_DIR" ]]; then
        local dir_size=$(du -sh "$OLD_INSTALL_DIR" 2>/dev/null | awk '{print $1}' || echo "unknown")
        local file_count=$(find "$OLD_INSTALL_DIR" -type f 2>/dev/null | wc -l || echo "0")

        echo -e "${YELLOW}  ${WARNING_MARK} Directory exists:${NC}"
        echo -e "${YELLOW}    Path: $OLD_INSTALL_DIR${NC}"
        echo -e "${CYAN}    Size: $dir_size${NC}"
        echo -e "${CYAN}    Files: $file_count${NC}"

        # Check for important files
        [[ -f "$OLD_INSTALL_DIR/data/users.json" ]] && echo -e "${CYAN}    Contains: users.json (USER DATA)${NC}"
        [[ -f "$OLD_INSTALL_DIR/config/xray_config.json" ]] && echo -e "${CYAN}    Contains: xray_config.json${NC}"
        [[ -f "$OLD_INSTALL_DIR/docker-compose.yml" ]] && echo -e "${CYAN}    Contains: docker-compose.yml${NC}"

        ((total_findings++)) || true
    else
        echo -e "${GREEN}  ${CHECK_MARK} Directory does not exist${NC}"
    fi
    echo ""

    # -------------------------------------------------------------------------
    # LEVEL 5: UFW Rules
    # -------------------------------------------------------------------------
    echo -e "${CYAN}[Level 5/7] Checking UFW rules...${NC}"

    if command -v ufw &>/dev/null; then
        local ufw_status=$(ufw status 2>/dev/null || echo "inactive")

        if [[ "$ufw_status" != "inactive" ]] && [[ "$ufw_status" != "Status: inactive" ]]; then
            # Search for vless-related rules and port 443
            while IFS= read -r rule; do
                [[ -n "$rule" ]] && OLD_UFW_RULES+=("$rule")
            done < <(ufw status numbered 2>/dev/null | grep -E "443|vless" || true)

            if [[ ${#OLD_UFW_RULES[@]} -gt 0 ]]; then
                echo -e "${YELLOW}  ${WARNING_MARK} Found ${#OLD_UFW_RULES[@]} UFW rule(s):${NC}"
                for rule in "${OLD_UFW_RULES[@]}"; do
                    echo -e "${YELLOW}    $rule${NC}"
                done
                ((total_findings += ${#OLD_UFW_RULES[@]}))
            else
                echo -e "${GREEN}  ${CHECK_MARK} No VLESS-related UFW rules found${NC}"
            fi
        else
            echo -e "${CYAN}  UFW is inactive${NC}"
        fi
    else
        echo -e "${CYAN}  UFW not installed, skipping rule check${NC}"
    fi
    echo ""

    # -------------------------------------------------------------------------
    # LEVEL 6: Systemd Services
    # -------------------------------------------------------------------------
    echo -e "${CYAN}[Level 6/7] Checking systemd services...${NC}"

    if command -v systemctl &>/dev/null; then
        # Search for vless-related services
        while IFS= read -r service; do
            [[ -n "$service" ]] && OLD_SERVICES+=("$service")
        done < <(systemctl list-unit-files 2>/dev/null | grep -i "vless" | awk '{print $1}' || true)

        if [[ ${#OLD_SERVICES[@]} -gt 0 ]]; then
            echo -e "${YELLOW}  ${WARNING_MARK} Found ${#OLD_SERVICES[@]} service(s):${NC}"
            for service in "${OLD_SERVICES[@]}"; do
                local status=$(systemctl is-enabled "$service" 2>/dev/null || echo "unknown")
                echo -e "${YELLOW}    - $service ($status)${NC}"
            done
            ((total_findings += ${#OLD_SERVICES[@]}))
        else
            echo -e "${GREEN}  ${CHECK_MARK} No VLESS services found${NC}"
        fi
    else
        echo -e "${CYAN}  systemctl not available, skipping service check${NC}"
    fi
    echo ""

    # -------------------------------------------------------------------------
    # LEVEL 7: Symlinks in /usr/local/bin
    # -------------------------------------------------------------------------
    echo -e "${CYAN}[Level 7/7] Checking symlinks in /usr/local/bin...${NC}"

    if [[ -d "/usr/local/bin" ]]; then
        while IFS= read -r symlink; do
            [[ -n "$symlink" ]] && OLD_SYMLINKS+=("$symlink")
        done < <(find /usr/local/bin -type l -name "vless-*" 2>/dev/null || true)

        # Also check for vless without prefix
        if [[ -L "/usr/local/bin/vless" ]]; then
            OLD_SYMLINKS+=("/usr/local/bin/vless")
        fi

        if [[ ${#OLD_SYMLINKS[@]} -gt 0 ]]; then
            echo -e "${YELLOW}  ${WARNING_MARK} Found ${#OLD_SYMLINKS[@]} symlink(s):${NC}"
            for symlink in "${OLD_SYMLINKS[@]}"; do
                local target=$(readlink -f "$symlink" 2>/dev/null || echo "broken")
                echo -e "${YELLOW}    - $symlink -> $target${NC}"
            done
            ((total_findings += ${#OLD_SYMLINKS[@]}))
        else
            echo -e "${GREEN}  ${CHECK_MARK} No VLESS symlinks found${NC}"
        fi
    else
        echo -e "${CYAN}  /usr/local/bin not found, skipping symlink check${NC}"
    fi
    echo ""

    # -------------------------------------------------------------------------
    # SUMMARY
    # -------------------------------------------------------------------------
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║               DETECTION SUMMARY                               ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [[ $total_findings -gt 0 ]]; then
        OLD_INSTALL_FOUND=true
        echo -e "${YELLOW}${WARNING_MARK} Old installation detected: $total_findings finding(s)${NC}"
        echo ""
        echo -e "  Containers: ${#OLD_CONTAINERS[@]}"
        echo -e "  Networks:   ${#OLD_NETWORKS[@]}"
        echo -e "  Volumes:    ${#OLD_VOLUMES[@]}"
        echo -e "  Directory:  $([ -d "$OLD_INSTALL_DIR" ] && echo "YES" || echo "NO")"
        echo -e "  UFW Rules:  ${#OLD_UFW_RULES[@]}"
        echo -e "  Services:   ${#OLD_SERVICES[@]}"
        echo -e "  Symlinks:   ${#OLD_SYMLINKS[@]}"
        echo ""
    else
        OLD_INSTALL_FOUND=false
        echo -e "${GREEN}${CHECK_MARK} No old VLESS installation found${NC}"
        echo -e "${GREEN}System is clean, ready for fresh installation${NC}"
        echo ""
    fi

    return 0
}

# =============================================================================
# FUNCTION: display_detection_summary
# =============================================================================
# Description: Display formatted summary with recommended actions
# Shows what was found and recommends backup + cleanup or skip
# Uses color-coded output for visibility
# Returns: 0 always
# =============================================================================
display_detection_summary() {
    if [[ "$OLD_INSTALL_FOUND" != "true" ]]; then
        echo -e "${GREEN}No old installation to summarize${NC}"
        return 0
    fi

    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║           OLD INSTALLATION DETECTED - ACTION REQUIRED         ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${YELLOW}The following components from a previous VLESS installation were detected:${NC}"
    echo ""

    if [[ ${#OLD_CONTAINERS[@]} -gt 0 ]]; then
        echo -e "${CYAN}Docker Containers (${#OLD_CONTAINERS[@]}):${NC}"
        for container in "${OLD_CONTAINERS[@]}"; do
            echo -e "  - $container"
        done
        echo ""
    fi

    if [[ ${#OLD_NETWORKS[@]} -gt 0 ]]; then
        echo -e "${CYAN}Docker Networks (${#OLD_NETWORKS[@]}):${NC}"
        for network in "${OLD_NETWORKS[@]}"; do
            echo -e "  - $network"
        done
        echo ""
    fi

    if [[ ${#OLD_VOLUMES[@]} -gt 0 ]]; then
        echo -e "${CYAN}Docker Volumes (${#OLD_VOLUMES[@]}):${NC}"
        for volume in "${OLD_VOLUMES[@]}"; do
            echo -e "  - $volume"
        done
        echo ""
    fi

    if [[ -d "$OLD_INSTALL_DIR" ]]; then
        echo -e "${CYAN}Installation Directory:${NC}"
        echo -e "  - $OLD_INSTALL_DIR"
        if [[ -f "$OLD_INSTALL_DIR/data/users.json" ]]; then
            echo -e "${YELLOW}    WARNING: Contains user data (users.json)${NC}"
        fi
        echo ""
    fi

    if [[ ${#OLD_UFW_RULES[@]} -gt 0 ]]; then
        echo -e "${CYAN}UFW Rules (${#OLD_UFW_RULES[@]}):${NC}"
        for rule in "${OLD_UFW_RULES[@]:0:3}"; do
            echo -e "  $rule"
        done
        [[ ${#OLD_UFW_RULES[@]} -gt 3 ]] && echo -e "  ... and $((${#OLD_UFW_RULES[@]} - 3)) more"
        echo ""
    fi

    if [[ ${#OLD_SERVICES[@]} -gt 0 ]]; then
        echo -e "${CYAN}Systemd Services (${#OLD_SERVICES[@]}):${NC}"
        for service in "${OLD_SERVICES[@]}"; do
            echo -e "  - $service"
        done
        echo ""
    fi

    if [[ ${#OLD_SYMLINKS[@]} -gt 0 ]]; then
        echo -e "${CYAN}Symlinks (${#OLD_SYMLINKS[@]}):${NC}"
        for symlink in "${OLD_SYMLINKS[@]}"; do
            echo -e "  - $symlink"
        done
        echo ""
    fi

    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║                  RECOMMENDED ACTION                           ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}Option 1 (RECOMMENDED):${NC} Backup and cleanup"
    echo -e "  - Creates timestamped backup of all data"
    echo -e "  - Backs up UFW rules separately"
    echo -e "  - Safely removes old installation"
    echo -e "  - Allows restoration if needed"
    echo ""
    echo -e "${YELLOW}Option 2 (RISKY):${NC} Cleanup without backup"
    echo -e "  - Immediately removes all components"
    echo -e "  - No recovery possible"
    echo -e "  - Use only if data is not important"
    echo ""
    echo -e "${CYAN}Option 3 (SAFE):${NC} Skip cleanup and exit"
    echo -e "  - Aborts installation"
    echo -e "  - Allows manual cleanup"
    echo -e "  - Recommended if unsure"
    echo ""

    return 0
}

# =============================================================================
# FUNCTION: backup_ufw_rules
# =============================================================================
# Description: Backup UFW configuration files and status (Q-A2)
# Creates timestamped backup directory
# Backs up: after.rules, before.rules, user.rules, user6.rules, status
# Returns: 0 on success, 1 on failure
# =============================================================================
backup_ufw_rules() {
    echo -e "${BLUE}Backing up UFW rules...${NC}"

    # Check if UFW is available
    if ! command -v ufw &>/dev/null; then
        echo -e "${YELLOW}${WARNING_MARK} UFW not installed, skipping UFW backup${NC}"
        return 0
    fi

    # Create backup directory with timestamp
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="${UFW_BACKUP_DIR}_${timestamp}"

    if ! mkdir -p "$backup_dir"; then
        echo -e "${RED}${CROSS_MARK} Failed to create UFW backup directory: $backup_dir${NC}"
        return 1
    fi

    echo -e "${CYAN}Backup directory: $backup_dir${NC}"

    # Backup UFW configuration files
    local ufw_files=(
        "/etc/ufw/after.rules"
        "/etc/ufw/before.rules"
        "/etc/ufw/user.rules"
        "/etc/ufw/user6.rules"
        "/etc/ufw/after6.rules"
        "/etc/ufw/before6.rules"
    )

    local backup_count=0
    for file in "${ufw_files[@]}"; do
        if [[ -f "$file" ]]; then
            local basename=$(basename "$file")
            if cp "$file" "$backup_dir/$basename" 2>/dev/null; then
                echo -e "${GREEN}  ${CHECK_MARK} Backed up: $basename${NC}"
                ((backup_count++)) || true
            else
                echo -e "${YELLOW}  ${WARNING_MARK} Failed to backup: $basename${NC}"
            fi
        fi
    done

    # Backup current UFW status
    echo -e "${CYAN}Saving UFW status...${NC}"
    if ufw status numbered > "$backup_dir/ufw_status.txt" 2>/dev/null; then
        echo -e "${GREEN}  ${CHECK_MARK} Saved UFW status${NC}"
        ((backup_count++)) || true
    else
        echo -e "${YELLOW}  ${WARNING_MARK} Failed to save UFW status${NC}"
    fi

    # Backup UFW verbose status
    if ufw status verbose > "$backup_dir/ufw_status_verbose.txt" 2>/dev/null; then
        echo -e "${GREEN}  ${CHECK_MARK} Saved UFW verbose status${NC}"
        ((backup_count++)) || true
    fi

    # Create backup metadata
    cat > "$backup_dir/backup_info.txt" <<EOF
UFW Backup Information
=====================
Backup Date: $(date)
Hostname: $(hostname)
UFW Version: $(ufw version 2>/dev/null || echo "unknown")
Files Backed Up: $backup_count

Backup Contents:
$(ls -lh "$backup_dir" 2>/dev/null || echo "Error listing contents")
EOF

    local backup_size=$(du -sh "$backup_dir" 2>/dev/null | awk '{print $1}' || echo "unknown")

    echo ""
    echo -e "${GREEN}${CHECK_MARK} UFW backup completed${NC}"
    echo -e "${CYAN}  Location: $backup_dir${NC}"
    echo -e "${CYAN}  Files backed up: $backup_count${NC}"
    echo -e "${CYAN}  Total size: $backup_size${NC}"
    echo ""

    return 0
}

# =============================================================================
# FUNCTION: backup_old_installation
# =============================================================================
# Description: Create comprehensive backup of old VLESS installation
# Backs up: /opt/familytraffic directory, Docker configs, UFW rules
# Creates timestamped backup with metadata
# Returns: 0 on success, 1 on failure
# =============================================================================
backup_old_installation() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           BACKING UP OLD INSTALLATION                        ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Create backup directory with timestamp
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="${BACKUP_BASE_DIR}_${timestamp}"

    if ! mkdir -p "$backup_dir"; then
        echo -e "${RED}${CROSS_MARK} Failed to create backup directory: $backup_dir${NC}"
        return 1
    fi

    echo -e "${CYAN}Backup directory: $backup_dir${NC}"
    echo ""

    local backup_success=true

    # -------------------------------------------------------------------------
    # BACKUP 1: /opt/familytraffic directory
    # -------------------------------------------------------------------------
    if [[ -d "$OLD_INSTALL_DIR" ]]; then
        echo -e "${CYAN}[1/5] Backing up $OLD_INSTALL_DIR...${NC}"

        if cp -a "$OLD_INSTALL_DIR" "$backup_dir/vless" 2>/dev/null; then
            local dir_size=$(du -sh "$backup_dir/vless" 2>/dev/null | awk '{print $1}' || echo "unknown")
            echo -e "${GREEN}  ${CHECK_MARK} Directory backed up ($dir_size)${NC}"

            # Highlight important files
            [[ -f "$backup_dir/vless/data/users.json" ]] && echo -e "${CYAN}    - users.json (user data)${NC}"
            [[ -f "$backup_dir/vless/config/xray_config.json" ]] && echo -e "${CYAN}    - xray_config.json${NC}"
            [[ -f "$backup_dir/vless/docker-compose.yml" ]] && echo -e "${CYAN}    - docker-compose.yml${NC}"
        else
            echo -e "${RED}  ${CROSS_MARK} Failed to backup directory${NC}"
            backup_success=false
        fi
    else
        echo -e "${CYAN}[1/5] No installation directory to backup${NC}"
    fi
    echo ""

    # -------------------------------------------------------------------------
    # BACKUP 2: Docker container configurations
    # -------------------------------------------------------------------------
    echo -e "${CYAN}[2/5] Exporting Docker container configurations...${NC}"

    if command -v docker &>/dev/null && [[ ${#OLD_CONTAINERS[@]} -gt 0 ]]; then
        mkdir -p "$backup_dir/docker_configs"

        for container in "${OLD_CONTAINERS[@]}"; do
            local config_file="$backup_dir/docker_configs/${container}_inspect.json"
            if docker inspect "$container" > "$config_file" 2>/dev/null; then
                echo -e "${GREEN}  ${CHECK_MARK} Exported: $container${NC}"
            else
                echo -e "${YELLOW}  ${WARNING_MARK} Failed to export: $container${NC}"
            fi
        done
    else
        echo -e "${CYAN}  No containers to export${NC}"
    fi
    echo ""

    # -------------------------------------------------------------------------
    # BACKUP 3: Docker network configurations
    # -------------------------------------------------------------------------
    echo -e "${CYAN}[3/5] Exporting Docker network configurations...${NC}"

    if command -v docker &>/dev/null && [[ ${#OLD_NETWORKS[@]} -gt 0 ]]; then
        mkdir -p "$backup_dir/docker_configs"

        for network in "${OLD_NETWORKS[@]}"; do
            local network_file="$backup_dir/docker_configs/${network}_network.json"
            if docker network inspect "$network" > "$network_file" 2>/dev/null; then
                echo -e "${GREEN}  ${CHECK_MARK} Exported: $network${NC}"
            else
                echo -e "${YELLOW}  ${WARNING_MARK} Failed to export: $network${NC}"
            fi
        done
    else
        echo -e "${CYAN}  No networks to export${NC}"
    fi
    echo ""

    # -------------------------------------------------------------------------
    # BACKUP 4: UFW rules (call backup_ufw_rules)
    # -------------------------------------------------------------------------
    echo -e "${CYAN}[4/5] Backing up UFW rules...${NC}"

    if backup_ufw_rules; then
        # Copy UFW backup to main backup directory
        local latest_ufw_backup=$(ls -td ${UFW_BACKUP_DIR}_* 2>/dev/null | head -1)
        if [[ -n "$latest_ufw_backup" ]] && [[ -d "$latest_ufw_backup" ]]; then
            cp -a "$latest_ufw_backup" "$backup_dir/ufw_backup"
            echo -e "${GREEN}  ${CHECK_MARK} UFW rules backed up to main backup${NC}"
        fi
    else
        echo -e "${YELLOW}  ${WARNING_MARK} UFW backup failed or skipped${NC}"
    fi
    echo ""

    # -------------------------------------------------------------------------
    # BACKUP 5: Create backup metadata
    # -------------------------------------------------------------------------
    echo -e "${CYAN}[5/5] Creating backup metadata...${NC}"

    cat > "$backup_dir/backup_metadata.txt" <<EOF
VLESS Installation Backup
========================
Backup Date: $(date)
Hostname: $(hostname)
Backup Directory: $backup_dir

Components Backed Up:
--------------------
Installation Directory: $([ -d "$backup_dir/vless" ] && echo "YES" || echo "NO")
Docker Containers: ${#OLD_CONTAINERS[@]}
Docker Networks: ${#OLD_NETWORKS[@]}
Docker Volumes: ${#OLD_VOLUMES[@]}
UFW Rules: $([ -d "$backup_dir/ufw_backup" ] && echo "YES" || echo "NO")

Containers List:
$(printf '%s\n' "${OLD_CONTAINERS[@]}" 2>/dev/null || echo "None")

Networks List:
$(printf '%s\n' "${OLD_NETWORKS[@]}" 2>/dev/null || echo "None")

Volumes List:
$(printf '%s\n' "${OLD_VOLUMES[@]}" 2>/dev/null || echo "None")

Backup Contents:
---------------
$(ls -lh "$backup_dir" 2>/dev/null)

Total Backup Size:
-----------------
$(du -sh "$backup_dir" 2>/dev/null)
EOF

    echo -e "${GREEN}  ${CHECK_MARK} Metadata created${NC}"
    echo ""

    # -------------------------------------------------------------------------
    # SUMMARY
    # -------------------------------------------------------------------------
    local backup_size=$(du -sh "$backup_dir" 2>/dev/null | awk '{print $1}' || echo "unknown")

    if [[ "$backup_success" == "true" ]]; then
        echo -e "${GREEN}${CHECK_MARK} Backup completed successfully${NC}"
        echo ""
        echo -e "${CYAN}Backup Information:${NC}"
        echo -e "  Location: $backup_dir"
        echo -e "  Total size: $backup_size"
        echo -e "  Metadata: $backup_dir/backup_metadata.txt"
        echo ""
        echo -e "${YELLOW}To restore from this backup, run:${NC}"
        echo -e "${YELLOW}  restore_from_backup \"$backup_dir\"${NC}"
        echo ""
        return 0
    else
        echo -e "${YELLOW}${WARNING_MARK} Backup completed with warnings${NC}"
        echo -e "${CYAN}  Location: $backup_dir${NC}"
        echo -e "${CYAN}  Total size: $backup_size${NC}"
        echo ""
        return 0  # Return 0 even with warnings (partial backup is better than none)
    fi
}

# =============================================================================
# FUNCTION: cleanup_old_installation
# =============================================================================
# Description: Safely cleanup old VLESS installation components
# REQUIRES USER CONFIRMATION before any deletion
# Cleans: containers, networks, volumes, directory, UFW rules, services, symlinks
# Returns: 0 on success, 1 on failure
# =============================================================================
cleanup_old_installation() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           CLEANING UP OLD INSTALLATION                       ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # MANDATORY USER CONFIRMATION
    echo -e "${YELLOW}${WARNING_MARK} WARNING: This will DELETE the following components:${NC}"
    echo ""
    [[ ${#OLD_CONTAINERS[@]} -gt 0 ]] && echo -e "${YELLOW}  - ${#OLD_CONTAINERS[@]} Docker container(s)${NC}"
    [[ ${#OLD_NETWORKS[@]} -gt 0 ]] && echo -e "${YELLOW}  - ${#OLD_NETWORKS[@]} Docker network(s)${NC}"
    [[ ${#OLD_VOLUMES[@]} -gt 0 ]] && echo -e "${YELLOW}  - ${#OLD_VOLUMES[@]} Docker volume(s)${NC}"
    [[ -d "$OLD_INSTALL_DIR" ]] && echo -e "${YELLOW}  - Installation directory: $OLD_INSTALL_DIR${NC}"
    [[ ${#OLD_UFW_RULES[@]} -gt 0 ]] && echo -e "${YELLOW}  - ${#OLD_UFW_RULES[@]} UFW rule(s)${NC}"
    [[ ${#OLD_SERVICES[@]} -gt 0 ]] && echo -e "${YELLOW}  - ${#OLD_SERVICES[@]} systemd service(s)${NC}"
    [[ ${#OLD_SYMLINKS[@]} -gt 0 ]] && echo -e "${YELLOW}  - ${#OLD_SYMLINKS[@]} symlink(s)${NC}"
    echo ""

    echo -e "${RED}${WARNING_MARK} This action is IRREVERSIBLE (unless you created a backup)${NC}"
    echo ""

    # Check for non-interactive confirmation via environment variable
    if [[ "${FT_CONFIRM_CLEANUP:-}" == "yes" ]]; then
        confirmation="yes"
        echo -e "${CYAN}Non-interactive mode: Auto-confirmed via FT_CONFIRM_CLEANUP${NC}"
    else
        echo -n -e "${YELLOW}Type 'yes' to confirm cleanup (30s timeout, default=no): ${NC}"
        if ! read -t 30 -r confirmation; then
            confirmation="no"
            echo ""
            echo -e "${CYAN}Input timeout reached, cleanup cancelled${NC}"
        fi
        echo ""
    fi

    if [[ "$confirmation" != "yes" ]]; then
        echo -e "${CYAN}Cleanup cancelled by user${NC}"
        return 1
    fi

    local cleanup_errors=0

    # -------------------------------------------------------------------------
    # CLEANUP 1: Stop and remove Docker containers
    # -------------------------------------------------------------------------
    if [[ ${#OLD_CONTAINERS[@]} -gt 0 ]]; then
        echo -e "${CYAN}[1/7] Removing Docker containers...${NC}"

        for container in "${OLD_CONTAINERS[@]}"; do
            echo -n -e "  Stopping $container... "
            if docker stop "$container" &>/dev/null; then
                echo -e "${GREEN}${CHECK_MARK}${NC}"
            else
                echo -e "${YELLOW}(already stopped)${NC}"
            fi

            echo -n -e "  Removing $container... "
            if docker rm -f "$container" &>/dev/null; then
                echo -e "${GREEN}${CHECK_MARK}${NC}"
            else
                echo -e "${RED}${CROSS_MARK}${NC}"
                ((cleanup_errors++)) || true
            fi
        done
        echo ""
    fi

    # -------------------------------------------------------------------------
    # CLEANUP 2: Remove Docker networks
    # -------------------------------------------------------------------------
    if [[ ${#OLD_NETWORKS[@]} -gt 0 ]]; then
        echo -e "${CYAN}[2/7] Removing Docker networks...${NC}"

        for network in "${OLD_NETWORKS[@]}"; do
            echo -n -e "  Removing $network... "
            if docker network rm "$network" &>/dev/null; then
                echo -e "${GREEN}${CHECK_MARK}${NC}"
            else
                echo -e "${RED}${CROSS_MARK}${NC}"
                ((cleanup_errors++)) || true
            fi
        done
        echo ""
    fi

    # -------------------------------------------------------------------------
    # CLEANUP 3: Remove Docker volumes
    # -------------------------------------------------------------------------
    if [[ ${#OLD_VOLUMES[@]} -gt 0 ]]; then
        echo -e "${CYAN}[3/7] Removing Docker volumes...${NC}"

        for volume in "${OLD_VOLUMES[@]}"; do
            echo -n -e "  Removing $volume... "
            if docker volume rm "$volume" &>/dev/null; then
                echo -e "${GREEN}${CHECK_MARK}${NC}"
            else
                echo -e "${RED}${CROSS_MARK}${NC}"
                ((cleanup_errors++)) || true
            fi
        done
        echo ""
    fi

    # -------------------------------------------------------------------------
    # CLEANUP 4: Remove /opt/familytraffic directory
    # -------------------------------------------------------------------------
    if [[ -d "$OLD_INSTALL_DIR" ]]; then
        echo -e "${CYAN}[4/7] Removing installation directory...${NC}"
        echo -n -e "  Removing $OLD_INSTALL_DIR... "

        if rm -rf "$OLD_INSTALL_DIR" 2>/dev/null; then
            echo -e "${GREEN}${CHECK_MARK}${NC}"
        else
            echo -e "${RED}${CROSS_MARK}${NC}"
            ((cleanup_errors++)) || true
        fi
        echo ""
    else
        echo -e "${CYAN}[4/7] No installation directory to remove${NC}"
        echo ""
    fi

    # -------------------------------------------------------------------------
    # CLEANUP 5: Clean UFW rules (manual intervention recommended)
    # -------------------------------------------------------------------------
    if [[ ${#OLD_UFW_RULES[@]} -gt 0 ]]; then
        echo -e "${CYAN}[5/7] Cleaning UFW rules...${NC}"
        echo -e "${YELLOW}  ${WARNING_MARK} Manual UFW rule removal recommended${NC}"
        echo -e "${YELLOW}  Found ${#OLD_UFW_RULES[@]} rule(s) that may need cleanup${NC}"
        echo -e "${CYAN}  Review with: ufw status numbered${NC}"
        echo -e "${CYAN}  Remove with: ufw delete <rule_number>${NC}"
        echo ""
    else
        echo -e "${CYAN}[5/7] No UFW rules to clean${NC}"
        echo ""
    fi

    # -------------------------------------------------------------------------
    # CLEANUP 6: Remove systemd services
    # -------------------------------------------------------------------------
    if [[ ${#OLD_SERVICES[@]} -gt 0 ]]; then
        echo -e "${CYAN}[6/7] Removing systemd services...${NC}"

        for service in "${OLD_SERVICES[@]}"; do
            echo -n -e "  Stopping $service... "
            systemctl stop "$service" &>/dev/null || true
            echo -e "${GREEN}${CHECK_MARK}${NC}"

            echo -n -e "  Disabling $service... "
            systemctl disable "$service" &>/dev/null || true
            echo -e "${GREEN}${CHECK_MARK}${NC}"

            # Try to find and remove service file
            local service_file="/etc/systemd/system/$service"
            if [[ -f "$service_file" ]]; then
                echo -n -e "  Removing $service_file... "
                if rm -f "$service_file" 2>/dev/null; then
                    echo -e "${GREEN}${CHECK_MARK}${NC}"
                else
                    echo -e "${RED}${CROSS_MARK}${NC}"
                    ((cleanup_errors++)) || true
                fi
            fi
        done

        # Reload systemd daemon
        echo -n -e "  Reloading systemd daemon... "
        if systemctl daemon-reload &>/dev/null; then
            echo -e "${GREEN}${CHECK_MARK}${NC}"
        else
            echo -e "${YELLOW}${WARNING_MARK}${NC}"
        fi
        echo ""
    else
        echo -e "${CYAN}[6/7] No systemd services to remove${NC}"
        echo ""
    fi

    # -------------------------------------------------------------------------
    # CLEANUP 7: Remove symlinks
    # -------------------------------------------------------------------------
    if [[ ${#OLD_SYMLINKS[@]} -gt 0 ]]; then
        echo -e "${CYAN}[7/7] Removing symlinks...${NC}"

        for symlink in "${OLD_SYMLINKS[@]}"; do
            echo -n -e "  Removing $symlink... "
            if rm -f "$symlink" 2>/dev/null; then
                echo -e "${GREEN}${CHECK_MARK}${NC}"
            else
                echo -e "${RED}${CROSS_MARK}${NC}"
                ((cleanup_errors++)) || true
            fi
        done
        echo ""
    else
        echo -e "${CYAN}[7/7] No symlinks to remove${NC}"
        echo ""
    fi

    # -------------------------------------------------------------------------
    # SUMMARY
    # -------------------------------------------------------------------------
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║               CLEANUP SUMMARY                                 ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [[ $cleanup_errors -eq 0 ]]; then
        echo -e "${GREEN}${CHECK_MARK} All cleanup tasks completed successfully${NC}"
        echo ""
        return 0
    else
        echo -e "${YELLOW}${WARNING_MARK} Cleanup completed with $cleanup_errors error(s)${NC}"
        echo -e "${YELLOW}Some components may require manual removal${NC}"
        echo ""
        return 1
    fi
}

# =============================================================================
# FUNCTION: restore_from_backup
# =============================================================================
# Description: Restore VLESS installation from backup directory
# Restores: /opt/familytraffic, UFW rules, Docker containers (if docker-compose.yml exists)
# Parameters: $1 = backup_directory path
# Returns: 0 on success, 1 on failure
# =============================================================================
restore_from_backup() {
    local backup_dir="$1"

    if [[ -z "$backup_dir" ]]; then
        echo -e "${RED}${CROSS_MARK} No backup directory specified${NC}"
        echo -e "${YELLOW}Usage: restore_from_backup <backup_directory>${NC}"
        return 1
    fi

    if [[ ! -d "$backup_dir" ]]; then
        echo -e "${RED}${CROSS_MARK} Backup directory not found: $backup_dir${NC}"
        return 1
    fi

    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           RESTORING FROM BACKUP                               ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Backup source: $backup_dir${NC}"
    echo ""

    # USER CONFIRMATION
    echo -e "${YELLOW}${WARNING_MARK} This will restore the old installation${NC}"

    # Check for non-interactive confirmation via environment variable
    if [[ "${FT_CONFIRM_RESTORE:-}" == "yes" ]]; then
        confirmation="yes"
        echo -e "${CYAN}Non-interactive mode: Auto-confirmed via FT_CONFIRM_RESTORE${NC}"
    else
        echo -n -e "${YELLOW}Type 'yes' to confirm restoration (30s timeout, default=no): ${NC}"
        if ! read -t 30 -r confirmation; then
            confirmation="no"
            echo ""
            echo -e "${CYAN}Input timeout reached, restoration cancelled${NC}"
        fi
        echo ""
    fi

    if [[ "$confirmation" != "yes" ]]; then
        echo -e "${CYAN}Restoration cancelled by user${NC}"
        return 1
    fi

    local restore_errors=0

    # -------------------------------------------------------------------------
    # RESTORE 1: /opt/familytraffic directory
    # -------------------------------------------------------------------------
    if [[ -d "$backup_dir/vless" ]]; then
        echo -e "${CYAN}[1/3] Restoring installation directory...${NC}"

        # Remove current installation if exists
        if [[ -d "$OLD_INSTALL_DIR" ]]; then
            echo -n -e "  Removing current installation... "
            rm -rf "$OLD_INSTALL_DIR" 2>/dev/null || true
            echo -e "${GREEN}${CHECK_MARK}${NC}"
        fi

        echo -n -e "  Restoring $OLD_INSTALL_DIR... "
        if cp -a "$backup_dir/vless" "$OLD_INSTALL_DIR" 2>/dev/null; then
            echo -e "${GREEN}${CHECK_MARK}${NC}"
        else
            echo -e "${RED}${CROSS_MARK}${NC}"
            ((restore_errors++)) || true
        fi
        echo ""
    else
        echo -e "${YELLOW}[1/3] No installation directory in backup${NC}"
        echo ""
    fi

    # -------------------------------------------------------------------------
    # RESTORE 2: UFW rules
    # -------------------------------------------------------------------------
    if [[ -d "$backup_dir/ufw_backup" ]]; then
        echo -e "${CYAN}[2/3] Restoring UFW rules...${NC}"

        local ufw_files=(
            "after.rules"
            "before.rules"
            "user.rules"
            "user6.rules"
            "after6.rules"
            "before6.rules"
        )

        for file in "${ufw_files[@]}"; do
            if [[ -f "$backup_dir/ufw_backup/$file" ]]; then
                echo -n -e "  Restoring $file... "
                if cp "$backup_dir/ufw_backup/$file" "/etc/ufw/$file" 2>/dev/null; then
                    echo -e "${GREEN}${CHECK_MARK}${NC}"
                else
                    echo -e "${RED}${CROSS_MARK}${NC}"
                    ((restore_errors++)) || true
                fi
            fi
        done

        # Reload UFW
        echo -n -e "  Reloading UFW... "
        if ufw reload &>/dev/null; then
            echo -e "${GREEN}${CHECK_MARK}${NC}"
        else
            echo -e "${YELLOW}${WARNING_MARK}${NC}"
        fi
        echo ""
    else
        echo -e "${YELLOW}[2/3] No UFW backup found${NC}"
        echo ""
    fi

    # -------------------------------------------------------------------------
    # RESTORE 3: Docker containers (if docker-compose.yml exists)
    # -------------------------------------------------------------------------
    if [[ -f "$OLD_INSTALL_DIR/docker-compose.yml" ]]; then
        echo -e "${CYAN}[3/3] Recreating Docker containers...${NC}"

        echo -n -e "  Starting containers with docker-compose... "
        if docker-compose -f "$OLD_INSTALL_DIR/docker-compose.yml" up -d &>/dev/null; then
            echo -e "${GREEN}${CHECK_MARK}${NC}"
        else
            echo -e "${RED}${CROSS_MARK}${NC}"
            ((restore_errors++)) || true
        fi
        echo ""
    else
        echo -e "${YELLOW}[3/3] No docker-compose.yml found, skipping container recreation${NC}"
        echo ""
    fi

    # -------------------------------------------------------------------------
    # SUMMARY
    # -------------------------------------------------------------------------
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║               RESTORATION SUMMARY                             ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [[ $restore_errors -eq 0 ]]; then
        echo -e "${GREEN}${CHECK_MARK} Restoration completed successfully${NC}"
        echo ""
        return 0
    else
        echo -e "${YELLOW}${WARNING_MARK} Restoration completed with $restore_errors error(s)${NC}"
        echo -e "${YELLOW}Some components may require manual restoration${NC}"
        echo ""
        return 1
    fi
}

# =============================================================================
# MAIN EXECUTION (when sourced, this section doesn't run)
# =============================================================================
# If this script is executed directly (for testing), run detection
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Running old installation detection module in test mode..."
    echo ""

    # Run detection
    detect_old_installation

    # Display summary if something found
    if [[ "$OLD_INSTALL_FOUND" == "true" ]]; then
        echo ""
        display_detection_summary

        echo ""
        echo "Test mode: No cleanup will be performed"
        echo "To cleanup, run: cleanup_old_installation"
        echo "To backup, run: backup_old_installation"
    fi

    exit 0
fi
