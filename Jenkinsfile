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
        USE_NODEPORT = "false"  // Will be set to true if static IP fails
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
        booleanParam(
            name: 'FORCE_NODEPORT',
            defaultValue: false,
            description: 'Force use of NodePort instead of LoadBalancer'
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

        stage('Setup Static IP or NodePort') {
            when {
                expression { params.ACTION == 'deploy' }
            }
            steps {
                script {
                    if (params.FORCE_NODEPORT) {
                        echo "Force NodePort mode enabled - skipping static IP setup"
                        env.USE_NODEPORT = "true"
                        sh """
                        # Get node IP for NodePort access
                        NODE_IP=\$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
                        
                        if [ -z "\$NODE_IP" ] || [ "\$NODE_IP" == "null" ]; then
                            NODE_IP=\$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
                            echo "Using internal IP (may need VPN/internal access): \$NODE_IP"
                        else
                            echo "Using external IP: \$NODE_IP"
                        fi
                        
                        echo \$NODE_IP > frontend_ip.txt
                        echo "30000" > frontend_port.txt
                        echo "NodePort setup complete - Frontend will be accessible at: http://\$NODE_IP:30000"
                        """
                    } else {
                        echo "Attempting to setup static IP for frontend"
                        sh """
                        # Get the node resource group
                        NODE_RG=\$(az aks show --resource-group ${env.RESOURCE_GROUP_NAME} --name ${env.AKS_CLUSTER_NAME} --query "nodeResourceGroup" -o tsv)
                        echo "Node Resource Group: \$NODE_RG"
                        
                        # Check if static public IP exists
                        if az network public-ip show --resource-group \$NODE_RG --name ${env.STATIC_IP_NAME} > /dev/null 2>&1; then
                            echo "Static IP '${env.STATIC_IP_NAME}' already exists - using existing IP"
                            STATIC_IP=\$(az network public-ip show --resource-group \$NODE_RG --name ${env.STATIC_IP_NAME} --query "ipAddress" -o tsv)
                            echo "Using existing static IP: \$STATIC_IP"
                            echo \$STATIC_IP > frontend_ip.txt
                            echo "3000" > frontend_port.txt
                            echo "loadbalancer" > service_type.txt
                        else
                            echo "Static IP '${env.STATIC_IP_NAME}' does not exist - checking quota"
                            
                            # Check current public IP count in the region
                            CURRENT_COUNT=\$(az network public-ip list --query "length([?location=='centralindia'])" -o tsv)
                            echo "Current public IP count in Central India: \$CURRENT_COUNT"
                            
                            if [ \$CURRENT_COUNT -ge 3 ]; then
                                echo "WARNING: Cannot create new public IP - quota limit reached (\$CURRENT_COUNT/3)"
                                echo "Falling back to NodePort mode"
                                
                                # Get node IP for NodePort fallback
                                NODE_IP=\$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
                                
                                if [ -z "\$NODE_IP" ] || [ "\$NODE_IP" == "null" ]; then
                                    NODE_IP=\$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
                                    echo "Using internal IP (may need VPN/internal access): \$NODE_IP"
                                else
                                    echo "Using external IP: \$NODE_IP"
                                fi
                                
                                echo \$NODE_IP > frontend_ip.txt
                                echo "30000" > frontend_port.txt
                                echo "nodeport" > service_type.txt
                                echo "USE_NODEPORT=true" >> \$WORKSPACE/nodeport.env
                            else
                                echo "Creating new static IP... (Current: \$CURRENT_COUNT/3)"
                                if az network public-ip create \
                                    --resource-group \$NODE_RG \
                                    --name ${env.STATIC_IP_NAME} \
                                    --sku Standard \
                                    --allocation-method static; then
                                    
                                    STATIC_IP=\$(az network public-ip show --resource-group \$NODE_RG --name ${env.STATIC_IP_NAME} --query "ipAddress" -o tsv)
                                    echo "Created new static IP: \$STATIC_IP"
                                    echo \$STATIC_IP > frontend_ip.txt
                                    echo "3000" > frontend_port.txt
                                    echo "loadbalancer" > service_type.txt
                                else
                                    echo "Failed to create static IP - falling back to NodePort"
                                    NODE_IP=\$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
                                    
                                    if [ -z "\$NODE_IP" ] || [ "\$NODE_IP" == "null" ]; then
                                        NODE_IP=\$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
                                    fi
                                    
                                    echo \$NODE_IP > frontend_ip.txt
                                    echo "30000" > frontend_port.txt
                                    echo "nodeport" > service_type.txt
                                    echo "USE_NODEPORT=true" >> \$WORKSPACE/nodeport.env
                                fi
                            fi
                        fi
                        """
                    }
                    
                    // Load environment if NodePort fallback was used
                    script {
                        if (fileExists('nodeport.env')) {
                            def props = readProperties file: 'nodeport.env'
                            env.USE_NODEPORT = props.USE_NODEPORT ?: env.USE_NODEPORT
                        }
                    }
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
                    
                    // Get the frontend IP and port
                    def frontendIP = sh(script: 'cat frontend_ip.txt', returnStdout: true).trim()
                    def frontendPort = sh(script: 'cat frontend_port.txt', returnStdout: true).trim()
                    
                    sh """
                    # Create backend secret with dynamic origin
                    kubectl create secret generic backend-secret \
                        --from-literal=MONGO_URI="mongodb+srv://tsinghalbe22:BDUosPJHgGlYDoD2@cluster0.cwknfdr.mongodb.net/?retryWrites=true&w=majority&appName=Cluster0" \
                        --from-literal=ORIGIN="http://${frontendIP}:${frontendPort}" \
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
                    
                    // Get service configuration
                    def serviceType = sh(script: 'cat service_type.txt', returnStdout: true).trim()
                    def frontendIP = sh(script: 'cat frontend_ip.txt', returnStdout: true).trim()
                    
                    // Replace image tags in Kubernetes manifests
                    sh """
                    echo 'Updating frontend deployment.yaml'
                    sed -i 's|{{ACR_URL}}|${env.ACR_URL}|g' k8s/frontend/deployment.yaml
                    sed -i 's|{{BUILD_NUMBER}}|${BUILD_NUMBER}|g' k8s/frontend/deployment.yaml

                    echo 'Updating backend deployment.yaml'
                    sed -i 's|{{ACR_URL}}|${env.ACR_URL}|g' k8s/backend/deployment.yaml
                    sed -i 's|{{BUILD_NUMBER}}|${BUILD_NUMBER}|g' k8s/backend/deployment.yaml
                    
                    # Add image pull secrets to deployments
                    sed -i '/spec:/a\\      imagePullSecrets:\\n      - name: acr-secret' k8s/frontend/deployment.yaml
                    sed -i '/spec:/a\\      imagePullSecrets:\\n      - name: acr-secret' k8s/backend/deployment.yaml
                    """
                    
                    // Configure service based on type
                    if (serviceType == "loadbalancer") {
                        echo "Configuring frontend service for LoadBalancer with static IP"
                        sh """
                        # Update frontend service to use LoadBalancer with static IP
                        sed -i 's|type: NodePort|type: LoadBalancer|g' k8s/frontend/service.yaml
                        sed -i '/type: LoadBalancer/a\\  loadBalancerIP: ${frontendIP}' k8s/frontend/service.yaml
                        # Remove any nodePort specifications
                        sed -i '/nodePort:/d' k8s/frontend/service.yaml
                        """
                    } else {
                        echo "Configuring frontend service for NodePort"
                        sh """
                        # Update frontend service to use NodePort
                        sed -i 's|type: LoadBalancer|type: NodePort|g' k8s/frontend/service.yaml
                        sed -i '/loadBalancerIP:/d' k8s/frontend/service.yaml
                        # Add nodePort if not present
                        if ! grep -q "nodePort:" k8s/frontend/service.yaml; then
                            sed -i '/targetPort: 3000/a\\    nodePort: 30000' k8s/frontend/service.yaml
                        fi
                        """
                    }
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
                    echo "Waiting for deployments to be ready..."
                    kubectl rollout status deployment/frontend --timeout=300s
                    kubectl rollout status deployment/backend --timeout=300s
                    
                    echo "Pod status:"
                    kubectl get pods -l app=frontend
                    kubectl get pods -l app=backend
                    
                    echo "Service status:"
                    kubectl get services
                    """
                    
                    // Show access information based on service type
                    def serviceType = sh(script: 'cat service_type.txt', returnStdout: true).trim()
                    def frontendIP = sh(script: 'cat frontend_ip.txt', returnStdout: true).trim()
                    def frontendPort = sh(script: 'cat frontend_port.txt', returnStdout: true).trim()
                    
                    if (serviceType == "loadbalancer") {
                        sh """
                        echo "Checking LoadBalancer status..."
                        EXTERNAL_IP=\$(kubectl get service frontend -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
                        if [ ! -z "\$EXTERNAL_IP" ] && [ "\$EXTERNAL_IP" != "null" ]; then
                            echo "Frontend LoadBalancer IP: \$EXTERNAL_IP"
                        else
                            echo "LoadBalancer IP still pending, should be: ${frontendIP}"
                        fi
                        """
                    } else {
                        sh """
                        echo "NodePort service configured"
                        echo "Frontend accessible at: http://${frontendIP}:${frontendPort}"
                        """
                    }
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
                // Clean up temporary files
                sh """
                rm -f frontend_ip.txt frontend_port.txt service_type.txt nodeport.env || true
                """
            }
        }
        success {
            echo "Pipeline executed successfully!"
            script {
                if (params.ACTION == 'deploy') {
                    echo "Deployment completed successfully!"
                    echo "ACR URL: ${env.ACR_URL}"
                    echo "AKS Cluster: ${env.AKS_CLUSTER_NAME}"
                    
                    // Show final access information
                    def serviceType = sh(script: 'cat service_type.txt 2>/dev/null || echo "unknown"', returnStdout: true).trim()
                    def frontendIP = sh(script: 'cat frontend_ip.txt 2>/dev/null || echo "unknown"', returnStdout: true).trim()
                    def frontendPort = sh(script: 'cat frontend_port.txt 2>/dev/null || echo "unknown"', returnStdout: true).trim()
                    
                    sh """
                    echo "============================================="
                    echo "         DEPLOYMENT ACCESS INFORMATION      "
                    echo "============================================="
                    echo "Service Type: ${serviceType}"
                    echo "Frontend URL: http://${frontendIP}:${frontendPort}"
                    if [ "${serviceType}" == "nodeport" ]; then
                        echo "Note: Using NodePort due to public IP quota limits"
                        echo "Port 30000 is exposed on all cluster nodes"
                    else
                        echo "Note: Using LoadBalancer with static IP"
                        echo "IP will remain the same across deployments"
                    fi
                    echo "Backend URL: http://${frontendIP}:8000 (if exposed)"
                    echo "============================================="
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
