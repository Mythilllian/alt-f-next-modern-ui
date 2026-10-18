#!/bin/sh
# Login, session and CSRF tests, run against the local BusyBox httpd harness.
#
#   BB=/path/to/busybox sh board/dns32x/webui-tests/test-auth.sh
#
# Takes about 20 seconds (it waits for short test timeouts to run out).

HERE=$(cd "$(dirname "$0")" && pwd)
export SANDBOX=${SANDBOX:-/tmp/altf-webui-test}
export PORT=${PORT:-18083}
H=http://127.0.0.1:$PORT
PASS=0; FAIL=0

sh "$HERE/harness.sh" stop >/dev/null 2>&1
sh "$HERE/harness.sh" start >/dev/null || exit 1
trap 'sh "$HERE/harness.sh" stop' EXIT

ok()   { PASS=$((PASS + 1)); echo "ok   $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }
status() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
hdr() { curl -s -D - -o /dev/null "$@" | tr -d '\r'; }
newsalt() { curl -s "$H/cgi-bin/login.cgi" | grep -o 'name="salt" value="[0-9a-f]*"' | grep -o '[0-9a-f]\{32\}'; }
md5() { printf '%s' "$1" | md5sum | cut -d' ' -f1; }
login() { # login <jar> <password> [extra form fields]
	_s=$(newsalt)
	curl -s -c "$1" -o /dev/null -d "salt=$_s&pwhash=$(md5 "$2$_s")&$3" "$H/cgi-bin/login_proc.cgi"
}

echo "== first login (no password yet)"
curl -s "$H/cgi-bin/login.cgi" | grep -q '<h1>Welcome</h1>' && ok "first visit asks to choose a password" || bad "first-time page"
h=$(hdr -d "passwd=secretpw&passwd_again=different&from_url=" "$H/cgi-bin/login_proc.cgi")
echo "$h" | grep -q 'Set-Cookie' && bad "mismatched passwords must not sign in" || ok "mismatched passwords do not sign in"
h=$(hdr -c "$SANDBOX/j0" -d "passwd=secretpw&passwd_again=secretpw&from_url=" "$H/cgi-bin/login_proc.cgi")
echo "$h" | grep -q '^Set-Cookie: ALTSID=[0-9a-f]\{64\};' && ok "choosing a password signs you in" || bad "first-time sign in: $h"
check "password file written" "$(cat "$SANDBOX/etc/web-secret" 2>/dev/null)" secretpw
check "first sign in starts the setup wizard" "$(cat "$SANDBOX/tmp/firstboot" 2>/dev/null)" host
rm -f "$SANDBOX/tmp/firstboot"   # the rest of the tests are about normal use

echo "== sign in"
check "protected page without a cookie redirects" "$(status "$H/cgi-bin/home.cgi")" 303
hdr "$H/cgi-bin/home.cgi" | grep -q '^Location: /cgi-bin/login.cgi' && ok "redirect goes to the login page" || bad "redirect target"
s=$(newsalt)
h=$(hdr -d "salt=$s&pwhash=$(md5 "wrong$s")&from_url=" "$H/cgi-bin/login_proc.cgi")
echo "$h" | grep -q 'Set-Cookie' && bad "wrong password signed in" || ok "wrong password is refused"
echo "$h" | grep -q 'Location: /cgi-bin/login.cgi?e=1' && ok "wrong password goes back to the form" || bad "wrong password redirect"
curl -s "$H/cgi-bin/login.cgi?e=1" | grep -q 'did not work' && ok "login page explains the failure" || bad "error message"

s=$(newsalt); hh=$(md5 "secretpw$s")
h=$(hdr -d "salt=$s&pwhash=$hh&from_url=" "$H/cgi-bin/login_proc.cgi")
echo "$h" | grep -q '^Set-Cookie: ALTSID=[0-9a-f]\{64\}; Path=/; HttpOnly; SameSite=Strict$' && ok "session cookie is HttpOnly, SameSite=Strict, Path=/ and has no expiry" || bad "cookie flags: $h"
h=$(hdr -d "salt=$s&pwhash=$hh&from_url=" "$H/cgi-bin/login_proc.cgi")
echo "$h" | grep -q 'Set-Cookie' && bad "the same challenge worked twice" || ok "a login challenge works only once"

s=$(newsalt)
h=$(hdr -d "salt=$s&passwd=secretpw&keep=yes" "$H/cgi-bin/login_proc.cgi")
echo "$h" | grep -q 'Max-Age=604800' && ok "no-JavaScript sign in works, keep-me-signed-in sets Max-Age" || bad "plain form login: $h"
s=$(newsalt)
h=$(hdr -H 'Origin: https://nas.local' -d "salt=$s&pwhash=$(md5 "secretpw$s")" "$H/cgi-bin/login_proc.cgi")
echo "$h" | grep -q '; Secure' && ok "cookie is Secure when signed in over https" || bad "secure flag"

echo "== safe redirects after sign in"
for target in 'http%3A%2F%2Fevil.com' '%2F%2Fevil.com' '%2Fcgi-bin%2Fx%0d%0aSet-Cookie:%20e=1' 'javascript:alert(1)' '%2Fcgi-bin%2F..%2F..%2Fetc'; do
	s=$(newsalt)
	l=$(hdr -d "salt=$s&pwhash=$(md5 "secretpw$s")&from_url=$target" "$H/cgi-bin/login_proc.cgi")
	echo "$l" | grep -q '^Location: /cgi-bin/home.cgi$' && ok "unsafe from_url '$target' ignored" || bad "from_url '$target' -> $(echo "$l" | grep Location)"
	echo "$l" | grep -qi '^Set-Cookie: e=1' && bad "header injection worked"
done
s=$(newsalt)
l=$(hdr -d "salt=$s&pwhash=$(md5 "secretpw$s")&from_url=%2Fcgi-bin%2Ffiles.cgi%3Fnojs%3D1" "$H/cgi-bin/login_proc.cgi")
echo "$l" | grep -q '^Location: /cgi-bin/files.cgi?nojs=1$' && ok "returns to the page you asked for" || bad "return page: $l"

echo "== using a session"
login "$SANDBOX/j1" secretpw
check "home page with a session" "$(status -b "$SANDBOX/j1" "$H/cgi-bin/home.cgi")" 200
for p in status shares advanced files; do check "$p.cgi with a session" "$(status -b "$SANDBOX/j1" "$H/cgi-bin/$p.cgi")" 200; done
check "forged cookie is refused" "$(status -b "ALTSID=$(printf '%064d' 1)" "$H/cgi-bin/home.cgi")" 303
check "path-like cookie is refused" "$(status -b 'ALTSID=../../etc/passwd' "$H/cgi-bin/home.cgi")" 303
check "short cookie is refused" "$(status -b 'ALTSID=abc' "$H/cgi-bin/home.cgi")" 303
check "background request without a session gets 401" "$(status -H 'X-Requested-With: XMLHttpRequest' "$H/cgi-bin/status.cgi?refresh=systems_st")" 401
check "old frame page without a session redirects" "$(status "$H/cgi-bin/sys_utils.cgi")" 303
check "two devices can be signed in at once" "$(login "$SANDBOX/j2" secretpw; status -b "$SANDBOX/j1" "$H/cgi-bin/home.cgi")$(status -b "$SANDBOX/j2" "$H/cgi-bin/home.cgi")" 200200
check "session directory is private" "$(ls -ld "$SANDBOX/tmp/sessions" | cut -c1-10)" drwx------
check "session files are private" "$(ls -l "$SANDBOX/tmp/sessions" | grep -v salt | grep -v '^total' | cut -c1-10 | sort -u)" -rw-------

echo "== cross-site posts"
check "POST with no Origin or Referer" "$(status -b "$SANDBOX/j1" -d x=1 "$H/cgi-bin/sys_utils_proc.cgi")" 403
check "POST from another site" "$(status -b "$SANDBOX/j1" -H 'Origin: http://evil.example' -d x=1 "$H/cgi-bin/sys_utils_proc.cgi")" 403
check "POST with a spoofed Referer host" "$(status -b "$SANDBOX/j1" -H 'Referer: http://evil.example/127.0.0.1:'$PORT -d x=1 "$H/cgi-bin/sys_utils_proc.cgi")" 403
check "POST with Origin null" "$(status -b "$SANDBOX/j1" -H 'Origin: null' -d x=1 "$H/cgi-bin/sys_utils_proc.cgi")" 403
c=$(hdr -b "$SANDBOX/j1" -H "Origin: $H" -d x=1 "$H/cgi-bin/sys_utils_proc.cgi")
if echo "$c" | grep -q '^HTTP/1.[01] 403' || echo "$c" | grep -q '^Location: /cgi-bin/login'; then bad "same-site POST was blocked"; else ok "POST from the same site is let through"; fi

echo "== timeouts"
echo "# test" > "$SANDBOX/etc/web-session.conf"; printf 'SESSION_IDLE=4\nSESSION_ABS=9\n' >> "$SANDBOX/etc/web-session.conf"
login "$SANDBOX/j3" secretpw
check "fresh session works" "$(status -b "$SANDBOX/j3" "$H/cgi-bin/home.cgi")" 200
sleep 3; check "activity slides the idle timeout (3s)" "$(status -b "$SANDBOX/j3" "$H/cgi-bin/home.cgi")" 200
sleep 3; check "still alive after 6s of total age" "$(status -b "$SANDBOX/j3" "$H/cgi-bin/home.cgi")" 200
sleep 4; check "absolute cap ends it even though it was active" "$(status -b "$SANDBOX/j3" "$H/cgi-bin/home.cgi")" 303
login "$SANDBOX/j4" secretpw
sleep 5; check "idle timeout ends an unused session" "$(status -b "$SANDBOX/j4" "$H/cgi-bin/home.cgi")" 303
ls "$SANDBOX/tmp/sessions" | grep -v salt > /dev/null && ok "expired files exist until the next login" || ok "expired files already gone"
login "$SANDBOX/j5" secretpw
n=$(ls "$SANDBOX/tmp/sessions" | grep -vc salt)
check "next login cleans up expired sessions" "$n" 1
cp "$HERE/../customroot/etc/web-session.conf" "$SANDBOX/etc/web-session.conf"

echo "== address binding"
login "$SANDBOX/j6" secretpw
f=$(ls "$SANDBOX/tmp/sessions" | grep -v salt | while read -r t; do grep -q yes "$SANDBOX/tmp/sessions/$t" || echo "$t"; done | head -1)
[ -n "$f" ] || f=$(ls -t "$SANDBOX/tmp/sessions" | grep -v salt | head -1)
for t in $(ls "$SANDBOX/tmp/sessions" | grep -v salt); do
	read -r a b c d < "$SANDBOX/tmp/sessions/$t"; echo "$a $b 10.9.9.9 $d" > "$SANDBOX/tmp/sessions/$t"
done
check "session from another address is refused" "$(status -b "$SANDBOX/j6" "$H/cgi-bin/home.cgi")" 303
login "$SANDBOX/j7" secretpw

echo "== sign out"
check "signed in before sign out" "$(status -b "$SANDBOX/j7" "$H/cgi-bin/home.cgi")" 200
hdr -b "$SANDBOX/j7" -H "Origin: $H" -X POST "$H/cgi-bin/logout.cgi" | grep -q 'Set-Cookie: ALTSID=;.*Max-Age=0' && ok "sign out expires the cookie" || bad "logout cookie"
check "session no longer works" "$(status -b "$SANDBOX/j7" "$H/cgi-bin/home.cgi")" 303

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
