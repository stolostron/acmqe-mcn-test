#!/bin/bash

set -eo pipefail

trap 'catch_error $?' EXIT

# Global variables
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

export CLUSTERSET="submariner"
export SUBMARINER_NS="submariner-operator"
export SUBMARINER_GLOBALNET="false"
export MANAGED_CLUSTERS=""
export GATHER_LOGS="true"
export LOGS="$SCRIPT_DIR/logs"
export TESTS_LOGS="$LOGS/tests_logs"
export DEBUG_LOGS="$LOGS/debug_logs"
export LOG_PATH=""
export SUBCTL_URL_DOWNLOAD="https://github.com/submariner-io/releases/releases"
export SUBM_OPERATOR_URL="https://github.com/submariner-io/submariner-operator"
export PLATFORM="aws,gcp"  # Default platform definition
export SUPPORTED_PLATFORMS="aws,gcp"  # Supported platform definition
# Non critial failures will be stored into the variable
# and printed at the end of the execution.
# The testing will be performed,
# but the failure of the final result will be set.
export FAILURES=""
export TESTS_FAILURES="false"

# Submariner versioning and image sourcing
# Declare a map to define submariner versions and channel to ACM versions
# The key will define the version of ACM
# The value will define the version of Submariner and a channel

# Declare associative arrays
declare -A ACM_2_4=(
    [acm_version]='2.4'
    [submariner_version]='0.11.2'
    [channel]='alpha'
)
export ACM_2_4
declare -A ACM_2_5=(
    [acm_version]='2.5'
    [submariner_version]='0.12.0'
    [channel]='stable'
)
export ACM_2_5
# Declare array of COMPONENTS_VERSIONS of associative arrays
export COMPONENT_VERSIONS=("${!ACM@}")


# Submariner images could be taken from two different places:
# * Official Red Hat registry - registry.redhat.io
# * Downstream Brew registry - brew.registry.redhat.io
# Note - the use of brew will require a secret with brew credentials to present in cluster
# If DOWNSTREAM flag is set to "true", it will fetch downstream images.
export DOWNSTREAM="false"
# Due to https://issues.redhat.com/browse/RFE-1608, add the ability
# to use local ocp cluster registry and import the images.
export LOCAL_MIRROR="true"
# The submariner version will be defined and used
# if the source of the images will be set to quay (downstream).
# The submariner version will be selected automatically.
export SUBMARINER_VERSION_INSTALL=""
export SUPPORTED_SUBMARINER_VERSIONS=("0.11.0" "0.11.2" "0.12.0")
export SUBMARINER_CHANNEL_RELEASE=""
# The default IPSEC NATT port is - 4500
export SUBMARINER_IPSEC_NATT_PORT=4505
export SUBMARINER_CABLE_DRIVER="libreswan"
export SUBMARINER_GATEWAY_COUNT=1
# Official RedHat registry
export OFFICIAL_REGISTRY="registry.redhat.io"
export STAGING_REGISTRY="registry.stage.redhat.io"
# External RedHat downstream registry (require authentication)
export BREW_REGISTRY="brew.registry.redhat.io"
export REGISTRY_IMAGE_PREFIX="rhacm2"
export REGISTRY_IMAGE_PREFIX_TECH_PREVIEW="rhacm2-tech-preview"
export REGISTRY_IMAGE_IMPORT_PATH="rh-osbs"
export CATALOG_REGISTRY="registry.access.redhat.com"
export CATALOG_IMAGE_PREFIX="openshift4"
export CATALOG_IMAGE_IMPORT_PATH="ose-oauth-proxy"
# Internal RedHat downstream registry
export VPN_REGISTRY="registry-proxy.engineering.redhat.com"
# Submariner images names
export SUBM_IMG_BUNDLE="submariner-operator-bundle"
export SUBM_IMG_OPERATOR="submariner-rhel8-operator"
export SUBM_IMG_GATEWAY="submariner-gateway-rhel8"
export SUBM_IMG_ROUTE="submariner-route-agent-rhel8"
export SUBM_IMG_NETWORK="submariner-networkplugin-syncer-rhel8"
export SUBM_IMG_LIGHTHOUSE="lighthouse-agent-rhel8"
export SUBM_IMG_COREDNS="lighthouse-coredns-rhel8"
export SUBM_IMG_GLOBALNET="submariner-globalnet-rhel8"

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
source "${SCRIPT_DIR}/lib/downstream_mirroring_workaround.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/submariner_deploy.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/submariner_test.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/gather_info.sh"


function verify_required_env_vars() {
    if [[ -z "${OC_CLUSTER_USER}" || -z "${OC_CLUSTER_PASS}" || -z "${OC_CLUSTER_URL}" ]]; then
        ERROR "Execution of the script require all env variables provided:
        'OC_CLUSTER_USER', 'OC_CLUSTER_PASS', 'OC_CLUSTER_URL'"
    fi
}

function prepare() {
    verify_required_env_vars
    verify_prerequisites_tools

    login_to_cluster "hub"

    check_clusters_deployment
    check_for_claim_cluster_with_pre_set_clusterset
    fetch_kubeconfig_contexts_and_pass
}

function deploy_submariner() {
    if [[ -n "$SUBMARINER_VERSION_INSTALL" ]]; then
        validate_given_submariner_version
    else
        select_submariner_version_and_channel_to_deploy
    fi

    if [[ "$DOWNSTREAM" == 'true' ]]; then
        if [[ "$LOCAL_MIRROR" == "true" ]]; then
            create_namespace
        fi

        create_brew_secret

        if [[ "$LOCAL_MIRROR" == 'true' ]]; then
            INFO "Using local ocp cluster due to -
            https://issues.redhat.com/browse/RFE-1608"
            set_custom_registry_mirror
            import_images_into_local_registry
        fi

        if [[ "$LOCAL_MIRROR" == 'false' ]]; then
            # https://issues.redhat.com/browse/RFE-1608
            create_icsp
        fi

        create_catalog_source
        verify_package_manifest
    fi

    create_clusterset
    assign_clusters_to_clusterset
    prepare_clusters_for_submariner
    deploy_submariner_broker
    deploy_submariner_addon
    wait_for_submariner_ready_state
}

function test_submariner() {
    verify_subctl_command
    execute_submariner_tests

    if [[ "$GATHER_LOGS" == "true" ]]; then
        INFO "Gather ACM Hub and managed clusters information"
        gather_debug_info
    fi
}

function finalize() {
    if [[ "$TESTS_FAILURES" == "true" ]]; then
        WARNING "Tests execution contains failures"
        get_tests_failures
    fi

    if [[ -n "$FAILURES" ]]; then
        WARNING "Execution finished, but the following failures detected: $FAILURES"
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
            --globalnet)
                if [[ -n "$2" ]]; then
                    SUBMARINER_GLOBALNET="$2"
                    shift 2
                fi
                ;;
            --downstream)
                DOWNSTREAM="true"
                shift
                ;;
            --mirror)
                if [[ -n "$2" ]]; then
                    LOCAL_MIRROR="$2"
                    shift 2
                fi
                ;;
            --gather-logs)
                if [[ -n "$2" ]]; then
                    GATHER_LOGS="$2"
                    shift 2
                fi
                ;;
            --subm-ipsec-natt-port)
                if [[ -n "$2" ]]; then
                    SUBMARINER_IPSEC_NATT_PORT="$2"
                    shift 2
                fi
                ;;
            --subm-cable-driver)
                if [[ -n "$2" ]]; then
                    SUBMARINER_CABLE_DRIVER="$2"
                    shift 2
                fi
                ;;
            --subm-gateway-count)
                if [[ -n "$2" ]]; then
                    SUBMARINER_GATEWAY_COUNT="$2"
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
