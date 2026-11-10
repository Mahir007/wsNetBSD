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
within a second or two. A program has to listen on all addresses: one that
listens only on `127.0.0.1` stays private to NetBSD.

### Your files from Windows

While you have a NetBSD window open, your NetBSD home directory is at
`\\wsl.localhost\NetBSD\home\USER`. root's home is not shared.

### Environment

Variables named in `WSLENV` reach NetBSD, as do the ones Windows Terminal sets.
The host name is the Windows computer name.

### More users

Each NetBSD user needs a matching account in the Alpine layer. To add one:

```
wsl -d NetBSD -u root -e /usr/libexec/wsnetbsd/adduser NAME
```

An existing NetBSD account keeps its uid. Then `wsl -d NetBSD -u NAME`.

### The Alpine layer

`wsl -d NetBSD -e /bin/sh` opens a shell in Alpine instead of NetBSD.

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

NetBSD has a 64 GB disk, stored as a file that grows as you use it. Deleting
files in NetBSD gives the space back.

## Troubleshooting

### "NetBSD did not start"

The message ends with the last lines of the log. The full logs are in the
Alpine layer:

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

### Lost changes after `wsl --shutdown`

`wsl --shutdown`, `wsl --terminate NetBSD` and shutting Windows down all stop
NetBSD without warning. The file system journal keeps the disk consistent,
but files written in the last few seconds can be lost. After closing the last
NetBSD window, NetBSD halts on its own within `IDLE_HALT_SECONDS`.

### A Windows program says "not found on the Windows PATH"

The list of Windows programs is built from the PATH of the first session after
the distribution starts. Programs installed since then appear the next time it
starts, or after `wsl --terminate NetBSD`.
