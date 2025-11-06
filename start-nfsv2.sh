#!/bin/bash
# NFSv2 Server Startup Script for Linux
# Simple script to start the NFSv2 server for VxWorks boot

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Reset terminal color on exit
trap 'tput sgr0' EXIT

echo -e "${BLUE}=========================================="
echo "NFSv2 Server for VxWorks"
echo "==========================================${NC}"
echo ""

# Get the directory where script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Create vxworks-files directory if it doesn't exist
if [ ! -d "vxworks-files" ]; then
    echo -e "${YELLOW}Creating vxworks-files directory...${NC}"
    mkdir -p vxworks-files
    chmod 777 vxworks-files
    echo -e "${GREEN}✓ Created vxworks-files/${NC}"
else
    echo -e "${GREEN}✓ vxworks-files directory exists${NC}"
fi
echo ""

# Stop host rpcbind (required for network_mode: host)
echo -e "${YELLOW}Stopping host rpcbind service...${NC}"
if systemctl is-active --quiet rpcbind; then
    sudo systemctl stop rpcbind
    echo -e "${GREEN}✓ Stopped rpcbind${NC}"
else
    echo -e "${GREEN}✓ rpcbind already stopped${NC}"
fi

if systemctl is-enabled --quiet rpcbind 2>/dev/null; then
    sudo systemctl disable rpcbind
    echo -e "${GREEN}✓ Disabled rpcbind (won't start on boot)${NC}"
fi
echo ""

# GitLab registry configuration
GITLAB_REGISTRY="registry.gitlab.com"
GITLAB_PROJECT="hstecher/docker-nfsv2"
IMAGE_NAME="nfsv2"
IMAGE_TAG="latest"
FULL_IMAGE_NAME="${GITLAB_REGISTRY}/${GITLAB_PROJECT}/${IMAGE_NAME}:${IMAGE_TAG}"

# Check if image exists, pull if needed
echo -e "${YELLOW}Checking for NFSv2 Docker image from GitLab registry...${NC}"
if ! docker images | grep -q "${GITLAB_PROJECT}/${IMAGE_NAME}"; then
    echo -e "${YELLOW}Pulling NFSv2 image from GitLab registry...${NC}"
    echo "  Image: ${FULL_IMAGE_NAME}"
    docker pull ${FULL_IMAGE_NAME}
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Failed to pull image from GitLab registry${NC}"
        echo ""
        echo "Make sure you are logged in to GitLab registry:"
        echo "  docker login ${GITLAB_REGISTRY}"
        echo ""
        echo "Or build and push the image first:"
        echo "  ./build-nfsv2.sh"
        exit 1
    fi
    echo -e "${GREEN}✓ Image pulled${NC}"
else
    echo -e "${YELLOW}Checking for image updates...${NC}"
    docker pull ${FULL_IMAGE_NAME} || echo -e "${YELLOW}Note: Could not pull latest (may be offline)${NC}"
    echo -e "${GREEN}✓ Image available${NC}"
fi
echo ""

# Stop and remove existing container if running
if docker ps -a | grep -q nfsv2-vxworks; then
    echo -e "${YELLOW}Removing existing container...${NC}"
    docker rm -f nfsv2-vxworks > /dev/null 2>&1
    echo -e "${GREEN}✓ Removed old container${NC}"
    echo ""
fi

# Start the container
echo -e "${YELLOW}Starting NFSv2 server container...${NC}"
docker run -d \
    --name nfsv2-vxworks \
    --privileged \
    --network host \
    -v "${SCRIPT_DIR}/vxworks-files:/export" \
    --restart unless-stopped \
    ${FULL_IMAGE_NAME}

echo -e "${GREEN}✓ Container started${NC}"
echo ""

# Wait for server to start
echo -e "${YELLOW}Waiting for server to initialize...${NC}"
sleep 5
echo ""

# Show logs
echo -e "${BLUE}=========================================="
echo "Server Status"
echo "==========================================${NC}"
docker logs nfsv2-vxworks 2>&1 | tail -20
echo ""

# Get host IP addresses
echo -e "${BLUE}=========================================="
echo "Network Information"
echo "==========================================${NC}"
echo "Your server is accessible at these IP addresses:"
echo ""
ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | while read ip; do
    echo -e "  ${GREEN}$ip${NC}"
done
echo ""

# Show VxWorks mount command
echo -e "${BLUE}=========================================="
echo "VxWorks Mount Command"
echo "==========================================${NC}"
HOST_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)
if [ -n "$HOST_IP" ]; then
    echo -e "From VxWorks shell, run:"
    echo ""
    echo -e "  ${GREEN}-> mount \"${HOST_IP}\", \"/export\", \"/tgtsvr\"${NC}"
    echo ""
    echo "Then access files at: /tgtsvr/"
else
    echo "Could not determine host IP. Use your server's IP address."
fi
echo ""

# Show file location
echo -e "${BLUE}=========================================="
echo "File Management"
echo "==========================================${NC}"
echo "Place your VxWorks boot files in:"
echo -e "  ${GREEN}${SCRIPT_DIR}/vxworks-files/${NC}"
echo ""
echo "Example:"
echo "  cp /path/to/vxWorks ${SCRIPT_DIR}/vxworks-files/"
echo "  cp /path/to/bootrom.bin ${SCRIPT_DIR}/vxworks-files/"
echo ""

# Show useful commands
echo -e "${BLUE}=========================================="
echo "Useful Commands"
echo "==========================================${NC}"
echo "View logs:           docker logs -f nfsv2-vxworks"
echo "Check RPC services:  docker exec nfsv2-vxworks rpcinfo -p localhost"
echo "Stop server:         docker stop nfsv2-vxworks"
echo "Start server:        docker start nfsv2-vxworks"
echo "Restart server:      docker restart nfsv2-vxworks"
echo ""

echo -e "${GREEN}=========================================="
echo "✅ NFSv2 Server is Running!"
echo "==========================================${NC}"
echo ""

