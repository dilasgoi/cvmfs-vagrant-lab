#!/bin/bash
# Run CVMFS publisher container
# Usage: ./run-container.sh [GITHUB_REPO GITHUB_TOKEN]

# Build if needed
if ! podman images | grep -q "localhost/cvmfs-publisher"; then
    echo "Building container..."
    cd /vagrant/containers/publisher
    podman build -t localhost/cvmfs-publisher .
fi

# Stop any existing
podman stop cvmfs-publisher 2>/dev/null || true
podman rm cvmfs-publisher 2>/dev/null || true

# Run container
echo "Starting container..."
podman run -d \
    --name cvmfs-publisher \
    --privileged \
    --device /dev/fuse \
    -e REPOSITORY_NAME=software.lab.local \
    -e GATEWAY_IP=192.168.58.10 \
    -e GATEWAY_PORT=4929 \
    -e GITHUB_REPO="$1" \
    -e GITHUB_TOKEN="$2" \
    localhost/cvmfs-publisher

echo "Container started!"
echo "View logs: podman logs -f cvmfs-publisher"
echo "Get shell: podman exec -it cvmfs-publisher bash"
