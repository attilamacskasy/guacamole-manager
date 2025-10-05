#!/bin/bash

# Guacamole Connection Management Script
# This script helps manage RDP connections for Windows servers and virtual desktops

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load environment variables
if [ -f "$PROJECT_DIR/.env" ]; then
    source "$PROJECT_DIR/.env"
else
    echo "Error: .env file not found. Please copy .env.example to .env and configure it."
    exit 1
fi

# Database connection settings
DB_HOST="172.22.18.10"
DB_PORT="5432"
DB_NAME="guacamole_db"
DB_USER="guacamole_user"

# Function to execute SQL commands
execute_sql() {
    local sql="$1"
    docker exec -i guacamole-postgres psql -h localhost -U "$DB_USER" -d "$DB_NAME" -c "$sql"
}

# Function to add RDP connection
add_rdp_connection() {
    local connection_name="$1"
    local hostname="$2"
    local username="$3"
    local password="$4"
    local domain="$5"
    local description="$6"
    
    echo "Adding RDP connection: $connection_name"
    
    # Insert connection
    local connection_sql="
    INSERT INTO guacamole_connection (connection_name, protocol) 
    VALUES ('$connection_name', 'rdp') 
    RETURNING connection_id;"
    
    local connection_id=$(execute_sql "$connection_sql" | grep -E '^[0-9]+$' | head -1)
    
    if [ -z "$connection_id" ]; then
        echo "Error: Failed to create connection"
        return 1
    fi
    
    # Insert connection parameters
    local params=(
        "hostname:$hostname"
        "port:3389"
        "username:$username"
        "password:$password"
        "domain:$domain"
        "security:rdp"
        "ignore-cert:true"
        "enable-drive:true"
        "drive-path:/srv/guacamole"
        "create-drive-path:true"
        "enable-wallpaper:false"
        "enable-theming:false"
        "enable-font-smoothing:false"
        "enable-full-window-drag:false"
        "enable-desktop-composition:false"
        "enable-menu-animations:false"
        "disable-bitmap-caching:false"
        "disable-offscreen-caching:false"
        "color-depth:16"
    )
    
    for param in "${params[@]}"; do
        IFS=':' read -r param_name param_value <<< "$param"
        local param_sql="
        INSERT INTO guacamole_connection_parameter (connection_id, parameter_name, parameter_value)
        VALUES ($connection_id, '$param_name', '$param_value');"
        execute_sql "$param_sql"
    done
    
    echo "RDP connection '$connection_name' added successfully with ID: $connection_id"
}

# Function to add VNC connection
add_vnc_connection() {
    local connection_name="$1"
    local hostname="$2"
    local password="$3"
    local port="${4:-5900}"
    local description="$5"
    
    echo "Adding VNC connection: $connection_name"
    
    # Insert connection
    local connection_sql="
    INSERT INTO guacamole_connection (connection_name, protocol) 
    VALUES ('$connection_name', 'vnc') 
    RETURNING connection_id;"
    
    local connection_id=$(execute_sql "$connection_sql" | grep -E '^[0-9]+$' | head -1)
    
    if [ -z "$connection_id" ]; then
        echo "Error: Failed to create connection"
        return 1
    fi
    
    # Insert connection parameters
    local params=(
        "hostname:$hostname"
        "port:$port"
        "password:$password"
        "enable-sftp:false"
        "color-depth:16"
    )
    
    for param in "${params[@]}"; do
        IFS=':' read -r param_name param_value <<< "$param"
        local param_sql="
        INSERT INTO guacamole_connection_parameter (connection_id, parameter_name, parameter_value)
        VALUES ($connection_id, '$param_name', '$param_value');"
        execute_sql "$param_sql"
    done
    
    echo "VNC connection '$connection_name' added successfully with ID: $connection_id"
}

# Function to list all connections
list_connections() {
    echo "Listing all connections:"
    local list_sql="
    SELECT c.connection_id, c.connection_name, c.protocol 
    FROM guacamole_connection c
    ORDER BY c.connection_name;"
    
    execute_sql "$list_sql"
}

# Function to delete connection
delete_connection() {
    local connection_id="$1"
    
    echo "Deleting connection with ID: $connection_id"
    
    # Delete parameters first
    local delete_params_sql="DELETE FROM guacamole_connection_parameter WHERE connection_id = $connection_id;"
    execute_sql "$delete_params_sql"
    
    # Delete connection
    local delete_connection_sql="DELETE FROM guacamole_connection WHERE connection_id = $connection_id;"
    execute_sql "$delete_connection_sql"
    
    echo "Connection deleted successfully"
}

# Function to create connection group
create_connection_group() {
    local group_name="$1"
    local group_type="${2:-ORGANIZATIONAL}"
    
    echo "Creating connection group: $group_name"
    
    local group_sql="
    INSERT INTO guacamole_connection_group (connection_group_name, type, max_connections, max_connections_per_user)
    VALUES ('$group_name', '$group_type', NULL, NULL)
    RETURNING connection_group_id;"
    
    local group_id=$(execute_sql "$group_sql" | grep -E '^[0-9]+$' | head -1)
    echo "Connection group '$group_name' created with ID: $group_id"
}

# Main script logic
case "$1" in
    "add-rdp")
        if [ $# -lt 5 ]; then
            echo "Usage: $0 add-rdp <connection_name> <hostname> <username> <password> [domain] [description]"
            echo "Example: $0 add-rdp 'Windows Server 2022' '192.168.1.100' 'administrator' 'password' 'DOMAIN'"
            exit 1
        fi
        add_rdp_connection "$2" "$3" "$4" "$5" "$6" "$7"
        ;;
    "add-vnc")
        if [ $# -lt 4 ]; then
            echo "Usage: $0 add-vnc <connection_name> <hostname> <password> [port] [description]"
            echo "Example: $0 add-vnc 'Ubuntu Desktop' '192.168.1.101' 'vncpassword' '5900'"
            exit 1
        fi
        add_vnc_connection "$2" "$3" "$4" "$5" "$6"
        ;;
    "list")
        list_connections
        ;;
    "delete")
        if [ $# -lt 2 ]; then
            echo "Usage: $0 delete <connection_id>"
            exit 1
        fi
        delete_connection "$2"
        ;;
    "create-group")
        if [ $# -lt 2 ]; then
            echo "Usage: $0 create-group <group_name> [group_type]"
            echo "Group types: ORGANIZATIONAL (default), BALANCING"
            exit 1
        fi
        create_connection_group "$2" "$3"
        ;;
    *)
        echo "Guacamole Connection Manager"
        echo "Usage: $0 <command> [arguments]"
        echo ""
        echo "Commands:"
        echo "  add-rdp <name> <hostname> <username> <password> [domain] [description]"
        echo "    Add a new RDP connection for Windows servers/desktops"
        echo ""
        echo "  add-vnc <name> <hostname> <password> [port] [description]"
        echo "    Add a new VNC connection for Linux desktops"
        echo ""
        echo "  list"
        echo "    List all existing connections"
        echo ""
        echo "  delete <connection_id>"
        echo "    Delete a connection by ID"
        echo ""
        echo "  create-group <group_name> [group_type]"
        echo "    Create a new connection group"
        echo ""
        echo "Examples:"
        echo "  $0 add-rdp 'Win Server 2022' '192.168.1.100' 'admin' 'password123' 'MYDOMAIN'"
        echo "  $0 add-vnc 'Ubuntu Desktop' '192.168.1.101' 'vncpass' '5900'"
        echo "  $0 list"
        echo "  $0 delete 5"
        echo "  $0 create-group 'Windows Servers'"
        ;;
esac