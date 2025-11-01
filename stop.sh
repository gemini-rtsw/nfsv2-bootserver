#!/bin/bash
# Stop script for NFSv2 server

echo "=========================================="
echo "Stopping NFSv2 Server"
echo "=========================================="
echo ""

# Stop container
echo "Stopping container..."
docker compose down
echo "✓ Container stopped"
echo ""

echo "=========================================="
echo "NFSv2 Server Stopped"
echo "=========================================="
echo ""
echo "Note: Host NFS services remain disabled."
echo "To re-enable them, run:"
echo "  sudo systemctl enable rpcbind rpcbind.socket"
echo "  sudo systemctl start rpcbind rpcbind.socket"
echo "=========================================="

