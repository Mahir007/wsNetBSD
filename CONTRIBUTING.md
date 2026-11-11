# Contributing

## Layout

| Path | |
|---|---|
| `alpine/` | Files copied over Alpine's minirootfs |
| `guest/` | Files copied over the NetBSD sets |
| `build/` | Build scripts, pinned hashes and the QEMU configuration |
| `test/smoke.sh` | Boots the rootfs and checks it, without Windows |

## How it works

WSL starts `vmctl boot` from `/etc/wsl.conf`. It starts the monitor, the only
process that starts or stops QEMU. The monitor boots NetBSD, and halts it when
no session has been attached for `IDLE_HALT_SECONDS`.

Every user's login shell in Alpine is `/usr/libexec/wsnetbsd/shell`. It
registers a session file in `/run/wsnetbsd/sessions`, waits for
`/run/wsnetbsd/ready`, and runs the command or a login shell in NetBSD over
ssh, through a QEMU port forward on 127.0.0.1. The monitor takes the first
free port from 22022 up, since all WSL distributions share one network
namespace, and writes it to `/run/wsnetbsd/ssh-port`.

The other direction uses a slirp `guestfwd` rule. A guest connection to
`10.0.2.100:22` makes QEMU start `sshd -i` in Alpine with
`alpine/usr/lib/wsnetbsd/sshd_config`, whose forced command is
`alpine/usr/libexec/wsnetbsd/hostcall`. The guest uses it to run Windows
programs, translate paths, forward ports and read the time. Nothing listens
on a port in WSL's network namespace, which every distribution shares.

Each user has one key pair in `/var/lib/wsnetbsd/host/keys`. That directory is
shared read-only with NetBSD as `/.wsl/keys`, and both sshds take
`keys/USER.pub` as the user's authorized key.

The guest's `watch` script sends its listening ports to `hostcall`, which adds
and removes QEMU `hostfwd` rules through the monitor FIFO. WSL forwards those
Alpine listeners to Windows. The same script resets the clock when it drifts
from Alpine's.

The monitor mounts a user's NetBSD home over their Alpine home with sshfs
while they have a session. Windows sees Alpine's files through WSL's 9p
server, and so sees the NetBSD home.

`wsl --manage --set-default-user` stops the distribution at once, so the
first-run script leaves the user in `/var/lib/wsnetbsd/default-user` and the
monitor applies it after the next idle halt.

The microvm machine has no ACPI, so NetBSD can halt but not power off. `vmctl`
halts it with `rc.shutdown` and `halt`, waits for the console to say so, and
kills QEMU. `shutdown(8)` takes too long: WSL stops the distribution 15
seconds after the last session.

## Building

The build runs on Alpine Linux x86_64, as root, with `/dev/kvm`. An Alpine WSL
distribution works, as does
`docker run --device /dev/kvm -v "$PWD:/src" -w /src alpine:3.23`. The
scripts install the packages they need with apk.

```
sh build/mkqemu.sh       # QEMU with only the microvm devices used, the slowest step
sh build/mkimage.sh      # the NetBSD disk, about 1 minute
sh build/mklauncher.sh   # NetBSD.exe, about 20 seconds
sh build/mkdist.sh       # the .zip and .wsl, about 1 minute
```

Everything goes to `WORK`, `/var/tmp/wsnetbsd-build` by default. The archives
are in `$WORK/out/dist`. `VERSION` sets the version, which defaults to
`0.0.0-dev+COMMIT`.

`mkimage.sh` cannot write FFS from Linux, so it boots NetBSD's live image as a
builder VM. `build/provision.sh` runs inside it, creates the file system on a
blank 64 GB sparse disk and extracts the sets into it. `mkdist.sh` converts
the disk to qcow2, which holds only the blocks in use and boots without
unpacking.

`mklauncher.sh` compiles wsldl from source, since the released `wsldl.exe` has
no icon. `alpine/usr/lib/wsnetbsd/netbsd.ico` is the icon for the launcher and
for the Start menu entry of a `.wsl` install.

Downloads are checked against pinned hashes: NetBSD's in
`build/netbsd-VERSION.sha512`, the others in `build/common.sh`. For a new
NetBSD release, copy the lines for the same files from the release's `SHA512`
files into a new `build/netbsd-VERSION.sha512`. `NETBSD_MIRROR` picks a
different mirror.

### QEMU

`build/qemu/microvm-wsl.mak` lists the devices QEMU is built with. QEMU's 9p
server ends a directory listing at the first entry it cannot stat, which hides
most of `/mnt/c`. `build/qemu/9p-readdir-skip-unstatable.patch` skips such
entries.

## Testing

`test/smoke.sh` boots the rootfs as a container and checks sessions, users,
the guest's calls into Alpine, port forwarding and the idle halt:

```
docker import "$WORK/out/dist/NetBSD-VERSION.wsl" wsnetbsd
docker run --rm --device /dev/kvm -v "$PWD/test:/test:ro" wsnetbsd /bin/sh /test/smoke.sh
```

Windows programs, Explorer access and the default user need a real WSL
install.

## CI and releases

`ci.yml` lints with shellcheck and actionlint, builds the archives in an
Alpine container, runs the smoke test, and checks the archive's contents and
version on Windows. Pushing a tag such as `v1.2.0` runs `release.yml`, which
builds through `ci.yml` and publishes that build. `build/release-notes.sh`
writes the notes.
