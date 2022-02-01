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

# Submariner versioning and image sourcing

# Declare a map to define submariner versions to ACM versions
# The key will define the version of ACM
# The value will define the version of Submariner
declare -A COMPONENT_VERSION
export COMPONENT_VERSION
COMPONENT_VERSION["2.4"]="0.11.1"
COMPONENT_VERSION["2.5"]="0.12"
# Submariner images could be taken from two different places:
# * Official Red Hat registry - registry.redhat.io
# * Downstream Brew registry - brew.registry.redhat.io
# Note - the use of brew will require a secret with brew credentials to present in cluster
# If DOWNSTREAM flag is set to "true", it will fetch downstream images.
export DOWNSTREAM="false"
# The submariner version will be defined and used
# if the source of the images will be set to quay (downstream).
# The submariner version will be selected automatically.
export SUBMARINER_VERSION_INSTALL=""
export SUPPORTED_SUBMARINER_VERSIONS=("0.11.0" "0.11.1" "0.12.0")

export BREW_REGISTRY="brew.registry.redhat.io"
export LATEST_IIB=""


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
source "${SCRIPT_DIR}/lib/downstream_prepare.sh"
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

    if [[ -n "$SUBMARINER_VERSION_INSTALL" ]]; then
        validate_given_submariner_version
    else
        select_submariner_version_to_deploy
    fi

    if [[ "$DOWNSTREAM" == 'true' ]]; then
        create_icsp
        create_catalog_source
    fi

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
                if [[ -n "$2" ]]; then
                    PLATFORM="$2"
                    shift 2
                fi
                ;;
            --version)
                if [[ -n "$2" ]]; then
                    SUBMARINER_VERSION_INSTALL="$2"
                    shift 2
                fi
                ;;
            --downstream)
                DOWNSTREAM="true"
                shift
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
