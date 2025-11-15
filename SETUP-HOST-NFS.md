# Setting Up Host Kernel NFS for NFSv3/4

Now that the NFSv2 container uses macvlan networking on `10.2.2.147`, you can enable kernel NFS on the host (`10.2.2.148`) for modern NFSv3/4 clients.

## Setup Steps

### 1. Enable host rpcbind and NFS services

```bash
# Start and enable rpcbind
sudo systemctl start rpcbind
sudo systemctl enable rpcbind

# Start and enable NFS server
sudo systemctl start nfs-server
sudo systemctl enable nfs-server
```

### 2. Configure host /etc/exports

Edit `/etc/exports` on the host (not in the container):

```bash
sudo vi /etc/exports
```

Add your exports for NFSv3/4 clients:

```
/export 10.2.2.233(rw,no_root_squash,sync) 10.2.2.234(rw,no_root_squash,sync)
# Add more IPs as needed
```

### 3. Apply the exports

```bash
sudo exportfs -ra
```

### 4. Verify host NFS is running

```bash
# Check NFS versions
sudo rpcinfo -p localhost | grep nfs

# Should see versions 3 and 4:
# 100003    3   tcp   2049  nfs
# 100003    4   tcp   2049  nfs

# Check exports
showmount -e localhost
```

### 5. Configure firewall (if enabled)

```bash
sudo firewall-cmd --permanent --add-service=nfs
sudo firewall-cmd --permanent --add-service=mountd
sudo firewall-cmd --permanent --add-service=rpc-bind
sudo firewall-cmd --reload
```

## Client Configuration

### VxWorks (NFSv2) Clients
Mount from container IP:
```
nfsMount("10.2.2.147", "/export", "/tgtsvr")
```

### Modern (NFSv3/4) Clients
Mount from host IP:
```bash
mount -t nfs 10.2.2.148:/export /mnt
```

## Verification

```bash
# On host, check both are running:
sudo rpcinfo -p localhost | grep nfs

# You should see:
# - Container NFSv2 on 10.2.2.147 (version 2)
# - Host kernel NFS on 10.2.2.148 (versions 3 and 4)

# Test from another machine:
rpcinfo -p 10.2.2.147 | grep nfs  # Should show version 2
rpcinfo -p 10.2.2.148 | grep nfs  # Should show versions 3 and 4
```

## Troubleshooting

If host NFS won't start:
```bash
# Check status
sudo systemctl status nfs-server

# Check logs
sudo journalctl -u nfs-server -n 50

# Verify no port conflicts
sudo netstat -tulpn | grep 2049
```

Both services can now run simultaneously on different IPs!

