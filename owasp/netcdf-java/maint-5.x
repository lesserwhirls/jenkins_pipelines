pipeline {
    agent  { label 'jenkins-worker' } 
    environment {
        JAVA_HOME = "/usr/thredds-test-environment/temurin11"
        TO = "thredds-developers@unidata.ucar.edu"
        JOB = "Jenkins build #${env.BUILD_NUMBER} for ${env.JOB_NAME}"
        BUILD_URL ="${env.BUILD_URL}"
    }
    stages {
        stage('Checkout from GitHub') {
            steps {
                checkout([
                    $class                           : 'GitSCM',
                    branches                         : [[name: "*/maint-5.x"]],
                    userRemoteConfigs                : [[credentialsId: 'user', url: 'https://github.com/Unidata/netcdf-java']],
                    doGenerateSubmoduleConfigurations: false
                ])
            }
        }
        stage('Assemble Project') {
            steps {
                sh '''
                   #!/bin/bash
                   select-java temurin 11
                   chmod u+x gradlew
                   ./gradlew assemble
                '''
            }
        }
        stage('Scan Dependencies') {
            steps {
                withCredentials([string(credentialsId: 'NVD_API_Key', variable: 'API_KEY')]) {
                    dependencyCheck additionalArguments: '--format HTML --format XML --suppression project-files/owasp-dependency-check/dependency-check-suppression.xml --nvdApiKey $API_KEY', odcInstallation: 'OWASP', stopBuild: true
                    step([
                        $class:                 'DependencyCheckPublisher',
                        pattern:                '**/dependency-check-report.xml', 
                        failedTotalCritical:    1,
                        failedTotalHigh:        1,
                        failedTotalLow:         1,
                        failedTotalMedium:      1
                    ])
                }
            }
        }
        stage('Publish Report') {
            steps {
                sh '''
                    #!/bin/bash
                    if [ ! -d build/reports ]; then
                        mkdir build/reports/
                    fi
                    mv dependency-check-report.* build/reports/
                '''
                publishHTML([ 
                    allowMissing: false, 
                    alwaysLinkToLastBuild: true, 
                    keepAll: false, 
                    reportDir: 'build/reports', 
                    reportFiles: 'dependency-check-report.*', 
                    reportName: 'OWASP Dependency Check Report', 
                    reportTitles: 'OWASP Dependency Check Report', 
                    useWrapperFileDirectly: true
                ])
            }
        }
    }
    post {  
        always {  
            echo "Build complete: ${currentBuild.currentResult}"  
        }  
        failure {  
            mail to: "${TO}", subject: "${JOB} FAILED", body: "${JOB} FAILED\n See: ${BUILD_URL}"
        }  
        unstable {  
            mail to: "${TO}", subject: "${JOB} UNSTABLE", body: "${JOB} UNSTABLE\n See: ${BUILD_URL}"
        }  
        changed {  
            script {
                if ("${currentBuild.currentResult}" == "SUCCESS") {
                    mail to: "${TO}", subject: "${JOB} STABLE", body: "${JOB} STABLE\n Build status back to normal."
                }
            }
        }   
    }
}

