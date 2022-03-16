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
    echo -e "\n${YELLOW}WARNING: ${NO_COLOR}${message}\n"
}

# Print the message with a prefix ERROR with RED color and fail the execution
function ERROR() {
    local message="$1"
    echo -e "\n${RED}ERROR: ${NO_COLOR}${message}"
    FAILURES+="${RED}ERROR: ${NO_COLOR}${message}"
    exit 1
}

# Print the message with a prefix LOG with CYAN color
# The output will be redirected to the log file as well.
function LOG() {
    local message="$1"
    local log_file=""

    if [[ -n "$LOG_PATH" ]]; then
        log_file="$LOG_PATH"
    fi

    echo -e "\n${CYAN}LOG: ${NO_COLOR}${message}"
    {
    echo -e "\n===================="
    echo -e "LOG: ${message}"
    echo -e "===================="
    }  >> "${log_file}"
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
    --all         - Perform deployment and testing of the Submariner addon

    --deploy      - Perform deployment of the Submariner addon

    --test        - Perform testing of the Submariner addon

    --platform    - Specify the platforms that should be used for testing
                    Separate multiple platforms by comma
                    (Optional)
                    By default - aws,gcp

    --version     - Specify Submariner version to be deployed
                    (Optional)
                    If not specified, submariner version will be chosen
                    based of the ACM hub support

    --globalnet   - Set the state of the Globalnet for the Submariner deployment.
                    The globalnet configuration will be applied starting from
                    ACM version 2.5.0 and Submariner 0.12.0
                    (Optional)
                    By default - false

    --downstream  - Use the flag if downsteram images should be used.
                    Submariner images could be sourced from two places:
                      * Official Red Hat ragistry - registry.redhat.io
                      * Downstream Quay registry - brew.registry.redhat.io
                    (Optional)
                    If flag is not used, official registry will be used

    --mirror      - Use local ocp registry.
                    Due to https://issues.redhat.com/browse/RFE-1608,
                    local ocp registry is required.
                    The images are imported and used from the local registry.
                    (Optional) (true/false)
                    By default - true
                    The flag is used only with "--downstream" flag.
                    Otherwise, ignored.

    --gather-logs - Specify if logs gathering should be performed.
                    The gathering will be done on all submariner configs.
                    (Optional)
                    By default - true

    --help|-h     - Print help
EOF
}

# Login to a cluster with the fiven details
function login_to_cluster() {
    local cluster="$1"

    if [[ "$cluster" == "hub" ]]; then
        oc login --insecure-skip-tls-verify \
            -u "$OC_CLUSTER_USER" -p "$OC_CLUSTER_PASS" "$OC_CLUSTER_URL"
        oc cluster-info | grep Kubernetes
    else
        if [[ ! -f "$LOGS/$cluster-password" || ! -f "$LOGS/$cluster-kubeconfig.yaml" ]]; then
            ERROR "Unable login to a $cluster cluster. Missing config files."
        fi

        cluster_pass="$LOGS/$cluster-password"
        cluster_url=$(yq eval '.clusters[].cluster.server' \
                        "$LOGS/$cluster-kubeconfig.yaml")
        oc login --insecure-skip-tls-verify -u "kubeadmin" \
            -p "$(< "$cluster_pass")" "$cluster_url" &> /dev/null
    fi
}

# The function will return token of the given cluster name
# The token information will be received based on the
# available kubeconfig file within the "$LOGS" dir.
function get_cluster_token() {
    local cluster="$1"
    local token="$2"

    login_to_cluster "$cluster"
    token=$(oc whoami -t)
    echo "$token"

    login_to_cluster "hub" &> /dev/null
}

# Prepare kubeconfig and password of the managed clusters by fetching them from the hub
function fetch_kubeconfig_contexts_and_pass() {
    INFO "Fetch kubeconfig and password for managed clusters"
    local kubeconfig_name
    local pass_name

    rm -rf "$LOGS"
    mkdir -p "$LOGS"

    for cluster in $MANAGED_CLUSTERS; do
        kubeconfig_name=$(oc get -n "$cluster" secrets --no-headers \
                            -o custom-columns=NAME:.metadata.name | grep kubeconfig)
        oc get secrets "$kubeconfig_name" -n "$cluster" \
            --template='{{index .data.kubeconfig | base64decode}}' > "$LOGS/$cluster-kubeconfig.yaml"

        CL="$cluster" yq eval -i '.contexts[].context.user = env(CL)
            | .contexts[].name = env(CL)
            | .current-context = env(CL)
            | .users[].name = env(CL)' "$LOGS/$cluster-kubeconfig.yaml"

        pass_name=$(oc get -n "$cluster" secrets --no-headers \
                      -o custom-columns=NAME:.metadata.name | grep password)
        oc get secrets "$pass_name" -n "$cluster" \
            --template='{{index .data.password | base64decode}}' > "$LOGS/$cluster-password"
    done
}

function validate_given_submariner_version() {
    INFO "Validate given Submariner version with supported versions"
    if [[ ! "${SUPPORTED_SUBMARINER_VERSIONS[*]}" =~ $SUBMARINER_VERSION_INSTALL ]]; then
        ERROR "Suplied Submariner version is not supported. Supported versions - ${SUPPORTED_SUBMARINER_VERSIONS[*]}"
    fi
    INFO "Submariner version provided manually - $SUBMARINER_VERSION_INSTALL"
}

# Function to convert raw text (e.g. yaml) to encoded url format
function raw_to_url_encode() {
    local string
    string="$(cat < /dev/stdin)"
    local strlen=${#string}
    local encoded=""
    local pos c o

    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="${c}" ;;
            * )               printf -v o '%%%02x' "'$c"
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

# Validate versions
# The function will get two versions:
# First - Base varsion
# Second - Current version
# The function will return the state of the current
# version comparing to the base:
# If current version equal or highter than base - "valid"
# If current version lower than base - "not_valid"
function validate_version() {
    local base_version="$1"
    local current_version="$2"
    local version_state="not_valid"

    if test "$(echo "$base_version $current_version" | tr " " "\n" | sort -rV | head -n 1)" == "$current_version"; then
        version_state="valid"
    fi
    if test "$(echo "$base_version $current_version" | tr " " "\n" | sort -rV | head -n 1)" != "$current_version"; then
        version_state="not_valid"
    fi
    echo "$version_state"
}

function catch_error() {
    if [[ "$1" != "0" ]]; then
        if [[ "$GATHER_LOGS" == "true" ]]; then
            gather_debug_info
            if [[ -n "$FAILURES" ]]; then
                echo -e "\nExecution aborted. The following failures detected:\n$FAILURES"
            fi
        fi
    fi
}
