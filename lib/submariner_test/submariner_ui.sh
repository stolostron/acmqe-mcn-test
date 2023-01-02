#!/bin/bash

# The function executes Submariner UI tests by using cypress tool.
# The cypress tests located within the current repository.
function execute_submariner_ui_tests() {
    INFO "Execute Submariner UI tests"

    pushd "$SCRIPT_DIR/cypress/" || return
    prepare_cypress_env

    local base_url
    base_url=$(oc whoami --show-console)
    export CYPRESS_BASE_URL="$base_url"
    export CYPRESS_OPTIONS_HUB_USER="$OC_CLUSTER_USER"
    export CYPRESS_OPTIONS_HUB_PASSWORD="$OC_CLUSTER_PASS"

    npx cypress run --browser chrome --headless
    combine_cypress_reports

    popd || return
}

function prepare_cypress_env() {
    rm -rf "$SCRIPT_DIR/cypress/results/"

    npm config set unsafe-perm true
    npm install
    npm ci
    npm_config_yes=true npx browserslist@latest --update-db
}

function combine_cypress_reports() {
    INFO "Combine cypress reports"

    local primary_cluster
    primary_cluster=$(echo "$MANAGED_CLUSTERS" | head -n 1)
    tests_basename=$(combine_tests_basename "ui" "$primary_cluster")

    npx jrm "$TESTS_LOGS/${tests_basename}_junit.xml" results/test-results-*.xml
}
