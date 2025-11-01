# NFSv2 Server for VxWorks Tornado 2.0

Docker-based NFS server using unfsd (userspace NFS) to provide NFSv2 support for VxWorks Tornado 2.0 systems on Rocky 9 hosts.

## Quick Setup

### 1. Prepare the Host (Rocky Linux 8/9)

```bash
# Clone/pull the repo
cd /path/to/docker-nfsv2
git pull

# Create directory for VxWorks files
mkdir -p vxworks-files
chmod 777 vxworks-files

# Stop host NFS services (required for network_mode: host)
sudo systemctl stop nfs-server rpcbind rpcbind.socket
sudo systemctl disable nfs-server rpcbind rpcbind.socket

# Stop kernel NFS threads if running
echo 0 | sudo tee /proc/fs/nfsd/threads

# Verify port 2049 is free
sudo ss -tulpn | grep 2049
```

### 2. Start the NFS Server

```bash
# Option A: Use the setup script (recommended)
./setup.sh

# Option B: Manual start
docker compose up -d

# Check it's running
docker logs nfsv2-vxworks

# Verify NFS is working
showmount -e localhost
# Should show: /export *

# Check RPC services
rpcinfo -p localhost | grep 100003
```

### Stopping the Server

```bash
# Use the stop script
./stop.sh

# Or manually
docker compose down
```

Expected output:
```
UNFS3 unfsd 0.9.22 (C) 2006, Pascal Schmidt
/export: ip 0.0.0.0 mask 0.0.0.0 options 5
```

### 3. Get Your Host IP

```bash
hostname -I
# Example: 10.26.70.200
```

### 4. Mount from VxWorks

From your VxWorks Tornado 2.0 shell:

```vxworks
mount "10.26.70.200", "/export", "/tgtsvr"
ls "/tgtsvr"
```

Replace `10.26.70.200` with your actual host IP.

## Directory Structure

```
.
├── docker-compose.yml          # Main configuration (uses mitcdh/unfs3)
├── setup.sh                    # Automated setup script
├── stop.sh                     # Stop script
├── vxworks-files/             # Your VxWorks boot images go here
│   └── (place your .out files, kernels, etc. here)
├── README.md                  # This file
└── README-PREBUILT.md         # Detailed troubleshooting guide
```

## Adding VxWorks Files

```bash
# Copy your boot images
cp /path/to/vxWorks vxworks-files/
cp /path/to/bootrom.sys vxworks-files/

# Verify permissions
ls -la vxworks-files/
```

## Testing from Linux

```bash
# Test mount with NFSv3 (Rocky 8/9 doesn't support v2 mounting)
sudo mkdir -p /mnt/nfs-test
sudo mount -t nfs -o vers=3 localhost:/export /mnt/nfs-test
ls -la /mnt/nfs-test
sudo umount /mnt/nfs-test
```

**Note:** Even though the Linux host can only mount with NFSv3, VxWorks has its own NFS client and should be able to use NFSv2.

## Troubleshooting

### Container won't start - "Address already in use"

```bash
# Check what's using port 2049
sudo ss -tulpn | grep 2049

# Stop kernel NFS
echo 0 | sudo tee /proc/fs/nfsd/threads

# Stop services
sudo systemctl stop nfs-server rpcbind rpcbind.socket

# Restart container
docker compose restart
```

### Container keeps restarting

```bash
# Check logs
docker logs nfsv2-vxworks

# Verify host services are stopped
systemctl status nfs-server rpcbind
```

### Can't mount from VxWorks

1. **Check NFS is running:**
   ```bash
   showmount -e <host-ip>
   ```

2. **Check firewall:**
   ```bash
   sudo firewall-cmd --list-all
   # If needed:
   sudo firewall-cmd --add-service=nfs --permanent
   sudo firewall-cmd --add-service=rpc-bind --permanent
   sudo firewall-cmd --reload
   ```

3. **Verify network connectivity:**
   ```bash
   # From VxWorks, ping the host
   ping "10.26.70.200"
   ```

4. **Check RPC services:**
   ```bash
   rpcinfo -p <host-ip>
   # Should show mountd and nfs services
   ```

## NFS Protocol Version

The container uses `mitcdh/unfs3` which provides:
- **Advertised:** NFSv3 (shown in rpcinfo)
- **Supported:** NFSv2 and NFSv3 (unfsd 0.9.22 supports both)
- **VxWorks:** Should negotiate NFSv2 automatically

Even though `rpcinfo` only shows version 3, unfsd was built to support version 2. VxWorks will negotiate the protocol version when connecting.

## Container Management

```bash
# Stop the container
docker compose down

# Restart the container
docker compose restart

# View logs
docker compose logs -f

# Check status
docker compose ps
```

## Important Notes

1. **Host networking required:** The container uses `network_mode: host` for proper NFS/RPC operation
2. **Privileged mode required:** NFS server needs elevated privileges
3. **Port conflicts:** Host NFS services must be stopped before starting container
4. **Export path:** The container exports `/export`, mapped to `./vxworks-files`

## Security Warning

⚠️ **This setup uses legacy, insecure protocols (NFSv2, no authentication) and should only be used on isolated lab networks for VxWorks Tornado 2.0 support.**

## Support

See `README-PREBUILT.md` for detailed troubleshooting and alternative configurations.

## What This Provides

✅ NFSv2 userspace server (via unfsd)  
✅ Works on Rocky 9 (kernel NFSv2 not required)  
✅ Compatible with VxWorks Tornado 2.0  
✅ Docker-based (easy deployment)  
✅ Host networking (proper RPC operation)
