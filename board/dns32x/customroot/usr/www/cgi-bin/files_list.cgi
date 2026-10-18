#!/bin/sh
# One folder level under /mnt as JSON: {"path":..,"entries":[{"n":name,"t":"d|-","s":bytes,"m":"YYYY-MM-DD HH:MM:SS"}],"truncated":bool}
# Errors are {"error":"plain-language message"} with a matching HTTP status.

source ./common.sh
source ./fs_common.sh
check_cookie api

json_error() {
	printf 'Status: %s\r\nContent-Type: application/json; charset=UTF-8\r\nCache-Control: no-store\r\n\r\n' "$1"
	printf '{"error":"%s"}\n' "$(fs_message "$2" | sed 's/"/\\"/g')"
	exit 0
}

p=$(fs_param p)
if test -z "$p"; then p=$FS_ROOT; fi

if ! fs_resolve "$p"; then
	case "$FS_ERR" in
		missing) json_error "404 Not Found" missing ;;
		*) json_error "403 Forbidden" outside ;;
	esac
fi
if ! test -d "$FS_REAL"; then json_error "400 Bad Request" notdir; fi

printf 'Content-Type: application/json; charset=UTF-8\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n\r\n'
fs_list "$FS_REAL" json
