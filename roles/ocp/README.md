# OCP

## Description
The `ocp` role creates or destroys OpenShift based clusters.  
The role will generate the `install-config.yaml` file based on the user input and will run the creation of the cluster by using the official `openshift-install` binary.

## Role default variables
#### State of the cluster
Create or destroy the cluster.  
The state could be 'present' or 'absent'.
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

#### Clusters deployment details
Provide the details of the clusters that needs to be deployed.
```
clusters:
  - name: test-cluster
    base_domain: example.com
    network:
      cluster: 10.128.0.0/14
      machine: 10.0.0.0/16
      service: 172.30.0.0/16
      type: OVNKubernetes
    cloud:
      platform: aws
      region: us-east-2
      instance_type: m5.xlarge
```

#### OpenShift version
Install OpenShift cluster version by fetching the relevant `openshift-install` binary.  
By default, will use latest stable version.
```
openshift_install: https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-install-linux.tar.gz
```

#### OCP assets directory
Specifies the directory where the cluster assets (configuration) files will be stored.  
These files are required to later destroy the clusters.  
```
ocp_assets_dir: logs/ocp_assets
```

***
The variables could be applied to the playbook run, by saving them into a separate yml file and include the file during the playbook execution.  
Note the '@' sign, which is used to apply the variables located within the provided file.

```
ansible-playbook playbooks/ocp.yml -e @/path/to/the/variable/file.yml
```
