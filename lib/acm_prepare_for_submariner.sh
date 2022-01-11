#!/bin/bash

# Configure ACM resources as preparation for Submariner Add on install.

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
    INFO "Clusters have been assigned to the clusterset $CLUSTERSET. Assigned: $assigned_clusters"
}
