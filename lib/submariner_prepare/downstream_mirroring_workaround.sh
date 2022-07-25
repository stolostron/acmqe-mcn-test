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

function create_service_account_for_internal_registry() {
    local cluster="$1"
    local kube_conf="$LOGS/$cluster-kubeconfig.yaml"
    local sa_name="$2"

    INFO "Create Service Account on $cluster cluster"
    SA="$sa_name" NS="$SUBMARINER_NS" yq eval \
        'with(.metadata; .name = env(SA) | .namespace = env(NS))' \
        "$SCRIPT_DIR/manifests/service-account.yaml" \
        | KUBECONFIG="$kube_conf" oc apply -f -

    INFO "Create RoleBinding for SA on $cluster cluster"
    SA="$sa_name" NS="$SUBMARINER_NS" yq eval \
        'with(.metadata; .name = env(SA)
        | .namespace = env(SUBMARINER_NS))
        | with(.subjects[]; .name = env(SA)
        | .namespace = env(SUBMARINER_NS))' \
        "$SCRIPT_DIR/manifests/service-account-role-config.yaml" \
        | KUBECONFIG="$kube_conf" oc apply -f -
}

function create_internal_registry_secret() {
    INFO "Create internal ocp registry secret"
    local ocp_registry_url
    local sa_secret_name
    local sa_name="submariner-registry-sa"

    for cluster in $MANAGED_CLUSTERS; do
        INFO "Create internal regsitry secret on $cluster cluster"
        local kube_conf="$LOGS/$cluster-kubeconfig.yaml"

        ocp_registry_url=$(KUBECONFIG="$kube_conf" oc registry info --internal)
        create_service_account_for_internal_registry "$cluster" "$sa_name"

        sa_secret_name=$(KUBECONFIG="$kube_conf" \
            oc -n "$SUBMARINER_NS" get sa "$sa_name" -o json \
            | jq -r '.secrets[] | select(.name | contains("dockercfg")).name')

        INFO "Update the cluster global pull-secret"
        KUBECONFIG="$kube_conf" oc patch secret pull-secret -n openshift-config \
            -p '{"data":{".dockerconfigjson":"'"$(KUBECONFIG="$kube_conf" oc get \
            secret pull-secret -n openshift-config \
            --output="jsonpath={.data.\.dockerconfigjson}" | base64 --decode \
            | jq -r -c '.auths |= . + '"$(KUBECONFIG="$kube_conf" oc get secret \
            "$sa_secret_name" -n "$SUBMARINER_NS" \
            --output="jsonpath={.data.\.dockercfg}" | base64 --decode)"'' \
            | base64 -w 0)"'"}}'
    done
    INFO "Internal secret has been updated on all managed clusters"
}

function create_namespace() {
    for cluster in $MANAGED_CLUSTERS; do
        INFO "Create $SUBMARINER_NS namespace on cluster $cluster"
        local kube_conf="$LOGS/$cluster-kubeconfig.yaml"

        NS="$SUBMARINER_NS" yq eval '.metadata.name = env(NS)' \
            "$SCRIPT_DIR/manifests/namespace.yaml" \
            | KUBECONFIG="$kube_conf" oc apply -f -
    done
}

function add_custom_registry_to_node() {
    # could be "master" or "worker"
    local node="$1"
    local ocp_registry_url
    local local_registry_path
    local config_source
    local submariner_ga="0.12.0"
    local registry_image_prefix_path
    version_state=$(validate_version "$submariner_ga" "$SUBMARINER_VERSION_INSTALL")

    if [[ "$version_state" == "valid" ]]; then
        export registry_image_prefix_path="${REGISTRY_IMAGE_PREFIX}"
    elif [[ "$version_state" == "not_valid" ]]; then
        export registry_image_prefix_path="${REGISTRY_IMAGE_PREFIX_TECH_PREVIEW}"
    fi

    for cluster in $MANAGED_CLUSTERS; do
        local ocp_version
        local kube_conf="$LOGS/$cluster-kubeconfig.yaml"

        ocp_registry_url=$(KUBECONFIG="$kube_conf" oc registry info --internal)
        local_registry_path="$ocp_registry_url/openshift"

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
            * ${OFFICIAL_REGISTRY}/${registry_image_prefix_path} -->
                - ${local_registry_path}
                - ${BREW_REGISTRY}/${REGISTRY_IMAGE_IMPORT_PATH}/${registry_image_prefix_path}
            * ${STAGING_REGISTRY}/${registry_image_prefix_path} -->
                - ${local_registry_path}
                - ${BREW_REGISTRY}/${REGISTRY_IMAGE_IMPORT_PATH}/${registry_image_prefix_path}
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
          location = "${OFFICIAL_REGISTRY}/${registry_image_prefix_path}"
          mirror-by-digest-only = false
          insecure = false
          blocked = false

          [[registry.mirror]]
            location = "${local_registry_path}"
            insecure = false

          [[registry.mirror]]
            location = "${BREW_REGISTRY}/${REGISTRY_IMAGE_IMPORT_PATH}/${registry_image_prefix_path}"
            insecure = false

        [[registry]]
          prefix = ""
          location = "${STAGING_REGISTRY}/${registry_image_prefix_path}"
          mirror-by-digest-only = false
          insecure = false
          blocked = false

          [[registry.mirror]]
            location = "${local_registry_path}"
            insecure = false

          [[registry.mirror]]
            location = "${BREW_REGISTRY}/${REGISTRY_IMAGE_IMPORT_PATH}/${registry_image_prefix_path}"
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
            "$SCRIPT_DIR/manifests/machine_config.yaml" \
            | KUBECONFIG="$kube_conf" oc apply -f -
    done
}

function check_for_nodes_ready_state() {
    local nodes_state="ready"
    local nodes_duration="5m"
    local machine_state="ready"
    local machine_duration="20m"

    for cluster in $MANAGED_CLUSTERS; do
        local kube_conf="$LOGS/$cluster-kubeconfig.yaml"

        INFO "Check for the nodes ready state"
        KUBECONFIG="$kube_conf" oc wait nodes --all --for=condition=ready \
            --timeout="$nodes_duration" || nodes_state="down"
        KUBECONFIG="$kube_conf" oc get nodes -o wide
        if [[ "$nodes_state" == "down" ]]; then
          ERROR "Timeout ($nodes_duration) exceeded while waiting for all nodes to be ready on cluster $cluster"
        fi

        # The "until" iteration is done below because when the MachineConfig applied in SNO cluster
        # and it got rebooted after configuration applied, the api call will return a "refused connection"
        # error, since the node is reboot and no api is available.
        # In that case, iterate 5 times to ensure connection is restored.
        iteration_timeout=5
        iteration=0
        INFO "Check for Machine Config Daemon to be rolled out by openshift-machine-config-operator"
        until [[ "$iteration" -eq "$iteration_timeout" ]]; do
            machine_state=$(KUBECONFIG="$kube_conf" oc -n openshift-machine-config-operator rollout status \
                daemonset machine-config-daemon --timeout="$machine_duration" || echo "down")

            if [[ "$machine_state" == "down" || "$machine_state" =~ "was refused" ]]; then
                INFO "Still waiting for Machine Config Daemon to be rolled out..."
                ((iteration="$iteration"+1))
                sleep 3m
            else
                break
            fi
        done
        if [[ "$machine_state" == "down" || "$machine_state" =~ "was refused" ]]; then
          ERROR "Timeout exceeded while waiting for Machine Config Daemon to be ready on cluster $cluster"
        fi

        iteration=0
        INFO "Check for Machine Config Pool to be updated"
        until [[ "$iteration" -eq "$iteration_timeout" ]]; do
            machine_state=$(KUBECONFIG="$kube_conf" oc wait machineconfigpool --all --for=condition=updated \
                --timeout="$machine_duration" || echo "down")

            if [[ "$machine_state" == "down" || "$machine_state" =~ "was refused" ]]; then
                INFO "Still waiting for Machine Config Pool to be updated..."
                ((iteration="$iteration"+1))
                sleep 3m
            else
                break
            fi
        done
        if [[ "$machine_state" == "down" || "$machine_state" =~ "was refused" ]]; then
          ERROR "Timeout exceeded while waiting for Machine Config Pool to be updated on cluster $cluster"
        fi

        iteration=0
        INFO "Check for Machine Config Pool ready state"
        for node in "master" "worker"; do
            until [[ "$iteration" -eq "$iteration_timeout" ]]; do
                machine_state=$(KUBECONFIG="$kube_conf" oc wait machineconfigpool "$node" \
                    --for=condition=Degraded=False \
                    --timeout="$machine_duration" || echo "down")

                if [[ "$machine_state" == "down" || "$machine_state" =~ "was refused" ]]; then
                    INFO "Still waiting for Machine Config Pool ready state..."
                    ((iteration="$iteration"+1))
                    sleep 3m
                else
                    break
                fi
            done
        done
        if [[ "$machine_state" == "down" || "$machine_state" =~ "was refused" ]]; then
          ERROR "Timeout exceeded while waiting for Machine Config to be ready on cluster $cluster"
        fi

        INFO "MachineConfig was applied correctly on cluster $cluster"
    done
}

function verify_custom_registry_on_nodes() {
    INFO "Verify custom registry applied properly on the nodes"
    
    for cluster in $MANAGED_CLUSTERS; do
        INFO "Verify custom registry existence on cluster $cluster"
        local kube_conf="$LOGS/$cluster-kubeconfig.yaml"

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

    create_internal_registry_secret
    add_custom_registry_to_node "master"
    add_custom_registry_to_node "worker"
    check_for_nodes_ready_state
    verify_custom_registry_on_nodes
}

function import_images_into_local_registry() {
    INFO "Import images into local cluster registry"
    local import_state
    local submariner_ga="0.12.0"
    local registry_image_prefix_path

    version_state=$(validate_version "$submariner_ga" "$SUBMARINER_VERSION_INSTALL")
    if [[ "$version_state" == "valid" ]]; then
        export registry_image_prefix_path="${REGISTRY_IMAGE_PREFIX}"
    elif [[ "$version_state" == "not_valid" ]]; then
        export registry_image_prefix_path="${REGISTRY_IMAGE_PREFIX_TECH_PREVIEW}"
    fi

    # Starting 0.13.0 the subctl will use a new flow for the nettest image
    # The subctl will search the image as per the other images repository
    # It means that starting 0.13.0 we need to import the nettest image into the cluster
    local subctl_e2e_new_img_flow="0.13.0"
    local subctl_import_nettest_img="false"
    local subctl_state

    subctl_state=$(validate_version "$subctl_e2e_new_img_flow" "$SUBMARINER_VERSION_INSTALL")
    if [[ "$subctl_state" == "valid" ]]; then
        subctl_import_nettest_img="true"
    fi

    for cluster in $MANAGED_CLUSTERS; do
        local kube_conf="$LOGS/$cluster-kubeconfig.yaml"

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
            local img_src="$BREW_REGISTRY/$REGISTRY_IMAGE_IMPORT_PATH/$registry_image_prefix_path-$image:v$SUBMARINER_VERSION_INSTALL"
            IMG_NAME="$image" IMG_NAME_TAG="$img_src" TAG="v$SUBMARINER_VERSION_INSTALL" \
                yq eval '.metadata.name = env(IMG_NAME)
                | with(.spec.tags[0]; .from.name = env(IMG_NAME_TAG)
                | .name = env(TAG))' \
                "$SCRIPT_DIR/manifests/image-stream.yaml" \
                | KUBECONFIG="$kube_conf" oc apply -f -

            if [[ "$import_state" =~ ("Import failed"|"error") ]]; then
                ERROR "Image import failed.
                $import_state"
            fi
            INFO "Imported image - $image:v$SUBMARINER_VERSION_INSTALL"
        done

        INFO "Import Submariner image index bundle into local registry"
        get_latest_iib

        IMG_NAME="$SUBM_IMG_BUNDLE-index" IMG_NAME_TAG="$LATEST_IIB" TAG="v$SUBMARINER_VERSION_INSTALL" \
            yq eval '.metadata.name = env(IMG_NAME)
                | with(.spec.tags[0]; .from.name = env(IMG_NAME_TAG)
                | .name = env(TAG))' \
                "$SCRIPT_DIR/manifests/image-stream.yaml" \
                | KUBECONFIG="$kube_conf" oc apply -f -

        if [[ "$import_state" =~ ("Import failed"|"error") ]]; then
            ERROR "Image import failed.
            $import_state"
        fi
        INFO "Imported image - $SUBM_IMG_BUNDLE-index:v$SUBMARINER_VERSION_INSTALL"

        if [[ "$subctl_import_nettest_img" == "true" ]]; then
            # Pulling only the upstream image until downstream image is created
            # https://github.com/stolostron/backlog/issues/23675
            INFO "Import nettest used for e2e testing"
            IMG_NAME="$SUBM_IMG_NETTEST_UPSTREAM" \
                IMG_NAME_TAG="$SUBM_IMG_NETTEST_PATH_UPSTREAM/$SUBM_IMG_NETTEST_UPSTREAM:$SUBMARINER_VERSION_INSTALL" \
                TAG="v$SUBMARINER_VERSION_INSTALL" \
                yq eval '.metadata.name = env(IMG_NAME)
                | with(.spec.tags[0]; .from.name = env(IMG_NAME_TAG)
                | .name = env(TAG))' \
                "$SCRIPT_DIR/manifests/image-stream.yaml" \
                | KUBECONFIG="$kube_conf" oc apply -f -

                INFO "Imported image - $SUBM_IMG_NETTEST_PATH_UPSTREAM/$SUBM_IMG_NETTEST_UPSTREAM:$SUBMARINER_VERSION_INSTALL"
        fi
    done
}
