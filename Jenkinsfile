pipeline {
    agent any

    environment {
        CLIENT_ID = credentials('azure-client-id')
        CLIENT_SECRET = credentials('azure-client-secret')
        TENANT_ID = credentials('azure-tenant-id')
        SUBSCRIPTION_ID = credentials('azure-subscription-id')
        ACR_URL = "dockeracrxyz.azurecr.io"
        RESOURCE_GROUP_NAME = "docker-vm-rg"  // Fixed: matches your main.tf
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

        stage('Terraform Init - Second VM') {
            steps {
                script {
                    dir('terraform/cluster') {  // Changed path to be more specific
                        sh '''
                if [ -f /home/jenkins/terraform.tfstate ]; then
                    cp /home/jenkins/terraform.tfstate .
                else
                    echo "terraform.tfstate not found, skipping copy."
                fi

                terraform init
                '''
                    }
                }
            }
        }

        stage('Terraform Plan - Second VM') {
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

        stage('Terraform Apply - Second VM') {
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

        stage('Get Second VM IP') {
            when {
                expression { params.ACTION == 'deploy' }
            }
            steps {
                script {
                    dir('terraform/cluster') {
                        sh '''
                        # Get the public IP of the second VM
                        SECOND_VM_IP=$(terraform output -raw public_ip_vm_2)
                        echo "Second VM Public IP: $SECOND_VM_IP"
                        echo $SECOND_VM_IP > ../second_vm_ip.txt
                        '''
                    }
                }
            }
        }

        stage('Wait for VM Ready') {
            when {
                expression { params.ACTION == 'deploy' }
            }
            steps {
                script {
                    sh '''
                    # Get the second VM IP
                    SECOND_VM_IP=$(cat terraform/second_vm_ip.txt)
                    echo "Waiting for VM to be accessible at: $SECOND_VM_IP"
                    
                    # Wait for VM to be ready for SSH
                    echo "Waiting for SSH to be available..."
                    timeout 300 bash -c "until nc -z $SECOND_VM_IP 22; do sleep 5; done"
                    
                    # Test SSH connectivity
                    sshpass -p 'Test1!' ssh -o StrictHostKeyChecking=no azureuser@$SECOND_VM_IP 'echo "VM is ready for configuration"'
                    
                    echo "VM is ready for Ansible configuration"
                    '''
                }
            }
        }

        stage('Run Ansible Playbook') {
            when {
                expression { params.ACTION == 'deploy' }
            }
            steps {
                script {
                    sh '''
                    # Get the second VM IP
                    SECOND_VM_IP=$(cat terraform/second_vm_ip.txt)
                    echo "Running Ansible playbook on VM: $SECOND_VM_IP"
                    
                    # Create dynamic inventory file
                    cat > inventory.ini << EOF
[docker_vms]
$SECOND_VM_IP ansible_user=azureuser ansible_password=Test1! ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF
                    
                    # Run Ansible playbook
                    ansible-playbook -i inventory.ini playbooks/docker-setup.yml
                    
                    echo "Ansible configuration completed"
                    '''
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

        stage('Terraform Destroy - Second VM') {
            when {
                allOf {
                    expression { params.ACTION == 'destroy' }
                    expression { !params.SKIP_TERRAFORM_DESTROY }
                }
            }
            steps {
                script {
                    echo "Destroying Second VM Terraform resources"
                    dir('terraform/second-vm') {
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
                    
                    // Show access information
                    sh """
                    echo "=== DEPLOYMENT INFORMATION ==="
                    if [ -f terraform/second_vm_ip.txt ]; then
                        SECOND_VM_IP=\$(cat terraform/second_vm_ip.txt)
                        echo "Second VM IP: \$SECOND_VM_IP"
                        echo ""
                        echo "Application URLs on Second VM:"
                        echo "Frontend: http://\$SECOND_VM_IP:3000"
                        echo "Backend: http://\$SECOND_VM_IP:8000"
                        echo ""
                        echo "SSH Access:"
                        echo "ssh azureuser@\$SECOND_VM_IP (password: Test1!)"
                    else
                        echo "Second VM IP file not found"
                    fi
                    echo "================================"
                    """
                }
            }
        }
        failure {
            echo "Pipeline failed!"
            script {
                // Get debugging information
                sh """
                echo "=== DEBUGGING INFORMATION ==="
                echo "Current directory contents:"
                ls -la
                echo ""
                echo "Terraform directory contents:"
                ls -la terraform/ || true
                echo ""
                echo "Azure resources in resource group:"
                az resource list --resource-group ${RESOURCE_GROUP_NAME} --output table || true
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
