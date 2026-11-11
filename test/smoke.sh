#!/bin/sh
# Boots the release rootfs and checks NetBSD through the same paths WSL uses,
# except the ones that need Windows. Runs inside the rootfs, imported as a
# container with KVM:
#   docker import rootfs.tar.gz wsnetbsd
#   docker run --rm --device /dev/kvm -v "$PWD/test:/test:ro" wsnetbsd /bin/sh /test/smoke.sh
set -u
shell=/usr/libexec/wsnetbsd/shell
failed=0

# check NAME EXPECTED ACTUAL
check() {
	if [ "$2" = "$3" ]; then
		echo "ok   $1"
	else
		echo "FAIL $1: expected '$2', got '$3'"
		failed=1
	fi
}

# eventually COMMAND: runs COMMAND until it prints something, for up to 10 s.
eventually() {
	_n=0
	while [ "$_n" -lt 20 ]; do
		_out=$(eval "$1" 2>/dev/null)
		[ -z "$_out" ] || { printf '%s\n' "$_out"; return; }
		sleep 0.5
		_n=$((_n + 1))
	done
}

/usr/libexec/wsnetbsd/vmctl boot

check "runs commands in NetBSD" NetBSD "$($shell -c 'uname -s')"
$shell -c 'exit 7'
check "passes the exit code" 7 "$?"
check "passes stdin" hello "$(echo hello | $shell -c cat)"
check "keeps stderr apart" "" "$($shell -c 'echo oops >&2' 2>/dev/null)"
check "starts in the same directory" /mnt "$(cd /mnt && $shell -c pwd)"
touch /mnt/smoke
check "shares /mnt" yes "$($shell -c 'test -f /mnt/smoke && echo yes')"
check "uses the Alpine host name" "$(hostname)" "$($shell -c hostname)"

/usr/libexec/wsnetbsd/adduser alice >/dev/null
check "maps users with the same uid" "alice 1000" "$(su alice -c 'id -un; id -u' | xargs)"
check "calls into Alpine" yes \
	"$(su alice -c '/usr/libexec/wsnetbsd/hostcall time' | grep -qx '[0-9]*' && echo yes)"

$shell -c 'nohup sh -c "echo forwarded | nc -N -l 8123" >/dev/null 2>&1 &'
check "forwards listening ports" forwarded "$(eventually 'timeout 2 nc 127.0.0.1 8123 </dev/null')"
$shell -c 'nohup sh -c "echo local | nc -N -l 127.0.0.1 8124" >/dev/null 2>&1 &'
check "forwards ports open only on localhost" local "$(eventually 'timeout 2 nc 127.0.0.1 8124 </dev/null')"

check "has X11 programs on the PATH" /usr/X11R7/bin/xterm "$($shell -c 'command -v xterm')"
check "has Mesa's software renderer" yes "$($shell -c 'test -e /usr/X11R7/lib/modules/dri/swrast_dri.so && echo yes')"
# shellcheck disable=SC2016 # expanded in the guest
check "sets LANG" C.UTF-8 "$($shell -c 'echo $LANG')"
# shellcheck disable=SC2016 # expanded in the guest
check "has CA certificates" yes "$($shell -c 'test -n "$(ls /etc/openssl/certs)" && echo yes')"

# Stands in for WSLg's X server: whatever listens on its socket gets the relay.
mkdir -p /tmp/.X11-unix
(echo relayed | nc -N -l -U /tmp/.X11-unix/X0) &
n=0
until [ -S /tmp/.X11-unix/X0 ] || [ "$n" -gt 20 ]; do sleep 0.1; n=$((n + 1)); done
# shellcheck disable=SC2016 # expanded in the guest
check "sets DISPLAY when WSLg is there" 10.0.2.100:0 "$($shell -c 'echo $DISPLAY')"
check "relays WSLg's X socket" relayed "$($shell -c 'timeout 5 nc -N 10.0.2.100 6000 </dev/null')"

# No sessions are left, so the monitor halts the guest.
n=0
while [ "$n" -lt 60 ] && /usr/libexec/wsnetbsd/vmctl status >/dev/null; do
	sleep 0.5
	n=$((n + 1))
done
check "halts when idle" yes \
	"$(grep -q 'operating system has halted' /run/wsnetbsd/console.log && echo yes)"
check "boots again for a new session" NetBSD "$($shell -c 'uname -s')"
check "finds the disk clean after the halt" yes \
	"$(grep -q 'file system is clean' /run/wsnetbsd/console.log && echo yes)"

exit "$failed"
