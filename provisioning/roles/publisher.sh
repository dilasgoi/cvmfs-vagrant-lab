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
    if python3 -c "import archspec.cpu; print(archspec.cpu.host())" >/dev/null 2>&1; then
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
    if command -v python3 >/dev/null 2>&1 && python3 -c "import archspec.cpu" 2>/dev/null; then
        # Use Python to get archspec info
        ARCHSPEC_JSON=$(python3 -c "
import json
import archspec.cpu
host = archspec.cpu.host()
print(json.dumps(host.to_dict()))
" 2>/dev/null)

        if [[ -n "$ARCHSPEC_JSON" ]]; then
            ARCHSPEC_NAME=$(echo "$ARCHSPEC_JSON" | jq -r '.name' 2>/dev/null || echo "unknown")
            ARCHSPEC_VENDOR=$(echo "$ARCHSPEC_JSON" | jq -r '.vendor' 2>/dev/null || echo "unknown")
            ARCHSPEC_GENERATION=$(echo "$ARCHSPEC_JSON" | jq -r '.generation' 2>/dev/null || echo "0")
            ARCHSPEC_FEATURES=$(echo "$ARCHSPEC_JSON" | jq -r '.features[]' 2>/dev/null | tr '\n' ' ' || echo "")

            log_info "Detected CPU: $ARCHSPEC_VENDOR $ARCHSPEC_NAME"
            log_info "Features: $ARCHSPEC_FEATURES"

            # Map to our architecture scheme
            map_architecture_to_cvmfs
        else
            log_warning "archspec detection failed, using fallback"
            fallback_architecture_detection
        fi
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

    # Also save to legacy locations for compatibility
    echo "$ARCH_LABEL" > /etc/cvmfs-arch
    echo "$CVMFS_ARCH" > /etc/cvmfs-arch-path
}

# Install CVMFS packages
install_packages() {
    log_info "Installing CVMFS client and server tools"
    apt-get install -y cvmfs cvmfs-server jq \
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

# Install CI/CD dependencies
install_cicd_dependencies() {
    log_info "Installing CI/CD dependencies"

    apt-get install -y \
        curl \
        jq \
        git \
        build-essential \
        python3 \
        python3-pip \
        python3-venv \
        libicu-dev \
        rsync \
        || die "Failed to install CI/CD dependencies"
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

# Setup mock EasyBuild environment
setup_mock_easybuild() {
    log_info "Setting up mock EasyBuild environment"

    # Create mock easybuild command that works with CVMFS transactions
    cat > /usr/local/bin/easybuild << 'EOF'
#!/bin/bash
# Mock EasyBuild for CVMFS Lab - installs directly into CVMFS repository

CVMFS_REPO="/cvmfs/software.lab.local"
ARCH=$(cat /etc/cvmfs-arch 2>/dev/null || echo "generic")

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            echo "EasyBuild 4.8.0 (mock for CVMFS)"
            exit 0
            ;;
        --help)
            echo "Mock EasyBuild for CVMFS Lab"
            echo "Usage: easybuild <easyconfig.eb> [options]"
            echo "Options:"
            echo "  --robot                 Enable dependency resolution"
            echo "  --prefix=PATH          Installation prefix (ignored, uses CVMFS)"
            exit 0
            ;;
        *.eb)
            EASYCONFIG="$1"
            ;;
    esac
    shift
done

if [[ -n "$EASYCONFIG" ]]; then
    # Extract software info from filename
    BASENAME=$(basename "$EASYCONFIG" .eb)
    SOFTWARE=$(echo "$BASENAME" | cut -d- -f1)
    VERSION=$(echo "$BASENAME" | cut -d- -f2)
    TOOLCHAIN=$(echo "$BASENAME" | cut -d- -f3,4)

    echo "== Building $SOFTWARE/$VERSION with toolchain $TOOLCHAIN for $ARCH =="
    echo "== Installing directly into CVMFS repository =="

    # Check if we're in a CVMFS transaction
    if ! mountpoint -q "$CVMFS_REPO"; then
        echo "ERROR: CVMFS repository not mounted. Start a transaction first!"
        exit 1
    fi

    # Simulate build steps
    echo "== Fetching sources..."
    sleep 1
    echo "== Configuring..."
    sleep 1
    echo "== Building... (this would take 5-30 minutes for real software)"
    sleep 2
    echo "== Installing..."

    # Create installation in CVMFS
    INSTALL_DIR="$CVMFS_REPO/software/$ARCH/$SOFTWARE/$VERSION-$TOOLCHAIN"
    sudo mkdir -p "$INSTALL_DIR/bin"

    # Create a mock binary
    cat << EOFBIN | sudo tee "$INSTALL_DIR/bin/$SOFTWARE" > /dev/null
#!/bin/bash
echo "$SOFTWARE version $VERSION"
echo "Built with toolchain: $TOOLCHAIN"
echo "Architecture: $ARCH"
echo "This is a mock binary for CVMFS Lab"
EOFBIN
    sudo chmod +x "$INSTALL_DIR/bin/$SOFTWARE"

    # Create module file
    MODULE_DIR="$CVMFS_REPO/modules/$ARCH/all/$SOFTWARE"
    sudo mkdir -p "$MODULE_DIR"
    cat << EOFMOD | sudo tee "$MODULE_DIR/$VERSION-$TOOLCHAIN.lua" > /dev/null
help([[$SOFTWARE version $VERSION - Mock module for CVMFS Lab]])
whatis("Description: Mock $SOFTWARE built with $TOOLCHAIN")
whatis("Version: $VERSION")

prepend_path("PATH", "$INSTALL_DIR/bin")
prepend_path("LD_LIBRARY_PATH", "$INSTALL_DIR/lib")

setenv("${SOFTWARE^^}_ROOT", "$INSTALL_DIR")
EOFMOD

    echo "== Successfully built $SOFTWARE/$VERSION"
    echo "== Installation: $INSTALL_DIR"
    echo "== Module: $MODULE_DIR/$VERSION-$TOOLCHAIN.lua"
fi
EOF
    chmod +x /usr/local/bin/easybuild
}

# Create helper scripts
create_helper_scripts() {
    log_info "Creating helper scripts"

    # Transaction helper scripts
    cat > /usr/local/bin/publish-start << EOF
#!/bin/bash
echo "Starting transaction on $REPOSITORY_NAME..."
sudo -u $REPO_OWNER cvmfs_server transaction $REPOSITORY_NAME
if [ \$? -eq 0 ]; then
    echo "Transaction started. You can now modify files in /cvmfs/$REPOSITORY_NAME/"
    echo "Use 'sudo' for file operations within /cvmfs/$REPOSITORY_NAME/"
    echo "Run 'publish-complete' when done, or 'publish-abort' to cancel"
else
    echo "Failed to start transaction"
    exit 1
fi
EOF
    chmod +x /usr/local/bin/publish-start

    cat > /usr/local/bin/publish-complete << EOF
#!/bin/bash
echo "Publishing changes to $REPOSITORY_NAME..."
sudo -u $REPO_OWNER cvmfs_server publish $REPOSITORY_NAME
if [ \$? -eq 0 ]; then
    echo "Changes published successfully!"
    echo "Architecture: $ARCH_LABEL"
else
    echo "Failed to publish changes"
    exit 1
fi
EOF
    chmod +x /usr/local/bin/publish-complete

    cat > /usr/local/bin/publish-abort << EOF
#!/bin/bash
echo "Aborting transaction on $REPOSITORY_NAME..."
sudo -u $REPO_OWNER cvmfs_server abort -f $REPOSITORY_NAME
echo "Transaction aborted"
EOF
    chmod +x /usr/local/bin/publish-abort

    # Info script
    cat > /usr/local/bin/publish-info << EOF
#!/bin/bash
echo "=== CVMFS Publisher Information ==="
echo "Node: $NODE_NAME"
echo "Architecture: $ARCH_LABEL ($ARCH_FEATURES)"
echo "CVMFS Architecture: $CVMFS_ARCH"
echo "Repository: $REPOSITORY_NAME"
echo "Gateway: http://$GATEWAY_IP:$GATEWAY_PORT/api/v1"
echo "Is Primary: $IS_PRIMARY"
echo
# Show detected architecture details if available
if [[ -f /etc/cvmfs-publisher/architecture.json ]]; then
    echo "Architecture Details:"
    jq -r '. | "  CPU: \(.archspec.vendor) \(.archspec.name)", "  Features: \(.cpu_features)", "  Compiler flags: \(.cflags)"' /etc/cvmfs-publisher/architecture.json
    echo
fi
echo "GitHub Actions Runner:"
if systemctl is-active --quiet github-runner; then
    echo "  Status: Running"
    echo "  Labels: self-hosted,linux,cvmfs-publisher,$ARCH_LABEL"
else
    echo "  Status: Not configured"
    echo "  Run 'register-github-runner <repo-url> <token>' to activate"
fi
echo
echo "Commands:"
echo "  publish-start    - Start a transaction"
echo "  publish-complete - Commit and publish changes"
echo "  publish-abort    - Cancel current transaction"
echo "  register-github-runner - Register with GitHub"
echo
echo "Current status:"
cvmfs_server list
EOF
    chmod +x /usr/local/bin/publish-info
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

# Create test publishing script
create_test_script() {
    log_info "Creating test publishing script"

    cat > /home/vagrant/test_publish.sh << 'EOF'
#!/bin/bash
echo "=== Testing publisher functionality ==="
echo

# Show architecture info
if [[ -f /etc/cvmfs-publisher/architecture.json ]]; then
    echo "Architecture Information:"
    jq -r '. | "  Label: \(.arch_label)", "  Features: \(.arch_features)", "  CVMFS Path: \(.cvmfs_arch)", "  Is Primary: \(.is_primary)"' /etc/cvmfs-publisher/architecture.json
    echo
fi

echo "1. Starting transaction..."
sudo -u vagrant cvmfs_server transaction software.lab.local || exit 1

echo "2. Creating test file..."
TEST_FILE="/cvmfs/software.lab.local/test/publish_$(date +%Y%m%d_%H%M%S).txt"
sudo mkdir -p $(dirname $TEST_FILE)
echo "Test publish from $(hostname) at $(date)" | sudo tee $TEST_FILE > /dev/null
echo "Publisher: $(whoami)" | sudo tee -a $TEST_FILE > /dev/null
echo "Architecture: $(cat /etc/cvmfs-arch)" | sudo tee -a $TEST_FILE > /dev/null
echo "CVMFS Architecture: $(cat /etc/cvmfs-arch-path)" | sudo tee -a $TEST_FILE > /dev/null

# Add archspec info if available
if [[ -f /etc/cvmfs-publisher/architecture.json ]]; then
    echo "CPU Details: $(jq -r '.archspec | "\(.vendor) \(.name)"' /etc/cvmfs-publisher/architecture.json)" | sudo tee -a $TEST_FILE > /dev/null
fi

echo "3. Publishing changes..."
sudo -u vagrant cvmfs_server publish software.lab.local || exit 1

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
