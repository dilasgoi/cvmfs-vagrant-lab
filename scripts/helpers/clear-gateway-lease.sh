#!/bin/bash
# Helper script to clear gateway leases
# Run this on the gateway node if you have stuck leases

echo "Clearing all gateway leases..."
sudo systemctl restart cvmfs-gateway
echo "Gateway restarted. All leases cleared."
