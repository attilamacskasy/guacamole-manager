#!/bin/bash
# 00_Setup_Permissions.sh
# This script sets execute permissions on all shell scripts in the Guacamole Manager toolkit.
# Run this after cloning the repository to ensure all scripts are executable.

echo "Guacamole Manager - Setting Execute Permissions"
echo "=============================================="
echo ""

# Main Configuration and Deployment Scripts
echo "Setting permissions for main deployment scripts:"

chmod +x 01A_Load_Config.sh
echo "  01A_Load_Config.sh        - Configuration loader with secure password prompting"

chmod +x 01B_Validate_Config.sh  
echo "  01B_Validate_Config.sh    - Configuration validation and system requirements check"

chmod +x 02_Setup_Guacamole-Manager.sh
echo "  02_Setup_Guacamole-Manager.sh - Environment setup and SSH Docker configuration"

chmod +x 03_Deploy-Guacamole-Stack.sh
echo "  03_Deploy-Guacamole-Stack.sh  - Complete Guacamole stack deployment to Synology"

echo ""
echo "Setting permissions for utility and management scripts:"

# Scripts directory
if [[ -d "scripts" ]]; then
    chmod +x scripts/backup-restore.sh
    echo "  scripts/backup-restore.sh     - Database and configuration backup/restore utility"
    
    chmod +x scripts/init-db.sh
    echo "  scripts/init-db.sh           - Database initialization and schema setup"
    
    chmod +x scripts/manage-connections.sh
    echo "  scripts/manage-connections.sh - RDP/VNC/SSH connection management"
    
    # Python script (already executable by default, but ensure it's noted)
    if [[ -f "scripts/guacamole-manager.py" ]]; then
        chmod +x scripts/guacamole-manager.py
        echo "  scripts/guacamole-manager.py  - Python-based Guacamole connection manager"
    fi
fi

echo ""
echo "Setting permissions for additional utility scripts:"

# Find and set permissions for any other shell scripts
find . -maxdepth 1 -name "*.sh" -not -name "00_Setup_Permissions.sh" -exec chmod +x {} \;

echo ""
echo "=============================================="
echo "Execute permissions set successfully!"
echo ""
echo "Script Categories:"
echo "  Configuration: 01A_*, 01B_* - Config loading and validation"
echo "  Setup:         02_*         - Environment and SSH setup" 
echo "  Deployment:    03_*         - Stack deployment to Synology"
echo "  Management:    scripts/*    - Backup, restore, and connection management"
echo ""
echo "Next steps:"
echo "  1. Configure: Edit 00_Guacamole-Manager_Config.json"
echo "  2. Validate:  ./01B_Validate_Config.sh"
echo "  3. Setup:     ./02_Setup_Guacamole-Manager.sh"
echo "  4. Deploy:    ./03_Deploy-Guacamole-Stack.sh"
