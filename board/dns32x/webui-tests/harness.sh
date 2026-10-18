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
	mkdir -p "$SANDBOX/bin" "$SANDBOX/etc/samba" "$SANDBOX/tmp" "$SANDBOX/mnt" "$SANDBOX/stubs"
	cp -r "$WWW_SRC" "$SANDBOX/www"
	# applets the scripts expect
	for a in sh ash httpd hexdump md5sum dd cut sed awk tr date realpath readlink ls head tail \
			cat sort expr touch rm mkdir chmod logger sleep grep wc basename dirname find hostname df pidof mktemp tr mv cp chown; do
		ln -sf "$BB" "$SANDBOX/bin/$a"
	done
	# run every script with the sandbox shell and redirect the absolute paths the
	# scripts use for secrets, sessions and the shared folder root into the sandbox
	for f in "$SANDBOX"/www/cgi-bin/*.cgi "$SANDBOX"/www/cgi-bin/*.sh; do
		sed -i -e "1s|^#!/bin/sh|#!$SANDBOX/bin/sh|" \
			-e "s|/etc/web-secret|$SANDBOX/etc/web-secret|g" \
			-e "s|/etc/web-session.conf|$SANDBOX/etc/web-session.conf|g" \
			-e "s|/tmp/sessions|$SANDBOX/tmp/sessions|g" \
			-e "s|/tmp/firstboot|$SANDBOX/tmp/firstboot|g" \
			-e "s|/tmp/fsl\.|$SANDBOX/tmp/fsl.|g" \
			-e "s|/etc/Alt-F|$SANDBOX/etc/Alt-F|g" \
			-e "s|/etc/samba/smb.conf|$SANDBOX/etc/smb.conf|g" \
			-e "s|/etc/samba/|$SANDBOX/etc/samba/|g" \
			-e "s|/etc/rsyncd.secrets|$SANDBOX/etc/rsyncd.secrets|g" \
			-e "s|/etc/inetd.conf|$SANDBOX/etc/inetd.conf|g" \
			-e "s|/mnt|$SANDBOX/mnt|g" "$f"
	done
	cp "$HERE/../customroot/etc/web-session.conf" "$SANDBOX/etc/"
	cp "$HERE/../customroot/etc/samba/smb.conf" "$SANDBOX/etc/smb.conf"
	cp "$HERE/../customroot/etc/inetd.conf" "$SANDBOX/etc/inetd.conf"
	echo "test" > "$SANDBOX/etc/Alt-F"
	for c in smartctl plabel tune2fs blkid smbstatus showmount smbpasswd chpasswd; do
		printf '#!/bin/sh\nexit 1\n' > "$SANDBOX/stubs/$c"; chmod +x "$SANDBOX/stubs/$c"
	done
	# df: pretend the disk is almost full while $SANDBOX/df-small exists (upload tests)
	printf '#!/bin/sh\nif [ -f "%s/df-small" ]; then echo "Filesystem 1K-blocks Used Available Use%% Mounted on"; echo "/dev/fake 1000 990 10 99%% /mnt"; else exec "%s" df "$@"; fi\n' "$SANDBOX" "$BB" > "$SANDBOX/stubs/df"
	chmod +x "$SANDBOX/stubs/df"
	# loadsave_settings: "-ls" lists saved settings (none here), "-st" says nothing changed
	printf '#!/bin/sh\ncase "$1" in -ls) exit 0 ;; *) exit 1 ;; esac\n' > "$SANDBOX/stubs/loadsave_settings"
	chmod +x "$SANDBOX/stubs/loadsave_settings"
	: > "$SANDBOX/etc/rsyncd.secrets"
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
