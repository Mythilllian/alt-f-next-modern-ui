# Shared helpers for the file browser (files.cgi, files_list.cgi, files_get.cgi).
# Everything a visitor can reach goes through fs_resolve, which only ever hands back
# a canonical path inside /mnt.

FS_ROOT=/mnt
FS_LIMIT=1000

fs_param() { qparam "$1"; }

# fs_resolve <percent-encoded path>: on success sets FS_REAL to the canonical path.
# On failure returns 1 and sets FS_ERR to bad, outside or missing.
#  - control characters and NUL, in raw or percent-encoded form, are refused
#  - the path must start with /mnt before it is touched
#  - realpath then removes "..", "." and follows every symlink, and the result must
#    still be /mnt or below it
fs_resolve() {
	FS_ERR=""; FS_REAL=""
	case "$1" in
		*%00*|*%0[aAdD]*) FS_ERR=bad; return 1 ;;
	esac
	if test "${#1}" -gt 4000; then FS_ERR=bad; return 1; fi
	_d=$(httpd -d "$1")
	case "$_d" in
		*[[:cntrl:]]*) FS_ERR=bad; return 1 ;;
		"$FS_ROOT"|"$FS_ROOT"/*) ;;
		*) FS_ERR=outside; return 1 ;;
	esac
	FS_REAL=$(realpath "$_d" 2>/dev/null) || { FS_ERR=missing; return 1; }
	case "$FS_REAL" in
		*[[:cntrl:]]*) FS_ERR=bad; return 1 ;;
		"$FS_ROOT"|"$FS_ROOT"/*)
			# realpath does not insist that the last part exists
			if test -e "$FS_REAL"; then return 0; fi
			FS_ERR=missing; return 1 ;;
	esac
	FS_ERR=outside
	return 1
}

# fs_message <error code>: plain-language reason
fs_message() {
	case "$1" in
		missing) echo "That folder isn't there any more. It may have been moved, or the drive was unplugged." ;;
		notdir) echo "That is a file, not a folder." ;;
		notfile) echo "That is a folder, not a file. Open it to see what is inside." ;;
		*) echo "That location isn't available." ;;
	esac
}

# fs_one <path>: print "type size date time" of the thing a path points to, following
# symlinks. Prints nothing if it is gone or is neither a file nor a folder.
fs_one() {
	set -f
	set -- $(ls -lndL --full-time "$1" 2>/dev/null)
	set +f
	case "$1" in
		-*) echo "f $5 $6 $7" ;;
		d*) echo "d 0 $6 $7" ;;
	esac
}

# fs_tsv <dir>: one tab-separated line per entry: type(d|f), bytes, "date time", name.
#
# This BusyBox is built without Unicode support, so "ls" shows every non-ASCII byte of
# a name as "?". Names therefore come from the shell's own glob (always exact) and "ls"
# supplies only size and date. Both sort bytewise, so line N of "ls" is entry N of the
# glob; if the counts ever disagree (folder changed while reading) each entry is asked
# for separately instead. Dot files and names with control characters are left out.
fs_tsv() {
	_dir=$1
	_tmp=$(mktemp /tmp/fsl.XXXXXX) || return 1
	ls -ln --full-time "$_dir" > "$_tmp" 2>/dev/null
	set -- "$_dir"/*
	if test "$#" -eq 1 && ! test -e "$1" -o -L "$1"; then rm -f "$_tmp"; return 0; fi
	_lines=$(grep -c '^[-dlbcps]' "$_tmp")
	if test "$_lines" -ne "$#"; then _fast=""; else _fast=1; fi

	_count=0; _first=1
	while test "$#" -gt 0; do
		_f=$1; shift
		if test -n "$_fast"; then
			read -r _perm _l1 _l2 _l3 _size _date _time _rest <&3
			if test -n "$_first" -a "$_perm" = total; then
				read -r _perm _l1 _l2 _l3 _size _date _time _rest <&3
			fi
			_first=""
		fi
		_name=${_f##*/}
		case "$_name" in *[[:cntrl:]]*|lost+found) continue ;; esac
		if test "$_count" -ge "$FS_LIMIT"; then echo "!truncated"; break; fi

		_type=""
		if test -n "$_fast"; then
			case "$_perm" in
				-*) _type=f ;;
				d*) _type=d; _size=0 ;;
				l*)	# a link: show it only if it leads to a file or folder inside /mnt
					_r=$(realpath "$_f" 2>/dev/null)
					case "$_r" in "$FS_ROOT"|"$FS_ROOT"/*)
						_info=$(fs_one "$_f")
						if test -n "$_info"; then read -r _type _size _date _time <<-EOT
							$_info
						EOT
						fi ;;
					esac ;;
			esac
		else
			_info=$(fs_one "$_f")
			if test -n "$_info"; then read -r _type _size _date _time <<-EOT
				$_info
			EOT
			fi
		fi
		if test -z "$_type"; then continue; fi
		printf '%s\t%s\t%s %s\t%s\n' "$_type" "$_size" "$_date" "$_time" "$_name"
		_count=$((_count + 1))
	done 3< "$_tmp"
	rm -f "$_tmp"
}

# fs_list <dir> <json|html>: one level only, as a JSON document or an HTML list
fs_list() {
	# the directory name travels in the environment: awk -v would interpret backslashes in it
	fs_tsv "$1" | FS_DIR="$1" awk -F'\t' -v mode="$2" '
	function jesc(s) {
		gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s)
		return s
	}
	function hesc(s) {
		gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); gsub(/"/, "\\&quot;", s)
		return s
	}
	function uenc(s,   i, c, r) {
		r = ""
		for (i = 1; i <= length(s); i++) {
			c = substr(s, i, 1)
			if (c ~ /[A-Za-z0-9_.~\/-]/) r = r c
			else r = r sprintf("%%%02X", ord[c])
		}
		return r
	}
	BEGIN {
		dir = ENVIRON["FS_DIR"]
		for (i = 1; i < 256; i++) ord[sprintf("%c", i)] = i
		n = 0; trunc = 0
		if (mode == "json") printf "{\"path\":\"%s\",\"entries\":[", jesc(dir)
		else print "<ul class=\"files\">"
	}
	$0 == "!truncated" { trunc = 1; next }
	NF >= 4 {
		type = $1; size = $2; mtime = $3; name = $4
		if (mode == "json") {
			printf "%s{\"n\":\"%s\",\"t\":\"%s\",\"s\":%.0f,\"m\":\"%s\"}", (n ? "," : ""), jesc(name), (type == "d" ? "d" : "-"), size, mtime
		} else {
			full = (dir == "/" ? "" : dir) "/" name
			if (type == "d")
				printf "<li><div class=\"row\"><div class=\"head\"><a class=\"name\" href=\"/cgi-bin/files.cgi?nojs=1&amp;p=%s\"><span class=\"ico\" aria-hidden=\"true\">&#128193;</span>%s</a></div><a class=\"meta\" href=\"/cgi-bin/files_get.cgi?p=%s\">Download folder</a><span class=\"meta date\">%s</span></div></li>\n", uenc(full), hesc(name), uenc(full), mtime
			else
				printf "<li><div class=\"row\"><div class=\"head\"><a class=\"name\" href=\"/cgi-bin/files_get.cgi?p=%s\"><span class=\"ico\" aria-hidden=\"true\">&#128196;</span>%s</a></div><span class=\"meta\">%.0f bytes</span><span class=\"meta date\">%s</span></div></li>\n", uenc(full), hesc(name), size, mtime
		}
		n++
	}
	END {
		if (mode == "json") printf "],\"truncated\":%s}\n", (trunc ? "true" : "false")
		else {
			print "</ul>"
			if (n == 0) print "<p class=\"empty\">This folder is empty.</p>"
			if (trunc) print "<p class=\"notice\">Only the first items are shown.</p>"
		}
	}'
}

# ------------------------------------------------------------------
# Uploads (files_put.cgi)
# ------------------------------------------------------------------

# fs_name_ok <relative path>: a plain name or a/b/c made of ordinary names.
# No leading or trailing slash, no empty, "." or ".." parts, no control characters.
fs_name_ok() {
	case "$1" in
		''|/*|*/|*//*|*[[:cntrl:]]*) return 1 ;;
	esac
	if test "${#1}" -gt 1000; then return 1; fi
	_ok=0
	_oifs=$IFS; IFS=/; set -f
	for _s in $1; do
		case "$_s" in
			.|..|.upload-*) _ok=1 ;;
		esac
		if test "${#_s}" -gt 255; then _ok=1; fi
	done
	IFS=$_oifs; set +f
	return $_ok
}

# fs_free_kb <dir>: free space in KB, capped at 2,000,000,000 (about 2 TB) so that it
# stays inside this BusyBox's 32-bit shell arithmetic. A request is at most 2 GB anyway.
fs_free_kb() {
	df -k "$1" 2>/dev/null | awk 'NR == 2 { f = $4; if (f > 2000000000) f = 2000000000; printf "%.0f", f }'
}

# fs_owner <dir>: sets FS_UID and FS_GID to the owner of a folder, so uploaded files
# can still be changed from other computers through Samba.
fs_owner() {
	set -f
	set -- $(ls -ldn "$1" 2>/dev/null)
	set +f
	FS_UID=$3; FS_GID=$4
}

fs_own() {	# fs_own <path> <mode>
	if test -n "$FS_UID" -a -n "$FS_GID"; then chown "$FS_UID:$FS_GID" "$1" 2>/dev/null; fi
	chmod "$2" "$1" 2>/dev/null
}

# fs_mkpath <base> <relative folder path>: create the folders one part at a time.
# A part that is a symlink is refused, so nothing can lead out of /mnt.
fs_mkpath() {
	_cur=$1
	_rc=0
	_oifs=$IFS; IFS=/; set -f
	for _s in $2; do
		_cur="$_cur/$_s"
		if test -L "$_cur"; then _rc=1; break; fi
		if test -d "$_cur"; then continue; fi
		if test -e "$_cur"; then _rc=1; break; fi
		if ! mkdir "$_cur" 2>/dev/null; then _rc=1; break; fi
		fs_own "$_cur" 775
	done
	IFS=$_oifs; set +f
	FS_TARGET=$_cur
	return $_rc
}

# fs_unique <dir> <name>: sets FS_FINAL to a name that is not taken, adding " (2)",
# " (3)" and so on before the extension. Nothing is ever overwritten.
fs_unique() {
	FS_FINAL=$2
	_n=2
	case "$2" in
		?*.*) _b=${2%.*}; _e=.${2##*.} ;;
		*) _b=$2; _e="" ;;
	esac
	while test -e "$1/$FS_FINAL" -o -L "$1/$FS_FINAL"; do
		FS_FINAL="$_b ($_n)$_e"
		_n=$((_n + 1))
	done
}
