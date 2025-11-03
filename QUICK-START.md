# NFSv2 for VxWorks - Quick Start Guide

## TL;DR - Get NFSv2 Running in 3 Minutes

### Choose Your Solution

| Solution | Best For | Protocol | Build Time |
|----------|----------|----------|------------|
| **nfs-user-server** | Pure NFSv2, maximum VxWorks compatibility | NFSv2 only | ~2 min |
| **unfsd** | Modern deployment, faster builds | NFSv2 + NFSv3 | ~1 min |

## 🚀 Fastest Path to Working NFS

### Step 1: Prepare Host (One-Time Setup)

```bash
# Stop host rpcbind (REQUIRED!)
sudo systemctl stop rpcbind
sudo systemctl disable rpcbind

# Create directory for boot files
mkdir -p vxworks-files
chmod 777 vxworks-files
```

### Step 2: Choose and Start Server

#### Option A: nfs-user-server (Classic, Pure NFSv2)

```bash
docker-compose -f docker-compose-nfs-user-server.yml up -d --build
```

Wait 2 minutes for build to complete.

#### Option B: unfsd (Modern, Faster)

```bash
docker-compose -f docker-compose-unfsd.yml up -d --build
```

Wait 1 minute for build to complete.

### Step 3: Verify It's Working

```bash
# Check logs (should see "NFS Server Ready!")
docker logs nfs-user-server-vxworks
# OR
docker logs unfsd-vxworks

# Check RPC services
docker exec nfs-user-server-vxworks rpcinfo -p
# OR
docker exec unfsd-vxworks rpcinfo
```

You should see:
- Port 111: portmapper
- Port 2049: nfs
- mountd service

### Step 4: Test from VxWorks

```vxworks
-> mount "192.168.1.100", "/export", "/tgtsvr"
-> ls "/tgtsvr"
```

Replace `192.168.1.100` with your Docker host IP.

## 📋 Common Commands

### Container Management

```bash
# View logs in real-time
docker logs -f [container-name]

# Stop server
docker-compose -f [compose-file].yml down

# Restart server
docker-compose -f [compose-file].yml restart

# Rebuild from scratch
docker-compose -f [compose-file].yml down
docker-compose -f [compose-file].yml up -d --build --force-recreate
```

### Testing

```bash
# Test from Linux
sudo mount -t nfs -o vers=2 <host-ip>:/export /mnt/test
echo "test" | sudo tee /mnt/test/testfile.txt
ls -la /mnt/test/
sudo umount /mnt/test

# Check what's exported
showmount -e <host-ip>

# Check if NFS ports are open
nmap -p 111,2049 <host-ip>
```

## 🐛 Quick Troubleshooting

### Problem: "address already in use"

**Solution:** Host rpcbind is still running
```bash
sudo systemctl stop rpcbind
docker-compose -f [compose-file].yml restart
```

### Problem: "Connection refused" from VxWorks

**Solution 1:** Check firewall
```bash
sudo firewall-cmd --add-service=nfs --permanent
sudo firewall-cmd --add-service=rpc-bind --permanent
sudo firewall-cmd --reload
```

**Solution 2:** Verify server is running
```bash
docker logs [container-name]
rpcinfo -p <host-ip>
```

### Problem: Build fails with download error

**Solution:** Source may be temporarily unavailable, try again or use alternative mirrors

### Problem: VxWorks can't mount

**Check these:**
1. ✅ Can you ping the Docker host from VxWorks?
2. ✅ Is the container running? `docker ps`
3. ✅ Are RPC services registered? `rpcinfo -p <host-ip>`
4. ✅ Is the path correct? Use `/export` not `/nfs/vxworks`

## 📊 Which Solution Should I Use?

### Use nfs-user-server if:
- You're booting **really old VxWorks** (Tornado 2.0 or earlier)
- You need **guaranteed NFSv2 compatibility**
- You want the **original Linux NFS server** that's been around since the 1990s
- VxWorks is your only client (no need for NFSv3)

### Use unfsd if:
- You want a **modern, maintained** codebase
- You need both **NFSv2 and NFSv3** support
- You want **faster builds** (Alpine vs Debian)
- You prefer **simpler operation** (single binary)

## 🎯 Production Deployment

### Recommended Setup for VxWorks Boot Server

1. Use **nfs-user-server** for maximum compatibility
2. Use `network_mode: host` (required for RPC)
3. Set `restart: unless-stopped` (auto-recovery)
4. Mount `vxworks-files` as volume (persistent storage)
5. Run on dedicated Linux machine (avoid port conflicts)

### Example Production Command

```bash
# Create persistent directory
sudo mkdir -p /srv/vxworks-boot
sudo chmod 777 /srv/vxworks-boot

# Copy boot files
cp vxWorks /srv/vxworks-boot/
cp bootrom.bin /srv/vxworks-boot/

# Start server
cd /path/to/nfsv2
docker-compose -f docker-compose-nfs-user-server.yml up -d --build

# Enable on boot
sudo systemctl enable docker
```

## 📝 File Checklist

Before booting VxWorks, ensure these files are in `vxworks-files/`:

- [ ] `vxWorks` or `vxWorks.st` (kernel image)
- [ ] `bootrom.bin` (optional, boot ROM image)
- [ ] Any application binaries
- [ ] Configuration files

## 🔥 Emergency Recovery

If nothing works:

```bash
# 1. Stop everything
docker-compose -f docker-compose-nfs-user-server.yml down
docker-compose -f docker-compose-unfsd.yml down

# 2. Clean up Docker
docker system prune -af

# 3. Reset rpcbind
sudo systemctl stop rpcbind
sudo systemctl disable rpcbind

# 4. Start fresh
docker-compose -f docker-compose-nfs-user-server.yml up -d --build

# 5. Check logs carefully
docker logs -f nfs-user-server-vxworks
```

## 📞 Getting Help

### Check These First

1. Read the logs: `docker logs [container-name]`
2. Check RPC: `rpcinfo -p <host-ip>`
3. Test mount from Linux first
4. Verify network connectivity from VxWorks

### Useful Debug Commands

```bash
# Inside container
docker exec -it [container-name] /bin/bash
cat /etc/exports
ps aux
netstat -tuln

# From host
ss -tuln | grep -E ':(111|2049)'
sudo tcpdump -i any port 2049 or port 111
```

## ✅ Success Checklist

Before declaring victory:

- [ ] Container starts without errors
- [ ] Logs show "NFS Server Ready!"
- [ ] `rpcinfo` shows nfs and mountd
- [ ] Linux can mount with NFSv2
- [ ] VxWorks can mount successfully
- [ ] Files are accessible from VxWorks
- [ ] Can create/delete files from VxWorks

## 🎉 You're Done!

If you made it here, you have a working NFSv2 server for your VxWorks system!

Put your boot files in `vxworks-files/` and point your VxWorks bootloader to:
- **Host:** `<docker-host-ip>`
- **Path:** `/export`

Happy booting! 🚀

