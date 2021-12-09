pipeline {
    agent {
        docker {
            image 'quay.io/rhn_support_abutt/centos8-nodejs12'
            args '--network host -u 0:0 -p 3000:3000'
        }
    }
    parameters {
        string(name:'DEMO_PARAM', defaultValue: 'Submariner demo input', description: 'Submariner demo variable for Jenkins pipeline')
    }
    environment {
        CI = 'true'
    }
    stages {
        stage('Build') {
            steps {                
                sh '''       
                npm config set unsafe-perm true                    
                npm install
                npm ci
                npx browserslist@latest --update-db
                '''
            }
        }
        stage('Test') {
            steps {
                sh """
                export DEMO_PARAM="${params.DEMO_PARAM}"
                
                echo "This is a jenkins piplene stage to test $DEMO_PARAM"
                """
            }
        }
    }
    post {
        always {
            archiveArtifacts artifacts: 'missing-artifacts-dir/*', followSymlinks: false
            junit 'missing-artifacts-dir/*.xml'
        }
    }
}
