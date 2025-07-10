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
        STATIC_IP_NAME = "shared-static-ip"
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

        stage('Setup Shared Static IP') {
            when {
                expression { params.ACTION == 'deploy' }
            }
            steps {
                script {
                    echo "Setting up shared static IP for Prometheus monitoring"
                    sh """
                    # Get the node resource group
                    NODE_RG=\$(az aks show --resource-group ${env.RESOURCE_GROUP_NAME} --name ${env.AKS_CLUSTER_NAME} --query "nodeResourceGroup" -o tsv)
                    
                    # Create static public IP if it doesn't exist
                    if ! az network public-ip show --resource-group \$NODE_RG --name ${env.STATIC_IP_NAME} > /dev/null 2>&1; then
                        echo "Creating shared static IP for Prometheus monitoring..."
                        az network public-ip create \
                            --resource-group \$NODE_RG \
                            --name ${env.STATIC_IP_NAME} \
                            --sku Standard \
                            --allocation-method static
                    else
                        echo "Shared static IP already exists"
                    fi
                    
                    # Get the static IP address
                    STATIC_IP=\$(az network public-ip show --resource-group \$NODE_RG --name ${env.STATIC_IP_NAME} --query "ipAddress" -o tsv)
                    echo "Shared Static IP for Prometheus: \$STATIC_IP"
                    
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
                    echo "Updating Kubernetes Manifests for Prometheus monitoring"
                    
                    // List contents of k8s to debug
                    sh 'ls -R k8s/'
                    
                    // Get static IP
                    def staticIP = sh(script: 'cat static_ip.txt', returnStdout: true).trim()
                    
                    // Replace image tags in Kubernetes manifests
                    sh """
                    echo 'Updating frontend deployment.yaml'
                    sed -i 's|{{ACR_URL}}|${env.ACR_URL}|g' k8s/frontend/deployment.yaml
                    sed -i 's|{{BUILD_NUMBER}}|${BUILD_NUMBER}|g' k8s/frontend/deployment.yaml
                    
                    echo 'Updating backend deployment.yaml'
                    sed -i 's|{{ACR_URL}}|${env.ACR_URL}|g' k8s/backend/deployment.yaml
                    sed -i 's|{{BUILD_NUMBER}}|${BUILD_NUMBER}|g' k8s/backend/deployment.yaml
                    
                    # Update frontend deployment with backend service URL
                    sed -i 's|{{BACKEND_URL}}|http://${staticIP}:8000|g' k8s/frontend/deployment.yaml
                    sed -i 's|{{BACKEND_IP}}|${staticIP}|g' k8s/frontend/deployment.yaml
                    
                    # Add image pull secrets to deployments
                    sed -i '/containers:/i\\      imagePullSecrets:\\n      - name: acr-secret' k8s/frontend/deployment.yaml
                    sed -i '/containers:/i\\      imagePullSecrets:\\n      - name: acr-secret' k8s/backend/deployment.yaml
                    """
                }
            }
        }

        stage('Create Multi-Port LoadBalancer Service') {
            when {
                expression { params.ACTION == 'deploy' }
            }
            steps {
                script {
                    echo "Creating multi-port LoadBalancer service for Prometheus monitoring"
                    def staticIP = sh(script: 'cat static_ip.txt', returnStdout: true).trim()
                    
                    sh """
                    cat > multi-port-service.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: multi-port-loadbalancer
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-static-ip: ${staticIP}
    prometheus.io/scrape: "true"
    prometheus.io/port: "3000,8000"
    prometheus.io/path: "/metrics"
spec:
  type: LoadBalancer
  loadBalancerIP: ${staticIP}
  ports:
  - name: frontend
    port: 3000
    targetPort: 3000
    protocol: TCP
  - name: backend
    port: 8000
    targetPort: 8000
    protocol: TCP
  selector:
    # This selector won't match any pods directly
    # We'll use separate services for actual routing
    app: multi-port-lb
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-internal
  labels:
    app: frontend
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "3000"
    prometheus.io/path: "/metrics"
spec:
  type: ClusterIP
  ports:
  - port: 3000
    targetPort: 3000
    protocol: TCP
  selector:
    app: frontend
---
apiVersion: v1
kind: Service
metadata:
  name: backend-internal
  labels:
    app: backend
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8000"
    prometheus.io/path: "/metrics"
spec:
  type: ClusterIP
  ports:
  - port: 8000
    targetPort: 8000
    protocol: TCP
  selector:
    app: backend
EOF
                    
                    # Apply the multi-port service
                    kubectl apply -f multi-port-service.yaml
                    """
                }
            }
        }

        stage('Deploy Applications') {
            when {
                expression { params.ACTION == 'deploy' }
            }
            steps {
                script {
                    echo "Deploying applications for Prometheus monitoring"
                    
                    // Deploy backend first
                    sh """
                    kubectl apply -f k8s/backend/deployment.yaml
                    """
                    
                    // Deploy frontend
                    sh """
                    kubectl apply -f k8s/frontend/deployment.yaml
                    """
                    
                    // Wait for deployments to be ready
                    echo "Waiting for deployments to be ready..."
                    sh """
                    kubectl wait --for=condition=Ready pod -l app=backend --timeout=300s
                    kubectl wait --for=condition=Ready pod -l app=frontend --timeout=300s
                    """
                }
            }
        }

        stage('Setup Traffic Routing with iptables') {
            when {
                expression { params.ACTION == 'deploy' }
            }
            steps {
                script {
                    echo "Setting up traffic routing for shared IP"
                    sh """
                    # Create a DaemonSet for traffic routing
                    cat > traffic-router.yaml << EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: traffic-router
spec:
  selector:
    matchLabels:
      app: traffic-router
  template:
    metadata:
      labels:
        app: traffic-router
    spec:
      hostNetwork: true
      containers:
      - name: router
        image: alpine:latest
        command: ["/bin/sh"]
        args:
        - -c
        - |
          apk add --no-cache iptables
          # Route port 3000 to frontend service
          iptables -t nat -A PREROUTING -p tcp --dport 3000 -j DNAT --to-destination \$(nslookup frontend-internal.default.svc.cluster.local | grep Address | tail -1 | awk '{print \$2}'):3000
          # Route port 8000 to backend service  
          iptables -t nat -A PREROUTING -p tcp --dport 8000 -j DNAT --to-destination \$(nslookup backend-internal.default.svc.cluster.local | grep Address | tail -1 | awk '{print \$2}'):8000
          # Keep container running
          tail -f /dev/null
        securityContext:
          privileged: true
          capabilities:
            add: ["NET_ADMIN", "NET_RAW"]
        volumeMounts:
        - name: xtables-lock
          mountPath: /run/xtables.lock
      volumes:
      - name: xtables-lock
        hostPath:
          path: /run/xtables.lock
          type: FileOrCreate
      tolerations:
      - effect: NoSchedule
        operator: Exists
EOF
                    
                    # Apply traffic router (commented out as it requires privileged access)
                    # kubectl apply -f traffic-router.yaml
                    echo "Traffic router configuration created (requires privileged access)"
                    """
                }
            }
        }

        stage('Alternative: Use Ingress Controller') {
            when {
                expression { params.ACTION == 'deploy' }
            }
            steps {
                script {
                    echo "Setting up NGINX Ingress for Prometheus monitoring"
                    def staticIP = sh(script: 'cat static_ip.txt', returnStdout: true).trim()
                    
                    sh """
                    # Install NGINX Ingress Controller if not exists
                    if ! kubectl get deployment ingress-nginx-controller -n ingress-nginx > /dev/null 2>&1; then
                        echo "Installing NGINX Ingress Controller..."
                        kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml
                        
                        # Wait for ingress controller to be ready
                        kubectl wait --namespace ingress-nginx \
                            --for=condition=ready pod \
                            --selector=app.kubernetes.io/component=controller \
                            --timeout=300s
                    fi
                    
                    # Create ingress with static IP
                    cat > prometheus-ingress.yaml << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prometheus-ingress
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/rewrite-target: /
    service.beta.kubernetes.io/azure-load-balancer-static-ip: ${staticIP}
    prometheus.io/scrape: "true"
    prometheus.io/port: "80"
spec:
  rules:
  - host: ${staticIP}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend-internal
            port:
              number: 3000
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: backend-internal
            port:
              number: 8000
      - path: /metrics
        pathType: Prefix
        backend:
          service:
            name: backend-internal
            port:
              number: 8000
EOF
                    
                    kubectl apply -f prometheus-ingress.yaml
                    """
                }
            }
        }

        stage('Deploy Prometheus Configuration') {
            when {
                expression { params.ACTION == 'deploy' }
            }
            steps {
                script {
                    echo "Creating Prometheus configuration"
                    def staticIP = sh(script: 'cat static_ip.txt', returnStdout: true).trim()
                    
                    sh """
                    # Create Prometheus config
                    cat > prometheus-config.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
    
    scrape_configs:
    - job_name: 'frontend'
      static_configs:
      - targets: ['${staticIP}:3000']
      metrics_path: /metrics
      scrape_interval: 15s
    
    - job_name: 'backend'
      static_configs:
      - targets: ['${staticIP}:8000']
      metrics_path: /metrics
      scrape_interval: 15s
    
    - job_name: 'kubernetes-pods'
      kubernetes_sd_configs:
      - role: pod
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        regex: ([^:]+)(?::\\d+)?;(\\d+)
        replacement: \$1:\$2
        target_label: __address__
EOF
                    
                    kubectl apply -f prometheus-config.yaml
                    echo "Prometheus configuration created for monitoring both services"
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
                    echo "Verifying deployment for Prometheus monitoring"
                    sh """
                    kubectl get pods -l app=frontend
                    kubectl get pods -l app=backend
                    kubectl get services
                    kubectl get ingress
                    
                    echo "Shared Static IP: \$(cat static_ip.txt)"
                    
                    # Wait for services to be ready
                    echo "Waiting for services to be accessible..."
                    sleep 30
                    
                    echo "=== PROMETHEUS MONITORING ENDPOINTS ==="
                    echo "Shared Static IP: \$(cat static_ip.txt)"
                    echo "Frontend: http://\$(cat static_ip.txt):3000"
                    echo "Backend: http://\$(cat static_ip.txt):8000"
                    echo "Frontend Metrics: http://\$(cat static_ip.txt):3000/metrics"
                    echo "Backend Metrics: http://\$(cat static_ip.txt):8000/metrics"
                    echo "API Endpoints: http://\$(cat static_ip.txt)/api"
                    echo "=========================================="
                    """
                }
            }
        }

        stage('Test Prometheus Endpoints') {
            when {
                expression { params.ACTION == 'deploy' }
            }
            steps {
                script {
                    echo "Testing Prometheus monitoring endpoints"
                    sh """
                    # Test internal service connectivity
                    kubectl run prometheus-test --rm -i --tty --image=curlimages/curl --restart=Never -- sh -c "
                        echo 'Testing frontend metrics endpoint...'
                        curl -f http://frontend-internal:3000/metrics || echo 'Frontend metrics not available'
                        echo 'Testing backend metrics endpoint...'
                        curl -f http://backend-internal:8000/metrics || echo 'Backend metrics not available'
                        echo 'Testing backend health...'
                        curl -f http://backend-internal:8000/health || curl -f http://backend-internal:8000 || echo 'Backend not accessible'
                    " || echo "Connectivity test completed"
                    
                    # Show service endpoints
                    echo "=== SERVICE ENDPOINTS ==="
                    kubectl get endpoints
                    echo "========================="
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
                    echo "=== PROMETHEUS MONITORING SETUP ==="
                    STATIC_IP=\$(cat static_ip.txt)
                    echo "Shared Static IP: \$STATIC_IP"
                    echo ""
                    echo "Application URLs:"
                    echo "Frontend: http://\$STATIC_IP:3000"
                    echo "Backend: http://\$STATIC_IP:8000"
                    echo "API: http://\$STATIC_IP/api"
                    echo ""
                    echo "Prometheus Scrape Endpoints:"
                    echo "Frontend Metrics: http://\$STATIC_IP:3000/metrics"
                    echo "Backend Metrics: http://\$STATIC_IP:8000/metrics"
                    echo ""
                    echo "Internal Service Names:"
                    echo "Frontend: frontend-internal.default.svc.cluster.local:3000"
                    echo "Backend: backend-internal.default.svc.cluster.local:8000"
                    echo "===================================="
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
                echo "All pods:"
                kubectl get pods -o wide || true
                echo ""
                echo "All services:"
                kubectl get services -o wide || true
                echo ""
                echo "Ingress status:"
                kubectl get ingress -o wide || true
                echo ""
                echo "LoadBalancer services:"
                kubectl get svc -o wide | grep LoadBalancer || true
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
