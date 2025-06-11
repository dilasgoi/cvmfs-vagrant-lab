
#!/bin/bash
# Provisioning script for CVMFS publisher nodes
# Sets up a node that can publish content via the gateway

set -e

# Load common functions
source /vagrant/provisioning/common/functions.sh

log_section "Setting up Publisher node"

# Install CVMFS packages
install_packages() {
    log_info "Installing CVMFS client and server tools"
    apt-get install -y cvmfs cvmfs-server \
        || die "Failed to install CVMFS packages"
}

# Wait for gateway to be ready
wait_for_gateway() {
    log_info "Waiting for Gateway to be ready..."
    local max_attempts=60
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if curl -fs "http://$GATEWAY_IP:$GATEWAY_PORT/api/v1" > /dev/null 2>&1; then
            log_success "Gateway API is ready!"
            return 0
        fi
        log_info "Waiting for gateway... (attempt $attempt/$max_attempts)"
        sleep 5
        ((attempt++))
    done

    die "Gateway API not available after $max_attempts attempts"
}

# Download repository keys
get_repository_keys() {
    log_info "Downloading repository keys"
    mkdir -p /etc/cvmfs/keys

    # Download public key
    download_file \
        "http://$GATEWAY_IP/cvmfs/keys/${REPOSITORY_NAME}.pub" \
        "/etc/cvmfs/keys/${REPOSITORY_NAME}.pub" \
        || die "Failed to download public key"

    # Download certificate
    download_file \
        "http://$GATEWAY_IP/cvmfs/keys/${REPOSITORY_NAME}.crt" \
        "/etc/cvmfs/keys/${REPOSITORY_NAME}.crt" \
        || die "Failed to download certificate"

    # Download gateway key
    download_file \
        "http://$GATEWAY_IP/cvmfs/keys/${REPOSITORY_NAME}.gw" \
        "/etc/cvmfs/keys/${REPOSITORY_NAME}.gw" \
        || die "Failed to download gateway key"

    # Set secure permissions on gateway key
    chmod 600 "/etc/cvmfs/keys/${REPOSITORY_NAME}.gw"
}

# Setup publisher repository
setup_publisher_repository() {
    log_info "Setting up publisher repository"

    # Determine publisher user
    PUBLISHER_USER=${SUDO_USER:-$REPO_OWNER}
    if [ "$PUBLISHER_USER" = "root" ]; then
        PUBLISHER_USER="vagrant"
    fi

    log_info "Using publisher user: $PUBLISHER_USER"

    # Setup repository to use gateway
    cvmfs_server mkfs \
        -w "http://$STRATUM0_IP/cvmfs/$REPOSITORY_NAME" \
        -u "gw,/srv/cvmfs/$REPOSITORY_NAME/data/txn,http://$GATEWAY_IP:$GATEWAY_PORT/api/v1" \
        -k /etc/cvmfs/keys \
        -o "$PUBLISHER_USER" \
        "$REPOSITORY_NAME" \
        || die "Failed to setup publisher repository"
}

# Create publisher helper scripts
create_helper_scripts() {
    log_info "Creating publisher helper scripts"

    # Transaction start script
    cat > /usr/local/bin/publish-start << EOF
#!/bin/bash
echo "Starting transaction on $REPOSITORY_NAME..."
sudo cvmfs_server transaction $REPOSITORY_NAME
if [ \$? -eq 0 ]; then
    echo "Transaction started. You can now modify files in /cvmfs/$REPOSITORY_NAME/"
    echo "Use 'sudo' when creating/modifying files"
    echo "Run 'publish-complete' when done, or 'publish-abort' to cancel"
else
    echo "Failed to start transaction"
    exit 1
fi
EOF
    chmod +x /usr/local/bin/publish-start

    # Publish complete script
    cat > /usr/local/bin/publish-complete << EOF
#!/bin/bash
echo "Publishing changes to $REPOSITORY_NAME..."
sudo cvmfs_server publish $REPOSITORY_NAME
if [ \$? -eq 0 ]; then
    echo "Changes published successfully!"
else
    echo "Failed to publish changes"
    exit 1
fi
EOF
    chmod +x /usr/local/bin/publish-complete

    # Abort transaction script
    cat > /usr/local/bin/publish-abort << EOF
#!/bin/bash
echo "Aborting transaction on $REPOSITORY_NAME..."
sudo cvmfs_server abort -f $REPOSITORY_NAME
echo "Transaction aborted"
EOF
    chmod +x /usr/local/bin/publish-abort

    # Info script
    cat > /usr/local/bin/publish-info << EOF
#!/bin/bash
echo "=== Repository Publishing Information ==="
echo "Repository: $REPOSITORY_NAME"
echo "Gateway: http://$GATEWAY_IP:$GATEWAY_PORT/api/v1"
echo
echo "Commands:"
echo "  publish-start    - Start a transaction"
echo "  publish-complete - Commit and publish changes"
echo "  publish-abort    - Cancel current transaction"
echo
echo "Current status:"
cvmfs_server list
EOF
    chmod +x /usr/local/bin/publish-info
}

# Create test publishing script
create_test_script() {
    log_info "Creating test publishing script"

    cat > /home/vagrant/test_publish.sh << 'EOF'
#!/bin/bash
echo "=== Testing publisher functionality ==="
echo

echo "1. Starting transaction..."
sudo cvmfs_server transaction software.lab.local || exit 1

echo "2. Creating test file..."
TEST_FILE="/cvmfs/software.lab.local/test/publish_$(date +%Y%m%d_%H%M%S).txt"
sudo mkdir -p $(dirname $TEST_FILE)
echo "Test publish from $(hostname) at $(date)" | sudo tee $TEST_FILE > /dev/null
echo "Publisher: $(whoami)" | sudo tee -a $TEST_FILE > /dev/null

echo "3. Publishing changes..."
sudo cvmfs_server publish software.lab.local || exit 1

echo "4. Verifying published content..."
if [ -f "$TEST_FILE" ]; then
    echo "Success! File published:"
    cat $TEST_FILE
else
    echo "Error: Published file not found"
    exit 1
fi

echo
echo "=== Test complete ==="
EOF

    chmod +x /home/vagrant/test_publish.sh
    chown vagrant:vagrant /home/vagrant/test_publish.sh
}

# Main execution
main() {
    # Install packages
    install_packages

    # Wait for gateway
    wait_for_gateway

    # Get repository keys
    get_repository_keys

    # Setup publisher repository
    setup_publisher_repository

    # Create helper scripts
    create_helper_scripts

    # Create test script
    create_test_script

    log_success "Publisher setup complete!"
    log_info "Use 'publish-start' to begin and 'publish-complete' to commit changes"
    log_info "Run '/home/vagrant/test_publish.sh' to test publishing"
    log_info "Run 'publish-info' for repository information"
}

# Run main function
main
