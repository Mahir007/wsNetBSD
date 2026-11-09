# Shared settings for the build scripts. Sourced, not run.

NETBSD_VERSION=11.1
NETBSD_URL=https://cdn.netbsd.org/pub/NetBSD/NetBSD-$NETBSD_VERSION
NETBSD_SETS="base comp etc games man misc modules rescue text"

IMAGE_SIZE=64G

QEMU_VERSION=10.1.5
QEMU_SHA512=c003c1175b3ee09a72a1523e4c7ab02e5538b482315d33d04fb0b8d321b4a002f3785012bb013bd20331f89022d9b604bb224d55a0d9f313edacbc9dcbac0e6d

ROOT=$(dirname "$(dirname "$(readlink -f "$0")")")
WORK=${WORK:-/var/tmp/wsnetbsd-build}
DL=$WORK/dl

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# fetch URL DEST SHA512: download with resume until DEST matches SHA512.
fetch() {
	[ -f "$2" ] && [ "$(sha512sum "$2" | cut -d' ' -f1)" = "$3" ] && return 0
	mkdir -p "$(dirname "$2")"
	i=0
	while [ "$i" -lt 30 ]; do
		i=$((i + 1))
		wget -c -q -T 20 -O "$2" "$1" || true
		[ "$(sha512sum "$2" | cut -d' ' -f1)" = "$3" ] && return 0
		sleep 2
	done
	die "could not download $1"
}

# sum_of SUMFILE NAME: read a hash from a BSD-format SHA512 file.
sum_of() {
	h=$(sed -n "s/^SHA512 ($2) = //p" "$1" | tr -d '\r')
	[ -n "$h" ] || die "$2 is not listed in $1"
	printf '%s\n' "$h"
}
