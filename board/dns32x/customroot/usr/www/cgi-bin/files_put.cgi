#!/bin/sh
# Upload into a folder under /mnt.
#
#   GET  ?check=1&p=<folder>                     {"free":<KB>}
#   POST ?p=<folder>&n=<name or sub/folder/name> raw file bytes as the request body
#   POST ?form=1&p=<folder>                      browser form (multipart), for pages without JavaScript
#
# The body is streamed straight to disk, never held in memory. It goes to a hidden
# temporary file first and is renamed when complete, so an interrupted upload leaves
# nothing behind. An existing file is never replaced: the new one gets " (2)" in its name.
# One request carries at most 2 GB (the BusyBox httpd limit).

source ./common.sh
source ./fs_common.sh

FORM=$(qparam form)
if test "$FORM" = 1; then check_cookie; else check_cookie api; fi

TMP=""
cleanup() { if test -n "$TMP"; then rm -f "$TMP"; fi; }
trap cleanup EXIT

# drain <bytes>: read and drop a request body so the browser can see our answer
# (only worth doing when it is not huge)
drain() { if test "${CONTENT_LENGTH:-0}" -le 67108864; then cat > /dev/null; fi; }

# fail <http status> <code> <plain-language message>
fail() {
	drain
	if test "$FORM" = 1; then
		printf 'HTTP/1.1 303\r\nContent-Type: text/html\r\nCache-Control: no-store\r\nLocation: /cgi-bin/files.cgi?nojs=1&p=%s&up=%s\r\n\r\n' "$(qencode "${FS_REAL:-$FS_ROOT}")" "$2"
	else
		printf 'Status: %s\r\nContent-Type: application/json; charset=UTF-8\r\nCache-Control: no-store\r\n\r\n{"error":"%s","code":"%s"}\n' "$1" "$3" "$2"
	fi
	exit 0
}

p=$(qparam p)
if test -z "$p" || ! fs_resolve "$p"; then
	case "$FS_ERR" in
		missing) fail "404 Not Found" missing "That folder isn't there any more. It may have been moved, or the drive was unplugged." ;;
		*) fail "403 Forbidden" outside "That location isn't available." ;;
	esac
fi
if ! test -d "$FS_REAL"; then fail "400 Bad Request" notdir "That is a file, not a folder."; fi
if test "$FS_REAL" = "$FS_ROOT"; then fail "400 Bad Request" root "Open a disk first, then upload into one of its folders."; fi
if ! test -w "$FS_REAL"; then fail "403 Forbidden" readonly "This folder can't be written to. The disk may be set to read-only."; fi

if test "$(qparam check)" = 1; then
	printf 'Content-Type: application/json; charset=UTF-8\r\nCache-Control: no-store\r\n\r\n{"free":%s}\n' "$(fs_free_kb "$FS_REAL")"
	exit 0
fi

if test "$REQUEST_METHOD" != POST; then fail "405 Method Not Allowed" method "That request is not allowed."; fi
len=${CONTENT_LENGTH:-0}
case "$len" in ''|*[!0-9]*) fail "400 Bad Request" bad "That upload could not be read." ;; esac

free=$(fs_free_kb "$FS_REAL")
# compared in KB (with 1 MB spare) to keep the numbers small
if test "${free:-0}" -lt $((len / 1024 + 1025)); then
	fail "413 Payload Too Large" space "There isn't enough room on the disk for this file."
fi

fs_owner "$FS_REAL"

if test "$FORM" = 1; then
	# multipart envelope: delimiter line, Content-Disposition, Content-Type, empty line,
	# then the file, then CRLF + delimiter + "--" + CRLF
	case "$CONTENT_TYPE" in multipart/form-data*) ;; *) fail "400 Bad Request" bad "That upload could not be read." ;; esac
	read -r delim
	read -r disp
	read -r _ctype
	read -r _empty
	fname=$(printf '%s' "$disp" | sed -n 's/.*filename="\(.*\)".*/\1/p')
	fname=$(httpd -d "$fname")
	fname=${fname##*/}; fname=${fname##*\\}
	if ! fs_name_ok "$fname"; then fail "400 Bad Request" name "That file name can't be used."; fi
	rel=$fname
else
	rel=$(qparam n)
	case "$rel" in *%00*) rel="" ;; esac	# decoding would cut the name at the NUL
	rel=$(httpd -d "$rel")
	if ! fs_name_ok "$rel"; then fail "400 Bad Request" name "That file name can't be used."; fi
fi

# folders inside the upload (folder uploads), created safely
dir=$FS_REAL
file=${rel##*/}
case "$rel" in
	*/*)
		if ! fs_mkpath "$dir" "${rel%/*}"; then fail "400 Bad Request" name "That folder name can't be used."; fi
		dir=$FS_TARGET ;;
esac

fs_unique "$dir" "$file"
TMP="$dir/.upload-$$-$len"
if ! cat > "$TMP"; then
	rm -f "$TMP"; TMP=""
	cat > /dev/null
	fail "500 Internal Server Error" write "The file could not be saved. The disk may be full."
fi

set -f
set -- $(ls -ln "$TMP" 2>/dev/null)
set +f
size=$5

if test "$FORM" = 1; then
	# cut the closing delimiter off the end of the file
	tail=$((2 + ${#delim} - 1 + 2 + 2))
	size=$((size - tail))
	if test "$size" -lt 0; then fail "400 Bad Request" bad "That upload could not be read."; fi
	dd if=/dev/null of="$TMP" bs=1 seek="$size" count=0 2> /dev/null
else
	if test "$size" != "$len"; then
		fail "400 Bad Request" partial "The upload was cut short. Please try again."
	fi
fi

fs_own "$TMP" 664
if ! mv "$TMP" "$dir/$FS_FINAL"; then fail "500 Internal Server Error" write "The file could not be saved."; fi
TMP=""

if test "$FORM" = 1; then
	printf 'HTTP/1.1 303\r\nContent-Type: text/html\r\nCache-Control: no-store\r\nLocation: /cgi-bin/files.cgi?nojs=1&p=%s&up=ok\r\n\r\n' "$(qencode "$FS_REAL")"
else
	saved=$FS_FINAL
	case "$rel" in */*) saved="${rel%/*}/$FS_FINAL" ;; esac
	printf 'Content-Type: application/json; charset=UTF-8\r\nCache-Control: no-store\r\n\r\n{"ok":true,"name":"%s"}\n' \
		"$(printf '%s' "$saved" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
fi
