pipeline {
    agent any

    environment {
        DOCKER_USER = 'tsinghalbe22'
        FRONTEND_IMAGE = "${DOCKER_USER}/frontend"
        BACKEND_IMAGE = "${DOCKER_USER}/backend"
        DOCKERHUB_CREDENTIALS = credentials('docker-hub-credentials')
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build Docker Images') {
            steps {
                script {
                    def tag = "${env.BUILD_NUMBER}"

                    frontendImage = docker.build("${FRONTEND_IMAGE}:${tag}", "./frontend")
                    backendImage  = docker.build("${BACKEND_IMAGE}:${tag}", "./backend")
                }
            }
        }

        stage('Push Docker Images') {
            steps {
                script {
                    def tag = "${env.BUILD_NUMBER}"

                    // Corrected login command for shell
                    sh """
                        echo "${DOCKERHUB_CREDENTIALS_PSW}" | docker login -u "${DOCKERHUB_CREDENTIALS_USR}" --password-stdin
                    """

                    frontendImage.push(tag)
                    frontendImage.push('latest')

                    backendImage.push(tag)
                    backendImage.push('latest')
                }
            }
        }
    }

    post {
        success {
            echo "Images pushed with tag: ${env.BUILD_NUMBER}"
        }
        failure {
            echo 'Pipeline failed.'
        }
    }
}
