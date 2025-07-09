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

        stage('Setup Static IPs') {
    when {
        expression { params.ACTION == 'deploy' }
    }
    steps {
        script {
            echo "Setting up static IPs for frontend and backend"
            sh """
            NODE_RG=\$(az aks show --resource-group ${env.RESOURCE_GROUP_NAME} --name ${env.AKS_CLUSTER_NAME} --query "nodeResourceGroup" -o tsv)

            # Frontend static IP
            if ! az network public-ip show --resource-group \$NODE_RG --name ${env.STATIC_IP_NAME} > /dev/null 2>&1; then
                echo "Creating frontend static IP..."
                az network public-ip create \
                    --resource-group \$NODE_RG \
                    --name ${env.STATIC_IP_NAME} \
                    --sku Standard \
                    --allocation-method static
            fi
            FRONTEND_IP=\$(az network public-ip show --resource-group \$NODE_RG --name ${env.STATIC_IP_NAME} --query "ipAddress" -o tsv)
            echo \$FRONTEND_IP > static_ip.txt

            # Backend static IP
            BACKEND_STATIC_IP_NAME="backend-static-ip"
            if ! az network public-ip show --resource-group \$NODE_RG --name \$BACKEND_STATIC_IP_NAME > /dev/null 2>&1; then
                echo "Creating backend static IP..."
                az network public-ip create \
                    --resource-group \$NODE_RG \
                    --name \$BACKEND_STATIC_IP_NAME \
                    --sku Standard \
                    --allocation-method static
            fi
            BACKEND_IP=\$(az network public-ip show --resource-group \$NODE_RG --name \$BACKEND_STATIC_IP_NAME --query "ipAddress" -o tsv)
            echo \$BACKEND_IP > backend_static_ip.txt
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
            az acr update --name ${env.ACR_NAME} --admin-enabled true
            ACR_PASSWORD=\$(az acr credential show --name ${env.ACR_NAME} --query "passwords[0].value" -o tsv)
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
            def frontendIP = sh(script: 'cat static_ip.txt', returnStdout: true).trim()
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
            def frontendIP = sh(script: 'cat static_ip.txt', returnStdout: true).trim()
            def backendIP = sh(script: 'cat backend_static_ip.txt', returnStdout: true).trim()

            sh """
            sed -i 's|{{ACR_URL}}|${env.ACR_URL}|g' k8s/frontend/deployment.yaml
            sed -i 's|{{BUILD_NUMBER}}|${BUILD_NUMBER}|g' k8s/frontend/deployment.yaml
            sed -i 's|{{ACR_URL}}|${env.ACR_URL}|g' k8s/backend/deployment.yaml
            sed -i 's|{{BUILD_NUMBER}}|${BUILD_NUMBER}|g' k8s/backend/deployment.yaml

            # Set both services to LoadBalancer and assign static IPs
            sed -i 's|type: NodePort|type: LoadBalancer|g' k8s/frontend/service.yaml
            sed -i '/type: LoadBalancer/a\\  loadBalancerIP: ${frontendIP}' k8s/frontend/service.yaml
            sed -i 's|type: NodePort|type: LoadBalancer|g' k8s/backend/service.yaml
            sed -i '/type: LoadBalancer/a\\  loadBalancerIP: ${backendIP}' k8s/backend/service.yaml

            # Add imagePullSecrets to both deployments
            sed -i '/spec:/a\\      imagePullSecrets:\\n      - name: acr-secret' k8s/frontend/deployment.yaml
            sed -i '/spec:/a\\      imagePullSecrets:\\n      - name: acr-secret' k8s/backend/deployment.yaml
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
            echo "Waiting for deployments to be ready..."
            kubectl rollout status deployment/frontend --timeout=300s
            kubectl rollout status deployment/backend --timeout=300s
            
            echo "Pod status:"
            kubectl get pods -l app=frontend
            kubectl get pods -l app=backend
            
            echo "Service status:"
            kubectl get services
            
            echo "Getting frontend external IP..."
            FRONTEND_IP=\$(kubectl get service frontend -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
            echo "Frontend accessible at: http://\$FRONTEND_IP:3000"

            echo "Getting backend external IP..."
            BACKEND_IP=\$(kubectl get service backend -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
            echo "Backend accessible at: http://\$BACKEND_IP:8000"
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
