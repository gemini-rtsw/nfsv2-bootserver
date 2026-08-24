#!/bin/bash
# Container entrypoint for the NFSv2 boot server.
#
# Carries NO site configuration. Everything that differs between the TCS and
# Altair boot servers arrives as environment (from the RPM's
# /etc/sysconfig/nfsv2-bootserver-<variant>) or as a bind-mounted file:
#
#   /etc/exports         NFS export list
#   /home/gemvx/.rhosts  rsh/rcp client list
#
# That is deliberate: adding a client must never require rebuilding the image.
# The Debian bullseye base is past LTS, so a rebuild is the risky operation,
# not the routine one.
set -e

NFS_EXPORT_DIR="${NFS_EXPORT_DIR:-/export}"
TFTP_ROOT="${TFTP_ROOT:-/export}"
VARIANT_LABEL="${VARIANT_LABEL:-generic}"
# Space-separated CIDR:GATEWAY pairs. NOTE: docker --env-file does not strip
# quotes, so this value must be unquoted in the sysconfig file.
EXTRA_ROUTES="${EXTRA_ROUTES:-}"

# Guarantee the log files exist so the final `tail -f` cannot fail and take
# PID 1 down with it.
mkdir -p /var/log && touch /var/log/nfsd.log /var/log/mountd-stdout.log

echo "=========================================="
echo "NFSv2 User-Space Server + TFTP"
echo "Variant: ${VARIANT_LABEL}"
echo "=========================================="
echo ""

echo "[1/8] Tuning network buffers..."
sysctl -w net.core.rmem_max=16777216 2>/dev/null || echo "  ⚠ Cannot set rmem_max (needs --privileged)"
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
echo "✓ Network tuning applied"
echo ""

echo "[2/8] Configuring routes..."
for pair in ${EXTRA_ROUTES}; do
    cidr="${pair%%:*}"
    gw="${pair##*:}"
    if [ -z "$cidr" ] || [ -z "$gw" ] || [ "$cidr" = "$gw" ]; then
        echo "  ⚠ Skipping malformed route entry: ${pair}"
        continue
    fi
    if ip route | grep -q "$cidr"; then
        echo "  route to ${cidr} already present"
        continue
    fi
    echo "  adding ${cidr} via ${gw}..."
    ip route add "$cidr" via "$gw" dev eth0 || echo "  ⚠ Could not add ${cidr} route"
done
echo "Current routes:"
ip route
echo "✓ Network routing configured"
echo ""

# mountd and nfsd log through syslog; without it their diagnostics vanish.
echo "[3/8] Starting syslog..."
syslogd || busybox syslogd || echo "⚠ Could not start syslogd"
sleep 1
echo "✓ syslog started"
echo ""

echo "[4/8] Starting rpcbind..."
rpcbind -w
sleep 2
echo "✓ rpcbind started"
echo ""

# mountd refuses an /etc/exports that is world-writable or not root-owned.
# A bind-mounted file carries the HOST's ownership straight through, so this
# check is what turns a silent no-mount into a legible error.
if [ -f /etc/exports ]; then
    perms=$(stat -c '%a' /etc/exports)
    owner=$(stat -c '%U' /etc/exports)
    if [ "$owner" != "root" ] || [ "$((0$perms & 022))" -ne 0 ]; then
        echo "⚠ WARNING: /etc/exports is ${owner}:${perms} — mountd requires root-owned, non-world-writable."
        echo "  Fix on the HOST: sudo chown root:root <file> && sudo chmod 644 <file>"
    fi
else
    echo "⚠ WARNING: no /etc/exports — nothing will be exportable."
fi

echo "[5/8] Starting rpc.mountd..."
/usr/sbin/rpc.mountd > /var/log/mountd-stdout.log 2>&1
sleep 2
if pgrep -x rpc.mountd > /dev/null 2>&1; then
    echo "✓ rpc.mountd started (PID: $(pgrep -x rpc.mountd))"
else
    echo "⚠ Warning: mountd may have exited, check logs"
    cat /var/log/mountd-stdout.log 2>/dev/null || true
fi
echo ""

echo "[6/8] Starting rpc.nfsd (NFSv2)..."
/usr/sbin/rpc.nfsd > /var/log/nfsd.log 2>&1
sleep 2
if pgrep -x rpc.nfsd > /dev/null 2>&1; then
    echo "✓ rpc.nfsd started (PID: $(pgrep -x rpc.nfsd))"
else
    echo "⚠ Warning: nfsd may have exited, check /var/log/nfsd.log"
    cat /var/log/nfsd.log 2>/dev/null || true
fi
echo ""

echo "Registered RPC services:"
rpcinfo -p localhost 2>/dev/null || echo "⚠ Could not query rpcbind"
echo ""
echo "Exports configuration:"
cat /etc/exports 2>/dev/null || true
echo ""

echo "[7/8] Starting TFTP server (root: ${TFTP_ROOT})..."
/usr/sbin/in.tftpd -l -s "${TFTP_ROOT}" -u root -c &
sleep 1
echo "✓ TFTP server started on port 69"
echo ""

echo "[8/8] Starting inetd (rsh/rexec) and NTP..."
/usr/sbin/inetd
ntpd -g -u ntp:ntp
sleep 1
echo "✓ inetd and NTP started"
echo ""

if [ -d "${NFS_EXPORT_DIR}" ]; then
    echo "✓ Export path exists: ${NFS_EXPORT_DIR} ($(stat -c '%a' "${NFS_EXPORT_DIR}"))"
else
    echo "⚠ Export path missing, creating: ${NFS_EXPORT_DIR}"
    mkdir -p "${NFS_EXPORT_DIR}"
    chmod 777 "${NFS_EXPORT_DIR}"
fi
echo ""

echo "=========================================="
echo "NFSv2 + TFTP Ready — ${VARIANT_LABEL}"
echo "  NFS export : ${NFS_EXPORT_DIR}"
echo "  TFTP root  : ${TFTP_ROOT}"
echo "  Protocol   : NFSv2"
echo "=========================================="
echo ""

# PID 1 must not exit; the daemons above have already forked into the
# background. Tailing the logs (rather than the original `tail -f /dev/null`)
# surfaces them in `docker logs` / `journalctl -u`.
exec tail -f /var/log/nfsd.log /var/log/mountd-stdout.log
