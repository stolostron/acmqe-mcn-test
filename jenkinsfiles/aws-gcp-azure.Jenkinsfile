podTemplate(yaml: readTrusted('jenkinsfiles/SubmarinerAgentPod.yaml')) {
    node(POD_LABEL) {
        checkout scm

        properties([
            parameters([
                extendedChoice(name: 'JOB_STAGES', description: 'Select the stages of the job to be executed',
                    value: 'Deploy OCP cluster,Deploy ACM Hub,Deploy Clusters by ACM,Deploy Managed OCP,Import OCP into ACM Hub,Submariner Validate prerequisites,Submariner Deploy,Submariner Test - E2E,Submariner Test - Cypress UI,Report to Polarion',
                    defaultValue: 'Deploy OCP cluster,Deploy ACM Hub,Deploy Clusters by ACM,Submariner Validate prerequisites,Submariner Deploy,Submariner Test - E2E,Submariner Test - Cypress UI,Report to Polarion',
                    multiSelectDelimiter: ',', type: 'PT_CHECKBOX', visibleItemCount: 10),
                credentials(name: 'SUBMARINER_CONFIG', defaultValue: 'acm-2.9-subm-0.16-aws-gcp-azure', description: 'Submariner config for environment deploy',
                    required: true, credentialType: 'org.jenkinsci.plugins.plaincredentials.impl.FileCredentialsImpl')
            ])
        ])

        container('submariner') {
            load 'jenkinsfiles/base.Jenkinsfile'
        }
    }
}
