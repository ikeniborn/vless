#!/bin/bash

# VLESS+Reality VPN Management System - SCRIPT_DIR Handling Test Suite
# Version: 1.0.0
# Description: Comprehensive tests for SCRIPT_DIR handling across modules
#
# This test suite validates:
# - Proper SCRIPT_DIR detection in different execution contexts
# - SCRIPT_DIR consistency across module sourcing
# - Path resolution accuracy
# - Cross-directory sourcing support

set -euo pipefail

# Test configuration
readonly TEST_NAME="SCRIPT_DIR Handling"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly MODULES_DIR="${PROJECT_ROOT}/modules"

# Test results tracking
declare -g TESTS_PASSED=0
declare -g TESTS_FAILED=0
declare -g TOTAL_TESTS=0

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

# Test framework functions
start_test() {
    local test_name="$1"
    log_info "Starting test: $test_name"
    ((TOTAL_TESTS++))
}

pass_test() {
    local test_name="$1"
    log_success "PASSED: $test_name"
    ((TESTS_PASSED++))
}

fail_test() {
    local test_name="$1"
    local reason="$2"
    log_error "FAILED: $test_name - $reason"
    ((TESTS_FAILED++))
}

# Test 1: Basic SCRIPT_DIR detection
test_basic_script_dir_detection() {
    local test_name="Basic SCRIPT_DIR Detection"
    start_test "$test_name"

    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

source "${MODULES_DIR}/common_utils.sh"

# SCRIPT_DIR should point to modules directory
if [[ "\$SCRIPT_DIR" == "${MODULES_DIR}" ]]; then
    exit 0
else
    echo "SCRIPT_DIR mismatch: expected ${MODULES_DIR}, got \$SCRIPT_DIR" >&2
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Basic SCRIPT_DIR detection failed"
    fi

    rm -f "$temp_script"
}

# Test 2: SCRIPT_DIR from different working directories
test_script_dir_from_different_cwd() {
    local test_name="SCRIPT_DIR from Different CWD"
    start_test "$test_name"

    local temp_script=$(mktemp)
    local temp_dir=$(mktemp -d)

    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Change to a different directory
cd "$temp_dir"

# Source the module
source "${MODULES_DIR}/common_utils.sh"

# SCRIPT_DIR should still be modules directory, not temp_dir
if [[ "\$SCRIPT_DIR" == "${MODULES_DIR}" ]]; then
    exit 0
else
    echo "SCRIPT_DIR affected by CWD: expected ${MODULES_DIR}, got \$SCRIPT_DIR" >&2
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "SCRIPT_DIR affected by current working directory"
    fi

    rm -f "$temp_script"
    rm -rf "$temp_dir"
}

# Test 3: SCRIPT_DIR with symbolic links
test_script_dir_with_symlinks() {
    local test_name="SCRIPT_DIR with Symbolic Links"
    start_test "$test_name"

    local temp_dir=$(mktemp -d)
    local symlink_dir="${temp_dir}/symlinked_modules"
    local temp_script=$(mktemp)

    # Create symbolic link to modules directory
    ln -sf "$MODULES_DIR" "$symlink_dir"

    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Source the module via symbolic link
source "${symlink_dir}/common_utils.sh"

# SCRIPT_DIR should resolve to the actual modules directory
if [[ "\$SCRIPT_DIR" == "${MODULES_DIR}" ]]; then
    exit 0
else
    echo "SCRIPT_DIR not resolved through symlink: expected ${MODULES_DIR}, got \$SCRIPT_DIR" >&2
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "SCRIPT_DIR not properly resolved through symbolic links"
    fi

    rm -f "$temp_script"
    rm -rf "$temp_dir"
}

# Test 4: SCRIPT_DIR preservation across nested sourcing
test_script_dir_nested_sourcing() {
    local test_name="SCRIPT_DIR Nested Sourcing"
    start_test "$test_name"

    local temp_script=$(mktemp)
    local temp_module1=$(mktemp)
    local temp_module2=$(mktemp)

    # Create nested sourcing modules
    cat > "$temp_module2" << 'EOF'
#!/bin/bash
set -euo pipefail

# This module doesn't change SCRIPT_DIR
test_nested_function() {
    echo "SCRIPT_DIR in nested: $SCRIPT_DIR"
}
EOF

    cat > "$temp_module1" << EOF
#!/bin/bash
set -euo pipefail

# Source common_utils first
source "${MODULES_DIR}/common_utils.sh"

# Source another module
source "$temp_module2"

test_main_function() {
    echo "SCRIPT_DIR in main: \$SCRIPT_DIR"
}
EOF

    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Source the nested modules
source "$temp_module1"

# SCRIPT_DIR should still point to modules directory
if [[ "\$SCRIPT_DIR" == "${MODULES_DIR}" ]]; then
    exit 0
else
    echo "SCRIPT_DIR changed during nested sourcing: \$SCRIPT_DIR" >&2
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "SCRIPT_DIR not preserved during nested sourcing"
    fi

    rm -f "$temp_script" "$temp_module1" "$temp_module2"
}

# Test 5: SCRIPT_DIR predefined handling
test_script_dir_predefined() {
    local test_name="SCRIPT_DIR Predefined Handling"
    start_test "$test_name"

    local temp_script=$(mktemp)
    local custom_dir=$(mktemp -d)

    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Predefine SCRIPT_DIR
SCRIPT_DIR="$custom_dir"

# Source common_utils.sh
source "${MODULES_DIR}/common_utils.sh"

# SCRIPT_DIR should remain our predefined value
if [[ "\$SCRIPT_DIR" == "$custom_dir" ]]; then
    exit 0
else
    echo "Predefined SCRIPT_DIR was overwritten: \$SCRIPT_DIR" >&2
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Predefined SCRIPT_DIR was overwritten"
    fi

    rm -f "$temp_script"
    rm -rf "$custom_dir"
}

# Test 6: PROJECT_ROOT derivation from SCRIPT_DIR
test_project_root_derivation() {
    local test_name="PROJECT_ROOT Derivation"
    start_test "$test_name"

    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

source "${MODULES_DIR}/common_utils.sh"

# PROJECT_ROOT should be parent of SCRIPT_DIR (modules directory)
expected_project_root="${PROJECT_ROOT}"
if [[ "\$PROJECT_ROOT" == "\$expected_project_root" ]]; then
    exit 0
else
    echo "PROJECT_ROOT derivation failed: expected \$expected_project_root, got \$PROJECT_ROOT" >&2
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "PROJECT_ROOT not properly derived from SCRIPT_DIR"
    fi

    rm -f "$temp_script"
}

# Test 7: SCRIPT_DIR in subshells
test_script_dir_in_subshells() {
    local test_name="SCRIPT_DIR in Subshells"
    start_test "$test_name"

    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

source "${MODULES_DIR}/common_utils.sh"

# Test SCRIPT_DIR in subshell
subshell_script_dir=\$(
    echo "\$SCRIPT_DIR"
)

# Should be the same as main shell
if [[ "\$subshell_script_dir" == "\$SCRIPT_DIR" ]] && [[ "\$SCRIPT_DIR" == "${MODULES_DIR}" ]]; then
    exit 0
else
    echo "SCRIPT_DIR not preserved in subshell: main=\$SCRIPT_DIR, sub=\$subshell_script_dir" >&2
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "SCRIPT_DIR not preserved in subshells"
    fi

    rm -f "$temp_script"
}

# Test 8: SCRIPT_DIR with relative paths
test_script_dir_relative_paths() {
    local test_name="SCRIPT_DIR with Relative Paths"
    start_test "$test_name"

    local temp_script=$(mktemp)
    local relative_modules_path="../modules"

    # Change to project root to make relative path work
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Change to project root
cd "${PROJECT_ROOT}"

# Source using relative path
source "${relative_modules_path}/common_utils.sh"

# SCRIPT_DIR should still be absolute path
if [[ "\$SCRIPT_DIR" == "${MODULES_DIR}" ]]; then
    exit 0
else
    echo "SCRIPT_DIR not absolute with relative sourcing: \$SCRIPT_DIR" >&2
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "SCRIPT_DIR not properly resolved from relative paths"
    fi

    rm -f "$temp_script"
}

# Test 9: SCRIPT_DIR consistency across modules
test_script_dir_consistency() {
    local test_name="SCRIPT_DIR Consistency Across Modules"
    start_test "$test_name"

    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Source multiple modules
source "${MODULES_DIR}/common_utils.sh"
common_utils_script_dir="\$SCRIPT_DIR"

source "${MODULES_DIR}/docker_setup.sh"
docker_setup_script_dir="\$SCRIPT_DIR"

source "${MODULES_DIR}/container_management.sh"
container_mgmt_script_dir="\$SCRIPT_DIR"

# All should have the same SCRIPT_DIR
if [[ "\$common_utils_script_dir" == "\$docker_setup_script_dir" ]] && \
   [[ "\$docker_setup_script_dir" == "\$container_mgmt_script_dir" ]] && \
   [[ "\$container_mgmt_script_dir" == "${MODULES_DIR}" ]]; then
    exit 0
else
    echo "SCRIPT_DIR inconsistency across modules" >&2
    echo "common_utils: \$common_utils_script_dir" >&2
    echo "docker_setup: \$docker_setup_script_dir" >&2
    echo "container_mgmt: \$container_mgmt_script_dir" >&2
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "SCRIPT_DIR inconsistent across modules"
    fi

    rm -f "$temp_script"
}

# Test 10: SCRIPT_DIR with copied modules
test_script_dir_copied_modules() {
    local test_name="SCRIPT_DIR with Copied Modules"
    start_test "$test_name"

    local temp_dir=$(mktemp -d)
    local temp_script=$(mktemp)

    # Copy common_utils.sh to temporary directory
    cp "${MODULES_DIR}/common_utils.sh" "$temp_dir/"

    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Source the copied module
source "${temp_dir}/common_utils.sh"

# SCRIPT_DIR should point to the temp directory
if [[ "\$SCRIPT_DIR" == "$temp_dir" ]]; then
    exit 0
else
    echo "SCRIPT_DIR not updated for copied module: expected $temp_dir, got \$SCRIPT_DIR" >&2
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "SCRIPT_DIR not properly set for copied modules"
    fi

    rm -f "$temp_script"
    rm -rf "$temp_dir"
}

# Test 11: SCRIPT_DIR with environment override
test_script_dir_env_override() {
    local test_name="SCRIPT_DIR Environment Override"
    start_test "$test_name"

    local temp_script=$(mktemp)
    local override_dir=$(mktemp -d)

    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Set SCRIPT_DIR via environment
export SCRIPT_DIR="$override_dir"

# Source module
source "${MODULES_DIR}/common_utils.sh"

# SCRIPT_DIR should preserve environment value
if [[ "\$SCRIPT_DIR" == "$override_dir" ]]; then
    exit 0
else
    echo "Environment SCRIPT_DIR override failed: \$SCRIPT_DIR" >&2
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Environment SCRIPT_DIR override not respected"
    fi

    rm -f "$temp_script"
    rm -rf "$override_dir"
}

# Test 12: SCRIPT_DIR path normalization
test_script_dir_normalization() {
    local test_name="SCRIPT_DIR Path Normalization"
    start_test "$test_name"

    local temp_script=$(mktemp)
    local messy_path="${MODULES_DIR}/../modules/./common_utils.sh"

    cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail

# Source using messy path with .. and .
source "$messy_path"

# SCRIPT_DIR should be normalized
if [[ "\$SCRIPT_DIR" == "${MODULES_DIR}" ]]; then
    exit 0
else
    echo "SCRIPT_DIR not normalized: \$SCRIPT_DIR" >&2
    exit 1
fi
EOF

    chmod +x "$temp_script"

    if "$temp_script" 2>/dev/null; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "SCRIPT_DIR path not properly normalized"
    fi

    rm -f "$temp_script"
}

# Test summary
print_test_summary() {
    echo
    echo "=============================================="
    echo "SCRIPT_DIR Handling Test Results"
    echo "=============================================="
    echo "Total tests: $TOTAL_TESTS"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "\n${GREEN}All SCRIPT_DIR handling tests passed!${NC}"
        return 0
    else
        echo -e "\n${RED}Some SCRIPT_DIR handling tests failed.${NC}"
        return 1
    fi
}

# Main test execution
main() {
    log_info "Starting SCRIPT_DIR Handling Test Suite"
    echo "Project Root: $PROJECT_ROOT"
    echo "Modules Directory: $MODULES_DIR"
    echo

    # Run all tests
    test_basic_script_dir_detection
    test_script_dir_from_different_cwd
    test_script_dir_with_symlinks
    test_script_dir_nested_sourcing
    test_script_dir_predefined
    test_project_root_derivation
    test_script_dir_in_subshells
    test_script_dir_relative_paths
    test_script_dir_consistency
    test_script_dir_copied_modules
    test_script_dir_env_override
    test_script_dir_normalization

    # Print summary
    print_test_summary
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi