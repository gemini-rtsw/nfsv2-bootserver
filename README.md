# NFSv2 Server for VxWorks Boot

A working NFSv2 user-space server for booting legacy VxWorks systems. Built from `nfs-user-server 2.2beta47` source.

## Quick Start (Linux)

```bash
# Start the NFSv2 server
sudo ./start-nfsv2.sh

# Check status
./status-nfsv2.sh

# Stop the server
./stop-nfsv2.sh
```

The startup script will:
- Build the Docker image (first time only)
- Create the `vxworks-files/` directory
- Start the NFSv2 server with proper configuration
- Display your server IP and VxWorks mount command

## VxWorks Mount

From your VxWorks shell:

```
-> mount "<server-ip>", "/export", "/tgtsvr"
```

Replace `<server-ip>` with your Linux server's IP address.

## File Management

Place your VxWorks boot files in the `vxworks-files/` directory:

```bash
cp /path/to/vxWorks vxworks-files/
cp /path/to/bootrom.bin vxworks-files/
```

These files will be accessible from VxWorks at `/tgtsvr/`

## Manual Docker Build

If you want to build/run manually:

```bash
# Build the image
docker build -t nfsv2:working .

# Run the container
docker run -d \
    --name nfsv2-vxworks \
    --privileged \
    --network host \
    -v $(pwd)/vxworks-files:/export \
    nfsv2:working
```

## Requirements

- Docker
- Linux host (requires `network_mode: host` for NFS to work properly)
- Root access (to stop host's rpcbind service)

## How It Works

This builds `nfs-user-server 2.2beta47` from source, which provides true NFSv2 support. The server runs in a Docker container with:

- **Protocol**: NFSv2 (required for old VxWorks systems)
- **Export**: `/export` → mapped to `./vxworks-files/` on host
- **Permissions**: `rw,no_root_squash,insecure` (suitable for boot/development)
- **Network**: Host mode (NFS requires direct port access)

## Verification

The startup script shows RPC services. You should see:

```
100003    2   udp   2049  nfs
100003    2   tcp   2049  nfs
```

The `2` in the second column indicates NFSv2.

## Technical Notes

- Modern Linux kernels have removed NFSv2 client support, so you cannot test mounting from a modern Linux client
- VxWorks has its own NFSv2 client implementation that works with this server
- The server must run with `--privileged` and `--network host` for proper NFS operation
- Host's rpcbind must be stopped to avoid port conflicts

## Troubleshooting

**Container won't start**: Make sure host rpcbind is stopped:
```bash
sudo systemctl stop rpcbind
```

**Can't mount from VxWorks**: 
- Check firewall rules (ports 111, 2049 must be open)
- Verify server IP with `ip addr`
- Check RPC services: `docker exec nfsv2-vxworks rpcinfo -p localhost`

**Need to see logs**:
```bash
docker logs -f nfsv2-vxworks
```
