#!/bin/bash
# Provisioning script for Squid proxy
# Sets up a caching proxy optimized for CVMFS

set -e

# Load common functions
source /vagrant/provisioning/common/functions.sh

log_section "Setting up Squid proxy"

# Install Squid
install_squid() {
    log_info "Installing Squid proxy"
    apt-get install -y squid || die "Failed to install Squid"
}

# Configure Squid for CVMFS
configure_squid() {
    log_info "Configuring Squid for CVMFS"

    # Stop Squid to prevent auto-start issues
    systemctl stop squid || true
    systemctl disable squid

    # Backup original configuration
    if [ -f /etc/squid/squid.conf ] && [ ! -f /etc/squid/squid.conf.bak ]; then
        cp /etc/squid/squid.conf /etc/squid/squid.conf.bak
    fi

    # Create CVMFS-optimized configuration
    cat > /etc/squid/squid.conf << 'EOF'
# CVMFS-optimized Squid configuration

# Port
http_port 3128

# Cache settings optimized for CVMFS
cache_mem 256 MB
maximum_object_size 1024 MB
cache_dir ufs /var/spool/squid 4000 16 256

# Access control lists
acl localnet src 192.168.58.0/24
acl localnet src 10.0.0.0/8
acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 443
acl CONNECT method CONNECT

# Access rules
http_access allow localnet
http_access allow localhost
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access deny all

# CVMFS-specific refresh patterns
refresh_pattern ^/cvmfs/[^/]*/\.cvmfspublished$ 0 0% 0
refresh_pattern ^/cvmfs/[^/]*/\.cvmfswhitelist$ 0 0% 0
refresh_pattern ^/cvmfs/[^/]*/data/ 0 86400 86400
refresh_pattern ^/cvmfs/.* 0 86400 86400

# Performance optimizations
collapsed_forwarding on
maximum_object_size_in_memory 128 KB

# Logging
access_log /var/log/squid/access.log
cache_log /var/log/squid/cache.log
cache_store_log none

# Leave coredumps in the first cache dir
coredump_dir /var/spool/squid
EOF
}

# Initialize Squid cache
initialize_cache() {
    log_info "Initializing Squid cache directories"

    # Clean up any existing cache
    rm -rf /var/spool/squid/*

    # Create cache directories with proper permissions
    squid -N -z || die "Failed to initialize Squid cache"
}

# Start Squid service
start_squid() {
    log_info "Starting Squid service"

    # Enable and start Squid
    systemctl enable squid
    systemctl start squid

    # Wait for Squid to be ready
    local max_attempts=10
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if systemctl is-active --quiet squid; then
            log_success "Squid is running!"
            break
        fi
        log_info "Waiting for Squid to start... ($attempt/$max_attempts)"
        sleep 2
        ((attempt++))
    done

    # Verify Squid is running
    if ! systemctl is-active --quiet squid; then
        log_error "Squid failed to start. Checking logs..."
        journalctl -xeu squid.service | tail -20
        die "Squid service failed to start"
    fi

    # Wait for port to be available
    wait_for_port localhost "$PROXY_PORT" || log_warning "Squid port not responding"
}

# Create monitoring scripts
create_monitoring_scripts() {
    log_info "Creating monitoring scripts"

    # Squid statistics script
    cat > /usr/local/bin/squid-stats << 'EOF'
#!/bin/bash
echo "=== Squid Cache Statistics ==="
squidclient -h localhost cache_object://localhost/info 2>/dev/null || echo "Squid not responding yet"
echo
echo "=== Cache Usage ==="
df -h /var/spool/squid
echo
echo "=== Recent requests ==="
if [ -f /var/log/squid/access.log ]; then
    echo "Last 20 requests:"
    tail -20 /var/log/squid/access.log
else
    echo "No access log yet"
fi
EOF
    chmod +x /usr/local/bin/squid-stats

    # Cache management script
    cat > /usr/local/bin/squid-cache-clear << 'EOF'
#!/bin/bash
echo "Clearing Squid cache..."
systemctl stop squid
rm -rf /var/spool/squid/*
squid -N -z
systemctl start squid
echo "Cache cleared and Squid restarted"
EOF
    chmod +x /usr/local/bin/squid-cache-clear
}

# Create info file
create_info_file() {
    cat > /home/vagrant/squid-proxy-info.txt << EOF
Squid Proxy Information
=======================

Proxy URL: http://$NODE_IP:$PROXY_PORT
Cache Size: 4000 MB
Memory Cache: 256 MB

Access Control:
- Allowed networks: 192.168.58.0/24, 10.0.0.0/8
- Allowed ports: 80, 443

CVMFS Optimization:
- No caching for .cvmfspublished and .cvmfswhitelist
- Extended caching for /data/ paths
- Collapsed forwarding enabled

Commands:
- View statistics: squid-stats
- Clear cache: squid-cache-clear
- View logs: tail -f /var/log/squid/access.log
- Service status: systemctl status squid

Testing:
curl -x http://$NODE_IP:$PROXY_PORT http://example.com
EOF
    chown vagrant:vagrant /home/vagrant/squid-proxy-info.txt
}

# Verify Squid is working
verify_squid() {
    log_info "Verifying Squid proxy"

    # Check if port is listening
    if netstat -tlnp 2>/dev/null | grep -q ":$PROXY_PORT.*squid"; then
        log_success "Squid is listening on port $PROXY_PORT"
    else
        log_warning "Squid may not be listening on expected port"
    fi

    # Test proxy functionality
    if curl -s -x "http://localhost:$PROXY_PORT" -I http://example.com >/dev/null 2>&1; then
        log_success "Proxy is functioning correctly"
    else
        log_warning "Proxy test failed"
    fi
}

# Main execution
main() {
    # Install Squid
    install_squid

    # Configure Squid
    configure_squid

    # Initialize cache
    initialize_cache

    # Start Squid
    start_squid

    # Create monitoring scripts
    create_monitoring_scripts

    # Create info file
    create_info_file

    # Verify Squid
    verify_squid

    log_success "Squid proxy setup complete!"
    log_info "Proxy running at: http://$NODE_IP:$PROXY_PORT"
    log_info "Run 'squid-stats' to view cache statistics"
}

# Run main function
main
