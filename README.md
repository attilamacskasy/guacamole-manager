# Apache Guacamole Manager

A comprehensive tool for deploying and managing Apache Guacamole as a VDI (Virtual Desktop Infrastructure) solution on Synology NAS using Docker Compose. This toolkit provides **fully automated deployment** from an Ubuntu VM in the same network, designed for CI/CD workflows and self-hosted GitHub workflow runners.

## Automated Deployment Scripts

This toolkit includes three sequential automation scripts for complete hands-free deployment:

### **Script 01**: `01_setup-guacamole-manager.sh` *(Coming Soon)*
- **Purpose**: Initial Ubuntu VM preparation and dependency installation
- **Function**: Installs all required packages, Docker, Python dependencies
- **Target**: Fresh Ubuntu 24.04 desktop/server installations

### **Script 02**: `02_setup-guacamole-manager.sh`
- **Purpose**: Configure remote Docker access to Synology NAS via SSH
- **Function**: Sets up secure SSH-based Docker command execution
- **Features**: 
  - Interactive credential collection with defaults
  - Remote Docker validation and testing
  - Python virtual environment creation
  - Clean CLI experience with debug mode option

### **Script 03**: `03_deploy-guacamole-stack.sh`
- **Purpose**: Deploy complete Guacamole stack to Synology NAS
- **Function**: Validates environment, creates folder structure, deploys containers
- **Features**:
  - Synology shared folder validation and creation
  - Docker Compose file transfer and deployment
  - Container status monitoring and health checks

## 🎯 Use Cases

- **Local Development**: Quick VDI deployment for testing and development
- **CI/CD Integration**: Automated deployment from GitHub Actions or GitLab CI
- **Self-Hosted Runners**: Deploy from GitHub self-hosted workflow runners
- **Network-Isolated Deployment**: Ubuntu VM → Synology NAS in same network
- **Repeatable Infrastructure**: Version-controlled, scriptable deployments

## 🏗️ Architecture

The deployment consists of the following services:

- **PostgreSQL Database** (172.22.18.10) - Stores Guacamole configuration and user data
- **Guacamole Daemon** (172.22.18.11) - Handles RDP/VNC/SSH connections
- **Guacamole Web App** (172.22.18.12) - Web-based management interface
- **Nginx Reverse Proxy** (172.22.18.13) - SSL termination and load balancing

## 📋 Prerequisites

### Synology NAS
- Synology NAS with Docker package installed
- SSH access enabled (Control Panel → Terminal & SNMP → Enable SSH)
- User account with admin/sudo privileges
- Network: macvlan-ovs_eth2 configured
- Subnet: 172.22.18.0/24 available

### Ubuntu VM (Deployment Machine)
- Ubuntu 24.04 LTS (desktop or server)
- Network connectivity to Synology NAS
- Internet access for package downloads
- SSH client capabilities

## Quick Start - Automated Deployment

### Step 1: Initial Setup
```bash
git clone https://github.com/attilamacskasy/guacamole-manager.git
cd guacamole-manager
```

### Step 2: Configure Remote Docker Access
```bash
./02_setup-guacamole-manager.sh
```
- Enter Synology IP, username, and SSH credentials
- Script validates connection and sets up remote Docker access
- Creates Python virtual environment with dependencies

### Step 3: Deploy Guacamole Stack
```bash
./03_deploy-guacamole-stack.sh
```
- Validates Synology environment and folder structure
- Creates required directories automatically
- Deploys complete Guacamole stack via Docker Compose

### Step 4: Access Guacamole
```
Web Interface: http://YOUR_SYNOLOGY_IP:8080/guacamole
Default Login: guacadmin / guacadmin
```

## �️ Advanced Usage

### Skip Package Installation (Subsequent Runs)
```bash
# Skip Ubuntu package installation if already done
./02_setup-guacamole-manager.sh --skip-install

# Enable debug output for troubleshooting  
./02_setup-guacamole-manager.sh --skip-install --debug
```

### CI/CD Integration Examples

#### GitHub Actions Workflow
```yaml
name: Deploy Guacamole to Synology
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: [self-hosted, linux]  # Your Ubuntu runner
    steps:
      - uses: actions/checkout@v4
      - name: Setup Environment
        run: ./02_setup-guacamole-manager.sh --skip-install
        env:
          SSH_PASS: ${{ secrets.SYNOLOGY_PASSWORD }}
      - name: Deploy Stack  
        run: ./03_deploy-guacamole-stack.sh
```

#### GitLab CI Pipeline
```yaml
stages:
  - deploy

deploy_guacamole:
  stage: deploy
  tags:
    - ubuntu-runner
  script:
    - ./02_setup-guacamole-manager.sh --skip-install
    - ./03_deploy-guacamole-stack.sh
  only:
    - main
```

### Environment Variables
Set these for non-interactive deployment:
```bash
export SYNOLOGY_IP="172.22.22.253"
export SSH_USER="admin"  
export SSH_PASS="your_password"
export SSH_PORT="22"
```

## 📂 Required Synology Setup

### Create Shared Folder
1. **DSM Web Interface** → **Control Panel** → **Shared Folder**
2. **Create** new folder named **`guacamole`** on **volume1**
3. **Set permissions** for your SSH user account
4. **Enable SSH** in **Control Panel** → **Terminal & SNMP**

### Folder Structure (Auto-Created)
```
/volume1/guacamole/
├── db/                    # PostgreSQL data
├── dbinit/               # Database initialization scripts
├── home/                 # Guacamole home directory
│   ├── drive/            # File sharing storage  
│   ├── record/           # Session recordings
│   ├── extensions/       # Guacamole extensions
│   └── nginx-logs/       # Web server logs
└── deploy/               # Docker Compose files (auto-created)
```

## 🌐 Network Configuration

### Synology Network Setup
- **Interface**: ovs_eth2 (macvlan)
- **Subnet**: 172.22.18.0/24
- **Gateway**: 172.22.18.1

### Service IP Addresses
- **PostgreSQL**: 172.22.18.10:5432
- **Guacamole Daemon**: 172.22.18.11:4822  
- **Web Interface**: 172.22.18.12:8080
- **Nginx Proxy**: 172.22.18.13:80,443

## 🔧 Manual Configuration (Legacy Method)

*For reference only - use automated scripts above for new deployments*

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
