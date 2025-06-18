#!/bin/bash
set -e

# Use same environment variables as native
: ${REPOSITORY_NAME:=software.lab.local}
: ${GATEWAY_IP:=192.168.58.10}
: ${GATEWAY_PORT:=4929}
: ${STRATUM0_IP:=192.168.58.10}

echo "=== CVMFS Publisher Container ==="
echo "Repository: $REPOSITORY_NAME"
echo "Running as: $(whoami) (uid=$(id -u))"

# Detect architecture (same as native)
ARCH=$(python3 -c "import archspec.cpu; print(archspec.cpu.host().name)" 2>/dev/null || echo "unknown")
echo "Architecture: $ARCH"

# Get repository keys (same as native)
echo "Getting repository keys..."
mkdir -p /etc/cvmfs/keys
for key in pub crt gw; do
    if curl -sf http://$GATEWAY_IP/cvmfs/keys/${REPOSITORY_NAME}.$key > /etc/cvmfs/keys/${REPOSITORY_NAME}.$key; then
        echo "  ✓ Downloaded ${REPOSITORY_NAME}.$key"
    else
        echo "  ✗ Failed to download ${REPOSITORY_NAME}.$key"
    fi
done
chmod 600 /etc/cvmfs/keys/${REPOSITORY_NAME}.gw

# Determine which user to use for CVMFS operations
if [[ $(id -u) -eq 0 ]]; then
    CVMFS_USER="root"
    echo "Running as root, using root for CVMFS operations"
else
    CVMFS_USER="publisher"
    echo "Running as publisher user"
fi

# Setup repository as publisher
echo "Setting up publisher repository..."
if cvmfs_server mkfs \
    -w http://$STRATUM0_IP/cvmfs/$REPOSITORY_NAME \
    -u gw,/srv/cvmfs/$REPOSITORY_NAME/data/txn,http://$GATEWAY_IP:$GATEWAY_PORT/api/v1 \
    -k /etc/cvmfs/keys \
    -o $CVMFS_USER \
    $REPOSITORY_NAME; then
    echo "✓ Repository configured successfully!"
else
    echo "✗ Repository setup failed (exit code: $?)"
    echo "  This might be normal if the repository already exists"

    # Check if repository exists
    if [[ -d /etc/cvmfs/repositories.d/$REPOSITORY_NAME ]]; then
        echo "  Repository configuration found, continuing..."
    fi
fi

# Manual overlay mount for container environment
echo
echo "Setting up overlay filesystem for container..."

# Ensure mount point exists
mkdir -p /cvmfs/$REPOSITORY_NAME

# Ensure scratch directories exist
mkdir -p /var/spool/cvmfs/$REPOSITORY_NAME/scratch/current
mkdir -p /var/spool/cvmfs/$REPOSITORY_NAME/ofs_workdir

# Check if already mounted
if mountpoint -q /cvmfs/$REPOSITORY_NAME; then
    echo "✓ /cvmfs/$REPOSITORY_NAME is already mounted"
else
    echo "Mounting overlay filesystem with fuse-overlayfs..."
    if fuse-overlayfs \
        -o lowerdir=/var/spool/cvmfs/$REPOSITORY_NAME/rdonly \
        -o upperdir=/var/spool/cvmfs/$REPOSITORY_NAME/scratch/current \
        -o workdir=/var/spool/cvmfs/$REPOSITORY_NAME/ofs_workdir \
        /cvmfs/$REPOSITORY_NAME; then
        echo "✓ Overlay filesystem mounted successfully"
    else
        echo "✗ Failed to mount overlay filesystem"
        echo "  Transactions may not work properly"
    fi
fi

# Test transaction capability
echo
echo "Testing transaction capability..."
if cvmfs_server transaction $REPOSITORY_NAME; then
    echo "✓ Transaction successful!"
    echo "Test file from container at $(date)" > /cvmfs/$REPOSITORY_NAME/container_test_$(date +%s).txt
    cvmfs_server abort -f $REPOSITORY_NAME
    echo "  (Test transaction aborted)"
else
    echo "✗ Cannot create transactions"
    echo "  This is expected if running without proper mount capabilities"
fi

# If GitHub credentials provided, setup and run the runner
if [[ -n "$GITHUB_REPO" && -n "$GITHUB_TOKEN" ]]; then
    echo
    echo "Setting up GitHub Actions runner..."
    cd /home/publisher
    curl -o actions-runner.tar.gz -L https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz
    tar xzf actions-runner.tar.gz
    rm -f actions-runner.tar.gz

    # Configure runner
    ./config.sh \
        --url "$GITHUB_REPO" \
        --token "$GITHUB_TOKEN" \
        --name "container-publisher-$ARCH" \
        --labels "self-hosted,linux,cvmfs-publisher,container,$ARCH" \
        --work "_work" \
        --unattended \
        --replace

    echo "Starting GitHub Actions runner..."
    exec ./run.sh
else
    echo
    echo "Container ready for manual operations."
    echo ""
    echo "Available commands:"
    echo "  cvmfs_server list"
    echo "  cvmfs_server transaction $REPOSITORY_NAME"
    echo "  cvmfs_server publish $REPOSITORY_NAME"
    echo "  cvmfs_server abort -f $REPOSITORY_NAME"
    echo ""
    echo "Example workflow:"
    echo "  cvmfs_server transaction $REPOSITORY_NAME"
    echo "  echo 'Hello from container' > /cvmfs/$REPOSITORY_NAME/test.txt"
    echo "  cvmfs_server publish $REPOSITORY_NAME"
    echo ""
    echo "Dropping to interactive shell..."

    # Start interactive bash instead of tail -f
    exec /bin/bash
fi
