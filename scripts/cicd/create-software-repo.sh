#!/bin/bash
# Script to create a new software repository for CVMFS deployment
# Can be used interactively or with command-line arguments

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
DEFAULT_REPO_NAME="cvmfs-cicd"
DEFAULT_CVMFS_REPO="software.lab.local"

# Function to show usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Create a CVMFS software repository structure"
    echo
    echo "Options:"
    echo "  -n, --name NAME         Repository name (default: $DEFAULT_REPO_NAME)"
    echo "  -d, --dir DIR          Target directory (default: ./NAME)"
    echo "  -r, --repo REPO        CVMFS repository name (default: $DEFAULT_CVMFS_REPO)"
    echo "  -g, --github URL       GitHub repository URL (will configure git remote)"
    echo "  -q, --quiet            Quiet mode (no interactive prompts)"
    echo "  -h, --help             Show this help message"
    echo
    echo "Examples:"
    echo "  # Interactive mode"
    echo "  $0"
    echo
    echo "  # Non-interactive with all options"
    echo "  $0 --name cicd --github https://github.com/user/cicd --quiet"
    echo
    echo "  # Quick setup with defaults"
    echo "  $0 -n my-software -q"
}

# Parse command line arguments
REPO_NAME=""
TARGET_DIR=""
CVMFS_REPO=""
GITHUB_URL=""
QUIET=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            REPO_NAME="$2"
            shift 2
            ;;
        -d|--dir)
            TARGET_DIR="$2"
            shift 2
            ;;
        -r|--repo)
            CVMFS_REPO="$2"
            shift 2
            ;;
        -g|--github)
            GITHUB_URL="$2"
            shift 2
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

# Set defaults or prompt for values
if [[ -z "$REPO_NAME" ]]; then
    if [[ "$QUIET" == "true" ]]; then
        REPO_NAME="$DEFAULT_REPO_NAME"
    else
        echo -e "${BLUE}=== CVMFS Software Repository Creator ===${NC}"
        echo
        echo "This script will help you create a new GitHub repository"
        echo "for deploying software to CVMFS using the vagrant lab."
        echo
        read -p "Enter the desired repository name (default: $DEFAULT_REPO_NAME): " REPO_NAME
        REPO_NAME=${REPO_NAME:-"$DEFAULT_REPO_NAME"}
    fi
fi

if [[ -z "$TARGET_DIR" ]]; then
    if [[ "$QUIET" == "true" ]]; then
        TARGET_DIR="./$REPO_NAME"
    else
        read -p "Enter target directory (default: ./$REPO_NAME): " TARGET_DIR
        TARGET_DIR=${TARGET_DIR:-"./$REPO_NAME"}
    fi
fi

if [[ -z "$CVMFS_REPO" ]]; then
    if [[ "$QUIET" == "true" ]]; then
        CVMFS_REPO="$DEFAULT_CVMFS_REPO"
    else
        read -p "Enter CVMFS repository name (default: $DEFAULT_CVMFS_REPO): " CVMFS_REPO
        CVMFS_REPO=${CVMFS_REPO:-"$DEFAULT_CVMFS_REPO"}
    fi
fi

# Check if directory exists
if [[ -d "$TARGET_DIR" ]]; then
    if [[ "$QUIET" == "true" ]]; then
        echo -e "${YELLOW}Warning: Directory $TARGET_DIR already exists. Removing it.${NC}"
        rm -rf "$TARGET_DIR"
    else
        echo -e "${RED}Error: Directory $TARGET_DIR already exists${NC}"
        read -p "Remove it and continue? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$TARGET_DIR"
        else
            exit 1
        fi
    fi
fi

echo -e "${BLUE}Creating repository structure in $TARGET_DIR...${NC}"

# Create directory structure
mkdir -p "$TARGET_DIR"/{.github/workflows,software/{common,x86-64-v3,x86-64-v4},easyconfigs,scripts}

# Get the absolute path to the templates directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAGRANT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE_DIR="$VAGRANT_ROOT/templates/software-repo"

# Copy workflow templates
if [[ -d "$TEMPLATE_DIR/.github/workflows" ]]; then
    cp "$TEMPLATE_DIR/.github/workflows"/*.yml "$TARGET_DIR/.github/workflows/"
else
    echo -e "${YELLOW}Warning: Template workflows not found, creating basic workflows${NC}"
    # Create basic workflow if templates not found
    cat > "$TARGET_DIR/.github/workflows/cvmfs-deploy.yml" << 'EOF'
name: Deploy to CVMFS

on:
  push:
    branches: [main]
    paths:
      - 'software/**'
      - 'easyconfigs/**'

env:
  CVMFS_REPOSITORY: ${{ vars.CVMFS_REPOSITORY || 'software.lab.local' }}

jobs:
  deploy:
    runs-on: [self-hosted, linux, cvmfs-publisher, "${{ matrix.arch }}"]
    strategy:
      matrix:
        arch: [x86-64-v3, x86-64-v4]
    steps:
      - uses: actions/checkout@v4
      - name: Deploy to CVMFS
        run: |
          echo "Deploying to $CVMFS_REPOSITORY on ${{ matrix.arch }}"
          # Deployment logic here
EOF
fi

# Create README
cat > "$TARGET_DIR/README.md" << EOF
# $REPO_NAME

CVMFS software repository for deploying scientific software.

## Quick Start

1. **Register GitHub runners** (if not already done):
   \`\`\`bash
   cd /path/to/cvmfs-vagrant-lab
   ./scripts/cicd/setup-github-runners.sh
   \`\`\`

2. **Configure repository variables** in GitHub:
   - Go to Settings → Secrets and variables → Actions → Variables
   - Add: \`CVMFS_REPOSITORY\` = \`$CVMFS_REPO\`

3. **Deploy software**:
   - Add files to \`software/\` or \`easyconfigs/\`
   - Push to trigger automatic deployment

## Repository Structure

\`\`\`
.
├── .github/workflows/    # GitHub Actions workflows
├── software/             # Pre-built software packages
│   ├── common/          # Architecture-independent files
│   ├── x86-64-v3/      # AVX2 optimized binaries
│   └── x86-64-v4/      # AVX512 optimized binaries
├── easyconfigs/         # EasyBuild configuration files
└── scripts/             # Helper scripts
\`\`\`

## Architecture Support

- **x86-64-v3**: Haswell and newer (AVX2, FMA, BMI)
- **x86-64-v4**: Skylake-X and newer (AVX512)

## Deployment

Push changes to \`main\` branch to trigger automatic deployment to CVMFS.
EOF

# Create .gitignore
cat > "$TARGET_DIR/.gitignore" << 'EOF'
# Temporary files
*.tmp
*.log
*.swp
*~

# Build artifacts
*.o
*.so
*.a

# Python
__pycache__/
*.pyc
*.pyo

# IDE
.vscode/
.idea/
EOF

# Create sample easyconfig
cat > "$TARGET_DIR/easyconfigs/Hello-1.0-GCCcore-12.3.0.eb" << 'EOF'
# Example EasyConfig - Hello World
name = 'Hello'
version = '1.0'

homepage = 'https://example.com'
description = """A simple hello world program for testing CVMFS deployment"""

toolchain = {'name': 'GCCcore', 'version': '12.3.0'}

# This is a mock build for demonstration
# In production, you would have:
# sources = ['hello-%(version)s.tar.gz']
# source_urls = ['https://example.com/downloads/']

moduleclass = 'tools'
EOF

# Create sample pre-built software
mkdir -p "$TARGET_DIR/software/x86-64-v3/hello/bin"
cat > "$TARGET_DIR/software/x86-64-v3/hello/bin/hello" << 'EOF'
#!/bin/bash
echo "Hello from CVMFS!"
echo "Architecture: x86-64-v3 (AVX2)"
echo "This is a pre-built binary example"
EOF
chmod +x "$TARGET_DIR/software/x86-64-v3/hello/bin/hello"

# Create the same for x86-64-v4
mkdir -p "$TARGET_DIR/software/x86-64-v4/hello/bin"
cat > "$TARGET_DIR/software/x86-64-v4/hello/bin/hello" << 'EOF'
#!/bin/bash
echo "Hello from CVMFS!"
echo "Architecture: x86-64-v4 (AVX512)"
echo "This is a pre-built binary example"
EOF
chmod +x "$TARGET_DIR/software/x86-64-v4/hello/bin/hello"

# Create architecture README files
echo "# x86-64-v3 Software (AVX2)" > "$TARGET_DIR/software/x86-64-v3/README.md"
echo "Place AVX2-optimized binaries here" >> "$TARGET_DIR/software/x86-64-v3/README.md"

echo "# x86-64-v4 Software (AVX512)" > "$TARGET_DIR/software/x86-64-v4/README.md"
echo "Place AVX512-optimized binaries here" >> "$TARGET_DIR/software/x86-64-v4/README.md"

echo "# Common Software (Architecture Independent)" > "$TARGET_DIR/software/common/README.md"
echo "Place architecture-independent files here (configs, data, docs)" >> "$TARGET_DIR/software/common/README.md"

# Create a quick test script
cat > "$TARGET_DIR/scripts/test-deployment.sh" << 'EOF'
#!/bin/bash
# Quick test to verify deployment worked

echo "Testing CVMFS deployment..."
echo

# Test on client
vagrant ssh cvmfs-client << 'EOSSH'
echo "Checking repository access..."
ls -la /cvmfs/software.lab.local/ 2>/dev/null || echo "Repository not mounted yet"

echo
echo "Checking software deployment..."
if [[ -f /cvmfs/software.lab.local/software/x86-64-v3/hello/bin/hello ]]; then
    echo "✓ Software found!"
    /cvmfs/software.lab.local/software/x86-64-v3/hello/bin/hello
else
    echo "✗ Software not found yet. It may take up to 5 minutes to replicate."
    echo "  Try: cvmfs_config reload software.lab.local"
fi
EOSSH
EOF
chmod +x "$TARGET_DIR/scripts/test-deployment.sh"

# Initialize git repository
cd "$TARGET_DIR"
git init -q
git add .
git commit -q -m "Initial repository structure"

# Add GitHub remote if provided
if [[ -n "$GITHUB_URL" ]]; then
    git remote add origin "$GITHUB_URL"
    echo -e "${BLUE}Added GitHub remote: $GITHUB_URL${NC}"
fi

# Success message
echo
echo -e "${GREEN}✓ Repository created successfully in: $TARGET_DIR${NC}"
echo

if [[ -n "$GITHUB_URL" ]]; then
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. cd $TARGET_DIR"
    echo "2. git push -u origin main"
    echo "3. Register runners: cd /path/to/cvmfs-vagrant-lab && ./scripts/cicd/setup-github-runners.sh"
    echo "4. Configure CVMFS_REPOSITORY variable in GitHub settings"
else
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. cd $TARGET_DIR"
    echo "2. Create repo on GitHub: https://github.com/new"
    echo "3. git remote add origin https://github.com/YOUR_ORG/$REPO_NAME.git"
    echo "4. git push -u origin main"
    echo "5. Register runners: cd /path/to/cvmfs-vagrant-lab && ./scripts/cicd/setup-github-runners.sh"
    echo "6. Configure CVMFS_REPOSITORY variable in GitHub settings"
fi

echo
echo -e "${YELLOW}Quick test after deployment:${NC}"
echo "cd $TARGET_DIR && ./scripts/test-deployment.sh"
echo
echo -e "${GREEN}Happy deploying!${NC}"
