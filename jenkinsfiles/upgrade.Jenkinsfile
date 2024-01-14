pipeline {
    agent {
        kubernetes {
            defaultContainer 'submariner'
            yamlFile 'jenkinsfiles/SubmarinerAgentPod.yaml'
        }
    }
    options {
        ansiColor('xterm')
        buildDiscarder(logRotator(daysToKeepStr: '30'))
        timeout(time: 8, unit: 'HOURS')
    }
    parameters {
        string(name: 'OC_CLUSTER_API', defaultValue: '', description: 'ACM Hub API URL')
        string(name: 'OC_CLUSTER_USER', defaultValue: '', description: 'ACM Hub username')
        string(name: 'OC_CLUSTER_PASS', defaultValue: '', description: 'ACM Hub password')
        extendedChoice(name: 'JOB_STAGES', description: 'Select the stages of the job to be executed',
            value: 'Deploy Base Env,Fetch Base Env job details,Upgrade,Submariner Test - E2E,Submariner Test - Cypress UI,Report to Polarion',
            defaultValue: 'Deploy Base Env,Fetch Base Env job details,Upgrade,Submariner Test - E2E,Submariner Test - Cypress UI,Report to Polarion',
            multiSelectDelimiter: ',', type: 'PT_CHECKBOX', visibleItemCount: 6)
        extendedChoice(name: 'PLATFORM', description: 'The managed clusters platform that should be tested',
            value: 'aws,gcp,azure', defaultValue: 'aws,gcp,azure', multiSelectDelimiter: ',', type: 'PT_CHECKBOX', visibleItemCount: 3)
        string(name: 'BASE_JOB_NAME', defaultValue: 'ACM-2.6-Submariner-0.13-AWS-GCP-Azure', description: 'Initial base job name')
    }
    environment {
        // The secret contains polarion authentication
        // and other details for report publish
        POLARION_SECRET = credentials('submariner-polarion-secret')
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
                    EXECUTE_JOB = true
                    SKIP_BASE_ENV_DEPLOY = false
                    if (params.OC_CLUSTER_API != '' &&
                        params.OC_CLUSTER_USER != '' &&
                        params.OC_CLUSTER_PASS != '') {
                            env.OC_CLUSTER_API = params.OC_CLUSTER_API
                            env.OC_CLUSTER_USER = params.OC_CLUSTER_USER
                            env.OC_CLUSTER_PASS = params.OC_CLUSTER_PASS
                            SKIP_BASE_ENV_DEPLOY = true
                    }
                }
            }
        }
        stage('Deploy Base Env') {
            when {
                allOf {
                    expression {
                        params.JOB_STAGES.contains(STAGE_NAME)
                    }
                    expression {
                        SKIP_BASE_ENV_DEPLOY == false
                    }
                }
            }
            steps {
                script {
                    def buildResult = build propagate: false, job: "${BASE_JOB_NAME}"
                    def buildNumber = buildResult.getNumber()
                    env.jobBuildNumber = buildNumber

                    def buildState = buildResult.result
                    if (buildState == 'FAILURE') {
                        println("Deploy Base Env job failed. Skipping the job...")
                        EXECUTE_JOB = false
                        currentBuild.result = 'NOT_BUILT'
                    }
                }
            }
        }
        stage('Fetch Base Env job details') {
            when {
                allOf {
                    expression {
                        params.JOB_STAGES.contains(STAGE_NAME)
                    }
                    expression {
                        SKIP_BASE_ENV_DEPLOY == false
                    }
                }
            }
            steps {
                script {
                    try {
                        step ([$class: 'CopyArtifact',
                            projectName: "${BASE_JOB_NAME}",
                            selector: specific("${jobBuildNumber}"),
                            filter: "logs/",
                            flatten: false]);
                    }
                    catch (exc) {
                        echo 'Failed to fetch config for the specified job'
                        throw new Exception("Job cannot continue without config information from deployment pipeline")
                    }

                    env.OC_CLUSTER_API = sh(
                        script: "yq eval '.[].api' logs/clusters_details.yml | head -1",
                        returnStdout: true).trim()
                    env.OC_CLUSTER_PASS = sh(
                        script: "yq eval '.[].pass' logs/clusters_details.yml | head -1",
                        returnStdout: true).trim()
                    env.OC_CLUSTER_USER = "kubeadmin"
                }
            }
        }
        stage('Upgrade') {
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
                ./run.sh --upgrade --platform "${params.PLATFORM}" --downstream true
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
                sh """
                ./run.sh --test --test-type e2e --platform "${params.PLATFORM}" --downstream true --report-suffix upgrade
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
                sh """
                ./run.sh --test --test-type ui --platform "${params.PLATFORM}" --downstream true --report-suffix upgrade
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
