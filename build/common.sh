# Shared settings for the build scripts. Sourced, not run.
# shellcheck shell=sh disable=SC2034 # settings for the scripts that source this

NETBSD_VERSION=11.1
# Any NetBSD mirror works: the files are checked against build/netbsd-*.sha512.
NETBSD_MIRROR=${NETBSD_MIRROR:-https://cdn.netbsd.org/pub/NetBSD}
NETBSD_URL=$NETBSD_MIRROR/NetBSD-$NETBSD_VERSION
NETBSD_SETS="base comp etc games man misc modules rescue text"

IMAGE_SIZE=64G

QEMU_VERSION=10.1.5
QEMU_SHA512=c003c1175b3ee09a72a1523e4c7ab02e5538b482315d33d04fb0b8d321b4a002f3785012bb013bd20331f89022d9b604bb224d55a0d9f313edacbc9dcbac0e6d

ALPINE_VERSION=3.23.8
ALPINE_SHA512=ebcdfe1819e4c8a53cfdfc9a0bfa51ccda440698dce909b887a34209185d3a34d9028d715b38444ac2bf1b211b3721dba95ef4dab1821727077071fc382f074b
# The libraries the QEMU from mkqemu.sh links.
QEMU_LIBS="glib libslirp libfdt zlib pcre2 libintl"
# Packages in the rootfs: QEMU's libraries, ssh both ways, and sshfs to show
# NetBSD homes to Windows.
ALPINE_PACKAGES="$QEMU_LIBS openssh-client-default openssh-keygen openssh-server sshfs"

# The launcher's source. Go checks its modules against go.sum.
WSLDL_VERSION=26032000
WSLDL_SHA256=a79f0609c5ba64d558351c2e32adb8525763d21f125ab6cffffbb64522008add
GOVERSIONINFO_VERSION=v1.7.0

DISTRO_NAME=NetBSD

ROOT=$(dirname "$(dirname "$(readlink -f "$0")")")
WORK=${WORK:-/var/tmp/wsnetbsd-build}
DL=$WORK/dl

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# hash_of FILE HASH: prints FILE's SHA-256 or SHA-512, whichever HASH is.
hash_of() {
	if [ "${#2}" = 64 ]; then sha256sum "$1"; else sha512sum "$1"; fi | cut -d' ' -f1
}

# fetch URL DEST HASH: download with resume until DEST matches HASH, a SHA-256
# or SHA-512.
fetch() {
	[ -f "$2" ] && [ "$(hash_of "$2" "$3")" = "$3" ] && return 0
	mkdir -p "$(dirname "$2")"
	i=0
	while [ "$i" -lt 30 ]; do
		i=$((i + 1))
		wget -c -q -T 20 -O "$2" "$1" || true
		[ "$(hash_of "$2" "$3")" = "$3" ] && return 0
		sleep 2
	done
	die "could not download $1"
}

# fetch_netbsd PATH DEST: fetches PATH, relative to the release directory on
# the mirror, and checks it against the hash this repository pins.
fetch_netbsd() {
	h=$(sed -n "s|^SHA512 ($1) = ||p" "$ROOT/build/netbsd-$NETBSD_VERSION.sha512" | tr -d '\r')
	[ -n "$h" ] || die "$1 has no hash in build/netbsd-$NETBSD_VERSION.sha512"
	fetch "$NETBSD_URL/$1" "$2" "$h"
}
