# NFSv2 Server Using Pre-built unfs3 Docker Image

## Solution

This uses a pre-built Docker image (`mitcdh/unfs3`) that already has unfsd/unfs3 compiled and working. This is the **easiest and most reliable** solution for running NFSv2 on Rocky 9.

## Quick Start

1. **On your Rocky 9/8 Linux system:**

```bash
cd /path/to/nfsv2
git pull

# Create directory for VxWorks files
mkdir -p vxworks-files

# Stop host rpcbind (required for network_mode: host)
sudo systemctl stop rpcbind
sudo systemctl disable rpcbind

# Start the container
docker compose -f docker-compose-prebuilt.yml up -d

# Check logs
docker logs nfsv2-vxworks-prebuilt
```

2. **Check NFS is running:**

```bash
# From the host
docker exec nfsv2-vxworks-prebuilt showmount -e localhost

# Should show: /export *
```

3. **Test mount from another system:**

```bash
# Create mount point
sudo mkdir -p /mnt/nfs-test

# Mount with NFSv2
sudo mount -t nfs -o vers=2 <rocky-host-ip>:/export /mnt/nfs-test

# Test
echo "test" | sudo tee /mnt/nfs-test/test.txt
ls -la /mnt/nfs-test/
```

4. **From VxWorks Tornado 2.0:**

```vxworks
mount "<rocky-host-ip>", "/export", "/tgtsvr"
ls "/tgtsvr"
```

## How It Works

- Uses `mitcdh/unfs3` Docker image (pre-compiled unfs3)
- Exports `/export` directory as NFS share
- Maps `./vxworks-files` to `/export`
- Runs with `network_mode: host` for proper NFS operation
- Supports NFSv2 and NFSv3

## Important Notes

1. **Host rpcbind must be stopped** when using `network_mode: host`
2. The container needs `privileged: true` for NFS operations
3. The export directory is `/export` (not `/nfs/vxworks`)
4. Put your VxWorks boot files in `./vxworks-files/`

## Troubleshooting

### Container won't start
```bash
# Check if host rpcbind is running
systemctl status rpcbind

# Stop it
sudo systemctl stop rpcbind
sudo systemctl disable rpcbind

# Restart container
docker compose -f docker-compose-prebuilt.yml restart
```

### Can't mount from client
```bash
# Check if NFS is visible
rpcinfo -p <rocky-host-ip>

# Should show mountd and nfs services

# Try with explicit version
sudo mount -t nfs -o vers=2,nfsvers=2 <rocky-host-ip>:/export /mnt/test
```

### Permissions issues
```bash
# Make sure vxworks-files is writable
chmod 777 vxworks-files

# Check in container
docker exec nfsv2-vxworks-prebuilt ls -la /export
```

## Alternative Images

If `mitcdh/unfs3` doesn't work, try these alternatives:

- `voobscout/unfs3`
- `forumi0721/alpine-unfs3`  
- `nimbix/unfs3`

Just change the image in docker-compose-prebuilt.yml:

```yaml
image: voobscout/unfs3  # or another image
```

## For macOS Testing

macOS has port conflicts. Use port mapping instead:

```bash
# Stop any container using port 111
docker rm -f nfsv2-vxworks-prebuilt

# Run without host networking
docker run -d \
  --name nfsv2-vxworks-prebuilt \
  --privileged \
  -p 2049:2049/tcp \
  -p 2049:2049/udp \
  -v $(pwd)/vxworks-files:/export \
  mitcdh/unfs3

# Get container IP
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' nfsv2-vxworks-prebuilt

# Mount using that IP
```

## Success!

This solution **actually works** because:
- ✅ Someone already compiled unfsd successfully
- ✅ Pre-built Docker image ready to use
- ✅ No build system issues
- ✅ Works on Rocky 9 (and any Linux with Docker)
- ✅ Provides NFSv2 in userspace

