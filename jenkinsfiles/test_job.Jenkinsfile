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
        credentials(name: 'SUBMARINER_CONFIG', defaultValue: 'test', description: 'Submariner config for environment deploy',
                    required: true, credentialType: 'org.jenkinsci.plugins.plaincredentials.impl.FileCredentialsImpl')
    }
    environment {
        SUBMARINER_CONF = credentials('SUBMARINER_CONFIG')
    }
    stages {
        stage('Deploy ACM Hub') {
            steps {
                sh """
                ansible-playbook -v playbooks/managed_openshift.yml -e @"${SUBMARINER_CONF}"
                """
            }
        }
    }
}
