#!/bin/bash

# Check if rpcbind is already running (host mode)
if pgrep -x rpcbind > /dev/null; then
    echo "rpcbind already running (using host's rpcbind)"
else
    echo "Starting rpcbind..."
    rpcbind -w
    sleep 2
fi

# Ensure rpcbind is accessible
echo "Waiting for rpcbind to be ready..."
sleep 2

# Check available NFS versions
echo "Checking available NFS versions..."
cat /proc/fs/nfsd/versions 2>/dev/null || echo "NFS versions info not available"

# Load nfsd kernel module
echo "Loading nfsd kernel module..."
modprobe nfsd 2>/dev/null || true

# Mount nfsd filesystem
mount -t nfsd nfsd /proc/fs/nfsd 2>/dev/null || true

# Start NFS statd (needs to run first)
echo "Starting rpc.statd..."
rpc.statd

# Wait a moment
sleep 1

# Start NFS server daemon (this spawns kernel threads and must complete before mountd)
echo "Starting rpc.nfsd..."
rpc.nfsd -N 4 8

# Verify nfsd is running
echo "Checking nfsd threads..."
ps -ef | grep '\[nfsd\]' || echo "Warning: nfsd kernel threads may not be running"

# Wait for nfsd to fully initialize
sleep 3

# Start NFS mount daemon (foreground mode, will be backgrounded by &)
echo "Starting rpc.mountd..."
rpc.mountd -N 4 -d all &

# Wait for mountd to register with rpcbind
sleep 3

# Verify mountd registered
echo "Verifying mountd registration..."
rpcinfo -p localhost | grep mountd || echo "Warning: mountd not registered with rpcbind"

# Export NFS shares (after mountd is running)
echo "Exporting NFS shares..."
exportfs -ra

# Verify exports are registered
sleep 2

# Show current exports
echo "Current NFS exports:"
exportfs -v

# Verify RPC services are registered
echo ""
echo "Registered RPC services:"
rpcinfo -p localhost 2>/dev/null | grep -E '(mountd|nfs|portmapper)' || echo "Warning: RPC services may not be fully registered yet"

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

