#!/bin/bash

# The functions below will prepare the
# managed clusters when downstream flow is used.

function create_icsp() {
    INFO "Create ImageContentSourcePolicy on the managed clusters"

    for cluster in $MANAGED_CLUSTERS; do
        INFO "Create Brew ICSP mirror on $cluster"
        yq eval '.spec.repositoryDigestMirrors[].mirrors[] = env(BREW_REGISTRY)' \
            "$SCRIPT_DIR/manifests/image-content-source-policy.yaml" \
            | KUBECONFIG="$LOGS/$cluster-kubeconfig.yaml" oc apply -f -
    done
}

# The image index builder (iib) will be used by the downstream deployment
# to serve as a CatalogSource for the submariner images
# Fetch builds from two issuers (pipeline triggers):
# "contra/piplene" - standard pipeline issuer
# "freshmaker" - CVE (security) fix issuer
# Compare between them and select the latest.
function get_latest_iib() {
    INFO "Fetch latest Image Index Builder (IIB) from UBI (datagrepper.engineering.redhat)"

    local kube_conf="$LOGS/$cluster-kubeconfig.yaml"
    local submariner_version="$SUBMARINER_VERSION_INSTALL"
    local latest_iib
    local ocp_version
    local umb_output
    local index_images
    local issuer
    local issuer_var
    local issuer_state

    local bundle_name="submariner-operator-bundle"
    local umb_url="https://datagrepper.engineering.redhat.com/raw?topic=/topic/VirtualTopic.eng.ci.redhat-container-image.pipeline.complete"
    local latest_builds_number=5
    local rows=$((latest_builds_number * 5))
    local number_of_days=30

    # The query component changed started from submariner version 0.12.* and for older version remain the same
    # For 0.12.* the component name is - "cvp-teamredhatadvancedclustermanagement"
    # For 0.11.* the component name is - "cvp-teamsubmariner"
    local submariner_component="cvp-teamredhatadvancedclustermanagement"
    if [[ "$submariner_version" == "0.11"* ]]; then
        submariner_component="cvp-teamsubmariner"
    fi

    # Loop over the build issuers and fetch results for each issuer.
    for issuer in "contra/pipeline" "freshmaker"; do
        local delta=$((number_of_days * 86400))  # 1296000 = 15 days * 86400 seconds

        # In order to separate the variables, create a variable for each issuer.
        # But since bash unable to use "/" sign as part of the variable name,
        # rename the variable for "contra/pipeline" key to "$pipeline_var".
        #
        # Declare dynamic variables in bash:
        # https://dev.to/a1ex/tricks-of-declaring-dynamic-variables-in-bash-15b9
        issuer_var="${issuer}_var"
        if [[ "$issuer" == "contra/pipeline" ]]; then
            issuer_var="pipeline_var"
        fi

        local iib_query='[.raw_messages[].msg | select(.pipeline.status=="complete" 
            and .artifact.component=="'"$submariner_component"'" and .artifact.issuer=="'"$issuer"'") 
            | {nvr: .artifact.nvr, index_image: .pipeline.index_image}] | .[0]'

        umb_output=$(curl --retry 30 --retry-delay 5 -k -Ls \
            "${umb_url}&rows_per_page=${rows}&delta=${delta}&contains=${bundle_name}-container-v${submariner_version}")
        index_images=$(echo "$umb_output" | jq -r "$iib_query")
        declare "$issuer_var"="$index_images"

        if [[ "$index_images" == "null" ]]; then
            delta=$((delta * 6))
            umb_output=$(curl --retry 30 --retry-delay 5 -k -Ls \
                "${umb_url}&rows_per_page=${rows}&delta=${delta}&contains=${bundle_name}-container-v${submariner_version}")
            index_images=$(echo "$umb_output" | jq -r "$iib_query")
            declare "$issuer_var"="$index_images"
        fi
    done

    # shellcheck disable=SC2154
    if [[ "$pipeline_var" == "null" && "$freshmaker_var" == "null" ]]; then
        ERROR "Unable to retrieve IIB images"
    fi

    # Assign 'contra/pipeline' as default issuer
    index_images="$pipeline_var"
    issuer="contra/pipeline"
    # Compare the builds of 'contra/pipeline' and 'freshmaker' and select the higher.
    # For example:
    # 0.13.1-3.1666718193 <- This will be selected
    # 0.13.1-2
    issuer_state=$(validate_version \
        "$(echo "$pipeline_var" | jq -r '.nvr' | grep -Po '(?<=container-v)[^)]*')" \
        "$(echo "$freshmaker_var" | jq -r '.nvr' | grep -Po '(?<=container-v)[^)]*')")
    # Checks if 'freshmaker' build is newer than 'contra/pipeline'
    if [[ "$issuer_state" == "valid" ]]; then
        index_images="$freshmaker_var"
        issuer="freshmaker"
    fi

    INFO "Retrieved the following index images from $issuer issuer - $index_images"

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
    local image_source="$LATEST_IIB"
    local catalog_ns="openshift-marketplace"

    for cluster in $MANAGED_CLUSTERS; do
        get_latest_iib
        image_source="$LATEST_IIB"


        INFO "Create CatalogSource on $cluster cluster"
        IMG_SRC="$image_source" NS="$catalog_ns" \
            yq eval '.spec.image = env(IMG_SRC)
            | .metadata.namespace = env(NS)' \
            "$SCRIPT_DIR/manifests/catalog-source.yaml" \
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

    for cluster in $MANAGED_CLUSTERS; do
        INFO "Verify package manifest for cluster $cluster"

        # For some reason version of the manifest is not fetched
        # on each call. Making repeating iterrations to get it.
        timeout=0
        until [[ "$timeout" -eq "$wait_timeout" ]]; do
            INFO "Searching for Submariner version - $submariner_version in PackageManifest"
            manifest_ver=$(KUBECONFIG="$LOGS/$cluster-kubeconfig.yaml" \
                            oc -n "$catalog_ns" get packagemanifest submariner --ignore-not-found \
                            -o json | jq -r '.status.channels[] | select(.currentCSV
                            | test("'"submariner.v$submariner_version"'")).currentCSVDesc.version')

            if [[ -n "$manifest_ver" && "$manifest_ver" =~ $submariner_version ]]; then
                INFO "Submariner package manifest contains version $manifest_ver"
                continue 2
            fi
            sleep $(( timeout++ ))
        done

        if [[ "$manifest_ver" != "$submariner_version" ]]; then
            ERROR "Submariner package manifest is missing $submariner_version version"
        fi
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
                "$SCRIPT_DIR/manifests/secret.yaml" \
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
