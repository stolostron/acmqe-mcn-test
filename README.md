# Submariner addon deployment and testing in ACM Hub environment

## Overview
The repo is used to deploy and test the Submariner addon in ACM environment.

## Prerequisites
**Note** - Execution of Submariner addon deployment and testing, requires the following:
* Pre installed ACM Hub cluster
* At least two managed clusters deployed by the ACM cluster

**Note** - If any requirement is missing, the test flow will fail with relevant message.

## Execute
Execution of deployment and testing requires connection details of the ACM HUB cluster.  
The details should be provided as environment variables.

The script could deploy and test all at once or separate the stages.

```bash
# Execute Submariner addon deployment and test
export OC_CLUSTER_URL=<hub cluster url>
export OC_CLUSTER_USER=<cluster user name (kubeadmin)>
export OC_CLUSTER_PASS=<password of the cluster user>

./run.sh --all
```

```bash
# Execute Submariner addon deployment
export OC_CLUSTER_URL=<hub cluster url>
export OC_CLUSTER_USER=<cluster user name (kubeadmin)>
export OC_CLUSTER_PASS=<password of the cluster user>

./run.sh --deploy
```

```bash
# Execute Submariner addon tests
export OC_CLUSTER_URL=<hub cluster url>
export OC_CLUSTER_USER=<cluster user name (kubeadmin)>
export OC_CLUSTER_PASS=<password of the cluster user>

./run.sh --test
```

## Testing platforms
The following clusters platforms are supported by the Submariner Addon deployment and test:
- [X] AWS
- [X] GCP
- [ ] Azure
- [ ] VMware
- [ ] OSP

The user is able to define manually which platforms should be deployed and tested.

```bash
export OC_CLUSTER_URL=<hub cluster url>
export OC_CLUSTER_USER=<cluster user name (kubeadmin)>
export OC_CLUSTER_PASS=<password of the cluster user>

./run.sh --all --platform gcp
```

Default - aws and gcp.  
Multiple platforms should be separated by comma:

```bash
./run.sh --test --platform aws,gcp
```

Provided platform will be searched and tested.  
If one of the provided platforms does not exist, deployment and test will continue  
with the existing platforms, but after the tests execution, the flow will fail with  
an error message that one of the requested platforms was not found.

```bash
./run.sh --deploy --downstream
```

Downstream flag will perform submariner deployment from brew.registry.redhat.io.  
**Note** - Brew secret should exists for this deployment.

```bash
./run.sh --deploy --version 0.11.1
```

Specify the Submariner version that needs to be deployed.  
Specified version will be verified against supported versions.

## Tests
Submariner addon testing performed by using the `subctl` command.  
The tools will be downloaded during the testing to the executors machine.

The following test phases will be done:

| Command                                  | Description                                                                               |
| ---------------------------------------- | ----------------------------------------------------------------------------------------- |
| `subctl show all`                        | Shows the aggregated information of versions, networks, gateways, connections, endpoints  |
| `subctl diagnose all`                    | Execute diagnostic checks to find possible issues or misconfigurations                    |
| `subctl diagnose firewall inter-cluster` | Checks if the firewall configuration allows tunnels to be configured on the Gateway nodes |
| `subctl verify`                          | Execute E2E tests to verify proper Submariner functionality                               |

For more information refer to the Submariner documentation - https://submariner.io/operations/deployment/subctl/

**Note** - The `subctl` tool is able to perform testing between two clusters only at the same time.  
In case multiple clusters exist under the ACM Hub management, the testing step will perform the following flow:  
* First cluster will be defined as the main cluster for the testing.
* All other clusters will be looped and tested against the "main" testing cluster.

All the testing information, in additional to the `kubeconfig` files of the managed clusters  
will be saved on the executors machine in a directory called `tests_logs`,  
which will be created during tests execution.
