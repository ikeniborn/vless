#!/usr/bin/env bats
# tests/unit/test_os_detection.bats - Unit tests for OS detection module

load ../test_helper

setup() {
    setup_test_env
    source "${LIB_DIR}/logger.sh"
    source "${LIB_DIR}/os_detection.sh"
}

teardown() {
    teardown_test_env
}

@test "detect_os succeeds when os-release exists" {
    skip_if_not_root

    run detect_os
    [ "$status" -eq 0 ]
}

@test "detect_os identifies operating system" {
    skip_if_not_root

    run detect_os
    [ "$status" -eq 0 ]
    # Should output OS name
    [[ "$output" =~ (Ubuntu|Debian|CentOS|Fedora) ]]
}

@test "is_supported_os returns true for Ubuntu" {
    # Mock OS detection
    export OS_NAME="Ubuntu"
    export OS_VERSION="22.04"

    run is_supported_os
    [ "$status" -eq 0 ]
}

@test "is_supported_os returns true for Debian" {
    export OS_NAME="Debian"
    export OS_VERSION="11"

    run is_supported_os
    [ "$status" -eq 0 ]
}

@test "is_supported_os returns false for unsupported OS" {
    export OS_NAME="Windows"
    export OS_VERSION="10"

    run is_supported_os
    [ "$status" -eq 1 ]
}

@test "get_package_manager returns apt for Ubuntu" {
    export OS_NAME="Ubuntu"

    run get_package_manager
    [ "$status" -eq 0 ]
    [[ "$output" == "apt" ]]
}

@test "get_package_manager returns apt for Debian" {
    export OS_NAME="Debian"

    run get_package_manager
    [ "$status" -eq 0 ]
    [[ "$output" == "apt" ]]
}

@test "check_system_requirements validates kernel version" {
    skip_if_not_root

    run check_system_requirements
    # Should succeed on modern systems
    [ "$status" -eq 0 ]
}

@test "detect_architecture identifies x86_64" {
    if [[ "$(uname -m)" != "x86_64" ]]; then
        skip "Not running on x86_64"
    fi

    run detect_architecture
    [ "$status" -eq 0 ]
    [[ "$output" == "x86_64" ]]
}

@test "detect_architecture identifies aarch64" {
    if [[ "$(uname -m)" != "aarch64" ]]; then
        skip "Not running on aarch64"
    fi

    run detect_architecture
    [ "$status" -eq 0 ]
    [[ "$output" == "aarch64" ]]
}
