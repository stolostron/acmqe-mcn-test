#!/bin/bash

# The functions below will prepare the
# managed clusters when downstream flow is used.

function create_icsp() {
    INFO "Create ImageContentSourcePolicy on the managed clusters"

    for cluster in $MANAGED_CLUSTERS; do
        INFO "Create Brew ICSP mirror on $cluster"
        yq eval '.spec.repositoryDigestMirrors[].mirrors[] = env(BREW_REGISTRY)' \
            "$SCRIPT_DIR/resources/image-content-source-policy.yaml" \
            | KUBECONFIG="$LOGS/$cluster-kubeconfig.yaml" oc apply -f -
    done
}

# The image index builder (iib) will be used by the downstream deployment
# to serve as a CatalogSource for the submariner images
function get_latest_iib() {
    INFO "Fetch latest Image Index Builder (IIB) from UBI (datagrepper.engineering.redhat)"

    local cluster="$1"
    local kube_conf="$LOGS/$cluster-kubeconfig.yaml"
    local submariner_version="$SUBMARINER_VERSION_INSTALL"
    local latest_iib
    local ocp_version
    local umb_output
    local index_images

    local bundle_name="submariner-operator-bundle"
    local umb_url="https://datagrepper.engineering.redhat.com/raw?topic=/topic/VirtualTopic.eng.ci.redhat-container-image.pipeline.complete"
    local iib_query='[.raw_messages[].msg | select(.pipeline.status=="complete") | {nvr: .artifact.nvr, index_image: .pipeline.index_image}] | .[0]'
    local latest_builds_number=5
    local rows=$((latest_builds_number * 5))
    local number_of_days=30
    local delta=$((number_of_days * 86400))  # 1296000 = 15 days * 86400 seconds

    umb_output=$(curl --retry 30 --retry-delay 5 -k -Ls \
                  "${umb_url}&rows_per_page=${rows}&delta=${delta}&contains=${bundle_name}-container-v${submariner_version}")
    index_images=$(echo "$umb_output" | jq -r "$iib_query")

    if [[ "$index_images" == "null" ]]; then
        WARNING "Failed to retrieve IIB by using the last $number_of_days days.
        Retrying with the number of days multiplied $number_of_days days x3."

        delta=$((delta * 3))
        umb_output=$(curl --retry 30 --retry-delay 5 -k -Ls \
                  "${umb_url}&rows_per_page=${rows}&delta=${delta}&contains=${bundle_name}-container-v${submariner_version}")
        index_images=$(echo "$umb_output" | jq -r "$iib_query")

        if [[ "$index_images" == "null" ]]; then
            ERROR "Unable to retrieve IIB images"
        fi
    fi
    INFO "Retrieved the following index images - $index_images"

    ocp_version=$(KUBECONFIG="$kube_conf" oc version | grep "Server Version: " | tr -s ' ' | cut -d ' ' -f3 | cut -d '.' -f1,2)
    latest_iib=$(echo "$index_images" | jq -r '.index_image."v'"${ocp_version}"'"' ) || :

    if [[ ! "$latest_iib" =~ iib:[0-9]+ ]]; then
        ERROR "No image index bundle $bundle_name for OCP version $ocp_version detected"
    fi

    LATEST_IIB="$BREW_REGISTRY/$(echo "$latest_iib" | cut -d'/' -f2-)"
    INFO "Detected IIB - $LATEST_IIB for cluster $cluster"
}

# The CatalogSource will be created with the iib image
# and used to fetch the submariner components images
function create_catalog_source() {
    INFO "Create CatalogSource on the managed clusters"
    local ocp_registry_url
    local ocp_registry_path
    local image_source="$LATEST_IIB"

    for cluster in $MANAGED_CLUSTERS; do
        get_latest_iib "$cluster"
        image_source="$LATEST_IIB"

        local catalog_ns="openshift-marketplace"
        if [[ "$DOWNSTREAM" == "true" && "$LOCAL_MIRROR" == "true" ]]; then
            catalog_ns="$SUBMARINER_NS"
            ocp_registry_url=$(oc registry info --internal)
            ocp_registry_path="$ocp_registry_url/$SUBMARINER_NS/$SUBM_IMG_BUNDLE-index:v$SUBMARINER_VERSION_INSTALL"
            image_source="$ocp_registry_path"
        fi

        INFO "Create CatalogSource on $cluster cluster"
        IMG_SRC="$image_source" NS="$catalog_ns" \
            yq eval '.spec.image = env(IMG_SRC)
            | .metadata.namespace = env(NS)' \
            "$SCRIPT_DIR/resources/catalog-source.yaml" \
            | KUBECONFIG="$LOGS/$cluster-kubeconfig.yaml" oc apply -f -
    done

    INFO "Check CatalogSource state"
    local wait_timeout=35
    local timeout
    local cmd_output=""
    for cluster in $MANAGED_CLUSTERS; do
        INFO "Check CatalogSource state on $cluster cluster"
        timeout=0
        until [[ "$timeout" -eq "$wait_timeout" ]] || [[ "$cmd_output" == "READY" ]]; do
            INFO "Waiting for CatalogSource 'READY' state..."
            cmd_output=$(KUBECONFIG="$LOGS/$cluster-kubeconfig.yaml" \
                            oc -n "$catalog_ns" get catalogsource submariner-catalog \
                            -o jsonpath='{.status.connectionState.lastObservedState}')
            sleep $(( timeout++ ))
        done

        if [[ "$cmd_output" != "READY" ]]; then
            ERROR "The CatalogSource didn't reach ready state - $cmd_output"
        fi
        INFO "The CatalogSource is in 'READY' state"
    done
}

# Verify required submariner version within the package manifest.
# The package manifest created based on the IIB within the CatalogSource.
function verify_package_manifest() {
    INFO "Verify Submariner version within the package manifest"

    local manifest_ver
    local submariner_version="$SUBMARINER_VERSION_INSTALL"
    local wait_timeout=30
    local timeout
    local catalog_ns="openshift-marketplace"

    if [[ "$DOWNSTREAM" == "true" && "$LOCAL_MIRROR" == "true" ]]; then
        catalog_ns="$SUBMARINER_NS"
    fi

    for cluster in $MANAGED_CLUSTERS; do
        INFO "Verify package manifest for cluster $cluster"

        # For some reason version of the manifest is not fetched
        # on each call. Making repeating iterrations to get it.
        timeout=0
        until [[ "$timeout" -eq "$wait_timeout" ]]; do
            INFO "Searching for Submariner version - $submariner_version in PackageManifest"
            manifest_ver=$(KUBECONFIG="$LOGS/$cluster-kubeconfig.yaml" \
                            oc -n "$catalog_ns" get packagemanifest submariner --ignore-not-found \
                            -o jsonpath='{.status.channels[?(@.currentCSV == "'"submariner.v$submariner_version"'")].currentCSVDesc.version}')

            if [[ -n "$manifest_ver" && "$manifest_ver" == "$submariner_version" ]]; then
                continue 2
            fi
            sleep $(( timeout++ ))
        done

        if [[ "$manifest_ver" != "$submariner_version" ]]; then
            ERROR "Submariner package manifest is missing $submariner_version version"
        fi
        INFO "Submariner package manifest contains version $submariner_version"
    done
}

function verify_brew_secret_existence() {
    local brew_sec
    local brew_sec_state

    brew_sec=$(oc -n openshift-config get secret pull-secret \
        --template='{{index .data ".dockerconfigjson" | base64decode}}' \
        | jq --arg brew "$BREW_REGISTRY" '{"auths": {($brew): .auths[$brew]}}' | base64 -w 0)

    brew_sec_state=$(echo "$brew_sec" | base64 -d \
                        | jq --arg brew "$BREW_REGISTRY" '.auths[$brew]')
    if [[ "$brew_sec_state" == "null" ]]; then
        ERROR "Brew secret is required for downstream deployment but not available. Aborting."
    fi
    echo "$brew_sec"
}

function create_brew_secret() {
    INFO "Create Brew secret on the managed clusters"
    local brew_sec

    INFO "Verify Brew secret existence on ACM Hub"
    brew_sec=$(verify_brew_secret_existence)

    local secret_ns=("openshift-config" "openshift-marketplace")
    if [[ "$DOWNSTREAM" == "true" && "$LOCAL_MIRROR" == "true" ]]; then
        secret_ns+=("$SUBMARINER_NS")
    fi

    for cluster in $MANAGED_CLUSTERS; do
        INFO "Create Brew secret on $cluster cluster"
        local kube_conf="$LOGS/$cluster-kubeconfig.yaml"

        INFO "Create Brew registry secret in globally available namespace"
        INFO "Create Brew registry secret to be reachable for the catalog source"
        for namespace in "${secret_ns[@]}"; do
            NS="$namespace" HASH="$brew_sec" \
                yq eval '.metadata.name = "brew-registry"
                | .metadata.namespace = env(NS)
                | .data.".dockerconfigjson" = env(HASH)' \
                "$SCRIPT_DIR/resources/secret.yaml" \
                | KUBECONFIG="$kube_conf" oc apply -f -
        done

        INFO "Update the cluster global pull-secret"
        KUBECONFIG="$kube_conf" oc patch secret pull-secret -n openshift-config \
            -p '{"data":{".dockerconfigjson":"'"$(KUBECONFIG="$kube_conf" oc get \
            secret pull-secret -n openshift-config \
            --output="jsonpath={.data.\.dockerconfigjson}" | base64 --decode \
            | jq -r -c '.auths |= . + '"$(KUBECONFIG="$kube_conf" oc get secret \
            brew-registry -n openshift-config \
            --output="jsonpath={.data.\.dockerconfigjson}" | base64 --decode \
            | jq -r -c '.auths')"'' | base64 -w 0)"'"}}'
    done
    INFO "Brew secret has been updated on all managed clusters"
}
