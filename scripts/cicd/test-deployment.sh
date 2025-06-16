#!/bin/bash
# Test CVMFS deployment after setting up CI/CD

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== CVMFS CI/CD Deployment Test ===${NC}"
echo

# Check if we're in the project root
if [[ ! -f "Vagrantfile" ]]; then
    echo -e "${RED}Error: This script must be run from the CVMFS vagrant project root${NC}"
    exit 1
fi

# Function to check runner status
check_runners() {
    echo -e "${BLUE}Checking GitHub Actions runners...${NC}"

    local active_count=0
    for pub in cvmfs-publisher1 cvmfs-publisher2; do
        echo -n "  $pub: "
        if vagrant ssh "$pub" -c "systemctl is-active github-runner" 2>/dev/null | grep -q "active"; then
            echo -e "${GREEN}Active${NC}"
            ((active_count++))
        else
            echo -e "${RED}Not running${NC}"
        fi
    done

    if [[ $active_count -eq 0 ]]; then
        echo -e "${YELLOW}No runners active. Run ./scripts/cicd/setup-github-runners.sh first${NC}"
        return 1
    fi

    return 0
}

# Function to test manual publishing
test_manual_publish() {
    local publisher=$1
    local test_file="test_$(date +%s).txt"

    echo -e "${BLUE}Testing manual publish from $publisher...${NC}"

    # Create and publish test content
    vagrant ssh "$publisher" << EOF
# Start transaction
if sudo -u vagrant cvmfs_server transaction software.lab.local; then
    # Create test content
    sudo mkdir -p /cvmfs/software.lab.local/cicd-test
    echo "CI/CD test from $publisher at $(date)" | sudo tee /cvmfs/software.lab.local/cicd-test/$test_file

    # Publish
    if sudo -u vagrant cvmfs_server publish software.lab.local; then
        echo "✓ Published successfully"
    else
        echo "✗ Publish failed"
        sudo -u vagrant cvmfs_server abort -f software.lab.local
        exit 1
    fi
else
    echo "✗ Failed to start transaction"
    exit 1
fi
EOF

    # Verify on client
    echo "  Verifying on client..."
    sleep 5  # Give time for replication

    if vagrant ssh cvmfs-client -c "cat /cvmfs/software.lab.local/cicd-test/$test_file" 2>/dev/null; then
        echo -e "  ${GREEN}✓ Content accessible on client${NC}"
        return 0
    else
        echo -e "  ${YELLOW}⚠ Content not yet accessible (may need more time for replication)${NC}"
        return 1
    fi
}

# Function to show workflow status
show_workflow_status() {
    echo -e "${BLUE}GitHub Actions Workflow Status:${NC}"

    if [[ -f ".github/workflows/deploy-software.yml" ]]; then
        echo -e "  ${GREEN}✓${NC} Workflow file exists"
    else
        echo -e "  ${RED}✗${NC} Workflow file missing"
        echo "    Create .github/workflows/deploy-software.yml"
    fi

    # Check if this is a git repo
    if git rev-parse --git-dir > /dev/null 2>&1; then
        local remote_url=$(git config --get remote.origin.url 2>/dev/null || echo "")
        if [[ -n "$remote_url" ]]; then
            echo -e "  ${GREEN}✓${NC} Git remote configured: $remote_url"
        else
            echo -e "  ${YELLOW}⚠${NC} No git remote configured"
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} Not a git repository"
    fi
}

# Function to test the full workflow
test_workflow() {
    echo -e "${BLUE}Testing deployment workflow...${NC}"

    # Create test content
    local test_dir="software-stack/software/common/cicd-test-$(date +%s)"
    mkdir -p "$test_dir"
    echo "#!/bin/bash" > "$test_dir/test.sh"
    echo "echo 'Hello from CI/CD test!'" >> "$test_dir/test.sh"
    chmod +x "$test_dir/test.sh"

    echo -e "${GREEN}✓${NC} Created test content in $test_dir"
    echo
    echo "To complete the workflow test:"
    echo "  1. git add $test_dir"
    echo "  2. git commit -m 'Test CI/CD deployment'"
    echo "  3. git push"
    echo "  4. Monitor the Actions tab on GitHub"
    echo "  5. Check deployment: vagrant ssh cvmfs-client -c 'ls /cvmfs/software.lab.local/software/common/'"
}

# Main execution
echo "1. Checking infrastructure..."
if ! vagrant status | grep -E "(gateway|publisher|client)" | grep -q "running"; then
    echo -e "${RED}Some VMs are not running. Run 'vagrant up' first${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Infrastructure is up${NC}"
echo

echo "2. Checking runners..."
check_runners
echo

echo "3. Testing manual publishing..."
if test_manual_publish "cvmfs-publisher1"; then
    echo -e "${GREEN}✓ Manual publishing works${NC}"
else
    echo -e "${YELLOW}⚠ Manual publishing needs attention${NC}"
fi
echo

echo "4. Workflow configuration..."
show_workflow_status
echo

echo "5. Creating test content..."
test_workflow
echo

echo -e "${BLUE}=== Summary ===${NC}"
echo "Your CVMFS CI/CD infrastructure is ready!"
echo
echo "Next steps:"
echo "  - Ensure runners are registered (if not done)"
echo "  - Push changes to software-stack/ to trigger deployment"
echo "  - Monitor deployments in GitHub Actions"
echo
echo "Useful commands:"
echo "  - Check runners: ./scripts/cicd/setup-github-runners.sh"
echo "  - View CVMFS content: vagrant ssh cvmfs-client -c 'ls -la /cvmfs/software.lab.local/'"
echo "  - Check transaction status: vagrant ssh cvmfs-publisher1 -c 'cvmfs_server list'"
