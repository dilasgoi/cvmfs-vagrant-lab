#!/bin/bash
# Provisioning script for CVMFS Stratum-1 replica server
# Sets up a mirror of the Stratum-0 repository

set -e

# Load common functions
source /vagrant/provisioning/common/functions.sh

log_section "Setting up Stratum-1 replica server"

# Install required packages
install_packages() {
    log_info "Installing CVMFS server and Apache packages"
    apt-get install -y \
        cvmfs \
        cvmfs-server \
        apache2 \
        libapache2-mod-wsgi-py3 \
        || die "Failed to install packages"
}

# Configure Apache for CVMFS
configure_apache() {
    log_info "Configuring Apache for CVMFS"

    # Create Apache configuration
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

    # Enable required modules
    a2enmod headers wsgi
    a2enconf cvmfs

    # Restart Apache
    systemctl restart apache2
    wait_for_service apache2 || die "Apache failed to start"
}

# Wait for Stratum-0 to be ready
wait_for_stratum0() {
    log_info "Waiting for Stratum-0 to be ready..."
    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if curl -fs "http://$STRATUM0_IP/cvmfs/$REPOSITORY_NAME/.cvmfspublished" > /dev/null; then
            log_success "Stratum-0 is ready!"
            return 0
        fi
        log_info "Waiting for Stratum-0... (attempt $attempt/$max_attempts)"
        sleep 5
        ((attempt++))
    done

    log_warning "Stratum-0 may not be fully ready, continuing anyway..."
}

# Get repository public key
get_repository_key() {
    log_info "Getting repository public key"
    mkdir -p /etc/cvmfs/keys

    download_file \
        "http://$STRATUM0_IP/cvmfs/keys/${REPOSITORY_NAME}.pub" \
        "/etc/cvmfs/keys/${REPOSITORY_NAME}.pub" \
        || die "Failed to download repository public key"
}

# Configure Stratum-1 specific settings
configure_stratum1() {
    log_info "Configuring Stratum-1 settings"

    # Create domain configuration
    mkdir -p /etc/cvmfs/domain.d
    cat > "/etc/cvmfs/domain.d/${CVMFS_DOMAIN}.local" << EOF
CVMFS_USE_GEOAPI=no
CVMFS_SERVER_URL="http://$STRATUM0_IP/cvmfs/@fqrn@"
CVMFS_KEYS_DIR=/etc/cvmfs/keys
EOF

    # Disable GeoIP database (not needed for local setup)
    cat > /etc/cvmfs/server.local << 'EOF'
CVMFS_GEO_DB_FILE=NONE
EOF
}

# Add repository replica
add_replica() {
    log_info "Adding replica for $REPOSITORY_NAME"

    cvmfs_server add-replica \
        -o "$REPO_OWNER" \
        "http://$STRATUM0_IP/cvmfs/$REPOSITORY_NAME" \
        "/etc/cvmfs/keys/${REPOSITORY_NAME}.pub" \
        || die "Failed to add replica"
}

# Create initial snapshot
create_initial_snapshot() {
    log_info "Creating initial snapshot"

    # Try to create snapshot, but don't fail if repository is empty
    if cvmfs_server snapshot "$REPOSITORY_NAME" 2>&1; then
        log_success "Initial snapshot created"
    else
        log_warning "Initial snapshot failed (repository may be empty or still initializing)"
    fi
}

# Setup automatic snapshots
setup_automatic_snapshots() {
    log_info "Setting up automatic snapshots"

    # Create cron job for regular snapshots
    cat > /etc/cron.d/cvmfs-stratum1-snapshots << 'EOF'
# Create snapshots every 5 minutes
*/5 * * * * root output=$(/usr/bin/cvmfs_server snapshot -a -i 2>&1) || echo "$output"
EOF

    # Create log directory
    mkdir -p /var/log/cvmfs
    touch /var/log/cvmfs/snapshots.log
    chown root:root /var/log/cvmfs/snapshots.log
}

# Create helper scripts
create_helper_scripts() {
    log_info "Creating helper scripts"

    # Status script
    cat > /usr/local/bin/cvmfs-status << EOF
#!/bin/bash
echo "=== Stratum-1 Status ==="
cvmfs_server info $REPOSITORY_NAME 2>/dev/null || echo "Repository info not available"
echo
echo "Last snapshot:"
ls -la /srv/cvmfs/$REPOSITORY_NAME/.cvmfs*published 2>/dev/null | tail -1 || echo "No snapshot yet"
echo
echo "Sync status:"
tail -5 /var/log/cvmfs/snapshots.log 2>/dev/null || echo "No snapshot log yet"
echo
echo "Apache status:"
systemctl is-active apache2 && echo "Apache: Active" || echo "Apache: Inactive"
EOF
    chmod +x /usr/local/bin/cvmfs-status

    # Manual snapshot script
    cat > /usr/local/bin/cvmfs-snapshot << EOF
#!/bin/bash
echo "Creating manual snapshot of $REPOSITORY_NAME..."
cvmfs_server snapshot $REPOSITORY_NAME
EOF
    chmod +x /usr/local/bin/cvmfs-snapshot
}

# Create info file
create_info_file() {
    cat > /home/vagrant/cvmfs-stratum1-info.txt << EOF
CVMFS Stratum-1 Replica Information
===================================

Repository: $REPOSITORY_NAME
Replica URL: http://$NODE_IP/cvmfs/$REPOSITORY_NAME
Upstream Stratum-0: http://$STRATUM0_IP/cvmfs/$REPOSITORY_NAME

Automatic Snapshots: Every 5 minutes via cron
Snapshot Log: /var/log/cvmfs/snapshots.log

Commands:
- Check status: cvmfs-status
- Manual snapshot: cvmfs-snapshot
- View logs: tail -f /var/log/cvmfs/snapshots.log
- Apache logs: tail -f /var/log/apache2/access.log

Repository Information:
- cvmfs_server info $REPOSITORY_NAME
- cvmfs_server list
EOF
    chown vagrant:vagrant /home/vagrant/cvmfs-stratum1-info.txt
}

# Main execution
main() {
    # Install packages
    install_packages

    # Configure Apache
    configure_apache

    # Wait for Stratum-0
    wait_for_stratum0

    # Get repository key
    get_repository_key

    # Configure Stratum-1
    configure_stratum1

    # Add replica
    add_replica

    # Create initial snapshot
    create_initial_snapshot

    # Setup automatic snapshots
    setup_automatic_snapshots

    # Create helper scripts
    create_helper_scripts

    # Create info file
    create_info_file

    log_success "Stratum-1 setup complete!"
    log_info "Replica URL: http://$NODE_IP/cvmfs/$REPOSITORY_NAME"
    log_info "Run 'cvmfs-status' to check replica status"
    log_info "Automatic snapshots configured to run every 5 minutes"
}

# Run main function
main
