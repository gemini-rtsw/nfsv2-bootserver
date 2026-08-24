# NFSv2 user-space boot server for VxWorks / RTEMS VME clients.
#
# This image is GENERIC: it contains no site configuration. The TCS and Altair
# boot servers run the same image and differ only in the environment and the
# bind-mounted /etc/exports and /home/gemvx/.rhosts supplied by their RPM.
#
# The base is pinned to a dated tag on purpose. Debian bullseye reaches end of
# LTS in Aug 2026; once it moves to archive.debian.org an unpinned
# `apt-get update` starts failing and this image can no longer be rebuilt.
# --platform is pinned, not inherited: both boot servers are x86_64, and a
# build on an Apple Silicon laptop would otherwise produce an arm64 image that
# installs fine and then cannot run on either host. build_app_image.sh
# deliberately passes no --platform of its own so this line wins.
FROM --platform=linux/amd64 debian:bullseye-20250203

# Freeze apt at a snapshot so the build stays reproducible after bullseye is
# archived. check-valid-until=no is required: archived Release files are
# expired and apt refuses them otherwise.
#
# http, not https: the base image ships no ca-certificates, so an https source
# cannot be used to install the package that would make https work. Integrity
# does not depend on the transport here -- apt verifies the Release signature
# against the debian-archive-keyring already in the image.
RUN printf 'deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/20250201T000000Z bullseye main\n\
deb [check-valid-until=no] http://snapshot.debian.org/archive/debian-security/20250201T000000Z bullseye-security main\n' \
      > /etc/apt/sources.list && \
    echo 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/80retries

RUN apt-get update && apt-get install -y \
    build-essential gcc make flex bison libc6-dev \
    && rm -rf /var/lib/apt/lists/*

# nfs-user-server 2.2beta47, vendored. This is the one component that must NOT
# drift: it is the only NFSv2 server that still speaks to these VME clients.
WORKDIR /usr/src
COPY nfs-user-server_2.2beta47.orig.tar.gz .
RUN tar -xzf nfs-user-server_2.2beta47.orig.tar.gz

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

# Runtime: NFS/TFTP/NTP/rsh plus the diagnostic tools this server has always
# carried (these boxes are on a closed network; there is no installing them later).
RUN apt-get update && apt-get install -y \
    rpcbind netbase procps libtirpc-common \
    iputils-ping traceroute iproute2 net-tools dnsutils \
    curl wget netcat telnet strace tcpdump \
    iftop nload sysstat inetutils-syslogd \
    tftpd-hpa tftp-hpa ntp ntpdate \
    openbsd-inetd rsh-redone-server \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/log && chmod 755 /var/log

RUN echo "# NTP server configuration for VxWorks/RTEMS clients" > /etc/ntp.conf && \
    echo "driftfile /var/lib/ntp/ntp.drift" >> /etc/ntp.conf && \
    echo "restrict default kod nomodify notrap nopeer noquery" >> /etc/ntp.conf && \
    echo "restrict 127.0.0.1" >> /etc/ntp.conf && \
    echo "restrict 10.0.0.0 mask 255.0.0.0 nomodify notrap" >> /etc/ntp.conf && \
    echo "server 127.127.1.0" >> /etc/ntp.conf && \
    echo "fudge 127.127.1.0 stratum 10" >> /etc/ntp.conf

RUN printf "shell\tstream\ttcp\tnowait\troot\t/usr/sbin/in.rshd\tin.rshd\n" >> /etc/inetd.conf && \
    printf "exec\tstream\ttcp\tnowait\troot\t/usr/sbin/in.rexecd\tin.rexecd\n" >> /etc/inetd.conf

# uid 2966 must match the gemvx uid on the VME clients, or rsh/rcp maps to the
# wrong user and file ownership on the export goes wrong.
RUN useradd -u 2966 -m -s /bin/bash gemvx

# Placeholders only. Both are bind-mounted over by the systemd unit; an image
# that shipped a real client list would put site config back inside the build.
RUN echo "# placeholder - bind-mounted by the RPM's systemd unit" > /etc/exports && \
    chmod 644 /etc/exports && chown root:root /etc/exports && \
    : > /home/gemvx/.rhosts && \
    chown gemvx:gemvx /home/gemvx/.rhosts && chmod 600 /home/gemvx/.rhosts

COPY scripts/start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 111/tcp 111/udp 2049/tcp 2049/udp 69/udp 123/udp 512/tcp 514/tcp

CMD ["/start.sh"]
