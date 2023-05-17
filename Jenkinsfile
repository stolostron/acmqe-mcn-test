pipeline {
    agent {
        docker {
            image 'quay.io/stolostron/acm-qe:submariner-fedora36-nodejs18'
            registryUrl 'https://quay.io/stolostron/acm-qe'
            registryCredentialsId '0089f10c-7a3a-4d16-b5b0-3a2c9abedaa2'
            args '--network host'
        }
    }
    options {
        ansiColor('xterm')
        buildDiscarder(logRotator(daysToKeepStr: '30'))
        timeout(time: 8, unit: 'HOURS')
    }
    parameters {
        string(name: 'OC_CLUSTER_URL', defaultValue: '', description: 'ACM Hub API URL')
        string(name: 'OC_CLUSTER_USER', defaultValue: '', description: 'ACM Hub username')
        string(name: 'OC_CLUSTER_PASS', defaultValue: '', description: 'ACM Hub password')
        extendedChoice(name: 'PLATFORM', description: 'The managed clusters platform that should be tested',
            value: 'aws,gcp,azure,vsphere', defaultValue: 'aws,gcp,vsphere', multiSelectDelimiter: ',', type: 'PT_CHECKBOX')
        booleanParam(name: 'GLOBALNET', defaultValue: true, description: 'Deploy Globalnet on Submariner')
        booleanParam(name: 'DOWNSTREAM', defaultValue: true, description: 'Deploy downstream version of Submariner')
        string(name:'TEST_TAGS', defaultValue: '', description: 'A tag to control job execution')
        booleanParam(name: 'POLARION', defaultValue: true, description: 'Publish tests results to Polarion')
        choice(name: 'JOB_STAGES', choices: ['all', 'deploy', 'test'], description: 'Select stage that should be executed by the job')
    }
    environment {
        EXECUTE_JOB = false
        OC_CLUSTER_URL = "${params.OC_CLUSTER_URL}"
        OC_CLUSTER_USER = "${params.OC_CLUSTER_USER}"
        OC_CLUSTER_PASS = "${params.OC_CLUSTER_PASS}"
        // Parameter will be used to disable globalnet in
        // ACM version below 2.5.0 as it's not supported
        GLOBALNET_TRIGGER = true
        // The secret contains polarion authentication
        // and other details for report publish
        POLARION_SECRET = credentials('submariner-polarion-secret')
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
                    environment name: 'TEST_TAGS', value: '@post-release'
                    environment name: 'TEST_TAGS', value: '@api'
                    environment name: 'TEST_TAGS', value: '@api-post-release'
                }
            }
            steps {
                sh """
                ./run.sh --validate-prereq --platform "${params.PLATFORM}"

                # In acm-qe jenkins, logs stored in a PV, so they are persistent over jobs.
                # Delete "logs/" dir so in case the job skipped, previous job results will not be reported.
                rm -rf logs/
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

                    // Checks the version of the MultiClusterHub
                    // If the version is below 2.5.0, globalnet
                    // is not supported - disable it.
                    // Otherwise, use parameter definition.
                    def mch_ver = readFile(file: 'mch_version.log')
                    println("MultiClusterHub version: " + mch_ver)

                    // Compare the minor version
                    check_version = '2.5.0'
                    check_version_minor = check_version.split('\\.')[1] as Integer
                    mch_ver_minor = mch_ver.split('\\.')[1] as Integer

                    if (mch_ver_minor < check_version_minor) {
                        println("Disable Globalnet as it's not supported in ACM " + mch_ver)
                        GLOBALNET_TRIGGER = false
                    }
                }
            }
        }
        stage('Deploy') {
            when {
                allOf {
                    expression {
                        EXECUTE_JOB == true
                    }
                    expression {
                        JOB_STAGES == 'all' || JOB_STAGES == 'deploy'
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

                    // The '@post-release' tag meant to test post GA release
                    // thus don't use the downstream tag.
                    // Override the any state of the DOWNSTREAM param.
                    if (params.TEST_TAGS == '@post-release') {
                        DOWNSTREAM = "--downstream false"
                    }
                }

                sh """
                ./run.sh --deploy --platform "${params.PLATFORM}" $GLOBALNET $DOWNSTREAM
                """
            }
        }
        stage('Test') {
            when {
                allOf {
                    expression {
                        EXECUTE_JOB == true
                    }
                    expression {
                        JOB_STAGES == 'all' || JOB_STAGES == 'test'
                    }
                }
            }
            steps {
                script {
                    DOWNSTREAM = "--downstream false"
                    if (params.DOWNSTREAM) {
                        DOWNSTREAM = "--downstream true"
                    }

                    // The '@post-release' tag meant to test post GA release
                    // thus don't use the downstream tag.
                    // Override the any state of the DOWNSTREAM param.
                    if (params.TEST_TAGS == '@post-release') {
                        DOWNSTREAM = "--downstream false"
                    }
                }

                sh """
                ./run.sh --test --platform "${params.PLATFORM}" $DOWNSTREAM
                """
            }
        }
        stage('Report to Polarion') {
            when {
                allOf {
                    expression {
                        EXECUTE_JOB == true
                    }
                    expression {
                        JOB_STAGES == 'all' || JOB_STAGES == 'test'
                    }
                }
            }
            steps {
                script {
                    POLARION = ""
                    if (params.POLARION) {
                        POLARION = "--polarion-vars-file ${POLARION_SECRET}"
                    }
                }

                sh """
                ./run.sh --report $POLARION
                """
            }
        }
    }
    post {
        always {
            archiveArtifacts artifacts: "logs/**/*.*", followSymlinks: false, allowEmptyArchive: true
            junit allowEmptyResults: true, testResults: "logs/**/**/*junit.xml"
        }
    }
}
