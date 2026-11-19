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
| `/gemini` symlink | — | `→ /export/gemini` |
| seeded subtree | — | `/export/gemini/altair/V3-7gate` |
| RPM | `nfsv2-bootserver-tcs` | `nfsv2-bootserver-altair` |

### How TCS clients reach `/gemini`

`/gemini` is a **separate export**, not part of `/gem_sw`. The three protocols
reach it differently:

| protocol | path | works because |
|---|---|---|
| TFTP | `/gemini/GEM8.6/...` | TCS sets `TFTP_ROOT=/`, so absolute paths resolve |
| rsh/rcp | `/gemini/...` | `in.rshd` does not chroot; the bind mount is just there |
| NFS | `nfsMount(ip, "/gemini", ...)` | **a second mount** — it does not appear under `/gem_sw` |

That second NFS mount is the one thing to remember: a client that mounts only
`/gem_sw` will not see the GEM8.6 tree, and the failure looks like missing
files rather than a missing mount.

**The two hosts reach `/gemini` differently, and the approaches are not
interchangeable.** TCS exports `/gem_sw`, which has no `gemini` subtree, so it
bind-mounts the host's `/gemini` in and exports it as a second path. Altair
exports `/export`, which already *contains* `gemini/`, reached through the
container symlink. Adding a `/gemini` bind mount on Altair would shadow that
symlink and show clients an empty tree; if a GEM8.6 package has to be
installed on the Altair host, make the host's `/gemini` a symlink to
`/export/gemini` instead. The entrypoint warns if it finds a non-symlink where
a symlink was configured.

The `/gemini` symlink is not cosmetic: Altair clients `rsh`/`rcp` in as `gemvx`
and address `/gemini` by absolute path. It is created at startup rather than
baked into the image because its target is the bind-mounted export, which does
not exist at build time. Both it and the seeded subtree come from
`EXPORT_SYMLINKS` and `SEED_DIRS` in the Altair sysconfig; TCS sets neither.

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

## You must restart the service yourself

**Nothing restarts the boot server for you.** Installing or upgrading the RPM,
and editing `/etc/nfsv2-bootserver/<variant>/*` or
`/etc/sysconfig/nfsv2-bootserver-<variant>`, only changes files on disk. The
running container keeps the old exports, settings and image until:

```bash
sudo systemctl restart nfsv2-bootserver-tcs
```

This is deliberate: the RPM's `%postun` uses `%systemd_postun`, not
`_with_restart`, because a restart in the middle of a crate's boot breaks that
boot. So:

- **Schedule the restart.** It interrupts NFS, TFTP and rsh for *every* crate
  on the server, not just the one you changed. Do it when no crate is booting
  and the instruments using the server are idle.
- **After an upgrade, pull the new image first** (see "Deploying"), or the
  restart takes the server down.
- **Check it came back**: `docker ps --filter name=nfsv2` shows the container
  `Up` and staying up, and `showmount -e <container IP>` from another host
  lists the exports you expect.
- IOC packages that only install files (gmoscc, gnirscc, pwfs, scs_mk, ...)
  need no boot-server restart: the crate reads the new files at its next boot.
  A restart is needed only when this package or its config changes.

## Adding or changing a client

No rebuild. Edit the config on the host and restart:

```bash
sudoedit /etc/nfsv2-bootserver/tcs/exports     # or .../altair/exports
sudoedit /etc/nfsv2-bootserver/tcs/rhosts
sudo systemctl restart nfsv2-bootserver-tcs
```

Both files are `%config(noreplace)`, so hand edits survive `dnf upgrade`. Push
the same edit to this repo so a fresh install starts from the right list.

Where sudo doesn't cover an editor (mkotcsboot-lv1's `software` sudo is only
dnf/yum/rpm/systemctl/journalctl), make the change here instead: PR, merge,
install the new build by full NVR, pull its image, restart. Check
`rpm -V nfsv2-bootserver-tcs` first: if the host copies were hand-edited, the
RPM writes `.rpmnew` files and you merge them yourself.

A crate whose IOC installs outside `/gemini` needs its directory bind-mounted
into the container (`EXTRA_DOCKER_ARGS` in the sysconfig) and its own export
line. Example: the SCS boots from `/gem_base/epics/ioc/scs_mk`, bound
read-only and exported to 10.2.2.107 only (`cd819b2`). Don't add such a path
to `EXTRA_EXPORT_DIRS`: the unit chmods those 0777 on the host.

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
and is deliberately not a config file. Do them in this order:

```bash
# 1. Install the exact build -- never a bare `dnf upgrade` (see below)
sudo dnf --refresh install nfsv2-bootserver-tcs-<full NVR>
rpm -q nfsv2-bootserver-tcs

# 2. Pull the image the new unit pins, BEFORE restarting
IMG=$(sed -n 's/^Environment=IMAGE=//p' /usr/lib/systemd/system/nfsv2-bootserver-tcs.service)
docker pull "$IMG"                         # as a docker-group user with a GHCR login

# 3. Restart while no crate is booting (see "You must restart the service yourself")
sudo systemctl restart nfsv2-bootserver-tcs
docker ps --filter name=nfsv2 --format '{{.Names}} {{.Status}}'   # nfsv2-tcs Up ...
```

Then check the exports from another host on the crates' network (the host
can't reach its own ipvlan container, and `showmount -e <host name>` shows the
host's own NFS, not the container's):

```bash
showmount -e 10.2.2.145                    # TCS container IP
```

**Install by full NVR, never `dnf upgrade`.** Releases are `1.git<hash>`, and
RPM compares the hash as text, not by date. On 2026-11-18 `dnf upgrade` on
mkotcsboot-lv1 picked an August build (`efa0b91`) over the current ones
because `e` sorts after `5` and `c`; that build lacked four crates' exports.
`install <full NVR>` works in either direction; `dnf downgrade` refuses when
the target happens to sort higher.

Rollback: `sudo dnf install nfsv2-bootserver-tcs-<previous full NVR>` and
restart. The older RPM's unit pins the older image, which is still in the
local store, so no pull is needed.

### The image must be local before the restart

The unit runs `docker pull` as **root**, not as you. The `gemini-rtsw` org
disables both Public and Internal package visibility, so this package is
necessarily Private and there is no credential-free path — root needs a token
on every boot server, once:

```bash
echo "<PAT>" | sudo -H docker login ghcr.io -u <user> --password-stdin
```

`-H` forces `HOME=/root`. Without it sudo may keep your `HOME`, report success,
and the unit still fails. (`su -` first is equivalent.) The PAT must be a
**classic** token with `read:packages`; GHCR refuses fine-grained tokens.

**On mkotcsboot-lv1 root has no GHCR login** (as of 2026-11-18), and the team's
sudo there doesn't allow `docker` as root. Instead, pull the pinned image as
`software` (docker group, has a GHCR login) before restarting, as in
"Deploying". Skipping that took the TCS boot server down for about three
minutes on 2026-11-18: the journal showed

```
Error response from daemon: Head "https://ghcr.io/v2/gemini-rtsw/nfsv2-bootserver/manifests/1.0.0-gitcd819b2": unauthorized
Unable to find image 'ghcr.io/gemini-rtsw/nfsv2-bootserver:1.0.0-gitcd819b2' locally
```

and the unit sat in `activating (auto-restart)`. Fix: `docker pull` as
software, then restart again (or roll back by full NVR).

A missing or expired credential is not fatal to a *running* server:
`ExecStartPre=-/usr/bin/docker pull` has a leading `-`, so a failed pull is
ignored and the service keeps running the image it already has. It is fatal on
a fresh install, and on the first restart after an upgrade — the unit pins a
new `<version>-git<hash>` tag that is not in the local image store, so
`docker run` cannot start it and systemd reports the unit failed. That is the
intended behaviour: the alternative is a host quietly running something other
than what `rpm -q` claims.

Note that installing the RPM does not restart the service (deliberately — see
"You must restart the service yourself"), so between upgrade and restart `rpm -q` legitimately reports a newer
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
