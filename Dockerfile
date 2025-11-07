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
    make && \
    make install

# Install runtime dependencies
RUN apt-get update && \
    apt-get install -y \
    rpcbind \
    netbase \
    procps \
    libtirpc-common \
    && rm -rf /var/lib/apt/lists/*

# Copy compiled binaries from builder (they install to /usr/sbin)
#COPY --from=builder /usr/sbin/rpc.nfsd /usr/local/sbin/rpc.nfsd
#COPY --from=builder /usr/sbin/rpc.mountd /usr/local/sbin/rpc.mountd
#COPY --from=builder /usr/sbin/showmount /usr/local/sbin/showmount

# Create export directory
RUN mkdir -p /export && chmod 777 /export

# Create exports file
RUN echo "/export *(rw,no_root_squash,insecure,async,no_subtree_check)" > /etc/exports

# Create startup script
COPY <<EOF /start.sh
#!/bin/bash
set -e

echo "=========================================="
echo "Starting NFSv2 User-Space Server"
echo "=========================================="
echo ""

echo "[0/3] Setting ulimit -n 65536..."
ulimit -n 65536
echo "✓ ulimit -n 65536"
echo ""

# Start rpcbind
echo "[1/3] Starting rpcbind..."
rpcbind -w
sleep 2
echo "✓ rpcbind started"
echo ""

# Start mountd
echo "[2/3] Starting rpc.mountd..."
/usr/sbin/rpc.mountd
sleep 1
echo "✓ rpc.mountd started"
echo ""

# Start nfsd
echo "[3/3] Starting rpc.nfsd (NFSv2)..."
/usr/sbin/rpc.nfsd
sleep 2
echo "✓ rpc.nfsd started"
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

tail -f /dev/null
EOF

RUN chmod +x /start.sh

EXPOSE 111/tcp 111/udp 2049/tcp 2049/udp

VOLUME ["/export"]
CMD ["/start.sh"]

