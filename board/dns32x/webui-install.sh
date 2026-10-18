#!/bin/sh
# Copy the web interface onto a running Alt-F box over SSH, or take it off again.
#
#   sh webui-install.sh [options] [user@]host           install (or update)
#   sh webui-install.sh --remove [options] [user@]host  put the original files back
#   sh webui-install.sh --status [user@]host            show what is installed
#
#   --yes   do not ask before changing the box
#
# Run it on your PC. It needs ssh and tar, and the files listed in webui-files.txt
# next to this script. The user defaults to root.
#
# Where the files end up depends on the box. Alt-F keeps its root in RAM on top of a
# read-only image, so a copy is gone after a reboot. If the box has an Alt-F folder on
# a disk that is in use, that folder is part of the root and the copy stays. The script
# tells you which case it is before it changes anything. Before the first install it
# saves the files it is about to replace in /usr/share/webui-backup on the box, and
# --remove puts them back.

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
LIST=$HERE/webui-files.txt
ROOT=$HERE/customroot

die() { echo "webui-install: $*" >&2; exit 1; }

mode=install; yes=""; host=""
for a in "$@"; do
	case "$a" in
		--remove) mode=remove ;;
		--status) mode=status ;;
		--yes) yes=1 ;;
		-h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		-*) die "unknown option $a" ;;
		*) test -z "$host" || die "only one host please"; host=$a ;;
	esac
done
test -n "$host" || die "usage: sh webui-install.sh [--remove|--status] [--yes] [user@]host"
case "$host" in
	*[!A-Za-z0-9@._:-]*) die "that host name has characters I don't accept" ;;
esac
case "$host" in *@*) ;; *) host=root@$host ;; esac

CTL=$(mktemp -d) || die "no temporary folder"
trap 'ssh -o ControlPath="$CTL/c" -O exit "$host" >/dev/null 2>&1; rm -rf "$CTL"' EXIT INT TERM
nas() { ssh -o ControlMaster=auto -o ControlPath="$CTL/c" -o ControlPersist=120 "$host" "$@"; }

# What the box looks like now. Runs on the box, changes nothing.
STATUS='
if test -f /usr/share/webui-backup/list.all; then echo "installed: yes"; else echo "installed: no"; fi
if test -h /Alt-F && grep -q "$(readlink -f /Alt-F)" /sys/fs/aufs/*/br* 2>/dev/null; then
	echo "persistent: yes ($(readlink -f /Alt-F) is part of the root, so changes stay after a reboot)"
else
	echo "persistent: no (changes are in RAM and disappear on reboot)"
fi
cat /etc/Alt-F 2>/dev/null | sed "s/^/Alt-F: /"
'

# Runs on the box. The tar of new files arrives on its input.
INSTALL='
set -e
B=/usr/share/webui-backup
T=/tmp/webui-payload.tar
cat > $T
if ! test -f $B/list.all; then
	mkdir -p $B
	tar tf $T | grep -v "/$" > $B/list.all
	echo etc/settings >> $B/list.all
	: > $B/existing; : > $B/new
	while read -r f; do
		if test -e "/$f"; then echo "$f" >> $B/existing; else echo "$f" >> $B/new; fi
	done < $B/list.all
	tar cf $B/orig.tar -C / $(cat $B/existing)
fi
# keep settings the owner already changed
if test -f /etc/web-session.conf; then cp -p /etc/web-session.conf /tmp/web-session.keep; fi
tar xf $T -C /
if test -f /tmp/web-session.keep; then cp -p /tmp/web-session.keep /etc/web-session.conf; rm -f /tmp/web-session.keep; fi
grep -q web-session /etc/settings || echo /etc/web-session.conf >> /etc/settings
rm -f $T
echo "done"
'

REMOVE='
set -e
B=/usr/share/webui-backup
test -f $B/list.all || { echo "nothing to remove: no backup found"; exit 1; }
tar xf $B/orig.tar -C /
for f in $(cat $B/new); do rm -f "/$f"; done
rm -rf $B
echo "done"
'

echo "Connecting to $host ..."
out=$(nas "sh -c '$STATUS'") || die "could not reach the box over ssh"
echo "$out"

case "$mode" in
status) exit 0 ;;
remove)
	case "$out" in *"installed: yes"*) ;; *) die "the web interface was not installed with this script" ;; esac
	if test -z "$yes"; then
		printf 'Put the original files back? [y/N] '; read -r ans
		case "$ans" in y|Y|yes) ;; *) echo "Nothing changed."; exit 0 ;; esac
	fi
	nas "sh -c '$REMOVE'" || die "remove failed"
	echo "Original files restored. If you saved settings while it was installed, run Advanced > Settings > Save again."
	;;
install)
	test -f "$LIST" || die "$LIST is missing"
	while read -r f; do test -f "$ROOT/$f" || die "missing file: $f"; done < "$LIST"
	if test -z "$yes"; then
		printf 'Copy the web interface to the box? [y/N] '; read -r ans
		case "$ans" in y|Y|yes) ;; *) echo "Nothing changed."; exit 0 ;; esac
	fi
	# files must belong to root on the box whatever user owns them here
	if tar --version 2>/dev/null | grep -q GNU; then
		own="--owner=0 --group=0 --numeric-owner"
	else
		own="--uid 0 --gid 0"
	fi
	# shellcheck disable=SC2086
	COPYFILE_DISABLE=1 tar cf - $own -C "$ROOT" -T "$LIST" | nas "sh -c '$INSTALL'" || die "install failed"
	echo "Open http://${host#*@}/ in a browser. Your existing password still works."
	case "$out" in *"persistent: yes"*) echo "Run with --remove to go back." ;; *) echo "Reboot the box to go back, or run with --remove." ;; esac
	;;
esac
