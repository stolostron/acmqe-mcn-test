#!/bin/bash

RUNTIME="docker"
SUBM_CONTAINER_NAME="${SUBM_CONTAINER_NAME:-subm-qe}"
SUBM_CONTAINER_IMAGE="${SUBM_CONTAINER_IMAGE:-quay.io/maxbab/subm-test:latest}"

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
    --runtime       - Sets runtime to be used.
                      Supported args: docker/podman
                      By default - "docker"
    --help|-h       - Print help
EOF
}

function check_container_engine() {
    if [[ "$RUNTIME" == "docker" ]]; then
        if ! [[ -x "$(command -v docker)" && -S /var/run/docker.sock ]]; then
            echo "Docker engine is not available"
            exit 1
        fi
    elif [[ "$RUNTIME" == "podman" ]]; then
        if ! [[ -x "$(command -v podman)" ]]; then
            echo "Podman engine is not available"
            exit 1
        fi
    else
        echo "Unable to locate container runtime - docker/podman"
        exit 1
    fi
    echo "Using $RUNTIME engine"
}

function start_container() {
    destroy_container

    echo "Creating $SUBM_CONTAINER_NAME test container"
    "$RUNTIME" run --name "$SUBM_CONTAINER_NAME" -t -d --network host \
        -e ANSIBLE_COLLECTIONS_PATHS=/usr/share/ansible/collections \
        -v "$(pwd)":/submariner -w /submariner \
        -e PWD="/submariner" "$SUBM_CONTAINER_IMAGE" cat
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

function parse_arguments() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --deploy)
                RUN_COMMAND="deploy"
                shift
                ;;
            --destroy)
                RUN_COMMAND="destroy"
                shift
                ;;
            --runtime)
                if [[ -n "$2" ]]; then
                    RUNTIME="$2"
                    shift 2
                else
                    echo "Runtime value was not provided"
                    exit 1
                fi
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

function main() {
    RUN_COMMAND=deploy
    parse_arguments "$@"

    case "$RUN_COMMAND" in
        deploy)
            check_container_engine
            start_container
            ;;
        destroy)
            check_container_engine
            destroy_container
            ;;
        *)
            echo "Invalid command given: $RUN_COMMAND"
            usage
            exit 1
            ;;
    esac
}

# Trigger main function
main "$@"
