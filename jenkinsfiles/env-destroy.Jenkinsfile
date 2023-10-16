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
        string(name: 'JOB_NAME', defaultValue: 'Custom-Env-Build', description: 'Job name')
        string(name: 'BUILD_NUMBER', defaultValue: '', description: 'Build number of the job')
        credentials(name: 'SUBMARINER_CONFIG', defaultValue: '', description: 'Submariner config for environment deploy',
            required: true, credentialType: 'org.jenkinsci.plugins.plaincredentials.impl.FileCredentialsImpl')
    }
    environment {
        SUBMARINER_CONF = credentials('SUBMARINER_CONFIG')
    }
    stages {
        stage('Fetch ACM Hub assets') {
            steps {
                script {
                    try {
                        step ([$class: 'CopyArtifact',
                            projectName: "${JOB_NAME}",
                            selector: specific("${BUILD_NUMBER}"),
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
        stage('Destroy environment') {
            steps {
                sh """
                ansible-playbook -v playbooks/ci/env_destroy.yml -e @"${SUBMARINER_CONF}"
                """
            }
        }
    }
}
