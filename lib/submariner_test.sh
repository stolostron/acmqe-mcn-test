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
        export KUBECONFIG="$TESTS_LOGS/$primary_test_cluster-kubeconfig.yaml:$TESTS_LOGS/$secondary_test_cluster-kubeconfig.yaml"

        INFO "Show all Submariner information"
        subctl show all 2>&1 \
            | tee  "$TESTS_LOGS/subctl_show_all_${primary_test_cluster}_${secondary_test_cluster}.log"

        INFO "Execute diagnose all tests"
        subctl diagnose all 2>&1 \
            | tee "$TESTS_LOGS/subctl_diagnose_all_${primary_test_cluster}_${secondary_test_cluster}.log"

        INFO "Execute diagnose firewall inter-cluster tests"
        subctl diagnose firewall inter-cluster \
            "$TESTS_LOGS/$primary_test_cluster-kubeconfig.yaml" \
            "$TESTS_LOGS/$secondary_test_cluster-kubeconfig.yaml" 2>&1 \
            |  tee "$TESTS_LOGS/subctl_firewall_tests_${primary_test_cluster}_${secondary_test_cluster}.log"

        INFO "Execute E2E tests"
        subctl verify --only service-discovery,connectivity --verbose \
            --kubecontexts "$primary_test_cluster","$secondary_test_cluster" 2>&1 \
            | tee "$TESTS_LOGS/subctl_e2e_tests_${primary_test_cluster}_${secondary_test_cluster}.log"
    done
    INFO "All the tests finished successfully"
    INFO "All the logs are placed within the $TESTS_LOGS directory"
}
