%global specver 1.0.0
%define git_hash %(if [ -n "$GIT_HASH" ]; then echo "$GIT_HASH"; else git rev-parse --short HEAD 2>/dev/null || echo nogit; fi)
%global appimage ghcr.io/gemini-rtsw/nfsv2-bootserver

Name:           nfsv2-bootserver
Version:        %{specver}
Release:        1.git%{git_hash}%{?dist}
Summary:        NFSv2 boot server for VxWorks and RTEMS VME clients
License:        Proprietary
Source0:        %{name}-%{version}.tar.gz
BuildArch:      noarch
BuildRequires:  systemd-rpm-macros

%description
NFSv2 + TFTP + NTP + rsh boot server for legacy VME clients, shipped as a
container and deployed by systemd.

The container image is generic. Site configuration -- export paths, client
lists, routes, container IP -- lives entirely in the variant subpackages
below, so adding a client is a config edit and a restart, never a rebuild.
Install exactly one variant per host.

%package tcs
Summary:        NFSv2 boot server configuration for the TCS (RTEMS VME) host
Requires:       systemd
# Docker itself is deliberately not a hard Requires: package names differ
# between docker-ce and the distro's podman-docker, and a wrong name blocks
# install. The unit declares Requires=docker.service, which is the real check.
Conflicts:      %{name}-altair
%description tcs
Configuration and systemd unit for the TCS boot server: exports /gem_sw to the
RTEMS VME clients and serves TFTP from / so the bootloader's absolute paths
resolve.

%package altair
Summary:        NFSv2 boot server configuration for the Altair (VxWorks) host
Requires:       systemd
# Docker itself is deliberately not a hard Requires: package names differ
# between docker-ce and the distro's podman-docker, and a wrong name blocks
# install. The unit declares Requires=docker.service, which is the real check.
Conflicts:      %{name}-tcs
%description altair
Configuration and systemd unit for the Altair boot server: exports /export to
the VxWorks clients and serves TFTP from the same directory.

%prep
%autosetup

%build
for v in tcs altair; do
  # Pin the NVR-unique tag, not :%{version}. build_app_image.sh pushes both,
  # but :%{version} is retagged by every build of the same version -- pinning
  # it would mean `dnf downgrade` moves the RPM back while the host keeps
  # pulling whatever last claimed that tag. :%{version}-git<hash> is 1:1 with
  # the RPM NVR, so the unit names exactly one immutable image.
  sed -e 's|@IMAGE@|%{appimage}:%{version}-git%{git_hash}|g' \
      -e "s|@VARIANT@|${v}|g" \
      deploy/%{name}.service.in > %{name}-${v}.service
  if grep -q '@IMAGE@\|@VARIANT@' %{name}-${v}.service; then
    echo "ERROR: placeholder not substituted in ${v} unit" >&2; exit 1
  fi
done

%install
for v in tcs altair; do
  install -Dpm 0644 %{name}-${v}.service   %{buildroot}%{_unitdir}/%{name}-${v}.service
  install -Dpm 0644 config/${v}/sysconfig  %{buildroot}%{_sysconfdir}/sysconfig/%{name}-${v}
  # exports must be root-owned and non-world-writable or rpc.mountd refuses it.
  # A bind mount carries host ownership through, so the mode set here is the
  # mode mountd sees inside the container.
  install -Dpm 0644 config/${v}/exports    %{buildroot}%{_sysconfdir}/%{name}/${v}/exports
  # .rhosts must not be group- or world-writable, or rshd ignores it.
  install -Dpm 0644 config/${v}/rhosts     %{buildroot}%{_sysconfdir}/%{name}/${v}/rhosts
done

%post tcs
%systemd_post %{name}-tcs.service
%preun tcs
%systemd_preun %{name}-tcs.service
# Plain postun, NOT _with_restart: an upgrade must not bounce a live boot
# server on its own. VME crates mid-boot would lose their NFS root. The admin
# restarts deliberately, when no crate is booting.
%postun tcs
%systemd_postun %{name}-tcs.service

%post altair
%systemd_post %{name}-altair.service
%preun altair
%systemd_preun %{name}-altair.service
%postun altair
%systemd_postun %{name}-altair.service

# The unit is NOT %config: it carries the image tag, so an upgrade must
# overwrite it -- that is how a new release moves the host to a new image.
# Everything under /etc/nfsv2-bootserver and /etc/sysconfig IS noreplace, so
# hand-edited client lists survive.
%files tcs
%{_unitdir}/%{name}-tcs.service
%dir %{_sysconfdir}/%{name}
%dir %{_sysconfdir}/%{name}/tcs
%config(noreplace) %{_sysconfdir}/sysconfig/%{name}-tcs
%config(noreplace) %{_sysconfdir}/%{name}/tcs/exports
%config(noreplace) %{_sysconfdir}/%{name}/tcs/rhosts

%files altair
%{_unitdir}/%{name}-altair.service
%dir %{_sysconfdir}/%{name}
%dir %{_sysconfdir}/%{name}/altair
%config(noreplace) %{_sysconfdir}/sysconfig/%{name}-altair
%config(noreplace) %{_sysconfdir}/%{name}/altair/exports
%config(noreplace) %{_sysconfdir}/%{name}/altair/rhosts

%changelog
* Mon Aug 24 2026 Hawi Stecher <hawi.stecher@noirlab.edu> - 1.0.0-1
- Migrate from GitLab CI to the gemini-rtsw GitHub pipeline.
- Collapse the tcs-main and main branches into one branch with per-variant
  config; ship two subpackages instead of two branches.
- Make the container image generic: exports and .rhosts are now bind-mounted
  host config rather than baked into the image.
- Adopt the fixed mountd/nfsd startup (foreground, no strace) and start
  syslogd, on both variants.
- Pin the Debian base to a dated tag and freeze apt at a snapshot so the image
  remains buildable after bullseye leaves LTS.
