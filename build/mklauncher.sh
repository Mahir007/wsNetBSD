#!/bin/sh
# Builds NetBSD.exe: the wsldl launcher, compiled from source with the NetBSD
# icon. The released wsldl.exe has no icon, and Windows shows a program's
# icon from its own resources.
set -eu
# shellcheck source=common.sh
. "$(dirname "$(readlink -f "$0")")/common.sh"

apk add --no-cache -q go

SRC=$WORK/wsldl-$WSLDL_VERSION
fetch "https://github.com/yuk7/wsldl/archive/refs/tags/$WSLDL_VERSION.tar.gz" \
	"$DL/wsldl-$WSLDL_VERSION.tar.gz" "$WSLDL_SHA256"
rm -rf "$SRC"
tar -xzf "$DL/wsldl-$WSLDL_VERSION.tar.gz" -C "$WORK"

# Modules go with the other downloads, which CI caches.
export GOTOOLCHAIN=local GOFLAGS="-trimpath -modcacherw" GOMODCACHE="$DL/gomod" GOCACHE="$WORK/gocache"
cd "$SRC/src"
log "building $DISTRO_NAME.exe"
# Task Manager lists the process by its description.
go run "github.com/josephspurrier/goversioninfo/cmd/goversioninfo@$GOVERSIONINFO_VERSION" \
	-64 -icon "$ROOT/alpine/usr/lib/wsnetbsd/netbsd.ico" \
	-description "$DISTRO_NAME" -original-name "$DISTRO_NAME.exe" \
	-o resource.syso versioninfo.json
mkdir -p "$WORK/out"
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build \
	-ldflags "-w -s -buildid= -X github.com/yuk7/wsldl/version.version=$WSLDL_VERSION" \
	-o "$WORK/out/$DISTRO_NAME.exe"
log "built $WORK/out/$DISTRO_NAME.exe"
