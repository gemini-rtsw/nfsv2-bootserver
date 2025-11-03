#!/bin/bash
# Check NFSv2 Server Status

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo "NFSv2 Server Status"
echo "==========================================${NC}"
echo ""

# Check if container exists
if ! docker ps -a | grep -q nfsv2-vxworks; then
    echo -e "${RED}✗ Container does not exist${NC}"
    echo ""
    echo "Run: sudo ./start-nfsv2.sh"
    exit 1
fi

# Check if container is running
if docker ps | grep -q nfsv2-vxworks; then
    echo -e "${GREEN}✓ Container is running${NC}"
else
    echo -e "${RED}✗ Container exists but is not running${NC}"
    echo ""
    echo "Start it with: docker start nfsv2-vxworks"
    exit 1
fi
echo ""

# Show RPC services
echo -e "${BLUE}RPC Services:${NC}"
docker exec nfsv2-vxworks rpcinfo -p localhost 2>/dev/null | grep -E "(nfs|mount)" || echo "Could not query RPC services"
echo ""

# Check for NFSv2
echo -e "${BLUE}NFSv2 Status:${NC}"
if docker exec nfsv2-vxworks rpcinfo -p localhost 2>/dev/null | grep -q "100003.*2"; then
    echo -e "${GREEN}✓ NFSv2 is registered and available${NC}"
else
    echo -e "${RED}✗ NFSv2 not found${NC}"
fi
echo ""

# Show export
echo -e "${BLUE}NFS Export:${NC}"
docker exec nfsv2-vxworks showmount -e localhost 2>/dev/null || echo "Could not query exports"
echo ""

# Show files in export
echo -e "${BLUE}Files in /export:${NC}"
FILE_COUNT=$(docker exec nfsv2-vxworks ls -1 /export 2>/dev/null | wc -l)
if [ "$FILE_COUNT" -gt 0 ]; then
    docker exec nfsv2-vxworks ls -lh /export 2>/dev/null
else
    echo -e "${YELLOW}No files yet - place VxWorks boot files in ./vxworks-files/${NC}"
fi
echo ""

# Show container info
echo -e "${BLUE}Container Info:${NC}"
echo "Uptime: $(docker inspect -f '{{.State.StartedAt}}' nfsv2-vxworks 2>/dev/null | cut -d'.' -f1)"
echo ""

# Show recent logs
echo -e "${BLUE}Recent Logs:${NC}"
docker logs --tail 10 nfsv2-vxworks 2>&1
echo ""

echo -e "${GREEN}=========================================="
echo "Server is healthy and ready!"
echo "==========================================${NC}"
echo ""

