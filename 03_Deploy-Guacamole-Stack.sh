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
    sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "mkdir -p $FOLDER_DEPLOY" 2>/dev/null || true
    
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
    sshpass -p "$SSH_PASS" scp -P $SSH_PORT docker-compose.yml .env "$SSH_USERNAME@$SYNOLOGY_IP:$FOLDER_DEPLOY/" 2>/dev/null || {
        echo "Failed to copy docker-compose.yml and .env. Check SSH/SCP access."
        exit 1
    }
    
    # Copy config directory if it exists
    if [[ -d "config" ]]; then
        sshpass -p "$SSH_PASS" scp -r -P $SSH_PORT config "$SSH_USERNAME@$SYNOLOGY_IP:$FOLDER_DEPLOY/" 2>/dev/null || {
            echo "Warning: Could not copy config directory"
        }
    fi
    
    # Deploy with docker-compose
    echo "Starting Guacamole stack..."
    DEPLOY_OUTPUT=$(sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "cd $FOLDER_DEPLOY && echo '$SSH_PASS' | sudo -S $DOCKER_COMPOSE_PATH up -d" 2>&1)
    
    if [[ $? -eq 0 ]]; then
        echo "Deployment successful!"
    else
        echo "Deployment failed:"
        echo "$DEPLOY_OUTPUT"
        exit 1
    fi
    
    # Clean up local .env file
    rm -f .env
    
    # Show final status
    echo ""
    echo "Guacamole stack status:"
    FINAL_STATUS=$(sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "echo '$SSH_PASS' | sudo -S $DOCKER_FOUND ps" 2>&1 | grep -E "(CONTAINER|guac)" || echo "Containers may still be starting...")
    echo "$FINAL_STATUS"
    
    echo ""
    echo "Guacamole deployment complete!"
    echo ""
    echo "Configuration used: $CONFIG_FILE"
    echo "Access URLs:"
    echo "  - Guacamole Web UI: http://$SYNOLOGY_IP:$GUACAMOLE_PORT/guacamole"
    echo "  - Default login: $DEFAULT_ADMIN_USERNAME / $DEFAULT_ADMIN_PASSWORD"
    echo ""
    echo "Useful SSH commands to run on Synology:"
    echo "  - Check logs: cd $FOLDER_DEPLOY && sudo $DOCKER_COMPOSE_PATH logs -f"
    echo "  - Stop stack: cd $FOLDER_DEPLOY && sudo $DOCKER_COMPOSE_PATH down"
    echo "  - Restart: cd $FOLDER_DEPLOY && sudo $DOCKER_COMPOSE_PATH restart"
    echo "  - View status: sudo $DOCKER_PATH ps"
    
else
    echo "Deployment cancelled."
fi