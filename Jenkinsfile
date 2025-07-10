pipeline {
    agent any
    
    environment {
        DOCKER_USER = 'tsinghalbe22'
        FRONTEND_IMAGE = "${DOCKER_USER}/frontend"
        BACKEND_IMAGE = "${DOCKER_USER}/backend"
        DOCKERHUB_CREDENTIALS = credentials('docker-hub-credentials')
        
        // Azure/Terraform credentials
        TF_VAR_client_id = credentials('azure-client-id')
        TF_VAR_client_secret = credentials('azure-client-secret')
        TF_VAR_tenant_id = credentials('azure-tenant-id')
        TF_VAR_subscription_id = credentials('azure-subscription-id')
        
        // Terraform state file paths
        TERRAFORM_DIR = './terraform/cluster'
        JENKINS_STATE_DIR = '/home/jenkins'
        STATE_FILE = 'terraform.tfstate'
        BACKUP_STATE_FILE = 'terraform.tfstate.backup'
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
        
        stage('Setup Terraform') {
            steps {
                script {
                    sh """
                        # Check if state file exists in Jenkins home and copy it
                        if [ -f "${JENKINS_STATE_DIR}/${STATE_FILE}" ]; then
                            echo "Found existing state file, copying to terraform directory..."
                            cp ${JENKINS_STATE_DIR}/${STATE_FILE} ${TERRAFORM_DIR}/
                        else
                            echo "No existing state file found, will create new infrastructure"
                        fi
                        
                        # Copy backup state file if it exists
                        if [ -f "${JENKINS_STATE_DIR}/${BACKUP_STATE_FILE}" ]; then
                            cp ${JENKINS_STATE_DIR}/${BACKUP_STATE_FILE} ${TERRAFORM_DIR}/
                        fi
                        
                        # Navigate to terraform directory
                        cd ${TERRAFORM_DIR}
                        
                        # Initialize Terraform
                        terraform init

                        cd terraform state
                    """
                }
            }
        }
        
        stage('Terraform Plan') {
            steps {
                script {
                    sh """
                        cd ${TERRAFORM_DIR}
                        terraform plan -out=tfplan \
                            -var="client_id=${TF_VAR_client_id}" \
                            -var="client_secret=${TF_VAR_client_secret}" \
                            -var="tenant_id=${TF_VAR_tenant_id}" \
                            -var="subscription_id=${TF_VAR_subscription_id}"
                    """
                }
            }
        }
        
        stage('Terraform Apply') {
            steps {
                script {
                    sh """
                        cd ${TERRAFORM_DIR}
                        terraform apply -auto-approve tfplan
                        
                        # Save state files back to Jenkins home for persistence
                        cp ${STATE_FILE} ${JENKINS_STATE_DIR}/ || true
                        cp ${BACKUP_STATE_FILE} ${JENKINS_STATE_DIR}/ || true
                        
                        # Get the public IP for deployment
                        PUBLIC_IP=\$(terraform output -raw public_ip_2)
                        echo "Azure VM Public IP: \$PUBLIC_IP"
                        
                        # Store IP in a file for the next stage
                        echo "\$PUBLIC_IP" > ${WORKSPACE}/public_ip.txt
                    """
                }
            }
        }
        
        // Deploy stage - TODO: Add deployment logic later
        // stage('Deploy to Azure VM') {
        //     steps {
        //         script {
        //             // Deployment logic will go here
        //             echo "Deployment stage - to be implemented"
        //         }
        //     }
        // }
    }
    
    post {
        success {
            script {
                def publicIP = readFile("${WORKSPACE}/public_ip.txt").trim()
                echo """
                    ✅ Pipeline completed successfully!
                    
                    🐳 Docker images built and pushed with tag: ${env.BUILD_NUMBER}
                    🏗️  Infrastructure deployed to Azure
                    🌐 Public IP: ${publicIP}
                    
                    📁 State files backed up to: ${JENKINS_STATE_DIR}
                    
                    ⏳ Manual deployment to VM required
                """
            }
        }
        failure {
            echo '❌ Pipeline failed. Check logs for details.'
        }
        always {
            // Clean up temporary files
            sh """
                rm -f ${WORKSPACE}/public_ip.txt || true
                rm -f ${TERRAFORM_DIR}/tfplan || true
            """
        }
    }
}
