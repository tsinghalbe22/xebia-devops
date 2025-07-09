pipeline {
    agent any

    environment {
        CLIENT_ID = credentials('azure-client-id')
        CLIENT_SECRET = credentials('azure-client-secret')
        TENANT_ID = credentials('azure-tenant-id')
        SUBSCRIPTION_ID = credentials('azure-subscription-id')
        ACR_URL = ""  // This will be set later
        AKS_API_SERVER = ""
        RESOURCE_GROUP_NAME = ""
        ACR_NAME = ""
        AKS_CLUSTER_NAME = ""
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
                        
                        // Switch to the /home/jenkins directory to access the tfstate
                        sh "cd /home/jenkins"
                        
                        // Capture outputs from Terraform
                        env.ACR_URL = sh(script: "terraform output -raw acr_url", returnStdout: true).trim()
                        env.ACR_NAME = sh(script: "terraform output -raw acr_name", returnStdout: true).trim()
                        env.AKS_API_SERVER = sh(script: "terraform output -raw aks_api_server", returnStdout: true).trim()
                        env.AKS_CLUSTER_NAME = sh(script: "terraform output -raw aks_cluster_name", returnStdout: true).trim()
                        env.RESOURCE_GROUP_NAME = sh(script: "terraform output -raw resource_group_name", returnStdout: true).trim()

                        // Output for debugging
                        echo "ACR URL: ${env.ACR_URL}"
                        echo "ACR Name: ${env.ACR_NAME}"
                        echo "AKS API Server: ${env.AKS_API_SERVER}"
                        echo "AKS Cluster Name: ${env.AKS_CLUSTER_NAME}"
                        echo "Resource Group: ${env.RESOURCE_GROUP_NAME}"
                    }
                }
            }
        }

        // Other stages go here...
    }

    post {
        always {
            script {
                // Clean up Docker images
                sh """
                docker system prune -af --volumes || true
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
