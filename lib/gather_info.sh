#!/bin/bash

# The functions will gather useful information from the Hub and
# managed clusters that might help in later debug of any issue.

function get_submariner_pods() {
    LOG "Get Submariner pods"
    local kube_conf="$1"
    local cluster_log="$2"

    KUBECONFIG="$kube_conf" oc -n "$SUBMARINER_NS" get pods \
        2>&1 | tee -a "$cluster_log"
}

function get_submariner_pods_images() {
    LOG "Get Submariner pods images"
    local kube_conf="$1"
    local cluster_log="$2"

    pods=$(KUBECONFIG="$kube_conf" oc -n "$SUBMARINER_NS" \
             get pods -o jsonpath='{.items[*].metadata.name}')
    for pod in $pods; do
        KUBECONFIG="$kube_conf" oc -n "$SUBMARINER_NS" get pods \
            "$pod" -o jsonpath='{.status.containerStatuses[0].imageID}'
        echo
    done
}

function get_submariner_pods_content() {
    LOG "Get Submariner pods content"
    local kube_conf="$1"
    local cluster_log="$2"
    local pods=""

    pods=$(KUBECONFIG="$kube_conf" oc -n "$SUBMARINER_NS" \
             get pods -o jsonpath='{.items[*].metadata.name}')
    for pod in $pods; do
        LOG "Pod $pod content"
        KUBECONFIG="$kube_conf" oc -n "$SUBMARINER_NS" describe \
            pod "$pod" 2>&1 | tee -a "$cluster_log"
    done
}

function get_cluster_service_version() {
    LOG "Get ClusterServiceVersion"
    local kube_conf="$1"
    local cluster_log="$2"
    local csv_version=""

    csv_version=$(KUBECONFIG="$kube_conf" \
                    oc -n "$SUBMARINER_NS" get csv -o json \
                    | jq -r '.items[] | select(.metadata.name 
                    | test("submariner")).metadata.name')
    if [[ -n "$csv_version" ]]; then
        KUBECONFIG="$kube_conf" \
            oc -n "$SUBMARINER_NS" get csv "$csv_version" \
            -o yaml 2>&1 | tee -a "$cluster_log"
    else
        LOG "No Submariner ClusterServiceVersion has been found"
    fi
}

function get_submariner_config_crd() {
    LOG "Get SubmarinerConfig CRD"
    local kube_conf="$1"
    local cluster_log="$2"

    KUBECONFIG="$kube_conf" oc get crd \
        submarinerconfigs.submarineraddon.open-cluster-management.io \
        -o yaml --ignore-not-found 2>&1 | tee -a "$cluster_log"
}

function get_icsp() {
    LOG "Get ICSP"
    local kube_conf="$1"
    local cluster_log="$2"
    local icsp=""

    icsp=$(KUBECONFIG="$kube_conf" oc get imagecontentsourcepolicy \
        -o jsonpath='{.items[?(@.metadata.name=="brew-registry")].metadata.name}')
    if [[ -n "$icsp" ]]; then
        KUBECONFIG="$kube_conf" oc get imagecontentsourcepolicy "$icsp" \
            -o yaml 2>&1 | tee -a "$cluster_log"
    else
        LOG "No ICSP for brew-registry has been found"
    fi
}

function get_catalog_source() {
    LOG "Get Submariner CatalogSource"
    local kube_conf="$1"
    local cluster_log="$2"
    local catalog_name=""
    local catalog_ns

    catalog_name=$(KUBECONFIG="$kube_conf" oc get catalogsource -A \
                -o jsonpath='{.items[?(@.metadata.name=="submariner-catalog")].metadata.name}')
    if [[ -n "$catalog_name" ]]; then
        catalog_ns=$(KUBECONFIG="$kube_conf" oc get catalogsource -A \
                -o jsonpath='{.items[?(@.metadata.name=="submariner-catalog")].metadata.namespace}')
        KUBECONFIG="$kube_conf" oc -n "$catalog_ns" get catalogsource \
            "$catalog_name" -o yaml 2>&1 | tee -a "$cluster_log"
    else
        LOG "No Submariner CatalogSource has been found"
    fi
}

function get_submariner_pods_logs() {
    LOG "Gather Submariner pods logs"
    LOG "The logs will be stored in the $cluster_log-pod_logs path"
    local kube_conf="$1"
    local cluster_log="$2-pod_logs"
    local pods=""
    export LOG_PATH="$cluster_log"

    pods=$(KUBECONFIG="$kube_conf" oc -n "$SUBMARINER_NS" \
             get pods -o jsonpath='{.items[*].metadata.name}')
    for pod in $pods; do
        KUBECONFIG="$kube_conf" oc -n "$SUBMARINER_NS" \
            logs "$pod" >> "$cluster_log"
    done
}

function gather_cluster_info() {
    local kube_conf
    local cluster_log

    for cluster in $MANAGED_CLUSTERS; do
        LOG "Gather information for $cluster cluster"
        kube_conf="$LOGS/$cluster-kubeconfig.yaml"
        cluster_log="$DEBUG_LOGS/$cluster.log"
        # The LOG_PATH env is set to append the LOG
        # messages into the log files.
        LOG_PATH="$cluster_log"

        get_submariner_pods "$kube_conf" "$cluster_log"
        get_submariner_pods_images "$kube_conf" "$cluster_log"
        get_submariner_pods_content "$kube_conf" "$cluster_log"
        get_cluster_service_version "$kube_conf" "$cluster_log"
        get_submariner_config_crd "$kube_conf" "$cluster_log"
        get_icsp "$kube_conf" "$cluster_log"
        get_catalog_source "$kube_conf" "$cluster_log"
        get_submariner_pods_logs "$kube_conf" "$cluster_log"
    done
}

function gather_hub_info() {
    local acm_hub_log="$DEBUG_LOGS/acm_hub.log"
    # The LOG_PATH env is set to append the LOG
    # messages into the log files.
    LOG_PATH="$acm_hub_log"
    LOG "Gather ACM Hub information"

    for cluster_ns in $MANAGED_CLUSTERS; do
        LOG "Get ClusterDeployments clusters"
        oc get clusterdeployment -A \
            --ignore-not-found 2>&1 | tee -a "$acm_hub_log"

        LOG "Get ClusterDeployments clusters details"
        oc get clusterdeployment -A -o yaml \
            --ignore-not-found 2>&1 | tee -a "$acm_hub_log"

        LOG "Get MultiClusterHub details"
        oc get multiclusterhub -A -o yaml \
            --ignore-not-found 2>&1 | tee -a "$acm_hub_log"

        LOG "Get Submariner ClusterSet details"
        oc get managedclusterset "$CLUSTERSET" -o yaml \
            --ignore-not-found 2>&1 | tee -a "$acm_hub_log"

        LOG "Get SubmarinerConfig from $cluster cluster"
        oc -n "$cluster_ns" get submarinerconfig submariner \
            -o yaml --ignore-not-found 2>&1 | tee -a "$acm_hub_log"

        LOG "Get ManagedClusterAddon from $cluster cluster"
        oc -n "$cluster_ns" get managedclusteraddon submariner \
            -o yaml --ignore-not-found 2>&1 | tee -a "$acm_hub_log"
    done
}

function gather_debug_info() {
    INFO "Gather debug info from ACM Hub and managed clusters"
    
    rm -rf "$DEBUG_LOGS"
    mkdir -p "$DEBUG_LOGS"

    gather_hub_info
    gather_cluster_info
    INFO "Debug logs have been gathered"
}
