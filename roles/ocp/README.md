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
    creds_type: aws
    openshift_version: "4.12"  # Optional variable to set OCP version per cluster
```

#### Clusters credentials
Credentials that should be used during openshift cluster deployment
```
clusters_credentials:
  aws:
    aws_access_key_id: <your_key_id>
    aws_secret_access_key: <your_access_key>
```

#### Openshift version
Set the version of openshift cluster to be installed.  
By default will deploy the latest stable.
```
openshift_version:
```

#### Openshift channel
The channel the should be used alongside with the version.  
Available values: 'stable', 'latest', 'candidate'.
```
openshift_channel: stable
```

#### Openshift binary name
The name of the archived binary of openshift-install.
```
openshift_install_binary: openshift-install-linux.tar.gz
```

#### Openshift install url
The url where the openshift binary should be pulled from.
```
openshift_install_url: https://mirror.openshift.com/pub/openshift-v4/clients/ocp
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
