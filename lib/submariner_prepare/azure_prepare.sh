#!/bin/bash

# Prepare Azure platform.
# The cloud-prepare is yet implemented for azure.
# Prepare steps will be done by "az" cli.

export AZURE_CLUSTERS=""
export AZURE_USER=""
export AZURE_PASS=""
export AZURE_TENANT=""
export AZURE_RESOURCE_GROUP=""
export AZURE_GW_NODE=""
export AZURE_GW_NSG_NAME=""
export GW_NSG_RULES=""

function identify_azure_clusters() {
    INFO "Azure: Identfy Azure clusters"

    AZURE_CLUSTERS=$(oc get clusterdeployment -A \
                      --selector "hive.openshift.io/cluster-platform in (azure)" \
                      -o jsonpath='{range.items[?(@.status.powerState=="Running")]}{.metadata.name}{"\n"}{end}')
    # ACM 2.4.x missing ".status.powerState", which is added in 2.5.x
    # In case first quesry return empty var, execute a different query
    if [[ -z "$AZURE_CLUSTERS" ]]; then
        AZURE_CLUSTERS=$(oc get clusterdeployment -A \
                          --selector "hive.openshift.io/cluster-platform in (azure)" \
                          -o jsonpath='{range.items[?(@.status.conditions[0].reason=="Running")]}{.metadata.name}{"\n"}{end}')
    fi
    INFO "Azure: Found clusters: $AZURE_CLUSTERS"
}

function fetch_azure_cluster_cloud_creds() {
    local cluster="$1"
    local creds_name
    local creds_details
    INFO "Azure: Fetch Azure cloud credentials for cluster $cluster"

    creds_name=$(get_cluster_credential_name "$cluster")
    creds_details=$(oc -n "$cluster" get secret "$creds_name" \
                        --template='{{index .data "osServicePrincipal.json" | base64decode}}')

    if [[ -z $creds_details ]]; then
        ERROR "Azure: Unable to fetch azure cloud credentials"
    fi

    INFO "Azure: Setting credentials variables"
    AZURE_USER=$(echo "$creds_details" | jq -r '.clientId')
    AZURE_PASS=$(echo "$creds_details" | jq -r '.clientSecret')
    AZURE_TENANT=$(echo "$creds_details" | jq -r '.tenantId')
}

function login_to_azure_cloud() {
    INFO "Azure: Login to Azure cloud"
    local login_state

    login_state=$(az login --service-principal \
                    --username "$AZURE_USER" \
                    --password "$AZURE_PASS" \
                    --tenant "$AZURE_TENANT" || false)

    if [[ "$login_state" == "false" ]]; then
        ERROR "Azure: Login to the cloud failed"
    fi
}

function fetch_resource_group_name() {
    INFO "Azure: Fetch resource group name of the resources"
    local cluster_name="$1"
    local cluster_infra_id

    cluster_infra_id=$(oc -n "$cluster_name" get clusterdeployment \
        "$cluster_name" -o jsonpath='{.spec.clusterMetadata.infraID}')
    AZURE_RESOURCE_GROUP=$(az group list \
                            --query "[?starts_with(name, '""$cluster_infra_id""')].name" \
                            -o tsv)
    INFO "Azure: Resource group is - $AZURE_RESOURCE_GROUP"
}

function label_worker_for_gateway() {
    INFO "Azure: Select and label worker as a gateway node"
    local cluster="$1"
    local kube_conf="$KCONF/$cluster-kubeconfig.yaml"

    AZURE_GW_NODE=$(KUBECONFIG="$kube_conf" oc get nodes \
                     --selector "node-role.kubernetes.io/worker" \
                     -o jsonpath='{.items[0].metadata.name}')
    KUBECONFIG="$kube_conf" oc label nodes "$AZURE_GW_NODE" \
        "submariner.io/gateway=true" --overwrite
    INFO "Azure: Selected $AZURE_GW_NODE to be used for cluster $cluster"
}

function create_and_attach_external_ip_to_gateway() {
    INFO "Azure: Create and attach external ip for gateway node"
    local public_ip_name="submariner-public-name"

    az network public-ip create --name "$public_ip_name" \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --sku Standard --output none
    az network nic ip-config update --name pipConfig \
        --nic-name "$AZURE_GW_NODE"-nic \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --public-ip-address "$public_ip_name" \
        --output none
}

function create_nsg_and_rules_for_gateway() {
    INFO "Azure: Create Network Security Group with rules for gateway node"
    local cluster="$1"
    AZURE_GW_NSG_NAME="submariner-gw-nsg-$cluster"
    
    INFO "Azure: Create network security group"
    az network nsg create --name "$AZURE_GW_NSG_NAME" \
        --resource-group "$AZURE_RESOURCE_GROUP" --output none

    # The parameters below could not be changed
    # so no need to provide them as global parameters
    local submariner_vxlan_port=4800
    local submariner_metrics_port=8080
    local submariner_nat_discovery_port=4490

    # Declare associative arrays
    declare -A RULE_1=(
        [dest_port]="$SUBMARINER_IPSEC_NATT_PORT"
        [direction]='Inbound'
        [protocol]='Udp'
        [rule_priority]=3500
    )
    export RULE_1
    declare -A RULE_2=(
        [dest_port]="$SUBMARINER_IPSEC_NATT_PORT"
        [direction]='Outbound'
        [protocol]='Udp'
        [rule_priority]=3501
    )
    export RULE_2
    declare -A RULE_3=(
        [dest_port]="$submariner_vxlan_port"
        [direction]='Inbound'
        [protocol]='Udp'
        [rule_priority]=3502
    )
    export RULE_3
    declare -A RULE_4=(
        [dest_port]="$submariner_vxlan_port"
        [direction]='Outbound'
        [protocol]='Udp'
        [rule_priority]=3503
    )
    export RULE_4
    declare -A RULE_5=(
        [dest_port]="$submariner_metrics_port"
        [direction]='Inbound'
        [protocol]='Tcp'
        [rule_priority]=3504
    )
    export RULE_5
    declare -A RULE_6=(
        [dest_port]="$submariner_metrics_port"
        [direction]='Outbound'
        [protocol]='Tcp'
        [rule_priority]=3505
    )
    export RULE_6
    declare -A RULE_7=(
        [dest_port]="$submariner_nat_discovery_port"
        [direction]='Inbound'
        [protocol]='Udp'
        [rule_priority]=3506
    )
    export RULE_7
    declare -A RULE_8=(
        [dest_port]="$submariner_nat_discovery_port"
        [direction]='Outbound'
        [protocol]='Udp'
        [rule_priority]=3507
    )
    export RULE_8
    declare -A RULE_9=(
        [dest_port]="0-0"
        [direction]='Inbound'
        [protocol]='Ah'  # Authentication Header (AH)
        [rule_priority]=3508
    )
    export RULE_9
    declare -A RULE_10=(
        [dest_port]="0-0"
        [direction]='Outbound'
        [protocol]='Ah'  # Authentication Header (AH)
        [rule_priority]=3509
    )
    export RULE_10
    declare -A RULE_11=(
        [dest_port]="0-0"
        [direction]='Inbound'
        [protocol]='Esp'  # Encapsulated Security Payload (ESP)
        [rule_priority]=3510
    )
    export RULE_11
    declare -A RULE_12=(
        [dest_port]="0-0"
        [direction]='Outbound'
        [protocol]='Esp'  # Encapsulated Security Payload (ESP)
        [rule_priority]=3511
    )
    export RULE_12
    # Declare array of GW_NSG_RULES of associative arrays
    export GW_NSG_RULES=("${!RULE@}")

    INFO "Azure: Create network security group rules"
    declare -n nsg_rule
    for nsg_rule in "${GW_NSG_RULES[@]}"; do
        INFO "Azure: Creating rule:
        NSG: $AZURE_GW_NSG_NAME
        Rule: submariner-gw-nsg-${nsg_rule[direction]}-${nsg_rule[protocol]}-${nsg_rule[dest_port]}
        Destination port: ${nsg_rule[dest_port]}
        Protocol: ${nsg_rule[protocol]}
        Direction: ${nsg_rule[direction]}
        Priority: ${nsg_rule[rule_priority]}
        Access: Allow"

        az network nsg rule create \
            --resource-group "$AZURE_RESOURCE_GROUP" \
            --nsg-name "$AZURE_GW_NSG_NAME" \
            --name submariner-gw-nsg-"${nsg_rule[direction]}"-"${nsg_rule[protocol]}"-"${nsg_rule[dest_port]}" \
            --destination-port-ranges "${nsg_rule[dest_port]}" \
            --protocol "${nsg_rule[protocol]}" \
            --direction "${nsg_rule[direction]}" \
            --priority "${nsg_rule[rule_priority]}" \
            --access Allow \
            --output none
    done
}

function attach_nsg_to_gateway_node() {
    INFO "Azure: Attach Network Security Group to the gateway node"
    local cluster="$1"
    local gw_nsg_name="submariner-gw-nsg-$cluster"

    az network nic update \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --name "$AZURE_GW_NODE"-nic \
        --network-security-group "$gw_nsg_name" \
        --output none
}

function update_ocp_nodes_security_group() {
    INFO "Azure: Update master and worker nodes security group to open 4800 udp port"
    local shared_nsg
    # The parameter below could not be changed
    # so no need to provide it as global parameter
    local submariner_vxlan_port=4800
    local rule_priority=2500

    # Fetch network security groups of the resource group:
    shared_nsg=$(az network nsg list \
                  --resource-group "$AZURE_RESOURCE_GROUP" \
                  --query "[?name!='""$AZURE_GW_NSG_NAME""'].name" \
                  -o tsv | head -n 1)

    for rule in Inbound Outbound; do
        az network nsg rule create \
            --resource-group "$AZURE_RESOURCE_GROUP" \
            --nsg-name "$shared_nsg" \
            --name submariner-internal-"$rule"-udp-"$submariner_vxlan_port" \
            --destination-port-ranges 4800 \
            --protocol Udp \
            --direction "$rule" \
            --priority "$rule_priority" \
            --access Allow \
            --output none

        (( rule_priority++ ))
    done
}

function prepare_azure_cloud() {
    INFO "Azure: Prepare cloud"

    identify_azure_clusters
    for cluster in $AZURE_CLUSTERS; do
        INFO "Azure: Prepare cloud for cluster $cluster"
        fetch_azure_cluster_cloud_creds "$cluster"
        login_to_azure_cloud
        fetch_resource_group_name "$cluster"
        label_worker_for_gateway "$cluster"
        create_and_attach_external_ip_to_gateway
        create_nsg_and_rules_for_gateway "$cluster"
        attach_nsg_to_gateway_node "$cluster"
        update_ocp_nodes_security_group
        INFO "Azure: Prepare cloud for cluster $cluster is done"
    done
}
