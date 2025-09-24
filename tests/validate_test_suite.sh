#!/bin/bash

# Quick validation script for the module loading test suite
# This script performs basic checks to ensure the test suite is properly set up

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Color codes
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

echo -e "${BLUE}Validating Module Loading Test Suite Setup${NC}"
echo "================================================"

# Check 1: Test files exist and are executable
echo "1. Checking test files..."
test_files=(
    "test_module_loading_fixes.sh"
    "test_readonly_variable_conflicts.sh"
    "test_script_dir_handling.sh"
    "test_container_management_module.sh"
    "run_module_loading_tests.sh"
)

all_files_ok=true
for file in "${test_files[@]}"; do
    if [[ -f "${SCRIPT_DIR}/${file}" ]] && [[ -x "${SCRIPT_DIR}/${file}" ]]; then
        echo -e "   ${GREEN}✓${NC} $file"
    else
        echo -e "   ${RED}✗${NC} $file (missing or not executable)"
        all_files_ok=false
    fi
done

# Check 2: Module files exist
echo "2. Checking module files..."
modules_dir="${PROJECT_ROOT}/modules"
module_files=(
    "common_utils.sh"
    "docker_setup.sh"
    "container_management.sh"
)

all_modules_ok=true
for file in "${module_files[@]}"; do
    if [[ -f "${modules_dir}/${file}" ]] && [[ -r "${modules_dir}/${file}" ]]; then
        echo -e "   ${GREEN}✓${NC} $file"
    else
        echo -e "   ${RED}✗${NC} $file (missing or not readable)"
        all_modules_ok=false
    fi
done

# Check 3: Test basic module loading
echo "3. Testing basic module loading..."
temp_script=$(mktemp)
cat > "$temp_script" << EOF
#!/bin/bash
set -euo pipefail
source "${modules_dir}/common_utils.sh"
if declare -F log_info >/dev/null; then
    echo "SUCCESS"
else
    echo "FAILED"
fi
EOF

chmod +x "$temp_script"
if result=$("$temp_script" 2>/dev/null) && [[ "$result" == "SUCCESS" ]]; then
    echo -e "   ${GREEN}✓${NC} Basic module loading works"
    module_loading_ok=true
else
    echo -e "   ${RED}✗${NC} Basic module loading failed"
    module_loading_ok=false
fi
rm -f "$temp_script"

# Check 4: Test help functionality
echo "4. Testing help functionality..."
if "${SCRIPT_DIR}/run_module_loading_tests.sh" --help >/dev/null 2>&1; then
    echo -e "   ${GREEN}✓${NC} Help functionality works"
    help_ok=true
else
    echo -e "   ${RED}✗${NC} Help functionality failed"
    help_ok=false
fi

# Summary
echo
echo "Validation Summary:"
echo "==================="

if [[ "$all_files_ok" == true ]] && [[ "$all_modules_ok" == true ]] && \
   [[ "$module_loading_ok" == true ]] && [[ "$help_ok" == true ]]; then
    echo -e "${GREEN}✓ All validation checks passed!${NC}"
    echo -e "${GREEN}✓ Test suite is ready to use${NC}"
    echo
    echo "You can now run the full test suite with:"
    echo "  ./run_module_loading_tests.sh"
    exit 0
else
    echo -e "${RED}✗ Some validation checks failed${NC}"
    echo "Please fix the issues above before running the test suite"
    exit 1
fi