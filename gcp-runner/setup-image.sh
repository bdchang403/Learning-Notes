#!/bin/bash
set -e

# 1. Install Dependencies
apt-get update
apt-get install -y docker.io git jq curl wget

# Ensure Docker is running (for pulls)
systemctl start docker
systemctl enable docker

# 2. Install GitHub Runner
mkdir -p /actions-runner && cd /actions-runner
curl -o actions-runner-linux-x64-2.311.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz
tar xzf ./actions-runner-linux-x64-2.311.0.tar.gz
./bin/installdependencies.sh

# 3. Pre-pull Docker Layers (Optimization)
# Pull the images your CI pipeline uses
docker pull node:20-alpine
docker pull nginx:alpine

# 4. Cleanup for Imaging
rm -f .runner .credentials
truncate -s 0 /etc/machine-id
