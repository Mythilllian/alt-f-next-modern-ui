#!/bin/sh
# Local test harness for the Alt-F web UI. Runs the real CGI scripts under a BusyBox
# httpd on your PC, with a throw-away copy of /etc, /tmp and /mnt.
#
#   BB=/path/to/busybox sh board/dns32x/webui-tests/harness.sh start|stop
#
# BB must be a BusyBox build with the httpd, ash, hexdump, md5sum and realpath applets
# (the stock x86_64 binary from busybox.net/downloads/binaries works).
# Do not run as root on a machine you care about: the scripts write to the sandbox only
# because their absolute paths are rewritten below, but some stubs are generous.

HERE=$(cd "$(dirname "$0")" && pwd)
WWW_SRC=$HERE/../customroot/usr/www
SANDBOX=${SANDBOX:-/tmp/altf-webui-test}
PORT=${PORT:-18080}
BB=${BB:-$(command -v busybox)}

setup() {
	rm -rf "$SANDBOX"
	mkdir -p "$SANDBOX/bin" "$SANDBOX/etc" "$SANDBOX/tmp" "$SANDBOX/mnt" "$SANDBOX/stubs"
	cp -r "$WWW_SRC" "$SANDBOX/www"
	# applets the scripts expect
	for a in sh ash httpd hexdump md5sum dd cut sed awk tr date realpath readlink ls head tail \
			cat sort expr touch rm mkdir chmod logger sleep grep wc basename dirname find; do
		ln -sf "$BB" "$SANDBOX/bin/$a"
	done
	# run every script with the sandbox shell and redirect the absolute paths the
	# scripts use for secrets, sessions and the shared folder root into the sandbox
	for f in "$SANDBOX"/www/cgi-bin/*.cgi "$SANDBOX"/www/cgi-bin/*.sh; do
		sed -i -e "1s|^#!/bin/sh|#!$SANDBOX/bin/sh|" \
			-e "s|/etc/web-secret|$SANDBOX/etc/web-secret|g" \
			-e "s|/etc/web-session.conf|$SANDBOX/etc/web-session.conf|g" \
			-e "s|/tmp/sessions|$SANDBOX/tmp/sessions|g" \
			-e "s|/etc/Alt-F|$SANDBOX/etc/Alt-F|g" \
			-e "s|/mnt|$SANDBOX/mnt|g" "$f"
	done
	cp "$HERE/../customroot/etc/web-session.conf" "$SANDBOX/etc/"
	echo "test" > "$SANDBOX/etc/Alt-F"
	for c in loadsave_settings smartctl plabel tune2fs blkid smbstatus showmount; do
		printf '#!/bin/sh\nexit 1\n' > "$SANDBOX/stubs/$c"; chmod +x "$SANDBOX/stubs/$c"
	done
}

start() {
	setup
	PATH="$SANDBOX/stubs:$SANDBOX/bin:/usr/bin:/bin" "$BB" httpd -f -p "$PORT" -h "$SANDBOX/www" \
		> "$SANDBOX/httpd.log" 2>&1 &
	echo $! > "$SANDBOX/httpd.pid"
	sleep 1
	echo "http://127.0.0.1:$PORT/ (sandbox $SANDBOX)"
}

stop() {
	if test -f "$SANDBOX/httpd.pid"; then kill "$(cat "$SANDBOX/httpd.pid")" 2>/dev/null; fi
}

case "$1" in
	start) start ;;
	stop) stop ;;
	setup) setup ;;
	*) echo "usage: $0 start|stop" >&2; exit 1 ;;
esac
