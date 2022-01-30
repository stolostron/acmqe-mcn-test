#!/bin/bash

set -eo pipefail

# Global variables
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

export CLUSTERSET="submariner"
export MANAGED_CLUSTERS=""
export TESTS_LOGS="$SCRIPT_DIR/tests_logs"
export SUBCTL_URL_DOWNLOAD="https://github.com/submariner-io/releases/releases"
export PLATFORM="aws,gcp"  # Default platform definition
export SUPPORTED_PLATFORMS="aws,gcp"  # Supported platform definition
# Non critial failures will be stored into the variable
# and printed at the end of the execution.
# The testing will be performed,
# but the failure of the final result will be set.
export FAILURES=""

# Import functions
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/helper_functions.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/prerequisites.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/validate_acm_readiness.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/acm_prepare_for_submariner.sh"
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

    check_clusters_deployment
    fetch_kubeconfig_contexts
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
    execute_submariner_tests
}

function finalize() {
    if  [[ -n "$FAILURES" ]]; then
        ERROR "Execution finished, but the following failures detected: $FAILURES"
    fi
}

function parse_arguments() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --all)
                RUN_COMMAND="all"
                shift
                ;;
            --deploy)
                RUN_COMMAND="deploy"
                shift
                ;;
            --test)
                RUN_COMMAND="test"
                shift
                ;;
            --platform)
                if [ -n "$2" ]; then
                    PLATFORM="$2"
                    shift 2
                fi
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                echo "Invalid argument provided: $1"
                usage
                exit 1
                ;;
        esac
    done
}


function main() {
    RUN_COMMAND=all
    parse_arguments "$@"

    case "$RUN_COMMAND" in
        all)
            prepare
            deploy_submariner
            test_submariner
            finalize
            ;;
        deploy)
            prepare
            deploy_submariner
            finalize
            ;;
        test)
            prepare
            test_submariner
            finalize
            ;;
        *)
            echo "Invalid command given: $RUN_COMMAND"
            usage
            exit 1
            ;;
    esac
}

# Trigger main function
main "$@"
