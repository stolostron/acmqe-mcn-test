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

function verify_prerequisites_tools() {
    INFO "Verify prerequisites tools"
    verify_ocp_clients
    verify_yq
    verify_jq
}

function verify_ibmcloud_binary() {
    local ver

    if ! command -v ibmcloud &> /dev/null; then
        WARNING "Missing ibmcloud command. Installing..."
        mkdir -p "$HOME"/.local/bin
        ver=$(curl -s -X GET \
            https://api.github.com/repos/IBM-Cloud/ibm-cloud-cli-release/releases/latest \
            | jq '.name' | tr -d "'\"" | grep -Po '(?<=v)[^)]*')

        wget -qO- "https://download.clis.cloud.ibm.com/ibm-cloud-cli/${ver}/binaries/IBM_Cloud_CLI_${ver}_linux_amd64.tgz" \
            -O - | tar -zx --strip=1 --no-anchored -C "$HOME"/.local/bin/ ibmcloud

        # Add local BIN dir to PATH
        [[ ":$PATH:" = *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"
        INFO "The ibmcloud command installed"
    fi
    INFO "The ibmcloud binary is found"
}

function get_subctl_for_testing() {
    INFO "Installing subctl client"

    local subctl_version
    local subctl_download_url
    subctl_version=$(fetch_installed_submariner_version)

    # Check if SUBCTL_DOWNLOAD_URL is provided as environment variable
    if [[ -z "${SUBCTL_DOWNLOAD_URL}" ]]; then
        ERROR "SUBCTL_DOWNLOAD_URL environment variable is not set. Please provide subctl download URL through Jenkins parameter."
    fi

    subctl_download_url="$SUBCTL_DOWNLOAD_URL"
    INFO "Using subctl download URL from Jenkins parameter: $subctl_download_url"

    INFO "Extracting subctl from container image: $subctl_download_url"

    # Try multiple paths for different image structures
    # Standard images use /dist/, Konflux images use /usr/local/bin/
    local extracted=false

    # Try path 1: /dist/subctl-*-linux-amd64.tar.xz (standard downstream path)
    if oc image extract --insecure=true "$subctl_download_url" --path=/dist/subctl-*-linux-amd64.tar.xz:./ --confirm 2>/dev/null; then
        if ls subctl-*-linux-amd64.tar.xz 1>/dev/null 2>&1; then
            extracted=true
            INFO "Extracted subctl from /dist/ path"
        fi
    fi

    # Try path 2: /usr/local/bin/subctl (Konflux images)
    if [[ "$extracted" == "false" ]]; then
        INFO "Trying alternative extraction path for Konflux image..."
        if oc image extract --insecure=true "$subctl_download_url" --path=/usr/local/bin/subctl:./ --confirm 2>/dev/null; then
            if [[ -f subctl ]]; then
                mkdir -p subctl-temp
                mv subctl "subctl-temp/subctl-v${subctl_version}-linux-amd64"
                tar -cJf subctl.tar.xz -C subctl-temp "subctl-v${subctl_version}-linux-amd64"
                rm -rf subctl-temp
                extracted=true
                INFO "Extracted subctl from /usr/local/bin/ path (Konflux)"
            fi
        fi
    fi

    # Try path 3: /usr/bin/subctl (fallback)
    if [[ "$extracted" == "false" ]]; then
        if oc image extract --insecure=true "$subctl_download_url" --path=/usr/bin/subctl:./ --confirm 2>/dev/null; then
            if [[ -f subctl ]]; then
                mkdir -p subctl-temp
                mv subctl "subctl-temp/subctl-v${subctl_version}-linux-amd64"
                tar -cJf subctl.tar.xz -C subctl-temp "subctl-v${subctl_version}-linux-amd64"
                rm -rf subctl-temp
                extracted=true
                INFO "Extracted subctl from /usr/bin/ path"
            fi
        fi
    fi

    if [[ "$extracted" == "false" ]]; then
        ERROR "Failed to extract subctl binary from $subctl_download_url. Tried paths: /dist/, /usr/local/bin/, and /usr/bin/"
    fi

    # If we extracted a tar.xz directly, rename it
    if ls subctl-*-linux-amd64.tar.xz 1>/dev/null 2>&1; then
        mv subctl-*-linux-amd64.tar.xz subctl.tar.xz
    fi

    INFO "Submariner addon version - $subctl_version"
    INFO "Downloaded subctl from - $subctl_download_url"

    tar xfJ subctl.tar.xz

    mkdir -p "$HOME"/.local/bin
    install subctl*linux-amd64 "$HOME"/.local/bin/subctl
    rm -f subctl.tar.xz subctl*linux-amd64

    # Add local BIN dir to PATH
    [[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"
    INFO "Subctl has been downloaded and placed under $HOME/.local/bin/"
    subctl version
}

function get_subctl_version() {
    subctl version 2>/dev/null | grep -Po '(?<=: v).*' || echo "Missing subctl client"
}

function verify_subctl_command() {
    INFO "Verify subctl command existence"

    local submariner_version
    local subctl_client

    submariner_version=$(fetch_installed_submariner_version)
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
