#!/bin/sh
# Syntax-check every web script, then run the harness tests.
#   BB=/path/to/busybox sh board/dns32x/webui-tests/run-all.sh
# shellcheck (optional): SHELLCHECK=/path/to/shellcheck

HERE=$(cd "$(dirname "$0")" && pwd)
CGI=$HERE/../customroot/usr/www/cgi-bin
rc=0

echo "== sh -n"
for f in "$CGI"/*.cgi "$CGI"/*.sh; do
	if ! sh -n "$f" 2>/dev/null; then echo "syntax error: $f"; rc=1; fi
done
if [ -n "$BB" ]; then
	for f in "$CGI"/*.cgi "$CGI"/*.sh; do
		if ! "$BB" sh -n "$f" 2>/dev/null; then echo "BusyBox ash syntax error: $f"; rc=1; fi
	done
fi
[ $rc -eq 0 ] && echo "all scripts parse"

if [ -n "$SHELLCHECK" ]; then
	echo "== shellcheck (new and rewritten scripts)"
	( cd "$CGI" && "$SHELLCHECK" -s sh -S warning -e SC1091,SC3046,SC3051,SC2034,SC3037,SC3021,SC2046 \
		home.cgi shares.cgi advanced.cgi classic.cgi confirm.cgi files.cgi files_list.cgi \
		files_get.cgi login.cgi logout.cgi fs_common.sh ) || rc=1
fi

for t in test-auth test-files; do
	echo "== $t"
	sh "$HERE/$t.sh" || rc=1
done
exit $rc
