#!/bin/bash

RUNTIME="docker"
SUBM_CONTAINER_NAME="${SUBM_CONTAINER_NAME:-subm-qe}"
SUBM_CONTAINER_IMAGE="${SUBM_CONTAINER_IMAGE:-quay.io/maxbab/subm-test:test}"

function usage() {
    cat <<EOF

    Deploy or destroy local environment.
    During deployment of local environment, test container will be created.
    Local path of acmqe-mcn-test will be mapped into the running test container.

    Execution of OCP reation, ACM deployment, clusters deployment be ACM,
    Submariner deploy, test and report will be done from the container.

    Arguments:
    ----------
    --deploy        - Perform creation of test container
    --destroy       - Perform destroy of test container
    --get-runtime   - Get available container runtime
    --help|-h       - Print help
EOF
}

function check_container_engine() {
    if command -v docker &> /dev/null; then
        RUNTIME="docker"
    elif command -v podman &> /dev/null; then
        RUNTIME="podman"
    else
        echo "Unable to locate container runtime - docker/podman"
        exit 1
    fi
    echo "$RUNTIME"
}

function start_container() {
    destroy_container

    echo "Creating $SUBM_CONTAINER_NAME test container"
    "$RUNTIME" run --name "$SUBM_CONTAINER_NAME" -t -d --network host \
        -v "$(pwd)":/submariner -w /submariner -e PWD="/submariner" "$SUBM_CONTAINER_IMAGE" cat
}

function destroy_container() {
    if [[ "$("$RUNTIME" ps --filter name="$SUBM_CONTAINER_NAME" --quiet)" ]]; then
        echo "Destroying $SUBM_CONTAINER_NAME container"
        "$RUNTIME" stop "$SUBM_CONTAINER_NAME"
        "$RUNTIME" rm "$SUBM_CONTAINER_NAME"
    else
        echo "No $SUBM_CONTAINER_NAME container found. Nothing to delete."
    fi
}

function main() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --deploy)
                check_container_engine
                start_container
                shift
                ;;
            --destroy)
                check_container_engine
                destroy_container
                shift
                ;;
            --get-runtime)
                check_container_engine
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                echo "Invalid argument provided: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Trigger main function
main "$@"
