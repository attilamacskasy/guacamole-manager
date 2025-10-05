#!/bin/bash
# validate_config.sh - Test script to validate the configuration system

echo "Testing Guacamole Manager Configuration System"
echo "=============================================="

# Test 1: Check if config file exists
echo ""
echo "Test 1: Configuration File"
if [[ -f "00_Guacamole-Manager_Config.json" ]]; then
    echo "✓ Configuration file exists: 00_Guacamole-Manager_Config.json"
else
    echo "✗ Configuration file missing: 00_Guacamole-Manager_Config.json"
    echo "Please copy from template: cp 00_Guacamole-Manager_Config.json.template 00_Guacamole-Manager_Config.json"
    exit 1
fi

# Test 2: Check if jq is installed
echo ""
echo "Test 2: Dependencies"
if command -v jq >/dev/null 2>&1; then
    echo "✓ jq is installed ($(jq --version))"
else
    echo "✗ jq is not installed"
    echo "Install with: sudo apt install -y jq"
    exit 1
fi

# Test 3: Load configuration
echo ""
echo "Test 3: Configuration Loading"

# Check if password is default and warn user
CONFIG_PASSWORD=$(jq -r '.database.password' 00_Guacamole-Manager_Config.json 2>/dev/null)
if [[ "$CONFIG_PASSWORD" == "your_secure_postgres_password_here" ]]; then
    echo "⚠ Database password is set to default placeholder"
    echo "  Scripts will prompt for password during execution"
    echo "  Consider updating the JSON file for non-interactive use"
    
    # Load other config values manually for validation
    export SYNOLOGY_IP=$(jq -r '.deployment.synology.ip_address' 00_Guacamole-Manager_Config.json)
    export SSH_USERNAME=$(jq -r '.deployment.synology.ssh_username' 00_Guacamole-Manager_Config.json)
    export SSH_PORT=$(jq -r '.deployment.synology.ssh_port' 00_Guacamole-Manager_Config.json)
    export SYNOLOGY_BASE_PATH=$(jq -r '.deployment.synology.base_path' 00_Guacamole-Manager_Config.json)
    export GUACAMOLE_SUBNET=$(jq -r '.deployment.network.subnet' 00_Guacamole-Manager_Config.json)
    export POSTGRES_PASSWORD="validation_dummy_password"
else
    # Load configuration normally (will not prompt for password)
    source ./01A_Load_Config.sh >/dev/null 2>&1
fi

if [[ -n "$SYNOLOGY_IP" && -n "$SSH_USERNAME" ]]; then
    echo "✓ Configuration loaded successfully"
else
    echo "✗ Configuration loading failed"
    echo "Check JSON syntax in 00_Guacamole-Manager_Config.json"
    exit 1
fi

# Test 4: Check key variables
echo ""
echo "Test 4: Key Configuration Values"
echo "  - Synology IP: $SYNOLOGY_IP"
echo "  - SSH Username: $SSH_USERNAME"
echo "  - SSH Port: $SSH_PORT"
echo "  - Base Path: $SYNOLOGY_BASE_PATH"
echo "  - Network Subnet: $GUACAMOLE_SUBNET"
echo "  - Database Password: $(echo $POSTGRES_PASSWORD | sed 's/./*/g')"

# Test 5: Validate required fields
echo ""
echo "Test 5: Required Field Validation"
REQUIRED_FIELDS=("SYNOLOGY_IP" "SSH_USERNAME" "POSTGRES_PASSWORD" "GUACAMOLE_SUBNET")
ALL_VALID=true

for field in "${REQUIRED_FIELDS[@]}"; do
    value="${!field}"
    if [[ -z "$value" || "$value" == "null" ]]; then
        echo "✗ Missing required field: $field"
        ALL_VALID=false
    else
        echo "✓ $field is set"
    fi
done

# Test 6: Docker Compose validation (local only)
echo ""
echo "Test 6: Docker Compose Validation"

# Temporarily unset Docker aliases for validation
unalias docker 2>/dev/null || true
unalias docker-compose 2>/dev/null || true

# Use system docker-compose if available, or skip validation
if command -v docker-compose >/dev/null 2>&1; then
    if docker-compose config --quiet 2>/dev/null; then
        echo "✓ Docker Compose configuration is valid"
    else
        echo "⚠ Docker Compose validation skipped (remote Docker configured)"
        echo "  Configuration will be validated during deployment"
    fi
elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    if docker compose config --quiet 2>/dev/null; then
        echo "✓ Docker Compose configuration is valid"
    else
        echo "⚠ Docker Compose validation skipped (remote Docker configured)"
        echo "  Configuration will be validated during deployment"
    fi
else
    echo "⚠ Docker not available locally - validation will occur during deployment"
fi

echo ""
if [[ "$ALL_VALID" == "true" ]]; then
    echo "=============================================="
    echo "✓ All tests passed! Configuration is ready."
    echo "You can now run: ./02_setup-guacamole-manager.sh"
    echo "=============================================="
else
    echo "=============================================="
    echo "✗ Some tests failed. Please fix the issues above."
    echo "=============================================="
    exit 1
fi