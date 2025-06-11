#!/bin/bash
# Provisioning script for combined Gateway + Stratum-0 server
# This sets up both the authoritative repository and the gateway service

set -e

# Load common functions
source /vagrant/provisioning/common/functions.sh

log_section "Setting up Combined Gateway + Stratum-0 server"

# Install required packages
install_packages() {
    log_info "Installing CVMFS server and gateway packages"
    apt-get install -y \
        cvmfs \
        cvmfs-server \
        cvmfs-gateway \
        apache2 \
        || die "Failed to install CVMFS packages"
}

# Configure Apache for CVMFS
configure_apache() {
    log_info "Configuring Apache for CVMFS"

    # Create Apache configuration for CVMFS
    cat > /etc/apache2/conf-available/cvmfs.conf << 'EOF'
Alias /cvmfs /srv/cvmfs

<Directory "/srv/cvmfs">
    Options -MultiViews +FollowSymLinks -Indexes
    AllowOverride None
    Require all granted
    EnableMMAP Off
    EnableSendFile Off

    <FilesMatch "^\.cvmfs">
        ForceType application/x-cvmfs
    </FilesMatch>

    Header set Cache-Control "max-age=86400"

    <FilesMatch "^\.cvmfspublished$|^\.cvmfswhitelist$">
        ForceType application/x-cvmfs
        Header set Cache-Control "max-age=60"
    </FilesMatch>
</Directory>
EOF

    # Enable required modules and configuration
    a2enmod headers
    a2enconf cvmfs

    # Restart Apache
    systemctl restart apache2
    wait_for_service apache2 || die "Apache failed to start"
}

# Create and initialize the repository
create_repository() {
    log_info "Creating repository: $REPOSITORY_NAME"

    # CRITICAL: Stop the gateway before creating the repository to avoid conflicts
    log_warning "Ensuring gateway is stopped during repository creation..."
    systemctl stop cvmfs-gateway 2>/dev/null || true

    # Create repository as a Stratum-0 (NOT with -g flag initially)
    log_info "Creating Stratum-0 repository..."
    cvmfs_server mkfs -o "$REPO_OWNER" "$REPOSITORY_NAME" \
        || die "Failed to create repository"

    # Add initial content
    log_info "Adding initial content to repository..."
    cvmfs_server transaction "$REPOSITORY_NAME" \
        || die "Failed to start transaction"

    # Create directory structure
    mkdir -p "/cvmfs/$REPOSITORY_NAME"/{bin,lib,test,doc,data}

    # Create README
    cat > "/cvmfs/$REPOSITORY_NAME/README.txt" << EOF
Welcome to CVMFS $REPOSITORY_NAME repository
Repository created on $(date)
This repository is managed via gateway
EOF

    # Create info file
    cat > "/cvmfs/$REPOSITORY_NAME/doc/info.txt" << EOF
Repository: $REPOSITORY_NAME
Created: $(date)
Type: Gateway-managed Stratum-0
Gateway URL: http://$GATEWAY_IP:$GATEWAY_PORT/api/v1
EOF

    # Create gateway info
    echo "This repository is managed via gateway" > "/cvmfs/$REPOSITORY_NAME/doc/gateway.txt"

    # Create test script
    cat > "/cvmfs/$REPOSITORY_NAME/test/hello.sh" << 'EOF'
#!/bin/bash
echo "Hello from CVMFS!"
echo "Running on: $(hostname)"
echo "Current date: $(date)"
echo "Repository: software.lab.local"
EOF
    chmod +x "/cvmfs/$REPOSITORY_NAME/test/hello.sh"

    # Create sample binary
    cat > "/cvmfs/$REPOSITORY_NAME/bin/cvmfs-test" << 'EOF'
#!/bin/bash
echo "CVMFS Test Utility v1.0"
echo "======================="
echo "Repository: software.lab.local"
echo "Location: /cvmfs/software.lab.local"
echo "Files in repository:"
find /cvmfs/software.lab.local -type f | head -20
EOF
    chmod +x "/cvmfs/$REPOSITORY_NAME/bin/cvmfs-test"

    # Publish initial content
    log_info "Publishing initial content..."
    cvmfs_server publish "$REPOSITORY_NAME" \
        || die "Failed to publish repository"
}

# Setup repository keys
setup_keys() {
    log_info "Setting up repository keys"

    # Make public key available via HTTP
    mkdir -p /srv/cvmfs/keys
    cp "/etc/cvmfs/keys/${REPOSITORY_NAME}.pub" /srv/cvmfs/keys/
    cp "/etc/cvmfs/keys/${REPOSITORY_NAME}.crt" /srv/cvmfs/keys/

    # Create .cvmfs_master_replica file to allow Stratum-1 replication
    touch "/srv/cvmfs/$REPOSITORY_NAME/.cvmfs_master_replica"

    # Generate API key for gateway
    log_info "Generating gateway API key..."
    KEY_ID="gateway_key"
    SECRET=$(openssl rand -hex 32)

    cat > "/etc/cvmfs/keys/${REPOSITORY_NAME}.gw" << EOF
plain_text $KEY_ID $SECRET
EOF
    chmod 600 "/etc/cvmfs/keys/${REPOSITORY_NAME}.gw"

    # Make gateway key available for publishers via Apache
    cp "/etc/cvmfs/keys/${REPOSITORY_NAME}.gw" /srv/cvmfs/keys/
    chmod 644 "/srv/cvmfs/keys/${REPOSITORY_NAME}.gw"
}

# Configure the gateway service
configure_gateway() {
    log_info "Configuring Repository Gateway"

    # Create gateway configuration directory
    mkdir -p /etc/cvmfs/gateway

    # Create repository configuration for gateway
    cat > /etc/cvmfs/gateway/repo.json << EOF
{
  "version": 2,
  "repos": ["$REPOSITORY_NAME"]
}
EOF

    # Gateway runtime settings
    cat > /etc/cvmfs/gateway/user.json << EOF
{
  "max_lease_time": $GATEWAY_MAX_LEASE_TIME,
  "port": $GATEWAY_PORT,
  "num_receivers": $GATEWAY_NUM_RECEIVERS,
  "receiver_commit_timeout": $GATEWAY_RECEIVER_TIMEOUT,
  "fe_tcp_port_begin": $GATEWAY_FE_TCP_PORT_BEGIN,
  "fe_tcp_port_end": $GATEWAY_FE_TCP_PORT_END
}
EOF

    # Enable gateway support in repository configuration
    echo "CVMFS_GATEWAY_SERVICES=http://$GATEWAY_IP:$GATEWAY_PORT/api/v1" >> \
        "/etc/cvmfs/repositories.d/$REPOSITORY_NAME/server.conf"
}

# Create helper scripts
create_helper_scripts() {
    log_info "Creating helper scripts"

    # Gateway status script
    cat > /usr/local/bin/gateway-status << 'EOF'
#!/bin/bash
echo "=== Gateway Status ==="
systemctl is-active --quiet cvmfs-gateway && echo "Gateway: Running" || echo "Gateway: Failed"
systemctl is-active --quiet apache2 && echo "Apache: Running" || echo "Apache: Failed"
echo
echo "=== Gateway API Check ==="
curl -s http://localhost:4929/api/v1/repos || echo "Gateway API not responding"
echo
echo "=== Repository Status ==="
cvmfs_server list
echo
echo "=== Apache Status ==="
systemctl status apache2 | grep -E "Active:"
EOF
    chmod +x /usr/local/bin/gateway-status

    # Local publish script (requires stopping gateway)
    cat > /usr/local/bin/local-publish << 'EOF'
#!/bin/bash
# Script for local publishing (must stop gateway first)
echo "WARNING: This will stop the gateway service for local publishing"
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    systemctl stop cvmfs-gateway
    echo "Gateway stopped. You can now use cvmfs_server transaction/publish"
    echo "Remember to start gateway again: systemctl start cvmfs-gateway"
fi
EOF
    chmod +x /usr/local/bin/local-publish

    # Create info file with important URLs and details
    cat > /home/vagrant/cvmfs-gateway-info.txt << EOF
CVMFS Gateway + Stratum-0 Information
=====================================

Repository Name: $REPOSITORY_NAME
Repository URL: http://$GATEWAY_IP/cvmfs/$REPOSITORY_NAME
Gateway API: http://$GATEWAY_IP:$GATEWAY_PORT/api/v1
Public Key: http://$GATEWAY_IP/cvmfs/keys/${REPOSITORY_NAME}.pub
Gateway Key: http://$GATEWAY_IP/cvmfs/keys/${REPOSITORY_NAME}.gw

Important Commands:
- Check status: gateway-status
- Local publish: local-publish (stops gateway temporarily)
- Gateway logs: journalctl -u cvmfs-gateway -f
- Apache logs: tail -f /var/log/apache2/access.log

Publisher Setup:
Publishers should run:
  cvmfs_server mkfs -w http://$GATEWAY_IP/cvmfs/$REPOSITORY_NAME \\
    -u gw,/srv/cvmfs/$REPOSITORY_NAME/data/txn,http://$GATEWAY_IP:$GATEWAY_PORT/api/v1 \\
    -k /path/to/keys -o <username> $REPOSITORY_NAME
EOF
    chown vagrant:vagrant /home/vagrant/cvmfs-gateway-info.txt
}

# Main execution
main() {
    # Read settings from YAML files
    GATEWAY_MAX_LEASE_TIME=${GATEWAY_MAX_LEASE_TIME:-7200}
    GATEWAY_NUM_RECEIVERS=${GATEWAY_NUM_RECEIVERS:-2}
    GATEWAY_RECEIVER_TIMEOUT=${GATEWAY_RECEIVER_TIMEOUT:-7200}
    GATEWAY_FE_TCP_PORT_BEGIN=${GATEWAY_FE_TCP_PORT_BEGIN:-4930}
    GATEWAY_FE_TCP_PORT_END=${GATEWAY_FE_TCP_PORT_END:-4950}

    # Install packages
    install_packages

    # Configure Apache
    configure_apache

    # Create repository
    create_repository

    # Setup keys
    setup_keys

    # Configure gateway
    configure_gateway

    # Start gateway service
    log_info "Starting gateway service..."
    systemctl enable cvmfs-gateway
    systemctl start cvmfs-gateway

    # Verify services are running
    sleep 5
    wait_for_service cvmfs-gateway || log_warning "Gateway service may not be ready"
    wait_for_port localhost "$GATEWAY_PORT" || log_warning "Gateway API port not responding"

    # Create helper scripts
    create_helper_scripts

    log_success "Combined Gateway + Stratum-0 setup complete!"
    log_info "See /home/vagrant/cvmfs-gateway-info.txt for details"
    log_info "Run 'gateway-status' to check service health"
}

# Run main function
main
