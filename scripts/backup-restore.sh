#!/bin/bash

# Guacamole Backup and Restore Script
# This script helps backup and restore Guacamole configurations and data

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

BACKUP_DIR="/volume1/guacamole/backups"
DATE=$(date +%Y%m%d_%H%M%S)

# Function to create backup
create_backup() {
    echo "Creating Guacamole backup..."
    
    mkdir -p "$BACKUP_DIR"
    
    # Create backup directory for this session
    local backup_session_dir="$BACKUP_DIR/backup_$DATE"
    mkdir -p "$backup_session_dir"
    
    # Backup database
    echo "Backing up PostgreSQL database..."
    docker exec guacamole-postgres pg_dump -U guacamole_user guacamole_db | gzip > "$backup_session_dir/guacamole_db_$DATE.sql.gz"
    
    # Backup configuration files
    echo "Backing up configuration files..."
    cp -r "$PROJECT_DIR/config" "$backup_session_dir/"
    cp "$PROJECT_DIR/docker-compose.yml" "$backup_session_dir/"
    cp "$PROJECT_DIR/.env" "$backup_session_dir/env_backup"
    
    # Backup Guacamole home directory (recordings, etc.)
    echo "Backing up Guacamole home directory..."
    tar -czf "$backup_session_dir/guacamole_home_$DATE.tar.gz" -C /volume1/guacamole/home .
    
    # Create backup manifest
    cat > "$backup_session_dir/backup_manifest.txt" << EOF
Guacamole Backup Manifest
========================
Backup Date: $(date)
Backup Location: $backup_session_dir

Contents:
- guacamole_db_$DATE.sql.gz: PostgreSQL database dump
- config/: Nginx and other configuration files
- docker-compose.yml: Docker Compose configuration
- env_backup: Environment variables backup
- guacamole_home_$DATE.tar.gz: Guacamole home directory (recordings, etc.)

Restore Instructions:
1. Stop all containers: docker-compose down
2. Run restore script: ./scripts/backup-restore.sh restore $backup_session_dir
EOF
    
    echo "Backup completed successfully!"
    echo "Backup location: $backup_session_dir"
    
    # Clean up old backups (keep last 7 days)
    find "$BACKUP_DIR" -type d -name "backup_*" -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
}

# Function to restore backup
restore_backup() {
    local backup_path="$1"
    
    if [ ! -d "$backup_path" ]; then
        echo "Error: Backup directory not found: $backup_path"
        exit 1
    fi
    
    echo "Restoring Guacamole from backup: $backup_path"
    
    # Stop containers
    echo "Stopping Guacamole containers..."
    cd "$PROJECT_DIR"
    docker-compose down
    
    # Restore database
    if [ -f "$backup_path/guacamole_db_"*.sql.gz ]; then
        echo "Restoring database..."
        # Start only the database container
        docker-compose up -d guacamole-db
        sleep 10
        
        # Restore database
        zcat "$backup_path"/guacamole_db_*.sql.gz | docker exec -i guacamole-postgres psql -U guacamole_user -d guacamole_db
        
        # Stop database
        docker-compose down
    fi
    
    # Restore configuration files
    if [ -d "$backup_path/config" ]; then
        echo "Restoring configuration files..."
        cp -r "$backup_path/config" "$PROJECT_DIR/"
    fi
    
    if [ -f "$backup_path/docker-compose.yml" ]; then
        echo "Restoring docker-compose.yml..."
        cp "$backup_path/docker-compose.yml" "$PROJECT_DIR/"
    fi
    
    if [ -f "$backup_path/env_backup" ]; then
        echo "Restoring environment configuration..."
        cp "$backup_path/env_backup" "$PROJECT_DIR/.env"
    fi
    
    # Restore home directory
    if [ -f "$backup_path"/guacamole_home_*.tar.gz ]; then
        echo "Restoring Guacamole home directory..."
        rm -rf /volume1/guacamole/home/*
        tar -xzf "$backup_path"/guacamole_home_*.tar.gz -C /volume1/guacamole/home/
    fi
    
    echo "Restore completed successfully!"
    echo "You can now start the containers with: docker-compose up -d"
}

# Function to list available backups
list_backups() {
    echo "Available backups:"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        echo "No backups found. Backup directory does not exist: $BACKUP_DIR"
        return
    fi
    
    for backup_dir in "$BACKUP_DIR"/backup_*; do
        if [ -d "$backup_dir" ]; then
            local backup_name=$(basename "$backup_dir")
            local backup_date=$(stat -c %y "$backup_dir" | cut -d' ' -f1)
            echo "  $backup_name (created: $backup_date)"
            
            if [ -f "$backup_dir/backup_manifest.txt" ]; then
                echo "    $(head -n 1 "$backup_dir/backup_manifest.txt" 2>/dev/null || echo 'No manifest available')"
            fi
        fi
    done
}

# Function to export connections configuration
export_connections() {
    local export_file="$BACKUP_DIR/connections_export_$DATE.sql"
    
    echo "Exporting connections configuration..."
    
    docker exec guacamole-postgres psql -U guacamole_user -d guacamole_db -c "
    COPY (
        SELECT 
            c.connection_name,
            c.protocol,
            string_agg(cp.parameter_name || ':' || cp.parameter_value, '|' ORDER BY cp.parameter_name) as parameters
        FROM guacamole_connection c
        LEFT JOIN guacamole_connection_parameter cp ON c.connection_id = cp.connection_id
        GROUP BY c.connection_id, c.connection_name, c.protocol
        ORDER BY c.connection_name
    ) TO STDOUT WITH CSV HEADER;
    " > "$export_file"
    
    echo "Connections exported to: $export_file"
}

# Main script logic
case "$1" in
    "backup")
        create_backup
        ;;
    "restore")
        if [ $# -lt 2 ]; then
            echo "Usage: $0 restore <backup_directory>"
            echo "Available backups:"
            list_backups
            exit 1
        fi
        restore_backup "$2"
        ;;
    "list")
        list_backups
        ;;
    "export-connections")
        export_connections
        ;;
    *)
        echo "Guacamole Backup and Restore Tool"
        echo "Usage: $0 <command> [arguments]"
        echo ""
        echo "Commands:"
        echo "  backup"
        echo "    Create a complete backup of Guacamole (database, config, recordings)"
        echo ""
        echo "  restore <backup_directory>"
        echo "    Restore Guacamole from a backup"
        echo ""
        echo "  list"
        echo "    List all available backups"
        echo ""
        echo "  export-connections"
        echo "    Export connections configuration to CSV"
        echo ""
        echo "Examples:"
        echo "  $0 backup"
        echo "  $0 restore /volume1/guacamole/backups/backup_20231201_143022"
        echo "  $0 list"
        echo "  $0 export-connections"
        ;;
esac