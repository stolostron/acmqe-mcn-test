#!/bin/bash

# The functions will gather useful information from the Hub and
# managed clusters that might help in later debug of any issue.

function get_submariner_pods() {
    LOG "Get Submariner pods"
    local kube_conf="$1"
    local cluster_log="$2"

    KUBECONFIG="$kube_conf" oc -n "$SUBMARINER_NS" get pods > \
        "${cluster_log}_pods_state.log"
}

function get_submariner_describe_pods() {
    LOG "Get Submariner pods content"
    local kube_conf="$1"
    local cluster_log="$2"
    local pods=""

    pods=$(KUBECONFIG="$kube_conf" oc -n "$SUBMARINER_NS" \
             get pods -o jsonpath='{.items[*].metadata.name}')
    for pod in $pods; do
        KUBECONFIG="$kube_conf" oc -n "$SUBMARINER_NS" describe \
            pod "$pod" > "${cluster_log}_describe_${pod}.log"
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
            -o yaml > "${cluster_log}_csv.yaml"
    else
        LOG "No Submariner ClusterServiceVersion has been found"
    fi
}

function get_icsp() {
    local kube_conf="$1"
    local cluster_log="$2"
    local icsp=""

    icsp=$(KUBECONFIG="$kube_conf" oc get imagecontentsourcepolicy \
        -o jsonpath='{.items[?(@.metadata.name=="brew-registry")].metadata.name}')
    if [[ -n "$icsp" ]]; then
        LOG "Get ICSP"
        KUBECONFIG="$kube_conf" oc get imagecontentsourcepolicy "$icsp" \
            -o yaml > "${cluster_log}_icsp.yaml"
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
            "$catalog_name" -o yaml > "${cluster_log}_catalog_source.yaml"
    else
        LOG "No Submariner CatalogSource has been found"
    fi
}

function get_package_manifest() {
    LOG "Get Submariner PackageManifest"
    local kube_conf="$1"
    local cluster_log="$2"

    KUBECONFIG="$kube_conf" oc -n "$SUBMARINER_NS" \
        get packagemanifest submariner -o yaml \
        --ignore-not-found > "${cluster_log}_package_manifest.yaml"
}

function get_submariner_addon_log() {
    LOG "Get submariner-addon log"
    local kube_conf="$1"
    local cluster_log="$2"
    local addon_pod

    addon_pod=$(KUBECONFIG="$kube_conf" oc -n "$SUBMARINER_NS" \
        get pods -l app=submariner-addon --no-headers=true \
        -o custom-columns=NAME:.metadata.name)

    if [[ -n "$addon_pod" ]]; then
        KUBECONFIG="$kube_conf" oc -n "$SUBMARINER_NS" \
            logs "$addon_pod" >> "${cluster_log}_submariner_addon.log"
    else
        echo "No addon pod has been found" > "${cluster_log}_submariner_addon.log"
    fi
}

function gather_cluster_info() {
    local kube_conf
    local cluster_log
    local kubecfg

    for cluster in $MANAGED_CLUSTERS; do
        LOG "Gather information for $cluster cluster"
        kubecfg+="$KCONF/$cluster-kubeconfig.yaml:"
        kube_conf="$KCONF/$cluster-kubeconfig.yaml"
        cluster_log="$DEBUG_LOGS/$cluster"

        get_submariner_pods "$kube_conf" "$cluster_log"
        get_submariner_describe_pods "$kube_conf" "$cluster_log"
        get_cluster_service_version "$kube_conf" "$cluster_log"
        get_icsp "$kube_conf" "$cluster_log"
        get_catalog_source "$kube_conf" "$cluster_log"
        get_package_manifest "$kube_conf" "$cluster_log"
        get_submariner_addon_log "$kube_conf" "$cluster_log"
    done

    KUBECONFIG="${kubecfg%:}"
    export KUBECONFIG
    LOG "Gather logs with subctl gather"
    subctl gather --dir "$DEBUG_LOGS"/ &> "$DEBUG_LOGS"/subctl_gather_state
    unset KUBECONFIG
}

function gather_hub_info() {
    local acm_hub_log="$DEBUG_LOGS/acm_hub"
    local addon_pod_ns
    local addon_pod_name

    LOG "Gather ACM Hub Cluster Deployments state"
    oc get clusterdeployment -A \
        --ignore-not-found > "${acm_hub_log}_cluster_deployment_state"

    LOG "Gather ACM Hub ClusterDeployments details"
    oc get clusterdeployment -A -o yaml \
        --ignore-not-found > "${acm_hub_log}_cluster_deployment.yaml"

    LOG "Gather ACM Hub MultiClusterHub details"
    oc get multiclusterhub -A -o yaml \
        --ignore-not-found > "${acm_hub_log}_multiclusterhub.yaml"

    LOG "Gather ACM Hub Submariner ClusterSet details"
    oc get managedclusterset "$CLUSTERSET" -o yaml \
        --ignore-not-found > "${acm_hub_log}_managed_cluster_set.yaml"

    LOG "Gather ACM Hub Submariner Addon pod log"
    addon_pod_ns=$(oc get pod -A -l app=submariner-addon \
        --no-headers=true -o custom-columns=NAMESPACE:.metadata.namespace)
    addon_pod_name=$(oc get pod -A -l app=submariner-addon \
        --no-headers=true -o custom-columns=NAME:.metadata.name)
    oc -n "$addon_pod_ns" \
        logs "$addon_pod_name" > "${acm_hub_log}_submariner_addon_pod.log" \
        || echo "No logs found for pod $addon_pod" > "${acm_hub_log}_submariner_addon_pod.log"

    for cluster_ns in $MANAGED_CLUSTERS; do
        LOG "Gather ACM Hub SubmarinerConfig for $cluster cluster"
        oc -n "$cluster_ns" get submarinerconfig submariner \
            -o yaml --ignore-not-found > \
            "${acm_hub_log}_${cluster_ns}_submariner_config.yaml"

        LOG "Gather ACM Hub ManagedClusterAddon for $cluster cluster"
        oc -n "$cluster_ns" get managedclusteraddon submariner \
            -o yaml --ignore-not-found > \
            "${acm_hub_log}_${cluster_ns}_managed_cluster_addon.yaml"
    done
}

function gather_debug_info() {
    INFO "Gather debug info from ACM Hub and managed clusters"
    local logs_filename="environment_logs.tar.gz"
    
    rm -rf "$DEBUG_LOGS"
    mkdir -p "$DEBUG_LOGS"

    verify_subctl_command
    gather_hub_info
    gather_cluster_info
    tar -czf "$SUBM_LOGS/$logs_filename" \
        --remove-files -C "$LOGS" "$DEBUG_LOGS"
    INFO "Debug logs have been gathered and stored in -
    $SUBM_LOGS/$logs_filename"
}
