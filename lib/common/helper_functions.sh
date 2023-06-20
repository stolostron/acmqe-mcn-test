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
    echo -e "${CYAN}LOG: ${NO_COLOR}${message}"
}

function usage() {
    cat <<EOF

    Deploy and test Submariner Addon on ACM hub
    The script supports the following platforms - AWS, GCP

    Requirements:
    - ACM hub ready
    - At least two managed clusters created by the hub
    Note! - The managed clusters needs to be created by the
            hub because credentials of the cloud are required
            to set submariner configurations.

    Export the following values to execute the flow:
    export OC_CLUSTER_API=<hub cluster url>
    export OC_CLUSTER_USER=<cluster user name>
    export OC_CLUSTER_PASS=<password of the cluster user>

    Arguments:
    Main arguments:
    -----------------
    --all                  - Perform deployment and testing of the Submariner addon

    --deploy               - Perform deployment of the Submariner addon

    --test                 - Perform testing of the Submariner addon

    --report               - Report tests results to Polarion

    --gather-logs          - Gather debug info and logs for environment

    --validate-prereq      - Perform prerequisites validation of the environment
                             before deployment.
                             The validation will consist of the following checks:
                             - Verify ACM hub credentials
                             - Verify at least two clusters available from provided platforms
                             This is used by the ci flow to not fail the job if provided
                             environment is not ready.
                             The state will be written to validation_state.log file
                             and will not fail the flow.

    Submariner deployment arguments:
    --------------------------------
    --platform             - Specify the platforms that should be used for testing
                             Separate multiple platforms by comma
                             (Optional)
                             By default - aws,gcp

    --downstream           - Use the flag if downstream images should be used.
                             Submariner images could be sourced from two places:
                               * Official Red Hat ragistry - registry.redhat.io
                               * Downstream Quay registry - brew.registry.redhat.io
                             (Optional)
                             By default - false

    --mirror               - Use local ocp registry.
                             Due to https://issues.redhat.com/browse/RFE-1608,
                             local ocp registry is required.
                             The images are imported and used from the local registry.
                             (Optional) (true/false)
                             By default - true
                             The flag is used only with "--downstream" flag.
                             Otherwise, ignored.

    --skip-gather-logs     - Specify if logs gathering should be skipped.
                             The gathering will be done on all submariner configs.
                             (Optional)
                             By default - false

    Tests arguments:
    ----------------
    --test-type            - Select test type that should be executed.
                             - e2e (api based testing)
                             - ui (cypress testing)
                             (Optional)
                             By default - e2e,ui

    Submariner configuration arguments:
    -----------------------------------
    --globalnet            - Set the state of the Globalnet for the Submariner deployment.
                             The globalnet configuration will be applied starting from
                             ACM version 2.5.0 and Submariner 0.12.0
                             (Optional)
                             By default - false

    --subm-ipsec-natt-port - IPSecNATTPort represents IPsec NAT-T port.
                             (Optional)
                             Submariner default - 4500.
                             Deployment default - 4505.

    --subm-cable-driver    - CableDriver represents the submariner cable driver implementation.
                             Available options are libreswan (default) strongswan, wireguard,
                             and vxlan.
                             (Optional)

    --subm-gateway-count   - Gateways represents the count of worker nodes that will be used
                             to deploy the Submariner gateway component on the managed cluster.
                             The default value is 1, if the value is greater than 1,
                             the Submariner gateway HA will be enabled automatically.
                             (Optional)

    --subm-gateway-random  - Set the deployment flow to randomize the gateway deployment
                             between clusters. When used, the flow will deploy 2 gateway nodes
                             on the first cluster and 1 gateway node on all other clusters.
                             Used by the internal QE flow to test random states of gateways.
                             Note - The use of this flag will ignore the "--subm-gateway-count"
                             flag.
                             (Optional)
                             By default - false

    Reporting arguments:
    --------------------
    --polarion-vars-file   - A path to the file that contains Polarion details.
                             Internal only (used by QE)
                             (Optional)
                             The file should contains the following variables:
                             """
                             [polarion_auth]
                             server = <polarion_server_url>
                             user = <polarion_user>
                             pass = <polarion_pass>

                             [polarion_team_config]
                             project_id = <project_id_name>
                             component_id = <component_name>
                             team_name = <team_name>
                             testrun_template = <testrun_template_name>
                             """
                             Alternatively, those environment variables could be exported.

    --polarion_add_skipped - Add skipped tests to polarion report.
                             Will deplay junit skipped tests as "Waiting" in Polarion (i.e. test not run yet)
                             Internal only (used by QE)
                             (Optional)
                             By default - false

    --help|-h     - Print help
EOF
}

# Login to a cluster with the fiven details
function login_to_cluster() {
    local cluster="$1"

    if [[ "$cluster" == "hub" ]]; then
        oc login --insecure-skip-tls-verify \
            -u "$OC_CLUSTER_USER" -p "$OC_CLUSTER_PASS" "$OC_CLUSTER_API"
        oc cluster-info | grep Kubernetes
    else
        if [[ ! -f "$KCONF/$cluster-password" || ! -f "$KCONF/$cluster-kubeconfig.yaml" ]]; then
            ERROR "Unable login to a $cluster cluster. Missing config files."
        fi

        cluster_pass="$KCONF/$cluster-password"
        cluster_url=$(yq eval '.clusters[].cluster.server' \
                        "$KCONF/$cluster-kubeconfig.yaml")
        oc login --insecure-skip-tls-verify -u "kubeadmin" \
            -p "$(< "$cluster_pass")" "$cluster_url" &> /dev/null
    fi
}

# Fetch the name of the cloud credentials for the cluster
function get_cluster_credential_name() {
    local cluster
    local platform_type
    local cluster_creds_name

    cluster="$1"

    platform_type=$(oc get clusterdeployment -n "$cluster" -o json --no-headers=true \
                 -o custom-columns=PLATFORM:".metadata.labels.hive\.openshift\.io/cluster-platform")
    cluster_creds_name=$(oc get clusterdeployment -n "$cluster" "$cluster" \
                           -o jsonpath={.spec.platform."$platform_type".credentialsSecretRef.name})
    echo "$cluster_creds_name"
}

# Prepare kubeconfig and password of the managed clusters by fetching them from the hub
function fetch_kubeconfig_contexts_and_pass() {
    INFO "Fetch kubeconfig and password for managed clusters"
    local kubeconfig_name
    local pass_name

    rm -rf "$KCONF"
    mkdir -p "$KCONF"

    for cluster in $MANAGED_CLUSTERS; do
        kubeconfig_name=$(oc get -n "$cluster" secrets --no-headers \
                            -o custom-columns=NAME:.metadata.name | grep kubeconfig || true)

        if [[ "$kubeconfig_name" == "" ]]; then
            ERROR "Unable to fetch kubeconfig from $cluster cluster"
        fi

        oc get secrets "$kubeconfig_name" -n "$cluster" \
            --template='{{index .data.kubeconfig | base64decode}}' > "$KCONF/$cluster-kubeconfig.yaml"

        CL="$cluster" yq eval -i '.contexts[].context.user = env(CL)
            | .contexts[].name = env(CL)
            | .current-context = env(CL)
            | .users[].name = env(CL)' "$KCONF/$cluster-kubeconfig.yaml"

        pass_name=$(oc get -n "$cluster" secrets --no-headers \
                      -o custom-columns=NAME:.metadata.name | grep password)
        oc get secrets "$pass_name" -n "$cluster" \
            --template='{{index .data.password | base64decode}}' > "$KCONF/$cluster-password"
    done
}

function validate_internal_registry() {
    INFO "Validate proper configuration of cluster internal registry"
    local registry_state
    local registry_config

    for cluster in $MANAGED_CLUSTERS; do
        local kube_conf="$KCONF/$cluster-kubeconfig.yaml"
        registry_state=$(KUBECONFIG="$kube_conf" oc get \
            configs.imageregistry.operator.openshift.io cluster -o jsonpath='{.spec.managementState}')

        if [[ "$registry_state" == "Removed" ]]; then
            INFO "The $cluster cluster internal registry is not configured. Setting up non prod registry..."
            KUBECONFIG="$kube_conf" oc patch configs.imageregistry.operator.openshift.io \
                cluster --type merge --patch '{"spec":{"managementState":"Managed"}}'

            KUBECONFIG="$kube_conf" oc patch configs.imageregistry.operator.openshift.io \
                cluster --type merge --patch '{"spec":{"storage":{"emptyDir":{}}}}'

            sleep 3m

            registry_config=$(KUBECONFIG="$kube_conf" \
                oc registry info --internal || echo "not_ready")
            if [[ "$registry_config" == "not_ready" ]]; then
                ERROR "The internal registry of $cluster cluster is not ready"
            fi
        fi
    done
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
        if [[ "$SKIP_GATHER_LOGS" == "false" ]]; then
            gather_debug_info
            if [[ -n "$FAILURES" ]]; then
                echo -e "\nExecution aborted. The following failures detected:\n$FAILURES"
            fi
        fi
    fi
}

# Selected options will be printed only when deploy cmd is used.
# The is because thos arguments are not used when running other
# flows, so it does not reflect the actual state of the environment.
function print_selected_options() {
    if [[ "$RUN_COMMAND" == "deploy" ]]; then
        echo -e "\n###############################\n"
        INFO "The following arguments were selected for the execution:
        Run command: $RUN_COMMAND
        Platform: $PLATFORM
        Globalnet: $SUBMARINER_GLOBALNET
        Use downstream deployment: $DOWNSTREAM
        Use downstream mirror: $LOCAL_MIRROR
        Skip gather logs: $SKIP_GATHER_LOGS

        Submariner IPSEC NATT Port: $SUBMARINER_IPSEC_NATT_PORT
        Submariner cable driver: $SUBMARINER_CABLE_DRIVER
        Submariner gateway count: $SUBMARINER_GATEWAY_COUNT
        Submariner gateway random: $SUBMARINER_GATEWAY_RANDOM"
        echo -e "\n###############################\n"
    fi
}
