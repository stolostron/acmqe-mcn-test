#!/bin/bash

function get_acm_latest_snapshot() {
    INFO "Fetch ACM latest snapshot from QUAY.IO registry"

    local acm_snapshot
    local acm_version="$ACM_UPGRADE_VERSION"
    local acm_iib_reg="https://quay.io/api/v1/repository/acm-d/acm-custom-registry/tag/"

    acm_snapshot=$(curl -s -X GET "$acm_iib_reg" \
        | jq -S '.tags[] | {name: .name} | select(.name | startswith("'"$acm_version"'"))' | jq -r '.name' | head -1)

    ACM_UPGRADE_SNAPSHOT="$acm_snapshot"
    INFO "Detected ACM snapshot - $ACM_UPGRADE_SNAPSHOT"
}

function update_subm_catalog_source() {
    INFO "Increase the submariner version"
    local submariner_version
    submariner_version=$(fetch_installed_submariner_version)
    submariner_version=$(increase_minor_version "$submariner_version")
    export SUBMARINER_VERSION_INSTALL=$submariner_version

    INFO "Update catalog source on the managed clusters for submariner version - $SUBMARINER_VERSION_INSTALL"
    for cluster in $MANAGED_CLUSTERS; do
        get_latest_iib
        IMG_SRC="$LATEST_IIB" 

        INFO "Update catalog source on $cluster cluster"
        KUBECONFIG="$KCONF/$cluster-kubeconfig.yaml" \
            oc -n openshift-marketplace patch catalogsource submariner-catalog --type=merge \
            -p '{"spec":{"image":"'"$IMG_SRC"'"}}'
    done
    unset SUBMARINER_VERSION_INSTALL

    for cluster in $MANAGED_CLUSTERS; do
        validate_catalog_source_readiness "spoke" "$cluster"
    done
}

function update_acm_catalog_source() {
    INFO "Increase the acm version"
    local catalog_image
    local registry_url
    local acm_image
    local acm_version="$ACM_UPGRADE_VERSION"
    local acm_catalog_ns="openshift-marketplace"
    local acm_catalogs=("acm-custom-registry" "mce-custom-registry")

    acm_version=$(fetch_multiclusterhub_version)
    acm_version=$(increase_minor_version "$acm_version")
    export ACM_UPGRADE_VERSION="$acm_version"

    get_acm_latest_snapshot
    INFO "Update catalog source on the ACM hub to version - $ACM_UPGRADE_VERSION with snapshot - $ACM_UPGRADE_SNAPSHOT"

    INFO "Update ACM CatalogSources with the newer version"
    for catalog in "${acm_catalogs[@]}"; do
        catalog_image=$(oc -n "$acm_catalog_ns" get catalogsource "$catalog" -o jsonpath='{.spec.image}')
        registry_url=${catalog_image%:*}
        acm_image="$registry_url:$ACM_UPGRADE_SNAPSHOT"

        oc -n "$acm_catalog_ns" patch catalogsource "$catalog" --type=merge \
            -p '{"spec":{"image":"'"$acm_image"'"}}'
    done

    validate_catalog_source_readiness "hub"
}

function perform_acm_upgrade() {
    INFO "Perform ACM upgrade"
    local acm_subs_name
    local acm_hub_version
    local acm_upgrade_version="$ACM_UPGRADE_VERSION"
    local acm_ns="open-cluster-management"
    local acm_channel="release"
    local timeout=0
    local wait_timeout=50

    acm_subs_name=$(oc -n open-cluster-management get subs \
        --no-headers=true -o custom-columns=NAME:".metadata.name")

    INFO "Change the ACM channel to $acm_channel-$acm_upgrade_version"
    oc -n "$acm_ns" patch subs "$acm_subs_name" --type=merge \
        -p '{"spec":{"channel":"'"$acm_channel-$acm_upgrade_version"'"}}'

    INFO "Start ACM Hub upgrade process"
    until [[ "$timeout" -eq "$wait_timeout" ]] || [[ "${acm_hub_version%.*}" == "$acm_upgrade_version" ]]; do
        INFO "Waiting for ACM Hub upgrade to complete..."
        acm_hub_version=$(oc get multiclusterhub -A -o jsonpath='{.items[0].status.currentVersion}')
        sleep $(( timeout++ ))
    done

    if [[ "${acm_hub_version%.*}" != "$acm_upgrade_version" ]]; then
        ERROR "ACM Hub upgrade to version $acm_upgrade_version failed"
    fi
    INFO "ACM Hub upgrade has been completed"
}
