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
        INFO "The oc and kubectl installed."
    fi
    INFO "The oc and kubectl commands found."
}

function verify_yq() {
    if ! command -v yq &> /dev/null; then
        if [[ "${OS}" == "darwin" ]]; then
            ERROR "Perform 'brew install yq' and try again."
        elif [[ "${OS}" == "linux" ]]; then
            WARNING "#### Missing yq command. Installing..."
            mkdir -p "$HOME"/.local/bin
            wget -qO- https://github.com/mikefarah/yq/releases/download/v4.16.2/yq_linux_amd64 \
                -O "$HOME"/.local/bin/yq && chmod +x "$HOME"/.local/bin/yq
            
            # Add local BIN dir to PATH
            [[ ":$PATH:" = *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"
        fi
        INFO "The yq command installed."
    fi
    INFO "The yq command is found."
}

function verify_prerequisites_tools() {
    INFO "Verify prerequisites tools"
    verify_ocp_clients
    verify_yq
}


### Prerequisites tools install for test
function fetch_submariner_addon_version() {
    local sub_cluster_ns
    local sub_version

    sub_cluster_ns=$(oc get clusterdeployment -A \
                   --selector=cluster.open-cluster-management.io/clusterset=submariner \
                   -o jsonpath='{.items[0].metadata.namespace}')
    sub_version=$(oc get managedclusteraddon/submariner -n "$sub_cluster_ns" \
                    -o jsonpath='{.status.conditions[?(@.type == "SubmarinerAgentDegraded")].message}' \
                    | grep -Po '(?<=submariner.)[^)]*')
    echo "$sub_version"
}

function get_subctl_for_testing() {
    INFO "Installing subctl client"

    local subctl_version
    local subctl_download_url
    subctl_version=$(fetch_submariner_addon_version)
    subctl_download_url="$SUBCTL_URL_DOWNLOAD/download/$subctl_version/subctl-$subctl_version-linux-amd64.tar.xz"

    INFO "Submariner addon version - $subctl_version"
    INFO "Download subctl from - $subctl_download_url"

    wget -qO- "$subctl_download_url" -O "subctl-$subctl_version-linux-amd64.tar.xz"
    tar xfJ "subctl-$subctl_version-linux-amd64.tar.xz"

    mkdir -p "$HOME"/.local/bin
    cp "subctl-$subctl_version/subctl-$subctl_version-linux-amd64" "$HOME"/.local/bin/subctl

    rm -rf "subctl-$subctl_version-linux-amd64.tar.xz" "subctl-$subctl_version"

    # Add local BIN dir to PATH
    [[ ":$PATH:" = *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"
    INFO "Subctl $subctl_version has been donwload and placed under $HOME/.local/bin/"
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
