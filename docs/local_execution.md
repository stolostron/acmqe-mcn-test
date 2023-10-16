# Local execution

Local execution of the pipeline could be done in two ways:
1) Containerized  
   The flow is using an image that is used during Jenkins CI pipeline execution.

   * System requirements:
     * Install Docker and ensure it is running properly on your computer.
   * Deployment preparation:
     * Prepare environment configuration file according to the [sample file](https://github.com/stolostron/ansible-collection.rhacm/blob/main/docs/config-sample.yml).
   * Perform ACM environment deployment:
     * Execute `make env-deploy CONF=/path/to/config.yml` to deploy environment.
   * Perform Submariner deployment execution:  
     Fetch the Hub `OC_CLUSTER...` details from `logs/clusters_details.yml` directory.  
     By default, aws and gcp platform defined.  
     It's possible to change any of the following parameters during submariner deployment/test:  
     Platform, Globalnet, Downstream - `make submariner-deploy SUBM_PLATFORM=value SUBM_GLOBALNET=true/false SUBM_DOWNSTREAM=true/false`
     * Execute `make submariner-deploy OC_CLUSTER_API=value OC_CLUSTER_USER=value OC_CLUSTER_PASS=value`
   * Perform Submariner test execution:  
     Fetch the Hub `OC_CLUSTER...` details from `logs/clusters_details.yml` directory.
     * Execute `make submariner-test OC_CLUSTER_API=value OC_CLUSTER_USER=value OC_CLUSTER_PASS=value`
   * Perform Submariner environment destroy:
     * Execute `make env-destroy CONF=/path/to/config.yml` to destroy environment.

2) Local python env  
   The flow will use local python to execute the pipeline.

   * Create virtual environment for python requirements and activate it:
     * `virtualenv <venv_name> && source <venv_name>/bin/activate`
   * Install python and ansible requirements:
     * `pip install -r requirements.txt`
     * `ansible-galaxy collection install -r requirements.yml`
   * Deployment preparation:
     * Prepare environment configuration file according to the [sample file](https://github.com/stolostron/ansible-collection.rhacm/blob/main/docs/config-sample.yml).
   * Perform ACM environment deployment:
     * Execute `ansible-playbook playbooks/env_deploy.yml -e @config.yml` to deploy environment.
   * Perform Submariner deployment execution:  
     Fetch the Hub `OC_CLUSTER...` details from `logs/clusters_details.yml` directory.
     * Export `OC_CLUSTER...` environment variables:
       * `export OC_CLUSTER_API=value`
       * `export OC_CLUSTER_USER=value`
       * `export OC_CLUSTER_PASS=value`
     * Execute submariner deployment:  
       By default, aws and gcp platform defined.  
       Define the following arguments as per environment requirements:  
       ``--platform`, `--globalnet`, `--downstream`
       * `./run.sh --deploy --platform aws,gcp --globalnet true --downstream true`
   * Perform Submariner test execution:  
     Fetch the Hub `OC_CLUSTER...` details from `logs/clusters_details.yml` directory.
     * Make sure the `OC_CLUSTER...` env vars are exported
     * Execute `./run.sh --test --platform aws,gcp --downstream true`
   * Perform Submariner environment destroy:
     * Execute `ansible-playbook playbooks/env_destroy.yml -e @config.yml` to destroy environment.
