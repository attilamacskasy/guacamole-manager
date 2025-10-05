#!/bin/bash

# Guacamole Database Initialization Script
# This script initializes the PostgreSQL database for Guacamole

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

echo "Initializing Guacamole database..."

# Create necessary directories on Synology
echo "Creating Synology directories..."
mkdir -p /volume1/guacamole/db
mkdir -p /volume1/guacamole/dbinit
mkdir -p /volume1/guacamole/home/drive
mkdir -p /volume1/guacamole/home/record
mkdir -p /volume1/guacamole/home/extensions
mkdir -p /volume1/guacamole/home/nginx-logs

# Download Guacamole SQL scripts
GUACAMOLE_VERSION="1.5.4"
DBINIT_DIR="/volume1/guacamole/dbinit"

echo "Downloading Guacamole database initialization scripts..."

# Download PostgreSQL schema
curl -L "https://raw.githubusercontent.com/apache/guacamole-server/main/src/protocols/rdp/guac_rdpdr.sql" \
    -o "$DBINIT_DIR/001-create-schema.sql" || {
    echo "Creating schema manually..."
    cat > "$DBINIT_DIR/001-create-schema.sql" << 'EOF'
--
-- PostgreSQL database schema for Apache Guacamole
--

-- Create the database and user if they don't exist
DO
$do$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'guacamole_user') THEN
      CREATE ROLE guacamole_user LOGIN PASSWORD 'POSTGRES_PASSWORD_PLACEHOLDER';
   END IF;
END
$do$;

-- Create database if it doesn't exist
SELECT 'CREATE DATABASE guacamole_db OWNER guacamole_user'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'guacamole_db')\gexec

-- Connect to the guacamole database
\c guacamole_db;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE guacamole_db TO guacamole_user;
GRANT ALL PRIVILEGES ON SCHEMA public TO guacamole_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO guacamole_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO guacamole_user;

-- The actual schema will be created by the Guacamole container
EOF
}

# Replace password placeholder
sed -i "s/POSTGRES_PASSWORD_PLACEHOLDER/$POSTGRES_PASSWORD/g" "$DBINIT_DIR/001-create-schema.sql"

# Generate Guacamole schema using Docker
echo "Generating Guacamole PostgreSQL schema..."
docker run --rm guacamole/guacamole:$GUACAMOLE_VERSION /opt/guacamole/bin/initdb.sh --postgresql > "$DBINIT_DIR/002-initdb.sql"

# Create initial admin user and configuration
cat > "$DBINIT_DIR/003-admin-user.sql" << EOF
-- Create default admin user
-- Password is 'guacadmin' (change after first login)
INSERT INTO guacamole_entity (name, type) VALUES ('$DEFAULT_ADMIN_USERNAME', 'USER');
INSERT INTO guacamole_user (entity_id, password_hash, password_salt, password_date)
SELECT 
    entity_id,
    decode('CA458A7D494E3BE824F5E1E175A1556C0F8EEF2C2D7DF3633BEC4A29C4411960', 'hex'),
    decode('FE24ADC5E11E2B25288D1704ABE67A79E342ECC26064CE69C5B3177795A82264', 'hex'),
    NOW()
FROM guacamole_entity WHERE name = '$DEFAULT_ADMIN_USERNAME' AND type = 'USER';

-- Grant admin permissions
INSERT INTO guacamole_user_permission (entity_id, affected_user_id, permission)
SELECT entity_id, entity_id, permission::guacamole_object_permission
FROM (
    SELECT entity_id FROM guacamole_entity WHERE name = '$DEFAULT_ADMIN_USERNAME' AND type = 'USER'
) u
CROSS JOIN (
    VALUES ('READ'), ('UPDATE'), ('DELETE'), ('ADMINISTER')
) p(permission);

-- Grant system permissions
INSERT INTO guacamole_system_permission (entity_id, permission)
SELECT entity_id, permission::guacamole_system_permission
FROM (
    SELECT entity_id FROM guacamole_entity WHERE name = '$DEFAULT_ADMIN_USERNAME' AND type = 'USER'
) u
CROSS JOIN (
    VALUES ('CREATE_CONNECTION'), ('CREATE_CONNECTION_GROUP'), ('CREATE_SHARING_PROFILE'), ('CREATE_USER'), ('CREATE_USER_GROUP'), ('ADMINISTER')
) p(permission);
EOF

echo "Database initialization files created successfully!"
echo "You can now run 'docker-compose up -d' to start the Guacamole stack."