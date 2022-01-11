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
        string(name: 'OC_CLUSTER_USER', defaultValue: 'kubeadmin', description: 'ACM Hub username')
        string(name: 'OC_CLUSTER_PASS', defaultValue: '', description: 'ACM Hub password')
        string(name: 'PLATFORM', defaultValue: 'aws,gcp', description: 'The managed clusters platform that should be tested')
    }
    stages {
        stage('Deploy') {
            steps {
                sh """
                export OC_CLUSTER_URL="${params.OC_CLUSTER_URL}"
                export OC_CLUSTER_USER="${params.OC_CLUSTER_USER}"
                export OC_CLUSTER_PASS="${params.OC_CLUSTER_PASS}"

                ./run.sh --deploy --platform "${params.PLATFORM}"
                """
            }
        }
        stage('Test') {
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
            archiveArtifacts artifacts: "tests_logs/*", followSymlinks: false
        }
    }
}
