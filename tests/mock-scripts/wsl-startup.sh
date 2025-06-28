#!/bin/bash
# WSL Mock Startup Script
# This script simulates WSL startup behavior for testing

echo "WSL Mock Environment Starting..."

# Set up environment variables
export WSL_DISTRO_NAME="Ubuntu-22.04"
export WSL_VERSION=2
export USER=testuser
export HOME=/home/testuser

# Create any missing directories
mkdir -p /home/testuser/.config
mkdir -p /home/testuser/.ssh
mkdir -p /home/testuser/projects
mkdir -p /home/testuser/scripts

# Set up basic environment
cd /home/testuser

# Start bash session
exec /bin/bash 