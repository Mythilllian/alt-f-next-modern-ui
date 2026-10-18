#!/bin/sh
# Run webui-install.sh against a fake box: a folder used as the root of a chroot inside a
# user namespace, reached through a stand-in for ssh. Needs BB (a BusyBox) and unshare.
#   BB=/path/to/busybox sh board/dns32x/webui-tests/test-install.sh
HERE=$(cd "$(dirname "$0")" && pwd)
I=$HERE/../webui-install.sh
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ok() { echo "ok   $1"; pass=$((pass+1)); }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
if [ -z "$BB" ] || ! unshare -Ur true 2>/dev/null; then echo "skipped: needs BB and unprivileged user namespaces"; exit 0; fi

mkdir -p "$W/nas/bin" "$W/nas/etc" "$W/nas/tmp" "$W/nas/usr/www/cgi-bin" "$W/fake"
cp "$BB" "$W/nas/bin/busybox"
for a in sh tar cat grep mkdir mv cp rm readlink sed; do ln -s busybox "$W/nas/bin/$a"; done
echo FOO=1 > "$W/nas/etc/settings"; echo ORIGINAL > "$W/nas/usr/www/cgi-bin/common.sh"
cat > "$W/fake/ssh" <<'SSH'
#!/bin/sh
for a in "$@"; do [ "$a" = -O ] && exit 0; done
while [ "$1" = -o ]; do shift 2; done
shift
exec unshare -Ur chroot "$NAS" /bin/sh -c "$*"
SSH
chmod +x "$W/fake/ssh"
export NAS=$W/nas PATH=$W/fake:$PATH

sh "$I" --yes box >/dev/null 2>&1 && ok "install runs" || bad "install runs"
n=$(wc -l < "$HERE/../webui-files.txt")
c=0; while read -r f; do [ -f "$NAS/$f" ] && c=$((c+1)); done < "$HERE/../webui-files.txt"
[ "$c" -eq "$n" ] && ok "all $n files copied" || bad "copied $c of $n files"
[ -x "$NAS/usr/www/cgi-bin/home.cgi" ] && ok "scripts stay executable" || bad "home.cgi not executable"
grep -q web-session "$NAS/etc/settings" && ok "settings list updated" || bad "settings list not updated"
echo SESSION_IDLE=1 > "$NAS/etc/web-session.conf"
sh "$I" --yes box >/dev/null 2>&1
[ "$(cat "$NAS/etc/web-session.conf")" = SESSION_IDLE=1 ] && ok "a second install keeps edited settings" || bad "settings overwritten"
[ "$(grep -c web-session "$NAS/etc/settings")" = 1 ] && ok "settings line added once" || bad "settings line duplicated"
sh "$I" --remove --yes box >/dev/null 2>&1 && ok "remove runs" || bad "remove runs"
[ "$(cat "$NAS/usr/www/cgi-bin/common.sh")" = ORIGINAL ] && ok "original file restored" || bad "original not restored"
[ "$(cat "$NAS/etc/settings")" = FOO=1 ] && ok "settings restored" || bad "settings not restored"
[ ! -e "$NAS/usr/www/cgi-bin/home.cgi" ] && [ ! -e "$NAS/usr/share/webui-backup" ] && ok "new files and backup gone" || bad "leftovers after remove"
sh "$I" --remove --yes box >/dev/null 2>&1 && bad "second remove should fail" || ok "second remove is refused"
sh "$I" --yes 'x;id' >/dev/null 2>&1 && bad "odd host accepted" || ok "odd host refused"
echo; echo "passed: $pass  failed: $fail"; [ "$fail" -eq 0 ]
