// Switch to read from a file instead of defining the file inline
// when the following bug fixed:
// https://issues.jenkins.io/browse/JENKINS-42971
podTemplate(yaml: '''
    apiVersion: v1
    kind: Pod
    metadata:
      labels:
        label: submariner
    spec:
      activeDeadlineSeconds: 18000
      containers:
      - name: jnlp
        image: 'image-registry.openshift-image-registry.svc:5000/jenkins-csb-skynet/qe-jenkins-agent:latest'
        workingDir: '/home/jenkins'
        env:
          - name: HOME
            value: '/home/jenkins'
        resources:
          limits:
            cpu: 100m
            memory: 300Mi
          requests:
            cpu: 50m
            memory: 256Mi
      - name: submariner
        image: 'quay.io/maxbab/subm-test:test'
        ttyEnabled: true
        alwaysPullImage: true
        command: [ 'sleep', '365d' ]
        workingDir: '/home/jenkins'
        env:
          - name: HOME
            value: '/home/jenkins'
        resources:
          limits:
            cpu: 2000m
            memory: 3Gi
          requests:
            cpu: 2000m
            memory: 3Gi
''') {
    node(POD_LABEL) {
        checkout scm

        properties([
            parameters([
                extendedChoice(name: 'JOB_STAGES', description: 'Select the stages of the job to be executed',
                    value: 'Deploy OCP cluster,Deploy ACM Hub,Deploy Clusters by ACM,Submariner Validate prerequisites,Submariner Deploy,Submariner Test - API,Submariner Test - UI',
                    defaultValue: 'Deploy OCP cluster,Deploy ACM Hub,Deploy Clusters by ACM,Submariner Validate prerequisites,Submariner Deploy,Submariner Test - API,Submariner Test - UI',
                    multiSelectDelimiter: ',', type: 'PT_CHECKBOX', visibleItemCount: 10),
                credentials(name: 'SUBMARINER_CONFIG', defaultValue: '', description: 'Submariner config for environment deploy',
                    required: true, credentialType: 'org.jenkinsci.plugins.plaincredentials.impl.FileCredentialsImpl'),
                extendedChoice(name: 'BRANCH', description: 'Git branch to be used during deployment',
                    defaultValue: 'main',
                    multiSelectDelimiter: ',',
                    type: 'PT_SINGLE_SELECT',
                    visibleItemCount: 10,
                    groovyScript: '''import jenkins.*
import jenkins.model.*
import hudson.*
import hudson.model.*

def gitURL = "https://github.com/stolostron/acmqe-mcn-test.git"
def command = "git ls-remote -h " + gitURL
def proc = command.execute()
proc.waitFor()

if (proc.exitValue() != 0) {
    println "Error, ${proc.err.text}"
    System.exit(0)
}

def branches = proc.in.text.readLines().collect {
    it.replaceAll(".*heads\\/", "")
}
return branches.join(",")''')
            ])
        ])

        container('submariner') {
            load 'jenkinsfiles/base.Jenkinsfile'
        }
    }
}
