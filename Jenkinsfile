pipeline {
    agent any

    environment {
        CLIENT_ID = credentials('azure-client-id')
        CLIENT_SECRET = credentials('azure-client-secret')
        TENANT_ID = credentials('azure-tenant-id')
        SUBSCRIPTION_ID = credentials('azure-subscription-id')
        ACR_URL = "dockeracrxyz.azurecr.io"  // This will be set later
        AKS_API_SERVER = ""
        RESOURCE_GROUP_NAME = "docker-vm-rg-terraform"
        ACR_NAME = "dockeracrxyz"
        AKS_CLUSTER_NAME = "docker-aks-cluster"
        KUBECONFIG = "/home/jenkins/.kube/config"
    }

    parameters {
        choice(
            name: 'ACTION',
            choices: ['deploy', 'destroy'],
            description: 'Select action to perform'
        )
        booleanParam(
            name: 'SKIP_TERRAFORM_DESTROY',
            defaultValue: true,
            description: 'Skip Terraform destroy step'
        )
    }

    stages {
        stage('Checkout Code') {
            steps {
                checkout scm
            }
        }

        stage('Azure Login') {
            steps {
                script {
                    // Login to Azure CLI
                    sh """
                    az login --service-principal \
                        --username ${CLIENT_ID} \
                        --password ${CLIENT_SECRET} \
                        --tenant ${TENANT_ID}
                    
                    az account set --subscription ${SUBSCRIPTION_ID}
                    """
                }
            }
        }

        stage('Terraform Init') {
            steps {
                script {
                    dir('terraform/cluster') {
                        sh 'terraform init -backend-config="path=/home/jenkins/terraform.tfstate"'
                    }
                }
            }
        }

        stage('Terraform Plan') {
            when {
                expression { params.ACTION == 'deploy' }
            }
            steps {
                script {
                    dir('terraform/cluster') {
                        sh '''
                        terraform plan \
                            -var="client_id=${CLIENT_ID}" \
                            -var="client_secret=${CLIENT_SECRET}" \
                            -var="tenant_id=${TENANT_ID}" \
                            -var="subscription_id=${SUBSCRIPTION_ID}" \
                            -out=tfplan
                        '''
                    }
                }
            }
        }

        stage('Terraform Apply') {
            when {
                expression { params.ACTION == 'deploy' }
            }
            steps {
                script {
                    dir('terraform/cluster') {
                        sh '''
                        terraform apply -auto-approve \
                            -var="client_id=${CLIENT_ID}" \
                            -var="client_secret=${CLIENT_SECRET}" \
                            -var="tenant_id=${TENANT_ID}" \
                            -var="subscription_id=${SUBSCRIPTION_ID}"
                        '''
                    }
                }
            }
        }

        stage('Docker Build and Push') {
            when {
                expression { params.ACTION == 'deploy' }
            }
            steps {
                script {
                    // Login to ACR
                    echo "Logging in to Azure Container Registry"
                    sh "az acr login --name ${env.ACR_NAME}"

                    // Build and push frontend
                    echo "Building and pushing Frontend Docker Image"
                    sh """
                    docker build -t ${env.ACR_URL}/frontend:${BUILD_NUMBER} frontend/
                    docker build -t ${env.ACR_URL}/frontend:latest frontend/
                    docker push ${env.ACR_URL}/frontend:${BUILD_NUMBER}
                    docker push ${env.ACR_URL}/frontend:latest
                    """
                    
                    // Build and push backend
                    echo "Building and pushing Backend Docker Image"
                    sh """
                    docker build -t ${env.ACR_URL}/backend:${BUILD_NUMBER} backend/
                    docker build -t ${env.ACR_URL}/backend:latest backend/
                    docker push ${env.ACR_URL}/backend:${BUILD_NUMBER}
                    docker push ${env.ACR_URL}/backend:latest
                    """
                }
            }
        }

        stage('Get AKS Credentials') {
            when {
                expression { params.ACTION == 'deploy' }
            }
            steps {
                script {
                    echo "Getting AKS credentials"
                    sh """
                    az aks get-credentials \
                        --resource-group ${env.RESOURCE_GROUP_NAME} \
                        --name ${env.AKS_CLUSTER_NAME} \
                        --overwrite-existing
                    """
                }
            }
        }

        stage('Update Kubernetes Manifests') {
            when {
                expression { params.ACTION == 'deploy' }
            }
            steps {
                 script {
            echo "Updating Kubernetes Manifests"
            
            // List contents of k8s to debug
            sh 'ls -R k8s/'

            // Replace image tags in Kubernetes manifests
            sh """
            echo 'Updating frontend deployment.yaml'
            sed -i 's|{{ACR_URL}}|${env.ACR_URL}|g' k8s/frontend/deployment.yaml
            sed -i 's|{{BUILD_NUMBER}}|${BUILD_NUMBER}|g' k8s/frontend/deployment.yaml

            echo 'Updating backend deployment.yaml'
            sed -i 's|{{ACR_URL}}|${env.ACR_URL}|g' k8s/backend/deployment.yaml
            sed -i 's|{{BUILD_NUMBER}}|${BUILD_NUMBER}|g' k8s/backend/deployment.yaml
            """
        }
            }
        }

        stage('Kubernetes Deployment') {
            when {
                expression { params.ACTION == 'deploy' }
            }
            steps {
                script {
                    echo "Deploying to Kubernetes"
                    sh """
            kubectl apply -f k8s/frontend/deployment.yaml
            kubectl apply -f k8s/backend/deployment.yaml
            kubectl apply -f k8s/frontend/service.yaml
            kubectl apply -f k8s/backend/service.yaml
            """
                }
            }
        }

        stage('Verify Deployment') {
            when {
                expression { params.ACTION == 'deploy' }
            }
            steps {
                script {
                    echo "Verifying deployment"
                    sh """
                    kubectl get pods -l app=frontend
                    kubectl get pods -l app=backend
                    kubectl get services
                    """
                }
            }
        }

        stage('Terraform Destroy') {
            when {
                allOf {
                    expression { params.ACTION == 'destroy' }
                    expression { !params.SKIP_TERRAFORM_DESTROY }
                }
            }
            steps {
                script {
                    echo "Destroying Terraform resources"
                    dir('terraform/cluster') {
                        sh '''
                        terraform destroy -auto-approve \
                            -var="client_id=${CLIENT_ID}" \
                            -var="client_secret=${CLIENT_SECRET}" \
                            -var="tenant_id=${TENANT_ID}" \
                            -var="subscription_id=${SUBSCRIPTION_ID}"
                        '''
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                // Clean up Docker images

            }
        }
        success {
            echo "Pipeline executed successfully!"
            script {
                if (params.ACTION == 'deploy') {
                    echo "Deployment completed successfully!"
                    echo "ACR URL: ${env.ACR_URL}"
                    echo "AKS Cluster: ${env.AKS_CLUSTER_NAME}"
                }
            }
        }
        failure {
            echo "Pipeline failed!"
            script {
                // Get recent logs for debugging
                sh """
                kubectl get events --sort-by=.metadata.creationTimestamp || true
                kubectl logs --tail=50 -l app=frontend || true
                kubectl logs --tail=50 -l app=backend || true
                """
            }
        }
        cleanup {
            // Clean up workspace
            cleanWs()
        }
    }
}
