# NFSv2 User Space Server - WORKING BUILD
# Uses nfs-user-server 2.2beta47 from Debian archive

FROM debian:bullseye 

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    gcc \
    make \
    flex \
    bison \
    libc6-dev \
    strace \
    tcpdump \
    && rm -rf /var/lib/apt/lists/*

# Copy local nfs-user-server source
WORKDIR /usr/src
COPY nfs-user-server_2.2beta47.orig.tar.gz .
RUN tar -xzf nfs-user-server_2.2beta47.orig.tar.gz

# Build nfs-user-server
WORKDIR /usr/src/nfs-server-2.2beta47
RUN ./configure --prefix=/usr/local && \
    touch site.mk && \
    touch site.h && \
    echo '#include <time.h>' > tmpfile && cat system.h >> tmpfile && mv tmpfile system.h && \
    sed -i 's/#define NFS_MAXDATA\t(16 \* 1024)/#define NFS_MAXDATA\t(32 \* 1024)/' nfsd.c && \
    sed -i 's/#define NFS_MAXDATA 8192/#define NFS_MAXDATA 32768/' nfs_prot.h && \
    sed -i 's/const NFS_MAXDATA       = 8192;/const NFS_MAXDATA       = 32768;/' nfs_prot.x && \
    make && \
    make install

# Install runtime dependencies and network debugging tools
RUN apt-get update && \
    apt-get install -y \
    rpcbind \
    netbase \
    procps \
    libtirpc-common \
    iputils-ping \
    traceroute \
    iproute2 \
    net-tools \
    dnsutils \
    curl \
    wget \
    netcat \
    telnet \
    && rm -rf /var/lib/apt/lists/*

# Create export directory and log directory
RUN mkdir -p /export && chmod 777 /export && \
    mkdir -p /var/log && chmod 755 /var/log

# Copy exports config file (can be overridden at runtime via volume mount)
COPY config/exports /etc/exports.template
RUN cp /etc/exports.template /etc/exports && \
    echo "Exports configuration:" && \
    cat /etc/exports

# Create startup script
COPY <<EOF /start.sh
#!/bin/bash
set -e

echo "=========================================="
echo "Starting NFSv2 User-Space Server"
echo "=========================================="
echo ""

echo "[0/5] Setting ulimit -n 65536..."
ulimit -n 65536
echo "✓ ulimit -n 65536"
echo ""

# Configure network routing
echo "[1/5] Configuring network routing..."
# Add default route if it doesn't exist
if ! ip route | grep -q default; then
    echo "Adding default route via 10.2.2.1..."
    ip route add default via 10.2.2.1 dev eth0 || echo "⚠ Warning: Could not add default route"
fi
# Add specific route for 10.2.49.0/24 via 10.2.2.234
if ! ip route | grep -q "10.2.49.0/24"; then
    echo "Adding route to 10.2.49.0/24 via 10.2.2.234..."
    ip route add 10.2.49.0/24 via 10.2.2.234 dev eth0 || echo "⚠ Warning: Could not add 10.2.49.x route"
fi
echo "Current routes:"
ip route
echo "✓ Network routing configured"
echo ""

# Start rpcbind
echo "[2/5] Starting rpcbind..."
rpcbind -w
sleep 2
echo "✓ rpcbind started"
echo ""

# Start mountd with strace debugging (including RPC calls and all file operations)
echo "[3/5] Starting rpc.mountd with strace logging..."
strace -f -o /var/log/mountd.log -e trace=all -e verbose=all /usr/sbin/rpc.mountd > /var/log/mountd-stdout.log 2>&1 &
MOUNTD_PID=$!
sleep 1
if ps -p $MOUNTD_PID > /dev/null 2>&1; then
    echo "✓ rpc.mountd started (PID: $MOUNTD_PID)"
    echo "  Strace log: /var/log/mountd.log"
    echo "  Stdout log: /var/log/mountd-stdout.log"
else
    echo "⚠ Warning: mountd may have exited, check logs"
    cat /var/log/mountd-stdout.log 2>/dev/null || true
fi
echo ""

# Start nfsd with debug logging
echo "[4/5] Starting rpc.nfsd (NFSv2) with logging..."
/usr/sbin/rpc.nfsd > /var/log/nfsd.log 2>&1 &
NFSD_PID=$!
sleep 2
if ps -p $NFSD_PID > /dev/null 2>&1; then
    echo "✓ rpc.nfsd started (PID: $NFSD_PID)"
    echo "  Debug log: /var/log/nfsd.log"
else
    echo "⚠ Warning: nfsd may have exited, check /var/log/nfsd.log"
    cat /var/log/nfsd.log 2>/dev/null || true
fi
echo ""

# Show registered services
echo "=========================================="
echo "Registered RPC Services:"
echo "=========================================="
rpcinfo -p localhost
echo ""

echo "=========================================="
echo "NFSv2 Server Ready!"
echo "=========================================="
echo "Export: /export"
echo "Protocol: NFSv2"
echo ""
echo "To mount from VxWorks:"
echo '  mount "<host-ip>", "/export", "/tgtsvr"'
echo ""
echo "To test from Linux (if NFSv2 supported):"
echo '  mount -t nfs -o vers=2 <host-ip>:/export /mnt/test'
echo "=========================================="
echo ""

echo "Setting up gemvx user and .rhosts file..."
if [ -f /home/gemvx/config/.rhosts ]; then
    cp /home/gemvx/config/.rhosts /home/gemvx/.rhosts
    chown gemvx:gemvx /home/gemvx/.rhosts && chmod 600 /home/gemvx/.rhosts
    echo "✓ gemvx user and .rhosts file set up"
else
    echo "⚠ Warning: /home/gemvx/config/.rhosts not found, skipping .rhosts setup"
fi
echo ""

echo "Setting up exports file..."
if [ -f /home/gemvx/config/exports ]; then
    cp /home/gemvx/config/exports /etc/exports
    echo "✓ Using custom exports from /home/gemvx/config/exports"
else
    echo "✓ Using default exports from /etc/exports.template"
fi
echo "Exports configuration:"
cat /etc/exports
echo ""

echo "[5/5] Starting inetd (rsh/rexec)..."
/usr/sbin/inetd
sleep 1
echo "✓ inetd started"
echo ""

# Show debug info
echo "=========================================="
echo "Debug Information"
echo "=========================================="
echo "Mountd strace log: /var/log/mountd.log"
echo "Mountd stdout log: /var/log/mountd-stdout.log"
echo "NFSd log: /var/log/nfsd.log"
echo ""
echo "To monitor logs:"
echo "  docker exec nfsv2-vxworks tail -f /var/log/mountd.log"
echo "  docker exec nfsv2-vxworks tail -f /var/log/mountd-stdout.log"
echo "  docker exec nfsv2-vxworks tail -f /var/log/nfsd.log"
echo ""

# Verify mount path exists and show permissions
echo "Checking export path permissions..."
if [ -d /export/gemini/altair/V3-7gate ]; then
    echo "✓ Path exists: /export/gemini/altair/V3-7gate"
    ls -ld /export/gemini/altair/V3-7gate
    echo "  Permissions: $(stat -c '%a' /export/gemini/altair/V3-7gate 2>/dev/null || stat -f '%A' /export/gemini/altair/V3-7gate)"
else
    echo "⚠ Path does not exist: /export/gemini/altair/V3-7gate"
    echo "  Creating parent directories..."
    mkdir -p /export/gemini/altair/V3-7gate
    chmod -R 777 /export/gemini
    echo "✓ Created and set permissions"
fi
echo ""

tail -f /dev/null
EOF

RUN chmod +x /start.sh

EXPOSE 111/tcp 111/udp 2049/tcp 2049/udp


# --- ADD rsh/rcp support ---
  RUN apt-get update && apt-get install -y \
  openbsd-inetd \
  rsh-redone-server \
  && rm -rf /var/lib/apt/lists/*

# add inetd services
RUN printf "shell\tstream\ttcp\tnowait\troot\t/usr/sbin/in.rshd\tin.rshd\n" >> /etc/inetd.conf && \
  printf "exec\tstream\ttcp\tnowait\troot\t/usr/sbin/in.rexecd\tin.rexecd\n" >> /etc/inetd.conf

# create user and trust 10.x.x.x
RUN useradd -u 2966 -m -s /bin/bash gemvx


# expose rsh/rexec ports
EXPOSE 512/tcp 514/tcp

RUN ln -s /export/gemini /gemini


VOLUME ["/export"]
CMD ["/start.sh"]

