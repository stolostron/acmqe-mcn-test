#!/bin/bash

# Check and configure ACM resources as preparation for Submariner Add on install.

# Check if managed clusters assigned to ACM hub.
function check_managed_clusters() {
    local clusters_count

    # Exclude the "hub" cluster based of the labels "local-cluster" key.
    MANAGED_CLUSTERS=$(oc get managedclusters '--selector=name!=local-cluster' \
                         --no-headers=true -o custom-columns=NAME:.metadata.name)
    clusters_count=$(echo "$MANAGED_CLUSTERS" | wc -w)

    if [[ "$clusters_count" -lt 2 ]]; then
        ERROR "At least two managed clusters required for Submariner deployment. Found - $clusters_count"
    fi

    INFO "Found the following managed clusters:"
    INFO "$MANAGED_CLUSTERS"
}

function create_clusterset() {
    yq eval '.metadata.name = env(CLUSTERSET)' \
        "$SCRIPT_DIR/resources/clusterset.yaml" | oc apply -f -
    oc get managedclusterset "$CLUSTERSET"
}

function assign_clusters_to_clusterset() {
    local assigned_clusters

    INFO "Add the RBAC ClusterRole entry to allow cluster join"
    yq eval '.rules[0].resourceNames = [env(CLUSTERSET)]' \
        "$SCRIPT_DIR/resources/clusterrole.yaml" | oc apply -f -

    INFO "Add managed clusters to the clusterset"
    for cluster in $MANAGED_CLUSTERS; do
        CL="$cluster" yq eval 'with(.metadata; .name = env(CL)
            | .labels."cluster.open-cluster-management.io/clusterset" = env(CLUSTERSET))' \
            resources/managedcluster.yaml | oc apply -f -
    done

    assigned_clusters=$(oc get managedclusters \
                          -l cluster.open-cluster-management.io/clusterset="$CLUSTERSET" \
                          --no-headers=true -o custom-columns=NAME:.metadata.name)
    
    if [[ "$MANAGED_CLUSTERS" != "$assigned_clusters" ]]; then
        ERROR "Failed to assign managed clusters to HUB. Assigned: $assigned_clusters"
    fi
    INFO "Managed clusters have been assigned to the HUB. Assigned: $assigned_clusters"
}
