#!/bin/bash

echo "Starting NFSv2 Userspace Server (unfsd)"
echo "========================================"

# Start rpcbind
echo "Starting rpcbind..."
rpcbind -w

# Wait for rpcbind to be ready
sleep 2

# Start unfsd (userspace NFS daemon) with NFSv2 support
echo "Starting unfsd (userspace NFS server with NFSv2)..."
/usr/local/sbin/unfsd -d -e /nfs/vxworks -p -u &

# Wait for unfsd to register
sleep 3

# Show registered RPC services
echo ""
echo "Registered RPC services:"
rpcinfo -p localhost

# Verify NFS mount daemon is registered
if rpcinfo -p localhost | grep -q mount; then
    echo ""
    echo "✓ NFS mount daemon registered successfully"
else
    echo ""
    echo "⚠ Warning: NFS mount daemon not registered"
fi

# Verify NFS server is registered
if rpcinfo -p localhost | grep -q nfs; then
    echo "✓ NFS server registered successfully"
else
    echo "⚠ Warning: NFS server not registered"
fi

# Test showmount
echo ""
echo "Testing showmount:"
showmount -e localhost || echo "showmount test failed"

# Start rsh/rlogin services
echo ""
echo "Starting rsh/rlogin services..."
systemctl start rsh.socket rlogin.socket 2>/dev/null || true

echo ""
echo "============================================"
echo "NFSv2 Userspace Server Ready!"
echo "============================================"
echo ""
echo "NFS Export: /nfs/vxworks"
echo "Protocol: NFSv2 and NFSv3 (userspace)"
echo ""
echo "Mount from VxWorks:"
echo "  mount \"<host_ip>\", \"/nfs/vxworks\", \"/tgtsvr\""
echo ""
echo "Mount from Linux:"
echo "  mount -t nfs -o vers=2 <host_ip>:/nfs/vxworks /mnt/test"
echo ""
echo "rsh/rcp services enabled (ports 512-514)"
echo ""
echo "SECURITY WARNING: This container uses insecure legacy protocols."
echo "Only use on isolated networks for legacy system support."
echo "============================================"
echo ""

# Keep container running
tail -f /dev/null

