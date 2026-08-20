#!/bin/bash

# The functions below will prepare the
# managed clusters when downstream flow is used.

function create_icsp() {
    INFO "Create ImageContentSourcePolicy on the managed clusters"

    for cluster in $MANAGED_CLUSTERS; do
        INFO "Create Brew ICSP mirror on $cluster"
        yq eval '.spec.repositoryDigestMirrors[].mirrors[] = env(BREW_REGISTRY)' \
            "$SCRIPT_DIR/manifests/image-content-source-policy.yaml" \
            | KUBECONFIG="$KCONF/$cluster-kubeconfig.yaml" oc apply -f -
    done
}

# ━━━ KONFLUX CONSTANTS ━━━
readonly KONFLUX_API="${KONFLUX_CLUSTER_API:-https://api.kflux-prd-rh02.0fk9.p1.openshiftapps.com:6443}"
readonly KONFLUX_NAMESPACE="submariner-tenant"

# Global flag to track Konflux login status
KONFLUX_LOGGED_IN=false

# ━━━ KONFLUX LOGIN ━━━
# Login to Konflux cluster using token, username/password, or interactive web login
function login_to_konflux() {
    # If already logged in, skip
    if [[ "$KONFLUX_LOGGED_IN" == "true" ]]; then
        return 0
    fi

    INFO "Logging into Konflux cluster at $KONFLUX_API"

    # Check prerequisites
    command -v oc &>/dev/null || ERROR "oc command not found - install OpenShift CLI"

    # Save current KUBECONFIG
    local saved_kubeconfig="${KUBECONFIG:-}"
    unset KUBECONFIG

    # Check if already logged in
    if oc whoami &>/dev/null 2>&1; then
        local server
        server=$(oc whoami --show-server 2>/dev/null || echo "")
        if [[ "$server" =~ "kflux" ]]; then
            INFO "Already logged into Konflux cluster"
            KONFLUX_LOGGED_IN=true
            [[ -n "$saved_kubeconfig" ]] && export KUBECONFIG="$saved_kubeconfig"
            return 0
        fi
    fi

    # Try token authentication if token is set
    if [[ -n "${KONFLUX_CLUSTER_TOKEN}" ]]; then
        INFO "Attempting token authentication to Konflux"
        if oc login --token="${KONFLUX_CLUSTER_TOKEN}" --server="${KONFLUX_API}" --insecure-skip-tls-verify=true &>/dev/null; then
            if oc whoami &>/dev/null 2>&1; then
                INFO "Successfully logged into Konflux using token"
                KONFLUX_LOGGED_IN=true
                [[ -n "$saved_kubeconfig" ]] && export KUBECONFIG="$saved_kubeconfig"
                return 0
            fi
        fi
        WARNING "Token authentication failed - token may be invalid or expired"
        WARNING "Falling back to interactive web login"
    fi

    # Try username/password authentication if credentials are set
    if [[ -n "${KONFLUX_CLUSTER_USER}" && -n "${KONFLUX_CLUSTER_PASS}" ]]; then
        INFO "Attempting username/password authentication to Konflux"
        if oc login -u "${KONFLUX_CLUSTER_USER}" -p "${KONFLUX_CLUSTER_PASS}" --server="${KONFLUX_API}" --insecure-skip-tls-verify=true &>/dev/null; then
            if oc whoami &>/dev/null 2>&1; then
                INFO "Successfully logged into Konflux using username/password"
                KONFLUX_LOGGED_IN=true
                [[ -n "$saved_kubeconfig" ]] && export KUBECONFIG="$saved_kubeconfig"
                return 0
            fi
        fi
        WARNING "Username/password authentication failed"
        WARNING "Falling back to interactive web login"
    fi

    # No credentials or credentials failed - try interactive web login
    INFO "No valid credentials found - initiating interactive web login to Konflux"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Konflux Interactive Login Required"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Opening browser for authentication to Konflux cluster..."
    echo "Server: ${KONFLUX_API}"
    echo ""
    echo "After successful login, the script will continue automatically."
    echo ""

    # Perform web login (interactive)
    if oc login --web --server="${KONFLUX_API}" --insecure-skip-tls-verify=true; then
        if oc whoami &>/dev/null 2>&1; then
            local server
            server=$(oc whoami --show-server 2>/dev/null || echo "")
            if [[ "$server" =~ "kflux" ]]; then
                local user
                user=$(oc whoami 2>/dev/null)
                INFO "Successfully logged into Konflux cluster (user: $user)"
                echo ""
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo ""
                KONFLUX_LOGGED_IN=true
                [[ -n "$saved_kubeconfig" ]] && export KUBECONFIG="$saved_kubeconfig"
                return 0
            fi
        fi
    fi

    # Login failed
    [[ -n "$saved_kubeconfig" ]] && export KUBECONFIG="$saved_kubeconfig"
    ERROR "Failed to login to Konflux cluster. Please check your credentials and try again."
}

# ━━━ VERSION MATCHING ━━━
function release_matches_version() {
    local release="$1"
    local version="$2"
    local sha_title

    sha_title=$(oc get release "$release" -n "$KONFLUX_NAMESPACE" \
        -o jsonpath='{.metadata.annotations.pac\.test\.appstudio\.openshift\.io/sha-title}' 2>/dev/null || echo "")

    echo "$sha_title" | head -1 | grep -q "v${version}"
}

function snapshot_matches_version() {
    local snapshot="$1"
    local version="$2"
    local sha_title

    sha_title=$(oc get snapshot "$snapshot" -n "$KONFLUX_NAMESPACE" \
        -o jsonpath='{.metadata.annotations.pac\.test\.appstudio\.openshift\.io/sha-title}' 2>/dev/null || echo "")

    if echo "$sha_title" | head -1 | grep -q "v${version}"; then
        return 0
    fi

    return 1
}

# ━━━ GET FBC URL ━━━
# Get FBC catalog URL from Jenkins parameter based on OCP version
function get_latest_iib() {
    INFO "Detecting OCP version to select appropriate FBC URL"

    local kube_conf="$KCONF/$cluster-kubeconfig.yaml"
    local ocp_version
    local ocp_minor
    local fbc_var_name
    local fbc_url

    ocp_version=$(KUBECONFIG="$kube_conf" oc version 2>/dev/null | grep "Server Version: " | tr -s ' ' | cut -d ' ' -f3 | cut -d '.' -f1,2)

    if [[ -z "$ocp_version" ]]; then
        ERROR "Failed to get OCP version from cluster $cluster"
    fi

    ocp_minor="${ocp_version#4.}"
    INFO "Detected OCP version: ${ocp_version}"

    fbc_var_name="FBC_URL_4_${ocp_minor}"
    fbc_url="${!fbc_var_name}"

    if [[ -z "$fbc_url" ]]; then
        ERROR "FBC URL not provided for OCP ${ocp_version}. Please set ${fbc_var_name} parameter in Jenkins."
    fi

    LATEST_IIB="$fbc_url"
    INFO "Using FBC URL from Jenkins parameter ${fbc_var_name}: $LATEST_IIB"
    return 0
}

# Fallback: Get FBC from Snapshots if Release CRs don't exist
function get_fbc_from_snapshots() {
    local ocp_minor="$1"
    local version="$2"

    INFO "Fetching FBC from Snapshots for OCP 4.${ocp_minor}"

    local snapshots
    snapshots=$(oc get snapshots -n "$KONFLUX_NAMESPACE" --sort-by=.metadata.creationTimestamp 2>/dev/null \
        | grep "^submariner-fbc-4-${ocp_minor}-" \
        | awk '{print $1}' || echo "")

    if [[ -z "$snapshots" ]]; then
        ERROR "No snapshots found for OCP 4.${ocp_minor}"
    fi

    local latest_snapshot
    latest_snapshot=$(echo "$snapshots" | tail -1)

    if [[ -z "$latest_snapshot" ]]; then
        ERROR "Failed to get latest snapshot for OCP 4.${ocp_minor}"
    fi

    INFO "Using latest FBC snapshot: $latest_snapshot"

    local catalog_image
    catalog_image=$(oc get snapshot "$latest_snapshot" -n "$KONFLUX_NAMESPACE" \
        -o jsonpath='{.spec.components[0].containerImage}' 2>/dev/null || echo "")

    if [[ -z "$catalog_image" ]]; then
        ERROR "Failed to extract catalog image from snapshot $latest_snapshot"
    fi

    LATEST_IIB="$catalog_image"
    INFO "Detected FBC from Konflux Snapshot: $LATEST_IIB (contains multiple Submariner versions)"
}

# ━━━ GET SUBCTL FROM KONFLUX ━━━
# Sets global variable: KONFLUX_SUBCTL_IMAGE
function get_konflux_subctl_image() {
    INFO "Fetch subctl container image from Konflux snapshots"

    local submariner_version="$SUBMARINER_VERSION_INSTALL"
    local version_short
    local application_name
    local component_name
    local subctl_image

    if [[ "$submariner_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        version_short="${submariner_version%.*}"
    else
        version_short="$submariner_version"
    fi
    version_short="${version_short//./-}"

    application_name="submariner-${version_short}"
    component_name="subctl-${version_short}"

    INFO "Looking for subctl in application: ${application_name}, component: ${component_name}"

    local saved_kubeconfig="${KUBECONFIG:-}"
    unset KUBECONFIG

    login_to_konflux

    local snapshots
    snapshots=$(oc get snapshots -n "$KONFLUX_NAMESPACE" --sort-by=.metadata.creationTimestamp 2>/dev/null \
        | grep "^${application_name}-" \
        | awk '{print $1}' || echo "")

    if [[ -z "$snapshots" ]]; then
        [[ -n "$saved_kubeconfig" ]] && export KUBECONFIG="$saved_kubeconfig"
        WARNING "No snapshots found for application ${application_name}"
        return 1
    fi

    local latest_snapshot
    latest_snapshot=$(echo "$snapshots" | tail -1)
    INFO "Using latest snapshot: $latest_snapshot"

    subctl_image=$(oc get snapshot "$latest_snapshot" -n "$KONFLUX_NAMESPACE" \
        -o json 2>/dev/null | jq -r ".spec.components[] | select(.name==\"${component_name}\") | .containerImage" || echo "")

    if [[ -z "$subctl_image" || "$subctl_image" == "null" ]]; then
        [[ -n "$saved_kubeconfig" ]] && export KUBECONFIG="$saved_kubeconfig"
        WARNING "Failed to extract subctl image from snapshot $latest_snapshot"
        return 1
    fi

    [[ -n "$saved_kubeconfig" ]] && export KUBECONFIG="$saved_kubeconfig"

    KONFLUX_SUBCTL_IMAGE="$subctl_image"
    INFO "Detected subctl from Konflux Snapshot: $KONFLUX_SUBCTL_IMAGE"
    return 0
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
            | KUBECONFIG="$KCONF/$cluster-kubeconfig.yaml" oc apply -f -
    done

    for cluster in $MANAGED_CLUSTERS; do
        validate_catalog_source_readiness "spoke" "$cluster"
    done
}

function validate_catalog_source_readiness() {
    INFO "Check CatalogSource state"
    local type="$1"  # hub or spoke
    local cluster="$2"
    local wait_timeout=35
    local timeout=0
    local cmd_output=""
    local catalog_ns="openshift-marketplace"
    local acm_catalog="acm-custom-registry"

    INFO "Check CatalogSource state on cluster $cluster"
    until [[ "$timeout" -eq "$wait_timeout" ]] || [[ "$cmd_output" == "READY" ]]; do
        INFO "Waiting for CatalogSource 'READY' state..."
        if [[ "$type" == "hub" ]]; then
            cmd_output=$(oc -n "$catalog_ns" get catalogsource "$acm_catalog" \
                -o jsonpath='{.status.connectionState.lastObservedState}')
        elif [[ "$type" == "spoke" ]]; then
            cmd_output=$(KUBECONFIG="$KCONF/$cluster-kubeconfig.yaml" \
                oc -n "$catalog_ns" get catalogsource "$DOWNSTREAM_CATALOG_SOURCE" \
                -o jsonpath='{.status.connectionState.lastObservedState}')
        fi
        sleep $(( timeout++ ))
    done

    if [[ "$cmd_output" != "READY" ]]; then
        ERROR "The CatalogSource didn't reach ready state - $cmd_output"
    fi
    INFO "The CatalogSource is in 'READY' state"
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
            manifest_ver=$(KUBECONFIG="$KCONF/$cluster-kubeconfig.yaml" \
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

function verify_private_quay_secret_existence() {
    local private_quay_sec
    local private_quay_sec_state

    private_quay_sec=$(oc -n openshift-config get secret pull-secret \
        --template='{{index .data ".dockerconfigjson" | base64decode}}' \
        | jq --arg private_quay "$PRIVATE_QUAY_REGISTRY" \
        '{"auths": {($private_quay): .auths[$private_quay]}}' | base64 -w 0)

    private_quay_sec_state=$(echo "$private_quay_sec" | base64 -d \
                        | jq --arg private_quay "$PRIVATE_QUAY_REGISTRY" '.auths[$private_quay]')
    if [[ "$private_quay_sec_state" == "null" ]]; then
        ERROR "Private quay secret is required for downstream deployment but not available. Aborting."
    fi
    echo "$private_quay_sec"
}

function create_brew_and_private_quay_secret() {
    INFO "Create Brew and private Quay secret on the managed clusters"
    local brew_sec
    local private_quay_sec

    INFO "Verify Brew secret existence on ACM Hub"
    brew_sec=$(verify_brew_secret_existence)
    INFO "Verify private Quay secret existence on ACM Hub"
    private_quay_sec=$(verify_private_quay_secret_existence)

    local secret_ns=("openshift-config" "openshift-marketplace")

    for cluster in $MANAGED_CLUSTERS; do
        INFO "Create Brew secret on $cluster cluster"
        local kube_conf="$KCONF/$cluster-kubeconfig.yaml"

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

        INFO "Create private Quay registry secret in globally available namespace"
        INFO "Create private Quay registry secret to be reachable for the catalog source"
        for namespace in "${secret_ns[@]}"; do
            NS="$namespace" HASH="$private_quay_sec" \
                yq eval '.metadata.name = "private-quay-registry"
                | .metadata.namespace = env(NS)
                | .data.".dockerconfigjson" = env(HASH)' \
                "$SCRIPT_DIR/manifests/secret.yaml" \
                | KUBECONFIG="$kube_conf" oc apply -f -
        done

        INFO "Update the cluster global pull-secret with Brew secret"
        KUBECONFIG="$kube_conf" oc patch secret pull-secret -n openshift-config \
            -p '{"data":{".dockerconfigjson":"'"$(KUBECONFIG="$kube_conf" oc get \
            secret pull-secret -n openshift-config \
            --output="jsonpath={.data.\.dockerconfigjson}" | base64 --decode \
            | jq -r -c '.auths |= . + '"$(KUBECONFIG="$kube_conf" oc get secret \
            brew-registry -n openshift-config \
            --output="jsonpath={.data.\.dockerconfigjson}" | base64 --decode \
            | jq -r -c '.auths')"'' | base64 -w 0)"'"}}'

        INFO "Update the cluster global pull-secret with private Quay secret"
        KUBECONFIG="$kube_conf" oc patch secret pull-secret -n openshift-config \
            -p '{"data":{".dockerconfigjson":"'"$(KUBECONFIG="$kube_conf" oc get \
            secret pull-secret -n openshift-config \
            --output="jsonpath={.data.\.dockerconfigjson}" | base64 --decode \
            | jq -r -c '.auths |= . + '"$(KUBECONFIG="$kube_conf" oc get secret \
            private-quay-registry -n openshift-config \
            --output="jsonpath={.data.\.dockerconfigjson}" | base64 --decode \
            | jq -r -c '.auths')"'' | base64 -w 0)"'"}}'
    done
    INFO "Brew and private Quay secret has been updated on all managed clusters"
}
