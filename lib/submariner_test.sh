#!/bin/bash

# Perform Submariner test by using the "subctl" command.

# The function executes Submariner E2E tests by using the subctl tool.
# The subctl tool is able to run E2E tests only on two clusters
# at the same time.
# In order to be able to test all clusters which contains
# submariner addon, the function below is using the first managed
# cluster as a primary cluster and all other clusters will run E2E
# tests with the primary cluster.
function execute_submariner_tests() {
    INFO "Execute Submariner tests"

    rm -rf "$TESTS_LOGS"
    mkdir -p "$TESTS_LOGS"

    # Subctl E2E tests are working with 2 clusters only at a time
    local primary_test_cluster
    local secondary_test_cluster

    primary_test_cluster=$(echo "$MANAGED_CLUSTERS" | head -n 1)

    for cluster in $MANAGED_CLUSTERS; do
        if [[ "$cluster" == "$primary_test_cluster" ]]; then
            continue
        fi

        secondary_test_cluster="$cluster"

        INFO "Running tests between $primary_test_cluster and $secondary_test_cluster clusters"
        export KUBECONFIG="$LOGS/$primary_test_cluster-kubeconfig.yaml:$LOGS/$secondary_test_cluster-kubeconfig.yaml"

        INFO "Show all Submariner information"
        subctl show all 2>&1 \
            | tee  "$TESTS_LOGS/subctl_show_all_${primary_test_cluster}_${secondary_test_cluster}.log" \
            || add_test_error $?

        INFO "Execute diagnose all tests"
        subctl diagnose all 2>&1 \
            | tee "$TESTS_LOGS/subctl_diagnose_all_${primary_test_cluster}_${secondary_test_cluster}.log" \
            || add_test_error $?

        INFO "Execute diagnose firewall inter-cluster tests"
        subctl diagnose firewall inter-cluster \
            "$LOGS/$primary_test_cluster-kubeconfig.yaml" \
            "$LOGS/$secondary_test_cluster-kubeconfig.yaml" 2>&1 \
            |  tee "$TESTS_LOGS/subctl_firewall_tests_${primary_test_cluster}_${secondary_test_cluster}.log" \
            || add_test_error $?

        INFO "Execute E2E tests"
        # Due to https://github.com/submariner-io/submariner-operator/issues/1977
        if subctl verify --help | grep -q --no-messages junit-report; then
            subctl verify --only service-discovery,connectivity --verbose \
                --junit-report "$TESTS_LOGS/submariner_e2e.xml" \
                --kubecontexts "$primary_test_cluster,$secondary_test_cluster" 2>&1 \
                | tee "$TESTS_LOGS/subctl_e2e_tests_${primary_test_cluster}_${secondary_test_cluster}.log" \
                || add_test_error $?
        else
            subctl verify --only service-discovery,connectivity --verbose \
                --kubecontexts "$primary_test_cluster,$secondary_test_cluster" 2>&1 \
                | tee "$TESTS_LOGS/subctl_e2e_tests_${primary_test_cluster}_${secondary_test_cluster}.log" \
                || add_test_error $?
        fi
    done
    unset KUBECONFIG
    INFO "Tests execution finished"
    INFO "All the logs are placed within the $TESTS_LOGS directory"
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
