# NFSv2 and rsh/rcp Server for VxWorks Tornado 2.0

This Docker container provides NFSv2 NFS server and rsh/rcp services specifically designed to support legacy VxWorks Tornado 2.0 VME images.

## Features

- **NFSv2 Support**: Configured to serve NFS version 2 protocol only
- **rsh/rcp/rlogin**: Legacy remote shell and copy utilities
- **Rocky Linux 9**: Based on modern, stable RHEL-compatible distribution
- **Optimized for VxWorks**: Pre-configured for VxWorks boot and development needs

## ⚠️ Security Warning

**This container uses extremely insecure legacy protocols (NFSv2, rsh, rcp) that should NEVER be exposed to the internet or untrusted networks.**

Only use this container:
- On isolated lab networks
- Behind firewalls
- For legacy system support only
- Where VxWorks/Tornado 2.0 compatibility is required

## Prerequisites

- Docker
- Docker Compose (optional)
- Host system with sufficient privileges

## Directory Structure

```
.
├── Dockerfile              # Container definition
├── docker-compose.yml      # Docker Compose configuration
├── entrypoint.sh          # Container startup script
├── vxworks-files/         # Your VxWorks boot images and files (created on first run)
└── README.md              # This file
```

## Quick Start

### Using Docker Compose (Recommended)

1. **Create the vxworks-files directory**:
   ```bash
   mkdir -p vxworks-files
   ```

2. **Place your VxWorks boot images** in the `vxworks-files/` directory

3. **Build and start the container**:
   ```bash
   docker-compose up -d
   ```

4. **View logs**:
   ```bash
   docker-compose logs -f
   ```

### Using Docker CLI

1. **Build the image**:
   ```bash
   docker build -t nfsv2-vxworks .
   ```

2. **Run the container**:
   ```bash
   docker run -d \
     --name nfsv2-vxworks \
     --privileged \
     --network host \
     -v $(pwd)/vxworks-files:/nfs/vxworks \
     nfsv2-vxworks
   ```

## Usage with VxWorks Tornado 2.0

### Mounting NFS from VxWorks

From the VxWorks shell:

```vxworks
# Mount the NFS share
mount "192.168.1.100", "/nfs/vxworks", "/tgtsvr"

# Or specify NFS version explicitly
nfsMount "192.168.1.100", "/nfs/vxworks", "/tgtsvr"
```

Replace `192.168.1.100` with your Docker host's IP address.

### Boot Configuration

In your VxWorks boot parameters:

```
boot device          : gei
processor number     : 0
host name            : host
file name            : /nfs/vxworks/vxWorks
inet on ethernet (e) : 192.168.1.50:ffffff00
host inet (h)        : 192.168.1.100
gateway inet (g)     : 192.168.1.1
user (u)             : target
ftp password (pw)    : password
flags (f)            : 0x0
target name (tn)     : target
startup script (s)   : /nfs/vxworks/startup.script
```

### Using rsh/rcp

From your host system or VxWorks:

```bash
# Copy file to container
rcp myfile root@192.168.1.100:/nfs/vxworks/

# Execute remote command
rsh root@192.168.1.100 ls -la /nfs/vxworks/

# Remote login
rlogin root@192.168.1.100
```

## Configuration

### NFS Export Options

The default export in `/etc/exports`:
```
/nfs/vxworks *(rw,sync,no_root_squash,no_subtree_check,insecure,nfsvers=2)
```

- `rw`: Read-write access
- `sync`: Synchronous writes
- `no_root_squash`: Allow root access from clients
- `no_subtree_check`: Improve reliability
- `insecure`: Allow connections from ports > 1024
- `nfsvers=2`: Only NFS version 2

### Ports Used

- **111** (TCP/UDP): rpcbind
- **2049** (TCP/UDP): NFS server
- **20048**: mountd
- **512**: rexec
- **513**: rlogin
- **514**: rsh

## Troubleshooting

### NFSv2 Not Working

1. **Check if NFSv2 is actually disabled in kernel**:
   ```bash
   docker exec nfsv2-vxworks cat /proc/fs/nfsd/versions
   ```
   Should show: `-2 +3 +4` or `+2 +3 +4`

2. **If NFSv2 is not available**, you may need to use NFSv3 instead. Modern kernels often have NFSv2 compiled out. To use NFSv3, modify the startup scripts.

3. **Check NFS exports**:
   ```bash
   docker exec nfsv2-vxworks exportfs -v
   ```

### Connection Refused

1. **Verify container is running**:
   ```bash
   docker ps | grep nfsv2
   ```

2. **Check network mode** is set to `host`

3. **Verify services are running**:
   ```bash
   docker exec nfsv2-vxworks ps aux | grep nfs
   docker exec nfsv2-vxworks ps aux | grep xinetd
   ```

### VxWorks Can't Mount

1. **Ping test** from VxWorks to Docker host
2. **Check firewall** on Docker host
3. **Verify NFS version** compatibility
4. **Try with IP address** instead of hostname

## Important Notes for NFSv2

**NFSv2 Limitations in Modern Systems:**

Modern Linux kernels (including Rocky 9's kernel) may have NFSv2 support disabled or removed entirely. If NFSv2 doesn't work:

1. **Option 1**: Use NFSv3 instead (VxWorks 5.x and Tornado 2.0 typically support NFSv3)
2. **Option 2**: Use an older Linux distribution (CentOS 6/7) where NFSv2 is more reliably available
3. **Option 3**: Build a custom kernel module if absolutely necessary

To switch to NFSv3, modify `entrypoint.sh`:
```bash
rpc.nfsd --no-nfs-version 4 8
rpc.mountd --no-nfs-version 4
```

And update `/etc/exports`:
```
/nfs/vxworks *(rw,sync,no_root_squash,no_subtree_check,insecure,nfsvers=3)
```

## Maintenance

### Stop the container:
```bash
docker-compose down
# or
docker stop nfsv2-vxworks
```

### View logs:
```bash
docker-compose logs -f
# or
docker logs -f nfsv2-vxworks
```

### Access container shell:
```bash
docker exec -it nfsv2-vxworks bash
```

## License

This configuration is provided as-is for legacy system support purposes.

## Support

For VxWorks-specific issues, consult your Tornado 2.0 documentation or Wind River support resources.

