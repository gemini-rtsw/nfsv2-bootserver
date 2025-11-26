# NFSv2 User Space Server with TFTP - For RTEMS VME Clients
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
    tftpd-hpa \
    tftp-hpa \
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
    iftop \
    nload \
    sysstat \
    && rm -rf /var/lib/apt/lists/*

# Create NFS export directory and log directory
# Note: /gem_sw is used for BOTH NFS and TFTP (same as original CentOS 6 setup)
RUN mkdir -p /gem_sw && chmod 777 /gem_sw && \
    mkdir -p /var/log && chmod 755 /var/log

# Copy exports config file
COPY config/exports /etc/exports
RUN echo "Exports configuration:" && \
    cat /etc/exports

# Create startup script
COPY <<EOF /start.sh
#!/bin/bash
set -e

echo "=========================================="
echo "Starting NFSv2 User-Space Server with TFTP"
echo "For RTEMS VME Clients"
echo "=========================================="
echo ""

echo "[0/6] Setting ulimit -n 65536..."
ulimit -n 65536
echo "✓ ulimit -n 65536"
echo ""

# Tune network buffers for reliability (optional, requires --privileged or --sysctl)
echo "[1/6] Tuning network parameters..."
sysctl -w net.core.rmem_max=16777216 2>/dev/null || echo "  ⚠ Warning: Cannot set rmem_max (needs --privileged)"
sysctl -w net.core.wmem_max=16777216 2>/dev/null || true
sysctl -w net.core.rmem_default=262144 2>/dev/null || true
sysctl -w net.core.wmem_default=262144 2>/dev/null || true
sysctl -w net.ipv4.tcp_rmem="4096 87380 16777216" 2>/dev/null || true
sysctl -w net.ipv4.tcp_wmem="4096 65536 16777216" 2>/dev/null || true
sysctl -w net.ipv4.tcp_window_scaling=1 2>/dev/null || true
sysctl -w net.ipv4.tcp_timestamps=1 2>/dev/null || true
sysctl -w net.ipv4.tcp_keepalive_time=60 2>/dev/null || true
sysctl -w net.ipv4.tcp_keepalive_intvl=10 2>/dev/null || true
sysctl -w net.ipv4.tcp_keepalive_probes=6 2>/dev/null || true
echo "✓ Network tuning attempted (may require --privileged for full effect)"
echo ""

# Configure network routing
echo "[2/6] Configuring network routing..."
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
# Add route for 10.1.2.0/24 (RTEMS VME client 10.1.2.177)
if ! ip route | grep -q "10.1.2.0/24"; then
    echo "Adding route to 10.1.2.0/24 via 10.2.2.1..."
    ip route add 10.1.2.0/24 via 10.2.2.1 dev eth0 || echo "⚠ Warning: Could not add 10.1.2.x route"
fi
echo "Current routes:"
ip route
echo "✓ Network routing configured"
echo ""

# Start rpcbind
echo "[3/6] Starting rpcbind..."
rpcbind -w
sleep 2
echo "✓ rpcbind started"
echo ""

# Start mountd with strace debugging (including RPC calls and all file operations)
echo "[4/6] Starting rpc.mountd with strace logging..."
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
echo "[5/6] Starting rpc.nfsd (NFSv2) with logging..."
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
echo "NFSv2 Server + TFTP Ready!"
echo "=========================================="
echo "NFS Export: /gem_sw"
echo "TFTP Root: /gem_sw (same directory as NFS)"
echo "Protocol: NFSv2"
echo ""
echo "RTEMS Client 1: 10.1.2.177"
echo "RTEMS Client 2: 10.2.2.104"
echo "Host IP: 10.2.2.146"
echo "Docker IP: 10.2.2.145"
echo ""
echo "To mount from RTEMS:"
echo '  nfsMount("<docker-ip>", "/gem_sw", "/mnt/nfs")'
echo ""
echo "To boot via TFTP from RTEMS:"
echo '  Boot file: /gem_sw/prod/redirector/tcs-mk-ioc'
echo "=========================================="
echo ""

echo "Configuration files loaded from image:"
echo "  - /etc/exports (NFS exports)"
echo "  - /home/gemvx/.rhosts (gemvx user access)"
echo ""
echo "Exports configuration:"
cat /etc/exports
echo ""

echo "[6/7] Starting TFTP server..."
# Start TFTP server rooted at / so full paths like /gem_sw/prod/... work
# The VME bootloader requests the full path /gem_sw/prod/redirector/tcs-mk-ioc
/usr/sbin/in.tftpd -l -s / -u root -c &
sleep 1
echo "✓ TFTP server started on port 69"
echo "  TFTP root: / (full paths like /gem_sw/prod/... work)"
echo ""

echo "[7/8] Starting inetd (rsh/rexec)..."
/usr/sbin/inetd
sleep 1
echo "✓ inetd started"
echo ""

echo "[8/8] Starting NTP server..."
# Sync time from host first, then start NTP daemon
ntpd -g -u ntp:ntp
sleep 1
echo "✓ NTP server started (serving time to RTEMS clients)"
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
echo "  docker exec nfsv2-rtems tail -f /var/log/mountd.log"
echo "  docker exec nfsv2-rtems tail -f /var/log/mountd-stdout.log"
echo "  docker exec nfsv2-rtems tail -f /var/log/nfsd.log"
echo ""
echo "TFTP server is running on port 69"
echo "  Serving from: /gem_sw (same as NFS)"
echo ""

# Verify mount path exists and show permissions
echo "Checking NFS export path permissions..."
if [ -d /gem_sw ]; then
    echo "✓ Path exists: /gem_sw"
    ls -ld /gem_sw
    echo "  Permissions: $(stat -c '%a' /gem_sw 2>/dev/null || stat -f '%A' /gem_sw)"
else
    echo "⚠ Path does not exist: /gem_sw"
    echo "  Creating directory..."
    mkdir -p /gem_sw
    chmod 777 /gem_sw
    echo "✓ Created and set permissions"
fi
echo ""

tail -f /dev/null
EOF

RUN chmod +x /start.sh

EXPOSE 111/tcp 111/udp 2049/tcp 2049/udp 69/udp 123/udp


# --- ADD rsh/rcp support ---
RUN apt-get update && apt-get install -y \
  openbsd-inetd \
  rsh-redone-server \
  ntp \
  ntpdate \
  && rm -rf /var/lib/apt/lists/*

# Configure NTP server to serve time to clients
RUN echo "# NTP Server Configuration for RTEMS VME clients" > /etc/ntp.conf && \
    echo "driftfile /var/lib/ntp/ntp.drift" >> /etc/ntp.conf && \
    echo "restrict default kod nomodify notrap nopeer noquery" >> /etc/ntp.conf && \
    echo "restrict 127.0.0.1" >> /etc/ntp.conf && \
    echo "restrict 10.0.0.0 mask 255.0.0.0 nomodify notrap" >> /etc/ntp.conf && \
    echo "server 127.127.1.0" >> /etc/ntp.conf && \
    echo "fudge 127.127.1.0 stratum 10" >> /etc/ntp.conf

# add inetd services
RUN printf "shell\tstream\ttcp\tnowait\troot\t/usr/sbin/in.rshd\tin.rshd\n" >> /etc/inetd.conf && \
  printf "exec\tstream\ttcp\tnowait\troot\t/usr/sbin/in.rexecd\tin.rexecd\n" >> /etc/inetd.conf

# create user and trust 10.x.x.x
RUN useradd -u 2966 -m -s /bin/bash gemvx

# Copy .rhosts for gemvx user
COPY config/.rhosts /home/gemvx/.rhosts
RUN chown gemvx:gemvx /home/gemvx/.rhosts && chmod 600 /home/gemvx/.rhosts

# expose rsh/rexec ports
EXPOSE 512/tcp 514/tcp

VOLUME ["/gem_sw"]
CMD ["/start.sh"]

