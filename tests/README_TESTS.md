# VLESS+Reality VPN Management System - Test Suite

## Overview

This comprehensive test suite provides automated testing for the VLESS+Reality VPN Management System across all implementation phases. The test framework includes unit tests, integration tests, security validation, performance benchmarking, and comprehensive reporting capabilities.

## Test Architecture

### 🧪 Test Framework Components

1. **Test Framework Core** (`test_framework.sh`)
   - Common test utilities and assertion functions
   - Test execution tracking and reporting
   - Mock function capabilities
   - Temporary file and directory management

2. **Master Test Runner** (`run_all_tests.sh`)
   - Orchestrates all test execution
   - Parallel and sequential execution modes
   - Comprehensive reporting and dashboards
   - Multiple output formats (JSON, HTML, XML, Markdown)

3. **Results Aggregator** (`test_results_aggregator.sh`)
   - Advanced test results analysis
   - Trend analysis and comparison tools
   - Interactive dashboards
   - Multiple export formats

### 📋 Test Categories

#### Unit Tests
- **`test_common_utils.sh`** - Core utility functions
- **`test_user_management.sh`** - User CRUD operations
- **`test_docker_services.sh`** - Docker service management
- **`test_backup_restore.sh`** - Backup and restore functionality
- **`test_security_hardening.sh`** - Security configuration tests

#### Integration Tests
- **`test_phase1_integration.sh`** - Core infrastructure setup workflow
- Additional integration tests for Phases 2-5 (following same pattern)

#### Security Validation
- **`test_security_validation.sh`** - Comprehensive security testing
  - Network security scanning
  - TLS/SSL configuration validation
  - Authentication mechanism testing
  - Access control verification
  - Penetration testing simulation
  - Compliance validation (CIS, NIST, GDPR, ISO 27001)

#### Performance Benchmarking
- **`test_performance_benchmarks.sh`** - Performance and load testing
  - Network throughput testing
  - Application performance metrics
  - System resource utilization
  - Load testing scenarios
  - Scalability analysis
  - Performance regression detection

## Quick Start

### Running All Tests

```bash
# Run all tests with default settings
./run_all_tests.sh

# Run with verbose output and parallel execution
./run_all_tests.sh --verbose --parallel

# Run only unit tests (quick validation)
./run_all_tests.sh --quick

# Run specific test categories
./run_all_tests.sh unit
./run_all_tests.sh security
./run_all_tests.sh performance
```

### Running Individual Test Suites

```bash
# Run specific test suite
./run_all_tests.sh --suite unit_common_utils

# Run with custom timeout
./run_all_tests.sh --timeout 1200 --suite performance_benchmarks

# Run multiple specific suites
./run_all_tests.sh --suite unit_common_utils --suite security_validation
```

### Test Results and Reporting

```bash
# Generate comprehensive reports
./run_all_tests.sh --verbose

# Disable report generation
./run_all_tests.sh --no-reports

# Aggregate and analyze results
./test_results_aggregator.sh aggregate

# Generate interactive dashboard
./test_results_aggregator.sh dashboard --format html

# Analyze trends over last 14 days
./test_results_aggregator.sh trends --days 14

# Export results in CSV format
./test_results_aggregator.sh export --format csv --output results.csv
```

## Test Configuration

### Environment Variables

```bash
# Test execution configuration
export TEST_TIMEOUT=600              # Test timeout in seconds (default: 600)
export PARALLEL_EXECUTION=true       # Enable parallel execution
export VERBOSE_OUTPUT=true           # Enable verbose output
export GENERATE_REPORTS=true         # Generate comprehensive reports

# Results management
export MAX_HISTORY_DAYS=30           # Days to keep test history
export TREND_ANALYSIS_DAYS=7         # Days for trend analysis

# Performance test parameters
export CONCURRENT_CONNECTIONS=100    # Concurrent connections for load testing
export TEST_DURATION=30              # Performance test duration
export PAYLOAD_SIZE=1024              # Test payload size
```

### Custom Configuration

Create a `.test_config` file in the tests directory:

```bash
# Custom test configuration
TEST_TIMEOUT=1200
PARALLEL_EXECUTION=true
VERBOSE_OUTPUT=false
CONCURRENT_CONNECTIONS=200
TEST_DURATION=60
```

## Test Results

### Output Structure

```
tests/
├── results/                          # Test execution results
│   ├── master_test_execution_*.log    # Master execution logs
│   ├── *_test_*.log                   # Individual test suite logs
│   ├── parsed_results_*.json          # Parsed test results
│   ├── reports/                       # Generated reports
│   │   ├── test_dashboard_*.html      # Interactive dashboards
│   │   ├── test_summary_*.json        # JSON summaries
│   │   ├── junit_results_*.xml        # JUnit XML reports
│   │   └── test_summary_*.md          # Markdown summaries
│   ├── archive/                       # Archived old results
│   └── trends/                        # Trend analysis data
```

### Report Types

1. **JSON Summary** - Machine-readable test results
2. **HTML Dashboard** - Interactive web-based dashboard with charts
3. **JUnit XML** - CI/CD integration compatible format
4. **Markdown Summary** - Human-readable summary report
5. **CSV Export** - Spreadsheet-compatible data export

## Test Development Guidelines

### Writing New Tests

1. **Follow naming convention**: `test_[module_name].sh`
2. **Use test framework functions**: Import and use `test_framework.sh`
3. **Implement required functions**:
   ```bash
   # Initialize test suite
   init_test_framework "Your Test Suite Name"

   # Individual test functions (must start with test_)
   test_your_functionality() {
       # Test implementation
       assert_equals "expected" "actual" "Test description"
   }

   # Finalize test suite
   finalize_test_suite
   ```

4. **Setup and cleanup**:
   ```bash
   setup_test_environment() {
       # Test environment setup
   }

   cleanup_test_environment() {
       # Test environment cleanup
       cleanup_temp_files
   }
   ```

### Best Practices

1. **Isolation**: Tests should not depend on external services or state
2. **Mocking**: Use mock functions for external dependencies
3. **Assertions**: Use clear, descriptive assertion messages
4. **Cleanup**: Always clean up temporary resources
5. **Documentation**: Document complex test scenarios
6. **Error Handling**: Test both success and failure scenarios

### Test Assertion Functions

```bash
# Basic assertions
assert_equals "expected" "actual" "Description"
assert_not_equals "not_expected" "actual" "Description"
assert_contains "haystack" "needle" "Description"
assert_not_contains "haystack" "needle" "Description"

# File system assertions
assert_file_exists "/path/to/file" "Description"
assert_file_not_exists "/path/to/file" "Description"

# Command execution assertions
assert_command_success "command" "Description"
assert_command_failure "command" "Description"

# Test completion
pass_test "Optional success message"
fail_test "Failure message"
skip_test "Skip reason"
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: VLESS Test Suite

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run Test Suite
        run: |
          cd tests
          ./run_all_tests.sh --no-reports
      - name: Upload Test Results
        uses: actions/upload-artifact@v3
        if: always()
        with:
          name: test-results
          path: tests/results/
```

### Jenkins Pipeline Example

```groovy
pipeline {
    agent any
    stages {
        stage('Test') {
            steps {
                sh 'cd tests && ./run_all_tests.sh'
            }
            post {
                always {
                    publishTestResults testResultsPattern: 'tests/results/reports/junit_*.xml'
                    publishHTML([
                        allowMissing: false,
                        alwaysLinkToLastBuild: true,
                        keepAll: true,
                        reportDir: 'tests/results/reports',
                        reportFiles: 'test_dashboard_*.html',
                        reportName: 'Test Dashboard'
                    ])
                }
            }
        }
    }
}
```

## Troubleshooting

### Common Issues

1. **Permission Denied**
   ```bash
   chmod +x tests/*.sh
   ```

2. **Missing Dependencies**
   ```bash
   # Install required tools
   sudo apt-get update
   sudo apt-get install jq bc curl
   ```

3. **Test Timeout**
   ```bash
   # Increase timeout
   export TEST_TIMEOUT=1200
   ./run_all_tests.sh
   ```

4. **Mock Command Issues**
   - Ensure mock commands are properly defined
   - Check function scope and availability

### Debug Mode

```bash
# Enable debug output
export VERBOSE_OUTPUT=true
bash -x ./run_all_tests.sh --suite unit_common_utils
```

### Log Analysis

```bash
# View recent test logs
ls -la tests/results/*.log

# Analyze specific test failure
grep -A 10 -B 5 "FAIL" tests/results/unit_common_utils_*.log

# Check test execution summary
tail -20 tests/results/master_test_execution_*.log
```

## Performance Considerations

### Test Execution Times

- **Unit Tests**: ~2-5 minutes total
- **Integration Tests**: ~5-10 minutes each
- **Security Validation**: ~10-15 minutes
- **Performance Benchmarks**: ~15-30 minutes
- **Full Suite**: ~30-60 minutes (sequential), ~15-25 minutes (parallel)

### Resource Requirements

- **CPU**: 2+ cores recommended for parallel execution
- **Memory**: 2GB+ available RAM
- **Disk**: 1GB+ free space for logs and reports
- **Network**: Internet connection for some integration tests

## Extending the Test Suite

### Adding New Test Categories

1. Create new test script following naming convention
2. Add to `TEST_SUITES` array in `run_all_tests.sh`
3. Update documentation and help text
4. Add appropriate test categorization

### Custom Reporting

1. Extend `test_results_aggregator.sh` with new export formats
2. Add custom dashboard components
3. Implement additional analysis functions

### Integration with External Tools

1. Add support for additional test frameworks
2. Implement custom result parsers
3. Create adapters for external reporting systems

## Support

For issues, questions, or contributions related to the test suite:

1. Check the troubleshooting section above
2. Review test logs in `tests/results/`
3. Examine individual test script implementations
4. Verify environment configuration and dependencies

---

**Test Suite Version**: 1.0.0
**Compatible with**: VLESS+Reality VPN Management System v1.0.0
**Last Updated**: $(date)
**Documentation**: This README