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
    local nettest_img_ref

    primary_test_cluster=$(echo "$MANAGED_CLUSTERS" | head -n 1)

    # Fetch the nettest image with digest to override the subctl reference
    # to the image with floating tags.
    nettest_img_ref=$(KUBECONFIG="$KCONF/$primary_test_cluster-kubeconfig.yaml" \
        oc -n "$SUBMARINER_NS" get pod -l app=submariner-metrics-proxy -o json \
        | jq -r '.items[0].spec.containers[0].image')

    for cluster in $MANAGED_CLUSTERS; do
        if [[ "$cluster" == "$primary_test_cluster" ]]; then
            continue
        fi

        secondary_test_cluster="$cluster"
        tests_basename=$(combine_tests_basename "e2e" "$primary_test_cluster" "$secondary_test_cluster")

        INFO "Running tests between $primary_test_cluster and $secondary_test_cluster clusters"
        export KUBECONFIG="$KCONF/$primary_test_cluster-kubeconfig.yaml:$KCONF/$secondary_test_cluster-kubeconfig.yaml"

        INFO "Show all Submariner information"
        subctl show all 2>&1 \
            | tee  "$TESTS_LOGS_E2E/${tests_basename}_subctl_show_all.log" \
            || add_test_error $?

        INFO "Execute diagnose CNI"
        subctl diagnose cni \
            --context "$primary_test_cluster" \
            --context "$secondary_test_cluster" 2>&1 \
            | tee "$TESTS_LOGS_E2E/${tests_basename}_subctl_diagnose_cni.log" \
            || add_test_error $?

        INFO "Execute diagnose Connections"
        subctl diagnose connections \
            --context "$primary_test_cluster" \
            --context "$secondary_test_cluster" 2>&1 \
            | tee "$TESTS_LOGS_E2E/${tests_basename}_subctl_diagnose_connections.log" \
            || add_test_error $?

        INFO "Execute diagnose Deployment"
        subctl diagnose deployment \
            --image-override submariner-nettest="$nettest_img_ref" \
            --context "$primary_test_cluster" \
            --context "$secondary_test_cluster" 2>&1 \
            | tee "$TESTS_LOGS_E2E/${tests_basename}_subctl_diagnose_deployment.log" \
            || add_test_error $?

        INFO "Execute diagnose k8s-version"
        subctl diagnose k8s-version \
            --context "$primary_test_cluster" \
            --context "$secondary_test_cluster" 2>&1 \
            | tee "$TESTS_LOGS_E2E/${tests_basename}_subctl_diagnose_k8s_version.log" \
            || add_test_error $?

        INFO "Execute diagnose service-discovery"
        subctl diagnose service-discovery \
            --context "$primary_test_cluster" \
            --context "$secondary_test_cluster" 2>&1 \
            | tee "$TESTS_LOGS_E2E/${tests_basename}_subctl_diagnose_service_discovery.log" \
            || add_test_error $?

        INFO "Execute E2E tests"
        subctl verify --verbose \
            --only service-discovery,connectivity,gateway-failover \
            --disruptive-tests \
            --image-override submariner-nettest="$nettest_img_ref" \
            --junit-report "$TESTS_LOGS_E2E/${tests_basename}_e2e_junit.xml" \
            --context "$primary_test_cluster" \
            --tocontext "$secondary_test_cluster" 2>&1 \
            | tee "$TESTS_LOGS_E2E/${tests_basename}_subctl_e2e_tests.log" \
            || add_test_error $?
        unset KUBECONFIG
    done
    INFO "The E2E tests execution finished"
}
