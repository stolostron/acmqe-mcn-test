# Submariner addon deployment and testing in ACM Hub environment

## Overview
The repo is used to deploy and test the Submariner addon in ACM environment.

## Run
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

## Prerequisites
**Note** - Execution of Submariner addon deployment and testing, requires the following:
* Pre installed ACM Hub cluster
* At least two managed clusters deployed by the ACM cluster
