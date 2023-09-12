# Prerequisites

Execution of Submariner deployment and testing, requires a few conditions to met.

## Environment requirements
* ACM Hub cluster
* At least two active managed clusters
  * The clusters could be deployed by the ACM hub via hive
  * The clusters could be deployed separately and imported into the hub  
    **Note** - In that case, cluster kubeconfig and cloud creds (when required) should exists within the hub. (See section below).

## Kubeconfig for imported cluster
As part of the automation flow, kubeconfig fetched in order to perform number of configuration steps on the managed clsuters.  
When we are deploying a managed cluster from the hub, the kubeconfig of the cluster and cloud credentials of the cluster platform stored on the hub under the cluster namespace.  
As a result, the kubeconfig file easily fetched and used.

But when we are deploying a cluster separately and them importing it into the hub, the kubeconfig and cloud credentials are not stored on the hub.  
In order to allow automation flow deploy and test on the imported clusters, we should create secrets with the following content:
* A secret with kubeconfig content of the imported cluster
* A secret with cloud credentials of the platform where cluster deployed.  
  **Note** - A secret with cloud credentials required only when there is a need to create a separate instance to serve as submariner gateway. It's not the case for all the platforms.

### Create kubeconfig secret
Follow next steps to create kubeconfig secret on the Hub:
1) Encode the kubeconfig file of the cluster
```
base64 -w0 /path/to/kubeconfig/file
```
2) Create a secret file and fill up with the relevant content
```
apiVersion: v1
kind: Secret
metadata:
  name: <cluster-name>-0-admin-kubeconfig
  namespace: <cluster-name>
type: Opaque
data:
  kubeconfig: <encoded_kubeconfig_file>
```
3) Apply the created secret file on the Hub cluster
```
oc apply -f secret.yaml
```

### Create cloud credentials secret
Follow next steps to create cloud credentials secret:  
**Note 1** - The cloud credentials secret required when an instance of submariner gateway should be created.  
**Note 2** - The cloud credentials doesn't need to be created for platforms such: ROSA, ARO, IBMPower.  
**Note 3** - Cloud credentials secret values may differ according to the cloud provider.
1) Encode the username/password values
```
base64 <credentials_values>
```
2) Create a secret file and fill up with the relevant content  
   Example of AWS cloud credentials
```
apiVersion: v1
kind: Secret
metadata:
  name: <cluster-name>-<credentials-name>
  namespace: <cluster-name>
type: Opaque
data:
  aws_access_key_id: <encoded value>
  aws_secret_access_key: <encoded value>
```
3) Apply the created secret file on the Hub cluster
```
oc apply -f secret.yaml
```

## Downstream Brew registry secret
**Note** - For downstream deployment/testing only.

In order to perform downstream testing (made by QE), we need an access to internal registry - Brew.  
Follow next steps to create internal registry secret.
1) Reach ou to Submariner QE to get the guide for Brew credentials creation
2) Login to the ACM Hub cluster
3) Fetch exiting `pull-secret` secret and write it to a `pull_secret.yaml` file
```
oc -n openshift-config get secret/pull-secret --template='{{index .data ".dockerconfigjson" | base64decode}}' > pull_secret.yaml
```
4) Update the `pull_secret.yaml` file with the brew registry credentials from the first step
```
oc registry login --registry="brew.registry.redhat.io" --auth-basic="<username>:<password>" --to=pull_secret.yaml
```
5) Update the Hub cluster `pull-secret` with the updated values
```
oc -n openshift-config set data secret/pull-secret --from-file=.dockerconfigjson=pull_secret.yaml
```
6) Delete the `pull_secret.yaml` file
```
rm pull_secret.yaml
```
