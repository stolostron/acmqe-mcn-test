#!/bin/bash

# Contains the functions that check for script execution prerequisites.

### Prerequisites tools install for deploy and test
OS=$(uname -s | tr '[:upper:]' '[:lower:]')

function verify_ocp_clients() {
    if ! command -v oc && command -v kubectl &> /dev/null; then
        WARNING "Missing oc/kubectl commands. Installing..."
        mkdir -p "$HOME"/.local/bin
        wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-install-linux.tar.gz \
            -O openshift-install-linux.tar.gz
        tar zxvf openshift-install-linux.tar.gz
        mv oc kubectl "$HOME"/.local/bin
        
        # Add local BIN dir to PATH
        [[ ":$PATH:" = *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"
    fi
    INFO "The oc/kubectl commands found."
}

function verify_yq() {
    if ! command -v yq &> /dev/null; then
        if [[ "${OS}" == "darwin" ]]; then
            ERROR "Perform 'brew install yq' and try again."
        elif [[ "${OS}" == "linux" ]]; then
            WARNING "#### Missing yq command. Installing..."
            mkdir -p "$HOME"/.local/bin
            wget https://github.com/mikefarah/yq/releases/download/v4.16.2/yq_linux_amd64 \
                -O "$HOME"/.local/bin/yq && chmod +x "$HOME"/.local/bin/yq
            
            # Add local BIN dir to PATH
            [[ ":$PATH:" = *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"
        fi
    fi
    INFO "The yq command is found."
}

function verify_prerequisites_tools() {
    INFO "Verify prerequisites tools"
    verify_ocp_clients
    verify_yq
}
