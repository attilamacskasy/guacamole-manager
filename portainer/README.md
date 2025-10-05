# Portainer Stack Deployment

This directory contains the stack configuration file for deploying Guacamole Manager using Portainer.

## Portainer Stack File

Copy the contents of `guacamole-stack.yml` to create a new stack in Portainer with the following configuration:

### Environment Variables

Set these environment variables in Portainer before deploying:

```
POSTGRES_PASSWORD=your_secure_postgres_password
LDAP_HOSTNAME=your-ad-server.domain.com (optional)
LDAP_PORT=389
LDAP_USER_BASE_DN=CN=Users,DC=yourdomain,DC=com
LDAP_USERNAME_ATTRIBUTE=sAMAccountName
LDAP_GROUP_BASE_DN=CN=Users,DC=yourdomain,DC=com
DEFAULT_ADMIN_USERNAME=guacadmin
DEFAULT_ADMIN_PASSWORD=guacadmin
```

### Network Configuration

Ensure the `macvlan-ovs_eth2` network exists in your Portainer environment. If it doesn't exist, create it with these settings:

- **Driver**: macvlan
- **Subnet**: 172.22.18.0/24
- **Gateway**: 172.22.18.1
- **Parent Interface**: ovs_eth2

### Volume Preparation

Before deployment, ensure these directories exist on your Synology NAS:

```bash
mkdir -p /volume1/guacamole/{db,dbinit,home/{drive,record,extensions,nginx-logs},backups}
chmod -R 755 /volume1/guacamole
```

## Deployment Steps

1. Access your Portainer web interface
2. Navigate to "Stacks"
3. Click "Add Stack"
4. Name your stack (e.g., "guacamole-vdi")
5. Copy the contents of `guacamole-stack.yml` into the editor
6. Configure environment variables
7. Click "Deploy the stack"

## Post-Deployment

After successful deployment:

1. Access Guacamole at: http://172.22.18.12:8080/guacamole/
2. Login with: guacadmin / guacadmin
3. Change the default password immediately
4. Begin adding your Windows servers and virtual desktops

## Monitoring

Use Portainer's container monitoring to check:
- Container health status
- Resource usage
- Logs for troubleshooting