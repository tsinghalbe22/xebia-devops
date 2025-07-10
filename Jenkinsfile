stage('Inject Public IP into Environment Files') {
    steps {
        script {
            def publicIP = readFile("${WORKSPACE}/public_ip.txt").trim()
            sh """
                echo "🔧 Replacing placeholders in backend/.env and frontend/.env"
                
                # Set environment variables for substitution
                export PUBLIC_IP="${publicIP}"
                export MONGO_URI="${MONGO_URI}"
                export EMAIL="${EMAIL}"
                export EMAIL_PASSWORD="${EMAIL_PASSWORD}"
                export JWT_SECRET="${JWT_SECRET}"
                
                # First convert {{placeholder}} format to \${VARIABLE} format for envsubst
                sed -i 's|{{ip}}|\${PUBLIC_IP}|g' backend/.env
                sed -i 's|{{mongo}}|\${MONGO_URI}|g' backend/.env
                sed -i 's|{{email}}|\${EMAIL}|g' backend/.env
                sed -i 's|{{email-pass}}|\${EMAIL_PASSWORD}|g' backend/.env
                sed -i 's|{{jwt-key}}|\${JWT_SECRET}|g' backend/.env
                
                # Handle frontend/.env if it exists and has placeholders
                if [ -f "frontend/.env" ]; then
                    sed -i 's|{{ip}}|\${PUBLIC_IP}|g' frontend/.env
                    envsubst < frontend/.env > frontend/.env.tmp && mv frontend/.env.tmp frontend/.env
                fi
                
                # Now use envsubst to replace the variables in backend/.env
                envsubst < backend/.env > backend/.env.tmp && mv backend/.env.tmp backend/.env
                
                echo "✅ Environment files updated successfully"
                
                # Debug: Show what was actually replaced
                echo "🔍 Backend .env contents:"
                cat backend/.env
                if [ -f "frontend/.env" ]; then
                    echo "🔍 Frontend .env contents:"
                    cat frontend/.env
                fi
            """
        }
    }
}
