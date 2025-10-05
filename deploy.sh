#!/bin/bash

# Guacamole Manager Deployment Script for Synology NAS
# This script automates the deployment of Apache Guacamole on Synology NAS

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Guacamole Manager Deployment Script ==="
echo "Deploying Apache Guacamole for VDI solution on Synology NAS"
echo ""

# Check if running on Synology
if [ ! -d "/volume1" ]; then
    echo "Warning: This script is designed for Synology NAS. /volume1 not found."
    echo "Continuing anyway..."
fi

# Step 1: Create environment configuration
echo "Step 1: Setting up environment configuration..."
if [ ! -f "$PROJECT_DIR/.env" ]; then
    cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
    echo "Created .env file from template. Please edit it with your settings:"
    echo "  - Set POSTGRES_PASSWORD to a secure password"
    echo "  - Configure LDAP settings if using Active Directory"
    echo ""
    read -p "Press Enter to continue after configuring .env file..."
fi

# Load environment variables
source "$PROJECT_DIR/.env"

# Step 2: Create Synology directories
echo "Step 2: Creating Synology directories..."
mkdir -p /volume1/guacamole/{db,dbinit,home/{drive,record,extensions,nginx-logs},backups}
chmod -R 755 /volume1/guacamole

echo "Created directories:"
echo "  - /volume1/guacamole/db (PostgreSQL data)"
echo "  - /volume1/guacamole/dbinit (Database initialization scripts)"
echo "  - /volume1/guacamole/home/drive (Shared drives)"
echo "  - /volume1/guacamole/home/record (Session recordings)"
echo "  - /volume1/guacamole/home/extensions (Guacamole extensions)"
echo "  - /volume1/guacamole/home/nginx-logs (Nginx logs)"
echo "  - /volume1/guacamole/backups (Backup storage)"

# Step 3: Initialize database
echo ""
echo "Step 3: Initializing database..."
bash "$SCRIPT_DIR/init-db.sh"

# Step 4: Start services
echo ""
echo "Step 4: Starting Guacamole services..."
cd "$PROJECT_DIR"

# Pull latest images
echo "Pulling Docker images..."
docker-compose pull

# Start services
echo "Starting services..."
docker-compose up -d

# Wait for services to start
echo "Waiting for services to start..."
sleep 30

# Check service status
echo ""
echo "Checking service status..."
docker-compose ps

# Step 5: Health checks
echo ""
echo "Step 5: Performing health checks..."

# Check database
echo "Checking database connection..."
if docker exec guacamole-postgres pg_isready -U guacamole_user -d guacamole_db; then
    echo "✓ Database is ready"
else
    echo "✗ Database connection failed"
fi

# Check Guacamole web interface
echo "Checking Guacamole web interface..."
sleep 10
if curl -f -s "http://172.22.18.12:8080/guacamole/" > /dev/null; then
    echo "✓ Guacamole web interface is accessible"
else
    echo "✗ Guacamole web interface is not accessible"
fi

# Step 6: Display access information
echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Access Information:"
echo "  - Guacamole URL: http://172.22.18.12:8080/guacamole/"
echo "  - Default Username: $DEFAULT_ADMIN_USERNAME"
echo "  - Default Password: $DEFAULT_ADMIN_PASSWORD"
echo ""
echo "Network Configuration:"
echo "  - Database: 172.22.18.10:5432"
echo "  - Guacamole Daemon: 172.22.18.11:4822"
echo "  - Guacamole Web: 172.22.18.12:8080"
echo "  - Nginx Proxy: 172.22.18.13:80"
echo ""
echo "Management Tools:"
echo "  - Add RDP connection: ./scripts/manage-connections.sh add-rdp"
echo "  - List connections: ./scripts/manage-connections.sh list"
echo "  - Create backup: ./scripts/backup-restore.sh backup"
echo "  - Python manager: python3 scripts/guacamole-manager.py --help"
echo ""
echo "Next Steps:"
echo "1. Change the default admin password after first login"
echo "2. Configure SSL certificates for HTTPS (optional)"
echo "3. Add your Windows servers and virtual desktops using the management tools"
echo "4. Set up regular backups using the backup script"
echo ""
echo "For support and documentation, see README.md"

# Step 7: Create sample connections (optional)
echo ""
read -p "Would you like to import sample connections? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Creating sample connections..."
    # Wait a bit more for the database to be fully ready
    sleep 15
    python3 "$SCRIPT_DIR/guacamole-manager.py" import "$PROJECT_DIR/templates/sample-connections.csv" || {
        echo "Python import failed, trying bash script..."
        bash "$SCRIPT_DIR/manage-connections.sh" add-rdp "Windows Server 2022 - Sample" "192.168.1.100" "administrator" "changeme" "MYDOMAIN"
    }
fi

echo ""
echo "Deployment completed successfully!"
echo "Visit http://172.22.18.12:8080/guacamole/ to access your Guacamole VDI solution."