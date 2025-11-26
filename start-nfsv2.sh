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
echo "NFSv2 + TFTP Server for RTEMS VME"
echo "==========================================${NC}"
echo ""

# Get the directory where script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Create /gem_sw on host if it doesn't exist (using container)
if [ ! -d "/gem_sw" ]; then
    echo -e "${YELLOW}Creating /gem_sw directory on host...${NC}"
    docker run --rm --privileged -v /:/host ${FULL_IMAGE_NAME} sh -c "mkdir -p /host/gem_sw && chmod 777 /host/gem_sw"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Created /gem_sw on host${NC}"
    else
        echo -e "${RED}✗ Failed to create /gem_sw${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ /gem_sw directory exists on host${NC}"
fi
echo ""

# Note: Using ipvlan network, so host rpcbind can stay running
echo -e "${GREEN}✓ Host rpcbind can remain active (using ipvlan network isolation)${NC}"
echo ""

# Network configuration
NETWORK_NAME="nfs-ipvlan"
CONTAINER_IP="10.2.2.145"
SUBNET="10.2.2.0/24"
GATEWAY="10.2.2.1"
PARENT_INTERFACE="ens33"

# GitLab registry configuration
GITLAB_REGISTRY="registry.gitlab.com"
GITLAB_PROJECT="nsf-noirlab/gemini/rtsw/nfsv2-bootserver"
IMAGE_NAME="nfsv2"
IMAGE_TAG="TCS"
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
if docker ps -a | grep -q nfsv2-rtems; then
    echo -e "${YELLOW}Removing existing container...${NC}"
    docker rm -f nfsv2-rtems > /dev/null 2>&1
    echo -e "${GREEN}✓ Removed old container${NC}"
    echo ""
fi

# Start the container
echo -e "${YELLOW}Starting NFSv2 + TFTP server container...${NC}"
echo -e "${BLUE}Container will be accessible at: ${CONTAINER_IP}${NC}"
docker run -d \
    --name nfsv2-rtems \
    --network ${NETWORK_NAME} \
    --ip ${CONTAINER_IP} \
    --privileged \
    -v "/gem_sw:/gem_sw:rw" \
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
docker logs nfsv2-rtems 2>&1 | tail -20
echo ""

# Get host IP addresses
echo -e "${BLUE}=========================================="
echo "Network Information"
echo "==========================================${NC}"
echo -e "${YELLOW}Docker Container IP:${NC}"
echo -e "  ${GREEN}${CONTAINER_IP}${NC}"
echo ""
echo -e "${YELLOW}Host IP:${NC}"
HOST_IP=$(ip -4 addr show ${PARENT_INTERFACE} | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
if [ -n "$HOST_IP" ]; then
    echo -e "  ${GREEN}${HOST_IP}${NC}"
else
    echo "  Could not determine host IP"
fi
echo ""
echo -e "${YELLOW}RTEMS VME Clients:${NC}"
echo -e "  ${GREEN}10.1.2.177${NC} (Client 1)"
echo -e "  ${GREEN}10.2.2.104${NC} (Client 2)"
echo ""

# Show RTEMS mount command
echo -e "${BLUE}=========================================="
echo "RTEMS Mount Command (NFSv2)"
echo "==========================================${NC}"
echo -e "From RTEMS shell, run:"
echo ""
echo -e "  ${GREEN}mount -t nfs -o nfsvers=2,proto=udp ${CONTAINER_IP}:/gem_sw /mnt/nfs${NC}"
echo ""
echo "Then access files at: /mnt/nfs/"
echo ""

# Show TFTP boot command
echo -e "${BLUE}=========================================="
echo "RTEMS TFTP Boot"
echo "==========================================${NC}"
echo -e "TFTP and NFS both serve from: ${GREEN}/gem_sw${NC}"
echo ""
echo "Boot file location:"
echo -e "  ${GREEN}/gem_sw/prod/redirector/tcs-mk-ioc${NC}"
echo ""
echo "From VME bootloader (PPC-Bug), the boot will use:"
echo -e "  Server IP: ${GREEN}${CONTAINER_IP}${NC}"
echo -e "  Boot file: ${GREEN}/gem_sw/prod/redirector/tcs-mk-ioc${NC}"
echo ""

# Show file location
echo -e "${BLUE}=========================================="
echo "File Management"
echo "==========================================${NC}"
echo "Both NFS and TFTP serve from the same directory:"
echo -e "  ${GREEN}/gem_sw${NC} (mounted from host)"
echo ""
echo "Boot files are located at:"
echo -e "  ${GREEN}/gem_sw/prod/redirector/tcs-mk-ioc${NC}"
echo -e "  ${GREEN}/gem_sw/prod/redirector/tcs-mk-ioc.cmd${NC}"
echo ""

# Show useful commands
echo -e "${BLUE}=========================================="
echo "Useful Commands"
echo "==========================================${NC}"
echo "View logs:           docker logs -f nfsv2-rtems"
echo "Check RPC services:  docker exec nfsv2-rtems rpcinfo -p localhost"
echo "Check boot files:    ls -la /gem_sw/prod/redirector/"
echo "Stop server:         docker stop nfsv2-rtems"
echo "Start server:        docker start nfsv2-rtems"
echo "Restart server:      docker restart nfsv2-rtems"
echo ""

echo -e "${GREEN}=========================================="
echo "✅ NFSv2 + TFTP Server is Running!"
echo "==========================================${NC}"
echo ""

