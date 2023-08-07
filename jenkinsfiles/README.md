# Submariner QE Jenkins jobs

Submariner uses jenkinsfiles to create, configure and trigger CI jobs.

The following is the description of each file related to jobs:
- `base.Jenkinsfile`  
  A base file that contains all stages for execution of the job.  
  It contains stages to deploy environment, deploy and test submariner and report tests results to Polarion.  
  This "base" file is used by other submariner jobs as a base line.

- `aws-gcp-azure.Jenkinsfile`  
  `gcp-vsphere.Jenkinsfile`  
  Specific submariner scenario job files.  
  Each file contains parameters related to specific job scenario.  
  The main parameter that differ between each scenario job, is the `SUBMARINER_CONFIG` parameter.  
  This parameter contains config file that is used by the automation.  
  Each job Jenkinsfile loads the `base.Jenkinsfile` to get the full flow of execution.

- `env-destroy.Jenkinsfile`  
  A job that destroys any environment created by the above jobs.  
  The job gets a name and a build number of required job, fetches artifacts of that job and uses them to destroy the environment.

- `SubmarinerAgentPod.yaml`  
  A file that contains config for the pod that will be used as a worker for job execution.  
  A Jenkins master is running on OpenShift cluster.  
  During execution of a new job, the `SubmarinerAgentPod.yaml` file loaded to a job and  
  used by the Jenkins master to create a Pod that will be used as a worker to execute the job.  
  After the job finishes, the pod gets destroyed.  
  The Pod is using an image that pre-created from the `Dockerfile` within the repo and stored on quay.io

- `acm-qe.Jenkinsfile`  
  A Jenkinsfile that creates and executes Submariner job on ACM-QE based jenkins server.  
  This server and jenkinsfile completely separated from the Submariner jenkins server.
