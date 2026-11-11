#!/bin/sh
# Builds the NetBSD root disk. Linux cannot write FFS, so the official live
# image runs as a builder VM and provisions a blank disk.
set -eu
# shellcheck source=common.sh
. "$(dirname "$(readlink -f "$0")")/common.sh"

# The builder VM runs on the QEMU this project ships, so the build needs no
# other QEMU.
QEMU_BIN=$WORK/out/qemu/qemu-system-x86_64
[ -x "$QEMU_BIN" ] || die "$QEMU_BIN is missing; run mkqemu.sh first"
[ -w /dev/kvm ] || die "/dev/kvm is not writable"
# shellcheck disable=SC2086 # word splitting is intended
apk add --no-cache -q $QEMU_LIBS

log "fetching NetBSD $NETBSD_VERSION"
fetch_netbsd amd64/binary/kernel/netbsd-MICROVM.gz "$DL/netbsd-MICROVM.gz"
LIVE=NetBSD-$NETBSD_VERSION-amd64-live.img.gz
fetch_netbsd "images/$LIVE" "$DL/$LIVE"
SHARE=$WORK/share
rm -rf "$SHARE"
mkdir -p "$SHARE/sets"
for s in $NETBSD_SETS kern-MICROVM; do
	fetch_netbsd "amd64/binary/sets/$s.tar.xz" "$DL/sets/$s.tar.xz"
	ln "$DL/sets/$s.tar.xz" "$SHARE/sets/$s.tar.xz"
done
# Outside sets/: provision.sh takes only Mesa's software renderer from it.
fetch_netbsd amd64/binary/sets/xserver.tar.xz "$DL/sets/xserver.tar.xz"
ln "$DL/sets/xserver.tar.xz" "$SHARE/xserver.tar.xz"

[ -f "$DL/netbsd-MICROVM" ] || gunzip -k "$DL/netbsd-MICROVM.gz"
[ -f "$WORK/live.img" ] || gunzip -kc "$DL/$LIVE" > "$WORK/live.img"

cp "$ROOT/build/provision.sh" "$SHARE/"
cp -R "$ROOT/guest" "$SHARE/guest"

VM=$WORK/vm
rm -rf "$VM"
mkdir -p "$VM" "$WORK/out"
IMG=$WORK/out/root.img
rm -f "$IMG"
truncate -s "$IMAGE_SIZE" "$IMG"

mkfifo "$VM/ser.in" "$VM/ser.out"
: > "$VM/builder.log"
cat "$VM/ser.out" >> "$VM/builder.log" &
READER=$!

log "booting builder VM"
"$QEMU_BIN" -L "$WORK/out/qemu" \
	-M microvm,x-option-roms=off,rtc=on,acpi=off,pic=off,accel=kvm \
	-m 2048 -smp "$(nproc)" -cpu host,+invtsc \
	-kernel "$DL/netbsd-MICROVM" -append "root=dk1 console=com rw" \
	-global virtio-mmio.force-legacy=false \
	-device virtio-blk-device,drive=live \
	-drive file="$WORK/live.img",format=raw,if=none,id=live,snapshot=on \
	-device virtio-blk-device,drive=target \
	-drive file="$IMG",format=raw,if=none,id=target,cache=unsafe \
	-fsdev local,id=share,path="$SHARE",security_model=none \
	-device virtio-9p-device,fsdev=share,mount_tag=share \
	-device virtio-rng-device \
	-display none -no-reboot -nodefaults -serial pipe:"$VM/ser" &
QEMU=$!
trap 'kill $QEMU $READER 2>/dev/null || true' EXIT

# waitfor REGEX SECONDS
waitfor() {
	n=$(($2 * 4))
	while [ "$n" -gt 0 ]; do
		tr -d '\r' < "$VM/builder.log" | grep -q "$1" && return 0
		kill -0 "$QEMU" 2>/dev/null || die "builder VM exited; see $VM/builder.log"
		sleep 0.25
		n=$((n - 1))
	done
	die "timed out waiting for '$1'; see $VM/builder.log"
}
send() { printf '%s\n' "$1" > "$VM/ser.in"; }

waitfor 'login: *$' 120
send root
waitfor '^netbsd# *$' 30
log "provisioning (see $VM/builder.log)"
send 'mkdir -p /tmp/h && mount_9p -cu /dev/vio9p0 /tmp/h && sh /tmp/h/provision.sh; echo PROVISION-""DONE=$?'
waitfor 'PROVISION-DONE=' 1200
tr -d '\r' < "$VM/builder.log" | grep -q 'PROVISION-DONE=0' || die "provisioning failed; see $VM/builder.log"

kill "$QEMU" 2>/dev/null || true
wait "$QEMU" 2>/dev/null || true
cp "$DL/netbsd-MICROVM" "$WORK/out/kernel"
log "built $IMG ($(du -m "$IMG" | cut -f1) MiB allocated, $IMAGE_SIZE apparent)"
