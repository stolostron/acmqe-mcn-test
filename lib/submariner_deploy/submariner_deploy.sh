#!/bin/bash

# Deploy Submariner addon on the clusterset managed clusters

# Prepare configuration for managed clusters.
# Create "gateway" instance and open required ports.
function prepare_clusters_for_submariner() {
    INFO "Perform Submariner cloud prepare for the managed clusters"
    local creds
    local submariner_channel
    local catalog_ns="openshift-marketplace"
    local catalog_source="redhat-operators"

    submariner_channel="$SUBMARINER_CHANNEL_RELEASE-$(echo "$SUBMARINER_VERSION_INSTALL" | grep -Po '.*(?=\.)')"

    if [[ "$DOWNSTREAM" == 'true' ]]; then
        catalog_source="submariner-catalog"
    fi

    if [[ "$SUBMARINER_GATEWAY_RANDOM" == "true" ]]; then
        SUBMARINER_GATEWAY_COUNT=2
    fi

    for cluster in $MANAGED_CLUSTERS; do
        creds=$(get_cluster_credential_name "$cluster")
        product=$(get_cluster_product "$cluster")
        # The ARO / ROSA cluster does not need cloud credentials
        # The ARO / ROSA cluster should use "loadBalancerEnable: true"
        local load_balancer="false"
        if [[ "$product" =~ ("ARO"|"ROSA") ]]; then
            creds="null"
            load_balancer="true"
        fi

        INFO "Using $creds credentials for $cluster cluster"
        INFO "Apply SubmarinerConfig on cluster $cluster"
        INFO "Use $SUBMARINER_GATEWAY_COUNT gateway node for $cluster cluster"

        CL="$cluster" CRED="$creds" SUBM_CHAN="$submariner_channel" \
            NS="$catalog_ns" SUBM_SOURCE="$catalog_source" LB="$load_balancer" \
            yq eval '.metadata.namespace = env(CL)
            | .spec.credentialsSecret.name = env(CRED)
            | .spec.IPSecNATTPort = env(SUBMARINER_IPSEC_NATT_PORT)
            | .spec.cableDriver = env(SUBMARINER_CABLE_DRIVER)
            | .spec.loadBalancerEnable = env(LB)
            | .spec.gatewayConfig.gateways = env(SUBMARINER_GATEWAY_COUNT)
            | .spec.subscriptionConfig.channel = env(SUBM_CHAN)
            | .spec.subscriptionConfig.source = env(SUBM_SOURCE)
            | .spec.subscriptionConfig.sourceNamespace = env(NS)' \
            "$SCRIPT_DIR/manifests/submariner-config.yaml" | oc apply -f -

        if [[ "$SUBMARINER_GATEWAY_RANDOM" == "true" ]]; then
            SUBMARINER_GATEWAY_COUNT=1
        fi

        if [[ "$product" == "ROSA" ]]; then
            deploy_gw_node_for_rosa "$cluster"
        fi
    done
}

# Deploying GW node for ROSA cluster should
# be done by using "rosa" binary.
function deploy_gw_node_for_rosa() {
    INFO "Deploy Gateway node for ROSA cluster"
    local cluster="$1"
    local machinepool_name="sm-gw-mp"
    local machinepool_state

    rosa login --token "$ROSA_TOKEN"
    machinepool_state=$(rosa list machinepool --cluster "$cluster" -o json \
        | jq -r '.[] | select(.id | contains("'"$machinepool_name"'")).id')

    # Until https://issues.redhat.com/browse/ACM-2494 is fixed,
    # create 3 machinepool replicas.
    if [[ "$machinepool_state" == "" ]]; then
        rosa create machinepool --cluster="$cluster" \
            --name="$machinepool_name" --replicas=3 --labels='submariner.io/gateway=true'
    fi
}

function deploy_submariner_broker() {
    INFO "Deploy Submariner broker"
    INFO "The Globalnet conditiona has been set to - $SUBMARINER_GLOBALNET"
    local broker_ns="$CLUSTERSET-broker"

    NS="$broker_ns" yq eval '.metadata.namespace = env(NS)
        | .spec.globalnetEnabled = env(SUBMARINER_GLOBALNET)' \
        "$SCRIPT_DIR/manifests/broker.yaml" | oc apply -f -
}

function deploy_submariner_addon() {
    INFO "Perform deployment of Submariner addon"

    for cluster in $MANAGED_CLUSTERS; do
        INFO "Deploy Submariner addon on cluster - $cluster"

        CL="$cluster" yq eval '.metadata.namespace = env(CL)' \
            "$SCRIPT_DIR/manifests/submariner-addon.yaml" | oc apply -f -
    done
}

# The function will check the Submariner addon deployment state
# based on the gived condition value.
# The function will get two arguments:
# 1 - namespace of the managed cluster
# 2 - condition that needs to be checked
function check_submariner_deployment_state() {
    local namespace
    local condition

    namespace=$1
    condition=$2

    oc get managedclusteraddons/submariner -n "$namespace" \
        -o jsonpath='{.status.conditions[?(@.type == "'"$condition"'")].reason}'
}

# The function will wait and check the state of the Submariner services.
# The following services are checked:
# - Submariner Gateway node
# - Submariner Agent
# - Submariner cross cluster connectivity
function wait_for_submariner_ready_state() {
    INFO "Wait for Submariner ready status"
    local wait_timeout=50
    local timeout
    local cmd_output

    INFO "Check Submariner Gateway node state on clusters"
    for cluster in $MANAGED_CLUSTERS; do
        INFO "Checking Submariner Gateway node state on $cluster cluster"
        timeout=0
        cmd_output=""
        until [[ "$timeout" -eq "$wait_timeout" ]] || [[ "$cmd_output" == "SubmarinerGatewayNodesLabeled" ]]; do
            INFO "Deploying..."
            cmd_output=$(check_submariner_deployment_state "$cluster" "SubmarinerGatewayNodesLabeled")
            sleep $(( timeout++ ))
        done

        if [[ "$cmd_output" != "SubmarinerGatewayNodesLabeled" ]]; then
            ERROR "The Submariner Gateway node is not labeled - $cmd_output"
        fi
        INFO "Submariner Gateway node has been deployed on $cluster cluster"
    done
    INFO "Submariner Gateway node has been sucesfully deployed on each cluster"

    INFO "Check Submariner Agent state on clusters"
    for cluster in $MANAGED_CLUSTERS; do
        INFO "Checking Submariner Agent state on $cluster cluster"
        timeout=0
        cmd_output=""
        until [[ "$timeout" -eq "$wait_timeout" ]] || [[ "$cmd_output" == "SubmarinerAgentDeployed" ]]; do
            INFO "Deploying..."
            cmd_output=$(check_submariner_deployment_state "$cluster" "SubmarinerAgentDegraded")
            sleep $(( timeout++ ))
        done

        if [[ "$cmd_output" != "SubmarinerAgentDeployed" ]]; then
            ERROR "The Submariner Agent state is not ready - $cmd_output"
        fi
        INFO "Submariner Agent has been deployed on $cluster cluster"
    done
    INFO "Submariner Agent has been sucesfully deployed on each cluster"

    INFO "Check Submariner connectivity between clusters"
    for cluster in $MANAGED_CLUSTERS; do
        INFO "Checking Submariner connectivity on $cluster cluster"
        timeout=0
        cmd_output=""
        until [[ "$timeout" -eq "$wait_timeout" ]] || [[ "$cmd_output" == "ConnectionsEstablished" ]]; do
            INFO "Deploying..."
            cmd_output=$(check_submariner_deployment_state "$cluster" "SubmarinerConnectionDegraded")
            sleep $(( timeout++ ))
        done

        if [[ "$cmd_output" != "ConnectionsEstablished" ]]; then
            ERROR "The Submariner connectivity is not ready - $cmd_output"
        fi
        INFO "Submariner connectivity has been established on $cluster cluster"
    done
    INFO "Submariner connectivity have been successfully established between clusters"
    INFO "All Submariner services successfully running on the clusters"
}
