#!/bin/bash

# Perform Submariner E2E tests by using the "subctl" command
# and Submariner UI tests by using cypress tool.

function execute_submariner_tests() {
    INFO "Execute Submariner tests"

    rm -rf "$TESTS_LOGS"
    mkdir -p "$TESTS_LOGS"

    verify_subctl_command

    if [[ "$TEST_TYPE" =~ "e2e" ]]; then
        execute_submariner_e2e_tests
    fi

    if [[ "$TEST_TYPE" =~ "ui" ]]; then
        verify_cypress
        # If cypress prerequisites are not fulfilled,
        # cypress tests will be skipped.
        if [[ "$UI_TESTS" == "false" ]]; then
            WARNING "Skip UI tests execution - system is not ready"
        else
            execute_submariner_ui_tests
        fi
    fi

    INFO "Tests execution finished"
    INFO "All the logs are placed within the $TESTS_LOGS directory"
}

# The function will combine test report basename.
# The function has types of tests it serves - "e2e" and "ui".
# The e2e test basename will contain platforms in the basename:
# - ACM-2.7.0-Submariner-0.14.1-AWS-GCP-Globalnet
# It means need to provide all three args - "type", "primary_cluster", "second_cluster"
# While UI test will skip platform details as it run only for the dashboard UI
# - ACM-2.7.0-Submariner-0.14.1-Globalnet-UI
# It means need to provide two args - "type" and "primary_cluster".
function combine_tests_basename() {
    local type="$1"  # e2e or ui
    local primary_cluster="$2"
    local secondary_cluster="$3"
    local acm_ver
    local subm_ver
    local primary_cl_platform
    local secondary_cl_platform
    local globalnet
    local globalnet_state=""

    acm_ver=$(oc get multiclusterhub -A -o jsonpath='{.items[0].status.currentVersion}')
    subm_ver=$(KUBECONFIG="$LOGS/$primary_cluster-kubeconfig.yaml" \
        oc -n submariner-operator get subs submariner \
        -o jsonpath='{.status.currentCSV}' \
        | grep -Po '(?<=submariner.v)[^)]*' | cut -d '-' -f1)

    globalnet_state=$(KUBECONFIG="$LOGS/$primary_cluster-kubeconfig.yaml" \
        oc -n submariner-operator get pods -l=app=submariner-globalnet \
        --no-headers=true -o custom-columns=NAME:".metadata.name")
    if [[ -z "$globalnet_state" ]]; then
        globalnet="NonGlobalnet"
    else
        globalnet="Globalnet"
    fi

    if [[ "$type" == "e2e" ]]; then
        primary_cl_platform=$(locate_cluster_platform "$primary_cluster")
        secondary_cl_platform=$(locate_cluster_platform "$secondary_cluster")

        echo "ACM-${acm_ver}-Submariner-${subm_ver}-${primary_cl_platform}-${secondary_cl_platform}-${globalnet}"
    elif [[ "$type" == "ui" ]]; then
        echo "ACM-${acm_ver}-Submariner-${subm_ver}-${globalnet}-UI"
    fi
}

# When one of the tests fails, add the error note to a global variable.
# At the end of all tests, the variable will be checked.
# If error occured, tests errors will be printed
function add_test_error() {
    local test_exit_code="$1"

    if (( "$test_exit_code" > 0 )); then
        WARNING "One of the tests failed... Adding to log"
        export TESTS_FAILURES="true"
    fi
}

function get_tests_failures() {
    WARNING "The following tests failures occured"

    local diagnose_logs
    local e2e_tests_log

    for log in "$TESTS_LOGS"/*.log; do
        diagnose_logs=$(grep --no-messages '✗' "$log" || true)
        if [[ -n "$diagnose_logs" ]]; then
            echo
            WARNING "Erros found in the following tests - $log"
            echo "$diagnose_logs"
        fi

        e2e_tests_log=$(sed -n -e '/Summarizing.*.Failures/,$p' "$log")
        if [[ -n "$e2e_tests_log" ]]; then
            echo
            WARNING "Erros found in the following tests - $log"
            echo "$e2e_tests_log"
        fi
    done
}
