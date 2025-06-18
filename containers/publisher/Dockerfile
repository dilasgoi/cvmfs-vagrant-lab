FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install CVMFS packages and dependencies
RUN apt-get update && apt-get install -y \
    wget curl sudo libfuse2 fuse-overlayfs attr libcap2-bin \
    && wget -q https://ecsft.cern.ch/dist/cvmfs/cvmfs-release/cvmfs-release-latest_all.deb \
    && dpkg -i cvmfs-release-latest_all.deb \
    && apt-get update \
    && apt-get install -y cvmfs cvmfs-server \
    && rm -f cvmfs-release-latest_all.deb \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install archspec for architecture detection
RUN apt-get update && apt-get install -y python3-pip \
    && pip3 install archspec \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create necessary directories
RUN mkdir -p /cvmfs /var/spool/cvmfs /var/lib/cvmfs /srv/cvmfs

# Create publisher user matching the host vagrant user (uid 1000)
RUN useradd -m -s /bin/bash -u 1000 publisher \
    && echo 'publisher ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Configure CVMFS for container environment
RUN printf '%s\n' \
    '# Container-optimized settings' \
    'CVMFS_UNION_FS_TYPE=overlayfs' \
    'CVMFS_UNION_MOUNT_CMD=/usr/bin/fuse-overlayfs' \
    'CVMFS_DONT_CHECK_OVERLAYFS_VERSION=true' \
    'CVMFS_AUTO_REPAIR_MOUNTPOINT=false' \
    'CVMFS_FORCE_REMOUNT_WARNING=false' \
    > /etc/cvmfs/server.local

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Default to root user (can be overridden with --user)
USER root

ENTRYPOINT ["/entrypoint.sh"]
