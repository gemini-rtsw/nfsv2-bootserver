# The Actual Problem: No Working NFSv2

## What We Tested

Tested the prebuilt `mitcdh/unfs3` image (unfsd 0.9.22):

### Result: **NFSv3 ONLY - No NFSv2**

```bash
$ docker exec nfsv2-test rpcinfo -p localhost
   program vers proto   port  service
    100003    3   udp   2049  # NFSv3 only
    100003    3   tcp   2049  # NFSv3 only
    100005    1   udp   2049  # mountd v1
    100005    3   udp   2049  # mountd v3
```

**NO `100003 vers 2` = NO NFSv2**

## Why This Matters

NFS version negotiation works via RPC registration:
1. Server registers supported versions with rpcbind
2. Client queries rpcbind to see what's available
3. Client uses highest mutually supported version

If version 2 isn't registered, **VxWorks cannot use it**. Period.

## The README is Wrong

Current README.md says:
> "Even though `rpcinfo` only shows version 3, unfsd was built to support version 2. VxWorks will negotiate the protocol version when connecting."

This is **incorrect**. RPC doesn't work that way. The versions must be advertised.

## Sources All Dead

Tried to build from source:
- ❌ Debian nfs-user-server: `http://ftp.debian.org/debian/pool/main/n/nfs-user-server/` - 404
- ❌ SourceForge unfsd: `https://sourceforge.net/projects/nfs/files/unfs3/0.9.22/` - 404  
- ❌ Alternative SourceForge URL: 404
- ❌ Debian Lenny image: doesn't exist

## What We Actually Need

### Option 1: Find Working Source
- nfs-user-server 2.2beta47 source (designed for NFSv2)
- unfsd 0.9.22 source compiled with `--enable-nfsv2` or similar flag
- Any other user-space NFS server that actually supports v2

### Option 2: Alternative Approaches
- **Use kernel NFS with old kernel** that supports NFSv2
- **Find a working binary** of nfs-user-server or unfsd with v2
- **Different NFS implementation** (BSD, Plan 9, etc.)

## Testing Checklist

To verify a solution actually works:

```bash
# 1. Start NFS server
docker run -d --name nfs-test [your-image]

# 2. Check RPC registration
docker exec nfs-test rpcinfo -p localhost | grep 100003

# MUST show BOTH:
#   100003    2   udp   2049
#   100003    2   tcp   2049
```

If you don't see version 2 registered, **it won't work with VxWorks**.

## Why You're Stuck

You've been working on this for days because:
1. All the "solutions" use unfsd/unfs3 prebuilt images
2. None of these images actually provide NFSv2
3. Source code to rebuild with NFSv2 is 404
4. The documentation claims it works when it doesn't

## Next Steps

**Before doing ANY more work:**
1. Find WORKING source code for:
   - nfs-user-server 2.2beta47, OR
   - unfsd 0.9.22, OR
   - Any other NFSv2 user-space server
2. Build it
3. TEST with `rpcinfo` to verify v2 is registered
4. Only then proceed with Docker packaging

**DO NOT:**
- ❌ Assume prebuilt images support v2
- ❌ Trust documentation without testing
- ❌ Write more configs/docs until you have working binary

## Alternative: Kernel NFS

If user-space is impossible, consider:
- CentOS 6/7 container with kernel NFS + NFSv2
- Requires `--privileged` and kernel module loading
- More complex but might be only option

## What Actually Works Right Now

**Nothing.** The current repo has no working NFSv2 solution. All containers provide NFSv3 only.

