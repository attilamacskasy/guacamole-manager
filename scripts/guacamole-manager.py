#!/usr/bin/env python3
"""
Guacamole Manager - Python Tool for Managing Apache Guacamole
This tool provides a Python interface for managing Guacamole connections and users.
"""

import os
import sys
import json
import argparse
import requests
import psycopg2
from psycopg2.extras import RealDictCursor
from datetime import datetime
import configparser

class GuacamoleManager:
    def __init__(self, config_file=None):
        self.config = self.load_config(config_file)
        self.db_config = {
            'host': self.config.get('database', 'host', fallback='172.22.18.10'),
            'port': self.config.get('database', 'port', fallback='5432'),
            'database': self.config.get('database', 'name', fallback='guacamole_db'),
            'user': self.config.get('database', 'user', fallback='guacamole_user'),
            'password': self.config.get('database', 'password')
        }
        
        self.guacamole_url = self.config.get('guacamole', 'url', fallback='http://172.22.18.12:8080/guacamole')
        
    def load_config(self, config_file=None):
        """Load configuration from file or environment variables"""
        config = configparser.ConfigParser()
        
        if config_file and os.path.exists(config_file):
            config.read(config_file)
        else:
            # Create default config from environment variables
            config['database'] = {
                'host': os.getenv('DB_HOST', '172.22.18.10'),
                'port': os.getenv('DB_PORT', '5432'),
                'name': os.getenv('DB_NAME', 'guacamole_db'),
                'user': os.getenv('DB_USER', 'guacamole_user'),
                'password': os.getenv('POSTGRES_PASSWORD', '')
            }
            
            config['guacamole'] = {
                'url': os.getenv('GUACAMOLE_URL', 'http://172.22.18.12:8080/guacamole'),
                'admin_user': os.getenv('DEFAULT_ADMIN_USERNAME', 'guacadmin'),
                'admin_password': os.getenv('DEFAULT_ADMIN_PASSWORD', 'guacadmin')
            }
            
        return config
    
    def get_db_connection(self):
        """Get database connection"""
        try:
            return psycopg2.connect(**self.db_config)
        except psycopg2.Error as e:
            print(f"Error connecting to database: {e}")
            return None
    
    def add_rdp_connection(self, name, hostname, username, password, domain=None, port=3389, **kwargs):
        """Add RDP connection to Guacamole"""
        conn = self.get_db_connection()
        if not conn:
            return False
            
        try:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                # Insert connection
                cur.execute(
                    "INSERT INTO guacamole_connection (connection_name, protocol) VALUES (%s, %s) RETURNING connection_id",
                    (name, 'rdp')
                )
                connection_id = cur.fetchone()['connection_id']
                
                # Define RDP parameters
                parameters = {
                    'hostname': hostname,
                    'port': str(port),
                    'username': username,
                    'password': password,
                    'security': 'rdp',
                    'ignore-cert': 'true',
                    'enable-drive': 'true',
                    'drive-path': '/srv/guacamole',
                    'create-drive-path': 'true',
                    'enable-wallpaper': kwargs.get('enable_wallpaper', 'false'),
                    'enable-theming': kwargs.get('enable_theming', 'false'),
                    'enable-font-smoothing': kwargs.get('enable_font_smoothing', 'false'),
                    'color-depth': kwargs.get('color_depth', '16'),
                    'resize-method': kwargs.get('resize_method', 'reconnect')
                }
                
                if domain:
                    parameters['domain'] = domain
                
                # Insert parameters
                for param_name, param_value in parameters.items():
                    cur.execute(
                        "INSERT INTO guacamole_connection_parameter (connection_id, parameter_name, parameter_value) VALUES (%s, %s, %s)",
                        (connection_id, param_name, param_value)
                    )
                
                conn.commit()
                print(f"RDP connection '{name}' added successfully with ID: {connection_id}")
                return connection_id
                
        except psycopg2.Error as e:
            print(f"Error adding RDP connection: {e}")
            conn.rollback()
            return False
        finally:
            conn.close()
    
    def add_vnc_connection(self, name, hostname, password, port=5900, **kwargs):
        """Add VNC connection to Guacamole"""
        conn = self.get_db_connection()
        if not conn:
            return False
            
        try:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                # Insert connection
                cur.execute(
                    "INSERT INTO guacamole_connection (connection_name, protocol) VALUES (%s, %s) RETURNING connection_id",
                    (name, 'vnc')
                )
                connection_id = cur.fetchone()['connection_id']
                
                # Define VNC parameters
                parameters = {
                    'hostname': hostname,
                    'port': str(port),
                    'password': password,
                    'color-depth': kwargs.get('color_depth', '16'),
                    'swap-red-blue': kwargs.get('swap_red_blue', 'false'),
                    'cursor': kwargs.get('cursor', 'local'),
                    'autoretry': kwargs.get('autoretry', '5')
                }
                
                # Insert parameters
                for param_name, param_value in parameters.items():
                    cur.execute(
                        "INSERT INTO guacamole_connection_parameter (connection_id, parameter_name, parameter_value) VALUES (%s, %s, %s)",
                        (connection_id, param_name, param_value)
                    )
                
                conn.commit()
                print(f"VNC connection '{name}' added successfully with ID: {connection_id}")
                return connection_id
                
        except psycopg2.Error as e:
            print(f"Error adding VNC connection: {e}")
            conn.rollback()
            return False
        finally:
            conn.close()
    
    def list_connections(self):
        """List all connections"""
        conn = self.get_db_connection()
        if not conn:
            return []
            
        try:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("""
                    SELECT c.connection_id, c.connection_name, c.protocol,
                           cp.parameter_name, cp.parameter_value
                    FROM guacamole_connection c
                    LEFT JOIN guacamole_connection_parameter cp ON c.connection_id = cp.connection_id
                    ORDER BY c.connection_name, cp.parameter_name
                """)
                
                results = cur.fetchall()
                connections = {}
                
                for row in results:
                    conn_id = row['connection_id']
                    if conn_id not in connections:
                        connections[conn_id] = {
                            'id': conn_id,
                            'name': row['connection_name'],
                            'protocol': row['protocol'],
                            'parameters': {}
                        }
                    
                    if row['parameter_name']:
                        connections[conn_id]['parameters'][row['parameter_name']] = row['parameter_value']
                
                return list(connections.values())
                
        except psycopg2.Error as e:
            print(f"Error listing connections: {e}")
            return []
        finally:
            conn.close()
    
    def delete_connection(self, connection_id):
        """Delete a connection"""
        conn = self.get_db_connection()
        if not conn:
            return False
            
        try:
            with conn.cursor() as cur:
                # Delete parameters first
                cur.execute("DELETE FROM guacamole_connection_parameter WHERE connection_id = %s", (connection_id,))
                
                # Delete connection
                cur.execute("DELETE FROM guacamole_connection WHERE connection_id = %s", (connection_id,))
                
                if cur.rowcount > 0:
                    conn.commit()
                    print(f"Connection {connection_id} deleted successfully")
                    return True
                else:
                    print(f"Connection {connection_id} not found")
                    return False
                    
        except psycopg2.Error as e:
            print(f"Error deleting connection: {e}")
            conn.rollback()
            return False
        finally:
            conn.close()
    
    def bulk_import_connections(self, csv_file):
        """Import connections from CSV file"""
        import csv
        
        try:
            with open(csv_file, 'r') as f:
                reader = csv.DictReader(f)
                success_count = 0
                
                for row in reader:
                    protocol = row.get('protocol', 'rdp').lower()
                    name = row['name']
                    hostname = row['hostname']
                    
                    if protocol == 'rdp':
                        result = self.add_rdp_connection(
                            name=name,
                            hostname=hostname,
                            username=row['username'],
                            password=row['password'],
                            domain=row.get('domain'),
                            port=int(row.get('port', 3389))
                        )
                    elif protocol == 'vnc':
                        result = self.add_vnc_connection(
                            name=name,
                            hostname=hostname,
                            password=row['password'],
                            port=int(row.get('port', 5900))
                        )
                    else:
                        print(f"Unsupported protocol: {protocol}")
                        continue
                    
                    if result:
                        success_count += 1
                
                print(f"Successfully imported {success_count} connections from {csv_file}")
                
        except Exception as e:
            print(f"Error importing connections: {e}")

def main():
    parser = argparse.ArgumentParser(description='Guacamole Manager - Python Tool')
    parser.add_argument('--config', help='Configuration file path')
    
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    
    # Add RDP connection
    rdp_parser = subparsers.add_parser('add-rdp', help='Add RDP connection')
    rdp_parser.add_argument('name', help='Connection name')
    rdp_parser.add_argument('hostname', help='Server hostname/IP')
    rdp_parser.add_argument('username', help='Username')
    rdp_parser.add_argument('password', help='Password')
    rdp_parser.add_argument('--domain', help='Domain name')
    rdp_parser.add_argument('--port', type=int, default=3389, help='RDP port (default: 3389)')
    
    # Add VNC connection
    vnc_parser = subparsers.add_parser('add-vnc', help='Add VNC connection')
    vnc_parser.add_argument('name', help='Connection name')
    vnc_parser.add_argument('hostname', help='Server hostname/IP')
    vnc_parser.add_argument('password', help='VNC password')
    vnc_parser.add_argument('--port', type=int, default=5900, help='VNC port (default: 5900)')
    
    # List connections
    list_parser = subparsers.add_parser('list', help='List all connections')
    list_parser.add_argument('--format', choices=['table', 'json'], default='table', help='Output format')
    
    # Delete connection
    delete_parser = subparsers.add_parser('delete', help='Delete connection')
    delete_parser.add_argument('connection_id', type=int, help='Connection ID to delete')
    
    # Import connections
    import_parser = subparsers.add_parser('import', help='Import connections from CSV')
    import_parser.add_argument('csv_file', help='CSV file path')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return
    
    manager = GuacamoleManager(args.config)
    
    if args.command == 'add-rdp':
        manager.add_rdp_connection(
            name=args.name,
            hostname=args.hostname,
            username=args.username,
            password=args.password,
            domain=args.domain,
            port=args.port
        )
    
    elif args.command == 'add-vnc':
        manager.add_vnc_connection(
            name=args.name,
            hostname=args.hostname,
            password=args.password,
            port=args.port
        )
    
    elif args.command == 'list':
        connections = manager.list_connections()
        
        if args.format == 'json':
            print(json.dumps(connections, indent=2))
        else:
            # Table format
            print(f"{'ID':<5} {'Name':<30} {'Protocol':<10} {'Hostname':<20}")
            print("-" * 70)
            for conn in connections:
                hostname = conn['parameters'].get('hostname', 'N/A')
                print(f"{conn['id']:<5} {conn['name']:<30} {conn['protocol']:<10} {hostname:<20}")
    
    elif args.command == 'delete':
        manager.delete_connection(args.connection_id)
    
    elif args.command == 'import':
        manager.bulk_import_connections(args.csv_file)

if __name__ == '__main__':
    main()