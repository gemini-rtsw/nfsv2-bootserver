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

# Note: Using ipvlan network, so host rpcbind can stay running
echo -e "${GREEN}✓ Host rpcbind can remain active (using ipvlan network isolation)${NC}"
echo ""

# Network configuration
NETWORK_NAME="nfs-ipvlan"
CONTAINER_IP="10.2.2.147"
SUBNET="10.2.2.0/24"
GATEWAY="10.2.2.1"
PARENT_INTERFACE="ens33"

# GitLab registry configuration
GITLAB_REGISTRY="registry.gitlab.com"
GITLAB_PROJECT="hstecher/docker-nfsv2"
IMAGE_NAME="nfsv2"
IMAGE_TAG="latest"
FULL_IMAGE_NAME="${GITLAB_REGISTRY}/${GITLAB_PROJECT}/${IMAGE_NAME}:${IMAGE_TAG}"

# Create ipvlan network if it doesn't exist
echo -e "${YELLOW}Checking ipvlan network...${NC}"
if ! docker network ls | grep -q ${NETWORK_NAME}; then
    echo -e "${YELLOW}Creating ipvlan network ${NETWORK_NAME}...${NC}"
    docker network create -d ipvlan \
        --subnet=${SUBNET} \
        --gateway=${GATEWAY} \
        -o parent=${PARENT_INTERFACE} \
        -o ipvlan_mode=l2 \
        ${NETWORK_NAME}
    echo -e "${GREEN}✓ IPVLAN network created (shares host MAC address)${NC}"
else
    echo -e "${GREEN}✓ IPVLAN network already exists${NC}"
fi
echo ""

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
echo -e "${BLUE}Container will be accessible at: ${CONTAINER_IP}${NC}"
docker run -d \
    --name nfsv2-vxworks \
    --network ${NETWORK_NAME} \
    --ip ${CONTAINER_IP} \
    --privileged \
    -v "/export:/export:rw" \
    -v "/etc/localtime:/etc/localtime:ro" \
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
echo -e "${YELLOW}NFSv2 Container (for VxWorks):${NC}"
echo -e "  ${GREEN}${CONTAINER_IP}${NC}"
echo ""
echo -e "${YELLOW}Host (for NFSv3/4):${NC}"
HOST_IP=$(ip -4 addr show ${PARENT_INTERFACE} | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
if [ -n "$HOST_IP" ]; then
    echo -e "  ${GREEN}${HOST_IP}${NC}"
else
    echo "  Could not determine host IP"
fi
echo ""

# Show VxWorks mount command
echo -e "${BLUE}=========================================="
echo "VxWorks Mount Command (NFSv2)"
echo "==========================================${NC}"
echo -e "From VxWorks shell, run:"
echo ""
echo -e "  ${GREEN}-> nfsMount(\"${CONTAINER_IP}\", \"/export\", \"/tgtsvr\")${NC}"
echo ""
echo "Then access files at: /tgtsvr/"
echo ""

# Show modern client mount command
echo -e "${BLUE}=========================================="
echo "Modern Client Mount (NFSv3/4 - requires host NFS setup)"
echo "==========================================${NC}"
if [ -n "$HOST_IP" ]; then
    echo -e "From Linux client, run:"
    echo ""
    echo -e "  ${GREEN}mount -t nfs ${HOST_IP}:/export /mnt${NC}"
    echo ""
    echo -e "${YELLOW}Note: Configure host /etc/exports for NFSv3/4 access${NC}"
else
    echo "Could not determine host IP"
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

