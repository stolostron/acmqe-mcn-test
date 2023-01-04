#!/bin/bash

# The function executes Submariner E2E tests by using the subctl tool.
# The subctl tool is able to run E2E tests only on two clusters
# at the same time.
# In order to be able to test all clusters which contains
# submariner addon, the function below is using the first managed
# cluster as a primary cluster and all other clusters will run E2E
# tests with the primary cluster.
function execute_submariner_e2e_tests() {
    INFO "Execute Submariner E2E tests"

    # Subctl E2E tests are working with 2 clusters only at a time
    local primary_test_cluster
    local secondary_test_cluster
    local tests_basename

    primary_test_cluster=$(echo "$MANAGED_CLUSTERS" | head -n 1)

    for cluster in $MANAGED_CLUSTERS; do
        if [[ "$cluster" == "$primary_test_cluster" ]]; then
            continue
        fi

        secondary_test_cluster="$cluster"
        tests_basename=$(combine_tests_basename "e2e" "$primary_test_cluster" "$secondary_test_cluster")

        INFO "Running tests between $primary_test_cluster and $secondary_test_cluster clusters"
        export KUBECONFIG="$LOGS/$primary_test_cluster-kubeconfig.yaml:$LOGS/$secondary_test_cluster-kubeconfig.yaml"

        INFO "Show all Submariner information"
        subctl show all 2>&1 \
            | tee  "$TESTS_LOGS/${tests_basename}_subctl_show_all.log" \
            || add_test_error $?

        INFO "Execute diagnose all tests"
        subctl diagnose all 2>&1 \
            | tee "$TESTS_LOGS/${tests_basename}_subctl_diagnose_all.log" \
            || add_test_error $?

        INFO "Execute diagnose firewall inter-cluster tests"
        subctl diagnose firewall inter-cluster \
            "$LOGS/$primary_test_cluster-kubeconfig.yaml" \
            "$LOGS/$secondary_test_cluster-kubeconfig.yaml" 2>&1 \
            |  tee "$TESTS_LOGS/${tests_basename}_subctl_firewall_tests.log" \
            || add_test_error $?

        INFO "Execute E2E tests"
        subctl verify --only service-discovery,connectivity --verbose \
            --junit-report "$TESTS_LOGS/${tests_basename}_e2e_junit.xml" \
            --kubecontexts "$primary_test_cluster,$secondary_test_cluster" 2>&1 \
            | tee "$TESTS_LOGS/${tests_basename}_subctl_e2e_tests.log" \
            || add_test_error $?
        unset KUBECONFIG
    done
    INFO "The E2E tests execution finished"
}
