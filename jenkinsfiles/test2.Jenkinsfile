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
        extendedChoice(name: 'JOB_STAGES', description: 'Select the stages of the job to be executed',
            value: 'Deploy Base Env,Fetch Base Env job details,test2',
            defaultValue: 'Deploy Base Env,Fetch Base Env job details,test2',
            multiSelectDelimiter: ',', type: 'PT_CHECKBOX', visibleItemCount: 6)
        string(name: 'BASE_JOB_NAME', defaultValue: 'test1', description: 'Initial base job name')
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
                }
            }
        }
        stage('test2') {
            when {
                allOf {
                    expression {
                        EXECUTE_JOB == true
                    }
                    expression {
                        params.JOB_STAGES.contains(STAGE_NAME)
                    }
                }
            }
            steps {
                sh """
                ls -l
                ls -l logs/
                cat logs/test1.job
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
