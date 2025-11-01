#!/bin/bash
# Stop script for NFSv2 server

set -e

echo "=========================================="
echo "Stopping NFSv2 Server"
echo "=========================================="
echo ""

# Stop container
echo "[1/2] Stopping container..."
docker compose down
echo "✓ Container stopped"
echo ""

# Ask if they want to re-enable host services
echo "[2/2] Do you want to re-enable host NFS services? (y/n)"
read -r response

if [[ "$response" =~ ^[Yy]$ ]]; then
    echo "Re-enabling host NFS services..."
    sudo systemctl enable rpcbind rpcbind.socket
    sudo systemctl start rpcbind rpcbind.socket
    echo "✓ Host services re-enabled"
else
    echo "✓ Host services remain disabled"
fi

echo ""
echo "=========================================="
echo "NFSv2 Server Stopped"
echo "=========================================="

