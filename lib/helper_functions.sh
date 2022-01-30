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

# Prepare kubeconfig of the managed clusters by fetching them from the hub
function fetch_kubeconfig_contexts() {
    INFO "Fetch kubeconfig for managed clusters"
    local kubeconfig_name

    rm -rf "$TESTS_LOGS"
    mkdir -p "$TESTS_LOGS"

    for cluster in $MANAGED_CLUSTERS; do
        kubeconfig_name=$(oc get -n "$cluster" secrets --no-headers \
                            -o custom-columns=NAME:.metadata.name | grep kubeconfig)
        oc get secrets "$kubeconfig_name" -n "$cluster" \
            --template='{{.data.kubeconfig}}' | base64 -d > "$TESTS_LOGS/$cluster-kubeconfig.yaml"

        CL="$cluster" yq eval -i '.contexts[].context.user = env(CL)
            | .contexts[].name = env(CL)
            | .current-context = env(CL)
            | .users[].name = env(CL)' "$TESTS_LOGS/$cluster-kubeconfig.yaml"
    done
}
