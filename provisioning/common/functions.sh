#!/bin/bash
# Common functions for CVMFS provisioning
# These functions are used across all provisioning scripts

# Color codes for output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_section() {
    echo
    echo -e "${PURPLE}=== $1 ===${NC}"
    echo
}

# Error handling
die() {
    log_error "$1"
    exit 1
}

# SSH configuration
configure_ssh() {
    log_info "Configuring SSH for faster connections"
    if ! grep -q "^UseDNS no" /etc/ssh/sshd_config; then
        echo "UseDNS no" >> /etc/ssh/sshd_config
        systemctl restart sshd
    fi
}

# System update
update_system() {
    log_info "Updating system packages"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update || die "Failed to update package list"
}

# Install base packages that all nodes need
install_base_packages() {
    log_info "Installing base packages"
    apt-get install -y \
        curl \
        wget \
        vim \
        net-tools \
        software-properties-common \
        || die "Failed to install base packages"
}

# Add CVMFS repository
add_cvmfs_repository() {
    log_info "Adding CVMFS repository"
    if [ ! -f /etc/apt/sources.list.d/cvmfs.list ]; then
        wget -q https://ecsft.cern.ch/dist/cvmfs/cvmfs-release/cvmfs-release-latest_all.deb \
            || die "Failed to download CVMFS repository package"
        dpkg -i cvmfs-release-latest_all.deb || die "Failed to install CVMFS repository"
        apt-get update
        rm -f cvmfs-release-latest_all.deb
    else
        log_info "CVMFS repository already configured"
    fi
}

# Configure hosts file with all CVMFS nodes
configure_hosts_file() {
    log_info "Configuring /etc/hosts with CVMFS infrastructure nodes"

    # Remove any existing CVMFS entries
    sed -i '/# CVMFS Infrastructure/,/# End CVMFS Infrastructure/d' /etc/hosts

    # Add all nodes
    cat >> /etc/hosts << EOF

# CVMFS Infrastructure
$GATEWAY_IP cvmfs-gateway-stratum0 gateway stratum0
$PUBLISHER1_IP cvmfs-publisher1 publisher1
$PUBLISHER2_IP cvmfs-publisher2 publisher2
$STRATUM1_IP cvmfs-stratum1 stratum1
$PROXY_IP squid-proxy proxy
$CLIENT_IP cvmfs-client client
# End CVMFS Infrastructure
EOF
}

# Wait for a service to become active
wait_for_service() {
    local service=$1
    local max_attempts=${2:-30}
    local attempt=0

    log_info "Waiting for $service to become active"
    while [ $attempt -lt $max_attempts ]; do
        if systemctl is-active --quiet "$service"; then
            log_success "$service is active"
            return 0
        fi
        sleep 1
        ((attempt++))
    done

    log_error "$service failed to start within $max_attempts seconds"
    systemctl status "$service" || true
    return 1
}

# Wait for a network port to become available
wait_for_port() {
    local host=$1
    local port=$2
    local max_attempts=${3:-60}
    local attempt=0

    log_info "Waiting for $host:$port to become available"
    while [ $attempt -lt $max_attempts ]; do
        if timeout 1 bash -c "cat < /dev/null > /dev/tcp/$host/$port" 2>/dev/null; then
            log_success "$host:$port is available"
            return 0
        fi
        sleep 1
        ((attempt++))
    done

    log_error "$host:$port not available after $max_attempts attempts"
    return 1
}

# Download file with retry logic
download_file() {
    local url=$1
    local destination=$2
    local max_attempts=${3:-3}
    local attempt=1

    log_info "Downloading $url to $destination"
    while [ $attempt -le $max_attempts ]; do
        if wget -q -O "$destination" "$url"; then
            log_success "Downloaded successfully"
            return 0
        fi
        log_warning "Download attempt $attempt/$max_attempts failed"
        ((attempt++))
        [ $attempt -le $max_attempts ] && sleep 2
    done

    log_error "Failed to download $url after $max_attempts attempts"
    return 1
}

# Create CVMFS info file for vagrant user
create_info_file() {
    local info_file="/home/vagrant/cvmfs-info.txt"
    log_info "Creating CVMFS info file"

    cat > "$info_file" << EOF
CVMFS Infrastructure Information
================================
Generated: $(date)
Node: $NODE_NAME
Role: $NODE_ROLE
IP Address: $NODE_IP

Repository Configuration:
- Name: $REPOSITORY_NAME
- Domain: $CVMFS_DOMAIN
- Owner: $REPO_OWNER

Network Endpoints:
- Gateway API: http://$GATEWAY_IP:$GATEWAY_PORT/api/v1
- Stratum-0: http://$STRATUM0_IP/cvmfs/$REPOSITORY_NAME
- Stratum-1: http://$STRATUM1_IP/cvmfs/$REPOSITORY_NAME
- Proxy: http://$PROXY_IP:$PROXY_PORT

Node IPs:
- Gateway/Stratum-0: $GATEWAY_IP
- Publisher 1: $PUBLISHER1_IP
- Publisher 2: $PUBLISHER2_IP
- Stratum-1: $STRATUM1_IP
- Proxy: $PROXY_IP
- Client: $CLIENT_IP

Useful Commands:
- Service status: systemctl status <service>
- CVMFS logs: journalctl -u cvmfs-gateway -f (on gateway)
- Apache logs: tail -f /var/log/apache2/access.log
- Repository list: cvmfs_server list
- Repository info: cvmfs_server info $REPOSITORY_NAME
EOF

    chown vagrant:vagrant "$info_file"
}

# Setup environment variables
setup_environment_variables() {
    log_info "Setting up CVMFS environment variables"
    cat > /etc/profile.d/cvmfs.sh << EOF
# CVMFS Environment Variables
export CVMFS_DOMAIN="$CVMFS_DOMAIN"
export CVMFS_REPOSITORY="$REPOSITORY_NAME"
export CVMFS_GATEWAY_URL="http://$GATEWAY_IP:$GATEWAY_PORT/api/v1"
export CVMFS_STRATUM0_URL="http://$STRATUM0_IP/cvmfs/$REPOSITORY_NAME"
export CVMFS_STRATUM1_URL="http://$STRATUM1_IP/cvmfs/$REPOSITORY_NAME"
export CVMFS_PROXY_URL="http://$PROXY_IP:$PROXY_PORT"
EOF
    chmod +x /etc/profile.d/cvmfs.sh
}
