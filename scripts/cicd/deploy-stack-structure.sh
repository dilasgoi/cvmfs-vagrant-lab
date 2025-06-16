#!/bin/bash
# Deploy CVMFS software stack directory structure
# This should be run once to initialize the quarterly versioned structure

set -e

# Configuration
CVMFS_REPO="software.lab.local"
CURRENT_QUARTER=$(date +"%Y.Q$(( ($(date +%-m)-1)/3+1 ))")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== CVMFS Software Stack Structure Deployment ===${NC}"
echo "Repository: $CVMFS_REPO"
echo "Quarter: $CURRENT_QUARTER"
echo

# Check if we're on the gateway/stratum0
if [[ ! -f /etc/cvmfs/repositories.d/$CVMFS_REPO/server.conf ]]; then
    echo -e "${RED}Error: This script must be run on the CVMFS gateway/stratum0 server${NC}"
    exit 1
fi

# Start transaction
echo -e "${YELLOW}Starting CVMFS transaction...${NC}"
if ! sudo -u vagrant cvmfs_server transaction $CVMFS_REPO; then
    echo -e "${RED}Failed to start transaction${NC}"
    exit 1
fi

# Create base structure
echo -e "${BLUE}Creating software stack structure...${NC}"

BASE_DIR="/cvmfs/$CVMFS_REPO/versions/$CURRENT_QUARTER/software/linux/x86_64"

# Define architectures
ARCHITECTURES=(
    "generic"
    "intel/haswell"
    "intel/skylake_avx512"
    "intel/icelake"
    "amd/zen2"
    "amd/zen3"
)

# Create directory structure
for arch in "${ARCHITECTURES[@]}"; do
    echo "  Creating $arch..."
    sudo mkdir -p "$BASE_DIR/$arch/software"
    sudo mkdir -p "$BASE_DIR/$arch/modules/all"

    # Create architecture info file
    sudo tee "$BASE_DIR/$arch/ARCHITECTURE" > /dev/null << EOF
Architecture: $arch
Created: $(date)
Quarter: $CURRENT_QUARTER
EOF
done

# Create symlink for current version
echo -e "${BLUE}Creating 'current' symlink...${NC}"
CURRENT_LINK="/cvmfs/$CVMFS_REPO/versions/current"
sudo rm -f "$CURRENT_LINK"
sudo ln -s "$CURRENT_QUARTER" "$CURRENT_LINK"

# Create README at root
echo -e "${BLUE}Creating documentation...${NC}"
sudo tee "/cvmfs/$CVMFS_REPO/versions/README.md" > /dev/null << 'EOF'
# CVMFS Software Stack

## Structure

```
versions/
├── current -> 2025.Q1  (symlink to latest quarter)
├── 2025.Q1/
│   └── software/linux/x86_64/
│       ├── generic/
│       ├── intel/haswell/
│       ├── intel/skylake_avx512/
│       ├── intel/icelake/
│       ├── amd/zen2/
│       └── amd/zen3/
└── README.md
```

## Architecture Mapping

- **generic**: Fallback for unknown CPUs
- **intel/haswell**: AVX2 support (Publisher 1)
- **intel/skylake_avx512**: AVX512 support (Publisher 2)
- **intel/icelake**: Ice Lake and newer
- **amd/zen2**: AMD EPYC 7002 series
- **amd/zen3**: AMD EPYC 7003 series

## Accessing Software

```bash
# Using current version
module use /cvmfs/software.lab.local/versions/current/software/linux/x86_64/intel/haswell/modules/all

# Using specific quarter
module use /cvmfs/software.lab.local/versions/2025.Q1/software/linux/x86_64/intel/haswell/modules/all
```
EOF

# Create deployment marker
sudo tee "/cvmfs/$CVMFS_REPO/versions/$CURRENT_QUARTER/.deployed" > /dev/null << EOF
Deployed: $(date)
Structure Version: 1.0
Architectures: ${ARCHITECTURES[@]}
EOF

# Publish changes
echo -e "${YELLOW}Publishing changes...${NC}"
if sudo -u vagrant cvmfs_server publish $CVMFS_REPO; then
    echo -e "${GREEN}✓ Successfully deployed software stack structure!${NC}"
    echo
    echo "Structure created at:"
    echo "  /cvmfs/$CVMFS_REPO/versions/$CURRENT_QUARTER/"
    echo "  /cvmfs/$CVMFS_REPO/versions/current/ -> $CURRENT_QUARTER"
else
    echo -e "${RED}Failed to publish changes${NC}"
    sudo -u vagrant cvmfs_server abort -f $CVMFS_REPO
    exit 1
fi
