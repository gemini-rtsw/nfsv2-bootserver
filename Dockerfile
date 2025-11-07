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

echo "[0/4] Setting ulimit -n 65536..."
ulimit -n 65536
echo "✓ ulimit -n 65536"
echo ""

# Start rpcbind
echo "[1/4] Starting rpcbind..."
rpcbind -w
sleep 2
echo "✓ rpcbind started"
echo ""

# Start mountd
echo "[2/4] Starting rpc.mountd..."
/usr/sbin/rpc.mountd
sleep 1
echo "✓ rpc.mountd started"
echo ""

# Start nfsd
echo "[3/4] Starting rpc.nfsd (NFSv2)..."
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

echo "[4/4] Starting inetd (rsh/rexec)..."
/usr/sbin/inetd
sleep 1
echo "✓ inetd started"
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
RUN useradd -m -s /bin/bash gemvx && \
  echo "10.2.2.57 gemvx" > /home/gemvx/.rhosts && \
  chown gemvx:gemvx /home/gemvx/.rhosts && chmod 600 /home/gemvx/.rhosts



# expose rsh/rexec ports
EXPOSE 512/tcp 514/tcp




VOLUME ["/export"]
CMD ["/start.sh"]

