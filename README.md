# CVMFS Vagrant Lab

A complete, automated CVMFS (CernVM File System) infrastructure setup using Vagrant for learning, testing, and development purposes.

## What is CVMFS?

CVMFS (CernVM File System) is a scalable, reliable, and low-maintenance software distribution service. It was developed to assist High Energy Physics (HEP) collaborations in deploying software on the worldwide distributed computing infrastructure. CVMFS is implemented as a POSIX read-only file system in user space (FUSE).

### Key Concepts

- **Stratum 0**: The master repository server where content is initially published
- **Stratum 1**: Mirror/replica servers that distribute content globally
- **Repository Gateway**: Allows distributed publishing to the repository
- **Proxy**: HTTP caching proxy (Squid) to reduce load and improve performance
- **Client**: Mounts and accesses CVMFS repositories

##  What This Lab Provides

This project sets up a complete CVMFS infrastructure with:

- **1 Gateway + Stratum-0 server** (combined node)
- **2 Publisher nodes** (for distributed content publishing)
- **1 Stratum-1 replica server** (mirrors the Stratum-0)
- **1 Squid proxy server** (for caching)
- **1 Client node** (to test repository access)

All nodes are automatically configured and interconnected, providing a realistic CVMFS deployment suitable for learning and experimentation.

## Prerequisites

- **VirtualBox** (6.1 or newer)
- **Vagrant** (2.2.19 or newer)

## Quick Start

1. **Clone the repository**:
   ```bash
   git clone https://github.com/dilasgoi/cvmfs-vagrant-lab
   cd cvmfs-vagrant-lab
   ```

2. **Start the infrastructure**:
   ```bash
   vagrant up
   ```
   This will create and configure all 6 VMs. Initial setup takes around 10 minutes as it upgrades the OS (you could skip this by commenting upgrade lines in
   the provision scripts).

3. **Run the test suite**:
   ```bash
   cd tests
   ./run-all-tests.sh
   ```
   Some tests regarding newly created published may fail on the client side but these failures are not a concern.

4. **Access a VM**:
   ```bash
   vagrant ssh cvmfs-client
   ```

## Project Structure

```
cvmfs-vagrant/
├── config/
│   ├── nodes.yaml        # VM definitions and network configuration
│   └── settings.yaml     # CVMFS and service settings
├── provisioning/
│   ├── common/          # Shared provisioning scripts
│   └── roles/           # Role-specific setup scripts
├── scripts/
│   ├── helpers/         # Utility scripts
│   └── utils/           # CVMFS-specific utilities
├── tests/               # Comprehensive test suite
└── Vagrantfile          # Vagrant configuration
```

## Infrastructure Overview

### Network Topology

```
┌─────────────────────────────────────────────────────────────────┐
│                     Private Network: 192.168.58.0/24            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Gateway + Stratum-0 (192.168.58.10)                            │
│  ┌─────────────────────────────────┐                            │
│  │ - Apache (HTTP)                 │                            │
│  │ - CVMFS Stratum-0               │◄─── Publishes              │
│  │ - Gateway API (:4929)           │                            │
│  └──────────────▲──────────────────┘                            │
│                 │                                               │
│                 │ Gateway API                                   │
│     ┌───────────┴──────────┬────────────────┐                   │
│     │                      │                │                   │
│  Publisher 1            Publisher 2     Stratum-1               │
│  (192.168.58.15)       (192.168.58.16) (192.168.58.11)          │
│  ┌─────────────┐       ┌─────────────┐ ┌─────────────┐          │
│  │ Publishes   │       │ Publishes   │ │ - Apache    │          │
│  │ content via │       │ content via │ │ - Replica   │◄─┐       │
│  │ Gateway     │       │ Gateway     │ │   mirror    │  │       │
│  └─────────────┘       └─────────────┘ └─────────────┘  │       │
│                                                         │       │
│                                                   Syncs │       │
│  Squid Proxy (192.168.58.14)                    from S0 │       │
│  ┌─────────────────────────────┐                        │       │
│  │ HTTP Caching Proxy (:3128)  │◄───────────────────────┘       │
│  └──────────────▲──────────────┘                                │
│                 │                                               │
│                 │ Cached Access                                 │
│                 │                                               │
│  Client (192.168.58.12)                                         │
│  ┌─────────────────────────────┐                                │
│  │ Mounts /cvmfs/              │                                │
│  │ software.lab.local          │                                │
│  └─────────────────────────────┘                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### VM Specifications

| Node | IP | Memory | CPUs | Role |
|------|-----|---------|-------|--------|
| cvmfs-gateway-stratum0 | 192.168.58.10 | 4GB | 4 | Gateway + Master Repository |
| cvmfs-publisher1 | 192.168.58.15 | 1GB | 2 | Content Publisher |
| cvmfs-publisher2 | 192.168.58.16 | 1GB | 2 | Content Publisher |
| cvmfs-stratum1 | 192.168.58.11 | 4GB | 4 | Replica Server |
| squid-proxy | 192.168.58.14 | 1GB | 1 | HTTP Cache |
| cvmfs-client | 192.168.58.12 | 2GB | 2 | Client Access |

## Configuration

### Repository Details

- **Repository Name**: `software.lab.local`
- **Domain**: `lab.local`
- **Mount Point**: `/cvmfs/software.lab.local`

### Key URLs

- **Gateway API**: http://192.168.58.10:4929/api/v1
- **Stratum-0**: http://192.168.58.10/cvmfs/software.lab.local
- **Stratum-1**: http://192.168.58.11/cvmfs/software.lab.local
- **Proxy**: http://192.168.58.14:3128

## Learning Exercises

### Exercise 1: Basic Publishing

1. SSH into publisher1:
   ```bash
   vagrant ssh cvmfs-publisher1
   ```

2. Start a transaction:
   ```bash
   cvmfs_server transaction software.lab.local
   ```

   Alternatively, you can use the provided wrapper:

   ```bash
   publish-start
   ```

3. Create content:
   ```bash
   sudo mkdir -p /cvmfs/software.lab.local/myapp/v1.0
   echo "Hello CVMFS!" | sudo tee /cvmfs/software.lab.local/myapp/v1.0/hello.txt
   ```

4. Publish the changes:
   ```bash
   cvmfs_server publish software.lab.local
   ```

   Alternatively, you can use the provided wrapper:

   ```bash
   publish-complete
   ```

5. Verify on the client:
   ```bash
   vagrant ssh cvmfs-client
   cat /cvmfs/software.lab.local/myapp/v1.0/hello.txt
   ```
   
   You might need to wait until new files are accesible from client.

   You could also force a reload on the client:

   ```bash
   vagrant ssh cvmfs-client
   cvmfs_config reload software.lab.local
   ```

### Exercise 2: Monitoring Replication

1. Watch Stratum-1 logs while publishing:
   ```bash
   # Terminal 1: Monitor Stratum-1
   vagrant ssh cvmfs-stratum1
   sudo tail -f /var/log/cvmfs/snapshots.log
   
   # Terminal 2: Publish content
   vagrant ssh cvmfs-publisher1
   cvmfs_server transaction software.lab.local
   echo "Replication test" | sudo tee /cvmfs/software.lab.local/repltest.txt
   cvmfs_server publish software.lab.local
   ```

### Exercise 3: Understanding Caching

1. Clear client cache and monitor proxy:
   ```bash
   # Terminal 1: Monitor proxy access
   vagrant ssh squid-proxy
   sudo tail -f /var/log/squid/access.log
   
   # Terminal 2: Access files
   vagrant ssh cvmfs-client
   sudo cvmfs_config wipecache
   cat /cvmfs/software.lab.local/README.txt
   ```

### Exercise 4: Concurrent Publishing

Test how the gateway handles concurrent publish attempts:

1. Try publishing from both publishers simultaneously
2. Observe lease management and conflict resolution

## Testing

### Run All Tests
```bash
cd tests
./run-all-tests.sh
```

### Run Specific Tests
```bash
./run-all-tests.sh 1 2 3  # Run only tests 1, 2, and 3
./run-all-tests.sh --quick # Run essential tests only
```

### Test Categories

1. **Infrastructure Tests**: VM availability and connectivity
2. **Gateway Tests**: API functionality and repository serving
3. **Security Tests**: Key distribution and authentication
4. **Publisher Tests**: Content publishing via gateway
5. **Stratum-1 Tests**: Repository replication
6. **Proxy Tests**: HTTP caching functionality
7. **Client Tests**: Repository mounting and access
8. **Workflow Tests**: End-to-end publishing workflow
9. **Performance Tests**: Timing and throughput measurements

## Common Operations

### Check Infrastructure Status
```bash
# On any VM
gateway-status      # (on gateway node)
cvmfs-status       # (on stratum-1)
squid-stats        # (on proxy)
cvmfs-check        # (on client)
```

### Publishing Workflow
```bash
# On publisher node
cvmfs_server transaction software.lab.local              # Start transaction
# Make changes to /cvmfs/software.lab.local/
cvmfs_server publish software.lab.local          # Commit and publish
# Or to cancel:
cvmfs_server abort -f software.lab.local             # Cancel transaction
```

### Client Operations
```bash
# On client node
cvmfs_config probe software.lab.local    # Check repository
cvmfs_config stat software.lab.local     # Show statistics
cvmfs-cache-info                        # Cache information
cvmfs-reload                            # Reload configuration
```

## Additional Resources

- [CVMFS Documentation](https://cvmfs.readthedocs.io/)
- [CVMFS Technical Report](https://cds.cern.ch/record/2667540)
- [CVMFS GitHub Repository](https://github.com/cvmfs/cvmfs)

---

## Appendix: Box Management System

This project includes an box management system that speeds up VM deployment after initial setup by creating pre-configured custom boxes.

### How It Works

**Initial Deployment (Slow Path):**
- Uses base Ubuntu boxes (`bento/ubuntu-22.04`)
- Runs full provisioning scripts (installs packages, configures CVMFS services)
- Takes 10-15 minutes for all 6 VMs

**Custom Box Deployment (Fast Path):**
- Uses pre-configured box files stored in `boxes/` directory
- Skips all provisioning (everything already installed and configured)
- Takes 2-4 minutes for all 6 VMs 

The system automatically detects when custom boxes are available and uses them instead of base boxes with provisioning.

### Box Management Commands

#### Creating Custom Boxes
```bash
# Package all running VMs into custom boxes
scripts/utils/box-manager.sh package-all

# Package specific VM only
scripts/utils/box-manager.sh package cvmfs-gateway-stratum0
```

#### Managing Boxes
```bash
# List available custom boxes and their status
scripts/utils/box-manager.sh list

# Remove all custom boxes (forces fresh rebuild next time)
scripts/utils/box-manager.sh clean

# Show available commands
scripts/utils/box-manager.sh --help
```

### Typical Workflow

#### First Time Setup
```bash
# 1. Initial deployment (slow - 10-15 minutes)
vagrant up

# 2. Create custom boxes after everything is working
scripts/utils/box-manager.sh package-all

# 3. Test fast deployment
vagrant destroy -f
vagrant up  # Now uses custom boxes - only 2-4 minutes!
```

#### Daily Development
```bash
# Fast environment recreation
vagrant destroy -f
vagrant up  # Uses custom boxes automatically
```

#### When Updating Configurations
```bash
# Force fresh provisioning when you modify configs/scripts
scripts/utils/box-manager.sh clean
vagrant up  # Full provisioning with your changes

# Re-package after testing
scripts/utils/box-manager.sh package-all
```

### When to Use Each Approach

**Use Custom Boxes (Fast Path) For:**
- Daily development work
- Testing CVMFS scenarios
- Demonstrations and workshops
- Quick environment recreation
- Reproducible testing environments

**Use Fresh Provisioning (Slow Path) For:**
- Updating configuration files in `config/`
- Modifying provisioning scripts in `provisioning/`
- Testing infrastructure changes
- Getting latest package versions
- Initial project setup

### Technical Details

- **Box Storage**: Custom boxes are stored in `boxes/` directory
- **Box Size**: Each box is approximately 800MB-1.5GB (compressed)
- **Detection**: Vagrantfile automatically detects available custom boxes
- **Fallback**: If custom box doesn't exist, automatically uses base box + provisioning
- **Cleanup**: Custom boxes can be safely deleted - system falls back to provisioning

The box management system maintains full compatibility with standard Vagrant workflows while providing significant performance improvements for repeated deployments.
