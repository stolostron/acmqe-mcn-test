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
    cat <<EOF

    Deploy and test Submariner Addon on ACM hub
    The script supports the following platforms - AWS, GCP

    Requirements:
    - ACM hub ready
    - At least two managed clusters

    Export the following values to execute the flow:
    export OC_CLUSTER_URL=<hub cluster url>
    export OC_CLUSTER_USER=<cluster user name>
    export OC_CLUSTER_PASS=<password of the cluster user>

    Arguments:
    --all      - Perform deployment and testing of the Submariner addon

    --deploy   - Perform deployment of the Submariner addon

    --test     - Perform testing of the Submariner addon

    --platform - Specify the platforms that should be used for testing
                 Separate multiple platforms by comma
                 (Optional)
                 By default - aws,gcp

    --help|-h  - Print help
EOF
}
