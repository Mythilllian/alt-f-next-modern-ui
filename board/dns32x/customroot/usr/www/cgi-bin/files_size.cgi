#!/bin/sh
# How much disk space a folder uses: {"bytes":N}. p=<path of a folder>.
# Counting walks every file, which is slow on a big folder and keeps the disk busy, so it
# only runs when someone asks for one folder, one at a time, and stops after FS_SIZE_LIMIT
# seconds. Items that the browser hides at the top of a disk are not counted. Other disks
# or drives mounted inside the folder are not counted either.

source ./common.sh
source ./fs_common.sh
check_cookie api

FS_SIZE_LIMIT=60
LOCK=/tmp/fs-size.lock

json_error() {
	printf 'Status: %s\r\nContent-Type: application/json; charset=UTF-8\r\nCache-Control: no-store\r\n\r\n' "$1"
	printf '{"error":"%s","code":"%s"}\n' "$3" "$2"
	exit 0
}

p=$(fs_param p)
if ! fs_resolve "$p"; then
	case "$FS_ERR" in
		missing) json_error "404 Not Found" missing "$(fs_message missing)" ;;
		*) json_error "403 Forbidden" outside "$(fs_message outside)" ;;
	esac
fi
if ! test -d "$FS_REAL" || test "$FS_REAL" = "$FS_ROOT"; then json_error "400 Bad Request" notdir "$(fs_message notdir)"; fi

# one count at a time; a lock left behind by a count that died is cleaned up
if ! mkdir "$LOCK" 2>/dev/null; then
	read -r _opid < "$LOCK/pid" 2>/dev/null
	if test -n "$_opid" && kill -0 "$_opid" 2>/dev/null; then
		json_error "503 Service Unavailable" busy "Another folder is being measured. Try again in a moment."
	fi
	rm -rf "$LOCK"
	mkdir "$LOCK" 2>/dev/null || json_error "503 Service Unavailable" busy "Another folder is being measured. Try again in a moment."
fi
echo $$ > "$LOCK/pid"
OUT=/tmp/fs-size.$$
dupid=""
cleanup() {
	if test -n "$dupid"; then kill "$dupid" 2>/dev/null; fi
	rm -rf "$LOCK" "$OUT"
}
trap cleanup EXIT

# at the top of a disk, measure each item on its own so hidden ones can be left out
set --
if test "${FS_REAL%/*}" = "$FS_ROOT"; then
	for _f in "$FS_REAL"/* "$FS_REAL"/.[!.]* "$FS_REAL"/..?*; do
		test -e "$_f" -o -L "$_f" || continue
		if fs_hidden "$FS_REAL" "${_f##*/}"; then continue; fi
		set -- "$@" "$_f"
	done
else
	set -- "$FS_REAL"
fi

: > "$OUT"
if test "$#" -gt 0; then
	nice du -skx "$@" > "$OUT" 2>/dev/null &
	dupid=$!
	_t0=$(date +%s)
	while kill -0 "$dupid" 2>/dev/null; do
		if test $(($(date +%s) - _t0)) -ge "$FS_SIZE_LIMIT"; then
			json_error "504 Gateway Timeout" toolong "This folder is too big to measure quickly. Open it and measure the folders inside instead."
		fi
		sleep 0.2 2>/dev/null || sleep 1
	done
	wait "$dupid" 2>/dev/null
	dupid=""
fi

# 1K blocks to bytes, in awk because shell arithmetic is only 32 bits here
bytes=$(awk '{ s += $1 } END { printf "%.0f", s * 1024 }' "$OUT")
printf 'Content-Type: application/json; charset=UTF-8\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n\r\n'
printf '{"bytes":%s}\n' "${bytes:-0}"
