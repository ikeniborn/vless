#!/bin/bash

# Color definitions for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Output functions
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_step() {
    echo -e "${CYAN}→${NC} $1"
}

print_header() {
    echo -e "\n${MAGENTA}========================================${NC}"
    echo -e "${MAGENTA}    $1${NC}"
    echo -e "${MAGENTA}========================================${NC}\n"
}

# Print critical warning with prominent box and red color
print_critical_warning() {
    local message="$1"
    local BOLD_RED='\033[1;31m'

    # Calculate box width based on longest line
    local max_length=0
    while IFS= read -r line; do
        local line_length=${#line}
        if [ $line_length -gt $max_length ]; then
            max_length=$line_length
        fi
    done <<< "$message"

    # Add padding
    local box_width=$((max_length + 4))
    local border=$(printf '═%.0s' $(seq 1 $box_width))

    echo ""
    echo -e "${BOLD_RED}╔${border}╗${NC}"

    # Print each line centered
    while IFS= read -r line; do
        local padding=$((max_length - ${#line}))
        local left_pad=$((padding / 2))
        local right_pad=$((padding - left_pad))
        printf "${BOLD_RED}║  %s%*s  ║${NC}\n" "$line" $((${#line} + right_pad)) "$(printf ' %.0s' $(seq 1 $right_pad))" | sed "s/  $(printf ' %.0s' $(seq 1 $right_pad))  /$(printf ' %.0s' $(seq 1 $left_pad))$line$(printf ' %.0s' $(seq 1 $right_pad))  /"
    done <<< "$message"

    echo -e "${BOLD_RED}╚${border}╝${NC}"
    echo ""
}