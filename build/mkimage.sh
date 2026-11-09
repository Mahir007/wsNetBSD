#!/bin/sh
# Builds the NetBSD root disk. Linux cannot write FFS, so the official live
# image runs as a builder VM and provisions a blank disk.
set -eu
. "$(dirname "$(readlink -f "$0")")/common.sh"

command -v qemu-system-x86_64 >/dev/null || die "qemu-system-x86_64 is required"
[ -w /dev/kvm ] || die "/dev/kvm is not writable"

B=$NETBSD_URL/amd64/binary
wget -q -O "$WORK/kernel.SHA512" "$B/kernel/SHA512" 2>/dev/null || { mkdir -p "$WORK"; wget -q -O "$WORK/kernel.SHA512" "$B/kernel/SHA512"; }
wget -q -O "$WORK/sets.SHA512" "$B/sets/SHA512"
wget -q -O "$WORK/images.SHA512" "$NETBSD_URL/images/SHA512"

log "fetching NetBSD $NETBSD_VERSION"
fetch "$B/kernel/netbsd-MICROVM.gz" "$DL/netbsd-MICROVM.gz" "$(sum_of "$WORK/kernel.SHA512" netbsd-MICROVM.gz)"
LIVE=NetBSD-$NETBSD_VERSION-amd64-live.img.gz
fetch "$NETBSD_URL/images/$LIVE" "$DL/$LIVE" "$(sum_of "$WORK/images.SHA512" "$LIVE")"
SHARE=$WORK/share
rm -rf "$SHARE"
mkdir -p "$SHARE/sets"
for s in $NETBSD_SETS kern-MICROVM; do
	fetch "$B/sets/$s.tar.xz" "$DL/sets/$s.tar.xz" "$(sum_of "$WORK/sets.SHA512" "$s.tar.xz")"
	ln "$DL/sets/$s.tar.xz" "$SHARE/sets/$s.tar.xz"
done

[ -f "$DL/netbsd-MICROVM" ] || gunzip -k "$DL/netbsd-MICROVM.gz"
[ -f "$DL/live.img" ] || gunzip -kc "$DL/$LIVE" > "$DL/live.img"

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
qemu-system-x86_64 \
	-M microvm,x-option-roms=off,rtc=on,acpi=off,pic=off,accel=kvm \
	-m 2048 -smp "$(nproc)" -cpu host,+invtsc \
	-kernel "$DL/netbsd-MICROVM" -append "root=dk1 console=com rw" \
	-global virtio-mmio.force-legacy=false \
	-device virtio-blk-device,drive=live \
	-drive file="$DL/live.img",format=raw,if=none,id=live,snapshot=on \
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
