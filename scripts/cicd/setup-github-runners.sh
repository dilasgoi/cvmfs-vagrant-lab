#!/bin/bash
# Setup GitHub Actions runners on CVMFS publishers for this repository

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== CVMFS GitHub Actions Runner Setup ===${NC}"
echo

# Check if we're in the vagrant directory
if [[ ! -f "Vagrantfile" ]]; then
    echo -e "${RED}Error: This script must be run from the CVMFS vagrant project root${NC}"
    exit 1
fi

# Try to get repo URL from git
REPO_URL=$(git config --get remote.origin.url 2>/dev/null | sed 's/\.git$//' | sed 's|git@github.com:|https://github.com/|' || true)

if [[ -z "$REPO_URL" || "$REPO_URL" == "null" ]]; then
    echo -e "${YELLOW}Warning: Could not detect repository URL from git${NC}"
    REPO_URL=""
fi

# Function to check if VM is running
check_vm_running() {
    local vm=$1
    if vagrant status "$vm" 2>/dev/null | grep -q "running"; then
        return 0
    else
        return 1
    fi
}

# Function to register a runner
register_runner() {
    local vm=$1
    local repo_url=$2
    local token=$3

    echo -e "${YELLOW}Registering runner on $vm...${NC}"

    vagrant ssh "$vm" -c "sudo /usr/local/bin/register-github-runner '$repo_url' '$token'" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✓ Successfully registered runner on $vm${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed to register runner on $vm${NC}"
        return 1
    fi
}

# Main script
echo "This script will register GitHub Actions runners for THIS repository"
echo "on your CVMFS publisher nodes."
echo
echo "You'll need a runner registration token from GitHub:"
echo "  1. Go to this repo's Settings > Actions > Runners"
echo "  2. Click 'New self-hosted runner'"
echo "  3. Copy the token from the configuration command"
echo

# Check if publishers are running
echo -e "${BLUE}Checking publisher VMs...${NC}"
publishers=("cvmfs-publisher1" "cvmfs-publisher2")
running_publishers=()

for pub in "${publishers[@]}"; do
    if check_vm_running "$pub"; then
        echo -e "  ${GREEN}✓${NC} $pub is running"
        running_publishers+=("$pub")
    else
        echo -e "  ${RED}✗${NC} $pub is not running"
    fi
done

if [[ ${#running_publishers[@]} -eq 0 ]]; then
    echo -e "${RED}No publisher VMs are running!${NC}"
    echo "Please start them with: vagrant up cvmfs-publisher1 cvmfs-publisher2"
    exit 1
fi

echo

# Get repository URL
if [[ -n "$REPO_URL" ]]; then
    echo "Detected repository: $REPO_URL"
    read -p "Is this correct? (Y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
        REPO_URL=""
    fi
fi

if [[ -z "$REPO_URL" ]]; then
    read -p "Enter your GitHub repository URL: " REPO_URL
fi

# Validate URL
if [[ ! "$REPO_URL" =~ ^https://github\.com/[^/]+/[^/]+$ ]]; then
    echo -e "${RED}Invalid repository URL format${NC}"
    exit 1
fi

# Show where to get token
echo
echo -e "${YELLOW}Get your registration token from:${NC}"
echo "$REPO_URL/settings/actions/runners"
echo

# Get registration token
echo "Enter your runner registration token:"
read -s TOKEN
echo

# Register runners
echo
echo -e "${BLUE}Registering runners...${NC}"

success_count=0
for pub in "${running_publishers[@]}"; do
    if register_runner "$pub" "$REPO_URL" "$TOKEN"; then
        ((success_count++))
    fi
done

# Summary
echo
echo -e "${BLUE}=== Registration Summary ===${NC}"
echo "Successfully registered: $success_count/${#running_publishers[@]} runners"

if [[ $success_count -gt 0 ]]; then
    echo
    echo -e "${GREEN}Your CVMFS publishers are now connected to GitHub Actions!${NC}"
    echo
    echo "The workflow will trigger when you:"
    echo "  - Push changes to software-stack/"
    echo "  - Manually trigger from Actions tab"
    echo
    echo "Runner labels:"
    echo "  - cvmfs-publisher1: self-hosted, linux, cvmfs-publisher, x86-64-v3"
    echo "  - cvmfs-publisher2: self-hosted, linux, cvmfs-publisher, x86-64-v4"
fi

# Show runner status
echo
echo -e "${BLUE}Runner status:${NC}"
for pub in "${running_publishers[@]}"; do
    echo -n "  $pub: "
    if vagrant ssh "$pub" -c "systemctl is-active github-runner" 2>/dev/null | grep -q "active"; then
        echo -e "${GREEN}Active${NC}"
    else
        echo -e "${RED}Not running${NC}"
    fi
done
