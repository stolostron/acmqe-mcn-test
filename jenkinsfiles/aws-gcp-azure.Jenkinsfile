podTemplate(yaml: readTrusted('jenkinsfiles/SubmarinerAgentPod.yaml')) {
    node(POD_LABEL) {
        checkout scm
        
        properties([
            parameters([
                booleanParam(name: 'GLOBALNET', defaultValue: false, description: 'Deploy Globalnet on Submariner'),
                booleanParam(name: 'DOWNSTREAM', defaultValue: true, description: 'Deploy downstream version of Submariner'),
                [$class: 'ChoiceParameter',
                    choiceType: 'PT_CHECKBOX',
                    name: 'JOB_STAGES',
                    description: 'Select the stages of the job to be executed',
                    filterable: false,
                    filterLength: 1,
                    script: [
                        $class: 'GroovyScript',
                        fallbackScript: [
                            classpath: [],
                            sandbox: true,
                            script: 'return ["ERROR"]'
                        ],
                        script: [
                            classpath: [],
                            sandbox: true,
                            script: '''
                                return [
                                    'Deploy OCP cluster:selected',
                                    'Deploy Managed OCP',
                                    'Deploy ACM Hub:selected',
                                    'Deploy Clusters by ACM:selected',
                                    'Import OCP into ACM Hub',
                                    'Submariner Validate prerequisites:selected',
                                    'Submariner Deploy:selected',
                                    'Submariner Test - E2E:selected',
                                    'Submariner Test - Cypress UI:selected',
                                    'Report to Polarion:selected'
                                ]
                            '''
                        ]
                    ]
                ],
                [$class: 'ChoiceParameter',
                    choiceType: 'PT_CHECKBOX',
                    name: 'PLATFORM',
                    description: 'The managed clusters platform that should be tested',
                    filterable: false,
                    filterLength: 1,
                    script: [
                        $class: 'GroovyScript',
                        fallbackScript: [
                            classpath: [],
                            sandbox: true,
                            script: 'return ["ERROR"]'
                        ],
                        script: [
                            classpath: [],
                            sandbox: true,
                            script: '''
                                return [
                                    'aws:selected',
                                    'gcp:selected',
                                    'azure:selected',
                                    'vsphere',
                                    'osp',
                                    'aro',
                                    'rosa'
                                ]
                            '''
                        ]
                    ]
                ],
                booleanParam(name: 'SUBMARINER_GATEWAY_RANDOM', defaultValue: true, description: 'Deploy two submariner gateways on one of the clusters'),
                string(name: 'NODE_TO_LABEL_AS_GW', defaultValue: '', description: 'Specify cluster node to be manually labeled as Submariner Gateway'),
                string(name: 'FBC_URL_4_19', defaultValue: '', description: 'FBC (File-Based Catalog) image URL for OCP 4.15'),
                string(name: 'FBC_URL_4_20', defaultValue: '', description: 'FBC (File-Based Catalog) image URL for OCP 4.16'),
                string(name: 'FBC_URL_4_21', defaultValue: '', description: 'FBC (File-Based Catalog) image URL for OCP 4.17'),
                string(name: 'FBC_URL_4_22', defaultValue: '', description: 'FBC (File-Based Catalog) image URL for OCP 4.18'),
                string(name: 'SUBCTL_DOWNLOAD_URL', defaultValue: '', description: 'Subctl container image URL (required)'),
                credentials(name: 'SUBMARINER_CONFIG', defaultValue: 'acm-2.17-subm-0.24-aws-gcp-azure', description: 'Submariner config for environment deploy',
                    required: true, credentialType: 'org.jenkinsci.plugins.plaincredentials.impl.FileCredentialsImpl')
            ])
        ])

        container('submariner') {
            load 'jenkinsfiles/base.Jenkinsfile'
        }
    }
}