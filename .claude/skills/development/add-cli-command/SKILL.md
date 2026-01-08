---
name: Add CLI Command
description: Add new command to vless/mtproxy/vless-proxy CLIs with auto-generated parsing
version: 1.0.0
tags: [development, cli, vless]
dependencies: [git-workflow]
files:
  templates: ./templates/*.sh
  shared: ../../_shared/*.json
---

# Add CLI Command v1.0

Добавление новой команды в VLESS CLI tools.

## Когда использовать

- Добавление новой vless команды
- Добавление новой mtproxy команды
- Добавление новой vless-proxy команды

## Workflow

### Phase 1: Load Context

```bash
Read docs/architecture/yaml/cli.yaml  # Existing commands
Read docs/architecture/yaml/lib-modules.yaml  # Implementation modules
```

### Phase 2: Define Command

Спроси пользователя:
- Command name
- Parameters
- Purpose
- Which CLI tool (vless/mtproxy/vless-proxy)

### Phase 3: Implement (HYBRID)

**1. Add command handler:**

```bash
# In scripts/vless
cmd_quota() {
    local username="$1"
    local quota_gb="$2"

    # Logging
    log_info "Setting quota for $username: ${quota_gb}GB"

    # Call library function
    source "${LIB_DIR}/user_management.sh"
    set_user_quota "$username" "$quota_gb"
}
```

**2. Add to command dispatcher:**

```bash
case "$1" in
    ...
    quota)
        shift
        cmd_quota "$@"
        ;;
    ...
esac
```

**3. Update help text:**

```bash
show_help() {
    cat << EOF
...
  quota <user> <gb>    Set user bandwidth quota
...
EOF
}
```

**APPROVAL GATE:** Show diff, wait confirmation

### Phase 4: Update cli.yaml

```yaml
- name: "quota"
  syntax: "vless quota <username> <quota_gb>"
  description: "Set user monthly bandwidth quota in GB"
  parameters:
    - name: "username"
      type: "string"
      required: true
    - name: "quota_gb"
      type: "integer"
      required: true
  implementation:
    file: "/usr/local/bin/vless"
    function: "cmd_quota"
    calls: "set_user_quota() from user_management.sh"
  example: "sudo vless quota alice 100"
```

### Phase 5: Test

```bash
# Test command syntax
sudo vless quota
# Expected: Show usage

# Test with args
sudo vless quota testuser 50
```

### Phase 6: Git Commit

```
feat: add 'vless quota' command

Add CLI command to set user bandwidth quotas.
```
