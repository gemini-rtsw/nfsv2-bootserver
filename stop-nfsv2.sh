#!/bin/bash
# Stop NFSv2 Server

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Reset terminal color on exit
trap 'echo -ne "${NC}"' EXIT

echo -e "${BLUE}=========================================="
echo "Stopping NFSv2 Server"
echo "==========================================${NC}"
echo ""

if docker ps | grep -q nfsv2-vxworks; then
    echo -e "${YELLOW}Stopping container...${NC}"
    docker stop nfsv2-vxworks
    echo -e "${GREEN}✓ Container stopped${NC}"
else
    echo "Container is not running"
fi
echo ""

echo -e "${BLUE}Options:${NC}"
echo "To remove container completely:  docker rm nfsv2-vxworks"
echo "To start again:                  sudo ./start-nfsv2.sh"
echo "To re-enable host rpcbind:       sudo systemctl enable rpcbind && sudo systemctl start rpcbind"
echo ""

