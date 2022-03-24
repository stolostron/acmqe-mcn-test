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
        string(name: 'VERSION', defaultValue: '', description: 'Define specific version of Submariner to be installed')
        booleanParam(name: 'DOWNSTREAM', defaultValue: true, description: 'Deploy downstream version of Submariner')
        string(name:'TEST_TAGS', defaultValue: '', description: 'A tag to control job execution')
    }
    stages {
        stage('Deploy') {
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
                script {
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
                export OC_CLUSTER_URL="${params.OC_CLUSTER_URL}"
                export OC_CLUSTER_USER="${params.OC_CLUSTER_USER}"
                export OC_CLUSTER_PASS="${params.OC_CLUSTER_PASS}"

                ./run.sh --deploy --platform "${params.PLATFORM}" $VERSION $DOWNSTREAM
                """
            }
        }
        stage('Test') {
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
                export OC_CLUSTER_URL="${params.OC_CLUSTER_URL}"
                export OC_CLUSTER_USER="${params.OC_CLUSTER_USER}"
                export OC_CLUSTER_PASS="${params.OC_CLUSTER_PASS}"

                ./run.sh --test --platform "${params.PLATFORM}"
                """
            }
        }
    }
    post {
        always {
            archiveArtifacts artifacts: "logs/**/*.*", followSymlinks: false
            junit allowEmptyResults: true, testResults: "logs/*.xml"
        }
    }
}
