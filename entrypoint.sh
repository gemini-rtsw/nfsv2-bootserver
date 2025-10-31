#!/bin/bash

# Start rpcbind
echo "Starting rpcbind..."
rpcbind -w

# Wait for rpcbind to be ready
sleep 2

# Check available NFS versions
echo "Checking available NFS versions..."
cat /proc/fs/nfsd/versions 2>/dev/null || echo "NFS versions info not available"

# Start NFS services (allow v2 and v3, disable v4 for legacy compatibility)
echo "Starting NFS services..."
rpc.nfsd -N 4 8
rpc.mountd -N 4
rpc.statd

# Export NFS shares
echo "Exporting NFS shares..."
exportfs -ra

# Show current exports
echo "Current NFS exports:"
exportfs -v

# Start systemd sockets for rsh/rlogin
echo "Starting rsh/rlogin services via systemd..."
systemctl start rsh.socket rlogin.socket 2>/dev/null || true

echo ""
echo "============================================"
echo "NFS v2 and rsh/rcp server is ready!"
echo "============================================"
echo ""
echo "NFS Export: /nfs/vxworks"
echo "Mount on VxWorks: mount \"<host_ip>\", \"/nfs/vxworks\", \"/tgtsvr\""
echo ""
echo "rsh/rcp services enabled (ports 512-514)"
echo ""
echo "SECURITY WARNING: This container uses insecure legacy protocols."
echo "Only use on isolated networks for legacy system support."
echo "============================================"
echo ""

# Keep the container running
tail -f /dev/null

