#!/bin/bash

set -eo pipefail

trap 'catch_error $?' EXIT

# Global variables
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

# Import functions
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/variables"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common/helper_functions.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common/prerequisites.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common/gather_info.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/submariner_prepare/validate_acm_readiness.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/submariner_prepare/acm_prepare_for_submariner.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/submariner_prepare/downstream_prepare.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/submariner_deploy/submariner_deploy.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/submariner_test/submariner_test.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/submariner_test/submariner_e2e.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/submariner_test/submariner_ui.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/reporting/polarion.sh"


function verify_required_env_vars() {
    if [[ -z "${OC_CLUSTER_USER}" || -z "${OC_CLUSTER_PASS}" || -z "${OC_CLUSTER_API}" ]]; then
        if [[ "$RUN_COMMAND" == "validate-prereq" ]]; then
            VALIDATION_STATE+="Not ready! Missing environment vars. Unable to login to the hub."
        else
            ERROR "Execution of the script require all env variables provided:
            'OC_CLUSTER_USER', 'OC_CLUSTER_PASS', 'OC_CLUSTER_API'"
        fi
    fi
    if [[ "$PLATFORM" =~ "rosa" ]]; then
        if [[ -z "${ROSA_TOKEN}" ]]; then
            if [[ "$RUN_COMMAND" == "validate-prereq" ]]; then
                VALIDATION_STATE+="Not ready! Missing environment vars. Unable to login to the hub."
            else
                ERROR "Execution of the script require the following env variable provided:
                'ROSA_TOKEN'"
            fi
        fi
    fi
}

# The function is used by ci to validate the environment for prerequisites.
# This is required to not fail the job if prerequisites are not ready.
# The job will be skipped.
function validate_prerequisites() {
    INFO "Validate prerequisites for deployment"
    local mch_ver

    verify_required_env_vars
    verify_prerequisites_tools
    login_to_cluster "hub"
    check_clusters_deployment
    check_for_claim_cluster_with_pre_set_clusterset

    mch_ver=$(fetch_multiclusterhub_version)
    echo "MultiClusterHub version:"
    echo "$mch_ver" | tee mch_version.log

    if [[ -z "$VALIDATION_STATE" ]]; then
        VALIDATION_STATE+="The environment is ready for the test"
    fi
    echo -e "\n$VALIDATION_STATE" | tee validation_state.log

    WARNING "The following Cluster Deployments present"
    oc get clusterdeployment -A
}

function prepare() {
    print_selected_options
    verify_required_env_vars
    verify_prerequisites_tools
    login_to_cluster "hub"
    check_clusters_deployment
    check_for_claim_cluster_with_pre_set_clusterset
    INFO "Fetch the kubeconfigs for selected clusters only"
    fetch_kubeconfig_contexts_and_pass
}

function deploy_submariner() {
    # Before each deployment, make sure old tests logs removed
    rm -rf "$TESTS_LOGS"
    mkdir -p "$TESTS_LOGS"

    select_submariner_version_and_channel_to_deploy

    if [[ "$PLATFORM" =~ "rosa" ]]; then
        # ROSA (aws ocp managed cluster) requires to create
        # submariner gateway node by using "rosa" binary.
        INFO "Fetch 'rosa' binary"
        verify_rosa_cli
    fi

    if [[ "$DOWNSTREAM" == 'true' ]]; then
        create_brew_and_private_quay_secret
        create_icsp

        create_catalog_source
    fi
    verify_package_manifest

    create_clusterset
    assign_clusters_to_clusterset
    prepare_clusters_for_submariner
    deploy_submariner_broker
    deploy_submariner_addon
    wait_for_submariner_ready_state
}

function test_submariner() {
    execute_submariner_tests

    if [[ "$SKIP_GATHER_LOGS" == "false" ]]; then
        INFO "Gather ACM Hub and managed clusters information"
        gather_debug_info
    fi
}

function report() {
    report_polarion
}

function update_submariner_catalog() {
    select_submariner_version_and_channel_to_deploy
    update_catalog_source
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
            --subm-catalog-update)
                RUN_COMMAND="catalog-update"
                shift
                ;;
            --test)
                RUN_COMMAND="test"
                shift
                ;;
            --report)
                RUN_COMMAND="report"
                shift
                ;;
            --gather-logs)
                RUN_COMMAND="gather-logs"
                shift
                ;;
            --validate-prereq)
                # The argument is used by the ci flow
                RUN_COMMAND="validate-prereq"
                shift
                ;;
            --platform)
                if [[ -n "$2" ]]; then
                    export PLATFORM="$2"
                    shift 2
                fi
                ;;
            --version)
                if [[ -n "$2" ]]; then
                    export SUBMARINER_VERSION_INSTALL="$2"
                    shift 2
                fi
                ;;
            --globalnet)
                if [[ -n "$2" ]]; then
                    export SUBMARINER_GLOBALNET="$2"
                    shift 2
                fi
                ;;
            --downstream)
                if [[ -n "$2" ]]; then
                    export DOWNSTREAM="$2"
                    shift 2
                fi
                ;;
            --skip-gather-logs)
                if [[ -n "$2" ]]; then
                    export SKIP_GATHER_LOGS="$2"
                    shift 2
                fi
                ;;
            --test-type)
                if [[ -n "$2" ]]; then
                    export TEST_TYPE="$2"
                    shift 2
                fi
                ;;
            --test-browser)
                if [[ -n "$2" ]]; then
                    export TEST_BROWSER="$2"
                    shift 2
                fi
                ;;
            --report-suffix)
                if [[ -n "$2" ]]; then
                    export TEST_REPORT_SUFFIX="$2"
                    shift 2
                fi
                ;;
            --subm-ipsec-natt-port)
                if [[ -n "$2" ]]; then
                    export SUBMARINER_IPSEC_NATT_PORT="$2"
                    shift 2
                fi
                ;;
            --subm-cable-driver)
                if [[ -n "$2" ]]; then
                    export SUBMARINER_CABLE_DRIVER="$2"
                    shift 2
                fi
                ;;
            --subm-gateway-count)
                if [[ -n "$2" ]]; then
                    export SUBMARINER_GATEWAY_COUNT="$2"
                    shift 2
                fi
                ;;
            --subm-gateway-random)
                if [[ -n "$2" ]]; then
                    export SUBMARINER_GATEWAY_RANDOM="$2"
                    shift 2
                fi
                ;;
            --polarion-vars-file)
                if [[ -n "$2" ]]; then
                    export POLARION_VARS_FILE="$2"
                    shift 2
                fi
                ;;
            --polarion_add_skipped)
                export POLARION_ADD_SKIPPED="true"
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
            report
            finalize
            ;;
        deploy)
            prepare
            deploy_submariner
            finalize
            ;;
        catalog-update)
            prepare
            update_submariner_catalog
            finalize
            ;;
        test)
            prepare
            test_submariner
            finalize
            ;;
        report)
            report
            finalize
            ;;
        gather-logs)
            prepare
            gather_debug_info
            ;;
        validate-prereq)
            validate_prerequisites
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
