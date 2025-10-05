#!/bin/bash

# Make scripts executable
find ./scripts -name "*.sh" -exec chmod +x {} \;

echo "Made all shell scripts executable"
echo ""
echo "Available commands:"
echo "  ./deploy.sh                           - Deploy Guacamole stack"
echo "  ./scripts/init-db.sh                  - Initialize database"
echo "  ./scripts/manage-connections.sh       - Manage RDP/VNC connections"
echo "  ./scripts/backup-restore.sh           - Backup and restore tools"
echo "  python3 scripts/guacamole-manager.py  - Python management tool"