#!/bin/bash
# tests/test_helper.bash - Common test utilities and setup
# Used by all test suites

# Project paths
export PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LIB_DIR="${PROJECT_ROOT}/lib"
export TESTS_DIR="${PROJECT_ROOT}/tests"
export TEMP_DIR="${TESTS_DIR}/tmp"

# Test configuration
export BATS_TEST_TIMEOUT=30

#######################################
# Set up test environment
# Creates temporary directory and sets up mock environment
# Globals:
#   TEMP_DIR
# Arguments:
#   None
# Returns:
#   None
#######################################
setup_test_env() {
    # Create temporary directory
    mkdir -p "$TEMP_DIR"

    # Set up mock installation directory
    export MOCK_INSTALL_DIR="${TEMP_DIR}/opt/vless"
    mkdir -p "$MOCK_INSTALL_DIR"/{config,data,keys,logs,backups}

    # Create mock files
    touch "${MOCK_INSTALL_DIR}/config/xray_config.json"
    echo '{"users":[]}' > "${MOCK_INSTALL_DIR}/data/users.json"

    # Set permissions
    chmod 750 "$MOCK_INSTALL_DIR"
}

#######################################
# Clean up test environment
# Removes temporary files and directories
# Globals:
#   TEMP_DIR
# Arguments:
#   None
# Returns:
#   None
#######################################
teardown_test_env() {
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

#######################################
# Mock command output
# Replaces a command with mock output for testing
# Arguments:
#   $1 - Command name
#   $2 - Mock output
# Returns:
#   None
#######################################
mock_command() {
    local cmd="$1"
    local output="$2"

    # Create mock script
    cat > "${TEMP_DIR}/${cmd}" <<EOF
#!/bin/bash
echo "$output"
exit 0
EOF

    chmod +x "${TEMP_DIR}/${cmd}"

    # Add to PATH
    export PATH="${TEMP_DIR}:${PATH}"
}

#######################################
# Assert file exists
# Arguments:
#   $1 - File path
# Returns:
#   0 if exists, 1 if not
#######################################
assert_file_exists() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo "Assertion failed: File does not exist: $file" >&2
        return 1
    fi

    return 0
}

#######################################
# Assert directory exists
# Arguments:
#   $1 - Directory path
# Returns:
#   0 if exists, 1 if not
#######################################
assert_dir_exists() {
    local dir="$1"

    if [[ ! -d "$dir" ]]; then
        echo "Assertion failed: Directory does not exist: $dir" >&2
        return 1
    fi

    return 0
}

#######################################
# Assert string contains
# Arguments:
#   $1 - Haystack
#   $2 - Needle
# Returns:
#   0 if contains, 1 if not
#######################################
assert_contains() {
    local haystack="$1"
    local needle="$2"

    if [[ ! "$haystack" =~ $needle ]]; then
        echo "Assertion failed: '$haystack' does not contain '$needle'" >&2
        return 1
    fi

    return 0
}

#######################################
# Assert command succeeds
# Arguments:
#   $@ - Command and arguments
# Returns:
#   0 if command succeeds, 1 if fails
#######################################
assert_success() {
    if ! "$@"; then
        echo "Assertion failed: Command failed: $*" >&2
        return 1
    fi

    return 0
}

#######################################
# Assert command fails
# Arguments:
#   $@ - Command and arguments
# Returns:
#   0 if command fails, 1 if succeeds
#######################################
assert_failure() {
    if "$@"; then
        echo "Assertion failed: Command succeeded when it should have failed: $*" >&2
        return 1
    fi

    return 0
}

#######################################
# Skip test if not root
# Skips test if not running as root user
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None (skips test)
#######################################
skip_if_not_root() {
    if [[ $EUID -ne 0 ]]; then
        skip "This test requires root privileges"
    fi
}

#######################################
# Skip test if command not found
# Arguments:
#   $1 - Command name
# Returns:
#   None (skips test)
#######################################
skip_if_command_missing() {
    local cmd="$1"

    if ! command -v "$cmd" &>/dev/null; then
        skip "Required command not found: $cmd"
    fi
}

#######################################
# Create mock Xray config
# Creates a minimal valid Xray configuration for testing
# Arguments:
#   $1 - Output file path
# Returns:
#   0 on success
#######################################
create_mock_xray_config() {
    local output="$1"

    cat > "$output" <<'EOF'
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [{
    "port": 443,
    "protocol": "vless",
    "settings": {
      "clients": [],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "www.google.com:443",
        "xver": 0,
        "serverNames": ["www.google.com"],
        "privateKey": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
        "shortIds": ["0123456789abcdef"]
      }
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "tag": "direct"
  }]
}
EOF

    return 0
}

#######################################
# Create mock users.json
# Creates a mock users database for testing
# Arguments:
#   $1 - Output file path
#   $2 - Number of users (optional, default: 0)
# Returns:
#   0 on success
#######################################
create_mock_users_json() {
    local output="$1"
    local count="${2:-0}"

    local users="[]"

    if [[ $count -gt 0 ]]; then
        users="["
        for ((i=1; i<=count; i++)); do
            local uuid="$(uuidgen 2>/dev/null || echo "00000000-0000-0000-0000-$(printf '%012d' $i)")"
            users+=$(cat <<EOF
{
  "username": "testuser${i}",
  "uuid": "${uuid}",
  "created": "2025-10-02T00:00:00Z"
}
EOF
            )
            [[ $i -lt $count ]] && users+=","
        done
        users+="]"
    fi

    echo "{\"users\":${users}}" > "$output"

    return 0
}

#######################################
# Wait for condition with timeout
# Arguments:
#   $1 - Timeout in seconds
#   $2 - Command to check (must return 0 when condition met)
# Returns:
#   0 if condition met, 1 if timeout
#######################################
wait_for_condition() {
    local timeout="$1"
    shift
    local check_cmd="$@"

    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        if eval "$check_cmd"; then
            return 0
        fi

        sleep 1
        ((elapsed++))
    done

    return 1
}

# Export functions for use in tests
export -f setup_test_env
export -f teardown_test_env
export -f mock_command
export -f assert_file_exists
export -f assert_dir_exists
export -f assert_contains
export -f assert_success
export -f assert_failure
export -f skip_if_not_root
export -f skip_if_command_missing
export -f create_mock_xray_config
export -f create_mock_users_json
export -f wait_for_condition
