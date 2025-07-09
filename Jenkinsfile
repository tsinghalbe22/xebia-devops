pipeline {
    agent any

    environment {
        CLIENT_ID = credentials('azure-client-id')
        CLIENT_SECRET = credentials('azure-client-secret')
        TENANT_ID = credentials('azure-tenant-id')
        SUBSCRIPTION_ID = credentials('azure-subscription-id')
        ACR_URL = ""  // This will be set later
        KUBECONFIG = "/home/jenkins/.kube/config"  // Path for kubeconfig
    }

    stages {
        stage('Checkout Code') {
            steps {
                checkout scm
            }
        }

        stage('Terraform Init') {
            steps {
                script {
                    // Initialize Terraform
                    sh 'terraform init -chdir=terraform/cluster'
                }
            }
        }

        stage('Terraform Plan') {
            steps {
                script {
                    // Run Terraform plan
                    sh '''
                    terraform plan -var="client_id=${CLIENT_ID}" \
                                   -var="client_secret=${CLIENT_SECRET}" \
                                   -var="tenant_id=${TENANT_ID}" \
                                   -var="subscription_id=${SUBSCRIPTION_ID}" \
                                   -out=tfplan terraform/cluster \
                                   -chdir=terraform/cluster
                    '''
                }
            }
        }

        stage('Terraform Apply') {
            steps {
                script {
                    // Apply Terraform
                    sh '''
                    terraform apply -auto-approve \
                                     -var="client_id=${CLIENT_ID}" \
                                     -var="client_secret=${CLIENT_SECRET}" \
                                     -var="tenant_id=${TENANT_ID}" \
                                     -var="subscription_id=${SUBSCRIPTION_ID}" \
                                     -chdir=terraform/cluster
                    '''
                    // Capture the ACR URL and AKS endpoint from Terraform output
                    def acrUrl = sh(script: "terraform output -raw acr_url terraform/cluster", returnStdout: true).trim()
                    def aksApiServer = sh(script: "terraform output -raw aks_api_server terraform/cluster", returnStdout: true).trim()
                    env.ACR_URL = acrUrl
                    env.AKS_API_SERVER = aksApiServer

                    // Outputting these for debugging purposes
                    echo "ACR URL: ${acrUrl}"
                    echo "AKS API Server: ${aksApiServer}"
                }
            }
        }

        stage('Docker Build and Push') {
            steps {
                script {
                    // Build and push Docker images (Frontend and Backend) to ACR
                    echo "Building Frontend Docker Image"
                    sh """
                    docker build -t ${ACR_URL}/frontend:latest frontend/
                    docker push ${ACR_URL}/frontend:latest
                    """
                    
                    echo "Building Backend Docker Image"
                    sh """
                    docker build -t ${ACR_URL}/backend:latest backend/
                    docker push ${ACR_URL}/backend:latest
                    """
                }
            }
        }

        stage('Kubernetes Deployment') {
            steps {
                script {
                    // Update kubeconfig with the AKS credentials and deploy the app
                    sh """
                    az aks get-credentials --resource-group docker-vm-rg --name docker-aks-cluster --overwrite-existing
                    kubectl apply -f k8s/frontend-deployment.yaml
                    kubectl apply -f k8s/backend-deployment.yaml
                    """
                }
            }
        }

        stage('Cleanup') {
            steps {
                script {
                    // Optionally, clean up the workspace and any resources
                    sh 'terraform destroy -auto-approve terraform/cluster'
                }
            }
        }
    }

    post {
        success {
            echo "Pipeline executed successfully!"
        }
        failure {
            echo "Pipeline failed!"
        }
    }
}
