#!/usr/bin/env bats
# tests/unit/test_validation.bats - Unit tests for validation module

load ../test_helper

setup() {
    setup_test_env
    source "${LIB_DIR}/logger.sh"
    source "${LIB_DIR}/validation.sh"
}

teardown() {
    teardown_test_env
}

# Username validation tests
@test "validate_username accepts valid alphanumeric username" {
    run validate_username "user123"
    [ "$status" -eq 0 ]
}

@test "validate_username accepts username with underscore" {
    run validate_username "user_name"
    [ "$status" -eq 0 ]
}

@test "validate_username accepts username with dash" {
    run validate_username "user-name"
    [ "$status" -eq 0 ]
}

@test "validate_username rejects empty username" {
    run validate_username ""
    [ "$status" -eq 1 ]
}

@test "validate_username rejects username with spaces" {
    run validate_username "user name"
    [ "$status" -eq 1 ]
}

@test "validate_username rejects username with special characters" {
    run validate_username "user@name"
    [ "$status" -eq 1 ]
}

@test "validate_username rejects very long username" {
    local long_name=$(printf 'a%.0s' {1..100})
    run validate_username "$long_name"
    [ "$status" -eq 1 ]
}

# Port validation tests
@test "validate_port accepts valid port 443" {
    run validate_port "443"
    [ "$status" -eq 0 ]
}

@test "validate_port accepts valid port 8443" {
    run validate_port "8443"
    [ "$status" -eq 0 ]
}

@test "validate_port accepts port 1024" {
    run validate_port "1024"
    [ "$status" -eq 0 ]
}

@test "validate_port accepts port 65535" {
    run validate_port "65535"
    [ "$status" -eq 0 ]
}

@test "validate_port rejects port 0" {
    run validate_port "0"
    [ "$status" -eq 1 ]
}

@test "validate_port rejects port 65536" {
    run validate_port "65536"
    [ "$status" -eq 1 ]
}

@test "validate_port rejects negative port" {
    run validate_port "-1"
    [ "$status" -eq 1 ]
}

@test "validate_port rejects non-numeric port" {
    run validate_port "abc"
    [ "$status" -eq 1 ]
}

@test "validate_port rejects empty port" {
    run validate_port ""
    [ "$status" -eq 1 ]
}

# IP address validation tests
@test "validate_ip accepts valid IP 192.168.1.1" {
    run validate_ip "192.168.1.1"
    [ "$status" -eq 0 ]
}

@test "validate_ip accepts valid IP 10.0.0.1" {
    run validate_ip "10.0.0.1"
    [ "$status" -eq 0 ]
}

@test "validate_ip accepts valid IP 172.16.0.1" {
    run validate_ip "172.16.0.1"
    [ "$status" -eq 0 ]
}

@test "validate_ip rejects invalid IP 256.1.1.1" {
    run validate_ip "256.1.1.1"
    [ "$status" -eq 1 ]
}

@test "validate_ip rejects invalid IP 192.168.1" {
    run validate_ip "192.168.1"
    [ "$status" -eq 1 ]
}

@test "validate_ip rejects invalid IP with text" {
    run validate_ip "192.168.1.abc"
    [ "$status" -eq 1 ]
}

@test "validate_ip rejects empty IP" {
    run validate_ip ""
    [ "$status" -eq 1 ]
}

# Subnet validation tests
@test "validate_subnet accepts valid subnet 172.20.0.0/16" {
    run validate_subnet "172.20.0.0/16"
    [ "$status" -eq 0 ]
}

@test "validate_subnet accepts valid subnet 10.0.0.0/8" {
    run validate_subnet "10.0.0.0/8"
    [ "$status" -eq 0 ]
}

@test "validate_subnet accepts valid subnet 192.168.0.0/24" {
    run validate_subnet "192.168.0.0/24"
    [ "$status" -eq 0 ]
}

@test "validate_subnet rejects subnet without CIDR" {
    run validate_subnet "172.20.0.0"
    [ "$status" -eq 1 ]
}

@test "validate_subnet rejects subnet with invalid CIDR" {
    run validate_subnet "172.20.0.0/33"
    [ "$status" -eq 1 ]
}

@test "validate_subnet rejects empty subnet" {
    run validate_subnet ""
    [ "$status" -eq 1 ]
}

# UUID validation tests
@test "validate_uuid accepts valid UUID v4" {
    run validate_uuid "550e8400-e29b-41d4-a716-446655440000"
    [ "$status" -eq 0 ]
}

@test "validate_uuid rejects invalid UUID format" {
    run validate_uuid "invalid-uuid"
    [ "$status" -eq 1 ]
}

@test "validate_uuid rejects empty UUID" {
    run validate_uuid ""
    [ "$status" -eq 1 ]
}

# Domain validation tests
@test "validate_domain accepts valid domain google.com" {
    run validate_domain "google.com"
    [ "$status" -eq 0 ]
}

@test "validate_domain accepts subdomain www.google.com" {
    run validate_domain "www.google.com"
    [ "$status" -eq 0 ]
}

@test "validate_domain accepts long domain" {
    run validate_domain "subdomain.example.domain.com"
    [ "$status" -eq 0 ]
}

@test "validate_domain rejects domain with spaces" {
    run validate_domain "google .com"
    [ "$status" -eq 1 ]
}

@test "validate_domain rejects domain with special chars" {
    run validate_domain "google@.com"
    [ "$status" -eq 1 ]
}

@test "validate_domain rejects empty domain" {
    run validate_domain ""
    [ "$status" -eq 1 ]
}

# Path validation tests
@test "validate_path accepts valid absolute path" {
    run validate_path "/opt/vless"
    [ "$status" -eq 0 ]
}

@test "validate_path rejects relative path" {
    run validate_path "relative/path"
    [ "$status" -eq 1 ]
}

@test "validate_path rejects empty path" {
    run validate_path ""
    [ "$status" -eq 1 ]
}
