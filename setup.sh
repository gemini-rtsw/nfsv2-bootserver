#!/bin/bash
# Quick setup script for NFSv2 server

echo "=========================================="
echo "NFSv2 Server Setup for VxWorks"
echo "=========================================="
echo ""

# Create vxworks-files directory
echo "[1/5] Setting up vxworks-files directory..."
if [ ! -d "vxworks-files" ]; then
    mkdir -p vxworks-files
fi

# Try to set permissions, use sudo if needed
if chmod 777 vxworks-files 2>/dev/null; then
    echo "✓ Directory ready"
elif sudo chmod 777 vxworks-files 2>/dev/null; then
    echo "✓ Directory ready (with sudo)"
else
    echo "✓ Directory exists (unable to change permissions, but may be OK)"
fi
echo ""

# Stop host services
echo "[2/5] Stopping host NFS services..."
sudo systemctl stop nfs-server 2>/dev/null || true
sudo systemctl stop rpcbind rpcbind.socket 2>/dev/null || true
sudo systemctl disable nfs-server 2>/dev/null || true
sudo systemctl disable rpcbind rpcbind.socket 2>/dev/null || true
echo "✓ Done"
echo ""

# Stop kernel NFS threads
echo "[3/5] Stopping kernel NFS threads..."
if [ -w /proc/fs/nfsd/threads ]; then
    echo 0 | sudo tee /proc/fs/nfsd/threads > /dev/null
    echo "✓ Stopped kernel NFS threads"
else
    echo "✓ No kernel NFS threads to stop"
fi
echo ""

# Check port 2049
echo "[4/5] Checking port 2049..."
if sudo ss -tulpn | grep -q :2049; then
    echo "⚠ Warning: Port 2049 is still in use!"
    sudo ss -tulpn | grep :2049
    echo ""
    echo "⚠ Container may fail to start. Reboot or manually kill the process using port 2049"
    echo ""
else
    echo "✓ Port 2049 is free"
fi
echo ""

# Start container
echo "[5/5] Starting NFSv2 container..."
docker compose up -d
echo ""

# Wait for container to start
echo "Waiting for container to initialize..."
sleep 5
echo ""

# Show status
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""

# Show container logs
echo "Container logs:"
docker logs nfsv2-vxworks
echo ""

# Show exports
echo "NFS Exports:"
showmount -e localhost 2>/dev/null || echo "⚠ showmount failed - container may still be starting"
echo ""

# Show host IP
echo "Your host IP address(es):"
hostname -I
echo ""

echo "=========================================="
echo "Next Steps:"
echo "=========================================="
echo ""
echo "1. Place your VxWorks files in: ./vxworks-files/"
echo ""
echo "2. From VxWorks, mount using:"
echo "   mount \"YOUR_HOST_IP\", \"/export\", \"/tgtsvr\""
echo ""
echo "3. Check logs anytime with:"
echo "   docker logs nfsv2-vxworks"
echo ""
echo "=========================================="

