#!/bin/bash

# Test Deployment Script - Test SCP enhancements without full deployment
# This script tests file copying operations with the enhanced SCP handling

set -e

# Source the configuration
if [[ -f "01A_Load_Config.sh" ]]; then
    source 01A_Load_Config.sh
else
    echo "Configuration loader not found. Please run from the guacamole-manager directory."
    exit 1
fi

echo "========================================"
echo "Testing Enhanced SCP Deployment Features"
echo "========================================"
echo ""
echo "Target: $SSH_USERNAME@$SYNOLOGY_IP:$SSH_PORT"
echo "Deploy folder: $FOLDER_DEPLOY"
echo ""

# Test SSH connection
echo "1. Testing SSH connection..."
SSH_TEST=$(sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "echo 'SSH connection successful'" 2>&1)
if [[ "$SSH_TEST" == *"SSH connection successful"* ]]; then
    echo "   SSH connection: OK"
else
    echo "   SSH connection: FAILED"
    echo "   Output: $SSH_TEST"
    exit 1
fi

# Create test directory
echo ""
echo "2. Creating test directory..."
TEST_DIR="${FOLDER_DEPLOY}_test_$(date +%s)"
echo "   Test directory: $TEST_DIR"

CREATE_RESULT=$(sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "mkdir -p $TEST_DIR && echo 'Test directory created'" 2>&1)
if [[ "$CREATE_RESULT" == *"Test directory created"* ]]; then
    echo "   Test directory creation: OK"
else
    echo "   Test directory creation: FAILED"
    echo "   Output: $CREATE_RESULT"
    exit 1
fi

# Create a small test file
echo ""
echo "3. Creating test files..."
echo "This is a test file for SCP timeout verification" > test_file.txt
echo "Test timestamp: $(date)" >> test_file.txt
echo "   Created test_file.txt"

# Test SCP with timeout (small file should succeed)
echo ""
echo "4. Testing SCP with timeout (30 seconds)..."
echo "   Command: timeout 30 sshpass -p [PASS] scp -v -o ConnectTimeout=10 -o ServerAliveInterval=5 -P $SSH_PORT test_file.txt $SSH_USERNAME@$SYNOLOGY_IP:$TEST_DIR/"

timeout 30 sshpass -p "$SSH_PASS" scp -v -o ConnectTimeout=10 -o ServerAliveInterval=5 -P $SSH_PORT test_file.txt "$SSH_USERNAME@$SYNOLOGY_IP:$TEST_DIR/" 2>&1
SCP_EXIT_CODE=$?

if [[ $SCP_EXIT_CODE -eq 0 ]]; then
    echo "   SCP test: SUCCESS"
elif [[ $SCP_EXIT_CODE -eq 124 ]]; then
    echo "   SCP test: TIMEOUT (this indicates SCP hanging issues)"
    echo "   Testing SSH fallback method..."
    
    # Test SSH fallback
    cat test_file.txt | sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "cat > $TEST_DIR/test_file_ssh.txt"
    SSH_EXIT_CODE=$?
    
    if [[ $SSH_EXIT_CODE -eq 0 ]]; then
        echo "   SSH fallback method: SUCCESS"
    else
        echo "   SSH fallback method: FAILED (exit code: $SSH_EXIT_CODE)"
    fi
else
    echo "   SCP test: FAILED (exit code: $SCP_EXIT_CODE)"
fi

# Verify files on remote
echo ""
echo "5. Verifying remote files..."
REMOTE_FILES=$(sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "ls -la $TEST_DIR/" 2>&1)
echo "   Files in test directory:"
echo "$REMOTE_FILES"

# Cleanup
echo ""
echo "6. Cleaning up..."
sshpass -p "$SSH_PASS" ssh -p $SSH_PORT "$SSH_USERNAME@$SYNOLOGY_IP" "rm -rf $TEST_DIR" 2>/dev/null || echo "   Warning: Could not remove test directory"
rm -f test_file.txt 2>/dev/null || echo "   Warning: Could not remove local test file"

echo ""
echo "========================================"
echo "Test completed!"
echo "========================================"
echo ""
echo "If SCP timed out but SSH fallback worked, your deployment script"
echo "will now use the SSH method automatically when SCP fails."
echo ""
echo "You can now run './03_Deploy_Guacamole_Stack.sh' with confidence"
echo "that it will handle SCP timeout issues gracefully."