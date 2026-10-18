#!/bin/sh
# Path-traversal, filename and download tests for the file browser, run against the
# local BusyBox httpd harness (see harness.sh).
#
#   BB=/path/to/busybox sh board/dns32x/webui-tests/test-files.sh
#
# Needs curl and python3 on the PC (python is only used to check the JSON).

HERE=$(cd "$(dirname "$0")" && pwd)
export SANDBOX=${SANDBOX:-/tmp/altf-webui-test}
export PORT=${PORT:-18082}
H=http://127.0.0.1:$PORT
PASS=0; FAIL=0

sh "$HERE/harness.sh" stop >/dev/null 2>&1
sh "$HERE/harness.sh" start >/dev/null || exit 1
trap 'sh "$HERE/harness.sh" stop' EXIT

M=$SANDBOX/mnt
echo -n secretpw > "$SANDBOX/etc/web-secret"

ok()   { PASS=$((PASS + 1)); echo "ok   $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }

# ---- sample tree ----
mkdir -p "$M/Disk1/Photos" "$M/Disk1/My Docs" "$M/Disk1/empty" "$M/Disk1/big"
echo "holiday" > "$M/Disk1/Photos/beach.jpg"
echo "pdfdata" > "$M/Disk1/My Docs/report final.pdf"
echo "q" > "$M/Disk1/it's \"quoted\" & more.txt"
echo "u" > "$M/Disk1/café ☕.txt"
echo "t" > "$M/Disk1/a<b>&amp;.txt"
echo "<script>alert(1)</script>" > "$M/Disk1/page.html"
echo "semi;colon" > "$M/Disk1/semi;colon,comma.txt"
echo "secret" > "$SANDBOX/outside.txt"
ln -sfn /etc "$M/Disk1/escape"
ln -sfn /etc/passwd "$M/Disk1/passwd-link"
ln -sfn "$SANDBOX/outside.txt" "$M/Disk1/outside-link"
ln -sfn "$M/Disk1/Photos" "$M/Disk1/inside-link"
mkdir -p "$M/../mnt-evil" && echo evil > "$M/../mnt-evil/x.txt"
i=0; while [ $i -lt 2100 ]; do : > "$M/Disk1/big/f$i"; i=$((i + 1)); done

# ---- sign in ----
salt=$(curl -s "$H/cgi-bin/login.cgi" | grep -o '[0-9a-f]\{32\}' | head -1)
hash=$(printf 'secretpw%s' "$salt" | md5sum | cut -d' ' -f1)
JAR=$SANDBOX/jar
curl -s -c "$JAR" -o /dev/null -d "salt=$salt&pwhash=$hash" "$H/cgi-bin/login_proc.cgi"

enc() { python3 -c 'import sys,urllib.parse as u; print(u.quote(sys.argv[1], safe=""))' "$1"; }
# prints the status code, or NOCGI when the answer did not come from our script
# (a 404 from httpd itself must never count as "refused")
code() {
	_c=$(curl -s -o /dev/null -D "$SANDBOX/hh" -w '%{http_code}' -b "$JAR" "$@")
	if grep -qi '^Cache-Control: .*no-store' "$SANDBOX/hh"; then echo "$_c"; else echo "NOCGI$_c"; fi
}
list() { curl -s -b "$JAR" "$H/cgi-bin/files_list.cgi?p=$1"; }
lcode() { code "$H/cgi-bin/files_list.cgi?p=$1"; }
gcode() { code "$H/cgi-bin/files_get.cgi?p=$1"; }

echo "== authentication"
check "list without session is 401" "$(curl -s -o /dev/null -w '%{http_code}' "$H/cgi-bin/files_list.cgi?p=$(enc "$M")")" 401
check "download without session is 401" "$(curl -s -o /dev/null -w '%{http_code}' "$H/cgi-bin/files_get.cgi?p=$(enc "$M/Disk1/page.html")")" 401
check "list with a forged cookie is 401" "$(curl -s -o /dev/null -w '%{http_code}' -b "ALTSID=$(printf '%064d' 7)" "$H/cgi-bin/files_list.cgi?p=$(enc "$M")")" 401

echo "== listing"
check "root list is 200" "$(lcode "$(enc "$M")")" 200
list "$(enc "$M")" | grep -q '"n":"Disk1"' && ok "root shows Disk1" || bad "root shows Disk1"
list "$(enc "$M/Disk1")" > "$SANDBOX/l.json"
python3 - "$SANDBOX/l.json" <<'PY' && ok "Disk1 JSON is valid and names are exact" || bad "Disk1 JSON names"
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
names = {e["n"] for e in d["entries"]}
want = {"it's \"quoted\" & more.txt", "café ☕.txt", "a<b>&amp;.txt", "semi;colon,comma.txt", "My Docs", "Photos", "page.html"}
missing = want - names
assert not missing, missing
assert all(set(e) == {"n", "t", "s", "m"} for e in d["entries"])
PY
check "folders are typed d" "$(python3 -c "import json;d=json.load(open('$SANDBOX/l.json'));print([e['t'] for e in d['entries'] if e['n']=='Photos'][0])")" d
list "$(enc "$M/Disk1/empty")" | grep -q '"entries":\[\]' && ok "empty folder lists no entries" || bad "empty folder"
list "$(enc "$M/Disk1/big")" > "$SANDBOX/big.json"
check "big folder is cut at 1000" "$(python3 -c "import json;d=json.load(open('$SANDBOX/big.json'));print(len(d['entries']),d['truncated'])")" "1000 True"
check "a folder that does not exist is 404, not 400" "$(lcode "$(enc "$M/Disk1/no-such-folder")")" 404
check "symlink inside /mnt is followed" "$(lcode "$(enc "$M/Disk1/inside-link")")" 200
python3 - "$SANDBOX/l.json" <<'PY' && ok "links that leave /mnt are not listed, links inside are" || bad "symlink listing"
import json, sys
names = {e["n"] for e in json.load(open(sys.argv[1], encoding="utf-8"))["entries"]}
assert "inside-link" in names, names
assert not names & {"escape", "passwd-link", "outside-link"}, names
PY

echo "== traversal and escapes are refused"
for p in \
	"$M/../" "$M/../etc" "$M/Disk1/../../etc" "/etc" "/etc/passwd" "/" "$M-evil" "${M}x" "${M}/../mnt-evil" \
	"$M/Disk1/escape" "$M/Disk1/escape/passwd" "$M/Disk1/passwd-link" "$M/Disk1/outside-link" \
	"relative/path" "mnt" "$M//../etc" ; do
	c=$(lcode "$(enc "$p")")
	case "$c" in 403|404) ok "list '$p' -> $c" ;; *) bad "list '$p' -> $c" ;; esac
	c=$(gcode "$(enc "$p")")
	case "$c" in 400|403|404) ok "get  '$p' -> $c" ;; *) bad "get  '$p' -> $c" ;; esac
done
# raw (not pre-encoded) tricks sent straight on the wire
for raw in \
	"$(enc "$M")/%2e%2e/%2e%2e/etc" "$(enc "$M")%2f%2e%2e%2f%2e%2e%2fetc" "$(enc "$M")%252f..%252f..%252fetc" \
	"%2e%2e%2f%2e%2e%2fetc%2fpasswd" "$(enc "$M")%00" "$(enc "$M")%00/../../etc" "$(enc "$M/Disk1")%0a" \
	"$(enc "$M/Disk1")%0d%0aX-Evil:1" "$(enc "$M/Disk1")%01" ; do
	c=$(lcode "$raw"); case "$c" in 400|403|404) ok "list raw '$raw' -> $c" ;; *) bad "list raw '$raw' -> $c" ;; esac
	c=$(gcode "$raw"); case "$c" in 400|403|404) ok "get  raw '$raw' -> $c" ;; *) bad "get  raw '$raw' -> $c" ;; esac
done
curl -s -b "$JAR" "$H/cgi-bin/files_get.cgi?p=$(enc "$M/Disk1/escape/passwd")" | grep -q root && bad "escape/passwd leaked file content" || ok "no /etc/passwd content leaked"
curl -s -b "$JAR" "$H/cgi-bin/files_get.cgi?p=$(enc "$M/Disk1/outside-link")" | grep -q secret && bad "outside-link leaked content" || ok "no outside file content leaked"

echo "== downloads"
check "folder is not a file" "$(gcode "$(enc "$M/Disk1/Photos")")" 400
check "missing file is 404" "$(gcode "$(enc "$M/Disk1/nope.txt")")" 404
for f in "My Docs/report final.pdf" "it's \"quoted\" & more.txt" "café ☕.txt" "a<b>&amp;.txt" "semi;colon,comma.txt" "Photos/beach.jpg"; do
	url="$H/cgi-bin/files_get.cgi?p=$(enc "$M/Disk1/$f")"
	curl -s -b "$JAR" -D "$SANDBOX/h" -o "$SANDBOX/body" "$url"
	cmp -s "$SANDBOX/body" "$M/Disk1/$f" && ok "bytes match: $f" || bad "bytes differ: $f"
	want=$(wc -c < "$M/Disk1/$f" | tr -d ' ')
	got=$(tr -d '\r' < "$SANDBOX/h" | sed -n 's/^[Cc]ontent-[Ll]ength: //p')
	check "Content-Length: $f" "$got" "$want"
	grep -qi '^Content-Disposition: attachment; filename="[^"]*"; filename\*=UTF-8' "$SANDBOX/h" && ok "attachment header: $f" || bad "attachment header: $f"
done
curl -s -b "$JAR" -D "$SANDBOX/h" -o /dev/null "$H/cgi-bin/files_get.cgi?p=$(enc "$M/Disk1/café ☕.txt")"
star=$(tr -d '\r' < "$SANDBOX/h" | sed -n "s/^Content-Disposition:.*filename\*=UTF-8''//p")
check "unicode name round-trips through filename*" "$(python3 -c 'import sys,urllib.parse as u; print(u.unquote(sys.argv[1]))' "$star")" "café ☕.txt"
curl -s -b "$JAR" -D "$SANDBOX/h" -o /dev/null "$H/cgi-bin/files_get.cgi?p=$(enc "$M/Disk1/it's \"quoted\" & more.txt")"
grep -i '^Content-Disposition' "$SANDBOX/h" | tr -d '\r' | grep -q 'filename="it_s _quoted_ _ more.txt"' && ok "quotes and & cleaned in ascii filename" || { bad "ascii filename"; grep -i Content-Disp "$SANDBOX/h"; }
curl -s -b "$JAR" -D "$SANDBOX/h" -o /dev/null "$H/cgi-bin/files_get.cgi?p=$(enc "$M/Disk1/page.html")&inline=1"
grep -qi '^Content-Disposition: attachment' "$SANDBOX/h" && ok "html is never shown inline" || bad "html shown inline"
grep -qi '^Content-Type: application/octet-stream' "$SANDBOX/h" && ok "html is served as a binary download" || bad "html content-type"
curl -s -b "$JAR" -D "$SANDBOX/h" -o /dev/null "$H/cgi-bin/files_get.cgi?p=$(enc "$M/Disk1/Photos/beach.jpg")&inline=1"
grep -qi '^Content-Disposition: inline' "$SANDBOX/h" && grep -qi '^Content-Type: image/jpeg' "$SANDBOX/h" && ok "jpeg can open inline" || bad "jpeg inline"

echo "== simple (no JavaScript) page"
page=$(curl -s -b "$JAR" "$H/cgi-bin/files.cgi?nojs=1&p=$(enc "$M/Disk1")")
echo "$page" | grep -q 'it&#39;s\|it&apos;s\|it.s &quot;quoted&quot; &amp; more.txt' && ok "html page escapes quotes and ampersand" || bad "html escaping"
echo "$page" | grep -q '<script>alert' && bad "unescaped script in listing" || ok "no raw script tag in listing"
echo "$page" | grep -q 'a&lt;b&gt;&amp;amp;.txt' && ok "angle brackets escaped" || bad "angle bracket escaping"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
