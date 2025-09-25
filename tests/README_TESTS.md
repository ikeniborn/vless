# VLESS+Reality VPN Service - Test Suite

This directory contains comprehensive automated tests for the VLESS+Reality VPN Service Manager implementation.

## Test Suite Overview

### Test Categories

1. **System Requirements Tests** (`test_requirements.sh`)
   - Root privilege validation
   - OS compatibility (Ubuntu 20.04+, Debian 11+)
   - Architecture support (x86_64, ARM64)
   - Resource requirements (RAM: 512MB+, Disk: 1GB+)
   - Port availability (443)

2. **Docker Installation Tests** (`test_installation.sh`)
   - Docker CE installation and verification
   - Docker Compose installation and verification
   - Service startup and configuration
   - Installation error handling and recovery

3. **Directory Structure Tests** (`test_structure.sh`)
   - Project directory creation
   - File permissions and security
   - Environment configuration
   - Structure integrity validation

4. **Main Integration Tests** (`test_vless_manager.sh`)
   - Full installation workflow
   - Function unit testing
   - Error handling and edge cases
   - Multi-platform compatibility

## Quick Start

### Run All Tests

```bash
# Navigate to test directory
cd /home/ikeniborn/Documents/Project/vless/tests/

# Make scripts executable (if needed)
chmod +x *.sh

# Run all test suites
./run_all_tests.sh run
```

### Run Specific Test Suite

```bash
# Run only system requirements tests
./run_all_tests.sh run-suite requirements

# Run only installation tests
./run_all_tests.sh run-suite installation

# Run only structure tests
./run_all_tests.sh run-suite structure

# Run only main integration tests
./run_all_tests.sh run-suite main
```

### Advanced Usage

```bash
# Run with verbose output
./run_all_tests.sh run --verbose

# Stop on first failure
./run_all_tests.sh run --stop-on-fail

# Archive test logs
./run_all_tests.sh run --archive /tmp/test-logs

# List available test suites
./run_all_tests.sh list

# Get help
./run_all_tests.sh help
```

## Individual Test Scripts

Each test script can be run independently:

```bash
# System requirements tests
./test_requirements.sh run

# Installation tests
./test_installation.sh run

# Structure tests
./test_structure.sh run

# Main integration tests
./test_vless_manager.sh run
```

## Safety Features

- **No System Modifications**: All tests use mocked system calls
- **Temporary Directories**: Tests create and clean up temporary test environments
- **Safe Docker Testing**: Docker installation tests are fully mocked
- **Permission Testing**: File permission tests use temporary directories
- **Network Isolation**: No actual network calls are made during testing

## Test Reports

Tests generate detailed reports including:

- Individual test results with pass/fail status
- Execution time and performance metrics
- Coverage analysis and test statistics
- Comprehensive final report with recommendations
- Archived logs for troubleshooting

## Expected Output

### Successful Test Run

```
================================================================================
         VLESS+Reality VPN Service Manager - Test Suite Runner
================================================================================
Version:        1.0.0
Project:        VLESS+Reality VPN Service Manager
Start Time:     2024-01-15 10:30:00
...

[1/4] Testing System Requirements...
[2/4] Testing Docker Installation...
[3/4] Testing Directory Structure...
[4/4] Testing Main Integration...

================================================================================
                           FINAL TEST RESULTS
================================================================================
Total Test Suites:    4
Passed Suites:       4
Failed Suites:       0
Success Rate:        100%

🎉 ALL TESTS PASSED! System is ready for deployment.
```

### Failed Test Run

```
================================================================================
                           FINAL TEST RESULTS
================================================================================
Total Test Suites:    4
Passed Suites:       3
Failed Suites:       1
Success Rate:        75%

❌ Some test suites failed. Please review and fix issues.

Suite Results:
  • requirements: PASSED
  • installation: FAILED
  • structure: PASSED
  • main: PASSED
```

## Troubleshooting

### Common Issues

1. **Permission Errors**
   ```bash
   chmod +x /home/ikeniborn/Documents/Project/vless/tests/*.sh
   ```

2. **Missing Dependencies**
   - Ensure bash, date, mkdir, chmod, stat are available
   - Check that vless-manager.sh exists in parent directory

3. **Test Environment**
   - Tests create temporary directories in /tmp/
   - Ensure sufficient disk space in /tmp/
   - Some tests may require specific shell features

### Debug Mode

Run individual tests with debug output:

```bash
# Enable bash debug mode
bash -x ./test_requirements.sh run

# Check test script syntax
bash -n ./test_requirements.sh
```

### Log Analysis

Test logs are stored in `/tmp/` with naming pattern:
- `vless_test_report_YYYYMMDD_HHMMSS.txt`
- `vless_requirements_test_report_YYYYMMDD_HHMMSS.txt`
- `vless_installation_test_report_YYYYMMDD_HHMMSS.txt`
- `vless_structure_test_report_YYYYMMDD_HHMMSS.txt`

## Test Development

### Adding New Tests

1. Create test function following naming convention:
   ```bash
   test_your_feature() {
       test_log "INFO" "Testing your feature"
       # Test implementation
       assert_equals "expected" "actual" "Test name"
   }
   ```

2. Add to main test execution function:
   ```bash
   test_your_feature
   ```

3. Update test counters and reporting

### Test Assertion Functions

Available assertion functions:
- `assert_equals expected actual "test_name"`
- `assert_return_code expected_code actual_code "test_name"`
- `assert_output_contains expected_text actual_output "test_name"`
- `assert_file_exists file_path "test_name"`
- `assert_directory_exists dir_path "test_name"`
- `assert_permissions path expected_perms "test_name"`

## Integration with CI/CD

Tests are designed for integration with automated build systems:

```bash
# Exit code 0 = all tests passed
# Exit code 1 = some tests failed
./run_all_tests.sh run
echo "Test exit code: $?"
```

## Version Information

- Test Suite Version: 1.0.0
- Target System: VLESS+Reality VPN Service Manager
- Compatibility: Ubuntu 20.04+, Debian 11+, x86_64/ARM64
- Shell Requirements: Bash 4.0+

## Support

For test-related issues:
1. Check individual test logs for detailed error information
2. Verify system meets test requirements
3. Ensure all test scripts are executable
4. Review comprehensive test report for recommendations