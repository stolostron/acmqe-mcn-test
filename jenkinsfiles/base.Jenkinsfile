pipeline {
    agent none
    // Agent definition is not used here as it's defined
    // by the jenkinsfile that loads this file.
    // agent {
    //     kubernetes {
    //         defaultContainer 'submariner'
    //         yamlFile 'jenkinsfiles/SubmarinerAgentPod.yaml'
    //     }
    // }
    options {
        ansiColor('xterm')
        buildDiscarder(logRotator(daysToKeepStr: '30'))
        timeout(time: 8, unit: 'HOURS')
    }
    parameters {
        string(name: 'OC_CLUSTER_API', defaultValue: '', description: 'ACM Hub API URL')
        string(name: 'OC_CLUSTER_USER', defaultValue: '', description: 'ACM Hub username')
        string(name: 'OC_CLUSTER_PASS', defaultValue: '', description: 'ACM Hub password')
        extendedChoice(name: 'PLATFORM', description: 'The managed clusters platform that should be tested',
            value: 'aws,gcp,azure,vsphere,osp,aro,rosa', defaultValue: 'aws,gcp,azure,vsphere,osp,aro,rosa', multiSelectDelimiter: ',', type: 'PT_CHECKBOX', visibleItemCount: 7)
        booleanParam(name: 'SUBMARINER_GATEWAY_RANDOM', defaultValue: true, description: 'Deploy two submariner gateways on one of the clusters')
    }
    environment {
        // Parameter will be used to disable globalnet in
        // ACM version below 2.5.0 as it's not supported
        GLOBALNET_TRIGGER = true
        // The secret contains polarion authentication
        // and other details for report publish
        POLARION_SECRET = credentials('submariner-polarion-secret')
        SUBMARINER_CONF = credentials('SUBMARINER_CONFIG')
        // Credentials for the registry.redhat.io
        RH_REG = credentials('submariner-rh-registry')
    }
    stages {
        // Environment vars defined within "environment" block
        // could not be overriden to be used across stages sh block.
        // Current flow could get OC_CLUSTER... var as parameter defined
        // by the user at job trigger or be defined later after cluster creation.
        // In order to be defined later and be able to override the env var,
        // we use init of env vars within stage.
        stage('Init env params') {
            steps {
                script {
                    if (params.OC_CLUSTER_API != '' &&
                        params.OC_CLUSTER_USER != '' &&
                        params.OC_CLUSTER_PASS != '') {
                            env.OC_CLUSTER_API = params.OC_CLUSTER_API
                            env.OC_CLUSTER_USER = params.OC_CLUSTER_USER
                            env.OC_CLUSTER_PASS = params.OC_CLUSTER_PASS
                    }
                }
            }
        }
        stage('Deploy OCP cluster') {
            when {
                expression {
                    params.JOB_STAGES.contains(STAGE_NAME)
                }
            }
            steps {
                script {
                    if (env.OC_CLUSTER_API == '' &&
                        env.OC_CLUSTER_USER == '' &&
                        env.OC_CLUSTER_PASS == '') {
                            println "OCP cluster deploy"
                            sh """
                            ansible-playbook -v playbooks/ci/ocp.yml -e @"${SUBMARINER_CONF}"
                            """

                            env.OC_CLUSTER_API = sh(
                                script: "yq eval '.[].api' logs/clusters_details.yml | head -1",
                                returnStdout: true).trim()
                            env.OC_CLUSTER_PASS = sh(
                                script: "yq eval '.[].pass' logs/clusters_details.yml | head -1",
                                returnStdout: true).trim()
                            env.OC_CLUSTER_USER = "kubeadmin"
                    } else {
                        println "OCP cluster details has been provided externally. Skipping creation..."
                    }
                }
            }
        }
        stage('Deploy ACM Hub') {
            when {
                expression {
                    params.JOB_STAGES.contains(STAGE_NAME)
                }
            }
            steps {
                sh """
                ansible-playbook -v playbooks/ci/acm.yml -e @"${SUBMARINER_CONF}"
                """
            }
        }
        stage('Deploy Clusters by ACM') {
            when {
                expression {
                    params.JOB_STAGES.contains(STAGE_NAME)
                }
            }
            steps {
                sh """
                ansible-playbook -v playbooks/ci/acm_hive_cluster.yml -e @"${SUBMARINER_CONF}"
                """
            }
        }
        stage('Deploy Managed OCP') {
            when {
                expression {
                    params.JOB_STAGES.contains(STAGE_NAME)
                }
            }
            steps {
                sh """
                ansible-playbook -v playbooks/ci/managed_openshift.yml -e @"${SUBMARINER_CONF}"
                """
            }
        }
        stage('Import OCP into ACM Hub') {
            when {
                expression {
                    params.JOB_STAGES.contains(STAGE_NAME)
                }
            }
            steps {
                sh """
                ansible-playbook -v playbooks/ci/acm_import_cluster.yml -e @"${SUBMARINER_CONF}"
                """
            }
        }
        // This stage will validate the environment for the job.
        // If the prerequisites will not met, the job will not be
        // executed to avoid non submariner job failures.
        stage('Submariner Validate prerequisites') {
            when {
                expression {
                    params.JOB_STAGES.contains(STAGE_NAME)
                }
            }
            steps {
                sh """
                ./run.sh --validate-prereq --platform "${params.PLATFORM}"
                """

                script {
                    def state = readFile(file: 'validation_state.log')
                    println(state)
                    // If validation_state.log file contains string "Not ready!",
                    // meaning environment prerequisites are not ready.
                    // The job will not be executed.
                    if (state.contains('Not ready!')) {
                        EXECUTE_JOB = false
                        currentBuild.result = 'NOT_BUILT'
                    } else {
                        EXECUTE_JOB = true
                    }

                    def mch_ver = readFile(file: 'mch_version.log')
                    println("MultiClusterHub version: " + mch_ver)
                    mch_ver_major = mch_ver.split('\\.')[0] as Integer
                    mch_ver_minor = mch_ver.split('\\.')[1] as Integer

                    // Checks the version of the MultiClusterHub
                    // If the version is below 2.5.0, globalnet
                    // is not supported - disable it.
                    // Otherwise, use parameter definition.
                    globalnet_ver = '2.5'
                    globalnet_ver_major = globalnet_ver.split('\\.')[0] as Integer
                    globalnet_ver_minor = globalnet_ver.split('\\.')[1] as Integer
                    if (mch_ver_major < globalnet_ver_major ||
                        mch_ver_minor < globalnet_ver_minor) {
                            println("Disable Globalnet as it's not supported in ACM " + mch_ver)
                            GLOBALNET_TRIGGER = false
                        }
                }
            }
        }
        stage('Submariner Deploy') {
            when {
                allOf {
                    expression {
                        params.JOB_STAGES.contains(STAGE_NAME)
                    }
                    expression {
                        EXECUTE_JOB == true
                    }
                }
            }
            steps {
                script {
                    GLOBALNET = "--globalnet ${params.GLOBALNET}"
                    // The "GLOBALNET_TRIGGER" will be used as a
                    // control point to for ACM versions below 2.5.0
                    // As it's not supported.
                    if (GLOBALNET_TRIGGER.toBoolean() == false) {
                        GLOBALNET = "--globalnet false"
                    }

                    DOWNSTREAM = "--downstream false"
                    if (params.DOWNSTREAM) {
                        DOWNSTREAM = "--downstream true"
                    }

                    // Deploy two submariner gateways on one of the clusters
                    // to test submariner gateway fail-over scenario.
                    SUBMARINER_GATEWAY_RANDOM = "--subm-gateway-random false"
                    if (params.SUBMARINER_GATEWAY_RANDOM) {
                        SUBMARINER_GATEWAY_RANDOM = "--subm-gateway-random true"
                    }

                    NODE_TO_LABEL_AS_GW = ""
                    if (params.NODE_TO_LABEL_AS_GW != '') {
                        NODE_TO_LABEL_AS_GW = "--subm-label-gw-node ${params.NODE_TO_LABEL_AS_GW}"
                    }
                }

                sh """
                ./run.sh --deploy --platform "${params.PLATFORM}" $GLOBALNET $DOWNSTREAM $SUBMARINER_GATEWAY_RANDOM $NODE_TO_LABEL_AS_GW
                """
            }
        }
        stage('Submariner Test - E2E') {
            when {
                allOf {
                    expression {
                        params.JOB_STAGES.contains(STAGE_NAME)
                    }
                    expression {
                        EXECUTE_JOB == true
                    }
                }
            }
            steps {
                script {
                    DOWNSTREAM = "--downstream false"
                    if (params.DOWNSTREAM) {
                        DOWNSTREAM = "--downstream true"
                    }
                }

                sh """
                ./run.sh --test --test-type e2e --platform "${params.PLATFORM}" $DOWNSTREAM
                """
            }
        }
        stage('Submariner Test - Cypress UI') {
            when {
                allOf {
                    expression {
                        params.JOB_STAGES.contains(STAGE_NAME)
                    }
                    expression {
                        EXECUTE_JOB == true
                    }
                }
            }
            steps {
                script {
                    DOWNSTREAM = "--downstream false"
                    if (params.DOWNSTREAM) {
                        DOWNSTREAM = "--downstream true"
                    }
                }

                sh """
                ./run.sh --test --test-type ui --platform "${params.PLATFORM}" $DOWNSTREAM
                """
            }
        }
        stage('Report to Polarion') {
            when {
                allOf {
                    expression {
                        params.JOB_STAGES.contains(STAGE_NAME)
                    }
                    expression {
                        EXECUTE_JOB == true
                    }
                }
            }
            steps {
                sh """
                ./run.sh --report --polarion-vars-file "${POLARION_SECRET}"
                """
            }
        }
    }
    post {
        always {
            archiveArtifacts artifacts: "logs/**", followSymlinks: false, allowEmptyArchive: true
            junit allowEmptyResults: true, testResults: "logs/**/**/*junit.xml"
        }
    }
}
