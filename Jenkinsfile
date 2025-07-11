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

        SONARQUBE_TOKEN = credentials('sonarqube-token')

        MONGO_URI = "mongodb+srv://tsinghalbe22:X7dFRYdqMdziFHCh@cluster0.cwknfdr.mongodb.net/?retryWrites=true\\&w=majority\\&appName=Cluster0"
        EMAIL = "test"                     // Set this in Jenkins credentials
        EMAIL_PASSWORD = "test"   // Set this in Jenkins credentials
        JWT_SECRET = "test"            // Set this in Jenkins credentials
        
        // Terraform state file paths
        TERRAFORM_DIR = './terraform/cluster'
        JENKINS_STATE_DIR = '/home/azureuser/jenkins'
        STATE_FILE = 'terraform.tfstate'
        BACKUP_STATE_FILE = 'terraform.tfstate.backup'
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('SonarQube Analysis') {
            steps {
                script {
                    // Using SonarQube Scanner tool
                    def scannerHome = tool 'SonarQube'
                    withSonarQubeEnv('SonarQube') {
                        sh """
                            ${scannerHome}/bin/sonar-scanner \\
                                -Dsonar.projectKey=xebia \\
                                -Dsonar.projectName="Xebia Project" \\
                                -Dsonar.projectVersion=1.0 \\
                                -Dsonar.sources=backend/models/ \\
                                -Dsonar.exclusions=**/node_modules/** \\
                                -Dsonar.host.url=\$SONAR_HOST_URL \\
                                -Dsonar.login=\$SONARQUBE_TOKEN
                        """
                    }
                }
            }
        }

        stage('Clean Docker Environment') {
    steps {
        script {
            sh """
                # Remove any existing images with the same tag
                docker rmi ${FRONTEND_IMAGE}:${env.BUILD_NUMBER} || true
                docker rmi ${BACKEND_IMAGE}:${env.BUILD_NUMBER} || true
                
                # Optional: Clean up dangling images and build cache
                docker system prune -f
            """
        }
    }
}
        
        stage('Build Docker Images') {
            steps {
                script {
                    def tag = "${env.BUILD_NUMBER}"
                    sh """
                        docker build --no-cache -t ${FRONTEND_IMAGE}:${tag} ./frontend
                        docker build --no-cache -t ${BACKEND_IMAGE}:${tag} ./backend
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
                        pwd
                        terraform init
                    """
                }
            }
        }
        
        stage('Terraform Plan') {
            steps {
                script {
                    sh """
                        cd ${TERRAFORM_DIR}
                        terraform plan \\
                  -var="client_id=${TF_VAR_client_id}" \\
                  -var="client_secret=${TF_VAR_client_secret}" \\
                  -var="tenant_id=${TF_VAR_tenant_id}" \\
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
                        pwd
                        terraform apply -auto-approve \\
                  -var="client_id=${TF_VAR_client_id}" \\
                  -var="client_secret=${TF_VAR_client_secret}" \\
                  -var="tenant_id=${TF_VAR_tenant_id}" \\
                  -var="subscription_id=${TF_VAR_subscription_id}"

                # Save state files back to Jenkins home for persistence
                cp ${STATE_FILE} ${JENKINS_STATE_DIR}/ || true
                cp ${BACKUP_STATE_FILE} ${JENKINS_STATE_DIR}/ || true

                # Get the public IP for deployment
                PUBLIC_IP=\$(terraform output -raw public_ip_2)
                echo "Azure VM Public IP: \$PUBLIC_IP"
                echo "\$PUBLIC_IP" > /home/public_ip.txt
                    """
                }
            }
        }

        stage('Inject Public IP into Environment Files') {
    steps {
        script {
            def publicIP = readFile("${WORKSPACE}/public_ip.txt").trim()

            sh """
                echo "🔧 Replacing placeholders in backend/.env and frontend/frontend.env"

                sed -i 's|{{ip}}|${publicIP}|g' backend/.env
                sed -i 's|{{mongo}}|${MONGO_URI}|g' backend/.env
                sed -i 's|{{email}}|${EMAIL}|g' backend/.env
                sed -i 's|{{email-pass}}|${EMAIL_PASSWORD}|g' backend/.env
                sed -i 's|{{jwt-key}}|${JWT_SECRET}|g' backend/.env

                sed -i 's|{{ip}}|${publicIP}|g' frontend/.env
            """
        }
    }
}

        stage('Configure Docker Compose') {
    steps {
        script {
            def tag = "${env.BUILD_NUMBER}"
            def frontendImage = "${env.FRONTEND_IMAGE}:${tag}"
            def backendImage = "${env.BACKEND_IMAGE}:${tag}"

            sh """
                # Replace placeholders in docker-compose.yml
                sed -i 's|{{frontend}}|${frontendImage}|g' docker-compose.yml
                sed -i 's|{{backend}}|${backendImage}|g' docker-compose.yml
            """
        }
    }
}

        
        stage('Run Ansible Playbook') {
    steps {
        script {
            def publicIP = readFile("${WORKSPACE}/public_ip.txt").trim()

            sh """
                cd ./ansible/cluster

                # Replace {{public}} placeholder with the actual public IP in inventory.ini
                sed -i 's/{{public}}/${publicIP}/g' inventory.ini

                # Run the Ansible playbook
                ansible-playbook -i inventory.ini deploy.yml \\
                    --ssh-extra-args="-o StrictHostKeyChecking=no"
            """
        }
    }
}

stage('Reload Prometheus Config') {
    steps {
        script {
            def publicIP = readFile("${WORKSPACE}/public_ip.txt").trim()
            sh """
                # Replace {{target}} with actual IP
                sed 's/{{target}}/${publicIP}/g' monitoring/prometheus.yml > /opt/monitoring-configs/prometheus.yml

                # Reload Prometheus config
                if [ \$(docker ps -q -f name=prometheus) ]; then
                    docker kill --signal=SIGHUP prometheus
                    echo "Prometheus config reloaded with IP ${publicIP}"
                else
                    echo "Prometheus is not running. Please start it manually or via Ansible."
                fi
            """
        }
    }
}
        
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
    }
}
