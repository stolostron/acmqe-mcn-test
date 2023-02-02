#!/bin/bash

# Contains the functions that check for script execution prerequisites.

### Prerequisites tools install for deploy and test
OS=$(uname -s | tr '[:upper:]' '[:lower:]')

function verify_ocp_clients() {
    if ! command -v oc &> /dev/null; then
        WARNING "Missing oc command. Installing..."
        mkdir -p "$HOME"/.local/bin
        wget -qO- https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz \
            -O openshift-install-linux.tar.gz
        tar zxvf openshift-install-linux.tar.gz
        mv oc kubectl "$HOME"/.local/bin
        
        # Add local BIN dir to PATH
        [[ ":$PATH:" = *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"
        INFO "The oc and kubectl installed"
    fi
    INFO "The oc and kubectl commands found"
}

function verify_yq() {
    if ! command -v yq &> /dev/null; then
        if [[ "${OS}" == "darwin" ]]; then
            ERROR "Perform 'brew install yq' and try again."
        elif [[ "${OS}" == "linux" ]]; then
            WARNING "Missing yq command. Installing..."
            mkdir -p "$HOME"/.local/bin
            wget -qO- https://github.com/mikefarah/yq/releases/download/v4.16.2/yq_linux_amd64 \
                -O "$HOME"/.local/bin/yq && chmod +x "$HOME"/.local/bin/yq
            
            # Add local BIN dir to PATH
            [[ ":$PATH:" = *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"
        fi
        INFO "The yq command installed"
    fi
    INFO "The yq command is found"
}

function verify_jq() {
    if ! command -v jq &> /dev/null; then
        WARNING "Missing jq command. Installing..."
        mkdir -p "$HOME"/.local/bin
        wget -qO- https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 \
            -O "$HOME"/.local/bin/jq && chmod +x "$HOME"/.local/bin/jq

        # Add local BIN dir to PATH
        [[ ":$PATH:" = *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"
        INFO "The jq command installed"
    fi
    INFO "The jq command is found"
}

# ROSA (aws ocp managed cluster)
function verify_rosa_cli() {
    if ! command -v rosa &> /dev/null; then
        WARNING "Missing rosa command. Installing..."
        mkdir -p "$HOME"/.local/bin
        wget -qO- "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/rosa/latest/rosa-linux.tar.gz" \
            -O rosa.tar.gz
        tar zxvf rosa.tar.gz
        rm -f rosa.tar.gz
        mv rosa "$HOME"/.local/bin

        # Add local BIN dir to PATH
        [[ ":$PATH:" = *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"
        INFO "The oc and kubectl installed"
    fi
    INFO "The rosa command is found"
}

function verify_prerequisites_tools() {
    INFO "Verify prerequisites tools"
    verify_ocp_clients
    verify_yq
    verify_jq
}


### Prerequisites tools install for test
function fetch_submariner_addon_version() {
    local sub_cluster_ns
    local sub_version

    sub_cluster_ns=$(echo "$MANAGED_CLUSTERS" | head -n 1)
    sub_version=$(oc get managedclusteraddon/submariner -n "$sub_cluster_ns" \
                    -o jsonpath='{.status.conditions[?(@.type == "SubmarinerAgentDegraded")].message}' \
                    | grep -Po '(?<=submariner.)[^)]*')
    echo "$sub_version"
}

function get_subctl_for_testing() {
    INFO "Installing subctl client"

    # local image_prefix="$REGISTRY_IMAGE_PREFIX"
    local subctl_version
    local subctl_download_url
    local subctl_archive
    local subctl_bin
    subctl_version=$(fetch_submariner_addon_version | cut -d '-' -f1)

    if [[ "$DOWNSTREAM" == "true" ]]; then
        # INFO "Download downstream subctl binary for testing"
        # subctl_download_url="$VPN_REGISTRY/$REGISTRY_IMAGE_IMPORT_PATH/$image_prefix-subctl-rhel8:$subctl_version"
        # INFO "Download subctl from - $subctl_download_url"
        # oc image extract --insecure=true "$subctl_download_url" --path=/dist/subctl-*-linux-amd64.tar.xz:./ --confirm

        # Untill the https://github.com/submariner-io/subctl/pull/526 patch will be available downstream,
        # use upstream subctl binary

        INFO "Download subctl binary for testing"
        subctl_version="${subctl_version:1:4}"
        subctl_download_url="$SUBCTL_UPSTREAM_URL/releases/download/subctl-release-$subctl_version/subctl-release-$subctl_version-linux-amd64.tar.xz"
        INFO "Download subctl from - $subctl_download_url"
        wget -qO- "$subctl_download_url" -O subctl.tar.xz
    else
        INFO "Download upstream subctl binary for testing"

        WARNING "Due to https://github.com/submariner-io/submariner-operator/issues/1977 devel version will be used"
        subctl_download_url="$SUBCTL_UPSTREAM_URL/releases/download/subctl-devel/subctl-devel-linux-amd64.tar.xz"
        wget -qO- "$subctl_download_url" -O subctl.tar.xz
    fi

    INFO "Submariner addon version - $subctl_version"
    INFO "Download subctl from - $subctl_download_url"

    subctl_archive=$(find . -maxdepth 1 -name "subctl*tar.xz")
    tar xfJ "$subctl_archive" --strip-components 1
    subctl_bin=$(find . -maxdepth 1 -name "subctl*linux-amd64")

    mkdir -p "$HOME"/.local/bin
    cp "$subctl_bin" "$HOME"/.local/bin/subctl
    rm -rf "$subctl_bin" "$subctl_archive"

    # Add local BIN dir to PATH
    [[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"
    INFO "Subctl has been donwload and placed under $HOME/.local/bin/"
    subctl version
}

function get_subctl_version() {
    subctl version 2>/dev/null | grep -Po '(?<=: v).*' || echo "Missing subctl client"
}

function verify_subctl_command() {
    INFO "Verify subctl command existence"

    local submariner_version
    local subctl_client

    submariner_version=$(fetch_submariner_addon_version)
    subctl_client=$(get_subctl_version)

    if ! command -v subctl &> /dev/null; then
        get_subctl_for_testing
    elif [[ "$submariner_version" != "$subctl_client" ]]; then
        get_subctl_for_testing
    else
        INFO "The subctl client exists and has the required version - $subctl_client"
    fi
}

# Verify system readiness for cypress testing.
# Since cypress requirements like npm and nodejs requires
# system administration priviliges, prerequisites will not be installed.
# The function only report readiness state.
function verify_cypress() {
    INFO "Verify cypress readiness"

    if ! command -v npm &> /dev/null || ! command -v node &> /dev/null; then
        INFO "Cypress prerequisites are not ready"
        export UI_TESTS="false"
    else
        INFO "Cypress requirements fulfilled"
    fi
}
