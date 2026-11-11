#!/bin/sh
# Assembles the release: Alpine's minirootfs with the packages the VM needs,
# the QEMU from mkqemu.sh, the kernel and disk from mkimage.sh, and the
# overlay in alpine/. Writes NetBSD-VERSION.zip, holding the launcher from
# mklauncher.sh and rootfs.tar.gz, and NetBSD-VERSION.wsl, the same rootfs
# for `wsl --install --from-file`.
#
# VERSION defaults to 0.0.0-dev+COMMIT.
set -eu
# shellcheck source=common.sh
. "$(dirname "$(readlink -f "$0")")/common.sh"

OUT=$WORK/out
for f in kernel root.img qemu/qemu-system-x86_64 qemu/qboot.rom "$DISTRO_NAME.exe"; do
	[ -f "$OUT/$f" ] || die "$OUT/$f is missing; run mkqemu.sh, mkimage.sh and mklauncher.sh first"
done
# GNU tar for reproducible archives.
apk add --no-cache -q tar gzip zip qemu-img

commit=$(git -C "$ROOT" rev-parse --short=7 HEAD 2>/dev/null || echo unknown)
VERSION=${VERSION:-0.0.0-dev+$commit}
# Files get the commit's time, so the same commit builds the same archives.
EPOCH=$(git -C "$ROOT" log -1 --format=%ct 2>/dev/null || date +%s)

MINIROOTFS=alpine-minirootfs-$ALPINE_VERSION-x86_64.tar.gz
fetch "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION%.*}/releases/x86_64/$MINIROOTFS" \
	"$DL/$MINIROOTFS" "$ALPINE_SHA512"

R=$WORK/rootfs
log "assembling the root filesystem"
rm -rf "$R"
mkdir -p "$R"
tar -xzpf "$DL/$MINIROOTFS" -C "$R"
cp /etc/resolv.conf "$R/etc/resolv.conf"
# shellcheck disable=SC2086 # one argument per package
apk --root "$R" --no-cache --quiet add $ALPINE_PACKAGES
# WSL writes its own.
rm -f "$R/etc/resolv.conf"

cp -R "$ROOT/alpine/." "$R/"
chmod 755 "$R"/usr/libexec/wsnetbsd/*
printf '%s\n' "$VERSION" > "$R/usr/lib/wsnetbsd/version"
# Users log in to NetBSD. root does too; `wsl -e /bin/sh` reaches Alpine.
sed -i 's|^\(root:[^:]*:0:0:[^:]*:[^:]*\):.*|\1:/usr/libexec/wsnetbsd/shell|' "$R/etc/passwd"
echo /usr/libexec/wsnetbsd/shell >> "$R/etc/shells"

install -m 755 "$OUT/qemu/qemu-system-x86_64" "$R/usr/lib/wsnetbsd/"
install -m 644 "$OUT/qemu/qboot.rom" "$OUT/kernel" "$R/usr/lib/wsnetbsd/"
mkdir -p "$R/var/lib/wsnetbsd/host/keys"
# A qcow2 file holds only the blocks in use, so the 64 GB disk ships as about
# 1 GB that gzip compresses below, and QEMU boots it as it is.
log "converting the NetBSD disk"
qemu-img convert -O qcow2 "$OUT/root.img" "$R/var/lib/wsnetbsd/root.qcow2"

DIST=$OUT/dist
rm -rf "$DIST"
mkdir -p "$DIST/zip"
log "writing rootfs.tar.gz"
(cd "$R" && ls -A) | LC_ALL=C sort > "$WORK/rootfs.list"
tar -C "$R" --create --numeric-owner --sort=name --mtime="@$EPOCH" \
	--pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime \
	--files-from="$WORK/rootfs.list" | gzip -n -6 > "$DIST/zip/rootfs.tar.gz"

# No preset.json: its wslversion makes wsldl run `wsl --set-version`, which
# fails on a distribution that is already WSL 2, the default.
cp "$OUT/$DISTRO_NAME.exe" "$DIST/zip/$DISTRO_NAME.exe"
touch -d "@$EPOCH" "$DIST/zip"/*
ZIP=$DIST/$DISTRO_NAME-$VERSION.zip
WSL=$DIST/$DISTRO_NAME-$VERSION.wsl
(cd "$DIST/zip" && zip -q -X -0 "$ZIP" "$DISTRO_NAME.exe" rootfs.tar.gz)
cp "$DIST/zip/rootfs.tar.gz" "$WSL"
rm -rf "$DIST/zip"
(cd "$DIST" && for f in *.zip *.wsl; do sha256sum "$f" > "$f.sha256"; done)

for f in "$ZIP" "$WSL"; do
	log "built $f ($(du -m "$f" | cut -f1) MiB)"
done
