FROM rockylinux:9

# Install EPEL and required packages
RUN dnf install -y epel-release && \
    dnf install -y \
    nfs-utils \
    rpcbind \
    rsh \
    net-tools \
    vim \
    iproute \
    procps-ng \
    kmod \
    && dnf clean all

# Create NFS export directory
RUN mkdir -p /nfs/vxworks && \
    chmod -R 777 /nfs/vxworks

# Configure NFS exports for NFSv2/v3 (Rocky 9 kernel may not support v2)
RUN echo "/nfs/vxworks *(rw,sync,no_root_squash,no_subtree_check,insecure)" > /etc/exports

# Configure systemd socket for rsh
RUN echo "[Unit]" > /etc/systemd/system/rsh.socket && \
    echo "Description=RSH Server Activation Socket" >> /etc/systemd/system/rsh.socket && \
    echo "" >> /etc/systemd/system/rsh.socket && \
    echo "[Socket]" >> /etc/systemd/system/rsh.socket && \
    echo "ListenStream=514" >> /etc/systemd/system/rsh.socket && \
    echo "Accept=yes" >> /etc/systemd/system/rsh.socket && \
    echo "" >> /etc/systemd/system/rsh.socket && \
    echo "[Install]" >> /etc/systemd/system/rsh.socket && \
    echo "WantedBy=sockets.target" >> /etc/systemd/system/rsh.socket

# Configure systemd service for rsh
RUN echo "[Unit]" > /etc/systemd/system/rsh@.service && \
    echo "Description=RSH Server" >> /etc/systemd/system/rsh@.service && \
    echo "" >> /etc/systemd/system/rsh@.service && \
    echo "[Service]" >> /etc/systemd/system/rsh@.service && \
    echo "ExecStart=-/usr/sbin/in.rshd -aL" >> /etc/systemd/system/rsh@.service && \
    echo "StandardInput=socket" >> /etc/systemd/system/rsh@.service && \
    echo "StandardError=journal" >> /etc/systemd/system/rsh@.service

# Configure systemd socket for rlogin
RUN echo "[Unit]" > /etc/systemd/system/rlogin.socket && \
    echo "Description=RLogin Server Activation Socket" >> /etc/systemd/system/rlogin.socket && \
    echo "" >> /etc/systemd/system/rlogin.socket && \
    echo "[Socket]" >> /etc/systemd/system/rlogin.socket && \
    echo "ListenStream=513" >> /etc/systemd/system/rlogin.socket && \
    echo "Accept=yes" >> /etc/systemd/system/rlogin.socket && \
    echo "" >> /etc/systemd/system/rlogin.socket && \
    echo "[Install]" >> /etc/systemd/system/rlogin.socket && \
    echo "WantedBy=sockets.target" >> /etc/systemd/system/rlogin.socket

# Configure systemd service for rlogin
RUN echo "[Unit]" > /etc/systemd/system/rlogin@.service && \
    echo "Description=RLogin Server" >> /etc/systemd/system/rlogin@.service && \
    echo "" >> /etc/systemd/system/rlogin@.service && \
    echo "[Service]" >> /etc/systemd/system/rlogin@.service && \
    echo "ExecStart=-/usr/sbin/in.rlogind -a" >> /etc/systemd/system/rlogin@.service && \
    echo "StandardInput=socket" >> /etc/systemd/system/rlogin@.service && \
    echo "StandardError=journal" >> /etc/systemd/system/rlogin@.service

# Create .rhosts file for passwordless rsh access (INSECURE - only for legacy systems)
RUN echo "+ +" > /root/.rhosts && \
    chmod 600 /root/.rhosts

# Add startup script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 111 111/udp 2049 2049/udp 514 513 512 20048

ENTRYPOINT ["/entrypoint.sh"]

