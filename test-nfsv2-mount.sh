#!/bin/bash
# Test NFSv2 mounting from a test client container

set -e

echo "=========================================="
echo "NFSv2 Mount Test Suite"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if server is running
if ! docker ps | grep -q nfsv2-vxworks; then
    echo -e "${RED}✗ NFSv2 server container not running${NC}"
    echo ""
    echo "Start it first:"
    echo "  docker run -d --name nfsv2-vxworks --privileged --network host \\"
    echo "    -v \$(pwd)/vxworks-files:/export nfsv2:working"
    exit 1
fi

echo -e "${GREEN}✓ NFSv2 server is running${NC}"
echo ""

# Get server IP (when using host network, it's localhost)
# For bridge network, we'd need to inspect
SERVER_IP="host.docker.internal"  # macOS Docker Desktop
if [ "$(uname)" = "Linux" ]; then
    # On Linux, server is on host network, so use host IP
    SERVER_IP="172.17.0.1"  # Docker bridge gateway
fi

echo "Server IP: $SERVER_IP"
echo ""

# Build test client
echo "Building NFSv2 test client container..."
docker build -f Dockerfile.nfsv2-test-client -t nfsv2-test-client . > /dev/null 2>&1
echo -e "${GREEN}✓ Test client built${NC}"
echo ""

# Run test
echo "=========================================="
echo "Running NFSv2 Mount Test"
echo "=========================================="
echo ""

# Try to get actual server container IP
SERVER_CONTAINER_IP=$(docker inspect nfsv2-vxworks 2>/dev/null | grep '"IPAddress"' | head -1 | awk -F'"' '{print $4}')
if [ -n "$SERVER_CONTAINER_IP" ] && [ "$SERVER_CONTAINER_IP" != "" ]; then
    echo "Found server container IP: $SERVER_CONTAINER_IP"
    TEST_IP="$SERVER_CONTAINER_IP"
else
    echo "Server using host network, will test from another container..."
    TEST_IP="172.17.0.1"
fi

# Run test client
echo ""
echo "Starting test client..."
echo ""

docker run --rm --privileged \
    nfsv2-test-client \
    /test-nfsv2.sh "$TEST_IP"

EXIT_CODE=$?

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}=========================================="
    echo "✅ NFSv2 MOUNT TEST PASSED!"
    echo "==========================================${NC}"
    echo ""
    echo "Your NFSv2 server is working correctly!"
    echo "VxWorks should be able to mount and boot from it."
else
    echo -e "${RED}=========================================="
    echo "✗ NFSv2 MOUNT TEST FAILED"
    echo "==========================================${NC}"
    echo ""
    echo "Check the error messages above."
fi

echo ""
echo "Server logs:"
docker logs --tail 20 nfsv2-vxworks

