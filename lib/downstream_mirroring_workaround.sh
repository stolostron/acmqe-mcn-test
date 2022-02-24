#!/bin/bash

# Current implementation of the downstream deployment requires us
# to set the mirroring from the MachineConfig manifest.
# This is done due to the following state:
# Downstream deployment is using the "brew.registry.redhat.io" registry.
# Container images are using two ways to specify an image:
#  - floating tags - Version number ("0.11.2"). Does not represent exact image.
#  - digest - Hash string that represent exact image.
# The new standard is to use digest only.
# The brew registry does not support "floating tags", only "digest".
# As a result, until other solution, there is a need to configure mirroring on
# the nodes via the "MachineConfig" manifest, because there is a parameter -
# "mirror-by-digest-only = false", which allows to specify floating tags.
# After setting the mirroring, the images needs to be imported into ocp
# internal registry. And those images will be used during the deployment.
# https://issues.redhat.com/browse/RFE-1608

function create_internal_registry_secret() {
    INFO "Create internal ocp registry secret"

    local ocp_token
    local ocp_registry_url
    local reg_username="kubeadmin"

    for cluster in $MANAGED_CLUSTERS; do
        INFO "Create internal regsitry secret on $cluster cluster"
        local kube_conf="$TESTS_LOGS/$cluster-kubeconfig.yaml"

        ocp_token=$(get_cluster_token "$cluster")
        ocp_registry_url=$(oc registry info --internal)

        INFO "Create internal registry secret in globally available namespace"
        INFO "Create internal registry secret to be reachable for the catalog source"
        for namespace in 'openshift-config' 'openshift-marketplace' $SUBMARINER_NS; do
            KUBECONFIG="$kube_conf" oc -n "$namespace" delete secret \
                internal-registry --ignore-not-found=true

            KUBECONFIG="$kube_conf" oc create secret docker-registry \
                -n "$namespace" internal-registry \
                --docker-server="$ocp_registry_url" \
                --docker-username="$reg_username" \
                --docker-password="$ocp_token"
        done

        INFO "Update the cluster global pull-secret"
        KUBECONFIG="$kube_conf" oc patch secret pull-secret -n openshift-config \
            -p '{"data":{".dockerconfigjson":"'"$(KUBECONFIG="$kube_conf" oc get \
            secret pull-secret -n openshift-config \
            --output="jsonpath={.data.\.dockerconfigjson}" | base64 --decode \
            | jq -r -c '.auths |= . + '"$(KUBECONFIG="$kube_conf" oc get secret \
            internal-registry -n openshift-config \
            --output="jsonpath={.data.\.dockerconfigjson}" | base64 --decode \
            | jq -r -c '.auths')"'' | base64 -w 0)"'"}}'
    done
    INFO "Internal secret has been updated on all managed clusters"
}

function create_namespace() {
    for cluster in $MANAGED_CLUSTERS; do
        INFO "Create $SUBMARINER_NS namespace on cluster $cluster"
        local kube_conf="$TESTS_LOGS/$cluster-kubeconfig.yaml"

        NS="$SUBMARINER_NS" yq eval '.metadata.name = env(NS)' \
            "$SCRIPT_DIR/resources/namespace.yaml" \
            | KUBECONFIG="$kube_conf" oc apply -f -
    done
}

function add_custom_registry_to_node() {
    # could be "master" or "worker"
    local node="$1"
    local local_registry_path="$2"
    local config_source

    if [[ -z "$local_registry_path" ]] || [[ ! "$node" =~ ^(master|worker)$ ]]; then
        ERROR "Openshift Registry values are missing: node or registry path"
    else
        INFO "Add the custom registry to $node node:
        * ${OFFICIAL_REGISTRY}/${REGISTRY_IMAGE_PREFIX} -->
            - ${local_registry_path}
            - ${BREW_REGISTRY}/${REGISTRY_IMAGE_PREFIX}
        * ${STAGING_REGISTRY}/${REGISTRY_IMAGE_PREFIX} -->
            - ${local_registry_path}
            - ${BREW_REGISTRY}/${REGISTRY_IMAGE_PREFIX}
        * ${VPN_REGISTRY} -->
            - ${BREW_REGISTRY}
        * ${OFFICIAL_REGISTRY}/${REGISTRY_IMAGE_PREFIX_TECH_PREVIEW} -->
            - ${local_registry_path}
            - ${BREW_REGISTRY}/${REGISTRY_IMAGE_IMPORT_PATH}/${REGISTRY_IMAGE_PREFIX_TECH_PREVIEW}
        * ${STAGING_REGISTRY}/${REGISTRY_IMAGE_PREFIX_TECH_PREVIEW} -->
            - ${local_registry_path}
            - ${BREW_REGISTRY}/${REGISTRY_IMAGE_IMPORT_PATH}/${REGISTRY_IMAGE_PREFIX_TECH_PREVIEW}
        * ${CATALOG_REGISTRY}/${CATALOG_IMAGE_PREFIX}/${CATALOG_IMAGE_IMPORT_PATH} -->
            - ${OFFICIAL_REGISTRY}/${CATALOG_IMAGE_PREFIX}/${CATALOG_IMAGE_IMPORT_PATH}
        "
    fi

    config_source=$(cat <<EOF | raw_to_url_encode
    [[registry]]
      prefix = ""
      location = "${OFFICIAL_REGISTRY}/${REGISTRY_IMAGE_PREFIX}"
      mirror-by-digest-only = false
      insecure = false
      blocked = false

      [[registry.mirror]]
        location = "${local_registry_path}"
        insecure = false

      [[registry.mirror]]
        location = "${BREW_REGISTRY}/${REGISTRY_IMAGE_PREFIX}"
        insecure = false

    [[registry]]
      prefix = ""
      location = "${STAGING_REGISTRY}/${REGISTRY_IMAGE_PREFIX}"
      mirror-by-digest-only = false
      insecure = false
      blocked = false

      [[registry.mirror]]
        location = "${local_registry_path}"
        insecure = false

      [[registry.mirror]]
        location = "${BREW_REGISTRY}/${REGISTRY_IMAGE_PREFIX}"
        insecure = false

    [[registry]]
      prefix = ""
      location = "${VPN_REGISTRY}"
      mirror-by-digest-only = false
      insecure = false
      blocked = false

      [[registry.mirror]]
        location = "${BREW_REGISTRY}"
        insecure = false

    [[registry]]
      prefix = ""
      location = "${OFFICIAL_REGISTRY}/${REGISTRY_IMAGE_PREFIX_TECH_PREVIEW}"
      mirror-by-digest-only = false
      insecure = false
      blocked = false

      [[registry.mirror]]
        location = "${local_registry_path}"
        insecure = false

      [[registry.mirror]]
        location = "${BREW_REGISTRY}/${REGISTRY_IMAGE_IMPORT_PATH}/${REGISTRY_IMAGE_PREFIX_TECH_PREVIEW}"
        insecure = false

    [[registry]]
      prefix = ""
      location = "${STAGING_REGISTRY}/${REGISTRY_IMAGE_PREFIX_TECH_PREVIEW}"
      mirror-by-digest-only = false
      insecure = false
      blocked = false

      [[registry.mirror]]
        location = "${local_registry_path}"
        insecure = false

      [[registry.mirror]]
        location = "${BREW_REGISTRY}/${REGISTRY_IMAGE_IMPORT_PATH}/${REGISTRY_IMAGE_PREFIX_TECH_PREVIEW}"
        insecure = false

      [[registry]]
        prefix = ""
        location = "${CATALOG_REGISTRY}/${CATALOG_IMAGE_PREFIX}/${CATALOG_IMAGE_IMPORT_PATH}"
        mirror-by-digest-only = true
        insecure = false
        blocked = false

        [[registry.mirror]]
          location = "${OFFICIAL_REGISTRY}/${CATALOG_IMAGE_PREFIX}/${CATALOG_IMAGE_IMPORT_PATH}"
          insecure = false
EOF
    )

    for cluster in $MANAGED_CLUSTERS; do
        local ocp_version
        local kube_conf="$TESTS_LOGS/$cluster-kubeconfig.yaml"

        INFO "Enable auto-reboot of $node node when changing Machine Config Pool on cluster $cluster"
        KUBECONFIG="$kube_conf" oc patch --type=merge \
            --patch='{"spec":{"paused":false}}' machineconfigpool/"$node"

        INFO "Check OCP and ignition versions"
        ocp_version=$(KUBECONFIG="$kube_conf" oc version | awk '/Server Version/ { print $3 }')
        ignition_version=$(KUBECONFIG="$kube_conf" oc -n openshift-machine-api \
                           get secret worker-user-data \
                           --template='{{index .data.userData | base64decode}}' \
                           | yq eval '.ignition.version' -)
        INFO "Cluster $cluster - version: $ocp_version, ignition version: $ignition_version"
        INFO "Apply custom registry using MachineConfig on cluster $cluster"
        NODE="$node" IGNITION="$ignition_version" \
            CONFIG_NAME="99-$node-submariner-registries" \
            CONFIG_SOURCE="data:text/plan,$config_source" \
            yq eval '.metadata.labels."machineconfiguration.openshift.io/role" = env(NODE)
            | .metadata.name = env(CONFIG_NAME)
            | .spec.config.ignition.version = env(IGNITION)
            | .spec.config.storage.files[].contents.source = env(CONFIG_SOURCE)' \
            "$SCRIPT_DIR/resources/machine_config.yaml" \
            | KUBECONFIG="$kube_conf" oc apply -f -
    done
}

function check_for_nodes_ready_state() {
    local nodes_state="ready"
    local nodes_duration="5m"
    local machine_state="ready"
    local machine_duration="20m"

    for cluster in $MANAGED_CLUSTERS; do
        local kube_conf="$TESTS_LOGS/$cluster-kubeconfig.yaml"

        INFO "Check for the nodes ready state"
        KUBECONFIG="$kube_conf" oc wait nodes --all --for=condition=ready \
            --timeout="$nodes_duration" || nodes_state="down"
        KUBECONFIG="$kube_conf" oc get nodes -o wide
        if [[ "$nodes_state" == "down" ]]; then
          ERROR "Timeout ($nodes_duration) exceeded while waiting for all nodes to be ready on cluster $cluster"
        fi

        INFO "Check for Machine Config Daemon to be rolled out by openshift-machine-config-operator"
        KUBECONFIG="$kube_conf" oc -n openshift-machine-config-operator rollout status \
            daemonset machine-config-daemon --timeout="$machine_duration" || machine_state="down"

        INFO "Check for Machine Config Pool to be updated"
        KUBECONFIG="$kube_conf" oc wait machineconfigpool --all --for=condition=updated \
            --timeout="$machine_duration" || machine_state="down"

        INFO "Check for Machine Config Pool ready state"
        for node in "master" "worker"; do
            KUBECONFIG="$kube_conf" oc wait machineconfigpool "$node" \
                --for=condition=Degraded=False \
                --timeout="$machine_duration" || machine_state="down"
        done

        if [[ "$machine_state" == "down" ]]; then
          ERROR "Timeout exceeded while waiting for Machine Config to be ready on cluster $cluster"
        fi
        INFO "MachineConfig was applied correctly on cluster $cluster"
    done
}

function verify_custom_registry_on_nodes() {
    INFO "Verify custom registry applied properly on the nodes"
    
    for cluster in $MANAGED_CLUSTERS; do
        INFO "Verify custom registry existence on cluster $cluster"
        local kube_conf="$TESTS_LOGS/$cluster-kubeconfig.yaml"

        for node in "master" "worker"; do
            local config_name="99-$node-submariner-registries"
            local state=""

            state=$(KUBECONFIG="$kube_conf" \
                oc get machineconfig "$config_name" \
                -o jsonpath='{.spec.config.storage.files[*].contents.source}' \
                | cut -d ',' -f2)

            if [[ -z "$state" ]]; then
                ERROR "Custom registry was not applied correctly in node $node on cluster $cluster"
            fi
            INFO "Custom registry was applied correctly in node $node on cluster $cluster"
        done
    done
}

function set_custom_registry_mirror() {
    INFO "Set custom registry mirror on the nodes by using MachineConfig"
    local ocp_registry_url
    local ocp_registry_path

    create_internal_registry_secret

    ocp_registry_url=$(oc registry info --internal)
    ocp_registry_path="$ocp_registry_url/$SUBMARINER_NS"

    add_custom_registry_to_node "master" "$ocp_registry_path"
    add_custom_registry_to_node "worker" "$ocp_registry_path"

    check_for_nodes_ready_state
    verify_custom_registry_on_nodes
}

function import_images_into_local_registry() {
    INFO "Import images into local cluster registry"
    local import_state
    local ocp_registry_url
    local ocp_registry_path

    for cluster in $MANAGED_CLUSTERS; do
        local kube_conf="$TESTS_LOGS/$cluster-kubeconfig.yaml"

        INFO "Disable the default remote OperatorHub sources for OLM"
        KUBECONFIG="$kube_conf" oc patch OperatorHub cluster --type json \
            -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]'

        INFO "Import Submariner images into cluster $cluster"
        for image in \
          $SUBM_IMG_BUNDLE \
          $SUBM_IMG_OPERATOR \
          $SUBM_IMG_GATEWAY \
          $SUBM_IMG_ROUTE \
          $SUBM_IMG_NETWORK \
          $SUBM_IMG_LIGHTHOUSE \
          $SUBM_IMG_COREDNS \
          $SUBM_IMG_GLOBALNET \
          ; do
            local img_src="$BREW_REGISTRY/$REGISTRY_IMAGE_IMPORT_PATH/$REGISTRY_IMAGE_PREFIX_TECH_PREVIEW-$image:v$SUBMARINER_VERSION_INSTALL"
            import_state=$(KUBECONFIG="$kube_conf" oc -n "$SUBMARINER_NS" import-image \
                "$image:v$SUBMARINER_VERSION_INSTALL" --from="$img_src" --confirm 2>&1) || true

            if [[ "$import_state" =~ ("Import failed"|"error") ]]; then
                ERROR "Image import failed.
                $import_state"
            fi
            INFO "Imported image - $image:v$SUBMARINER_VERSION_INSTALL"
        done

        INFO "Import Submariner image index bundle into local registry"
        if [[ -n "$LATEST_IIB" ]]; then
            INFO "Detected IIB - $LATEST_IIB"
        else
            get_latest_iib
        fi
        ocp_registry_url=$(oc registry info --internal)
        ocp_registry_path="$ocp_registry_url/$SUBMARINER_NS/$SUBM_IMG_BUNDLE-index:v$SUBMARINER_VERSION_INSTALL"

        import_state=$(KUBECONFIG="$kube_conf" oc -n "$SUBMARINER_NS" import-image \
            "$ocp_registry_path" --from="$LATEST_IIB" --confirm 2>&1) || true

        if [[ "$import_state" =~ ("Import failed"|"error") ]]; then
            ERROR "Image import failed.
            $import_state"
        fi
        INFO "Imported image - $SUBM_IMG_BUNDLE-index:v$SUBMARINER_VERSION_INSTALL"
    done
}
