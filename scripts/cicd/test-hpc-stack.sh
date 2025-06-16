#!/bin/bash
# Test HPC software stack deployment

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== HPC Software Stack Test ===${NC}"
echo

# Check if we're in the project root
if [[ ! -f "Vagrantfile" ]]; then
    echo -e "${RED}Error: This script must be run from the CVMFS vagrant project root${NC}"
    exit 1
fi

# Get current quarter
QUARTER=$(date +"%Y.Q$(( ($(date +%-m)-1)/3+1 ))")

echo "Testing quarter: $QUARTER"
echo

# Test 1: Deploy structure
echo -e "${BLUE}1. Testing structure deployment...${NC}"
echo "   Running on gateway/stratum0..."

vagrant ssh cvmfs-gateway-stratum0 << 'EOF'
if [[ -x /vagrant/software-stack/deploy-stack-structure.sh ]]; then
    bash /vagrant/software-stack/deploy-stack-structure.sh
else
    echo "Deploy script not found!"
    exit 1
fi
EOF

echo

# Test 2: Verify structure on client
echo -e "${BLUE}2. Verifying structure on client...${NC}"

vagrant ssh cvmfs-client << EOF
echo "Checking directory structure..."

# Force reload
cvmfs_config reload software.lab.local 2>/dev/null || true

# Check if structure exists
BASE="/cvmfs/software.lab.local/versions"

if [[ -L "\$BASE/current" ]]; then
    echo "✓ Current symlink exists: \$(readlink \$BASE/current)"
else
    echo "✗ Current symlink missing"
fi

# List architectures
echo
echo "Available architectures:"
if [[ -d "\$BASE/$QUARTER/software/linux/x86_64" ]]; then
    find "\$BASE/$QUARTER/software/linux/x86_64" -maxdepth 2 -type d -name "software" | \
        sed "s|.*/x86_64/||" | sed "s|/software||" | sort
else
    echo "✗ Structure not found"
fi
EOF

echo

# Test 3: Test publishing from publishers
echo -e "${BLUE}3. Testing publishing to architecture paths...${NC}"

for publisher in cvmfs-publisher1 cvmfs-publisher2; do
    echo -e "${YELLOW}Testing $publisher...${NC}"

    vagrant ssh "$publisher" << 'EOF'
# Get architecture
CVMFS_ARCH=$(cat /etc/cvmfs-arch-path 2>/dev/null || echo "unknown")
QUARTER=$(date +"%Y.Q$(( ($(date +%-m)-1)/3+1 ))")

echo "Publisher architecture: $CVMFS_ARCH"

# Start transaction
if sudo -u vagrant cvmfs_server transaction software.lab.local; then
    # Add test software
    TEST_DIR="/cvmfs/software.lab.local/versions/$QUARTER/software/linux/x86_64/$CVMFS_ARCH/software/test-tool"
    sudo mkdir -p "$TEST_DIR/1.0/bin"

    cat << 'SCRIPT' | sudo tee "$TEST_DIR/1.0/bin/test-tool" > /dev/null
#!/bin/bash
echo "Test Tool v1.0"
echo "Architecture: $CVMFS_ARCH"
echo "Built on: $(hostname)"
SCRIPT
    sudo chmod +x "$TEST_DIR/1.0/bin/test-tool"

    # Create module
    MODULE_DIR="/cvmfs/software.lab.local/versions/$QUARTER/software/linux/x86_64/$CVMFS_ARCH/modules/all/test-tool"
    sudo mkdir -p "$MODULE_DIR"

    cat << 'MODULE' | sudo tee "$MODULE_DIR/1.0.lua" > /dev/null
help([[Test tool for CVMFS demo]])
whatis("Test Tool v1.0")
prepend_path("PATH", "/cvmfs/software.lab.local/versions/current/software/linux/x86_64/$CVMFS_ARCH/software/test-tool/1.0/bin")
MODULE

    # Publish
    if sudo -u vagrant cvmfs_server publish software.lab.local; then
        echo "✓ Published test software to $CVMFS_ARCH"
    else
        echo "✗ Failed to publish"
        sudo -u vagrant cvmfs_server abort -f software.lab.local
    fi
else
    echo "✗ Failed to start transaction"
fi
EOF
done

echo

# Test 4: Verify on client
echo -e "${BLUE}4. Verifying published software on client...${NC}"

vagrant ssh cvmfs-client << EOF
# Reload
cvmfs_config reload software.lab.local 2>/dev/null || true
sleep 3

QUARTER="$QUARTER"
BASE="/cvmfs/software.lab.local/versions/\$QUARTER/software/linux/x86_64"

echo "Checking for test-tool in architectures:"
for arch in intel/haswell intel/skylake_avx512; do
    if [[ -x "\$BASE/\$arch/software/test-tool/1.0/bin/test-tool" ]]; then
        echo "✓ Found in \$arch:"
        \$BASE/\$arch/software/test-tool/1.0/bin/test-tool
    else
        echo "✗ Not found in \$arch"
    fi
done

echo
echo "Module paths:"
for arch in intel/haswell intel/skylake_avx512; do
    if [[ -f "\$BASE/\$arch/modules/all/test-tool/1.0.lua" ]]; then
        echo "✓ Module found in \$arch"
    else
        echo "✗ Module not found in \$arch"
    fi
done
EOF

echo
echo -e "${BLUE}=== Test Summary ===${NC}"
echo "Your HPC software stack structure is:"
echo "  Base: /cvmfs/software.lab.local/versions/$QUARTER/"
echo "  Current: /cvmfs/software.lab.local/versions/current/"
echo
echo "Publisher mappings:"
echo "  cvmfs-publisher1 → intel/haswell"
echo "  cvmfs-publisher2 → intel/skylake_avx512"
echo
echo "To use modules:"
echo "  module use /cvmfs/software.lab.local/versions/current/software/linux/x86_64/intel/haswell/modules/all"
