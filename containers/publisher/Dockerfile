FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install CVMFS packages (both client and server tools)
RUN apt-get update && apt-get install -y \
    wget curl sudo fuse libfuse2 \
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

# Create publisher user with correct uid/gid
RUN useradd -m -s /bin/bash -u 1000 publisher \
    && echo 'publisher ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
