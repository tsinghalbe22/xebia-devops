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

                    sh """
                        docker build -t ${FRONTEND_IMAGE}:${tag} ./frontend
                        docker build -t ${BACKEND_IMAGE}:${tag} ./backend
                    """
                }
            }
        }

        stage('Push Docker Images') {
            steps {
                script {
                    def tag = "${env.BUILD_NUMBER}"

                    sh """
                        echo "${DOCKERHUB_CREDENTIALS_PSW}" | docker login -u "${DOCKERHUB_CREDENTIALS_USR}" --password-stdin

                        docker tag ${FRONTEND_IMAGE}:${tag} ${FRONTEND_IMAGE}:latest
                        docker tag ${BACKEND_IMAGE}:${tag} ${BACKEND_IMAGE}:latest

                        docker push ${FRONTEND_IMAGE}:${tag}
                        docker push ${FRONTEND_IMAGE}:latest

                        docker push ${BACKEND_IMAGE}:${tag}
                        docker push ${BACKEND_IMAGE}:latest
                    """
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
