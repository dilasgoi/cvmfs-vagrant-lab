#!/bin/bash
# Base provisioning script for all CVMFS nodes
# This script runs on every node before role-specific provisioning

set -e

# Load common functions
source /vagrant/provisioning/common/functions.sh

log_section "Starting base provisioning"
log_info "Node: $NODE_NAME ($NODE_ROLE)"
log_info "IP: $NODE_IP"

# Fix potential SSH issues
configure_ssh

# Update system. Disabled by default as it is time consuming.
# update_system

# Install base packages
install_base_packages

# Add CVMFS repository
add_cvmfs_repository

# Update hosts file with all nodes
configure_hosts_file

# Setup environment variables
setup_environment_variables

# Create info file for vagrant user
create_info_file

log_section "Base provisioning complete"
