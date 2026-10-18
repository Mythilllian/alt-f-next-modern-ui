#!/bin/sh
# Stream one file from /mnt. p=<path>, optional inline=1 to show safe types in the browser.
# If p is a folder, stream it as a tar archive (symlinks are stored as links, never followed).

source ./common.sh
source ./fs_common.sh
check_cookie api

fail() {
	printf 'Status: %s\r\nContent-Type: text/plain; charset=UTF-8\r\nCache-Control: no-store\r\n\r\n%s\n' "$1" "$(fs_message "$2")"
	exit 0
}

p=$(fs_param p)
if test -z "$p"; then fail "400 Bad Request" outside; fi
if ! fs_resolve "$p"; then
	case "$FS_ERR" in
		missing) fail "404 Not Found" missing ;;
		*) fail "403 Forbidden" outside ;;
	esac
fi
if test -d "$FS_REAL"; then
	if test "$FS_REAL" = "$FS_ROOT"; then fail "400 Bad Request" notfile; fi
	name=${FS_REAL##*/}
	ascii=$(printf '%s' "$name" | tr -c 'A-Za-z0-9._ -' '_')
	utf8=$(printf '%s' "$name" | hexdump -ve '/1 "-%02X"' | tr '-' '%')
	printf 'Content-Type: application/x-tar\r\n'
	printf 'Content-Disposition: attachment; filename="%s.tar"; filename*=UTF-8'"''"'%s.tar\r\n' "$ascii" "$utf8"
	printf 'X-Content-Type-Options: nosniff\r\nCache-Control: private, no-store\r\n\r\n'
	# no Content-Length: the size is not known before the archive is made
	# the top folder of a disk holds Alt-F's own files, which are left out
	set --
	if test "${FS_REAL%/*}" = "$FS_ROOT"; then
		for _p in $FS_PRIVATE; do set -- "$@" --exclude "$name/$_p"; done
		for _p in "$FS_REAL"/zi??????; do
			if fs_hidden "$FS_REAL" "${_p##*/}"; then set -- "$@" --exclude "$name/${_p##*/}"; fi
		done
	fi
	cd "${FS_REAL%/*}" && exec tar -cf - "$@" -- "$name" 2>/dev/null
	exit 0
fi
if ! test -f "$FS_REAL" -a -r "$FS_REAL"; then fail "404 Not Found" missing; fi

# size is the 5th column of the long listing (no stat -c in this BusyBox)
set -f
set -- $(ls -ln "$FS_REAL" 2>/dev/null)
size=$5
set +f
case "$size" in ''|*[!0-9]*) fail "404 Not Found" missing ;; esac

name=${FS_REAL##*/}
ext=$(printf '%s' "${name##*.}" | tr 'A-Z' 'a-z')
if test "$ext" = "$name"; then ext=""; fi

# only types that cannot run script in the page are ever shown inline
type="application/octet-stream"; safe=""
case "$ext" in
	jpg|jpeg) type=image/jpeg; safe=1 ;;
	png) type=image/png; safe=1 ;;
	gif) type=image/gif; safe=1 ;;
	webp) type=image/webp; safe=1 ;;
	pdf) type=application/pdf; safe=1 ;;
	txt|log|md|csv) type="text/plain; charset=UTF-8"; safe=1 ;;
	mp3) type=audio/mpeg; safe=1 ;;
	m4a) type=audio/mp4; safe=1 ;;
	ogg|oga) type=audio/ogg; safe=1 ;;
	wav) type=audio/wav; safe=1 ;;
	mp4|m4v) type=video/mp4; safe=1 ;;
	webm) type=video/webm; safe=1 ;;
	zip) type=application/zip ;;
	gz|tgz) type=application/gzip ;;
	tar) type=application/x-tar ;;
	doc) type=application/msword ;;
	docx) type=application/vnd.openxmlformats-officedocument.wordprocessingml.document ;;
	xls) type=application/vnd.ms-excel ;;
	xlsx) type=application/vnd.openxmlformats-officedocument.spreadsheetml.sheet ;;
	ppt) type=application/vnd.ms-powerpoint ;;
	pptx) type=application/vnd.openxmlformats-officedocument.presentationml.presentation ;;
	mkv) type=video/x-matroska ;;
	avi) type=video/x-msvideo ;;
	mov) type=video/quicktime ;;
esac

disp=attachment
if test "$(fs_param inline)" = 1 -a -n "$safe"; then disp=inline; fi

# Content-Disposition: a plain ASCII fallback plus the exact name, percent-encoded (RFC 5987)
ascii=$(printf '%s' "$name" | tr -c 'A-Za-z0-9._ -' '_')
utf8=$(printf '%s' "$name" | hexdump -ve '/1 "-%02X"' | tr '-' '%')

printf 'Content-Type: %s\r\n' "$type"
printf 'Content-Length: %s\r\n' "$size"
printf 'Content-Disposition: %s; filename="%s"; filename*=UTF-8'"''"'%s\r\n' "$disp" "$ascii" "$utf8"
printf 'X-Content-Type-Options: nosniff\r\nContent-Security-Policy: sandbox\r\nCache-Control: private, no-store\r\n\r\n'
exec cat "$FS_REAL"
