# wsNetBSD

NetBSD 11.1 as a WSL distribution. `wsl -d NetBSD` opens a NetBSD shell, and
commands, pipes, exit codes and the working directory pass through as they do
for Linux distributions.

WSL can only run Linux, so the distribution is an Alpine Linux layer that boots
NetBSD's MICROVM kernel under KVM and hands every session to it. NetBSD starts
with the first session and halts a few seconds after the last one ends.

## Requirements

- Windows 11 on x64, with virtualization enabled in the firmware
- An up-to-date WSL (`wsl --update`)
- Nested virtualization in WSL, which Windows 11 enables by default

## Install

Download `NetBSD-VERSION.zip` from the releases page and extract it where the
distribution should live; its disk is stored in the same folder. Run
`NetBSD.exe`. The first run installs the distribution. The next one asks for a
user name for NetBSD.

Or install the `.wsl` file, which WSL stores in its usual place. WSL asks for
the user name on the first launch:

```
wsl --install --from-file NetBSD-VERSION.wsl
```

## Quick start

```
NetBSD.exe                 # or: wsl -d NetBSD
wsl -d NetBSD uname -a
dir | wsl -d NetBSD wc -l
```

The user you create on first run joins `wheel`. root has no password, so `su`
works, as does `wsl -d NetBSD -u root`. With the `.wsl` install the user is
the default at once. With `NetBSD.exe` it becomes the default after you close
every NetBSD window and NetBSD halts, because WSL restarts the distribution to
apply it.

## Usage

### Windows drives

Windows drives are at `/mnt/c` and so on, as in other distributions.

### Windows programs

Programs on the Windows PATH run by name, as in WSL:

```
notepad.exe notes.txt
explorer.exe .
cmd.exe /c ver
```

NetBSD cannot execute a `.exe` by its path, so use `winexec` for programs that
are not on the PATH:

```
winexec "/mnt/c/Program Files/App/app.exe" --help
```

A Windows program starts in the current directory when it is under `/mnt` or
in your home directory, and in your home directory otherwise. `wslpath`
translates paths with the same options as in WSL.

### Ports

TCP ports that NetBSD programs listen on are forwarded to Windows `localhost`
within a second or two, including ports open only on `127.0.0.1` or `::1`. A
port that another WSL distribution is using is forwarded once it is free.

### Graphical programs

X11 programs open on the Windows desktop through WSLg, and PulseAudio programs
play through Windows:

```
xclock &
```

X11's own programs are included, and OpenGL programs run on Mesa's llvmpipe
renderer, on all of WSL's CPUs. For programs from pkgsrc that draw their own
text, install a font:

```
PKG_PATH=https://cdn.netbsd.org/pub/pkgsrc/packages/NetBSD/x86_64/11.1/All pkg_add dejavu-ttf
```

NetBSD halts a few seconds after the last terminal closes, and takes any
graphical programs with it. Wayland and GPU acceleration are not available.
Frames reach Windows over a network connection, so a full-screen OpenGL
program manages only a few frames per second.

### OpenGL ES and OpenCL

NetBSD's own Mesa has no OpenGL ES libraries. Mesa from pkgsrc adds them, and
also renders with llvmpipe:

```
PKG_PATH=https://cdn.netbsd.org/pub/pkgsrc/packages/NetBSD/x86_64/11.1/All pkg_add MesaLib
```

OpenCL runs on the CPU with PoCL, which brings LLVM and clang, about 220 MB.
`opencl-headers` is for building OpenCL programs:

```
PKG_PATH=https://cdn.netbsd.org/pub/pkgsrc/packages/NetBSD/x86_64/11.1/All pkg_add pocl opencl-headers
```

### Your files from Windows

While you have a NetBSD window open, your NetBSD home directory is at
`\\wsl.localhost\NetBSD\home\USER`. root's home is not shared.

### Environment

Variables named in `WSLENV` reach NetBSD, as do the ones Windows Terminal sets.
`LANG` is `C.UTF-8` unless `WSLENV` brings another. The host name is the
Windows computer name.

### More users

Each NetBSD user needs a matching account in the Alpine layer. To add one:

```
wsl -d NetBSD -u root -e /usr/libexec/wsnetbsd/adduser NAME
```

An existing NetBSD account keeps its uid. Then `wsl -d NetBSD -u NAME`.

### The Alpine layer

`wsl -d NetBSD -e /bin/sh` opens a shell in Alpine instead of NetBSD, and does
not start NetBSD.

### Settings

`/etc/wsnetbsd.conf` in the Alpine layer can set these:

| Setting | Default | |
|---|---|---|
| `MAX_MEMORY_MIB` | 8192 | NetBSD gets half of WSL's memory, up to this |
| `IDLE_HALT_SECONDS` | 5 | How long NetBSD keeps running after the last session ends |
| `NO_FORWARD_PORTS` | 22 | Ports never forwarded to Windows, separated by spaces |

For example:

```
wsl -d NetBSD -u root -e sh -c 'echo MAX_MEMORY_MIB=4096 >> /etc/wsnetbsd.conf'
```

They apply the next time the distribution starts. Keep `IDLE_HALT_SECONDS`
well under 15: WSL
stops the distribution 15 seconds after the last session, and NetBSD needs
about 3 seconds to halt.

### Disk

NetBSD has a 64 GB disk, stored as a file that grows as you use it. The file
does not shrink when you delete files in NetBSD, which reuses the space. To
give that space back:

```
wsl -d NetBSD -u root -e /usr/libexec/wsnetbsd/compact
```

It fills NetBSD's free space with zeros, which QEMU leaves out of the file.
That takes about 20 minutes for 50 GB of free space, and until it finishes
programs in NetBSD can run out of disk space. Windows gets the space back if the distribution's virtual
disk is sparse: `wsl --manage NetBSD --set-sparse true`.

## Troubleshooting

### "NetBSD did not start"

The message shows the last lines of the log. The full logs are in the Alpine
layer:

```
wsl -d NetBSD -e cat /run/wsnetbsd/monitor.log
wsl -d NetBSD -e cat /run/wsnetbsd/console.log
```

If `wsl -d NetBSD -e ls -l /dev/kvm` finds no `/dev/kvm`, WSL has no nested
virtualization. Check that virtualization is on in the firmware, and that
`%USERPROFILE%\.wslconfig` does not turn it off:

```
[wsl2]
nestedVirtualization=true
```

Then run `wsl --shutdown` and start NetBSD again.

### NetBSD boots but logins fail

When NetBSD's ssh server does not answer, for example after a change to
`/etc/rc.conf` or `/etc/ssh/sshd_config`, or when the boot stops for a file
system check, use NetBSD's serial console. It has a login prompt, and root
has no password there either:

```
wsl -d NetBSD -u root -e /usr/libexec/wsnetbsd/console
```

Ctrl-] detaches and leaves you logged in. Only one console can be attached at
a time. The console starts NetBSD if it is not running and keeps it running
while attached. It does not know the window size, so for full-screen programs
set it, as in `stty rows 40 columns 120`.

Logins work again once the ssh server answers. To restart NetBSD instead, run
`shutdown -h now` on the console and detach when it says it has halted. The
next login starts it.

### Lost changes after `wsl --shutdown`

`wsl --shutdown`, `wsl --terminate NetBSD` and shutting Windows down all stop
NetBSD without warning. The file system journal keeps the disk consistent,
but files written in the last few seconds can be lost. After closing the last
NetBSD window, NetBSD halts on its own within `IDLE_HALT_SECONDS`. The next
start after a stop without warning takes a few seconds longer, for a full file
system check.

### A Windows program says "not found on the Windows PATH"

The list of Windows programs is built from the PATH of the first session after
the distribution starts. Programs installed since then appear the next time it
starts, or after `wsl --terminate NetBSD`.

### An OpenCL program stops with "Operation not supported"

The full message is
`PTHREAD ERROR in pocl_async_callback_init():2643: Operation not supported (45)`.
PoCL starts threads, which on NetBSD works only in a program that loaded
`libpthread` when it started. Link the program with `-pthread`, or run it with
`LD_PRELOAD=/usr/lib/libpthread.so`.

## License

The scripts in this repository are under the MIT license, in `LICENSE`. The
release also contains NetBSD, Alpine Linux, QEMU and wsldl, each under its own
license. QEMU is under the GPL, version 2, and is built from the source that
`build/common.sh` names, with the patch in `build/qemu/`.
