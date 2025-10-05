# Apache Guacamole Manager

A comprehensive tool for deploying and managing Apache Guacamole as a VDI (Virtual Desktop Infrastructure) solution on Synology NAS using Docker Compose. This tool is specifically designed for managing Windows Servers and virtualized desktops through Guacamole's web-based remote desktop gateway.

## Features

- **Easy Deployment**: One-command deployment on Synology NAS with Container Manager and Portainer
- **Network Optimization**: Pre-configured for macvlan-ovs_eth2 with custom subnet (172.22.18.0/24)
- **VDI Management**: Specialized tools for managing Windows servers and virtual desktops
- **Database Management**: PostgreSQL with automated initialization and backup/restore
- **Connection Management**: CLI and Python tools for bulk connection management
- **SSL Ready**: Nginx reverse proxy with SSL/TLS support
- **Active Directory Integration**: Optional LDAP/AD authentication
- **Session Recording**: Built-in session recording capabilities
- **Automated Backups**: Scheduled backup and restore functionality

## Architecture

The deployment consists of the following services:

- **PostgreSQL Database** (172.22.18.10) - Stores Guacamole configuration and user data
- **Guacamole Daemon** (172.22.18.11) - Handles RDP/VNC/SSH connections
- **Guacamole Web App** (172.22.18.12) - Web-based management interface
- **Nginx Reverse Proxy** (172.22.18.13) - SSL termination and load balancing

## Prerequisites

- Synology NAS with Docker support
- Container Manager or Portainer.io installed
- Network: macvlan-ovs_eth2 configured
- Storage: /volume1/guacamole directory prepared
- Subnet: 172.22.18.0/24 available

## Quick Start

### 1. Clone and Configure

```bash
git clone <repository-url>
cd guacamole-manager
cp .env.example .env
```

Edit `.env` file with your settings:
```bash
# Required: Set a secure PostgreSQL password
POSTGRES_PASSWORD=your_secure_password_here

# Optional: Active Directory integration
LDAP_HOSTNAME=your-ad-server.domain.com
LDAP_USER_BASE_DN=CN=Users,DC=yourdomain,DC=com
LDAP_USERNAME_ATTRIBUTE=sAMAccountName
```

### 2. Deploy with One Command

```bash
./deploy.sh
```

This script will:
- Create necessary Synology directories
- Initialize the PostgreSQL database
- Start all Docker services
- Perform health checks
- Display access information

### 3. Access Guacamole

- **URL**: http://172.22.18.12:8080/guacamole/
- **Username**: `guacadmin`
- **Password**: `guacadmin` (change after first login)

## Management Tools

### Bash Scripts

#### Add RDP Connections
```bash
# Add Windows Server
./scripts/manage-connections.sh add-rdp "Windows Server 2022" "192.168.1.100" "administrator" "password" "MYDOMAIN"

# Add Windows 10 VDI
./scripts/manage-connections.sh add-rdp "Win10-VDI-01" "192.168.1.110" "user01" "password" "MYDOMAIN"
```

#### Add VNC Connections
```bash
# Add Ubuntu Desktop
./scripts/manage-connections.sh add-vnc "Ubuntu Desktop" "192.168.1.120" "vncpassword" "5900"
```

#### List and Manage Connections
```bash
# List all connections
./scripts/manage-connections.sh list

# Delete connection
./scripts/manage-connections.sh delete <connection_id>

# Create connection group
./scripts/manage-connections.sh create-group "Windows Servers"
```

### Python Manager

Install Python dependencies:
```bash
pip install -r requirements.txt
```

#### Command Line Usage
```bash
# Add RDP connection
python3 scripts/guacamole-manager.py add-rdp "Server Name" "192.168.1.100" "username" "password" --domain "MYDOMAIN"

# Add VNC connection
python3 scripts/guacamole-manager.py add-vnc "Desktop Name" "192.168.1.120" "vncpassword"

# List connections (table format)
python3 scripts/guacamole-manager.py list

# List connections (JSON format)
python3 scripts/guacamole-manager.py list --format json

# Import from CSV
python3 scripts/guacamole-manager.py import templates/sample-connections.csv

# Delete connection
python3 scripts/guacamole-manager.py delete <connection_id>
```

#### Bulk Import from CSV

Create a CSV file with your connections:
```csv
name,protocol,hostname,username,password,domain,port,description
Windows Server 2022,rdp,192.168.1.100,administrator,AdminPass123,MYDOMAIN,3389,Primary DC
Windows 10 VDI,rdp,192.168.1.110,user01,UserPass123,MYDOMAIN,3389,Virtual Desktop
Ubuntu Desktop,vnc,192.168.1.120,,VncPass123,,5900,Linux Desktop
```

Import the connections:
```bash
python3 scripts/guacamole-manager.py import your-connections.csv
```

## Backup and Restore

### Create Backup
```bash
./scripts/backup-restore.sh backup
```

This creates a complete backup including:
- PostgreSQL database dump
- Configuration files
- Session recordings
- Docker Compose configuration

### Restore from Backup
```bash
# List available backups
./scripts/backup-restore.sh list

# Restore from specific backup
./scripts/backup-restore.sh restore /volume1/guacamole/backups/backup_20231201_143022
```

### Export Connections
```bash
./scripts/backup-restore.sh export-connections
```

## Configuration

### Docker Compose

The main configuration is in `docker-compose.yml`. Key settings:

- **Network**: Uses macvlan driver with ovs_eth2 parent interface
- **Volumes**: Maps to Synology /volume1/guacamole
- **Health Checks**: PostgreSQL health monitoring
- **Dependencies**: Proper service startup order

### Nginx Configuration

SSL configuration (optional):
1. Place SSL certificates in `config/nginx/ssl/`
2. Edit `config/nginx/nginx.conf` to uncomment HTTPS sections
3. Restart nginx container

### Active Directory Integration

Add to your `.env` file:
```bash
LDAP_HOSTNAME=your-ad-server.domain.com
LDAP_PORT=389
LDAP_USER_BASE_DN=CN=Users,DC=yourdomain,DC=com
LDAP_USERNAME_ATTRIBUTE=sAMAccountName
LDAP_GROUP_BASE_DN=CN=Users,DC=yourdomain,DC=com
```

## VDI Use Cases

### Windows Server Management
- Remote administration of Windows Servers
- File server access and management
- Domain controller administration
- SQL Server management

### Virtual Desktop Infrastructure
- Windows 10/11 virtual desktops
- User-specific desktop environments
- Centralized desktop management
- Session recording for compliance

### Mixed Environment Support
- Windows RDP connections
- Linux VNC desktops
- SSH terminal access
- Web-based applications

## Monitoring and Maintenance

### Health Checks
```bash
# Check service status
docker-compose ps

# View logs
docker-compose logs guacamole
docker-compose logs guacamole-db
docker-compose logs guacd

# Check database connectivity
docker exec guacamole-postgres pg_isready -U guacamole_user
```

### Performance Tuning

#### PostgreSQL Optimization
Edit database parameters in docker-compose.yml:
```yaml
environment:
  POSTGRES_SHARED_PRELOAD_LIBRARIES: pg_stat_statements
  POSTGRES_MAX_CONNECTIONS: 200
  POSTGRES_SHARED_BUFFERS: 256MB
```

#### Guacamole Optimization
```yaml
environment:
  GUACAMOLE_HOME: /opt/guacamole
  GUACD_LOG_LEVEL: info
```

### Session Recording

Recordings are stored in `/volume1/guacamole/home/record/`. To enable:

1. Edit connection parameters
2. Set `recording-path` to `/var/lib/guacamole/recordings`
3. Set `create-recording-path` to `true`

## Troubleshooting

### Common Issues

#### Database Connection Failed
```bash
# Check database logs
docker-compose logs guacamole-db

# Verify network connectivity
docker exec guacamole ping 172.22.18.10
```

#### Guacamole Web Interface Not Accessible
```bash
# Check Guacamole logs
docker-compose logs guacamole

# Verify guacd connectivity
docker exec guacamole telnet 172.22.18.11 4822
```

#### RDP Connection Issues
- Verify Windows server allows RDP connections
- Check firewall settings on target server
- Ensure correct credentials and domain
- Verify network connectivity from Guacamole to target

#### VNC Connection Issues
- Verify VNC server is running on target
- Check VNC password configuration
- Ensure correct port is specified
- Test network connectivity

### Log Files

- **Guacamole**: `docker-compose logs guacamole`
- **Database**: `docker-compose logs guacamole-db`
- **Guacd**: `docker-compose logs guacd`
- **Nginx**: `/volume1/guacamole/home/nginx-logs/`

## Security Considerations

1. **Change Default Passwords**: Immediately change the default admin password
2. **SSL/TLS**: Enable HTTPS for production use
3. **Network Security**: Restrict access to Guacamole network
4. **Regular Updates**: Keep Docker images updated
5. **Backup Encryption**: Encrypt backup files
6. **Access Controls**: Use connection groups and user permissions

## Updates and Upgrades

### Update Guacamole Version

1. Update image versions in `docker-compose.yml`
2. Create backup: `./scripts/backup-restore.sh backup`
3. Pull new images: `docker-compose pull`
4. Restart services: `docker-compose up -d`

### Database Schema Updates

Major version updates may require schema changes. Check Guacamole documentation for upgrade procedures.

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review Docker logs
3. Consult Apache Guacamole documentation
4. Open an issue in the project repository

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

---

**Note**: This tool is designed specifically for Synology NAS environments with Container Manager and Portainer. Adaptations may be needed for other environments.
Guacamole Manager makes it easy to deploy and manage Apache Guacamole with Docker Compose, no manual setup required. It includes scripts to automate configuration, manage users, add or remove RDP, SSH, and VNC connections, and handle backups. Perfect for labs, SMB customers and DevOps environments needing quick, repeatable remote access.
