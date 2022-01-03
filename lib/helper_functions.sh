#!/bin/bash

# Helper functions for the script

# Constants #
export GREEN='\x1b[38;5;22m'
export CYAN='\033[0;36m'
export YELLOW='\x1b[33m'
export RED='\x1b[0;31m'
export NO_COLOR='\x1b[0m'

# Print the message with a prefix INFO with CYAN color
function INFO() {
    local message="$1"
    echo -e "${CYAN}INFO: ${NO_COLOR}${message}"
}

# Print the message with a prefix WARNING with YELLOW color
function WARNING() {
    local message="$1"
    echo -e "${YELLOW}WARNING: ${NO_COLOR}${message}"
}

# Print the message with a prefix ERROR with RED color and fail the execution
function ERROR() {
    local message="$1"
    echo -e "${RED}ERROR: ${NO_COLOR}${message}"
    exit 1
}

function usage() {
    echo
    echo "Deploy Submariner Addon on ACM hub"
    echo "Requirements:"
    echo "- ACM hub ready"
    echo "- At least two managed clusters"
    echo
    echo "Arguments:"
    echo "--all      - Perform deployment and testing of the Submariner addon"
    echo "--deploy   - Perform deployment of the Submariner addon"
    echo "--test     - Perform testing of the Submariner addon"
    echo "--help     - Print help"
    echo
}
