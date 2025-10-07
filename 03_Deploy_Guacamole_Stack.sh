#!/bin/bash
# 03_deploy-guacamole-stack.sh
# This script deploys the Guacamole stack using docker-compose on the remote Synology NAS.
# Prerequisite: Run 02_setup-guacamole-manager.sh first to configure remote Docker access.

set -e

# Load configuration from JSON file
CONFIG_FILE="00_Guacamole-Manager_Config.json"
if [[ -f "$CONFIG_FILE" ]]; then
    echo "Loading configuration from $CONFIG_FILE..."
    source ./01A_Load_Config.sh "$CONFIG_FILE"
else
    echo "Configuration file not found: $CONFIG_FILE"
    echo "Please ensure the config file exists or run the setup script first."
    exit 1
fi

# Activate Python virtual environment if it exists and not already activated
if [[ -f "venv/bin/activate" && -z "$VIRTUAL_ENV" ]]; then
    echo "Activating Python virtual environment..."
    source venv/bin/activate
fi

# Get Synology connection details from configuration
echo "[1/4] Getting Synology connection details from config..."
echo "Using configuration:"
echo "  Synology IP: $SYNOLOGY_IP"  
echo "  SSH Username: $SSH_USERNAME"
echo "  SSH Port: $SSH_PORT"
echo "  Base Path: $SYNOLOGY_BASE_PATH"
echo ""
read -s -p "Enter SSH password for $SSH_USERNAME@$SYNOLOGY_IP: " SSH_PASS
echo ""

# Test SSH connection
echo "Testing SSH connection to Synology..."
if ! sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "echo 'SSH connection successful'" > /dev/null 2>&1; then
    echo "SSH connection failed. Please check your credentials."
    exit 1
fi

echo "SSH connection verified"

# Use Docker path from configuration
DOCKER_FOUND="$DOCKER_PATH"
echo "Using Docker from configuration: $DOCKER_FOUND"

# Verify Docker exists
if ! sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "test -f $DOCKER_FOUND" 2>/dev/null; then
    echo "Docker not found at configured path: $DOCKER_FOUND"
    echo "Please check the configuration file."
    exit 1
fi

echo "Docker verified at: $DOCKER_FOUND"

# Check if docker-compose file exists
echo "[2/4] Checking docker-compose configuration..."
if [[ ! -f "docker-compose.yml" ]]; then
    echo "docker-compose.yml not found in current directory."
    echo "Please ensure you're in the guacamole-manager directory."
    exit 1
fi

echo "Found docker-compose.yml"

# Quick validation that setup was completed
echo "[3/4] Verifying setup prerequisites..."
if ! sshpass -p "$SSH_PASS" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "test -d $SYNOLOGY_BASE_PATH" 2>/dev/null; then
    echo "Synology folder structure not found at: $SYNOLOGY_BASE_PATH"
    echo "Please run the setup script first: ./02_setup-guacamole-manager.sh"
    exit 1
fi

echo "Prerequisites validated"

# Show current status
echo "[4/4] Current Docker status on Synology..."
echo "Running containers:"
DOCKER_PS_OUTPUT=$(sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "echo '$SSH_PASS' | sudo -S $DOCKER_FOUND ps" 2>&1)
if [[ "$DOCKER_PS_OUTPUT" == *"Password:"* ]]; then
    echo "$DOCKER_PS_OUTPUT" | sed 's/.*Password: //' | head -10
else
    echo "$DOCKER_PS_OUTPUT" | head -10
fi

echo ""
echo "Guacamole-related containers:"
GUAC_CONTAINERS=$(sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "echo '$SSH_PASS' | sudo -S $DOCKER_FOUND ps -a" 2>&1 | grep -i guac || echo "No Guacamole containers found")
echo "$GUAC_CONTAINERS"

# Deploy the stack
echo ""
echo "Ready to deploy Guacamole stack!"

read -p "Do you want to deploy/update the Guacamole stack? (y/N): " DEPLOY_CONFIRM
if [[ "$DEPLOY_CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Preparing deployment..."
    
    # Create deployment directory on Synology
    echo "Creating deployment directory: $FOLDER_DEPLOY"
    CREATE_DIR_RESULT=$(sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "mkdir -p $FOLDER_DEPLOY && echo 'Directory created successfully'" 2>&1)
    if [[ "$CREATE_DIR_RESULT" == *"Directory created successfully"* ]]; then
        echo "Deployment directory ready"
    else
        echo "Warning: Could not create deployment directory"
        echo "Output: $CREATE_DIR_RESULT"
        echo "Continuing anyway..."
    fi
    
    # Verify directory exists and has proper permissions
    echo "Verifying deployment directory permissions..."
    DIR_CHECK=$(sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "ls -ld $FOLDER_DEPLOY" 2>&1)
    echo "Directory status: $DIR_CHECK"
    
    # Generate .env file for docker-compose from configuration
    echo "Generating .env file from configuration..."
    cat > .env << EOF
# Generated from $CONFIG_FILE
POSTGRES_DB=$POSTGRES_DB
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_PORT=$POSTGRES_PORT
GUACAMOLE_VERSION=$GUACAMOLE_VERSION
GUACAMOLE_PORT=$GUACAMOLE_PORT
GUACD_PORT=$GUACD_PORT
DB_IP=$DB_IP
GUACD_IP=$GUACD_IP
GUACAMOLE_IP=$GUACAMOLE_IP
NGINX_IP=$NGINX_IP
GUACAMOLE_SUBNET=$GUACAMOLE_SUBNET
GUACAMOLE_GATEWAY=$GUACAMOLE_GATEWAY
PARENT_INTERFACE=$PARENT_INTERFACE
FOLDER_DB=$FOLDER_DB
FOLDER_DBINIT=$FOLDER_DBINIT
FOLDER_HOME=$FOLDER_HOME
FOLDER_DRIVE=$FOLDER_DRIVE
FOLDER_RECORD=$FOLDER_RECORD
FOLDER_EXTENSIONS=$FOLDER_EXTENSIONS
FOLDER_NGINX_LOGS=$FOLDER_NGINX_LOGS
HTTP_PORT=$HTTP_PORT
HTTPS_PORT=$HTTPS_PORT
LDAP_HOSTNAME=${LDAP_HOSTNAME:-}
LDAP_PORT=${LDAP_PORT:-389}
LDAP_USER_BASE_DN=${LDAP_USER_BASE_DN:-}
LDAP_USERNAME_ATTRIBUTE=${LDAP_USERNAME_ATTRIBUTE:-}
LDAP_GROUP_BASE_DN=${LDAP_GROUP_BASE_DN:-}
EOF
    
    # Copy docker-compose.yml and config files to Synology
    echo "Copying configuration files to $FOLDER_DEPLOY..."
    
    # Test SSH file creation access
    echo "Testing SSH file access to Synology..."
    TEST_SSH=$(echo "test" | sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "cat > $FOLDER_DEPLOY/test.txt && echo 'SSH file access successful' || echo 'SSH file access failed'" 2>&1)
    if [[ "$TEST_SSH" == *"SSH file access successful"* ]]; then
        echo "SSH file access verified"
        # Clean up test file
        sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "rm -f $FOLDER_DEPLOY/test.txt" 2>/dev/null
    else
        echo "SSH file access test failed: $TEST_SSH"
        echo ""
        echo "Please check:"
        echo "1. SSH connection: ssh -p $SSH_PORT $SSH_USERNAME@$SYNOLOGY_IP"
        echo "2. Directory permissions: ls -la $SYNOLOGY_BASE_PATH"
        echo "3. Write permissions on deployment folder"
        exit 1
    fi
    
    # Validate docker-compose.yml before copying
    echo "  Validating docker-compose.yml..."
    if command -v docker-compose &> /dev/null; then
        docker-compose -f docker-compose.yml config > /dev/null 2>&1
        if [[ $? -eq 0 ]]; then
            echo "    docker-compose.yml validation: OK"
        else
            echo "    docker-compose.yml validation: FAILED"
            echo "    Please check your docker-compose.yml file for syntax errors"
            exit 1
        fi
    else
        echo "    docker-compose not available locally, skipping validation"
    fi
    
    # Copy docker-compose.yml via SSH
    echo "  Copying docker-compose.yml via SSH..."
    cat docker-compose.yml | sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "cat > $FOLDER_DEPLOY/docker-compose.yml"
    if [[ $? -eq 0 ]]; then
        echo "    docker-compose.yml copied successfully"
    else
        echo "    Failed to copy docker-compose.yml"
        exit 1
    fi
    
    # Validate .env file before copying
    echo "  Validating .env file..."
    if [[ -f ".env" ]]; then
        # Check for required variables
        REQUIRED_VARS=("POSTGRES_DB" "POSTGRES_USER" "POSTGRES_PASSWORD" "GUACAMOLE_PORT")
        MISSING_VARS=()
        
        for var in "${REQUIRED_VARS[@]}"; do
            if ! grep -q "^${var}=" .env; then
                MISSING_VARS+=("$var")
            fi
        done
        
        if [[ ${#MISSING_VARS[@]} -eq 0 ]]; then
            echo "    .env file validation: OK"
        else
            echo "    .env file validation: FAILED"
            echo "    Missing required variables: ${MISSING_VARS[*]}"
            exit 1
        fi
    else
        echo "    .env file not found!"
        exit 1
    fi
    
    # Copy .env file via SSH
    echo "  Copying .env file via SSH..."
    cat .env | sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "cat > $FOLDER_DEPLOY/.env"
    if [[ $? -eq 0 ]]; then
        echo "    .env file copied successfully"
    else
        echo "    Failed to copy .env file"
        exit 1
    fi
    
    # Verify files were copied correctly
    echo ""
    echo "Verifying copied files..."
    FILE_LIST=$(sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "ls -la $FOLDER_DEPLOY/" 2>&1)
    echo "Files in deployment directory:"
    echo "$FILE_LIST"
    echo ""
    
    # Copy config directory if it exists
    if [[ -d "config" ]]; then
        echo "  Copying config directory via SSH..."
        tar -czf - config | sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "cd $FOLDER_DEPLOY && tar -xzf -"
        if [[ $? -eq 0 ]]; then
            echo "    config directory copied successfully"
        else
            echo "    Warning: Could not copy config directory"
        fi
    fi
    
    # Validate docker-compose.yml on remote before deployment
    echo ""
    echo "Validating docker-compose.yml on remote system..."
    REMOTE_VALIDATION=$(sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "cd $FOLDER_DEPLOY && $DOCKER_COMPOSE_PATH config" 2>&1)
    if [[ $? -eq 0 ]]; then
        echo "  Remote docker-compose validation: OK"
    else
        echo "  Remote docker-compose validation: FAILED"
        echo "  Error: $REMOTE_VALIDATION"
        exit 1
    fi
    
    # Deploy with docker-compose with real-time monitoring
    echo ""
    echo "============================================"
    echo "Starting Guacamole stack deployment..."
    echo "============================================"
    echo ""
    
    # First, stop any existing containers
    echo "Stopping any existing Guacamole containers..."
    sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "cd $FOLDER_DEPLOY && echo '$SSH_PASS' | sudo -S $DOCKER_COMPOSE_PATH down" 2>/dev/null || true
    
    echo "Starting new containers..."
    echo "Command: docker-compose up -d"
    echo ""
    
    # Deploy and capture output in real-time
    sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "cd $FOLDER_DEPLOY && echo '$SSH_PASS' | sudo -S $DOCKER_COMPOSE_PATH up -d 2>&1"
    DEPLOY_EXIT_CODE=$?
    
    echo ""
    if [[ $DEPLOY_EXIT_CODE -eq 0 ]]; then
        echo "Docker deployment command completed successfully!"
    else
        echo "Docker deployment command failed with exit code: $DEPLOY_EXIT_CODE"
        exit 1
    fi
    
    # Monitor container startup
    echo ""
    echo "Monitoring container startup..."
    for i in {1..30}; do
        echo "  Checking containers (attempt $i/30)..."
        CONTAINER_STATUS=$(sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "cd $FOLDER_DEPLOY && $DOCKER_COMPOSE_PATH ps --format table" 2>&1)
        
        # Count running containers
        RUNNING_COUNT=$(echo "$CONTAINER_STATUS" | grep -c "Up" || echo "0")
        TOTAL_COUNT=$(echo "$CONTAINER_STATUS" | grep -c "guac" || echo "0")
        
        echo "    Running containers: $RUNNING_COUNT/$TOTAL_COUNT"
        
        if [[ $RUNNING_COUNT -ge 3 ]]; then
            echo "  All containers are running!"
            break
        fi
        
        if [[ $i -eq 30 ]]; then
            echo "  Warning: Some containers may not have started properly"
        else
            sleep 2
        fi
    done
    
    # Clean up local .env file
    rm -f .env
    
    # Show detailed final status
    echo ""
    echo "============================================"
    echo "Final Deployment Status"
    echo "============================================"
    echo ""
    
    # Show docker-compose status
    echo "Docker Compose Status:"
    COMPOSE_STATUS=$(sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "cd $FOLDER_DEPLOY && $DOCKER_COMPOSE_PATH ps" 2>&1)
    echo "$COMPOSE_STATUS"
    
    echo ""
    echo "Container Details:"
    CONTAINER_DETAILS=$(sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "echo '$SSH_PASS' | sudo -S $DOCKER_COMPOSE_PATH -f $FOLDER_DEPLOY/docker-compose.yml ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}'" 2>&1)
    echo "$CONTAINER_DETAILS"
    
    echo ""
    echo "Network Status:"
    NETWORK_STATUS=$(sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "echo '$SSH_PASS' | sudo -S docker network ls | grep guac || echo 'Guacamole network not found'" 2>&1)
    echo "$NETWORK_STATUS"
    
    echo ""
    echo "Guacamole deployment complete!"
    echo ""
    echo "Configuration used: $CONFIG_FILE"
    echo "Access URLs:"
    echo "  - Guacamole Web UI: http://$SYNOLOGY_IP:$GUACAMOLE_PORT/guacamole"
    echo "  - Default login: $DEFAULT_ADMIN_USERNAME / $DEFAULT_ADMIN_PASSWORD"
    # Test Guacamole accessibility
    echo ""
    echo "Testing Guacamole Web Interface..."
    if command -v curl &> /dev/null; then
        echo "Checking if Guacamole is responding at http://$SYNOLOGY_IP:$GUACAMOLE_PORT/guacamole"
        GUAC_TEST=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "http://$SYNOLOGY_IP:$GUACAMOLE_PORT/guacamole" 2>/dev/null || echo "000")
        
        if [[ "$GUAC_TEST" == "200" || "$GUAC_TEST" == "302" ]]; then
            echo "  Guacamole web interface: ACCESSIBLE"
        else
            echo "  Guacamole web interface: NOT YET ACCESSIBLE (HTTP $GUAC_TEST)"
            echo "  This is normal - containers may still be starting up"
            echo "  Try accessing in a few minutes: http://$SYNOLOGY_IP:$GUACAMOLE_PORT/guacamole"
        fi
    else
        echo "  curl not available - cannot test web interface automatically"
        echo "  Please test manually: http://$SYNOLOGY_IP:$GUACAMOLE_PORT/guacamole"
    fi
    
    echo ""
    echo "============================================"
    echo "Useful SSH commands to run on Synology:"
    echo "============================================"
    echo "  - Check logs: cd $FOLDER_DEPLOY && sudo $DOCKER_COMPOSE_PATH logs -f"
    echo "  - Stop stack: cd $FOLDER_DEPLOY && sudo $DOCKER_COMPOSE_PATH down"
    echo "  - Restart: cd $FOLDER_DEPLOY && sudo $DOCKER_COMPOSE_PATH restart"
    echo "  - View status: sudo $DOCKER_PATH ps"
    echo "  - Follow container logs: cd $FOLDER_DEPLOY && sudo $DOCKER_COMPOSE_PATH logs -f [container_name]"
    
else
    echo "Deployment cancelled."
fi