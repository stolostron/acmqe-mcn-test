#!/bin/bash

set -eo pipefail

# Global variables
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

export CLUSTERSET="submariner"
export MANAGED_CLUSTERS=""
export TESTS_LOGS="$SCRIPT_DIR/tests_logs"
export SUBCTL_URL_DOWNLOAD="https://github.com/submariner-io/releases/releases"

# Import functions
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/helper_functions.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/prerequisites.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/acm_prepare.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/submariner_deploy.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/submariner_test.sh"


function verify_required_env_vars() {
    if [[ -z "${OC_CLUSTER_USER}" || -z "${OC_CLUSTER_PASS}" || -z "${OC_CLUSTER_URL}" ]]; then
        ERROR "Execution of the script require all env variables provided:
        'OC_CLUSTER_USER', 'OC_CLUSTER_PASS', 'OC_CLUSTER_URL'"
    fi
}

function prepare() {
    verify_required_env_vars
    verify_prerequisites_tools

    oc login --insecure-skip-tls-verify -u "$OC_CLUSTER_USER" -p "$OC_CLUSTER_PASS" "$OC_CLUSTER_URL"

    check_managed_clusters
}

function deploy_submariner() {
    create_clusterset
    assign_clusters_to_clusterset

    prepare_clusters_for_submariner
    deploy_submariner_addon
    wait_for_submariner_ready_state
}

function test_submariner() {
    verify_subctl_command
    fetch_kubeconfig_contexts
    execute_submariner_tests
}


case "$1" in
    --all)
        prepare
        deploy_submariner
        test_submariner
        ;;
    --deploy)
        prepare
        deploy_submariner
        ;;
    --test)
        prepare
        test_submariner
        ;;
    --help|-h)
        usage
        ;;
    *)
        echo "Invalid argument provided: $1"
        usage
        exit 1
        ;;
esac
