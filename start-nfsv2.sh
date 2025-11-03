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

echo -e "${BLUE}=========================================="
echo "NFSv2 Server for VxWorks"
echo "==========================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: This script must be run as root (sudo)${NC}"
    echo "Reason: Need to stop host rpcbind service"
    echo ""
    echo "Run: sudo ./start-nfsv2.sh"
    exit 1
fi

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
    systemctl stop rpcbind
    echo -e "${GREEN}✓ Stopped rpcbind${NC}"
else
    echo -e "${GREEN}✓ rpcbind already stopped${NC}"
fi

if systemctl is-enabled --quiet rpcbind 2>/dev/null; then
    systemctl disable rpcbind
    echo -e "${GREEN}✓ Disabled rpcbind (won't start on boot)${NC}"
fi
echo ""

# Check if image exists, build if needed
echo -e "${YELLOW}Checking for NFSv2 Docker image...${NC}"
if ! docker images | grep -q "nfsv2.*working"; then
    echo -e "${YELLOW}Building NFSv2 image (first time only)...${NC}"
    docker build -t nfsv2:working .
    echo -e "${GREEN}✓ Image built${NC}"
else
    echo -e "${GREEN}✓ Image exists${NC}"
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
    nfsv2:working

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

