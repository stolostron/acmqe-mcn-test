# ACM

## Description
The `acm` role prepares and deploys MultiClusterHub on a given OCP cluster.

## Role Variables
#### OCP cluster authentication details
These variables are used to authenticate and interact with cluster during MCH deployment.
```
cluster_api:
cluster_user:
cluster_pass:
```

#### ACM version
Specify the version of ACM Hub that should be deployed.  
Use the following format for the version: "2.8", "2.7".
```
acm_version: "2.8"
```

#### Snapshot
In order to deploy specific version of ACM, specify snapshot.  
Example of snapshot: `2.7.2-DOWNSTREAM-2023-03-02-21-33-34`
**Note** - If snapshot is not specified, latest snapshot for chosen version will be selected automatically by the playbook.
```
snapshot:
```

#### ACM namespace
The namespace that should be used for ACM MCH deployment.  
```
acm_namespace: open-cluster-management
```

#### Registry secrets
During deployment of downstream MultiClusterHub, an access to internal registry is required.  
For that we need to provide registry secrets.  
The secrets will be included into the main `pull-secret` secret within ocp cluster.
```
registry_secrets:
  - name: "quay.io:443"
    user: <username>
    pass: <password>
  - name: "brew.registry.redhat.io"
    user: <username>
    pass: <password>
```

#### ACM registry mirror
ACM registry that is used to fetch the downstream images from.
```
acm_registry_mirror: quay.io:443/acm-d
```

#### Registry query url
The url is used to query the registry for the latest snapshot regarding provided ACM version.
```
registry_query_url: https://quay.io/api/v1/repository/acm-d/acm-custom-registry/tag/
```

#### ACM Catalog Sources
Catalog Sources used during ACM deployment to point to specific version of ACM.  
ACM and MCE are mandatory parts of ACM deployment.
```
catalog_sources:
  - type: acm
    catalog_name: acm-custom-registry
    display_name: Advanced Cluster Management
    catalog_ns: openshift-marketplace
  - type: mce
    catalog_name: mce-custom-registry
    display_name: MultiCluster Engine
    catalog_ns: openshift-marketplace
```

***
The variables could be applied to the playbook run, by saving them into a separate yml file and include the file during the playbook execution.  
Note the '@' sign, which is used to apply the variables located within the provided file.

```
ansible-playbook playbooks/acm.yml -e @/path/to/the/variable/file.yml
```
