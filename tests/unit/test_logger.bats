#!/usr/bin/env bats
# tests/unit/test_logger.bats - Unit tests for logger module

load ../test_helper

setup() {
    setup_test_env
    source "${LIB_DIR}/logger.sh"
}

teardown() {
    teardown_test_env
}

@test "log_info outputs INFO message" {
    run log_info "Test message"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "INFO" ]]
    [[ "$output" =~ "Test message" ]]
}

@test "log_error outputs ERROR message" {
    run log_error "Error message"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ERROR" ]]
    [[ "$output" =~ "Error message" ]]
}

@test "log_warn outputs WARN message" {
    run log_warn "Warning message"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "WARN" ]]
    [[ "$output" =~ "Warning message" ]]
}

@test "log_success outputs SUCCESS message" {
    run log_success "Success message"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "SUCCESS" ]]
    [[ "$output" =~ "Success message" ]]
}

@test "log_debug outputs DEBUG message when enabled" {
    export DEBUG=true
    run log_debug "Debug message"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "DEBUG" ]]
    [[ "$output" =~ "Debug message" ]]
}

@test "log_debug is silent when DEBUG not enabled" {
    unset DEBUG
    run log_debug "Debug message"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "logger includes timestamp" {
    run log_info "Test"
    [ "$status" -eq 0 ]
    # Check for timestamp format YYYY-MM-DD HH:MM:SS
    [[ "$output" =~ [0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2} ]]
}

@test "logger handles empty messages" {
    run log_info ""
    [ "$status" -eq 0 ]
}

@test "logger handles special characters" {
    run log_info "Test with $pecial ch@racters & symbols!"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Test with" ]]
}

@test "logger handles multiline messages" {
    run log_info "Line 1
Line 2
Line 3"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Line 1" ]]
}
