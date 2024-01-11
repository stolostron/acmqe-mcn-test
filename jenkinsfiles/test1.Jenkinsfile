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
    stages {
        stage('test') {
            steps {
                sh """
                mkdir logs/
                echo "test1 job" > logs/test1.job

                exit 1
                """
                script {
                    currentBuild.result = 'UNSTABLE'
                }
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
