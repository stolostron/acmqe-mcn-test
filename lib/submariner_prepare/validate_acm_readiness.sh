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

# The SNO (Single Node Openshift) cluster is not supported by the Submariner as ACM Hub Addon
# Detect and exclude the sno cluster from submariner clusters execution
function detect_sno_clusters() {
    local clusters
    local sno_clusters
    local master_count
    local worker_count

    for cluster in $MANAGED_CLUSTERS; do
        master_count=$(oc -n "$cluster" get secret "$cluster"-install-config \
            --template='{{index .data "install-config.yaml" | base64decode}}' \
            | yq eval '.controlPlane.replicas' -)
        worker_count=$(oc -n "$cluster" get secret "$cluster"-install-config \
            --template='{{index .data "install-config.yaml" | base64decode}}' \
            | yq eval '.compute[0].replicas' -)

        if [[ "$master_count" -eq 1 && "$worker_count" -eq 0 ]]; then
            sno_clusters+="$cluster,"
        else
            clusters+="$cluster,"
        fi
    done
    clusters=$(echo "${clusters%,}" | tr "," "\n")
    sno_clusters=$(echo "${sno_clusters%,}" | tr "," "\n")

    if [[ -n "$sno_clusters" ]]; then
        INFO "Detected SNO (Single Node Openshift) clusters
        $sno_clusters
        Excluding as not supported.
        Overriding MANAGED_CLUSTERS list:
        $clusters"

        MANAGED_CLUSTERS="$clusters"
    fi
}

# No POWERSTATE state is available for the managed clusters
# Checking the running state by fetching the ManagedClusterConditionAvailable
# The function will check the platform that will be provided as an input.
function check_managed_clusters_readiness() {
    local clusters="$1"
    local ready_clusters

    for cluster in $clusters; do
        local state=""

        if [[ "$cluster" == "local-cluster" ]]; then
            continue
        fi

        state=$(oc get managedclusters "$cluster" --ignore-not-found \
                 -o jsonpath='{.status.conditions[?(@.type == "ManagedClusterConditionAvailable")].status}')

        if [[ "$state" == "True" ]]; then
            ready_clusters+="$cluster,"
        fi
    done
    ready_clusters=$(echo "${ready_clusters%,}" | tr "," "\n")

    if [[ -n "$ready_clusters" ]]; then
        MANAGED_CLUSTERS=$(echo "$ready_clusters $MANAGED_CLUSTERS" | tr " " "\n")
        MANAGED_CLUSTERS="${MANAGED_CLUSTERS%$'\n'}"
    fi
}

function fetch_managed_cluster_by_platform() {
    local platform="$1"
    local clusters
    INFO "Validate $platform clusters"

    clusters=$(oc get managedcluster -o json \
        | jq -r '.items[] | select(.status.clusterClaims | from_entries
        | select(."platform.open-cluster-management.io"
        | contains("'"$platform"'"))).metadata.name')

    check_managed_clusters_readiness "$clusters"
}

# Fetch the cluster from ManagedClusters resources by defined product (ex: ARO/ROSA).
# Looking for "product.open-cluster-management.io" value of clusterClaims.
function fetch_managed_cluster_by_product() {
    local product="$1"
    local clusters
    INFO "Validate $product clusters"

    clusters=$(oc get managedcluster -o json \
        | jq -r '.items[] | select(.status.clusterClaims | from_entries
        | select(."product.open-cluster-management.io"
        | contains("'"$product"'"))).metadata.name')

    check_managed_clusters_readiness "$clusters"
}

# When a non-globalnet deployment is used, need to ensure
# that requested clusters does not using overlapping cidr
# and exclude the overlapping clusters from the deployment list.
function validate_non_globalnet_clusters() {
    INFO "Non Globalnet deployment selected - Validate clusters"
    local clusters
    local discarded_clusters
    local subnets=()
    local cluster_net
    local service_net
    local platform_str
    local platform_iter

    for cluster in $MANAGED_CLUSTERS; do
        local kube_conf="$KCONF/$cluster-kubeconfig.yaml"

        cluster_net=$(KUBECONFIG="$kube_conf" oc get network.config.openshift.io \
            cluster -o jsonpath='{.status.clusterNetwork[*].cidr}')
        service_net=$(KUBECONFIG="$kube_conf" oc get network.config.openshift.io \
            cluster -o jsonpath='{.status.serviceNetwork[*]}')

        if [[ ! "${subnets[*]}" =~ $cluster_net || ! "${subnets[*]}" =~ $service_net ]]; then
            clusters+="$cluster,"
            subnets+=("$cluster_net")
            subnets+=("$service_net")
        else
            discarded_clusters+="$cluster,"
        fi
    done
    clusters=$(echo "${clusters%,}" | tr "," "\n")
    discarded_clusters=$(echo "${discarded_clusters%,}" | tr "," "\n")

    INFO "The following clusters have non overlapping CIDR:
    $clusters
    Overriding MANAGED_CLUSTERS list"

    if [[ -n "$discarded_clusters" ]]; then
        WARNING "A Non Globalnet deployment selected
        The following clusters were discarded due to overlapping CIDR: $discarded_clusters"
    fi
    MANAGED_CLUSTERS="$clusters"

    for platform in $MANAGED_CLUSTERS; do
        platform_iter=$(locate_cluster_platform "$platform" | tr '[:upper:]' '[:lower:]')
        platform_str+="$platform_iter,"
    done
    PLATFORM="${platform_str%,}"
    INFO "Update PLATFORM variable to met the updated clusters due to non globalnet deployment:
    $PLATFORM"
}

# Check if cluster deployment exists in ACM
function check_clusters_deployment() {
    local clusters_count
    local platform_clusters

    check_requested_platforms
    get_available_platforms

    platform_clusters=$(oc get clusterdeployment -A \
                         --selector "hive.openshift.io/cluster-platform in ($PLATFORM)" \
                         -o jsonpath='{range.items[?(@.status.powerState=="Running")]}{.metadata.name}{"\n"}{end}')
    # ACM 2.4.x missing ".status.powerState", which is added in 2.5.x
    # In case first quesry return empty var, execute a different query
    if [[ -z "$platform_clusters" ]]; then
        platform_clusters=$(oc get clusterdeployment -A \
                             --selector "hive.openshift.io/cluster-platform in ($PLATFORM)" \
                             -o jsonpath='{range.items[?(@.status.conditions[0].reason=="Running")]}{.metadata.name}{"\n"}{end}')
    fi

    for cluster in $platform_clusters; do
        check_managed_clusters_readiness "$cluster"
    done

    detect_sno_clusters

    if [[ "$PLATFORM" =~ "aro" ]]; then
        fetch_managed_cluster_by_product "ARO"
    fi
    if [[ "$PLATFORM" =~ "rosa" ]]; then
        fetch_managed_cluster_by_product "ROSA"
    fi
    if [[ "$PLATFORM" =~ "ibmpower" ]]; then
        fetch_managed_cluster_by_platform "IBMPowerPlatform"
    fi
    if [[ "$PLATFORM" =~ "ibmz" ]]; then
        fetch_managed_cluster_by_platform "IBMZPlatform"
    fi
    if [[ "$PLATFORM" =~ "osp" ]]; then
        fetch_managed_cluster_by_platform "OpenStack"
    fi

    # The fetch is a workaround to get kubeconfig files from imported clusters
    # to validate information. Later this function will run again to fetch
    # the relevant kubeconfigs
    fetch_kubeconfig_contexts_and_pass

    if [[ "$SUBMARINER_GLOBALNET" == "false" ]]; then
        validate_non_globalnet_clusters
    fi

    clusters_count=$(echo "$MANAGED_CLUSTERS" | wc -w)
    if [[ "$clusters_count" -lt 2 ]]; then
        if [[ "$RUN_COMMAND" == "validate-prereq" ]]; then
            VALIDATION_STATE+="Not ready! Found $clusters_count managed clusters, required at least 2."
        else
            ERROR "At least two managed clusters required for Submariner deployment. Found - $clusters_count"
        fi
    fi

    INFO "Found the following active managed clusters:"
    INFO "$MANAGED_CLUSTERS"
}

# When one of the managed clusters claimed from a pool and pre-assigned to a clusterset,
# due to the lack of functionality, it couldn't be removed from that clusterset.
# As a result, this clusterset needs to be used as a clusterset for the submariner
# deployment.
# It will reset the CLUSTERSET environment variable.
function check_for_claim_cluster_with_pre_set_clusterset() {
    INFO "Check for claim cluster"
    local clusters
    local clusters_count
    local claim_cluster
    local claim_clusterset
    local clusterset_defined="false"

    for cluster in $MANAGED_CLUSTERS; do
        claim_cluster=$(oc get clusterdeployment -n "$cluster" "$cluster" --ignore-not-found \
            -o json | jq '.metadata.annotations."hive.openshift.io/cluster-pool-spec-hash"')

        if [[ "$claim_cluster" != @(null|"") ]]; then
            INFO "Claim detected for cluster - $cluster"
            claim_clusterset=$(oc get clusterdeployment -n "$cluster" "$cluster" \
                -o json | jq -r '.metadata.labels."cluster.open-cluster-management.io/clusterset"')

            if [[ "$claim_clusterset" != "null" && "$clusterset_defined" == "false" ]]; then
                INFO "Detected claim cluster $cluster with clusterset $claim_clusterset"
                WARNING "Claim cluster has a pre-defined clusterset.
                That clusterset should be used for the Submariner deployment
                due to ACM limitations.
                Set Submariner ClusterSet to - $claim_clusterset"
                export CLUSTERSET=$claim_clusterset
                clusterset_defined="true"
                clusters+="$cluster,"
            elif [[ "$claim_clusterset" != "null" && "$claim_clusterset" == "$CLUSTERSET" ]]; then
                INFO "Detected claim cluster $cluster with clusterset $claim_clusterset"
                clusters+="$cluster,"
            elif [[ "$claim_clusterset" != "null" && "$claim_clusterset" != "$CLUSTERSET" ]]; then
                WARNING "Detected claim cluster $cluster with conflicting clusterset $claim_clusterset
                    Excluding the cluster from execution list"
            elif [[ "$claim_clusterset" == "null" ]]; then
                INFO "Detected claim cluster $cluster with no clusterset"
                clusters+="$cluster,"
            fi
        else
            INFO "Claim not detected for cluster - $cluster"
            clusters+="$cluster,"
        fi
    done

    clusters=$(echo "${clusters%,}" | tr "," "\n")
    if [[ "$MANAGED_CLUSTERS" != "$clusters" && "$clusterset_defined" == "true" ]]; then
        MANAGED_CLUSTERS="$clusters"

        INFO "Claim clusters clustersets conflicts.
            The new MANAGED CLUSTERS list - $MANAGED_CLUSTERS"
    fi

    clusters_count=$(echo "$MANAGED_CLUSTERS" | wc -w)
    if [[ "$clusters_count" -lt 2 ]]; then
        if [[ "$RUN_COMMAND" == "validate-prereq" ]]; then
            VALIDATION_STATE+="Not ready! Found $clusters_count managed clusters, required at least 2."
        else
            ERROR "At least two managed clusters required for Submariner deployment. Found - $clusters_count"
        fi
    fi
}
