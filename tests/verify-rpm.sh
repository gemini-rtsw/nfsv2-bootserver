#!/bin/bash
# Checks CI cannot infer. Run from the repo root with the built RPMs in rpms/.
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
# `grep -q X && fail` would exit 1 under `set -e` when grep finds nothing,
# ending the script silently as a pass. Always use an explicit if.
refute() { if grep -q "$1" "$2"; then fail "$3"; fi; }
# Directives only -- the units carry comments that legitimately mention
# ":latest" and the placeholder names while explaining why they are not used.
directives() { grep -v '^[[:space:]]*#' "$1" > "$1.directives"; echo "$1.directives"; }

for v in tcs altair; do
  rpm=$(ls rpms/nfsv2-bootserver-$v-*.rpm 2>/dev/null | head -1) \
    || fail "no $v subpackage built"
  [ -n "$rpm" ] || fail "no $v subpackage built"

  d=$(mktemp -d)
  trap 'rm -rf "$d"' EXIT
  ( cd "$d" && rpm2cpio "$OLDPWD/$rpm" | cpio -idm --quiet )

  unit="$d/usr/lib/systemd/system/nfsv2-bootserver-$v.service"
  [ -f "$unit" ] || fail "$v: unit not in package"

  # The unit must pin a real version tag, never :latest -- otherwise `rpm -q`
  # stops telling you what the host actually runs.
  dir=$(directives "$unit")
  grep -q 'Environment=IMAGE=ghcr.io/gemini-rtsw/nfsv2-bootserver:[0-9]' "$dir" \
    || fail "$v: unit does not pin a versioned image"
  refute ':latest'            "$dir" "$v: unit pins :latest"
  refute '@IMAGE@\|@VARIANT@' "$dir" "$v: unsubstituted placeholder in unit"

  # Splitting one export path across several lines silently disables the later
  # lines in nfs-user-server -- the failure mode behind the Dec 2025 outage.
  exports="$d/etc/nfsv2-bootserver/$v/exports"
  [ -f "$exports" ] || fail "$v: exports not in package"
  dupes=$(grep -v '^[[:space:]]*#' "$exports" | awk 'NF {print $1}' | sort | uniq -d)
  [ -z "$dupes" ] || fail "$v: exports splits a path across lines: $dupes"

  # Config must be noreplace, or a routine upgrade wipes the client list.
  conf=$(rpm -qpc "$rpm" 2>/dev/null)
  for f in "/etc/nfsv2-bootserver/$v/exports" \
           "/etc/nfsv2-bootserver/$v/rhosts" \
           "/etc/sysconfig/nfsv2-bootserver-$v"; do
    echo "$conf" | grep -qx "$f" || fail "$v: $f is not marked %config"
  done

  # The unit must NOT be %config: it carries the image tag and has to be
  # overwritten on upgrade for a new release to move the host to a new image.
  if echo "$conf" | grep -q "nfsv2-bootserver-$v.service"; then
    fail "$v: unit is %config; upgrades would not move the image tag"
  fi

  rm -rf "$d"; trap - EXIT
  echo "OK: $v"
done
echo "All RPM checks passed."
