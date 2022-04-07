pipeline {
    agent {
        docker {
            image 'quay.io/generic/rhel8'
            args '--network host -u 0:0'
        }
    }
    options {
        ansiColor('xterm')
    }
    parameters {
        string(name: 'OC_CLUSTER_URL', defaultValue: '', description: 'ACM Hub API URL')
        string(name: 'OC_CLUSTER_USER', defaultValue: '', description: 'ACM Hub username')
        string(name: 'OC_CLUSTER_PASS', defaultValue: '', description: 'ACM Hub password')
        extendedChoice(name: 'PLATFORM', description: 'The managed clusters platform that should be tested',
            value: 'aws,gcp', defaultValue: 'aws,gcp', multiSelectDelimiter: ',', type: 'PT_CHECKBOX')
        booleanParam(name: 'GLOBALNET', defaultValue: false, description: 'Deploy Globalnet on Submariner')
        string(name: 'VERSION', defaultValue: '', description: 'Define specific version of Submariner to be installed')
        booleanParam(name: 'DOWNSTREAM', defaultValue: true, description: 'Deploy downstream version of Submariner')
        string(name:'TEST_TAGS', defaultValue: '', description: 'A tag to control job execution')
    }
    environment {
        EXECUTE_JOB = false
        OC_CLUSTER_URL = "${params.OC_CLUSTER_URL}"
        OC_CLUSTER_USER = "${params.OC_CLUSTER_USER}"
        OC_CLUSTER_PASS = "${params.OC_CLUSTER_PASS}"
    }
    stages {
        // This stage will validate the environment for the job.
        // If the prerequisites will not met, the job will not be
        // executed to avoid non submariner job failures.
        stage('Validate prerequisites') {
            when {
                anyOf {
                    // The job flow will be executed only if TEST_TAGS parameter
                    // will be empty or definited with the values below.
                    // The last two values are used by the acm qe ci.
                    environment name: 'TEST_TAGS', value: ''
                    environment name: 'TEST_TAGS', value: '@e2e'
                    environment name: 'TEST_TAGS', value: '@Submariner'
                }
            }
            steps {
                sh """
                ./run.sh --validate-prereq
                """

                script {
                    def result = readFile(file: 'validation_state.log')
                    println(result)
                    // If validation_state.log file contains string "Not ready!",
                    // meaning environment prerequisites are not ready.
                    // The job will not be executed.
                    if (result.contains('Not ready!')) {
                        EXECUTE_JOB = false
                    } else {
                        EXECUTE_JOB = true
                    }
                }
            }
        }
        stage('Deploy') {
            when {
                expression {
                    EXECUTE_JOB == true
                }
            }
            steps {
                script {
                    GLOBALNET = ""
                    if (params.GLOBALNET) {
                        GLOBALNET = "--globalnet true"
                    }

                    VERSION = ""
                    if (params.VERSION != '') {
                        VERSION = "--version ${params.VERSION}"
                    }

                    DOWNSTREAM = ""
                    if (params.DOWNSTREAM) {
                        DOWNSTREAM = "--downstream"
                    }
                }

                sh """
                ./run.sh --deploy --platform "${params.PLATFORM}" $GLOBALNET $VERSION $DOWNSTREAM
                """
            }
        }
        stage('Test') {
            when {
                expression {
                    EXECUTE_JOB == true
                }
            }
            steps {
                sh """
                ./run.sh --test --platform "${params.PLATFORM}"
                """
            }
        }
    }
    post {
        always {
            archiveArtifacts artifacts: "logs/**/*.*", followSymlinks: false, allowEmptyArchive: true
            junit allowEmptyResults: true, testResults: "logs/**/*.xml"
        }
    }
}
