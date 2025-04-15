podTemplate(yaml: readTrusted('jenkinsfiles/SubmarinerAgentPod.yaml')) {
    node(POD_LABEL) {
        checkout scm

        properties([
            parameters([
                booleanParam(name: 'GLOBALNET', defaultValue: false, description: 'Deploy Globalnet on Submariner'),
                booleanParam(name: 'DOWNSTREAM', defaultValue: true, description: 'Deploy downstream version of Submariner'),
                extendedChoice(name: 'JOB_STAGES', description: 'Select the stages of the job to be executed',
                    value: 'Deploy OCP cluster,Deploy Managed OCP,Deploy ACM Hub,Deploy Clusters by ACM,Import OCP into ACM Hub,Submariner Validate prerequisites,Submariner Deploy,Submariner Test - E2E,Submariner Test - Cypress UI,Report to Polarion',
                    defaultValue: 'Deploy OCP cluster,Deploy ACM Hub,Deploy Clusters by ACM,Submariner Validate prerequisites,Submariner Deploy,Submariner Test - E2E,Submariner Test - Cypress UI,Report to Polarion',
                    multiSelectDelimiter: ',', type: 'PT_CHECKBOX', visibleItemCount: 10),
                extendedChoice(name: 'PLATFORM', description: 'The managed clusters platform that should be tested',
                    value: 'aws,gcp,azure,vsphere,osp,aro,rosa', defaultValue: 'aws,gcp,azure', multiSelectDelimiter: ',', type: 'PT_CHECKBOX', visibleItemCount: 7),
                booleanParam(name: 'SUBMARINER_GATEWAY_RANDOM', defaultValue: true, description: 'Deploy two submariner gateways on one of the clusters'),
                string(name: 'NODE_TO_LABEL_AS_GW', defaultValue: '', description: 'Specify cluster node to be manually labeled as Submariner Gateway'),
                credentials(name: 'SUBMARINER_CONFIG', defaultValue: 'acm-2.14-subm-0.21-aws-gcp-azure2', description: 'Submariner config for environment deploy',
                    required: true, credentialType: 'org.jenkinsci.plugins.plaincredentials.impl.FileCredentialsImpl')
            ])
        ])

        container('submariner') {
            load 'jenkinsfiles/base.Jenkinsfile'
        }
    }
}