#!/bin/bash

# VLESS+Reality VPN Management System - Test Results Aggregator
# Version: 1.0.0
# Description: Advanced test results aggregation, analysis, and reporting system

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly RESULTS_DIR="${SCRIPT_DIR}/results"
readonly REPORTS_DIR="${RESULTS_DIR}/reports"
readonly ARCHIVE_DIR="${RESULTS_DIR}/archive"
readonly TRENDS_DIR="${RESULTS_DIR}/trends"

# Report configuration
readonly REPORT_VERSION="1.0.0"
readonly MAX_HISTORY_DAYS=${MAX_HISTORY_DAYS:-30}
readonly TREND_ANALYSIS_DAYS=${TREND_ANALYSIS_DAYS:-7}

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Initialize aggregator
initialize_aggregator() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           VLESS Test Results Aggregator v${REPORT_VERSION}                 ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Create necessary directories
    mkdir -p "$RESULTS_DIR" "$REPORTS_DIR" "$ARCHIVE_DIR" "$TRENDS_DIR"

    echo -e "${BLUE}📁 Results Directory: ${WHITE}$RESULTS_DIR${NC}"
    echo -e "${BLUE}📊 Reports Directory: ${WHITE}$REPORTS_DIR${NC}"
    echo -e "${BLUE}🗄️  Archive Directory: ${WHITE}$ARCHIVE_DIR${NC}"
    echo -e "${BLUE}📈 Trends Directory: ${WHITE}$TRENDS_DIR${NC}"
    echo ""
}

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [COMMAND]

Advanced test results aggregation and reporting system.

COMMANDS:
    aggregate           Aggregate latest test results (default)
    trends             Analyze test trends over time
    compare            Compare test results between runs
    archive            Archive old test results
    dashboard          Generate interactive dashboard
    metrics            Extract detailed metrics
    export             Export results in various formats
    cleanup            Clean up old files and optimize storage

OPTIONS:
    -h, --help         Show this help message
    -v, --verbose      Enable verbose output
    -f, --format       Output format (json|html|xml|csv|markdown)
    -d, --days DAYS    Number of days to analyze (default: 7)
    -o, --output FILE  Output file path
    -t, --type TYPE    Report type (summary|detailed|trends|comparison)
    --no-archive       Skip archiving of processed results
    --include-logs     Include detailed log analysis
    --filter PATTERN   Filter results by pattern

EXAMPLES:
    $0                                    # Aggregate latest results
    $0 trends --days 14                  # Analyze 14-day trends
    $0 dashboard --format html           # Generate HTML dashboard
    $0 export --format csv --output results.csv
    $0 compare run1.json run2.json       # Compare two test runs
    $0 cleanup --days 30                 # Clean files older than 30 days

ENVIRONMENT VARIABLES:
    MAX_HISTORY_DAYS     Maximum days to keep in history (default: 30)
    TREND_ANALYSIS_DAYS  Days to analyze for trends (default: 7)
    VERBOSE_OUTPUT       Enable verbose output
    RESULTS_FORMAT       Default output format

EOF
}

# Parse log files and extract test results
parse_test_results() {
    local log_files=("$@")
    local parsed_results="${RESULTS_DIR}/parsed_results_$(date +%Y%m%d_%H%M%S).json"

    echo -e "${CYAN}📋 Parsing test results from ${#log_files[@]} log files...${NC}"

    # Initialize JSON structure
    cat > "$parsed_results" << 'EOF'
{
    "metadata": {
        "timestamp": "",
        "version": "",
        "total_files_processed": 0
    },
    "test_suites": [],
    "summary": {
        "total_suites": 0,
        "passed_suites": 0,
        "failed_suites": 0,
        "skipped_suites": 0,
        "total_tests": 0,
        "passed_tests": 0,
        "failed_tests": 0,
        "skipped_tests": 0,
        "total_duration": 0
    }
}
EOF

    # Update metadata
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --arg timestamp "$timestamp" \
       --arg version "$REPORT_VERSION" \
       --argjson total "${#log_files[@]}" \
       '.metadata.timestamp = $timestamp | .metadata.version = $version | .metadata.total_files_processed = $total' \
       "$parsed_results" > "${parsed_results}.tmp" && mv "${parsed_results}.tmp" "$parsed_results"

    # Parse each log file
    for log_file in "${log_files[@]}"; do
        if [[ -f "$log_file" ]]; then
            echo -e "${BLUE}  Processing: ${WHITE}$(basename "$log_file")${NC}"
            parse_single_log_file "$log_file" "$parsed_results"
        else
            echo -e "${YELLOW}  Warning: File not found: $log_file${NC}"
        fi
    done

    # Calculate summary statistics
    calculate_summary_statistics "$parsed_results"

    echo -e "${GREEN}✓ Parsing completed: ${WHITE}$(basename "$parsed_results")${NC}"
    echo "$parsed_results"
}

# Parse a single log file
parse_single_log_file() {
    local log_file="$1"
    local results_file="$2"

    # Extract test suite information
    local suite_name=$(basename "$log_file" .log | sed 's/_[0-9]*$//')
    local start_time=""
    local end_time=""
    local duration=0
    local tests_passed=0
    local tests_failed=0
    local tests_skipped=0
    local suite_status="unknown"

    # Parse log content
    if [[ -f "$log_file" ]]; then
        # Extract test counts
        tests_passed=$(grep -c "PASS" "$log_file" 2>/dev/null || echo "0")
        tests_failed=$(grep -c "FAIL" "$log_file" 2>/dev/null || echo "0")
        tests_skipped=$(grep -c "SKIP" "$log_file" 2>/dev/null || echo "0")

        # Determine suite status
        if [[ $tests_failed -eq 0 ]]; then
            suite_status="passed"
        else
            suite_status="failed"
        fi

        # Extract timing information (if available)
        start_time=$(grep "Starting test suite:" "$log_file" | head -1 | grep -o "[0-9-]* [0-9:]*" || echo "")
        end_time=$(grep "Test suite completed:" "$log_file" | tail -1 | grep -o "[0-9-]* [0-9:]*" || echo "")

        # Calculate duration (mock if not available)
        if [[ -n "$start_time" && -n "$end_time" ]]; then
            duration=$(( $(date -d "$end_time" +%s) - $(date -d "$start_time" +%s) ))
        else
            duration=$((tests_passed + tests_failed + tests_skipped))  # Mock duration
        fi
    fi

    # Create test suite object
    local suite_json=$(cat << EOF
{
    "name": "$suite_name",
    "status": "$suite_status",
    "start_time": "$start_time",
    "end_time": "$end_time",
    "duration": $duration,
    "tests": {
        "total": $((tests_passed + tests_failed + tests_skipped)),
        "passed": $tests_passed,
        "failed": $tests_failed,
        "skipped": $tests_skipped
    },
    "log_file": "$log_file",
    "test_details": []
}
EOF
    )

    # Extract individual test details
    local test_details=""
    if [[ -f "$log_file" ]]; then
        # Parse individual test results
        while IFS= read -r line; do
            if [[ "$line" =~ Running:.*test_ ]]; then
                local test_name=$(echo "$line" | grep -o "test_[a-zA-Z_]*" || echo "unknown_test")
                local test_status="unknown"
                local test_duration=1

                # Look for the result of this test in subsequent lines
                if grep -A 5 "$test_name" "$log_file" | grep -q "PASS"; then
                    test_status="passed"
                elif grep -A 5 "$test_name" "$log_file" | grep -q "FAIL"; then
                    test_status="failed"
                elif grep -A 5 "$test_name" "$log_file" | grep -q "SKIP"; then
                    test_status="skipped"
                fi

                test_details+="{\"name\": \"$test_name\", \"status\": \"$test_status\", \"duration\": $test_duration},"
            fi
        done < "$log_file"

        # Remove trailing comma
        test_details=${test_details%,}
    fi

    # Update the suite object with test details
    if [[ -n "$test_details" ]]; then
        suite_json=$(echo "$suite_json" | jq ".test_details = [$test_details]")
    fi

    # Add suite to results file
    jq --argjson suite_data "$suite_json" '.test_suites += [$suite_data]' "$results_file" > "${results_file}.tmp" && mv "${results_file}.tmp" "$results_file"
}

# Calculate summary statistics
calculate_summary_statistics() {
    local results_file="$1"

    echo -e "${BLUE}  Calculating summary statistics...${NC}"

    # Calculate totals using jq
    local total_suites=$(jq '.test_suites | length' "$results_file")
    local passed_suites=$(jq '[.test_suites[] | select(.status == "passed")] | length' "$results_file")
    local failed_suites=$(jq '[.test_suites[] | select(.status == "failed")] | length' "$results_file")
    local skipped_suites=$(jq '[.test_suites[] | select(.status == "skipped")] | length' "$results_file")

    local total_tests=$(jq '[.test_suites[].tests.total] | add // 0' "$results_file")
    local passed_tests=$(jq '[.test_suites[].tests.passed] | add // 0' "$results_file")
    local failed_tests=$(jq '[.test_suites[].tests.failed] | add // 0' "$results_file")
    local skipped_tests=$(jq '[.test_suites[].tests.skipped] | add // 0' "$results_file")
    local total_duration=$(jq '[.test_suites[].duration] | add // 0' "$results_file")

    # Update summary in results file
    jq --argjson total_suites "$total_suites" \
       --argjson passed_suites "$passed_suites" \
       --argjson failed_suites "$failed_suites" \
       --argjson skipped_suites "$skipped_suites" \
       --argjson total_tests "$total_tests" \
       --argjson passed_tests "$passed_tests" \
       --argjson failed_tests "$failed_tests" \
       --argjson skipped_tests "$skipped_tests" \
       --argjson total_duration "$total_duration" \
       '.summary.total_suites = $total_suites |
        .summary.passed_suites = $passed_suites |
        .summary.failed_suites = $failed_suites |
        .summary.skipped_suites = $skipped_suites |
        .summary.total_tests = $total_tests |
        .summary.passed_tests = $passed_tests |
        .summary.failed_tests = $failed_tests |
        .summary.skipped_tests = $skipped_tests |
        .summary.total_duration = $total_duration' \
       "$results_file" > "${results_file}.tmp" && mv "${results_file}.tmp" "$results_file"
}

# Analyze test trends over time
analyze_test_trends() {
    local days="${1:-$TREND_ANALYSIS_DAYS}"
    local output_file="${2:-${TRENDS_DIR}/trend_analysis_$(date +%Y%m%d_%H%M%S).json}"

    echo -e "${CYAN}📈 Analyzing test trends over the last $days days...${NC}"

    # Find all result files from the specified time period
    local result_files=()
    while IFS= read -r -d '' file; do
        result_files+=("$file")
    done < <(find "$RESULTS_DIR" -name "parsed_results_*.json" -mtime -"$days" -print0 2>/dev/null)

    if [[ ${#result_files[@]} -eq 0 ]]; then
        echo -e "${YELLOW}⚠️  No test results found for the last $days days${NC}"
        return 1
    fi

    echo -e "${BLUE}  Found ${#result_files[@]} result files to analyze${NC}"

    # Initialize trend analysis structure
    cat > "$output_file" << EOF
{
    "metadata": {
        "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "analysis_period_days": $days,
        "total_result_files": ${#result_files[@]}
    },
    "trends": {
        "success_rate": [],
        "test_count": [],
        "duration": [],
        "failure_rate": []
    },
    "statistics": {
        "average_success_rate": 0,
        "trend_direction": "stable",
        "volatility": "low",
        "improvement_areas": []
    }
}
EOF

    # Process each result file chronologically
    local total_success_rate=0
    local file_count=0

    for result_file in $(printf '%s\n' "${result_files[@]}" | sort); do
        if [[ -f "$result_file" ]]; then
            local timestamp=$(jq -r '.metadata.timestamp // empty' "$result_file")
            local total_tests=$(jq '.summary.total_tests // 0' "$result_file")
            local passed_tests=$(jq '.summary.passed_tests // 0' "$result_file")
            local total_duration=$(jq '.summary.total_duration // 0' "$result_file")

            # Calculate success rate
            local success_rate=0
            if [[ $total_tests -gt 0 ]]; then
                success_rate=$(echo "scale=2; $passed_tests * 100 / $total_tests" | bc -l 2>/dev/null || echo "0")
            fi

            # Add data point to trends
            local data_point=$(cat << EOF
{
    "timestamp": "$timestamp",
    "success_rate": $success_rate,
    "total_tests": $total_tests,
    "passed_tests": $passed_tests,
    "duration": $total_duration
}
EOF
            )

            jq --argjson datapoint "$data_point" \
               '.trends.success_rate += [$datapoint] |
                .trends.test_count += [$datapoint] |
                .trends.duration += [$datapoint]' \
               "$output_file" > "${output_file}.tmp" && mv "${output_file}.tmp" "$output_file"

            total_success_rate=$(echo "$total_success_rate + $success_rate" | bc -l 2>/dev/null || echo "$total_success_rate")
            ((file_count++))
        fi
    done

    # Calculate trend statistics
    local average_success_rate=0
    if [[ $file_count -gt 0 ]]; then
        average_success_rate=$(echo "scale=2; $total_success_rate / $file_count" | bc -l 2>/dev/null || echo "0")
    fi

    # Determine trend direction (simplified analysis)
    local trend_direction="stable"
    if [[ $file_count -ge 3 ]]; then
        # Compare first third vs last third
        local first_third_avg=$(jq '[.trends.success_rate[:'"$((file_count/3))"'][].success_rate] | add / length' "$output_file" 2>/dev/null || echo "0")
        local last_third_avg=$(jq '[.trends.success_rate[-'"$((file_count/3))"':][].success_rate] | add / length' "$output_file" 2>/dev/null || echo "0")

        if (( $(echo "$last_third_avg > $first_third_avg + 5" | bc -l 2>/dev/null || echo "0") )); then
            trend_direction="improving"
        elif (( $(echo "$last_third_avg < $first_third_avg - 5" | bc -l 2>/dev/null || echo "0") )); then
            trend_direction="declining"
        fi
    fi

    # Update statistics
    jq --argjson avg_success_rate "$average_success_rate" \
       --arg trend_direction "$trend_direction" \
       '.statistics.average_success_rate = $avg_success_rate |
        .statistics.trend_direction = $trend_direction' \
       "$output_file" > "${output_file}.tmp" && mv "${output_file}.tmp" "$output_file"

    echo -e "${GREEN}✓ Trend analysis completed: ${WHITE}$(basename "$output_file")${NC}"
    echo "$output_file"
}

# Compare two test runs
compare_test_runs() {
    local run1_file="$1"
    local run2_file="$2"
    local comparison_output="${3:-${REPORTS_DIR}/comparison_$(date +%Y%m%d_%H%M%S).json}"

    echo -e "${CYAN}⚖️  Comparing test runs...${NC}"
    echo -e "${BLUE}  Run 1: ${WHITE}$(basename "$run1_file")${NC}"
    echo -e "${BLUE}  Run 2: ${WHITE}$(basename "$run2_file")${NC}"

    if [[ ! -f "$run1_file" || ! -f "$run2_file" ]]; then
        echo -e "${RED}❌ One or both result files not found${NC}"
        return 1
    fi

    # Extract data from both runs
    local run1_data=$(jq '.summary' "$run1_file")
    local run2_data=$(jq '.summary' "$run2_file")

    local run1_timestamp=$(jq -r '.metadata.timestamp // "unknown"' "$run1_file")
    local run2_timestamp=$(jq -r '.metadata.timestamp // "unknown"' "$run2_file")

    # Calculate differences
    local total_tests_diff=$(( $(jq '.total_tests' <<< "$run2_data") - $(jq '.total_tests' <<< "$run1_data") ))
    local passed_tests_diff=$(( $(jq '.passed_tests' <<< "$run2_data") - $(jq '.passed_tests' <<< "$run1_data") ))
    local failed_tests_diff=$(( $(jq '.failed_tests' <<< "$run2_data") - $(jq '.failed_tests' <<< "$run1_data") ))
    local duration_diff=$(( $(jq '.total_duration' <<< "$run2_data") - $(jq '.total_duration' <<< "$run1_data") ))

    # Calculate success rates
    local run1_success_rate=0
    local run2_success_rate=0
    local run1_total_tests=$(jq '.total_tests' <<< "$run1_data")
    local run2_total_tests=$(jq '.total_tests' <<< "$run2_data")

    if [[ $run1_total_tests -gt 0 ]]; then
        run1_success_rate=$(echo "scale=2; $(jq '.passed_tests' <<< "$run1_data") * 100 / $run1_total_tests" | bc -l 2>/dev/null || echo "0")
    fi

    if [[ $run2_total_tests -gt 0 ]]; then
        run2_success_rate=$(echo "scale=2; $(jq '.passed_tests' <<< "$run2_data") * 100 / $run2_total_tests" | bc -l 2>/dev/null || echo "0")
    fi

    local success_rate_diff=$(echo "scale=2; $run2_success_rate - $run1_success_rate" | bc -l 2>/dev/null || echo "0")

    # Generate comparison report
    cat > "$comparison_output" << EOF
{
    "metadata": {
        "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "comparison_type": "test_run_comparison",
        "run1": {
            "file": "$run1_file",
            "timestamp": "$run1_timestamp"
        },
        "run2": {
            "file": "$run2_file",
            "timestamp": "$run2_timestamp"
        }
    },
    "summary_comparison": {
        "run1": $run1_data,
        "run2": $run2_data,
        "differences": {
            "total_tests": $total_tests_diff,
            "passed_tests": $passed_tests_diff,
            "failed_tests": $failed_tests_diff,
            "duration_seconds": $duration_diff,
            "success_rate_percentage": $success_rate_diff
        }
    },
    "analysis": {
        "performance_change": "$(if (( $(echo "$success_rate_diff > 0" | bc -l 2>/dev/null || echo "0") )); then echo "improved"; elif (( $(echo "$success_rate_diff < 0" | bc -l 2>/dev/null || echo "0") )); then echo "degraded"; else echo "unchanged"; fi)",
        "test_coverage_change": "$(if [[ $total_tests_diff -gt 0 ]]; then echo "increased"; elif [[ $total_tests_diff -lt 0 ]]; then echo "decreased"; else echo "unchanged"; fi)",
        "execution_time_change": "$(if [[ $duration_diff -gt 0 ]]; then echo "slower"; elif [[ $duration_diff -lt 0 ]]; then echo "faster"; else echo "unchanged"; fi)"
    }
}
EOF

    # Compare individual test suites
    local suite_comparisons='[]'
    local run1_suites=$(jq -c '.test_suites[]' "$run1_file" 2>/dev/null)
    local run2_suites=$(jq -c '.test_suites[]' "$run2_file" 2>/dev/null)

    # Create suite comparison data
    while IFS= read -r suite1; do
        local suite_name=$(jq -r '.name' <<< "$suite1")
        local suite2=$(jq --arg name "$suite_name" '.test_suites[] | select(.name == $name)' "$run2_file" 2>/dev/null)

        if [[ -n "$suite2" ]]; then
            local suite_comparison=$(cat << EOF
{
    "suite_name": "$suite_name",
    "run1": $suite1,
    "run2": $suite2,
    "status_change": "$(jq -r '.status' <<< "$suite1") -> $(jq -r '.status' <<< "$suite2")",
    "test_count_change": $(( $(jq '.tests.total' <<< "$suite2") - $(jq '.tests.total' <<< "$suite1") )),
    "duration_change": $(( $(jq '.duration' <<< "$suite2") - $(jq '.duration' <<< "$suite1") ))
}
EOF
            )
            suite_comparisons=$(jq --argjson comparison "$suite_comparison" '. += [$comparison]' <<< "$suite_comparisons")
        fi
    done <<< "$run1_suites"

    # Add suite comparisons to output
    jq --argjson comparisons "$suite_comparisons" '.suite_comparisons = $comparisons' "$comparison_output" > "${comparison_output}.tmp" && mv "${comparison_output}.tmp" "$comparison_output"

    echo -e "${GREEN}✓ Comparison completed: ${WHITE}$(basename "$comparison_output")${NC}"
    echo "$comparison_output"
}

# Generate interactive dashboard
generate_interactive_dashboard() {
    local output_file="${1:-${REPORTS_DIR}/interactive_dashboard_$(date +%Y%m%d_%H%M%S).html}"

    echo -e "${CYAN}🎛️  Generating interactive dashboard...${NC}"

    # Find latest parsed results
    local latest_results=$(find "$RESULTS_DIR" -name "parsed_results_*.json" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)

    if [[ -z "$latest_results" || ! -f "$latest_results" ]]; then
        echo -e "${YELLOW}⚠️  No parsed results found for dashboard generation${NC}"
        return 1
    fi

    # Extract data for dashboard
    local summary_data=$(jq '.summary' "$latest_results" 2>/dev/null || echo '{}')
    local suite_data=$(jq '.test_suites' "$latest_results" 2>/dev/null || echo '[]')

    cat > "$output_file" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VLESS Test Dashboard</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f8f9fa; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 2rem; text-align: center; }
        .header h1 { font-size: 2.5rem; margin-bottom: 0.5rem; }
        .header p { font-size: 1.1rem; opacity: 0.9; }
        .container { max-width: 1400px; margin: 0 auto; padding: 2rem; }
        .metrics-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 1.5rem; margin-bottom: 2rem; }
        .metric-card { background: white; border-radius: 10px; padding: 1.5rem; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .metric-card h3 { color: #333; margin-bottom: 1rem; font-size: 1.1rem; }
        .metric-value { font-size: 2.5rem; font-weight: bold; margin-bottom: 0.5rem; }
        .metric-success { color: #28a745; }
        .metric-warning { color: #ffc107; }
        .metric-danger { color: #dc3545; }
        .metric-info { color: #17a2b8; }
        .chart-section { background: white; border-radius: 10px; padding: 2rem; margin-bottom: 2rem; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .chart-container { position: relative; height: 400px; }
        .suite-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 1.5rem; }
        .suite-card { background: white; border-radius: 10px; padding: 1.5rem; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .suite-header { display: flex; justify-content: between; align-items: center; margin-bottom: 1rem; }
        .suite-status { padding: 0.25rem 0.75rem; border-radius: 20px; font-size: 0.85rem; font-weight: bold; }
        .status-passed { background: #d4edda; color: #155724; }
        .status-failed { background: #f8d7da; color: #721c24; }
        .status-skipped { background: #fff3cd; color: #856404; }
        .progress-bar { background: #e9ecef; height: 8px; border-radius: 4px; overflow: hidden; margin: 0.5rem 0; }
        .progress-fill { height: 100%; background: linear-gradient(90deg, #28a745, #20c997); transition: width 0.3s ease; }
        .tabs { display: flex; border-bottom: 2px solid #dee2e6; margin-bottom: 1rem; }
        .tab { padding: 1rem 2rem; background: none; border: none; cursor: pointer; font-size: 1rem; }
        .tab.active { border-bottom: 3px solid #667eea; color: #667eea; font-weight: bold; }
        .tab-content { display: none; }
        .tab-content.active { display: block; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🧪 VLESS Test Dashboard</h1>
        <p>Real-time Test Results & Analytics</p>
        <p>Last Updated: $(date)</p>
    </div>

    <div class="container">
        <!-- Key Metrics -->
        <div class="metrics-grid">
            <div class="metric-card">
                <h3>Total Test Suites</h3>
                <div class="metric-value metric-info" id="total-suites">$(jq '.total_suites // 0' <<< "$summary_data")</div>
                <div>Across all test categories</div>
            </div>
            <div class="metric-card">
                <h3>Success Rate</h3>
                <div class="metric-value metric-success" id="success-rate">
                    $(echo "scale=1; $(jq '.passed_tests // 0' <<< "$summary_data") * 100 / $(jq '.total_tests // 1' <<< "$summary_data")" | bc -l 2>/dev/null || echo "0")%
                </div>
                <div>Overall test pass rate</div>
            </div>
            <div class="metric-card">
                <h3>Total Tests</h3>
                <div class="metric-value metric-info" id="total-tests">$(jq '.total_tests // 0' <<< "$summary_data")</div>
                <div>$(jq '.passed_tests // 0' <<< "$summary_data") passed, $(jq '.failed_tests // 0' <<< "$summary_data") failed</div>
            </div>
            <div class="metric-card">
                <h3>Execution Time</h3>
                <div class="metric-value metric-info" id="execution-time">$(jq '.total_duration // 0' <<< "$summary_data")s</div>
                <div>Total test execution duration</div>
            </div>
        </div>

        <!-- Tabs for different views -->
        <div class="tabs">
            <button class="tab active" onclick="showTab('overview')">Overview</button>
            <button class="tab" onclick="showTab('suites')">Test Suites</button>
            <button class="tab" onclick="showTab('trends')">Trends</button>
            <button class="tab" onclick="showTab('details')">Details</button>
        </div>

        <!-- Overview Tab -->
        <div id="overview" class="tab-content active">
            <div class="chart-section">
                <h2>Test Results Distribution</h2>
                <div class="chart-container">
                    <canvas id="resultsChart"></canvas>
                </div>
            </div>

            <div class="chart-section">
                <h2>Test Suite Performance</h2>
                <div class="chart-container">
                    <canvas id="performanceChart"></canvas>
                </div>
            </div>
        </div>

        <!-- Test Suites Tab -->
        <div id="suites" class="tab-content">
            <h2>Individual Test Suite Results</h2>
            <div class="suite-grid">
EOF

    # Add individual suite cards
    echo "$suite_data" | jq -c '.[]' | while read -r suite; do
        local suite_name=$(jq -r '.name' <<< "$suite")
        local suite_status=$(jq -r '.status' <<< "$suite")
        local suite_total=$(jq '.tests.total' <<< "$suite")
        local suite_passed=$(jq '.tests.passed' <<< "$suite")
        local suite_duration=$(jq '.duration' <<< "$suite")

        local success_rate=0
        if [[ $suite_total -gt 0 ]]; then
            success_rate=$(echo "scale=1; $suite_passed * 100 / $suite_total" | bc -l 2>/dev/null || echo "0")
        fi

        cat >> "$output_file" << EOF
                <div class="suite-card">
                    <div class="suite-header">
                        <h3>$suite_name</h3>
                        <span class="suite-status status-$suite_status">$(echo $suite_status | tr '[:lower:]' '[:upper:]')</span>
                    </div>
                    <div class="progress-bar">
                        <div class="progress-fill" style="width: ${success_rate}%"></div>
                    </div>
                    <div style="display: flex; justify-content: space-between; margin-top: 1rem;">
                        <span>Tests: $suite_passed/$suite_total</span>
                        <span>Duration: ${suite_duration}s</span>
                    </div>
                </div>
EOF
    done

    cat >> "$output_file" << 'EOF'
            </div>
        </div>

        <!-- Trends Tab -->
        <div id="trends" class="tab-content">
            <div class="chart-section">
                <h2>Success Rate Trends</h2>
                <div class="chart-container">
                    <canvas id="trendsChart"></canvas>
                </div>
            </div>
        </div>

        <!-- Details Tab -->
        <div id="details" class="tab-content">
            <div class="chart-section">
                <h2>Detailed Test Information</h2>
                <table style="width: 100%; border-collapse: collapse;">
                    <thead>
                        <tr style="background: #f8f9fa;">
                            <th style="padding: 1rem; text-align: left;">Test Suite</th>
                            <th style="padding: 1rem; text-align: left;">Status</th>
                            <th style="padding: 1rem; text-align: left;">Tests</th>
                            <th style="padding: 1rem; text-align: left;">Success Rate</th>
                            <th style="padding: 1rem; text-align: left;">Duration</th>
                        </tr>
                    </thead>
                    <tbody>
EOF

    # Add detailed table rows
    echo "$suite_data" | jq -c '.[]' | while read -r suite; do
        local suite_name=$(jq -r '.name' <<< "$suite")
        local suite_status=$(jq -r '.status' <<< "$suite")
        local suite_total=$(jq '.tests.total' <<< "$suite")
        local suite_passed=$(jq '.tests.passed' <<< "$suite")
        local suite_duration=$(jq '.duration' <<< "$suite")

        local success_rate=0
        if [[ $suite_total -gt 0 ]]; then
            success_rate=$(echo "scale=1; $suite_passed * 100 / $suite_total" | bc -l 2>/dev/null || echo "0")
        fi

        cat >> "$output_file" << EOF
                        <tr>
                            <td style="padding: 1rem;">$suite_name</td>
                            <td style="padding: 1rem;"><span class="status-$suite_status">$(echo $suite_status | tr '[:lower:]' '[:upper:]')</span></td>
                            <td style="padding: 1rem;">$suite_passed/$suite_total</td>
                            <td style="padding: 1rem;">${success_rate}%</td>
                            <td style="padding: 1rem;">${suite_duration}s</td>
                        </tr>
EOF
    done

    cat >> "$output_file" << 'EOF'
                    </tbody>
                </table>
            </div>
        </div>
    </div>

    <script>
        // Tab switching functionality
        function showTab(tabName) {
            // Hide all tab contents
            document.querySelectorAll('.tab-content').forEach(content => {
                content.classList.remove('active');
            });

            // Remove active class from all tabs
            document.querySelectorAll('.tab').forEach(tab => {
                tab.classList.remove('active');
            });

            // Show selected tab content
            document.getElementById(tabName).classList.add('active');

            // Add active class to clicked tab
            event.target.classList.add('active');
        }

        // Chart.js configurations
        const ctx1 = document.getElementById('resultsChart').getContext('2d');
        const resultsChart = new Chart(ctx1, {
            type: 'doughnut',
            data: {
                labels: ['Passed', 'Failed', 'Skipped'],
                datasets: [{
                    data: [
EOF

    echo "                        $(jq '.passed_tests // 0' <<< "$summary_data")," >> "$output_file"
    echo "                        $(jq '.failed_tests // 0' <<< "$summary_data")," >> "$output_file"
    echo "                        $(jq '.skipped_tests // 0' <<< "$summary_data")" >> "$output_file"

    cat >> "$output_file" << 'EOF'
                    ],
                    backgroundColor: ['#28a745', '#dc3545', '#ffc107']
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        position: 'bottom'
                    }
                }
            }
        });

        // Performance chart (suite durations)
        const ctx2 = document.getElementById('performanceChart').getContext('2d');
        const performanceChart = new Chart(ctx2, {
            type: 'bar',
            data: {
                labels: [
EOF

    # Add suite names and durations
    echo "$suite_data" | jq -r '.[].name' | while read -r name; do
        echo "                    '$name'," >> "$output_file"
    done

    cat >> "$output_file" << 'EOF'
                ],
                datasets: [{
                    label: 'Duration (seconds)',
                    data: [
EOF

    echo "$suite_data" | jq -r '.[].duration' | while read -r duration; do
        echo "                        $duration," >> "$output_file"
    done

    cat >> "$output_file" << 'EOF'
                    ],
                    backgroundColor: '#667eea'
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: {
                        beginAtZero: true
                    }
                }
            }
        });

        // Trends chart (mock data for demonstration)
        const ctx3 = document.getElementById('trendsChart').getContext('2d');
        const trendsChart = new Chart(ctx3, {
            type: 'line',
            data: {
                labels: ['Day 1', 'Day 2', 'Day 3', 'Day 4', 'Day 5', 'Day 6', 'Day 7'],
                datasets: [{
                    label: 'Success Rate (%)',
                    data: [85, 90, 88, 92, 94, 91, 95],
                    borderColor: '#667eea',
                    backgroundColor: 'rgba(102, 126, 234, 0.1)',
                    fill: true
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: {
                        beginAtZero: true,
                        max: 100
                    }
                }
            }
        });
    </script>
</body>
</html>
EOF

    echo -e "${GREEN}✓ Interactive dashboard generated: ${WHITE}$(basename "$output_file")${NC}"
    echo "$output_file"
}

# Export results in various formats
export_results() {
    local format="${1:-json}"
    local output_file="${2:-${REPORTS_DIR}/export_$(date +%Y%m%d_%H%M%S).$format}"
    local input_file="${3:-}"

    echo -e "${CYAN}📤 Exporting results in $format format...${NC}"

    # Find latest results if no input file specified
    if [[ -z "$input_file" ]]; then
        input_file=$(find "$RESULTS_DIR" -name "parsed_results_*.json" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
    fi

    if [[ -z "$input_file" || ! -f "$input_file" ]]; then
        echo -e "${RED}❌ No input file found for export${NC}"
        return 1
    fi

    case "$format" in
        "csv")
            export_to_csv "$input_file" "$output_file"
            ;;
        "xml")
            export_to_xml "$input_file" "$output_file"
            ;;
        "markdown"|"md")
            export_to_markdown "$input_file" "$output_file"
            ;;
        "json")
            cp "$input_file" "$output_file"
            ;;
        *)
            echo -e "${RED}❌ Unsupported export format: $format${NC}"
            return 1
            ;;
    esac

    echo -e "${GREEN}✓ Export completed: ${WHITE}$(basename "$output_file")${NC}"
    echo "$output_file"
}

# Export to CSV format
export_to_csv() {
    local input_file="$1"
    local output_file="$2"

    cat > "$output_file" << 'EOF'
Suite Name,Status,Total Tests,Passed Tests,Failed Tests,Skipped Tests,Duration (s),Success Rate (%)
EOF

    jq -r '.test_suites[] |
        [.name, .status, .tests.total, .tests.passed, .tests.failed, .tests.skipped, .duration,
         (if .tests.total > 0 then (.tests.passed * 100 / .tests.total | floor) else 0 end)] |
        @csv' "$input_file" >> "$output_file"
}

# Export to XML format
export_to_xml() {
    local input_file="$1"
    local output_file="$2"

    cat > "$output_file" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<test_results>
EOF

    # Add metadata
    local timestamp=$(jq -r '.metadata.timestamp // "unknown"' "$input_file")
    cat >> "$output_file" << EOF
    <metadata>
        <timestamp>$timestamp</timestamp>
        <version>$(jq -r '.metadata.version // "unknown"' "$input_file")</version>
    </metadata>
    <summary>
        <total_suites>$(jq '.summary.total_suites // 0' "$input_file")</total_suites>
        <passed_suites>$(jq '.summary.passed_suites // 0' "$input_file")</passed_suites>
        <failed_suites>$(jq '.summary.failed_suites // 0' "$input_file")</failed_suites>
        <total_tests>$(jq '.summary.total_tests // 0' "$input_file")</total_tests>
        <passed_tests>$(jq '.summary.passed_tests // 0' "$input_file")</passed_tests>
        <failed_tests>$(jq '.summary.failed_tests // 0' "$input_file")</failed_tests>
        <total_duration>$(jq '.summary.total_duration // 0' "$input_file")</total_duration>
    </summary>
    <test_suites>
EOF

    # Add test suites
    jq -c '.test_suites[]' "$input_file" | while read -r suite; do
        local name=$(jq -r '.name' <<< "$suite")
        local status=$(jq -r '.status' <<< "$suite")
        local total=$(jq '.tests.total' <<< "$suite")
        local passed=$(jq '.tests.passed' <<< "$suite")
        local failed=$(jq '.tests.failed' <<< "$suite")
        local skipped=$(jq '.tests.skipped' <<< "$suite")
        local duration=$(jq '.duration' <<< "$suite")

        cat >> "$output_file" << EOF
        <test_suite name="$name" status="$status">
            <tests total="$total" passed="$passed" failed="$failed" skipped="$skipped"/>
            <duration>$duration</duration>
        </test_suite>
EOF
    done

    cat >> "$output_file" << 'EOF'
    </test_suites>
</test_results>
EOF
}

# Export to Markdown format
export_to_markdown() {
    local input_file="$1"
    local output_file="$2"

    local timestamp=$(jq -r '.metadata.timestamp // "unknown"' "$input_file")

    cat > "$output_file" << EOF
# VLESS Test Results Report

**Generated:** $timestamp
**Version:** $(jq -r '.metadata.version // "unknown"' "$input_file")

## Summary

| Metric | Value |
|--------|-------|
| Total Test Suites | $(jq '.summary.total_suites // 0' "$input_file") |
| Passed Suites | $(jq '.summary.passed_suites // 0' "$input_file") |
| Failed Suites | $(jq '.summary.failed_suites // 0' "$input_file") |
| Total Tests | $(jq '.summary.total_tests // 0' "$input_file") |
| Passed Tests | $(jq '.summary.passed_tests // 0' "$input_file") |
| Failed Tests | $(jq '.summary.failed_tests // 0' "$input_file") |
| Skipped Tests | $(jq '.summary.skipped_tests // 0' "$input_file") |
| Total Duration | $(jq '.summary.total_duration // 0' "$input_file")s |

## Test Suite Details

| Suite Name | Status | Tests | Success Rate | Duration |
|------------|--------|-------|--------------|----------|
EOF

    jq -r '.test_suites[] |
        "| \(.name) | \(.status) | \(.tests.passed)/\(.tests.total) | \(if .tests.total > 0 then (.tests.passed * 100 / .tests.total | floor) else 0 end)% | \(.duration)s |"' \
        "$input_file" >> "$output_file"

    cat >> "$output_file" << 'EOF'

## Notes

- This report was generated automatically by the VLESS Test Results Aggregator
- For detailed logs, check the individual test suite log files
- Failed tests should be investigated and resolved before deployment

EOF
}

# Archive old test results
archive_old_results() {
    local days="${1:-$MAX_HISTORY_DAYS}"

    echo -e "${CYAN}🗄️  Archiving test results older than $days days...${NC}"

    # Create dated archive directory
    local archive_subdir="${ARCHIVE_DIR}/$(date +%Y%m%d)"
    mkdir -p "$archive_subdir"

    # Find and archive old files
    local archived_count=0
    while IFS= read -r -d '' file; do
        if [[ -f "$file" ]]; then
            local filename=$(basename "$file")
            mv "$file" "$archive_subdir/"
            echo -e "${BLUE}  Archived: ${WHITE}$filename${NC}"
            ((archived_count++))
        fi
    done < <(find "$RESULTS_DIR" -name "*.log" -o -name "*.json" -type f -mtime +"$days" -print0 2>/dev/null)

    if [[ $archived_count -eq 0 ]]; then
        echo -e "${BLUE}ℹ No files found to archive${NC}"
    else
        echo -e "${GREEN}✓ Archived $archived_count files to: ${WHITE}$archive_subdir${NC}"
    fi

    # Compress old archives
    find "$ARCHIVE_DIR" -name "*.json" -o -name "*.log" -type f -mtime +7 -exec gzip {} \; 2>/dev/null || true

    echo ""
}

# Cleanup old files
cleanup_old_files() {
    local days="${1:-$MAX_HISTORY_DAYS}"

    echo -e "${CYAN}🧹 Cleaning up files older than $days days...${NC}"

    # Remove very old archives
    local removed_count=0
    while IFS= read -r -d '' file; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            ((removed_count++))
        fi
    done < <(find "$ARCHIVE_DIR" -type f -mtime +"$((days * 2))" -print0 2>/dev/null)

    # Remove empty archive directories
    find "$ARCHIVE_DIR" -type d -empty -delete 2>/dev/null || true

    if [[ $removed_count -eq 0 ]]; then
        echo -e "${BLUE}ℹ No old files found to remove${NC}"
    else
        echo -e "${GREEN}✓ Removed $removed_count old files${NC}"
    fi

    echo ""
}

# Main execution function
main() {
    local command="aggregate"
    local format="json"
    local days="$TREND_ANALYSIS_DAYS"
    local output_file=""
    local files_to_process=()

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE_OUTPUT=true
                shift
                ;;
            -f|--format)
                format="$2"
                shift 2
                ;;
            -d|--days)
                days="$2"
                shift 2
                ;;
            -o|--output)
                output_file="$2"
                shift 2
                ;;
            aggregate|trends|compare|archive|dashboard|metrics|export|cleanup)
                command="$1"
                shift
                ;;
            *)
                # Assume it's a file to process
                files_to_process+=("$1")
                shift
                ;;
        esac
    done

    # Initialize aggregator
    initialize_aggregator

    # Execute command
    case "$command" in
        "aggregate")
            # Find all log files if none specified
            if [[ ${#files_to_process[@]} -eq 0 ]]; then
                while IFS= read -r -d '' file; do
                    files_to_process+=("$file")
                done < <(find "$RESULTS_DIR" -name "*.log" -type f -mtime -1 -print0 2>/dev/null)
            fi

            if [[ ${#files_to_process[@]} -eq 0 ]]; then
                echo -e "${YELLOW}⚠️  No recent log files found to aggregate${NC}"
                exit 1
            fi

            parse_test_results "${files_to_process[@]}"
            ;;

        "trends")
            analyze_test_trends "$days" "$output_file"
            ;;

        "compare")
            if [[ ${#files_to_process[@]} -lt 2 ]]; then
                echo -e "${RED}❌ Two result files required for comparison${NC}"
                exit 1
            fi
            compare_test_runs "${files_to_process[0]}" "${files_to_process[1]}" "$output_file"
            ;;

        "dashboard")
            generate_interactive_dashboard "$output_file"
            ;;

        "export")
            export_results "$format" "$output_file" "${files_to_process[0]:-}"
            ;;

        "archive")
            archive_old_results "$days"
            ;;

        "cleanup")
            cleanup_old_files "$days"
            ;;

        *)
            echo -e "${RED}❌ Unknown command: $command${NC}"
            show_usage
            exit 1
            ;;
    esac
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi