#!/bin/bash

# The function executes Submariner UI tests by using cypress tool.
# The cypress tests located within the current repository.
function execute_submariner_ui_tests() {
    INFO "Execute Submariner UI tests"
    local primary_cluster
    local base_url
    local subm_state

    pushd "$SCRIPT_DIR/cypress/" || return
    prepare_cypress_env

    primary_cluster=$(echo "$MANAGED_CLUSTERS" | head -n 1)
    tests_basename=$(combine_tests_basename "ui" "$primary_cluster")

    base_url=$(oc whoami --show-console)
    export CYPRESS_BASE_URL="$base_url"
    export CYPRESS_OC_CLUSTER_USER="$OC_CLUSTER_USER"
    export CYPRESS_OC_CLUSTER_PASS="$OC_CLUSTER_PASS"

    export CYPRESS_CLUSTERSET="$CLUSTERSET"
    export CYPRESS_SUBMARINER_IPSEC_NATT_PORT="$SUBMARINER_IPSEC_NATT_PORT"

    export CYPRESS_LOGS_PATH="$TESTS_LOGS_UI"

    npx cypress run --browser "$TEST_BROWSER" --headless --env grepFilterSpecs=true,grepTags=@e2e || true

    INFO "Combine cypress reports"
    npx jrm "$TESTS_LOGS_UI/${tests_basename}_junit.xml" results/test-results-*.xml

    popd || return

    # Restore submariner deployment in case it was deleted by one of the tests
    subm_state=$(oc -n "$primary_cluster" get managedclusteraddon submariner \
        --no-headers=true -o custom-columns=NAME:".metadata.name" --ignore-not-found)
    if [[ "$subm_state" != "submariner" ]]; then
        INFO "Restore submariner deployment to initial state"
        # Wait for 30 sec to ensure that all the resources properly deleted from the managed clusters
        sleep 30s
        (restore_submariner_deployment)
    fi
}

function prepare_cypress_env() {
    rm -rf "$SCRIPT_DIR/cypress/results/"

    npm config set unsafe-perm true
    npm ci
    npm_config_yes=true npx browserslist@latest --update-db
}

function restore_submariner_deployment() {
    select_submariner_version_and_channel_to_deploy
    prepare_clusters_for_submariner
    deploy_submariner_addon
    wait_for_submariner_ready_state
}
