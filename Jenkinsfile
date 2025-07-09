pipeline {
    agent any

    environment {
        CLIENT_ID = credentials('azure-client-id')
        CLIENT_SECRET = credentials('azure-client-secret')
        TENANT_ID = credentials('azure-tenant-id')
        SUBSCRIPTION_ID = credentials('azure-subscription-id')
        ACR_URL = "dockeracrxyz.azurecr.io"
        AKS_API_SERVER = ""
        RESOURCE_GROUP_NAME = "docker-vm-rg-terraform"
        ACR_NAME = "dockeracrxyz"
        AKS_CLUSTER_NAME = "docker-aks-cluster"
        KUBECONFIG = "/home/jenkins/.kube/config"
        STATIC_IP_NAME = "frontend-static-ip"
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

        stage('Setup Static IP') {
            when {
                expression { params.ACTION == 'deploy' }
            }
            steps {
                script {
                    echo "Setting up static IP for frontend"
                    sh """
                    # Get the node resource group
                    NODE_RG=\$(az aks show --resource-group ${env.RESOURCE_GROUP_NAME} --name ${env.AKS_CLUSTER_NAME} --query "nodeResourceGroup" -o tsv)
                    
                    # Create static public IP if it doesn't exist
                    if ! az network public-ip show --resource-group \$NODE_RG --name ${env.STATIC_IP_NAME} > /dev/null 2>&1; then
                        echo "Creating static IP..."
                        az network public-ip create \
                            --resource-group \$NODE_RG \
                            --name ${env.STATIC_IP_NAME} \
                            --sku Standard \
                            --allocation-method static
                    else
                        echo "Static IP already exists"
                    fi
                    
                    # Get the static IP address
                    STATIC_IP=\$(az network public-ip show --resource-group \$NODE_RG --name ${env.STATIC_IP_NAME} --query "ipAddress" -o tsv)
                    echo "Static IP: \$STATIC_IP"
                    
                    # Store the IP for later use
                    echo \$STATIC_IP > static_ip.txt
                    """
                }
            }
        }

        stage('Setup ACR Authentication') {
            when {
                expression { params.ACTION == 'deploy' }
            }
            steps {
                script {
                    echo "Setting up ACR authentication"
                    sh """
                    # Enable ACR admin user
                    az acr update --name ${env.ACR_NAME} --admin-enabled true
                    
                    # Get ACR credentials
                    ACR_PASSWORD=\$(az acr credential show --name ${env.ACR_NAME} --query "passwords[0].value" -o tsv)
                    
                    # Create or update Kubernetes secret
                    kubectl create secret docker-registry acr-secret \
                        --docker-server=${env.ACR_URL} \
                        --docker-username=${env.ACR_NAME} \
                        --docker-password=\$ACR_PASSWORD \
                        --dry-run=client -o yaml | kubectl apply -f -
                    """
                }
            }
        }

        stage('Create Backend Secret') {
            when {
                expression { params.ACTION == 'deploy' }
            }
            steps {
                script {
    echo "Creating backend secret"
    def staticIP = sh(script: 'cat static_ip.txt', returnStdout: true).trim()
    
    sh """
    kubectl create secret generic backend-secret \
        --from-literal=MONGO_URI="mongodb+srv://tsinghalbe22:BDUosPJHgGlYDoD2@cluster0.cwknfdr.mongodb.net/?retryWrites=true&w=majority&appName=Cluster0" \
        --from-literal=ORIGIN="http://${staticIP}:3000" \
        --from-literal=EMAIL="your-email@example.com" \
        --from-literal=PASSWORD="your-email-password" \
        --from-literal=LOGIN_TOKEN_EXPIRATION="30d" \
        --from-literal=OTP_EXPIRATION_TIME="120000" \
        --from-literal=PASSWORD_RESET_TOKEN_EXPIRATION="2m" \
        --from-literal=COOKIE_EXPIRATION_DAYS="30" \
        --from-literal=SECRET_KEY="e5ee2b6c6bd78cda55c4af8e678b08b6983e324411d90ffe04387fb716f59f4e" \
        --from-literal=PRODUCTION="false" \
        --dry-run=client -o yaml | kubectl apply -f -
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
                    
                    // Get static IP for frontend service
                    def frontendIP = sh(script: 'cat static_ip.txt', returnStdout: true).trim()
                    
                    // Replace image tags in Kubernetes manifests
                    sh """
                    echo 'Updating frontend deployment.yaml'
                    sed -i 's|{{ACR_URL}}|${env.ACR_URL}|g' k8s/frontend/deployment.yaml
                    sed -i 's|{{BUILD_NUMBER}}|${BUILD_NUMBER}|g' k8s/frontend/deployment.yaml

                    echo 'Updating backend deployment.yaml'
                    sed -i 's|{{ACR_URL}}|${env.ACR_URL}|g' k8s/backend/deployment.yaml
                    sed -i 's|{{BUILD_NUMBER}}|${BUILD_NUMBER}|g' k8s/backend/deployment.yaml
                    
                    # Convert both services to LoadBalancer
                    sed -i 's|type: NodePort|type: LoadBalancer|g' k8s/frontend/service.yaml
                    sed -i 's|type: NodePort|type: LoadBalancer|g' k8s/backend/service.yaml
                    
                    # Add static IP to frontend service
                    sed -i '/type: LoadBalancer/a\\  loadBalancerIP: ${frontendIP}' k8s/frontend/service.yaml
                    
                    # Add image pull secrets to deployments
                    sed -i '/containers:/i\\      imagePullSecrets:\\n      - name: acr-secret' k8s/frontend/deployment.yaml
                    sed -i '/containers:/i\\      imagePullSecrets:\\n      - name: acr-secret' k8s/backend/deployment.yaml
                    """
                }
            }
        }

        stage('Deploy Backend Service First') {
            when {
                expression { params.ACTION == 'deploy' }
            }
            steps {
                script {
                    echo "Deploying backend service and deployment"
                    sh """
                    kubectl apply -f k8s/backend/deployment.yaml
                    kubectl apply -f k8s/backend/service.yaml
                    """
                    
                    // Wait for backend LoadBalancer to get IP
                    echo "Waiting for backend LoadBalancer IP..."
                    sh """
                    kubectl wait --for=condition=Ready pod -l app=backend --timeout=300s
                    """
                    
                    // Get backend IP (retry loop)
                    def backendIP = ""
                    for (int i = 0; i < 30; i++) {
                        try {
                            backendIP = sh(script: 'kubectl get service backend -o jsonpath="{.status.loadBalancer.ingress[0].ip}"', returnStdout: true).trim()
                            if (backendIP && backendIP != "") {
                                echo "Backend LoadBalancer IP: ${backendIP}"
                                break
                            }
                        } catch (Exception e) {
                            echo "Waiting for backend IP... attempt ${i+1}/30"
                        }
                        sleep(10)
                    }
                    
                    if (!backendIP || backendIP == "") {
                        error "Failed to get backend LoadBalancer IP after 5 minutes"
                    }
                    
                    // Store backend IP for next stage
                    sh "echo '${backendIP}' > backend_ip.txt"
                }
            }
        }

        stage('Update Frontend with Backend IP') {
            when {
                expression { params.ACTION == 'deploy' }
            }
            steps {
                script {
                    echo "Updating frontend with backend IP"
                    
                    def backendIP = sh(script: 'cat backend_ip.txt', returnStdout: true).trim()
                    
                    // Update frontend deployment with backend IP
                    sh """
                    # Remove any existing REACT_APP_BASE_URL if present
                    sed -i '/REACT_APP_BASE_URL/d' k8s/frontend/deployment.yaml
                    
                    # Add backend URL environment variable
                    sed -i '/ports:/a\\          env:\\n          - name: REACT_APP_BASE_URL\\n            value: "http://${backendIP}:8000"' k8s/frontend/deployment.yaml
                    """
                }
            }
        }

        stage('Deploy Frontend Service') {
            when {
                expression { params.ACTION == 'deploy' }
            }
            steps {
                script {
                    echo "Deploying frontend service and deployment"
                    sh """
                    kubectl apply -f k8s/frontend/deployment.yaml
                    kubectl apply -f k8s/frontend/service.yaml
                    """
                }
            }
        }

        stage('Update Backend CORS') {
            when {
                expression { params.ACTION == 'deploy' }
            }
            steps {
                script {
                    echo "Updating backend CORS with frontend IP"
                    
                    def frontendIP = sh(script: 'cat static_ip.txt', returnStdout: true).trim()
                    
                    // Update backend secret with correct CORS origin
                    sh """
                    kubectl create secret generic backend-secret \
                        --from-literal=MONGO_URI="mongodb+srv://tsinghalbe22:BDUosPJHgGlYDoD2@cluster0.cwknfdr.mongodb.net/?retryWrites=true&w=majority&appName=Cluster0" \
                        --from-literal=ORIGIN="http://${frontendIP}:3000" \
                        --from-literal=EMAIL="your-email@example.com" \
                        --from-literal=PASSWORD="your-email-password" \
                        --from-literal=LOGIN_TOKEN_EXPIRATION="30d" \
                        --from-literal=OTP_EXPIRATION_TIME="120000" \
                        --from-literal=PASSWORD_RESET_TOKEN_EXPIRATION="2m" \
                        --from-literal=COOKIE_EXPIRATION_DAYS="30" \
                        --from-literal=SECRET_KEY="e5ee2b6c6bd78cda55c4af8e678b08b6983e324411d90ffe04387fb716f59f4e" \
                        --from-literal=PRODUCTION="false" \
                        --dry-run=client -o yaml | kubectl apply -f -
                    
                    # Restart backend deployment to pick up new secret
                    kubectl rollout restart deployment/backend
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
                    
                    echo "Frontend IP: \$(cat static_ip.txt)"
                    echo "Backend IP: \$(cat backend_ip.txt)"
                    
                    echo "URLs:"
                    echo "Frontend: http://\$(cat static_ip.txt):3000"
                    echo "Backend: http://\$(cat backend_ip.txt):8000"
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
                sh "echo Pipeline completed"
            }
        }
        success {
            echo "Pipeline executed successfully!"
            script {
                if (params.ACTION == 'deploy') {
                    echo "Deployment completed successfully!"
                    echo "ACR URL: ${env.ACR_URL}"
                    echo "AKS Cluster: ${env.AKS_CLUSTER_NAME}"
                    
                    // Show access information
                    sh """
                    echo "=== ACCESS INFORMATION ==="
                    FRONTEND_IP=\$(kubectl get service frontend -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
                    echo "Frontend URL: http://\$FRONTEND_IP:3000"
                    echo "Backend URL: http://\$FRONTEND_IP:8000 (if exposed)"
                    echo "==========================="
                    """
                }
            }
        }
        failure {
            echo "Pipeline failed!"
            script {
                // Get recent logs for debugging
                sh """
                echo "=== DEBUGGING INFORMATION ==="
                kubectl get events --sort-by=.metadata.creationTimestamp --tail=20 || true
                echo ""
                echo "Frontend pods:"
                kubectl get pods -l app=frontend || true
                echo ""
                echo "Backend pods:"
                kubectl get pods -l app=backend || true
                echo ""
                echo "Services:"
                kubectl get services || true
                echo ""
                echo "Frontend logs:"
                kubectl logs --tail=50 -l app=frontend || true
                echo ""
                echo "Backend logs:"
                kubectl logs --tail=50 -l app=backend || true
                echo "=============================="
                """
            }
        }
        cleanup {
            // Clean up workspace
            cleanWs()
        }
    }
}
