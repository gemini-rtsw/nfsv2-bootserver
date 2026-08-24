# nfsv2-bootserver

NFSv2 + TFTP + NTP + rsh boot server for the legacy VxWorks and RTEMS VME
crates at Gemini North. Ships as a container image; deployed by RPM + systemd
through the [gemini-rtsw-ci](https://github.com/gemini-rtsw/gemini-rtsw-ci)
pipeline.

The NFS server is `nfs-user-server 2.2beta47`, vendored in this repo. It is the
only NFSv2 implementation these clients still talk to, which is why it is built
from a checked-in tarball rather than a package.

## Two servers, one image

| | TCS | Altair |
|---|---|---|
| host | `mkotcsboot-lv1` | Altair boot host |
| clients | RTEMS VME | VxWorks |
| NFS export | `/gem_sw` | `/export` |
| TFTP root | `/` (bootloader sends absolute paths) | `/export` |
| container IP | 10.2.2.145 | 10.2.2.147 |
| RPM | `nfsv2-bootserver-tcs` | `nfsv2-bootserver-altair` |

**The image is generic — it contains no site configuration.** Export paths,
client lists, routes and the container IP all come from the variant's RPM at
runtime. This replaces the old arrangement of a `main` and a `tcs-main` branch
each baking its own config into its own image tag, which made the two servers
impossible to compare and left the deployed TCS config existing only inside a
running container.

Install and enable exactly one variant per host. The two subpackages
deliberately do **not** `Conflicts:` each other — they share no files, and the
pipeline installs every subpackage it builds into a single dev image, which a
`Conflicts:` breaks. Installing both starts nothing; only the unit you
`systemctl enable` runs.

## Adding or changing a client

No rebuild. Edit the config on the host and restart:

```bash
sudoedit /etc/nfsv2-bootserver/tcs/exports     # or .../altair/exports
sudoedit /etc/nfsv2-bootserver/tcs/rhosts
sudo systemctl restart nfsv2-bootserver-tcs
```

Both files are `%config(noreplace)`, so hand edits survive `dnf upgrade`. Push
the same edit to this repo so a fresh install starts from the right list.

> **One export path per line.** `nfs-user-server` takes the *first* line for a
> given path and ignores later ones, so a second `/gem_sw ...` line silently
> grants nothing. Put every client for a path on that path's single line. CI
> rejects a config that splits a path (`tests/verify-rpm.sh`).

> **`/etc/exports` must be root-owned and not world-writable**, or `rpc.mountd`
> refuses to serve. The RPM installs it `root:root 0644`; the bind mount
> carries that through to the container. The entrypoint warns loudly if it
> ever isn't.

Host-specific settings — container IP, routes, interface — live in
`/etc/sysconfig/nfsv2-bootserver-<variant>`, also `noreplace`.

> That file is read by **both** systemd and `docker --env-file`. `--env-file`
> does not strip quotes, so values must be unquoted: `VARIANT_LABEL=TCS / RTEMS
> VME`, never `VARIANT_LABEL="TCS / RTEMS VME"`.

## Deploying

```bash
sudo dnf install nfsv2-bootserver-tcs      # or -altair
sudo systemctl enable --now nfsv2-bootserver-tcs
systemctl status nfsv2-bootserver-tcs
journalctl -u nfsv2-bootserver-tcs -f      # the entrypoint's startup report
```

Upgrades move the host to a new image, because the unit carries the version tag
and is deliberately not a config file:

```bash
sudo dnf upgrade nfsv2-bootserver-tcs
sudo systemctl restart nfsv2-bootserver-tcs
rpm -q nfsv2-bootserver-tcs                # what is actually deployed
```

`dnf downgrade` is a real rollback: the older RPM's unit pins the older image.

### Root must be logged in to GHCR

The unit runs `docker pull` as **root**, not as you. The `gemini-rtsw` org
disables both Public and Internal package visibility, so this package is
necessarily Private and there is no credential-free path — root needs a token
on every boot server, once:

```bash
echo "<PAT>" | sudo -H docker login ghcr.io -u <user> --password-stdin
```

`-H` forces `HOME=/root`. Without it sudo may keep your `HOME`, report success,
and the unit still fails. (`su -` first is equivalent.) The PAT needs
`read:packages`.

A missing or expired credential is not fatal to a *running* server:
`ExecStartPre=-/usr/bin/docker pull` has a leading `-`, so a failed pull is
ignored and the service keeps running the image it already has. It is fatal on
a fresh install, and on the first restart after an upgrade — the unit pins a
new `<version>-git<hash>` tag that is not in the local image store, so
`docker run` cannot start it and systemd reports the unit failed. That is the
intended behaviour: the alternative is a host quietly running something other
than what `rpm -q` claims.

Note that `dnf upgrade` alone does not restart the service (deliberately — see
below), so between upgrade and restart `rpm -q` legitimately reports a newer
version than the running container. Confirm with:

```bash
rpm -q nfsv2-bootserver-tcs
sudo docker images ghcr.io/gemini-rtsw/nfsv2-bootserver
sudo journalctl -u nfsv2-bootserver-tcs | grep -i 'denied\|unauthorized'
```

Use a PAT with a long expiry, and note the renewal date somewhere — an expired
token turns every future upgrade into a silent no-op.

## Layout

```
Dockerfile                  generic image; no site config
scripts/start.sh            entrypoint, fully env-driven
config/{tcs,altair}/        exports, rhosts, sysconfig per variant
deploy/*.service.in         systemd unit template (@IMAGE@, @VARIANT@)
nfsv2-bootserver.spec       one spec, two subpackages
tests/verify-rpm.sh         CI checks: image pin, export syntax, %config flags
```

## Building locally

```bash
./gemini-rtsw-ci/build_rpm.sh --profile lightweight --el 9
./gemini-rtsw-ci/build_app_image.sh --no-push
./tests/verify-rpm.sh
```

## The Debian base is pinned, deliberately

`FROM debian:bullseye-20250203`, with `apt` frozen to a `snapshot.debian.org`
timestamp. Bullseye leaves LTS in August 2026; after it moves to
`archive.debian.org` an unpinned `apt-get update` fails and the image cannot be
rebuilt at all. The pin keeps the build reproducible past that date.

`snapshot.debian.org` is rate-limited and occasionally slow — fine for the
occasional rebuild this repo needs. If it becomes a problem,
`http://archive.debian.org/debian bullseye main` is the stable alternative at
the cost of getting final-LTS package versions rather than a specific date.

## History

Before August 2026 this repo had two divergent branches (`main` for Altair,
`tcs-main` for TCS) and pushed images to a now-archived GitLab registry. Both
are superseded by this layout. The old branches are kept for reference:

| branch | last commit | shipped as |
|---|---|---|
| `main` (old) | `1dfd4a7` | `nfsv2:altair` |
| `tcs-main` | `d5d291e` | `nfsv2:TCS` |

The TCS server ran image `ac88a1c4ab92`, built from the `5d1a67e` tree.
`EXECUTIVE_SUMMARY_Boot_Server_Issues_Dec2025.md` on `tcs-main` documents the
December 2025 investigation.
