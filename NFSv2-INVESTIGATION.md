# NFS v2 User Space Investigation for VxWorks Boot

## Requirements
- **NFSv2 protocol support** (required for old VxWorks systems)
- **User space implementation** (easier to deploy in Docker)
- **Compatible with VxWorks Tornado 2.0 and older systems**

## NFS v2 User Space Options

### 1. nfs-user-server (Classic Linux NFS v2 Server)

**Overview:**
- Original Linux user-space NFS server from the 1990s
- Explicitly designed for NFSv2 protocol
- Last maintained version: 2.2beta47-25 (Debian)
- Well-tested with legacy systems like VxWorks

**Pros:**
- ✅ Native NFSv2 support (primary protocol)
- ✅ Designed specifically for user-space operation
- ✅ Proven compatibility with old VxWorks systems
- ✅ Stable and mature codebase
- ✅ Lightweight and simple

**Cons:**
- ❌ No longer in modern Linux distributions
- ❌ Must be compiled from source
- ❌ Limited active development
- ❌ Fewer features than modern alternatives

**Source Locations:**
- Debian Archive: http://ftp.debian.org/debian/pool/main/n/nfs-user-server/
- Debian Sources: https://sources.debian.org/src/nfs-user-server/
- Version: 2.2beta47-25

**Components:**
- `rpc.nfsd` - Main NFS daemon
- `rpc.mountd` - Mount protocol daemon
- `rpc.ugidd` - User/Group ID mapper
- `showmount` - Display mount information

### 2. unfsd/unfs3 (User-space NFSv2/v3 Server)

**Overview:**
- Modern user-space NFS server
- Supports both NFSv2 and NFSv3
- Actively maintained (last update: 2022)
- Single binary solution

**Pros:**
- ✅ Supports NFSv2 via backwards compatibility
- ✅ More modern codebase
- ✅ Single binary (unfsd)
- ✅ Available in some package managers
- ✅ Pre-built Docker images available
- ✅ Better error handling and logging

**Cons:**
- ❌ Primary focus is NFSv3 (NFSv2 is secondary)
- ❌ May need explicit NFSv2 flags
- ❌ Slightly more complex

**Source Locations:**
- SourceForge: https://sourceforge.net/projects/nfs/files/unfs3/
- Version: 0.9.22 (has NFSv2 support)

### 3. Linux Kernel NFS Server (Not User Space)

**Not suitable for our use case:**
- Requires kernel modules
- Complex to run in Docker
- Overkill for VxWorks boot server

## Recommendation

For **VxWorks boot server**, both options work:

1. **nfs-user-server** - Best for pure NFSv2 compatibility
   - If you need maximum compatibility with ancient VxWorks
   - If NFSv2 is the only protocol needed
   - Closest to original VxWorks NFS implementation

2. **unfsd** - Best for modern deployment
   - Easier to deploy (pre-built images available)
   - Better maintained
   - Still fully supports NFSv2

## Implementation Approach

We'll build **both** solutions:

1. **Dockerfile.nfs-user-server** - Pure NFSv2 implementation
2. **Dockerfile.unfsd** - Modern alternative with NFSv2 support

Both will:
- Run in Docker containers
- Use user-space NFS (no kernel dependencies)
- Export `/export` directory
- Support NFSv2 protocol
- Work with VxWorks boot clients

## Testing Requirements

The NFS server must support:
- NFSv2 protocol (mount version 1)
- UDP transport
- `no_root_squash` for VxWorks boot files
- Proper RPC/portmapper integration
- Ports: 111 (rpcbind), 2049 (nfs)

## References

- VxWorks typically uses NFSv2 for boot protocol
- VxWorks Tornado 2.0 requires NFSv2 mount protocol
- Modern Linux defaults to NFSv3/v4, so explicit v2 must be enabled

