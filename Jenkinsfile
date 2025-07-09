pipeline {
    agent any

    environment {
        CLIENT_ID = credentials('azure-client-id')
        CLIENT_SECRET = credentials('azure-client-secret')
        TENANT_ID = credentials('azure-tenant-id')
        SUBSCRIPTION_ID = credentials('azure-subscription-id')
        ACR_URL = ""  
        AKS_API_SERVER = ""
        RESOURCE_GROUP_NAME = ""
        ACR_NAME = ""
        AKS_CLUSTER_NAME = ""
        KUBECONFIG = "/home/jenkins/.kube/config"
    }

    parameters {
        choice(name: 'ACTION', choices: ['deploy', 'destroy'], description: 'Select action to perform')
        booleanParam(name: 'SKIP_TERRAFORM_DESTROY', defaultValue: true, description: 'Skip Terraform destroy step')
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
                sh """
                terraform plan \
                    -var="client_id=${CLIENT_ID}" \
                    -var="client_secret=${CLIENT_SECRET}" \
                    -var="tenant_id=${TENANT_ID}" \
                    -var="subscription_id=${SUBSCRIPTION_ID}" \
                    -out=tfplan
                """
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
                        sh """
                        terraform apply -auto-approve \
                            -var="client_id=${CLIENT_ID}" \
                            -var="client_secret=${CLIENT_SECRET}" \
                            -var="tenant_id=${TENANT_ID}" \
                            -var="subscription_id=${SUBSCRIPTION_ID}"
                        
                        export ACR_URL=$(terraform output -raw acr_url)
                        export ACR_NAME=$(terraform output -raw acr_name)
                        export AKS_API_SERVER=$(terraform output -raw aks_api_server)
                        export AKS_CLUSTER_NAME=$(terraform output -raw aks_cluster_name)
                        export RESOURCE_GROUP_NAME=$(terraform output -raw resource_group_name)

                        echo "ACR URL: ${ACR_URL}"
                        echo "ACR Name: ${ACR_NAME}"
                        echo "AKS API Server: ${AKS_API_SERVER}"
                        echo "AKS Cluster Name: ${AKS_CLUSTER_NAME}"
                        echo "Resource Group: ${RESOURCE_GROUP_NAME}"
                        """
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
                    sh """
                    echo "Logging in to Azure Container Registry"
                    az acr login --name ${env.ACR_NAME}

                    echo "Building and pushing Docker images"
                    docker build -t ${env.ACR_URL}/frontend:${BUILD_NUMBER} frontend/
                    docker build -t ${env.ACR_URL}/frontend:latest frontend/
                    docker push ${env.ACR_URL}/frontend:${BUILD_NUMBER}
                    docker push ${env.ACR_URL}/frontend:latest
                    
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
                    sh """
                    echo "Getting AKS credentials"
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
                    sh """
                    sed -i 's|{{ACR_URL}}|${env.ACR_URL}|g' k8s/frontend-deployment.yaml
                    sed -i 's|{{ACR_URL}}|${env.ACR_URL}|g' k8s/backend-deployment.yaml
                    sed -i 's|{{BUILD_NUMBER}}|${BUILD_NUMBER}|g' k8s/frontend-deployment.yaml
                    sed -i 's|{{BUILD_NUMBER}}|${BUILD_NUMBER}|g' k8s/backend-deployment.yaml
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
                    sh """
                    echo "Deploying to Kubernetes"
                    kubectl apply -f k8s/frontend-deployment.yaml
                    kubectl apply -f k8s/backend-deployment.yaml
                    kubectl rollout status deployment/frontend-deployment
                    kubectl rollout status deployment/backend-deployment
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
                    sh """
                    echo "Verifying deployment"
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
                        sh """
                        terraform destroy -auto-approve \
                            -var="client_id=${CLIENT_ID}" \
                            -var="client_secret=${CLIENT_SECRET}" \
                            -var="tenant_id=${TENANT_ID}" \
                            -var="subscription_id=${SUBSCRIPTION_ID}"
                        """
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                sh 'docker system prune -af --volumes || true'
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
                sh """
                kubectl get events --sort-by=.metadata.creationTimestamp || true
                kubectl logs --tail=50 -l app=frontend || true
                kubectl logs --tail=50 -l app=backend || true
                """
            }
        }

        cleanup {
            cleanWs()
        }
    }
}
