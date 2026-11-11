#!/bin/sh
# Runs inside the builder VM. ld1 is the blank target disk; the build share is
# mounted at /tmp/h.
set -eu
H=/tmp/h
T=/tmp/t

newfs -O 2 /dev/rld1a
mkdir -p "$T"
mount -o async /dev/ld1a "$T"

for f in "$H"/sets/*.tar.xz; do
	echo "extracting ${f##*/}"
	tar -xJpf "$f" -C "$T"
done
# Mesa's software renderer, the one file of the X servers' set NetBSD needs.
# Without it OpenGL programs exit with an X error: WSLg's X server refuses
# the indirect rendering Mesa falls back to.
dri=./usr/X11R7/lib/modules/dri
tar -xJpf "$H/xserver.tar.xz" -C "$T" \
	$dri/gallium_dri.so $dri/gallium_dri.so.0 $dri/swrast_dri.so $dri/swrast_dri.so.0

chroot "$T" sh -c 'cd /dev && sh MAKEDEV all'
# The installer normally does this. Without it HTTPS and pkg_add fail.
chroot "$T" certctl rehash

# cp -R would copy the Windows-side mode bits the share reports.
cd "$H/guest"
find . -type d | while read -r d; do mkdir -p "$T/$d"; done
find . -type f | while read -r f; do cp "$f" "$T/$f"; chmod 644 "$T/$f"; done
chmod 555 "$T/etc/rc.d/wsnetbsd" "$T"/usr/libexec/wsnetbsd/* "$T"/usr/local/bin/*
cd /

cat >> "$T/etc/rc.conf" <<'EOF'

rc_configured=YES
hostname=netbsd
dhcpcd=NO
ifconfig_vioif0="inet 10.0.2.15 netmask 255.255.255.0"
defaultroute=10.0.2.2
sshd=YES
wsnetbsd=YES
postfix=NO
inetd=NO
fccache=NO
quota=NO
virecover=NO
savecore=NO
wscons=NO
update_motd=NO
no_swap=YES

# /etc/rc.d/wsnetbsd removes this at a clean stop. If NetBSD stopped
# without warning, or while freeing deleted files, the journal keeps the file
# system consistent but can leak those blocks. A full check finds them.
if [ -e /var/db/wsnetbsd.running ]; then fsck_flags="-f -p"; fi
EOF

# sshd uses the first value it reads, so the stock line has to go.
# /.wsl/bin holds links to Windows programs and goes last, as in WSL.
sed 's|^AuthorizedKeysFile.*|AuthorizedKeysFile .ssh/authorized_keys /.wsl/keys/%u.pub|' \
	"$T/etc/ssh/sshd_config" > "$T/etc/ssh/sshd_config.new"
mv "$T/etc/ssh/sshd_config.new" "$T/etc/ssh/sshd_config"
cat >> "$T/etc/ssh/sshd_config" <<'EOF'

SetEnv PATH=/sbin:/usr/sbin:/bin:/usr/bin:/usr/X11R7/bin:/usr/pkg/sbin:/usr/pkg/bin:/usr/local/sbin:/usr/local/bin:/.wsl/bin LANG=C.UTF-8
EOF
# shellcheck disable=SC2016 # expanded at login
for f in etc/skel/.profile root/.profile; do
	printf '\n# Windows programs\nPATH=${PATH}:/.wsl/bin\n' >> "$T/$f"
done
# shellcheck disable=SC2016 # expanded at login
for f in etc/skel/.cshrc root/.cshrc; do
	printf '\n# Windows programs\nset path = ($path /.wsl/bin)\n' >> "$T/$f"
done

# WSL kills the VM without warning when Windows shuts down. Writing dirty
# buffers sooner narrows what that loses, to about what Linux on ext4 loses.
cat >> "$T/etc/sysctl.conf" <<'EOF'

net.inet.ip.dad_count=0
net.inet6.ip6.dad_count=0
vfs.sync.filedelay=5
vfs.sync.dirdelay=4
vfs.sync.metadelay=3
EOF

mkdir -p "$T/kern" "$T/proc" "$T/mnt" "$T/.wsl"

sync
umount "$T"
fsck_ffs -fy /dev/rld1a
sync
