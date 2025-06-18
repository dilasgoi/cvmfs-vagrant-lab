#!/bin/bash
set -e

# Use same environment variables as native
: ${REPOSITORY_NAME:=software.lab.local}
: ${GATEWAY_IP:=192.168.58.10}
: ${GATEWAY_PORT:=4929}
: ${STRATUM0_IP:=192.168.58.10}

echo "=== CVMFS Publisher Container ==="
echo "Repository: $REPOSITORY_NAME"

# Detect architecture (same as native)
ARCH=$(python3 -c "import archspec.cpu; print(archspec.cpu.host().name)" 2>/dev/null || echo "unknown")
echo "Architecture: $ARCH"

# Get repository keys (same as native)
echo "Getting repository keys..."
mkdir -p /etc/cvmfs/keys
curl -sf http://$GATEWAY_IP/cvmfs/keys/${REPOSITORY_NAME}.pub > /etc/cvmfs/keys/${REPOSITORY_NAME}.pub
curl -sf http://$GATEWAY_IP/cvmfs/keys/${REPOSITORY_NAME}.crt > /etc/cvmfs/keys/${REPOSITORY_NAME}.crt
curl -sf http://$GATEWAY_IP/cvmfs/keys/${REPOSITORY_NAME}.gw > /etc/cvmfs/keys/${REPOSITORY_NAME}.gw
chmod 600 /etc/cvmfs/keys/${REPOSITORY_NAME}.gw

# Setup repository as publisher (same command as native!)
echo "Setting up publisher repository..."
cvmfs_server mkfs \
    -w http://$STRATUM0_IP/cvmfs/$REPOSITORY_NAME \
    -u gw,/srv/cvmfs/$REPOSITORY_NAME/data/txn,http://$GATEWAY_IP:$GATEWAY_PORT/api/v1 \
    -k /etc/cvmfs/keys \
    -o publisher \
    $REPOSITORY_NAME 2>&1 | grep -v "not mounted properly" || true

echo "Repository configured successfully!"

# Create simple test script
cat > /home/publisher/test_publish.sh << 'EOF'
#!/bin/bash
echo "Testing CVMFS publishing..."

# Start transaction
echo "1. Starting transaction..."
cvmfs_server transaction software.lab.local

# The repository is now mounted at /cvmfs/software.lab.local
echo "2. Creating test file..."
echo "Hello from container at $(date)" > /cvmfs/software.lab.local/test_container.txt

# Publish
echo "3. Publishing..."
cvmfs_server publish software.lab.local

echo "Done!"
EOF
chmod +x /home/publisher/test_publish.sh

echo
echo "Container ready!"
echo "The repository will be mounted at /cvmfs/$REPOSITORY_NAME when you start a transaction"
echo
echo "Commands:"
echo "  cvmfs_server transaction $REPOSITORY_NAME  # Start transaction"
echo "  cvmfs_server publish $REPOSITORY_NAME     # Publish changes"
echo "  cvmfs_server abort -f $REPOSITORY_NAME    # Abort transaction"
echo
echo "Test with: ./test_publish.sh"
echo

# Keep container running
exec /bin/bash
