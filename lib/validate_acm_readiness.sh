#!/bin/bash

# Validate ACM Hub is ready for the Submariner addon install and test requirements.

# The function will verify that the platform (aws, gcp, etc...)
# provided by the user or default is within the supported platforms of the script
function check_requested_platforms() {
    INFO "Validate given 'platforms' argument"
    for provider in $(echo "$PLATFORM" | tr ',' ' '); do
        if [[ "$SUPPORTED_PLATFORMS" != *"$provider"* ]]; then
            ERROR "Script supports the following platforms - $SUPPORTED_PLATFORMS. Given - $PLATFORM"
        fi
    done
    INFO "The following platforms requested for testing - $PLATFORM"
}

# The function will search for available clusters
# based on the requested platforms - aws, gcp, etc...
# If one of the requested platforms will not be found,
# the deployment and test flow will continue, but at the end
# of script execution, a failure will be raise and noted that
# requested plafrom was not found.
function get_available_platforms() {
    INFO "Fetch existing clusters platforms"
    local clusters_platforms

    clusters_platforms=$(oc get clusterdeployment -A \
                           --selector "hive.openshift.io/cluster-platform in ($PLATFORM)" \
                           --no-headers=true \
                           -o custom-columns=PLATFORM:".metadata.labels.hive\.openshift\.io/cluster-platform")
    clusters_platforms=$(echo "$clusters_platforms" | uniq)

    for provider in $(echo "$PLATFORM" | tr ',' ' '); do
        if [[ "$clusters_platforms" != *"$provider"* ]]; then
            WARNING "Requested platform - $provider, not in existing cluster platforms - $clusters_platforms"
            FAILURES+="Platform $provider requested, but not found!"
        fi
    done
    INFO "Existing clusters using the following platform - $PLATFORM"
}

# Check if cluster deployment exists in ACM
function check_clusters_deployment() {
    local clusters_count

    check_requested_platforms
    get_available_platforms

    MANAGED_CLUSTERS=$(oc get clusterdeployment -A \
                         --selector "hive.openshift.io/cluster-platform in ($PLATFORM)" \
                         -o jsonpath='{range.items[?(@.status.powerState=="Running")]}{.metadata.name}{"\n"}{end}')
    # ACM 2.4.x missing ".status.powerState", which is added in 2.5.x
    # In case first quesry return empty var, execute a different query
    if [[ -z "$MANAGED_CLUSTERS" ]]; then
        MANAGED_CLUSTERS=$(oc get clusterdeployment -A \
                             --selector "hive.openshift.io/cluster-platform in ($PLATFORM)" \
                             -o jsonpath='{range.items[?(@.status.conditions[0].reason=="Running")]}{.metadata.name}{"\n"}{end}')
    fi
    clusters_count=$(echo "$MANAGED_CLUSTERS" | wc -w)

    if [[ "$clusters_count" -lt 2 ]]; then
        ERROR "At least two managed clusters required for Submariner deployment. Found - $clusters_count"
    fi

    INFO "Found the following active managed clusters:"
    INFO "$MANAGED_CLUSTERS"
}
