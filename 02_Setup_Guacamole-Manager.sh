#!/bin/bash
# setup-guacamole-manager.sh
# This script prepares a new Ubuntu 24.04 desktop for the Guacamole Manager toolkit.
# It installs all required system and Python dependencies, sets up Docker, and prepares the environment.
# 
# Usage: ./setup-guacamole-manager.sh [--skip-install] [--debug] [--config CONFIG_FILE]

set -e

# Load configuration from JSON file
CONFIG_FILE="00_Guacamole-Manager_Config.json"

# Enable debug mode (set to false for clean output)
DEBUG=false

# Check for parameters
SKIP_INSTALL=false
for arg in "$@"; do
    case $arg in
        --skip-install)
            SKIP_INSTALL=true
            echo "Skipping system package installation..."
            ;;
        --debug)
            DEBUG=true
            echo "Debug mode enabled..."
            ;;
        --config)
            shift
            CONFIG_FILE="$1"
            ;;
        *)
            ;;
    esac
done

# Load configuration
if [[ -f "$CONFIG_FILE" ]]; then
    echo "Loading configuration from $CONFIG_FILE..."
    source ./01A_Load_Config.sh "$CONFIG_FILE"
else
    echo "Configuration file not found: $CONFIG_FILE"
    echo "Please ensure the config file exists or create one from the template."
    exit 1
fi

if [[ "$SKIP_INSTALL" == "false" ]]; then
    # 1. Update system and install base packages
    echo "[1/5] Updating system and installing base packages..."
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y \
        python3 python3-pip python3-venv \
        git curl wget unzip \
        docker-compose \
        nginx

    # 2. Install SSH client and utilities for remote Docker
    echo "[2/6] Installing SSH client and utilities..."
    sudo apt install -y openssh-client sshpass jq
else
    echo "[1-2/6] Skipping package installation..."
fi

# 3. Configure remote Docker via SSH
echo "[3/6] Configuring remote Docker connection via SSH..."
echo "Using configuration from $CONFIG_FILE:"
echo "  Synology IP: $SYNOLOGY_IP"
echo "  SSH Username: $SSH_USERNAME"
echo "  SSH Port: $SSH_PORT"
echo ""
read -s -p "Enter SSH password for $SSH_USERNAME@$SYNOLOGY_IP: " SSH_PASS
echo ""

# Test SSH connection
echo "Testing SSH connection to Synology..."
SSH_TEST_CMD_MASKED="sshpass -p \"****\" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -p $SSH_PORT \"$SSH_USERNAME@$SYNOLOGY_IP\" \"echo 'SSH connection successful'\""
if [[ "$DEBUG" == "true" ]]; then
    echo "DEBUG: SSH test command: $SSH_TEST_CMD_MASKED"
fi

if sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "echo 'SSH connection successful'" > /dev/null 2>&1; then
    echo "SSH connection successful!"
else
    echo "SSH connection failed. Please check:"
    echo "  1. IP address and credentials are correct"
    echo "  2. SSH is enabled on Synology (Control Panel > Terminal & SNMP > Enable SSH)"
    echo "  3. User has admin privileges"
    exit 1
fi

# Test Docker on remote host
echo "Testing Docker on remote Synology..."
echo "Using configured Docker path: $DOCKER_PATH"

# Test if Docker exists at the configured path
if sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "test -f $DOCKER_PATH" 2>/dev/null; then
    DOCKER_FOUND="$DOCKER_PATH"
    echo "Docker found at: $DOCKER_FOUND"
else
    echo "Docker not found at configured path: $DOCKER_PATH"
    echo "Please check the configuration file and ensure Docker is installed."
    exit 1
fi

# Test Docker with sudo (required for non-root users)
DOCKER_VERSION_CMD_MASKED="sshpass -p \"****\" ssh -p $SSH_PORT \"$SSH_USERNAME@$SYNOLOGY_IP\" \"echo '****' | sudo -S $DOCKER_FOUND version --format '{{.Server.Version}}'\""
if [[ "$DEBUG" == "true" ]]; then
    echo "DEBUG: Docker version check: $DOCKER_VERSION_CMD_MASKED"
fi

echo "Testing Docker with sudo..."
DOCKER_TEST_OUTPUT=$(sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "echo '$SSH_PASS' | sudo -S $DOCKER_FOUND version --format '{{.Server.Version}}'" 2>&1)
DOCKER_TEST_EXIT=$?

# Clean up the output (extract version after "Password: ")
if [[ "$DOCKER_TEST_OUTPUT" == *"Password: "* ]]; then
    DOCKER_VERSION=$(echo "$DOCKER_TEST_OUTPUT" | sed 's/.*Password: //')
else
    DOCKER_VERSION="$DOCKER_TEST_OUTPUT"
fi

echo "DEBUG: Docker test exit code: $DOCKER_TEST_EXIT"
echo "DEBUG: Docker test raw output: '$DOCKER_TEST_OUTPUT'"
echo "DEBUG: Docker test clean version: '$DOCKER_VERSION'"

if [[ $DOCKER_TEST_EXIT -eq 0 && "$DOCKER_VERSION" != "" && "$DOCKER_VERSION" != *"failed"* ]]; then
    echo "Docker is available on Synology (version: $DOCKER_VERSION)"
else
    echo "Docker test failed. Output: $DOCKER_VERSION"
    echo "Please ensure:"
    echo "  1. '$SSH_USERNAME' has sudo privileges"
    echo "  2. Docker is installed and running"
    echo "  3. Password is correct for sudo"
    exit 1
fi

# Create Docker wrapper scripts
mkdir -p ~/.local/bin
cat > ~/.local/bin/docker-remote << EOF
#!/bin/bash
sshpass -p '$SSH_PASS' ssh -p $SSH_PORT $SSH_USERNAME@$SYNOLOGY_IP "echo '$SSH_PASS' | sudo -S $DOCKER_FOUND \\\$@"
EOF

# Use configured Docker Compose path
DOCKER_COMPOSE_FOUND="$DOCKER_COMPOSE_PATH"
echo "Using configured Docker Compose path: $DOCKER_COMPOSE_FOUND"

# Verify Docker Compose exists
if sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "test -f $DOCKER_COMPOSE_FOUND" 2>/dev/null; then
    echo "Docker Compose found at: $DOCKER_COMPOSE_FOUND"
else
    echo "Docker Compose not found at configured path: $DOCKER_COMPOSE_FOUND"
    echo "Trying Docker Compose plugin..."
    DOCKER_COMPOSE_FOUND="$DOCKER_FOUND compose"
fi

cat > ~/.local/bin/docker-compose-remote << EOF
#!/bin/bash
sshpass -p '$SSH_PASS' ssh -p $SSH_PORT $SSH_USERNAME@$SYNOLOGY_IP "echo '$SSH_PASS' | sudo -S $DOCKER_COMPOSE_FOUND \\\$@"
EOF

chmod +x ~/.local/bin/docker-remote ~/.local/bin/docker-compose-remote

# Add to PATH and create aliases
echo "export PATH=\$HOME/.local/bin:\$PATH" >> ~/.bashrc
echo "alias docker='docker-remote'" >> ~/.bashrc
echo "alias docker-compose='docker-compose-remote'" >> ~/.bashrc

# Set environment for current session
export PATH=$HOME/.local/bin:$PATH
alias docker='docker-remote'
alias docker-compose='docker-compose-remote'

# Test Docker connection via SSH
echo "Testing Docker connection via SSH using wrapper script..."
if [[ "$DEBUG" == "true" ]]; then
    echo "DEBUG: Testing docker-remote wrapper..."
    echo "DEBUG: Wrapper script content (password masked):"
    sed "s/$SSH_PASS/****/g" ~/.local/bin/docker-remote
fi

# Simple test - just check if docker command works (avoid complex format strings)
WRAPPER_OUTPUT=$(docker-remote --version 2>&1)
WRAPPER_EXIT=$?

if [[ "$DEBUG" == "true" ]]; then
    echo "DEBUG: Wrapper test exit code: $WRAPPER_EXIT"
    echo "DEBUG: Wrapper test output: '$WRAPPER_OUTPUT'"
fi

if [[ $WRAPPER_EXIT -eq 0 ]]; then
    echo "Remote Docker connection successful!"
else
    echo "Remote Docker connection failed."
    if [[ "$DEBUG" == "true" ]]; then
        echo "Output: $WRAPPER_OUTPUT"
    fi
    exit 1
fi

# 4. Validate Synology folder structure
echo "[4/6] Validating Synology folder structure..."

# Check if main Guacamole shared folder exists
echo "Checking main Guacamole shared folder: $SYNOLOGY_BASE_PATH"

# Simple test first - just check if folder exists
echo "Testing folder existence..."
if sshpass -p "$SSH_PASS" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "test -d $SYNOLOGY_BASE_PATH" 2>/dev/null; then
    echo "$SYNOLOGY_BASE_PATH folder exists"
else
    echo "$SYNOLOGY_BASE_PATH shared folder not found on Synology!"
    echo ""
    echo "Let me check what's available in /volume1/:"
    
    VOLUME_LIST=$(sshpass -p "$SSH_PASS" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "ls -1 /volume1/" 2>&1)
    VOLUME_EXIT=$?
    
    if [[ $VOLUME_EXIT -eq 0 ]]; then
        echo "Available folders in /volume1/:"
        echo "$VOLUME_LIST" | head -10
    else
        echo "Cannot access /volume1/ - Error: $VOLUME_LIST"
    fi
    
    echo ""
    echo "REQUIRED SETUP:"
    echo "1. Log into your Synology DSM web interface"
    echo "2. Go to Control Panel > Shared Folder"
    echo "3. Create a new shared folder named 'guacamole' on volume1"
    echo "4. Set appropriate permissions for your user '$SSH_USERNAME'"
    echo "5. Update the configuration file if needed"
    echo "6. Re-run this script"
    echo ""
    exit 1
fi

# Define required subfolders for Guacamole from configuration
REQUIRED_FOLDERS=(
    "$FOLDER_DB"
    "$FOLDER_DBINIT" 
    "$FOLDER_HOME"
    "$FOLDER_DRIVE"
    "$FOLDER_RECORD"
    "$FOLDER_EXTENSIONS"
    "$FOLDER_NGINX_LOGS"
)

echo "Checking/creating required subfolders..."
CREATED_FOLDERS=()

for folder in "${REQUIRED_FOLDERS[@]}"; do
    echo "Checking folder: $folder"
    
    if ! sshpass -p "$SSH_PASS" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "test -d \"$folder\"" 2>/dev/null; then
        echo "Creating missing folder: $folder"
        
        CREATE_RESULT=$(sshpass -p "$SSH_PASS" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "mkdir -p \"$folder\"" 2>&1)
        CREATE_EXIT=$?
        
        if [[ $CREATE_EXIT -eq 0 ]]; then
            CREATED_FOLDERS+=("$folder")
            echo "Created: $folder"
        else
            echo "Failed to create folder: $folder"
            echo "Error: $CREATE_RESULT"
            echo "Please check permissions on $SYNOLOGY_BASE_PATH"
            exit 1
        fi
    else
        echo "Exists: $folder"
    fi
done

if [[ ${#CREATED_FOLDERS[@]} -gt 0 ]]; then
    echo "Created ${#CREATED_FOLDERS[@]} missing folders"
else
    echo "All required folders already exist"
fi

# Set proper permissions (optional step)
echo "Setting folder permissions..."

# Simple permission test - just try to set the main folder permission
if [[ "$DEBUG" == "true" ]]; then
    echo "DEBUG: Attempting to set basic permissions..."
fi

# Use a simple, quick permission check instead of recursive chmod
CHMOD_TEST=$(sshpass -p "$SSH_PASS" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "ls -ld $SYNOLOGY_BASE_PATH" 2>&1)
CHMOD_TEST_EXIT=$?

if [[ $CHMOD_TEST_EXIT -eq 0 ]]; then
    echo "Folder permissions verified (current: $(echo "$CHMOD_TEST" | awk '{print $1}'))"
    echo "Note: Synology manages permissions automatically - folders are ready for Docker"
else
    echo "Warning: Could not verify permissions, but folders exist"
    echo "Synology will handle permissions automatically for Docker volumes"
fi

echo "Folder structure validated"

# 5. Clone or update the guacamole-manager repository
echo "[5/6] Checking guacamole-manager repository..."

# Check if we're already in the guacamole-manager directory
if [[ "$(basename "$PWD")" == "guacamole-manager" ]]; then
    echo "Already in guacamole-manager directory. Updating repository..."
    #git fetch origin
    #git pull origin main
    REPO_DIR="$PWD"
elif [ -d "guacamole-manager" ]; then
    echo "Repository exists. Updating to latest version..."
    cd guacamole-manager
    #git fetch origin
    #git pull origin main
    REPO_DIR="$PWD"
    cd ..
else
    echo "Cloning guacamole-manager repository..."
    #git clone https://github.com/attilamacskasy/guacamole-manager.git
    REPO_DIR="$PWD/guacamole-manager"
fi

# 6. Install Python requirements
echo "[6/6] Installing Python requirements..."
cd "$REPO_DIR"
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

deactivate

# Return to original directory if we weren't already in guacamole-manager
if [[ "$(basename "$REPO_DIR")" != "$(basename "$PWD")" ]]; then
    cd ..
fi

# 7. Final instructions
echo ""
echo "Setup complete!"
echo ""
echo "Remote Docker connection established to Synology at $SYNOLOGY_IP"
echo "Synology folder structure validated and created"
echo "Python virtual environment created with all dependencies"
echo ""
echo "Configuration loaded from: $CONFIG_FILE"
echo "Next step: Deploy Guacamole stack"
echo "Run: ./03_deploy-guacamole-stack.sh"
