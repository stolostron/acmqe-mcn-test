#!/bin/bash

function create_roks_clusters_list() {
    INFO "Create ROKS clusters list"
    local clusters

    for cluster in $MANAGED_CLUSTERS; do
        product=$(get_cluster_product "$cluster")

        if [[ "$product" == "ROKS" ]]; then
            clusters+="$cluster,"
        fi
    done
    clusters=$(echo "${clusters%,}" | tr "," "\n")
    ROKS_CLUSTERS="$clusters"
}

function enable_calico_api_on_roks_cluster() {
    local timeout
    local wait_timeout=30

    for cluster in $ROKS_CLUSTERS; do
        INFO "Install Calico API on $cluster ROKS cluster"
        KUBECONFIG="$KCONF/$cluster-kubeconfig.yaml" \
            oc apply -f "$SCRIPT_DIR/manifests/tigera_api.yaml"

        tigera_available=""
        tigera_degraded=""
        timeout=0
        until [[ "$timeout" -eq "$wait_timeout" ]]; do
            INFO "Validate Calico API readiness on $cluster ROKS cluster"
            tigera_available=$(KUBECONFIG="$KCONF/$cluster-kubeconfig.yaml" \
                oc get tigerastatus apiserver --ignore-not-found \
                -o jsonpath='{.status.conditions[?(@.type == "Available")].status}')
            tigera_degraded=$(KUBECONFIG="$KCONF/$cluster-kubeconfig.yaml" \
                oc get tigerastatus apiserver --ignore-not-found \
                -o jsonpath='{.status.conditions[?(@.type == "Degraded")].status}')

            if [[ -n "$tigera_available" && "$tigera_available" == "True" ]]; then
                if [[ -n "$tigera_degraded" && "$tigera_degraded" == "False" ]]; then
                    INFO "Calico API has been installed and validated on $cluster ROKS cluster"
                    continue 2
                fi
            fi
            sleep $(( timeout++ ))
        done

        if [[ "$tigera_available" != "True" || "$tigera_degraded" != "False" ]]; then
            ERROR "Calico API was not enabled on $cluster ROKS cluster"
        fi
    done
}

# In order to apply secrets into the roks cluster,
# need to reload the nodes after secret creation.
function reload_roks_cluster_nodes() {
    local timeout
    local wait_timeout=70

    INFO "Reload ROKS cluster workers to apply the created secrets"
    ibmcloud login --apikey "$ROKS_TOKEN" -q

    for cluster in $ROKS_CLUSTERS; do
        INFO "Replacing worker nodes on ROKS cluster $cluster"
        for worker in $(ibmcloud ks worker ls --cluster "$cluster" --output json | jq -r '.[].id'); do
            ibmcloud ks worker replace --cluster "$cluster" --worker "$worker" --update -f
        done
    done

    INFO "Wait for 1 minute to make sure ROKS cluster replacement started"
    sleep 1m

    for cluster in $ROKS_CLUSTERS; do
        INFO "Wait for the worker nodes on ROKS cluster $cluster to get ready"
        worker_actual_state=""
        timeout=0
        until [[ "$timeout" -eq "$wait_timeout" ]]; do
            INFO "Waiting for ROKS $cluster cluster workers to be in 'Deployed' state"
            worker_actual_state=$(ibmcloud ks worker ls --cluster "$cluster" \
                --output json | jq -r '.[].lifecycle.actualState' | uniq)
            worker_actual_state_num=$(echo "$worker_actual_state" | wc -l)

            if [[ "$worker_actual_state_num" == 1 && "$worker_actual_state" == "deployed" ]]; then
                INFO "ROKS $cluster cluster workers state is Deployed"
                break
            fi
            sleep $(( timeout++ ))
        done

        if [[ "$worker_actual_state_num" != 1 || "$worker_actual_state" != "deployed" ]]; then
            ERROR "ROKS $cluster cluster was unable to replace the worker nodes"
        fi

        worker_msg=""
        timeout=0
        until [[ "$timeout" -eq "$wait_timeout" ]]; do
            INFO "Waiting for ROKS $cluster cluster workers to be in 'Ready' message"
            worker_msg=$(ibmcloud ks worker ls --cluster "$cluster" \
                --output json | jq -r '.[].health.message' | uniq)
            worker_msg_num=$(echo "$worker_msg" | wc -l)

            if [[ "$worker_msg_num" == 1 && "$worker_msg" == "Ready" ]]; then
                INFO "ROKS $cluster cluster workers message is Ready"
                break
            fi
            sleep $(( timeout++ ))
        done

        if [[ "$worker_msg_num" != 1 || "$worker_msg" != "Ready" ]]; then
            ERROR "ROKS $cluster cluster was unable to replace the worker nodes"
        fi

        worker_state=""
        timeout=0
        until [[ "$timeout" -eq "$wait_timeout" ]]; do
            INFO "Waiting for ROKS $cluster cluster workers to be in 'Normal' state"
            worker_state=$(ibmcloud ks worker ls --cluster "$cluster" \
                --output json | jq -r '.[].health.state' | uniq)
            worker_state_num=$(echo "$worker_state" | wc -l)

            if [[ "$worker_state_num" == 1 && "$worker_state" == "normal" ]]; then
                INFO "ROKS $cluster cluster workers state is Normal"
                break
            fi
            sleep $(( timeout++ ))
        done

        if [[ "$worker_state_num" != 1 || "$worker_state" != "normal" ]]; then
            ERROR "ROKS $cluster cluster was unable to replace the worker nodes"
        fi

        INFO "ROKS $cluster cluster workers have been replaced"
    done
}

function inset_mirror_to_roks_nodes() {
    INFO "Insert mirror into ROKS cluster nodes"

    mirror=$(cat <<EOF
[[registry]]
  location = \"registry.redhat.io/rhacm2\"
  insecure = false
  blocked  = false
  mirror-by-digest-only = true
  prefix = \"\"

  [[registry.mirror]]
    location = \"brew.registry.redhat.io\"
    insecure = false

[[registry]]
  location = \"registry.stage.redhat.io\"
  insecure = false
  blocked  = false
  mirror-by-digest-only = true
  prefix = \"\"

  [[registry.mirror]]
    location = \"brew.registry.redhat.io\"
    insecure = false

[[registry]]
  location = \"registry-proxy.engineering.redhat.com\"
  insecure = false
  blocked  = false
  mirror-by-digest-only = true
  prefix = \"\"

  [[registry.mirror]]
    location = \"brew.registry.redhat.io\"
    insecure = false
EOF
)

    for cluster in $ROKS_CLUSTERS; do
        local kube_conf="$KCONF/$cluster-kubeconfig.yaml"

        cluster_nodes=$(KUBECONFIG="$kube_conf" oc get nodes \
            --no-headers=true -o custom-columns=NAME:".metadata.name")

        for worker in $cluster_nodes; do
            INFO "Update and reboot node $worker on cluster $cluster"
            KUBECONFIG="$kube_conf" oc debug node/"$worker" -- \
                /bin/sh -c 'echo "'"${mirror}"'" >> /host/etc/containers/registries.conf && echo "Registries updated"'
        done
        for worker in $(ibmcloud ks worker ls --cluster "$cluster" --output json | jq -r '.[].id'); do
            ibmcloud ks worker reboot --cluster "$cluster" --worker "$worker" -f
        done
    done

    check_for_nodes_ready_state
}

function check_for_nodes_ready_state() {
    local nodes_state="ready"
    local nodes_duration="5m"

    # Wait a minute to make sure nodes starts rebooting
    sleep 1m

    for cluster in $ROKS_CLUSTERS; do
        local kube_conf="$KCONF/$cluster-kubeconfig.yaml"

        INFO "Check for the nodes ready state"
        KUBECONFIG="$kube_conf" oc wait nodes --all --for=condition=ready \
            --timeout="$nodes_duration" || nodes_state="down"
        KUBECONFIG="$kube_conf" oc get nodes -o wide
        if [[ "$nodes_state" == "down" ]]; then
          ERROR "Timeout ($nodes_duration) exceeded while waiting for all nodes to be ready on cluster $cluster"
        fi

        INFO "MachineConfig was applied correctly on cluster $cluster"
    done
}
