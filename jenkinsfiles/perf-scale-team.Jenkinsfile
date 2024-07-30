podTemplate(yaml: readTrusted('jenkinsfiles/SubmarinerAgentPod.yaml')) {
    node(POD_LABEL) {
        checkout scm

        properties([
            parameters([
                booleanParam(name: 'GLOBALNET', defaultValue: true, description: 'Deploy Globalnet on Submariner'),
                booleanParam(name: 'DOWNSTREAM', defaultValue: true, description: 'Deploy downstream version of Submariner'),
                extendedChoice(name: 'JOB_STAGES', description: 'Select the stages of the job to be executed',
                    value: 'Deploy OCP cluster,Deploy Managed OCP,Deploy ACM Hub,Deploy Clusters by ACM,Import OCP into ACM Hub,Submariner Validate prerequisites,Submariner Deploy',
                    defaultValue: 'Deploy Managed OCP,Deploy ACM Hub,Import OCP into ACM Hub,Submariner Validate prerequisites,Submariner Deploy',
                    multiSelectDelimiter: ',', type: 'PT_CHECKBOX', visibleItemCount: 10),
                extendedChoice(name: 'PLATFORM', description: 'The managed clusters platform that should be tested',
                    value: 'aws,gcp,azure,vsphere,osp,aro,rosa', defaultValue: 'rosa', multiSelectDelimiter: ',', type: 'PT_CHECKBOX', visibleItemCount: 7),
                string(name: 'NODE_TO_LABEL_AS_GW', defaultValue: '', description: 'Specify cluster node to be manually labeled as Submariner Gateway'),
                credentials(name: 'SUBMARINER_CONFIG', defaultValue: 'perf-scale-team-acm-2.10-subm-0.17-rosa', description: 'Submariner config for environment deploy',
                    required: true, credentialType: 'org.jenkinsci.plugins.plaincredentials.impl.FileCredentialsImpl')
            ])
        ])

        container('submariner') {
            load 'jenkinsfiles/base.Jenkinsfile'
        }
    }
}
