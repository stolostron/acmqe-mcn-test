# Managed Cluster

## Description
The `managed_cluster` role prepares and deploys Managed Clusters on a Hub cluster.

## Role Variables
#### State
State of the managed clusters. Could be "present" or "absent".
```
state: present
```

#### OpenShift pull secret
The pull secret is used to authenticate with the services that are provided by the included authorities, `Quay.io` and `registry.redhat.io`, which serve the container images for OpenShift Container Platform components.  
Use the following link to obtain the pull-secret - https://console.redhat.com/openshift/install/pull-secret  
The variable is mandatory.
```
pull_secret:
```

#### SSH Public key
The ssh public key pushed to the cluster nodes during deploy and used to access the nodes.  
The variable is mandatory.
```
ssh_pub_key:
```

#### Managed clusters
Defines managed clusters that should be deployed on the Hub.
**Note** - For more provides and override options, refer to `config-sample.yml` file.
```
managed_clusters:
  - name: cluster1
    credentials: cluster1-creds
    platform: aws
    region: us-east-2
    network:
      cluster: 10.128.0.0/14
      machine: 10.0.0.0/16
      service: 172.30.0.0/16
      type: OVNKubernetes
    managed_cluster_image: quay.io/openshift-release-dev/ocp-release:4.12.7-multi
```

#### Clusters credentials
Define credentials that will be used by the managed clusters during creation.
**Note** - For more provides and override options, refer to `config-sample.yml` file.
```
managed_clusters_credentials:
  - name: cluster1-creds
    platform: aws
    namespace: open-cluster-management-hub
    base_domain:
    aws_access_key_id:
    aws_secret_access_key:
```

***
The variables could be applied to the playbook run, by saving them into a separate yml file and include the file during the playbook execution.  
Note the '@' sign, which is used to apply the variables located within the provided file.

```
ansible-playbook playbooks/managed_cluster.yml -e @/path/to/the/variable/file.yml
```
