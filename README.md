# Submariner deployment and testing in Advanced Cluster Management (ACM) environment

## Overview
The repository contains the following flows:
* Deploy ACM based environment according to the user input.
* Deploy Submariner on ACM
* Test Submariner
* Report Tests results (used by QE)

## Prerequisites
**Note** - Execution of Submariner addon deployment and testing, requires the following:
* ACM Hub cluster
* At least two active managed clusters
  * The clusters could be deployed by the ACM hub
  * The clusters could be deployed separately and imported into the hub  
    **Note** - In case clusters were created separately and imported, ensure cluster and cloud credentials exists within the hub.

**Note** - If any requirement is missing, the flow will fail with relevant error message.


* In case required environment already exists, skip to the next section.
* In case environment needs to be deployed, review the **ACM environment deployment** section.

### ACM environment deployment
Fully ACM based environment could be deployed by using the [stolostron.rhacm](https://github.com/stolostron/ansible-collection.rhacm) collection.  
Refer to the local execution flow [doc](docs/local_execution.md) for the details.

## Supported platforms
The following clusters platforms are supported by the Submariner Addon deployment and test:
- [X] AWS
- [X] GCP
- [X] Azure
- [ ] OSP

The user is able to define manually which platforms should be deployed and tested.  
Multiple platforms should be separated by a comma.

## ACM Hub and Submariner versions
Before deployment execution, switch to the relevant branch - release-2.6, release-2.7, etc...

| ACM Hub | Submariner |
|---------|------------|
| 2.5.x   | 0.12.x     |

## Execution
Execution of deployment, testing and reporting requires connection details to the ACM HUB cluster.  
The details should be provided as environment variables.  
The execution of the flow is done by providing a main argument followed by an optional arguments.

Example:

```bash
export OC_CLUSTER_API=<hub cluster api url>
export OC_CLUSTER_USER=<cluster user name (kubeadmin)>
export OC_CLUSTER_PASS=<password of the cluster user>

./run.sh --deploy --platform aws,gcp --downstream true --globalnet true
```

### Command arguments
```
    Main arguments:
    -----------------
    --all                  - Perform deployment and testing of the Submariner addon

    --deploy               - Perform deployment of the Submariner addon

    --test                 - Perform testing of the Submariner addon

    --report               - Report tests results to Polarion

    --gather-logs          - Gather debug info and logs for environment

    --validate-prereq      - Perform prerequisites validation of the environment
                             before deployment.
                             The validation will consist of the following checks:
                             - Verify ACM hub credentials
                             - Verify at least two clusters available from provided platforms
                             This is used by the ci flow to not fail the job if provided
                             environment is not ready.
                             The state will be written to validation_state.log file
                             and will not fail the flow.

    Submariner deployment arguments:
    --------------------------------
    --platform             - Specify the platforms that should be used for testing
                             Separate multiple platforms by comma
                             (Optional)
                             By default - aws,gcp

    --downstream           - Use the flag if downstream images should be used.
                             Submariner images could be sourced from two places:
                               * Official Red Hat ragistry - registry.redhat.io
                               * Downstream Quay registry - brew.registry.redhat.io
                             (Optional)
                             By default - false

    --mirror               - Use local ocp registry.
                             Due to https://issues.redhat.com/browse/RFE-1608,
                             local ocp registry is required.
                             The images are imported and used from the local registry.
                             (Optional) (true/false)
                             By default - true
                             The flag is used only with "--downstream" flag.
                             Otherwise, ignored.

    --skip-gather-logs     - Specify if logs gathering should be skipped.
                             The gathering will be done on all submariner configs.
                             (Optional)
                             By default - false

    Submariner configuration arguments:
    -----------------------------------
    --globalnet            - Set the state of the Globalnet for the Submariner deployment.
                             The globalnet configuration will be applied starting from
                             ACM version 2.5.0 and Submariner 0.12.0
                             (Optional)
                             By default - false

    --subm-ipsec-natt-port - IPSecNATTPort represents IPsec NAT-T port.
                             (Optional)
                             Submariner default - 4500.
                             Deployment default - 4505.

    --subm-cable-driver    - CableDriver represents the submariner cable driver implementation.
                             Available options are libreswan (default) strongswan, wireguard,
                             and vxlan.
                             (Optional)

    --subm-gateway-count   - Gateways represents the count of worker nodes that will be used
                             to deploy the Submariner gateway component on the managed cluster.
                             The default value is 1, if the value is greater than 1,
                             the Submariner gateway HA will be enabled automatically.
                             (Optional)

    --subm-gateway-random  - Set the deployment flow to randomize the gateway deployment
                             between clusters. When used, the flow will deploy 2 gateway nodes
                             on the first cluster and 1 gateway node on all other clusters.
                             Used by the internal QE flow to test random states of gateways.
                             Note - The use of this flag will ignore the "--subm-gateway-count"
                             flag.
                             (Optional)
                             By default - false

    Reporting arguments:
    --------------------
    --polarion-vars-file   - A path to the file that contains Polarion details.
                             Internal only (used by QE)
                             (Optional)
                             The file should contains the following variables:
                             """
                             [polarion_auth]
                             server = <polarion_server_url>
                             user = <polarion_user>
                             pass = <polarion_pass>

                             [polarion_team_config]
                             project_id = <project_id_name>
                             component_id = <component_name>
                             team_name = <team_name>
                             testrun_template = <testrun_template_name>
                             """
                             Alternatively, those environment variables could be exported.

    --polarion_add_skipped - Add skipped tests to polarion report.
                             Will deplay junit skipped tests as "Waiting" in Polarion (i.e. test not run yet)
                             Internal only (used by QE)
                             (Optional)
                             By default - false

    --help|-h     - Print help
```

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

## Report (QE internal)
The reports of tests results are made to the Polarion system.  
Report flow will generate the `testcases` and `testruns` xml files based on the junit file.  
The generated files will be pushed into the Polarion to update the state of the testing.

### Polarion input file
In order to make an update of the tests state in Polarion, additional details should be provided.  
Provided details could be exported as environment variables or provided as a text based file.

```
[polarion_auth]
server = <polarion_server_url>
user = <polarion_user>
pass = <polarion_pass>

[polarion_team_config]
project_id = <project_id_name>
component_id = <component_name>
team_name = <team_name>
testrun_template = <testrun_template_name>
```
