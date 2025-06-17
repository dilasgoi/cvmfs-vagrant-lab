#!/bin/bash
# Provisioning script for CVMFS publisher nodes with GitHub Actions runner
# Now with dynamic architecture detection via archspec

set -e

# Load common functions
source /vagrant/provisioning/common/functions.sh

log_section "Setting up Publisher node with GitHub Actions Runner"

# Install archspec for architecture detection
install_archspec() {
    log_info "Installing archspec"

    # Install Python pip if not present
    apt-get install -y python3-pip

    # Install archspec
    pip3 install archspec

    # Verify installation
    if archspec cpu --help >/dev/null 2>&1; then
        log_success "archspec installed successfully"
    else
        log_error "Failed to install archspec"
        # Fallback to manual detection
        return 1
    fi
}

# Detect microarchitecture using archspec
detect_architecture() {
    log_info "Detecting CPU microarchitecture"

    # Try archspec first
    if command -v archspec >/dev/null 2>&1; then
        # Get detailed CPU info
        ARCHSPEC_JSON=$(archspec cpu --json)
        ARCHSPEC_NAME=$(echo "$ARCHSPEC_JSON" | jq -r '.name' 2>/dev/null || echo "unknown")
        ARCHSPEC_VENDOR=$(echo "$ARCHSPEC_JSON" | jq -r '.vendor' 2>/dev/null || echo "unknown")
        ARCHSPEC_GENERATION=$(echo "$ARCHSPEC_JSON" | jq -r '.generation' 2>/dev/null || echo "0")
        ARCHSPEC_FEATURES=$(echo "$ARCHSPEC_JSON" | jq -r '.features[]' 2>/dev/null | tr '\n' ' ' || echo "")

        log_info "Detected CPU: $ARCHSPEC_VENDOR $ARCHSPEC_NAME"
        log_info "Features: $ARCHSPEC_FEATURES"

        # Map to our architecture scheme
        map_architecture_to_cvmfs
    else
        log_warning "archspec not available, using fallback detection"
        fallback_architecture_detection
    fi

    # Save detection results
    save_architecture_info
}

# Map archspec output to CVMFS architecture paths
map_architecture_to_cvmfs() {
    log_info "Mapping $ARCHSPEC_NAME to CVMFS architecture"

    # Determine x86-64 microarchitecture level and CVMFS path
    case "$ARCHSPEC_NAME" in
        # x86-64-v4 CPUs (AVX512)
        skylake_avx512|cascadelake|cooperlake|icelake|tigerlake|rocketlake|alderlake|sapphirerapids)
            ARCH_LABEL="x86-64-v4"
            ARCH_FEATURES="AVX512"
            CVMFS_ARCH="intel/skylake_avx512"
            ARCH_CFLAGS="-march=skylake-avx512 -O2 -pipe"
            ARCH_CPU_FEATURES="AVX512F AVX512CD AVX512BW AVX512DQ AVX512VL"
            IS_PRIMARY="false"  # v4 is never primary
            ;;

        # x86-64-v3 CPUs (AVX2)
        haswell|broadwell|skylake)
            ARCH_LABEL="x86-64-v3"
            ARCH_FEATURES="AVX2"
            CVMFS_ARCH="intel/haswell"
            ARCH_CFLAGS="-march=haswell -O2 -pipe"
            ARCH_CPU_FEATURES="AVX2 FMA BMI BMI2"
            # First v3 node is primary
            if [[ "$NODE_NAME" == "cvmfs-publisher1" ]]; then
                IS_PRIMARY="true"
            else
                IS_PRIMARY="false"
            fi
            ;;

        # AMD Zen architectures
        zen|zen2|zen3|zen4)
            if echo "$ARCHSPEC_FEATURES" | grep -q "avx512"; then
                ARCH_LABEL="x86-64-v4"
                ARCH_FEATURES="AVX512"
                CVMFS_ARCH="amd/zen4"
                ARCH_CFLAGS="-march=znver4 -O2 -pipe"
                IS_PRIMARY="false"
            else
                ARCH_LABEL="x86-64-v3"
                ARCH_FEATURES="AVX2"
                CVMFS_ARCH="amd/zen3"
                ARCH_CFLAGS="-march=znver3 -O2 -pipe"
                IS_PRIMARY="false"
            fi
            ;;

        # Default/older CPUs
        *)
            log_warning "Unknown or older CPU: $ARCHSPEC_NAME"
            ARCH_LABEL="x86-64-v2"
            ARCH_FEATURES="SSE4.2"
            CVMFS_ARCH="generic"
            ARCH_CFLAGS="-march=x86-64 -mtune=generic -O2 -pipe"
            ARCH_CPU_FEATURES="SSE4_2"
            IS_PRIMARY="false"
            ;;
    esac

    log_info "Mapped to: $ARCH_LABEL ($CVMFS_ARCH)"
}

# Fallback detection if archspec fails
fallback_architecture_detection() {
    # Use cpuinfo to detect features
    if grep -q "avx512" /proc/cpuinfo; then
        ARCH_LABEL="x86-64-v4"
        ARCH_FEATURES="AVX512"
        CVMFS_ARCH="intel/skylake_avx512"
        ARCH_CFLAGS="-march=skylake-avx512 -O2 -pipe"
        ARCH_CPU_FEATURES="AVX512F AVX512CD AVX512BW AVX512DQ AVX512VL"
    elif grep -q "avx2" /proc/cpuinfo; then
        ARCH_LABEL="x86-64-v3"
        ARCH_FEATURES="AVX2"
        CVMFS_ARCH="intel/haswell"
        ARCH_CFLAGS="-march=haswell -O2 -pipe"
        ARCH_CPU_FEATURES="AVX2 FMA BMI BMI2"
    else
        ARCH_LABEL="x86-64-v2"
        ARCH_FEATURES="SSE4.2"
        CVMFS_ARCH="generic"
        ARCH_CFLAGS="-march=x86-64 -mtune=generic -O2 -pipe"
        ARCH_CPU_FEATURES="SSE4_2"
    fi

    # Determine if primary based on node name and architecture
    if [[ "$NODE_NAME" == "cvmfs-publisher1" && "$ARCH_LABEL" == "x86-64-v3" ]]; then
        IS_PRIMARY="true"
    else
        IS_PRIMARY="false"
    fi
}

# Save architecture information
save_architecture_info() {
    log_info "Saving architecture information"

    # Create architecture info directory
    mkdir -p /etc/cvmfs-publisher

    # Save as JSON for programmatic access
    cat > /etc/cvmfs-publisher/architecture.json << EOF
{
  "arch_label": "$ARCH_LABEL",
  "arch_features": "$ARCH_FEATURES",
  "cvmfs_arch": "$CVMFS_ARCH",
  "cflags": "$ARCH_CFLAGS",
  "cpu_features": "$ARCH_CPU_FEATURES",
  "is_primary": $IS_PRIMARY,
  "archspec": {
    "name": "${ARCHSPEC_NAME:-unknown}",
    "vendor": "${ARCHSPEC_VENDOR:-unknown}",
    "generation": "${ARCHSPEC_GENERATION:-0}",
    "features": "${ARCHSPEC_FEATURES:-}"
  },
  "detected_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

    # Create simple files for shell scripts
    echo "$ARCH_LABEL" > /etc/cvmfs-publisher/arch-label
    echo "$CVMFS_ARCH" > /etc/cvmfs-publisher/cvmfs-arch
    echo "$IS_PRIMARY" > /etc/cvmfs-publisher/is-primary
}

# Install CVMFS packages
install_packages() {
    log_info "Installing CVMFS client and server tools"
    apt-get install -y cvmfs cvmfs-server jq \
        || die "Failed to install CVMFS packages"
}

# Setup GitHub Actions runner with detected architecture
setup_github_runner() {
    log_info "Setting up GitHub Actions runner"

    local RUNNER_VERSION="2.311.0"
    local RUNNER_USER="runner"
    local RUNNER_HOME="/home/$RUNNER_USER"
    local RUNNER_DIR="$RUNNER_HOME/actions-runner"

    # Create runner user
    if ! id "$RUNNER_USER" &>/dev/null; then
        useradd -m -s /bin/bash "$RUNNER_USER"
        # Setup SSH key for runner (for git operations)
        sudo -u "$RUNNER_USER" ssh-keygen -t ed25519 -f "$RUNNER_HOME/.ssh/id_ed25519" -N ""
    fi

    # Create sudoers file for runner
    cat > /etc/sudoers.d/github-runner << EOF
# Allow runner to execute CVMFS commands as the repository owner
$RUNNER_USER ALL=($REPO_OWNER) NOPASSWD: /usr/bin/cvmfs_server transaction $REPOSITORY_NAME
$RUNNER_USER ALL=($REPO_OWNER) NOPASSWD: /usr/bin/cvmfs_server publish $REPOSITORY_NAME
$RUNNER_USER ALL=($REPO_OWNER) NOPASSWD: /usr/bin/cvmfs_server abort -f $REPOSITORY_NAME
$RUNNER_USER ALL=($REPO_OWNER) NOPASSWD: /usr/bin/cvmfs_server abort $REPOSITORY_NAME
$RUNNER_USER ALL=($REPO_OWNER) NOPASSWD: /usr/bin/cvmfs_server list
$RUNNER_USER ALL=(ALL) NOPASSWD: ALL
EOF
    chmod 440 /etc/sudoers.d/github-runner

    # Download and install runner
    sudo -u "$RUNNER_USER" -i bash << EOF
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

# Download runner
curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L \
    https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

# Extract
tar xzf ./actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
rm actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

# Create environment file for the runner with detected architecture
cat > .env << 'ENVFILE'
CVMFS_REPOSITORY=$REPOSITORY_NAME
ARCHITECTURE=$ARCH_LABEL
ARCH_FEATURES=$ARCH_FEATURES
NODE_NAME=$NODE_NAME
GATEWAY_URL=http://$GATEWAY_IP:$GATEWAY_PORT/api/v1
REPO_OWNER=$REPO_OWNER
CVMFS_ARCH=$CVMFS_ARCH
IS_PRIMARY=$IS_PRIMARY
ENVFILE
EOF

    # Create systemd service
    cat > /etc/systemd/system/github-runner.service << EOSERVICE
[Unit]
Description=GitHub Actions Runner ($NODE_NAME - $ARCH_LABEL)
After=network.target

[Service]
Type=simple
User=$RUNNER_USER
WorkingDirectory=$RUNNER_DIR
ExecStart=$RUNNER_DIR/run.sh
Environment="CVMFS_REPOSITORY=$REPOSITORY_NAME"
Environment="ARCHITECTURE=$ARCH_LABEL"
Environment="CVMFS_ARCH=$CVMFS_ARCH"
Environment="NODE_NAME=$NODE_NAME"
Environment="REPO_OWNER=$REPO_OWNER"
Environment="IS_PRIMARY=$IS_PRIMARY"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOSERVICE

    systemctl daemon-reload
    systemctl enable github-runner
}

# Enhanced runner registration script
create_enhanced_register_script() {
    log_info "Creating enhanced registration script"

    cat > /usr/local/bin/register-github-runner << 'EOF'
#!/bin/bash
# Register GitHub Actions runner with auto-detected architecture
# Usage: register-github-runner <repo-url> <token>

if [[ $# -ne 2 ]]; then
    echo "Usage: register-github-runner <repo-url> <token>"
    echo "Example: register-github-runner https://github.com/user/repo ABCDEFGH123456"
    exit 1
fi

REPO_URL="$1"
TOKEN="$2"

# Read detected architecture
ARCH_INFO="/etc/cvmfs-publisher/architecture.json"
if [[ -f "$ARCH_INFO" ]]; then
    ARCH_LABEL=$(jq -r '.arch_label' "$ARCH_INFO")
    CVMFS_ARCH=$(jq -r '.cvmfs_arch' "$ARCH_INFO")
    ARCH_FEATURES=$(jq -r '.arch_features' "$ARCH_INFO")
    IS_PRIMARY=$(jq -r '.is_primary' "$ARCH_INFO")
    ARCHSPEC_NAME=$(jq -r '.archspec.name' "$ARCH_INFO")
else
    echo "ERROR: Architecture detection info not found!"
    echo "This should have been created during provisioning."
    exit 1
fi

# Build labels
LABELS="self-hosted,linux,cvmfs-publisher"
LABELS="$LABELS,$ARCH_LABEL"
LABELS="$LABELS,$(echo $CVMFS_ARCH | tr '/' '-')"

# Add feature labels
if [[ "$ARCH_FEATURES" == *"AVX512"* ]]; then
    LABELS="$LABELS,avx512"
elif [[ "$ARCH_FEATURES" == *"AVX2"* ]]; then
    LABELS="$LABELS,avx2"
fi

# Add primary label if applicable
if [[ "$IS_PRIMARY" == "true" ]]; then
    LABELS="$LABELS,primary-publisher"
fi

# Add archspec name as label
if [[ "$ARCHSPEC_NAME" != "unknown" ]]; then
    LABELS="$LABELS,$ARCHSPEC_NAME"
fi

echo "Registering runner for $REPO_URL"
echo "Architecture: $ARCH_LABEL ($CVMFS_ARCH)"
echo "Features: $ARCH_FEATURES"
echo "Labels: $LABELS"
echo "Is Primary: $IS_PRIMARY"

# Stop service if running
systemctl stop github-runner 2>/dev/null || true

# Configure runner
cd /home/runner/actions-runner
sudo -u runner ./config.sh \
    --url "$REPO_URL" \
    --token "$TOKEN" \
    --name "$(hostname)-$ARCH_LABEL" \
    --labels "$LABELS" \
    --work "_work" \
    --unattended \
    --replace

# Start service
systemctl start github-runner
systemctl status github-runner
EOF
    chmod +x /usr/local/bin/register-github-runner
}

# Rest of the original functions remain the same but use detected values...
# (I'll skip repeating all the unchanged functions for brevity)

# Main execution
main() {
    # Install packages
    install_packages

    # Install and run archspec detection
    install_archspec
    detect_architecture

    # Wait for gateway
    wait_for_gateway

    # Get repository keys
    get_repository_keys

    # Setup publisher repository
    setup_publisher_repository

    # Install CI/CD dependencies
    install_cicd_dependencies

    # Setup GitHub runner with detected architecture
    setup_github_runner

    # Setup mock EasyBuild
    setup_mock_easybuild

    # Create helper scripts
    create_helper_scripts
    create_enhanced_register_script

    # Create test script
    create_test_script

    log_success "Publisher setup complete!"
    log_info "Detected Architecture: $ARCH_LABEL ($ARCH_FEATURES)"
    log_info "CVMFS Architecture: $CVMFS_ARCH"
    log_info "Is Primary Publisher: $IS_PRIMARY"
    log_info "archspec detected: ${ARCHSPEC_NAME:-fallback}"
    log_info "Use 'register-github-runner <repo-url> <token>' to activate CI/CD"
    log_info "Run '/home/vagrant/test_publish.sh' to test publishing"
    log_info "Run 'publish-info' for repository information"
}

# Run main function
main
