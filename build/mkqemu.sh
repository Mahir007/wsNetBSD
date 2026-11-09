#!/bin/sh
# Builds a QEMU that can only run a KVM microvm with the devices this project
# uses. Run on Alpine, so the binary links against the libraries in the rootfs.
set -eu
. "$(dirname "$(readlink -f "$0")")/common.sh"

apk add --no-cache -q build-base meson ninja python3 pkgconf bash perl flex bison \
	linux-headers glib-dev libslirp-dev attr-dev dtc-dev zlib-dev

SRC=$WORK/qemu-$QEMU_VERSION
TAR=$DL/qemu-$QEMU_VERSION.tar.xz
fetch "https://download.qemu.org/qemu-$QEMU_VERSION.tar.xz" "$TAR" "$QEMU_SHA512"

rm -rf "$SRC"
mkdir -p "$WORK"
tar -xJf "$TAR" -C "$WORK"
patch -d "$SRC" -p1 < "$ROOT/build/qemu/9p-readdir-skip-unstatable.patch"
cp "$ROOT/build/qemu/microvm-wsl.mak" "$SRC/configs/devices/x86_64-softmmu/"

log "configuring QEMU $QEMU_VERSION"
mkdir "$SRC/out"
cd "$SRC/out"
../configure --target-list=x86_64-softmmu \
	--without-default-features --without-default-devices \
	--with-devices-x86_64=microvm-wsl \
	--enable-kvm --enable-slirp --enable-virtfs --enable-attr --enable-fdt=system \
	--disable-tcg --disable-install-blobs --disable-docs --disable-tools \
	--disable-guest-agent --enable-trace-backends=nop --extra-cflags=-Os

log "compiling"
ninja qemu-system-x86_64

mkdir -p "$WORK/out/qemu"
install -m 755 qemu-system-x86_64 "$WORK/out/qemu/"
strip "$WORK/out/qemu/qemu-system-x86_64"
install -m 644 ../pc-bios/qboot.rom "$WORK/out/qemu/"
log "built $WORK/out/qemu ($(du -sk "$WORK/out/qemu" | cut -f1) KiB)"
ldd "$WORK/out/qemu/qemu-system-x86_64"
