#!/bin/bash

# Configure ACM resources as preparation for Submariner Add on install.

function create_clusterset() {
    yq eval '.metadata.name = env(CLUSTERSET)' \
        "$SCRIPT_DIR/resources/cluster-set.yaml" | oc apply -f -
    oc get managedclusterset "$CLUSTERSET"
}

function assign_clusters_to_clusterset() {
    local assigned_clusters

    INFO "Add the RBAC ClusterRole entry to allow cluster join"
    yq eval '.rules[0].resourceNames = [env(CLUSTERSET)]' \
        "$SCRIPT_DIR/resources/cluster-role.yaml" | oc apply -f -

    INFO "Add managed clusters to the clusterset"
    for cluster in $MANAGED_CLUSTERS; do
        CL="$cluster" yq eval 'with(.metadata; .name = env(CL)
            | .labels."cluster.open-cluster-management.io/clusterset" = env(CLUSTERSET))' \
            resources/managed-cluster.yaml | oc apply -f -
    done

    assigned_clusters=$(oc get managedclusters \
                          -l cluster.open-cluster-management.io/clusterset="$CLUSTERSET" \
                          --no-headers=true -o custom-columns=NAME:.metadata.name)
    
    if [[ "$MANAGED_CLUSTERS" != "$assigned_clusters" ]]; then
        ERROR "Failed to assign managed clusters to HUB. Assigned: $assigned_clusters"
    fi
    INFO "Clusters have been assigned to the clusterset $CLUSTERSET. Assigned: $assigned_clusters"
}

function fetch_multiclusterhub_version() {
    local mch_version

    mch_version=$(oc get multiclusterhub -A -o jsonpath='{.items[0].status.currentVersion}')
    echo "$mch_version"
}

# The submariner version selection will be done
# when brew image source will be selected.
# Otherwise, it will install from official source:
# catalog.redhat.com
function select_submariner_version_to_deploy() {
    INFO "Select downstream Submariner version to deploy"
    local mch_ver

    mch_ver=$(fetch_multiclusterhub_version)
    INFO "MultiClusterHub version - $mch_ver"

    for key in ${!COMPONENT_VERSION[*]}; do
        if [[ "$mch_ver" == "$key"* ]]; then
            SUBMARINER_VERSION_INSTALL="${COMPONENT_VERSION[$key]}"
            INFO "Submariner version - $SUBMARINER_VERSION_INSTALL will be installed"
        fi
    done

    if [[ -z "$SUBMARINER_VERSION_INSTALL" ]]; then
        ERROR "Unable to match between ACM and Submariner versions"
    fi
}
