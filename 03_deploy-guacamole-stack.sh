#!/bin/bash
# 03_deploy-guacamole-stack.sh
# This script deploys the Guacamole stack using docker-compose on the remote Synology NAS.
# Prerequisite: Run 02_setup-guacamole-manager.sh first to configure remote Docker access.

set -e

# Activate Python virtual environment if it exists and not already activated
if [[ -f "venv/bin/activate" && -z "$VIRTUAL_ENV" ]]; then
    echo "Activating Python virtual environment..."
    source venv/bin/activate
fi

# Get Synology connection details (use same defaults as setup script)
echo "[1/5] Getting Synology connection details..."
read -p "Enter Synology IP address (default: 172.22.22.253): " SYNOLOGY_IP
SYNOLOGY_IP=${SYNOLOGY_IP:-172.22.22.253}
read -p "Enter SSH username (default: attila): " SSH_USER
SSH_USER=${SSH_USER:-attila}
read -p "Enter SSH port (default 22): " SSH_PORT
SSH_PORT=${SSH_PORT:-22}
read -s -p "Enter SSH password: " SSH_PASS
echo ""

# Test SSH connection
echo "Testing SSH connection to Synology..."
if ! sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -p $SSH_PORT "$SSH_USER@$SYNOLOGY_IP" "echo 'SSH connection successful'" > /dev/null 2>&1; then
    echo "SSH connection failed. Please check your credentials."
    exit 1
fi

echo "SSH connection verified"

# Find Docker path on Synology
DOCKER_FOUND=""
DOCKER_PATHS=("/usr/local/bin/docker" "/usr/bin/docker")

for docker_path in "${DOCKER_PATHS[@]}"; do
    if sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USER@$SYNOLOGY_IP" "test -f $docker_path" 2>/dev/null; then
        DOCKER_FOUND="$docker_path"
        break
    fi
done

if [[ -z "$DOCKER_FOUND" ]]; then
    echo "Docker not found on Synology. Please install Docker package."
    exit 1
fi

echo "Docker found at: $DOCKER_FOUND"

# Check if docker-compose file exists
echo "[2/5] Checking docker-compose configuration..."
if [[ ! -f "docker-compose.yml" ]]; then
    echo "docker-compose.yml not found in current directory."
    echo "Please ensure you're in the guacamole-manager directory."
    exit 1
fi

echo "Found docker-compose.yml"

# Quick validation that setup was completed
echo "[3/4] Verifying setup prerequisites..."
if ! sshpass -p "$SSH_PASS" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -p $SSH_PORT "$SSH_USER@$SYNOLOGY_IP" "test -d /volume1/guacamole" 2>/dev/null; then
    echo "Synology folder structure not found!"
    echo "Please run the setup script first: ./02_setup-guacamole-manager.sh"
    exit 1
fi

echo "Prerequisites validated"

# Show current status
echo "[4/4] Current Docker status on Synology..."
echo "Running containers:"
DOCKER_PS_OUTPUT=$(sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USER@$SYNOLOGY_IP" "echo '$SSH_PASS' | sudo -S $DOCKER_FOUND ps" 2>&1)
if [[ "$DOCKER_PS_OUTPUT" == *"Password:"* ]]; then
    echo "$DOCKER_PS_OUTPUT" | sed 's/.*Password: //' | head -10
else
    echo "$DOCKER_PS_OUTPUT" | head -10
fi

echo ""
echo "Guacamole-related containers:"
GUAC_CONTAINERS=$(sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USER@$SYNOLOGY_IP" "echo '$SSH_PASS' | sudo -S $DOCKER_FOUND ps -a" 2>&1 | grep -i guac || echo "No Guacamole containers found")
echo "$GUAC_CONTAINERS"

# Deploy the stack
echo ""
echo "Ready to deploy Guacamole stack!"

read -p "Do you want to deploy/update the Guacamole stack? (y/N): " DEPLOY_CONFIRM
if [[ "$DEPLOY_CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Preparing deployment..."
    
    # Create deployment directory on Synology
    sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USER@$SYNOLOGY_IP" "mkdir -p /volume1/guacamole/deploy" 2>/dev/null || true
    
    # Copy docker-compose.yml and config files to Synology
    echo "Copying configuration files..."
    sshpass -p "$SSH_PASS" scp -P $SSH_PORT docker-compose.yml "$SSH_USER@$SYNOLOGY_IP:/volume1/guacamole/deploy/" 2>/dev/null || {
        echo "Failed to copy docker-compose.yml. Check SSH/SCP access."
        exit 1
    }
    
    # Copy config directory if it exists
    if [[ -d "config" ]]; then
        sshpass -p "$SSH_PASS" scp -r -P $SSH_PORT config "$SSH_USER@$SYNOLOGY_IP:/volume1/guacamole/deploy/" 2>/dev/null || {
            echo "Warning: Could not copy config directory"
        }
    fi
    
    # Deploy with docker-compose
    echo "Starting Guacamole stack..."
    DEPLOY_OUTPUT=$(sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USER@$SYNOLOGY_IP" "cd /volume1/guacamole/deploy && echo '$SSH_PASS' | sudo -S /usr/local/bin/docker-compose up -d" 2>&1)
    
    if [[ $? -eq 0 ]]; then
        echo "Deployment successful!"
    else
        echo "Deployment failed:"
        echo "$DEPLOY_OUTPUT"
        exit 1
    fi
    
    # Show final status
    echo ""
    echo "Guacamole stack status:"
    FINAL_STATUS=$(sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USER@$SYNOLOGY_IP" "echo '$SSH_PASS' | sudo -S $DOCKER_FOUND ps" 2>&1 | grep -E "(CONTAINER|guac)" || echo "Containers may still be starting...")
    echo "$FINAL_STATUS"
    
    echo ""
    echo "Guacamole deployment complete!"
    echo ""
    echo "Access URLs:"
    echo "  - Guacamole Web UI: http://$SYNOLOGY_IP:8080/guacamole"
    echo "  - Default login: guacadmin / guacadmin"
    echo ""
    echo "Useful SSH commands to run on Synology:"
    echo "  - Check logs: cd /volume1/guacamole/deploy && sudo docker-compose logs -f"
    echo "  - Stop stack: cd /volume1/guacamole/deploy && sudo docker-compose down"
    echo "  - Restart: cd /volume1/guacamole/deploy && sudo docker-compose restart"
    echo "  - View status: sudo docker ps"
    
else
    echo "Deployment cancelled."
fi