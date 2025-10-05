#!/bin/bash
# load_config.sh - Helper script to load configuration from JSON into environment variables

CONFIG_FILE="${1:-00_Guacamole-Manager_Config.json}"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Configuration file not found: $CONFIG_FILE"
    echo "Please ensure 00_Guacamole-Manager_Config.json exists in the current directory."
    exit 1
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "jq is required but not installed. Installing jq..."
    sudo apt update && sudo apt install -y jq
fi

# Function to load config values into environment variables
load_config() {
    # Synology Configuration
    export SYNOLOGY_IP=$(jq -r '.deployment.synology.ip_address' "$CONFIG_FILE")
    export SSH_USERNAME=$(jq -r '.deployment.synology.ssh_username' "$CONFIG_FILE")
    export SSH_PORT=$(jq -r '.deployment.synology.ssh_port' "$CONFIG_FILE")
    export SYNOLOGY_BASE_PATH=$(jq -r '.deployment.synology.base_path' "$CONFIG_FILE")
    export DOCKER_PATH=$(jq -r '.deployment.synology.docker_path' "$CONFIG_FILE")
    export DOCKER_COMPOSE_PATH=$(jq -r '.deployment.synology.docker_compose_path' "$CONFIG_FILE")
    
    # Network Configuration
    export GUACAMOLE_SUBNET=$(jq -r '.deployment.network.subnet' "$CONFIG_FILE")
    export GUACAMOLE_GATEWAY=$(jq -r '.deployment.network.gateway' "$CONFIG_FILE")
    export DB_IP=$(jq -r '.deployment.network.db_ip' "$CONFIG_FILE")
    export GUACD_IP=$(jq -r '.deployment.network.guacd_ip' "$CONFIG_FILE")
    export GUACAMOLE_IP=$(jq -r '.deployment.network.guacamole_ip' "$CONFIG_FILE")
    export NGINX_IP=$(jq -r '.deployment.network.nginx_ip' "$CONFIG_FILE")
    export PARENT_INTERFACE=$(jq -r '.deployment.network.parent_interface' "$CONFIG_FILE")
    
    # Folder Configuration
    export FOLDER_DB=$(jq -r '.deployment.folders.db' "$CONFIG_FILE")
    export FOLDER_DBINIT=$(jq -r '.deployment.folders.dbinit' "$CONFIG_FILE")
    export FOLDER_HOME=$(jq -r '.deployment.folders.home' "$CONFIG_FILE")
    export FOLDER_DRIVE=$(jq -r '.deployment.folders.drive' "$CONFIG_FILE")
    export FOLDER_RECORD=$(jq -r '.deployment.folders.record' "$CONFIG_FILE")
    export FOLDER_EXTENSIONS=$(jq -r '.deployment.folders.extensions' "$CONFIG_FILE")
    export FOLDER_NGINX_LOGS=$(jq -r '.deployment.folders.nginx_logs' "$CONFIG_FILE")
    export FOLDER_DEPLOY=$(jq -r '.deployment.folders.deploy' "$CONFIG_FILE")
    
    # Database Configuration
    export POSTGRES_DB=$(jq -r '.database.name' "$CONFIG_FILE")
    export POSTGRES_USER=$(jq -r '.database.username' "$CONFIG_FILE")
    local config_password=$(jq -r '.database.password' "$CONFIG_FILE")
    export POSTGRES_PORT=$(jq -r '.database.port' "$CONFIG_FILE")
    
    # Check if password is the default placeholder and prompt user if needed
    if [[ "$config_password" == "your_secure_postgres_password_here" ]]; then
        echo ""
        echo "Database password is set to default placeholder value."
        echo "For security, please provide a custom database password:"
        read -s -p "Enter PostgreSQL database password: " POSTGRES_PASSWORD
        echo ""
        
        # Validate password is not empty
        while [[ -z "$POSTGRES_PASSWORD" ]]; do
            echo "Password cannot be empty. Please enter a secure password:"
            read -s -p "Enter PostgreSQL database password: " POSTGRES_PASSWORD
            echo ""
        done
        
        export POSTGRES_PASSWORD
    else
        export POSTGRES_PASSWORD="$config_password"
    fi
    
    # Guacamole Configuration
    export GUACAMOLE_VERSION=$(jq -r '.guacamole.version' "$CONFIG_FILE")
    export GUACAMOLE_PORT=$(jq -r '.guacamole.port' "$CONFIG_FILE")
    export DEFAULT_ADMIN_USERNAME=$(jq -r '.guacamole.default_admin_username' "$CONFIG_FILE")
    export DEFAULT_ADMIN_PASSWORD=$(jq -r '.guacamole.default_admin_password' "$CONFIG_FILE")
    
    # LDAP Configuration
    export LDAP_ENABLED=$(jq -r '.ldap.enabled' "$CONFIG_FILE")
    export LDAP_HOSTNAME=$(jq -r '.ldap.hostname' "$CONFIG_FILE")
    export LDAP_PORT=$(jq -r '.ldap.port' "$CONFIG_FILE")
    export LDAP_USER_BASE_DN=$(jq -r '.ldap.user_base_dn' "$CONFIG_FILE")
    export LDAP_USERNAME_ATTRIBUTE=$(jq -r '.ldap.username_attribute' "$CONFIG_FILE")
    export LDAP_GROUP_BASE_DN=$(jq -r '.ldap.group_base_dn' "$CONFIG_FILE")
    
    # SSL Configuration
    export SSL_ENABLED=$(jq -r '.ssl.enabled' "$CONFIG_FILE")
    export SSL_CERT_PATH=$(jq -r '.ssl.cert_path' "$CONFIG_FILE")
    export SSL_KEY_PATH=$(jq -r '.ssl.key_path' "$CONFIG_FILE")
    
    # Port Configuration
    export HTTP_PORT=$(jq -r '.ports.http' "$CONFIG_FILE")
    export HTTPS_PORT=$(jq -r '.ports.https' "$CONFIG_FILE")
    export GUACD_PORT=$(jq -r '.ports.guacd' "$CONFIG_FILE")
}

# Load configuration
load_config

# If script is sourced, don't exit
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Configuration loaded successfully from $CONFIG_FILE"
    echo "Key variables set:"
    echo "  SYNOLOGY_IP=$SYNOLOGY_IP"
    echo "  SSH_USERNAME=$SSH_USERNAME"
    echo "  SSH_PORT=$SSH_PORT"
    echo "  SYNOLOGY_BASE_PATH=$SYNOLOGY_BASE_PATH"
    echo "  GUACAMOLE_SUBNET=$GUACAMOLE_SUBNET"
    echo "  POSTGRES_PASSWORD=$POSTGRES_PASSWORD"
fi