# NFSv2 Server for VxWorks Boot

A working NFSv2 user-space server for booting legacy VxWorks systems. Built from `nfs-user-server 2.2beta47` source.

## Quick Start (Linux)

### Prerequisites

Enable promiscuous mode on your network interface (required for IPVLAN):

```bash
# Enable promiscuous mode (replace ens33 with your interface name)
sudo ip link set ens33 promisc on

# Verify it's enabled (should see PROMISC in the flags)
ip link show ens33
```

### Start the Server

```bash
# Start the NFSv2 server
./start-nfsv2.sh

# Check status
./status-nfsv2.sh

# Stop the server
./stop-nfsv2.sh
```

The startup script will:
- Build/pull the Docker image (first time only)
- Create the `vxworks-files/` directory
- Create an IPVLAN network
- Start the NFSv2 server with IP 10.2.2.147
- Display your server IP and VxWorks mount command

## VxWorks Mount

From your VxWorks shell, mount from the container IP (10.2.2.147):

```
-> nfsMount("10.2.2.147", "/export", "/tgtsvr")
```

If you changed the container IP in `start-nfsv2.sh`, use that IP instead.

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

# Create IPVLAN network
docker network create -d ipvlan \
    --subnet=10.2.2.0/24 \
    --gateway=10.2.2.1 \
    -o parent=ens33 \
    -o ipvlan_mode=l2 \
    nfs-ipvlan

# Run the container
docker run -d \
    --name nfsv2-vxworks \
    --network nfs-ipvlan \
    --ip 10.2.2.147 \
    --privileged \
    -v /export:/export:rw \
    -v $(pwd)/config:/home/gemvx/config:rw \
    --restart unless-stopped \
    nfsv2:working
```

## Requirements

- Docker
- Linux host with IPVLAN support
- Network interface in promiscuous mode (`sudo ip link set <interface> promisc on`)
- Available IP address on your network for the container (default: 10.2.2.147)

## Adding a New VxWorks Client

To allow a new VxWorks client to NFS mount, two files need to be updated and the image rebuilt:

**1. `config/exports`** — grant NFS access:
```
/export 10.1.2.175(rw,no_root_squash)
```

**2. `config/.rhosts`** — grant rsh/rcp access:
```
10.1.2.175 gemvx
```

**3. Routing** — if the new client is on a subnet not already routed by the container, add a route in the `[2/6] Configuring network routing` section of the startup script in `Dockerfile`. For example, clients on `10.1.x.x` need:
```bash
ip route add 10.1.0.0/16 via 10.2.2.1 dev eth0
```
The `10.1.0.0/16` route via `10.2.2.1` is already present. If your client is on a different subnet, add the appropriate route using the same pattern.

After editing, commit and push — the GitLab CI pipeline will rebuild and push the image automatically.

> **Note:** rsh may work even without the routing fix because the client initiates the TCP connection outbound. NFS uses UDP where the *server* sends packets back to the client IP, so a missing return route will silently break NFS while rsh continues to work.

## How It Works

This builds `nfs-user-server 2.2beta47` from source, which provides true NFSv2 support. The server runs in a Docker container with:

- **Protocol**: NFSv2 (required for old VxWorks systems)
- **Export**: `/export` → mapped to host's `/export` directory
- **Permissions**: `rw,no_root_squash` per client IP (configured in `config/exports`)
- **Network**: IPVLAN mode with dedicated IP (10.2.2.147)
  - Uses same MAC address as host (switch-friendly)
  - Allows host to run NFSv3/4 simultaneously on different IP
- **Routing**: Static routes added at startup for each client subnet (currently `10.2.49.0/24` and `10.1.0.0/16`)

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
- The server uses IPVLAN networking to avoid port conflicts with host NFS
- Host can run NFSv3/4 kernel NFS on a different IP simultaneously (see `SETUP-HOST-NFS.md`)
- IPVLAN requires promiscuous mode on the parent interface
- Container shares the host's MAC address but has its own IP

## Troubleshooting

**Cannot ping container from external machines**:
```bash
# Enable promiscuous mode on parent interface
sudo ip link set ens33 promisc on

# Verify it's enabled
ip link show ens33 | grep PROMISC
```

**Can't mount from VxWorks**:
- Verify container IP: `docker inspect nfsv2-vxworks | grep IPAddress`
- Check if container is reachable: `ping 10.2.2.147` (from VxWorks client)
- Check RPC services: `docker exec nfsv2-vxworks rpcinfo -p localhost`
- Verify client IP is in `config/exports`
- Check debug logs: `docker exec nfsv2-vxworks tail -100 /var/log/mountd.log`
- **rsh works but NFS doesn't**: The container is missing a return route to the client's subnet. Check `docker exec nfsv2-vxworks ip route` and add the missing subnet route in the Dockerfile startup script (see *Adding a New VxWorks Client* above).

**Host cannot ping container**:
- This is normal! IPVLAN containers cannot communicate with their host
- Use `docker exec` to access the container instead

**Need to see logs**:
```bash
docker logs -f nfsv2-vxworks
docker exec nfsv2-vxworks tail -f /var/log/mountd.log
```

**Run both NFSv2 and NFSv3/4**: See `SETUP-HOST-NFS.md` for details.
