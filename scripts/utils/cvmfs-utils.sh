#!/bin/bash
# CVMFS utility functions
# Shared utilities for CVMFS operations

# Check if repository exists
repository_exists() {
    local repo_name=$1
    cvmfs_server list 2>/dev/null | grep -q "^$repo_name "
}

# Check if transaction is open
transaction_is_open() {
    local repo_name=$1
    cvmfs_server list 2>/dev/null | grep "^$repo_name " | grep -q "transaction"
}

# Safe transaction start
safe_start_transaction() {
    local repo_name=$1

    if transaction_is_open "$repo_name"; then
        log_warning "Transaction already open for $repo_name"
        return 1
    fi

    cvmfs_server transaction "$repo_name"
}

# Safe publish
safe_publish() {
    local repo_name=$1

    if ! transaction_is_open "$repo_name"; then
        log_warning "No transaction open for $repo_name"
        return 1
    fi

    cvmfs_server publish "$repo_name"
}

# Get repository revision
get_repository_revision() {
    local repo_name=$1
    local repo_url=${2:-"http://localhost/cvmfs/$repo_name"}

    curl -s "$repo_url/.cvmfspublished" 2>/dev/null | head -1 | cut -d'|' -f2
}

# Check if gateway is running
is_gateway_running() {
    systemctl is-active --quiet cvmfs-gateway
}

# Check if Apache is serving repository
is_repository_accessible() {
    local repo_name=$1
    local repo_url=${2:-"http://localhost/cvmfs/$repo_name"}

    curl -s -o /dev/null -w "%{http_code}" "$repo_url/.cvmfspublished" | grep -q "200"
}

# Wait for repository to be accessible
wait_for_repository() {
    local repo_name=$1
    local repo_url=${2:-"http://localhost/cvmfs/$repo_name"}
    local max_attempts=${3:-30}
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if is_repository_accessible "$repo_name" "$repo_url"; then
            return 0
        fi
        sleep 2
        ((attempt++))
    done

    return 1
}

# Create repository snapshot info
create_snapshot_info() {
    local repo_name=$1
    local info_file="/var/log/cvmfs/${repo_name}_snapshot.info"

    cat > "$info_file" << EOF
Repository: $repo_name
Timestamp: $(date)
Revision: $(get_repository_revision "$repo_name")
Size: $(du -sh "/srv/cvmfs/$repo_name" 2>/dev/null | cut -f1)
Files: $(find "/srv/cvmfs/$repo_name" -type f 2>/dev/null | wc -l)
EOF
}

# Verify repository integrity
verify_repository() {
    local repo_name=$1

    log_info "Verifying repository $repo_name..."

    # Check if repository exists
    if ! repository_exists "$repo_name"; then
        log_error "Repository $repo_name does not exist"
        return 1
    fi

    # Run CVMFS check
    if cvmfs_server check "$repo_name" >/dev/null 2>&1; then
        log_success "Repository $repo_name is healthy"
        return 0
    else
        log_error "Repository $repo_name has errors"
        return 1
    fi
}

# Get repository statistics
get_repository_stats() {
    local repo_name=$1

    cvmfs_server info "$repo_name" 2>/dev/null | grep -E "revision|modified|size"
}

# Export functions for use in other scripts
export -f repository_exists
export -f transaction_is_open
export -f safe_start_transaction
export -f safe_publish
export -f get_repository_revision
export -f is_gateway_running
export -f is_repository_accessible
export -f wait_for_repository
export -f create_snapshot_info
export -f verify_repository
export -f get_repository_stats
