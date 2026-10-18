#!/bin/sh
# Upload tests (files and folders) against the local BusyBox httpd harness.
#   BB=/path/to/busybox sh board/dns32x/webui-tests/test-upload.sh

HERE=$(cd "$(dirname "$0")" && pwd)
export SANDBOX=${SANDBOX:-/tmp/altf-webui-test}
export PORT=${PORT:-18084}
H=http://127.0.0.1:$PORT
PASS=0; FAIL=0

sh "$HERE/harness.sh" stop >/dev/null 2>&1
sh "$HERE/harness.sh" start >/dev/null || exit 1
trap 'sh "$HERE/harness.sh" stop' EXIT

ok()   { PASS=$((PASS + 1)); echo "ok   $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }

M=$SANDBOX/mnt
echo -n secretpw > "$SANDBOX/etc/web-secret"
mkdir -p "$M/Disk1/Up" "$SANDBOX/outdir"
ln -sfn "$SANDBOX/outdir" "$M/Disk1/Up/out"

salt=$(curl -s "$H/cgi-bin/login.cgi" | grep -o '[0-9a-f]\{32\}' | head -1)
hash=$(printf 'secretpw%s' "$salt" | md5sum | cut -d' ' -f1)
JAR=$SANDBOX/jar
curl -s -c "$JAR" -o /dev/null -d "salt=$salt&pwhash=$hash" "$H/cgi-bin/login_proc.cgi"

enc() { python3 -c 'import sys,urllib.parse as u; print(u.quote(sys.argv[1], safe=""))' "$1"; }
# put <folder> <name (raw, will be encoded)> <file> [extra curl args]  -> prints "<status> <body>"
put() { d=$1; n=$2; f=$3; shift 3
	curl -s -b "$JAR" -H "Origin: $H" -H 'X-Requested-With: XMLHttpRequest' -w ' %{http_code}' --data-binary "@$f" "$@" \
		"$H/cgi-bin/files_put.cgi?p=$(enc "$d")&n=$(enc "$n")"; }
putraw() { d=$1; n=$2; f=$3; shift 3   # n already encoded
	curl -s -b "$JAR" -H "Origin: $H" -H 'X-Requested-With: XMLHttpRequest' -w ' %{http_code}' --data-binary "@$f" "$@" \
		"$H/cgi-bin/files_put.cgi?p=$(enc "$d")&n=$n"; }
code() { echo "${1##* }"; }

U=$M/Disk1/Up
printf 'hello upload\n' > "$SANDBOX/a.txt"

echo "== access"
check "no session is 401" "$(curl -s -o /dev/null -w '%{http_code}' -H "Origin: $H" --data-binary @"$SANDBOX/a.txt" "$H/cgi-bin/files_put.cgi?p=$(enc "$U")&n=a.txt")" 401
check "no Origin or Referer is 403" "$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" -H 'X-Requested-With: XMLHttpRequest' --data-binary @"$SANDBOX/a.txt" "$H/cgi-bin/files_put.cgi?p=$(enc "$U")&n=a.txt")" 403
check "another site's Origin is 403" "$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" -H 'Origin: http://evil.example' --data-binary @"$SANDBOX/a.txt" "$H/cgi-bin/files_put.cgi?p=$(enc "$U")&n=a.txt")" 403
[ ! -e "$U/a.txt" ] && ok "nothing was written by the refused requests" || bad "refused request wrote a file"
check "GET without check is refused" "$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" -H 'X-Requested-With: x' "$H/cgi-bin/files_put.cgi?p=$(enc "$U")&n=a.txt")" 405
curl -s -b "$JAR" -H 'X-Requested-With: x' "$H/cgi-bin/files_put.cgi?check=1&p=$(enc "$U")" | grep -q '"free":[0-9]' && ok "free space query answers" || bad "free query"

echo "== one file"
r=$(put "$U" "a.txt" "$SANDBOX/a.txt")
check "upload succeeds" "$(code "$r")" 200
echo "$r" | grep -q '"ok":true,"name":"a.txt"' && ok "answer names the saved file" || bad "answer: $r"
cmp -s "$SANDBOX/a.txt" "$U/a.txt" && ok "bytes match" || bad "bytes differ"
check "file mode" "$(ls -l "$U/a.txt" | cut -c1-10)" "-rw-rw-r--"

echo "== names"
for n in "my photo (1).jpg" "it's \"quoted\" & more.txt" "café ☕.txt" "a<b>&amp;.txt" "semi;colon,comma #1.txt" "100%.txt" "-dash.txt" ".hidden"; do
	r=$(put "$U" "$n" "$SANDBOX/a.txt")
	if [ "$(code "$r")" = 200 ] && cmp -s "$SANDBOX/a.txt" "$U/$n"; then ok "stored under its exact name: $n"; else bad "name '$n': $r"; fi
done
long=$(python3 -c 'print("n"*255)'); r=$(put "$U" "$long" "$SANDBOX/a.txt"); check "255 character name" "$(code "$r")" 200
long=$(python3 -c 'print("n"*256)'); r=$(put "$U" "$long" "$SANDBOX/a.txt"); check "256 character name is refused" "$(code "$r")" 400

echo "== nothing is replaced"
printf 'second' > "$SANDBOX/b.txt"; printf 'third' > "$SANDBOX/c.txt"
put "$U" "dup.tar.gz" "$SANDBOX/a.txt" > /dev/null
r=$(put "$U" "dup.tar.gz" "$SANDBOX/b.txt"); echo "$r" | grep -q '"name":"dup.tar (2).gz"' && ok "second copy becomes 'dup.tar (2).gz'" || bad "dup 2: $r"
r=$(put "$U" "dup.tar.gz" "$SANDBOX/c.txt"); echo "$r" | grep -q '"name":"dup.tar (3).gz"' && ok "third copy becomes 'dup.tar (3).gz'" || bad "dup 3: $r"
cmp -s "$SANDBOX/a.txt" "$U/dup.tar.gz" && ok "the original is untouched" || bad "original changed"
r=$(put "$U" ".hidden" "$SANDBOX/b.txt"); echo "$r" | grep -q '"name":".hidden (2)"' && ok "dot file without extension" || bad "dotfile dup: $r"

echo "== folders"
r=$(put "$U" "Trip/Day 1/photos/beach.txt" "$SANDBOX/a.txt")
check "nested folder upload" "$(code "$r")" 200
cmp -s "$SANDBOX/a.txt" "$U/Trip/Day 1/photos/beach.txt" && ok "file landed in the new folders" || bad "nested file missing"
check "created folder mode" "$(ls -ld "$U/Trip/Day 1" | cut -c1-10)" drwxrwxr-x
r=$(put "$U" "Trip/Day 1/photos/beach.txt" "$SANDBOX/b.txt"); echo "$r" | grep -q 'beach (2).txt' && ok "files in existing folders also keep both copies" || bad "nested dup: $r"
r=$(put "$U/Trip" "extra/x.txt" "$SANDBOX/a.txt"); check "upload into a sub folder as the target" "$(code "$r")" 200

echo "== refused names and places"
for n in "../x.txt" "a/../../x.txt" "/abs.txt" "a//b.txt" "." ".." "a/." "a/.." "a/" "x/../y" ".upload-1" "a/.upload-2"; do
	r=$(put "$U" "$n" "$SANDBOX/a.txt"); check "refused name '$n'" "$(code "$r")" 400
done
for raw in "%0a" "x%0ay" "x%00y" "x%0d.txt" "%2e%2e%2fx" "..%2fx" "a%2f%2e%2e%2f%2e%2e%2fx" "%01x"; do
	r=$(putraw "$U" "$raw" "$SANDBOX/a.txt"); check "refused raw name '$raw'" "$(code "$r")" 400
done
[ ! -e "$M/x.txt" ] && [ ! -e "$M/Disk1/x.txt" ] && [ ! -e "$SANDBOX/x.txt" ] && ok "nothing escaped the target folder" || bad "something escaped"
r=$(put "$U" "out/evil.txt" "$SANDBOX/a.txt"); check "a symlink inside the path is refused" "$(code "$r")" 400
[ -z "$(ls "$SANDBOX/outdir")" ] && ok "nothing was written through the symlink" || bad "wrote through a symlink"
r=$(put "$U/out" "evil.txt" "$SANDBOX/a.txt"); check "a symlink as the target folder is refused" "$(code "$r")" 403
r=$(put "/etc" "evil.txt" "$SANDBOX/a.txt"); check "target outside /mnt" "$(code "$r")" 403
r=$(put "$M/../" "evil.txt" "$SANDBOX/a.txt"); check "target with .." "$(code "$r")" 403
r=$(put "$M" "evil.txt" "$SANDBOX/a.txt"); check "the all-disks root is refused" "$(code "$r")" 400
r=$(put "$U/a.txt" "evil.txt" "$SANDBOX/a.txt"); check "a file as the target" "$(code "$r")" 400
r=$(put "$U/missing" "evil.txt" "$SANDBOX/a.txt"); check "a missing target folder" "$(code "$r")" 404
mkdir -p "$M/Disk1/ro"; chmod 555 "$M/Disk1/ro"; r=$(put "$M/Disk1/ro" "x.txt" "$SANDBOX/a.txt"); check "read-only folder" "$(code "$r")" 403; chmod 755 "$M/Disk1/ro"

echo "== disk space"
: > "$SANDBOX/df-small"
r=$(put "$U" "full.txt" "$SANDBOX/a.txt"); check "not enough room is 413" "$(code "$r")" 413
echo "$r" | grep -q 'enough room' && ok "the message is in plain language" || bad "space message: $r"
curl -s -b "$JAR" -H 'X-Requested-With: x' "$H/cgi-bin/files_put.cgi?check=1&p=$(enc "$U")" | grep -q '"free":10}' && ok "free space query reports the small disk" || bad "free query on small disk"
rm -f "$SANDBOX/df-small"
[ ! -e "$U/full.txt" ] && ok "no file left after the refusal" || bad "file left after refusal"

echo "== multi-terabyte disks (32-bit shell arithmetic)"
: > "$SANDBOX/df-huge"
r=$(put "$U" "huge-disk.txt" "$SANDBOX/a.txt"); check "upload works when the disk has 3.9 TB free" "$(code "$r")" 200
curl -s -b "$JAR" -H 'X-Requested-With: x' "$H/cgi-bin/files_put.cgi?check=1&p=$(enc "$U")" | grep -q '"free":2000000000}' && ok "reported free space is capped, never negative" || bad "free space cap"
out=$(cd "$SANDBOX/www/cgi-bin" && PATH="$SANDBOX/stubs:$SANDBOX/bin:/usr/bin:/bin" "$SANDBOX/bin/sh" -c '. ./common.sh; storage_info; echo "$ST_USED_H|$ST_TOTAL_H|$ST_PCT|$ST_MAXPCT"')
check "storage totals for two 3.9 TB disks" "$out" "281.8 MB|7.3 TB|0|1"
rm -f "$SANDBOX/df-huge"

echo "== big, binary and interrupted"
dd if=/dev/urandom of="$SANDBOX/big.bin" bs=1M count=200 2>/dev/null
printf '\r\n--abc\r\n\000\377\r\n' >> "$SANDBOX/big.bin"
r=$(put "$U" "big.bin" "$SANDBOX/big.bin"); check "200 MB binary upload" "$(code "$r")" 200
cmp -s "$SANDBOX/big.bin" "$U/big.bin" && ok "200 MB arrives byte for byte" || bad "big file differs"
python3 - "$H" "$SANDBOX" "$(enc "$U")" <<'PY'
import socket, sys, re
host = sys.argv[1].split("//")[1].split(":"); port = int(host[1]); sbx = sys.argv[2]; d = sys.argv[3]
jar = [l.split("\t") for l in open(sbx + "/jar") if "ALTSID" in l][0]
tok = jar[-1].strip()
s = socket.create_connection(("127.0.0.1", port))
s.sendall((f"POST /cgi-bin/files_put.cgi?p={d}&n=cut.bin HTTP/1.0\r\nHost: 127.0.0.1:{port}\r\nOrigin: http://127.0.0.1:{port}\r\n"
           f"Cookie: ALTSID={tok}\r\nX-Requested-With: x\r\nContent-Length: 5000000\r\n\r\n").encode() + b"x" * 100000)
s.close()
PY
sleep 1
[ ! -e "$U/cut.bin" ] && ok "an interrupted upload leaves no file" || bad "partial file left"
check "no temporary files are left" "$(find "$M" -name '.upload-*' | wc -l | tr -d ' ')" 0

echo "== form upload (no JavaScript)"
printf 'form file\r\n--x--\r\nend' > "$SANDBOX/form file.bin"
h=$(curl -s -D - -o /dev/null -b "$JAR" -H "Origin: $H" -F "file=@$SANDBOX/form file.bin" "$H/cgi-bin/files_put.cgi?form=1&p=$(enc "$U")" | tr -d '\r')
echo "$h" | grep -q '^Location: /cgi-bin/files.cgi?nojs=1&p=.*&up=ok$' && ok "form upload redirects back with success" || bad "form redirect: $h"
cmp -s "$SANDBOX/form file.bin" "$U/form file.bin" && ok "multipart body arrives byte for byte" || { bad "multipart bytes differ"; ls -l "$U/form file.bin"; }
: > "$SANDBOX/empty.bin"; curl -s -o /dev/null -b "$JAR" -H "Origin: $H" -F "file=@$SANDBOX/empty.bin" "$H/cgi-bin/files_put.cgi?form=1&p=$(enc "$U")"
[ -f "$U/empty.bin" ] && [ ! -s "$U/empty.bin" ] && ok "an empty file uploads as an empty file" || bad "empty file"
h=$(curl -s -D - -o /dev/null -b "$JAR" -H "Origin: $H" -F "file=@$SANDBOX/a.txt;filename=../../evil.txt" "$H/cgi-bin/files_put.cgi?form=1&p=$(enc "$U")" | tr -d '\r')
[ -f "$U/evil.txt" ] && [ ! -e "$M/evil.txt" ] && ok "a path in the file name is cut down to the name" || bad "form path handling"
h=$(curl -s -D - -o /dev/null -b "$JAR" -H "Origin: $H" -F "file=@$SANDBOX/a.txt" "$H/cgi-bin/files_put.cgi?form=1&p=$(enc "$M")" | tr -d '\r')
echo "$h" | grep -q 'up=root' && ok "form upload to the all-disks root is refused" || bad "form root: $h"
curl -s -b "$JAR" "$H/cgi-bin/files.cgi?nojs=1&p=$(enc "$U")&up=ok" | grep -q 'Upload a file here' && ok "the simple page has the upload form" || bad "no form on the simple page"
curl -s -b "$JAR" "$H/cgi-bin/files.cgi?nojs=1&p=$(enc "$M")" | grep -q 'Upload a file here' && bad "form shown at the root" || ok "no upload form at the all-disks root"

echo "== listing sees the new files"
curl -s -b "$JAR" "$H/cgi-bin/files_list.cgi?p=$(enc "$U")" | python3 -c '
import json,sys
d=json.load(sys.stdin); n={e["n"] for e in d["entries"]}
assert "café ☕.txt" in n and "Trip" in n and "big.bin" in n and ".hidden" not in n, n' && ok "uploads show up in the browser, dot files stay hidden" || bad "listing after upload"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
