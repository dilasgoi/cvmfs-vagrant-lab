#!/bin/bash
# Provisioning script for CVMFS client
# Sets up a client that can mount and access the CVMFS repository

set -e

# Load common functions
source /vagrant/provisioning/common/functions.sh

log_section "Setting up CVMFS client"

# Install CVMFS client
install_cvmfs_client() {
    log_info "Installing CVMFS client package"
    apt-get install -y cvmfs || die "Failed to install CVMFS client"
}

# Wait for infrastructure to be ready
wait_for_infrastructure() {
    log_info "Waiting for CVMFS infrastructure to be ready..."

    # Wait for Stratum-1 to be available
    local max_attempts=60
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if curl -fs "http://$STRATUM1_IP/cvmfs/$REPOSITORY_NAME/.cvmfspublished" > /dev/null 2>&1; then
            log_success "Infrastructure is ready!"
            return 0
        fi
        log_info "Waiting for infrastructure... ($attempt/$max_attempts)"
        sleep 5
        ((attempt++))
    done

    log_warning "Infrastructure may not be fully ready, continuing anyway..."
}

# Get repository public key
get_repository_key() {
    log_info "Getting repository public key"

    # Create keys directory structure
    mkdir -p "/etc/cvmfs/keys/$CVMFS_DOMAIN"

    # Try to get key from Stratum-0 first, fall back to Stratum-1
    if ! download_file \
        "http://$STRATUM0_IP/cvmfs/keys/${REPOSITORY_NAME}.pub" \
        "/etc/cvmfs/keys/$CVMFS_DOMAIN/${REPOSITORY_NAME}.pub" 3; then

        log_warning "Failed to get key from Stratum-0, trying Stratum-1..."
        download_file \
            "http://$STRATUM1_IP/cvmfs/keys/${REPOSITORY_NAME}.pub" \
            "/etc/cvmfs/keys/$CVMFS_DOMAIN/${REPOSITORY_NAME}.pub" \
            || die "Failed to download repository public key"
    fi
}

# Configure CVMFS client
configure_cvmfs_client() {
    log_info "Configuring CVMFS client"

    # Default configuration
    cat > /etc/cvmfs/default.local << EOF
CVMFS_REPOSITORIES=$REPOSITORY_NAME
CVMFS_HTTP_PROXY="http://$PROXY_IP:$PROXY_PORT"
CVMFS_QUOTA_LIMIT=2000
CVMFS_CACHE_BASE=/var/lib/cvmfs
CVMFS_SHARED_CACHE=no
EOF

    # Repository-specific configuration
    mkdir -p /etc/cvmfs/config.d
    cat > "/etc/cvmfs/config.d/${REPOSITORY_NAME}.conf" << EOF
CVMFS_SERVER_URL="http://$STRATUM1_IP/cvmfs/@fqrn@;http://$STRATUM0_IP/cvmfs/@fqrn@"
CVMFS_KEYS_DIR=/etc/cvmfs/keys/$CVMFS_DOMAIN
CVMFS_PUBLIC_KEY=/etc/cvmfs/keys/$CVMFS_DOMAIN/${REPOSITORY_NAME}.pub
EOF

    # Domain configuration
    mkdir -p /etc/cvmfs/domain.d
    cat > "/etc/cvmfs/domain.d/${CVMFS_DOMAIN}.local" << 'EOF'
CVMFS_USE_GEOAPI=no
EOF
}

# Setup autofs for automatic mounting
setup_autofs() {
    log_info "Setting up autofs for automatic mounting"

    # Create autofs configuration
    cat > /etc/auto.master.d/cvmfs.autofs << 'EOF'
/cvmfs /etc/auto.cvmfs
EOF

    # Restart autofs
    systemctl restart autofs
    wait_for_service autofs || log_warning "autofs may not be ready"
}

# Setup CVMFS
setup_cvmfs() {
    log_info "Running CVMFS setup"
    cvmfs_config setup || die "CVMFS setup failed"
}

# Test CVMFS access
test_cvmfs_access() {
    log_info "Testing CVMFS repository access"

    # Probe repository
    if cvmfs_config probe "$REPOSITORY_NAME" 2>&1; then
        log_success "Repository probe successful"
    else
        log_warning "Repository probe failed (repository may be empty)"
    fi

    # Try to access repository
    if ls "/cvmfs/$REPOSITORY_NAME" >/dev/null 2>&1; then
        log_success "Repository mounted successfully"
    else
        log_warning "Repository not yet accessible"
    fi
}

# Create test scripts
create_test_scripts() {
    log_info "Creating test scripts"

    # Comprehensive test script
    cat > /home/vagrant/test_cvmfs.sh << 'EOF'
#!/bin/bash
echo "============================================"
echo "         CVMFS Test Suite"
echo "============================================"
echo

echo "1. Configuration Status:"
echo "------------------------"
cvmfs_config stat -v software.lab.local 2>/dev/null || echo "Failed to get status"
echo

echo "2. Repository Contents:"
echo "----------------------"
if mountpoint -q /cvmfs/software.lab.local; then
    ls -la /cvmfs/software.lab.local/
else
    echo "Repository not mounted. Trying to access..."
    ls /cvmfs/software.lab.local/ >/dev/null 2>&1
    sleep 2
    ls -la /cvmfs/software.lab.local/ 2>/dev/null || echo "Failed to access repository"
fi
echo

echo "3. Test Files:"
echo "--------------"
if [ -f /cvmfs/software.lab.local/README.txt ]; then
    cat /cvmfs/software.lab.local/README.txt
else
    echo "README.txt not found!"
fi
echo

echo "4. Running Test Script:"
echo "----------------------"
if [ -x /cvmfs/software.lab.local/test/hello.sh ]; then
    /cvmfs/software.lab.local/test/hello.sh
else
    echo "Test script not found or not executable!"
fi
echo

echo "5. Binary Test:"
echo "---------------"
if [ -x /cvmfs/software.lab.local/bin/cvmfs-test ]; then
    /cvmfs/software.lab.local/bin/cvmfs-test
else
    echo "Binary not found!"
fi
echo

echo "6. Cache Information:"
echo "--------------------"
df -h /var/lib/cvmfs
echo

echo "7. Network Path:"
echo "----------------"
echo "Client -> Proxy ($PROXY_IP:3128) -> Stratum1 ($STRATUM1_IP) -> Gateway/Stratum0 ($GATEWAY_IP)"
echo "Publishing: Publisher ($PUBLISHER1_IP/$PUBLISHER2_IP) -> Gateway API ($GATEWAY_IP:4929)"
echo

echo "============================================"
echo "Test complete!"
echo "============================================"
EOF
    chmod +x /home/vagrant/test_cvmfs.sh

    # Quick access test
    cat > /home/vagrant/quick_test.sh << 'EOF'
#!/bin/bash
echo "Quick CVMFS Access Test"
echo "======================"
echo -n "Repository accessible: "
ls /cvmfs/software.lab.local >/dev/null 2>&1 && echo "YES" || echo "NO"
echo -n "README exists: "
[ -f /cvmfs/software.lab.local/README.txt ] && echo "YES" || echo "NO"
echo -n "Test script exists: "
[ -x /cvmfs/software.lab.local/test/hello.sh ] && echo "YES" || echo "NO"
echo
cvmfs_config stat software.lab.local | grep -E "VERSION|REVISION|CACHE"
EOF
    chmod +x /home/vagrant/quick_test.sh

    chown vagrant:vagrant /home/vagrant/*.sh
}

# Create helper commands
create_helper_commands() {
    log_info "Creating helper commands"

    # Repository check command
    cat > /usr/local/bin/cvmfs-check << 'EOF'
#!/bin/bash
echo "Checking CVMFS repository: software.lab.local"
echo "==========================================="
cvmfs_config probe software.lab.local
echo
echo "Repository statistics:"
cvmfs_config stat software.lab.local
EOF
    chmod +x /usr/local/bin/cvmfs-check

    # Cache management command
    cat > /usr/local/bin/cvmfs-cache-info << 'EOF'
#!/bin/bash
echo "CVMFS Cache Information"
echo "======================"
echo "Cache location: /var/lib/cvmfs"
echo
echo "Disk usage:"
df -h /var/lib/cvmfs
echo
echo "Cache contents:"
du -sh /var/lib/cvmfs/* 2>/dev/null | sort -h
echo
echo "Configuration:"
cvmfs_config showconfig software.lab.local | grep -E "CACHE|QUOTA"
EOF
    chmod +x /usr/local/bin/cvmfs-cache-info

    # Reload configuration command
    cat > /usr/local/bin/cvmfs-reload << 'EOF'
#!/bin/bash
echo "Reloading CVMFS configuration..."
cvmfs_config reload
echo "Remounting repository..."
cvmfs_config umount
cvmfs_config probe software.lab.local
echo "Done!"
EOF
    chmod +x /usr/local/bin/cvmfs-reload
}

# Create info file
create_client_info_file() {
    cat > /home/vagrant/cvmfs-client-info.txt << EOF
CVMFS Client Information
========================

Repository: $REPOSITORY_NAME
Mount Point: /cvmfs/$REPOSITORY_NAME
Cache Location: /var/lib/cvmfs
Cache Quota: 2000 MB

Configuration Files:
- Main config: /etc/cvmfs/default.local
- Repository config: /etc/cvmfs/config.d/${REPOSITORY_NAME}.conf
- Domain config: /etc/cvmfs/domain.d/${CVMFS_DOMAIN}.local

Network Configuration:
- Proxy: http://$PROXY_IP:$PROXY_PORT
- Primary server: http://$STRATUM1_IP/cvmfs/$REPOSITORY_NAME
- Backup server: http://$STRATUM0_IP/cvmfs/$REPOSITORY_NAME

Commands:
- Test access: /home/vagrant/test_cvmfs.sh
- Quick test: /home/vagrant/quick_test.sh
- Check repository: cvmfs-check
- Cache info: cvmfs-cache-info
- Reload config: cvmfs-reload
- Show config: cvmfs_config showconfig $REPOSITORY_NAME

Troubleshooting:
- Check mount: mountpoint /cvmfs/$REPOSITORY_NAME
- View logs: journalctl -u autofs
- Probe repo: cvmfs_config probe $REPOSITORY_NAME
- Clear cache: sudo cvmfs_config wipecache
EOF
    chown vagrant:vagrant /home/vagrant/cvmfs-client-info.txt
}

# Main execution
main() {
    # Install CVMFS client
    install_cvmfs_client

    # Wait for infrastructure
    wait_for_infrastructure

    # Get repository key
    get_repository_key

    # Configure CVMFS client
    configure_cvmfs_client

    # Setup autofs
    setup_autofs

    # Setup CVMFS
    setup_cvmfs

    # Test access
    test_cvmfs_access

    # Create test scripts
    create_test_scripts

    # Create helper commands
    create_helper_commands

    # Create info file
    create_client_info_file

    log_success "Client setup complete!"
    log_info "Run '/home/vagrant/test_cvmfs.sh' for full test"
    log_info "Run 'cvmfs-check' to verify repository access"
    log_info "See /home/vagrant/cvmfs-client-info.txt for details"
}

# Run main function
main
