#!/bin/bash
# setup-guacamole-manager.sh
# This script prepares a new Ubuntu 24.04 desktop for the Guacamole Manager toolkit.
# It installs all required system and Python dependencies, sets up Docker, and prepares the environment.
# 
# Usage: ./setup-guacamole-manager.sh [--skip-install] [--debug]

set -e

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
        *)
            ;;
    esac
done

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
    echo "[2/5] Installing SSH client and utilities..."
    sudo apt install -y openssh-client sshpass
else
    echo "[1-2/5] Skipping package installation..."
fi

# 3. Configure remote Docker via SSH
echo "[3/5] Configuring remote Docker connection via SSH..."
echo "Please provide your Synology credentials:"
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
SSH_TEST_CMD_MASKED="sshpass -p \"****\" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -p $SSH_PORT \"$SSH_USER@$SYNOLOGY_IP\" \"echo 'SSH connection successful'\""
if [[ "$DEBUG" == "true" ]]; then
    echo "DEBUG: SSH test command: $SSH_TEST_CMD_MASKED"
fi

if sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -p $SSH_PORT "$SSH_USER@$SYNOLOGY_IP" "echo 'SSH connection successful'" > /dev/null 2>&1; then
    echo "✓ SSH connection successful!"
else
    echo "✗ SSH connection failed. Please check:"
    echo "  1. IP address and credentials are correct"
    echo "  2. SSH is enabled on Synology (Control Panel > Terminal & SNMP > Enable SSH)"
    echo "  3. User has admin privileges"
    exit 1
fi

# Test Docker on remote host
echo "Testing Docker on remote Synology..."
# Check for Docker in multiple locations (Synology uses /usr/local/bin/docker)
DOCKER_CHECK_CMD_MASKED="sshpass -p \"****\" ssh -p $SSH_PORT \"$SSH_USER@$SYNOLOGY_IP\" \"test -f /usr/local/bin/docker || test -f /usr/bin/docker || which docker\""
if [[ "$DEBUG" == "true" ]]; then
    echo "DEBUG: Docker check command: $DOCKER_CHECK_CMD_MASKED"
fi

# Try multiple ways to find Docker
DOCKER_PATHS=("/usr/local/bin/docker" "/usr/bin/docker")
DOCKER_FOUND=""

for docker_path in "${DOCKER_PATHS[@]}"; do
    if sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USER@$SYNOLOGY_IP" "test -f $docker_path" 2>/dev/null; then
        DOCKER_FOUND="$docker_path"
        echo "DEBUG: Docker found at: $docker_path"
        break
    fi
done

# Fallback to which command with full PATH
if [[ -z "$DOCKER_FOUND" ]]; then
    DOCKER_WHICH=$(sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USER@$SYNOLOGY_IP" "PATH=/usr/local/bin:/usr/bin:/bin:\$PATH which docker" 2>/dev/null || echo "not_found")
    if [[ "$DOCKER_WHICH" != "not_found" ]]; then
        DOCKER_FOUND="$DOCKER_WHICH"
        echo "DEBUG: Docker found via which: $DOCKER_WHICH"
    fi
fi

if [[ -z "$DOCKER_FOUND" ]]; then
    echo "✗ Docker not found. Please install Docker package on your Synology NAS."
    echo "DEBUG: Checked paths: ${DOCKER_PATHS[*]} and PATH search"
    exit 1
fi

echo "✓ Docker found at: $DOCKER_FOUND"

# Test Docker with sudo (required for non-root users)
DOCKER_VERSION_CMD_MASKED="sshpass -p \"****\" ssh -p $SSH_PORT \"$SSH_USER@$SYNOLOGY_IP\" \"echo '****' | sudo -S $DOCKER_FOUND version --format '{{.Server.Version}}'\""
if [[ "$DEBUG" == "true" ]]; then
    echo "DEBUG: Docker version check: $DOCKER_VERSION_CMD_MASKED"
fi

echo "Testing Docker with sudo..."
DOCKER_TEST_OUTPUT=$(sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USER@$SYNOLOGY_IP" "echo '$SSH_PASS' | sudo -S $DOCKER_FOUND version --format '{{.Server.Version}}'" 2>&1)
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
    echo "✓ Docker is available on Synology (version: $DOCKER_VERSION)"
else
    echo "✗ Docker test failed. Output: $DOCKER_VERSION"
    echo "Please ensure:"
    echo "  1. '$SSH_USER' has sudo privileges"
    echo "  2. Docker is installed and running"
    echo "  3. Password is correct for sudo"
    exit 1
fi

# Create Docker wrapper scripts
mkdir -p ~/.local/bin
cat > ~/.local/bin/docker-remote << EOF
#!/bin/bash
sshpass -p '$SSH_PASS' ssh -p $SSH_PORT $SSH_USER@$SYNOLOGY_IP "echo '$SSH_PASS' | sudo -S $DOCKER_FOUND \\\$@"
EOF

# Check if docker-compose exists (it might be a plugin: docker compose)
DOCKER_COMPOSE_FOUND=""
if sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USER@$SYNOLOGY_IP" "test -f /usr/local/bin/docker-compose" 2>/dev/null; then
    DOCKER_COMPOSE_FOUND="/usr/local/bin/docker-compose"
elif sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USER@$SYNOLOGY_IP" "test -f /usr/bin/docker-compose" 2>/dev/null; then
    DOCKER_COMPOSE_FOUND="/usr/bin/docker-compose"
else
    # Use docker compose plugin
    DOCKER_COMPOSE_FOUND="$DOCKER_FOUND compose"
fi

echo "DEBUG: Docker Compose command: $DOCKER_COMPOSE_FOUND"

cat > ~/.local/bin/docker-compose-remote << EOF
#!/bin/bash
sshpass -p '$SSH_PASS' ssh -p $SSH_PORT $SSH_USER@$SYNOLOGY_IP "echo '$SSH_PASS' | sudo -S $DOCKER_COMPOSE_FOUND \\\$@"
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
    echo "✓ Remote Docker connection successful!"
else
    echo "✗ Remote Docker connection failed."
    if [[ "$DEBUG" == "true" ]]; then
        echo "Output: $WRAPPER_OUTPUT"
    fi
    exit 1
fi

# 4. Clone or update the guacamole-manager repository
echo "[4/5] Checking guacamole-manager repository..."

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

# 5. Install Python requirements
echo "[5/5] Installing Python requirements..."
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

# 6. Final instructions
echo ""
echo "Setup complete!"
echo ""
echo "✓ Remote Docker connection established to Synology at $SYNOLOGY_IP"
echo "✓ Python virtual environment created with all dependencies"
echo ""
echo "Docker commands now work via SSH:"
echo "  - 'docker' commands will execute on your Synology NAS"
echo "  - 'docker-compose' commands will execute on your Synology NAS"
echo ""
echo "Next step: Deploy Guacamole stack"
echo "Run: ./03_deploy-guacamole-stack.sh"
