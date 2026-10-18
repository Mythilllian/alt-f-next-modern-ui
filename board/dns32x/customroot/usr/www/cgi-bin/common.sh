
CONF_MISC=/etc/misc.conf
CONF_HOSTS=/etc/hosts

# sed removes any ' or " that would upset quoted assignment
# awk ensures that
# - all variables passed have legal names
# - special characters are not interpreted by sh
read_args() {
	read -r args
	eval $(echo -n $args | tr '\r' '\n' | sed -e 's/'"'"'/%27/g;s/"/%22/g' | \
		awk 'BEGIN{RS="&";FS="="}
			$1~/^[a-zA-Z][a-zA-Z0-9_]*$/ {
			printf "%s=%c%s%c\n",$1,39,$2,39}')

	# some forms needs key=value evaluated as value=key,
	# so reverse and evaluate them
	eval $(echo -n $args |  sed -e 's/'"'"'/%27/g;s/"/%22/g' | \
		awk 'BEGIN{RS="&";FS="="}
			$2~/^[a-zA-Z][a-zA-Z0-9_]*$/ {
			printf "%s=%c%s%c\n",$2,39,$1,39}' )
}

# like read_args above but for QUERY_STRING (does not evaluate value=key)
# split tok[&tok]*, where tok has form "<key=value>"
# notice that QUERY_STRING does not has spaces at its end (busybox httpd bug?)
parse_qstring() {
	eval $(echo -n $QUERY_STRING | sed -e 's/'"'"'/%27/g;s/"/%22/g' |
		awk 'BEGIN{RS="?";FS="="} $1~/^[a-zA-Z][a-zA-Z0-9_]*$/ {
			printf "%s=%c%s%c\n",$1,39,substr($0,index($0,$2)),39}')
}

isnumber() {
	echo "$1" | grep -qE '^[0-9.]+$'
}

# Celsius to Fahrenheit
celtofar() {
	awk 'END{ printf "%d", 9 * '$1' / 5 + 32}' </dev/null
}

# Fahrenheit to Celsius
fartocel() {
	awk 'END{ printf "%.1f", 5 / 9 * ( '$1' - 32)}' </dev/null
}

checkpass() {
	lpass=$(httpd -d "$1")
	if test -n "$lpass"; then
		if test -n "$(echo \"$lpass\" | tr -d [!-~])"; then
			echo "Use only ASCII characters and no spaces for the password: allowed are\n\
letters, numbers and ! \" # $ % & \' ( ) * + , - . / : ; < = > ? @ [ \\\ ] ^ _ \` { | } ~"
			return 1
		else
			echo $lpass
			return 0
		fi
	else
		echo "Password can't be empty"
		return 1
	fi
}

check_https() {
	if echo $HTTP_REFERER | grep -q 'http://'; then
		echo "<h4 class=\"warn\">You are using plain http, password will be transmited in clear.<br>
	You should use instead a <a href=\"https://${HTTP_HOST%%:*}\" target=\"_top\">secure https connection</a>.<br>$1</h4>"
	fi
}

checkip() {
	echo $* | awk '{ nf = split($0, a, ".")
		if (nf < 4) exit 1
		for (i=1; i<=nf; i++) {
			if (a[i] < 0 || a[i] > 255) exit 1
		}
		exit 0
	}'
}

gethname() {
	local th
    if ! checkip "$1"; then
        echo $1
    elif ! th=$(awk '/^'$1'[[:space:]]+/{print $3; exit 1}' $CONF_HOSTS); then
        echo $th
    elif ! th=$(nslookup $1 | awk '/Address.*'$1'/{if (length($4) != 0) {print $4; exit 1}}'); then
        echo $th
    else
        echo $1
    fi
}

checkmac() {
	echo "$1" | grep -q -e '^\([a-fA-F0-9]\{2\}:\)\{5\}[a-fA-F0-9]\{2\}$'
}

checkport() {
	netstat -ltn 2> /dev/null | grep -q ":$1[[:space:]]"
}

checkname() {
	echo "$1" | grep -v -q -e '^[^a-zA-Z]' -e '[^a-zA-Z0-9-].*'
}

find_mp() {
	if ! test -d "$1"; then return 1; fi
	tmp=$(readlink -f "$1")
	while ! mountpoint -q "$tmp"; do
		tmp=$(dirname "$tmp")
	done
	echo $tmp
}

check_folder() {
	if ! tmp=$(find_mp "$1"); then
		echo "\"$1\" does not exists or is not a folder."
		return 1
	fi

	if test "$tmp" = "/" -o "$tmp" = "."; then
		echo "\"$1\" is not on a filesystem."
		return 1
	fi

	if test "$tmp" = "$1"; then
		echo "\"$1\" is a filesystem root, not a folder."
		return 1
	fi
}

eatspaces() {
	echo "$*" | tr -d ' \t'
}

# mainly for fstab usage, where spaces are '\040' coded
path_escape() {
	echo "$1" | sed 's/ /\\040/g'
}

path_unescape() {
	echo "$1" | sed 's/\\040/ /g'
}

# FIXME: missing
# s/	/\&#x09;/g
# s/!/\&#x21;/g
# s/#/\&#x23;/g
# s/\\$/\&#x24;/g
# s/%/\&#x25;/g
# s/;/&#x3b;/g

http_encode() {
echo "$1" | sed "
s/\&/\&#x26;/g
s/ /\&#x20;/g
s/\"/\&#x22;/g
s/'/\&#x27;/g
s/(/\&#x28;/g
s/)/\&#x29;/g
s/\*/\&#x2a;/g
s/+/\&#x2b;/g
s/,/\&#x2c;/g
s/-/\&#x2d;/g
s/\./\&#x2e;/g
s/\//\&#x2f;/g
s/:/\&#x3a;/g
s/</\&#x3c;/g
s/=/\&#x3d;/g
s/>/\&#x3e;/g
s/?/\&#x3f;/g
s/@/\&#x40;/g
s/\[/\&#x5b;/g
s/\\\/\&#x5c;/g
s/\]/\&#x5d;/g
s/\^/\&#x5e;/g
s/_/\&#x5f;/g
s/\`/\&#x60;/g
s/{/\&#x7b;/g
s/|/\&#x7c;/g
s/}/\&#x7d;/g
s/~/\&#x7e;/g
"
}

# FIXME: howto make hexdump to output a '%'?
url_encode() {
	echo -n "$1" | hexdump -ve '/1 "-%X"' | tr '-' '%'
}

has_disks() {
	disks=$(ls /dev/sd?) >/dev/null 2>&1
	ndisks=$(echo "$disks" | grep /dev/ | wc -l)
	if test -z "$disks"; then
		echo "<br><strong>No disks found!</strong><br>"
		echo "</body></html>"
		exit 1
	fi
}

# $1=sda
disk_details() {
	. /etc/bay
	dbay=$(eval echo \$$1)
	dcap="$(eval echo \$${dbay}_cap)"
	dfam="$(eval echo \$${dbay}_fam)"
	dmod="$(eval echo \$${dbay}_mod)"
	if echo $dbay | grep -q ^usb; then
		dbay=${dbay:0:3}
	fi
}

# $1=sda
disk_power() {
	if test -b /dev/$1; then
		echo $(hdparm -C /dev/$1 2> /dev/null | awk '/drive/{print $4}')
	else
		echo "None"
	fi
}

# $1=part (sda2, eg)
isdirty() {
	res="$(tune2fs -l /dev/$1 2> /dev/null)"
	if test $? != 0; then return 1; fi
	if test $(echo "$res" | awk '
		/Filesystem state:/ {print $3}') = "clean"; then
		return 1
	fi
	return 0
}

# $1=part (sda2, eg)
ismount() {
	grep -q ^/dev/$1[[:space:]] /proc/mounts
}

find_dm() {
	eval $(dmsetup info /dev/$1/$2 | awk '/Major/{printf "mj=%d mi=%d", $3, $4}')
	awk '/'$mj' *'$mi'/{printf "%s", $4}' /proc/partitions
}

# $1=sda global: ln
fs_progress() {
	part=$1
	ln=""
	for k in check fix format convert shrink enlarg wip; do
		if test -f /tmp/${k}-${part}; then
			if kill -0 $(cat /tmp/${k}-${part}.pid) 2> /dev/null; then
				if test -s /tmp/${k}-${part}.log; then
					ln=$(cat /tmp/${k}-${part}.log | tr -s '\b\r\001\002' '\n' | tail -n1)
				fi
				if test $k = "check" -o $k = "fix"; then
					ln=$(echo $ln | awk '{ $3 += 0; if ($3 != 0 && $3 > $2) printf "step %d: %d%%", $1, $2*100/$3}')
				elif test $k = "format"; then
					ln=$(echo $ln | awk -F/ '/.*\/.*/{ $2 += 0; if ($2 != 0 && $2 > $1) printf "%d%%", $1*100/$2}')
				elif test $k = "shrink" -o $k = "enlarg"; then
					if grep -q resize2fs  /tmp/${k}-${part}.log 2> /dev/null; then
						ln=$(echo $ln | grep -o X)
						if test -n "$ln"; then
							step=$(tail -2 /tmp/${k}-${part}.log | head -1 | sed -n 's/Begin pass \([[:digit:]]\).*/\1/p')
							ln=" step 2.$step: $(expr $(echo "$ln" | wc -l) \* 100 / 40)%"
						fi
					else
						ln=$(echo $ln | awk '{ $3 += 0; if ($3 != 0 && $3 > $2) printf "step 1.%d: %d%%", $1, $2*100/$3}')
					fi
				elif test $k = "wip" ; then
					kill -SIGUSR1 $(cat /tmp/${k}-${part}.pid)
					tsz=$(head -1 /tmp/${k}-${part}.log 2> /dev/null)
					csz=$(tail -1  /tmp/${k}-${part}.log 2> /dev/null | cut -f1 -d" ")
					ln=$(printf "%d%%" $(expr $csz \* 100 / $tsz))
				fi
				ln="${k}ing...$ln"
			else
				rm /tmp/${k}-${part}*
			fi
		fi
	done
}

firstboot() {
	if ! test -f /tmp/firstboot; then return; fi

	pg=${0%.cgi}
	if test "$pg" = "login"; then return; fi

	currst=$(cat /tmp/firstboot)
	currpg=${currst%_?}

	if echo $0 | grep -q '_proc\.cgi'; then
		ppg=${0%_proc.cgi}
	fi

	if test -z "$ppg" -a "$pg" != "$currpg"; then
		gotopage /cgi-bin/${currpg}.cgi
		exit 0
	fi

msg1="Welcome to your first login to Alt-F.<br><br> <em>If you know what you are doing</em>, Logout to skip this wizard.<br><br>"
msg_host="You should now fill-in all the host details and Submit them."
msg_time_1="You should now specify the Continent/City where you live and Submit it.<br>"
msg_time_2="You should now adjust the current date and time, either through the internet or manually, and Submit it."
msg_diskwiz="You should now select a disk configuration."
msg_newuser_1="You should now specify the filesystem where users will login and store their personal data."
msg_newuser_2="You should now create an user account."
msg_smb="You can now create new folders and define them as network shares."
msg_packages_ipkg="You should now specify the filesystem where Alt-F packages can be installed."
msg_settings="You should now save in flash memory the changes that you have just made.<br>
You should do it whenever you want your changes to survive a box reboot."

	case "$currst" in
		host) next=time_1;;
		time_1) next=time_2;;
		time_2) next=diskwiz;;
		diskwiz) next=newuser_1;;
		newuser_1) next=newuser_2;;
		newuser_2) next=smb;;
		smb) if grep -q 'DNS-323' /tmp/board; then next=settings; else next=packages_ipkg; fi;;
		packages_ipkg) next=settings;;
		settings) next=status;;
		*) rm /tmp/firstboot; firstmsg=""; return ;;
	esac

	firstmsg="<h4 class=\"warn\">$msg1 $(eval echo \$msg_$currst)</h4>"

	if test "$ppg" = "$currpg"; then
		echo $next > /tmp/firstboot
	fi
}

# $1-title (optional)
html_header() {
	if test -n "$HTML_HEADER_DONE"; then return; fi
	HTML_HEADER_DONE="yes"
	if test "$#" != 0; then
		center="<h2 class="title">$1</h2>"
	fi

	echo -e "Content-Type: text/html; charset=UTF-8\r\n\r"

	cat<<-EOF
		<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">
		<html><head profile="http://www.w3.org/2005/10/profile">
		<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
		<link rel="icon" type="image/png" href="../dns-323.png">
		<style type="text/css">
			$(echo "$LOCAL_STYLE")
			html { height: 100%; }
			body { height: 100%; font-family: arial,verdana; }
		</style>
		$(load_thm default.thm)
		<title></title></head>
		<body>
		$center
	EOF
}

debug() {
	HTML_HEADER_DONE="yes"
	echo -e "Content-Type: text/html; charset=UTF-8\r\n\r"
	echo "<html><body><pre>$(set)"
}

enddebug() {
	echo "</pre></body></html>"
}

msg() {
	txt=$(echo "$1" | sed 's|"|\\"|g' | awk '{printf "%s\\n", $0}')

	html_header
	echo "<script type=text/javascript>
	alert(\"$txt\")
	window.location.assign(document.referrer)
	</script>
	</body></html>"
	exit 1
}

back_button() {
	echo "<input type=button value=\"Back\" onclick=\"history.back()\">"
}

# $1-label $2-url
goto_button() {
	echo "<input type=button value=\"$1\" onclick=\"window.location.assign('$2')\">"
}

# $1=pre-select part (eg: sda4) $2=name postfix, e.g. '1', optional
select_part() {
	if test -n "$1"; then presel=$1; fi

	echo "<select name=part$2>"
	echo "<option value=none>Select a filesystem</option>"

	df -h | while read ln; do
		part=""
		eval $(echo $ln | awk '/^\/dev\/(sd|md)/{printf "part=%s; pcap=%s; avai=%s", \
			$1, $2, $4}')
		if test -z $part; then continue; fi
		part=$(basename $part)
		partl=$(plabel $part)
		partb=$(sed -n "s/${part%[0-9]}=\(.*\)/, \1 disk/p" /etc/bay)
		if test -z "$partl"; then partl=$part; fi
		sel=""; if test "$presel" = "$part"; then sel="selected"; fi
		echo "<option $sel value=$part> $partl ($part, ${pcap}B, ${avai}B free${partb})</option>"
	done
	echo "</select>"
}

upload_file() {
# POST upload format:
# -----------------------------29995809218093749221856446032^M
# Content-Disposition: form-data; name="file1"; filename="..."^M
# Content-Type: application/octet-stream^M
# ^M    <--------- headers end with empty line
# file contents
# file contents
# file contents
# ^M    <--------- extra empty line
# -----------------------------29995809218093749221856446032--^M

	eval $(df -m /tmp | awk '/tmpfs/{printf "totalm=%d; freem=%d;", $2, $4}')
	reqm=$((CONTENT_LENGTH * 2 / 1024 / 1024))
	if test "$reqm" -gt "$freem"; then
		if ! mount -o remount,size=$((totalm + reqm + 10 - freem))M /tmp; then
			cat > /dev/null # discard transfer
			echo "Not enought /tmp memory,\n$reqm MB required, $freem MB available.\nIs swap active?"
			return 1
		fi
	fi

	read -r delim_line
	read -r Content_Disposition
	read -r Content_Type
	read -r empty_line

	if ! ( echo "$CONTENT_TYPE" | grep -q multipart/form-data &&
		echo "$Content_Disposition" | grep -q form-data ); then
			cat > /dev/null # discard transfer
			echo "Not a (simple) POST response."
			return 1
	fi

	fname1=$(echo $Content_Disposition | sed -n 's/.*[[:space:]]name="\(.*\)";.*/\1/p')
	hfname1=$(echo $Content_Disposition | sed -n 's/.*[[:space:]]filename="\(.*\)".*/\1/p')
	if test -z "$hfname1"; then
		cat > /dev/null # discard transfer
		echo "Not a valid Content_Disposition POST response."
		return 1
	fi

	fname1=/tmp/$fname1
	cat > $fname1

	# get next file name
	fname2=$(sed -n '/^Content-Disposition:/s/.*[[:space:]]name="\(.*\)";.*/\1/p' $fname1)
	hfname2=$(sed -n '/^Content-Disposition:/s/.*[[:space:]]filename="\(.*\)".*/\1/p' $fname1)

	if test -n "$hfname2"; then
		fname2=/tmp/$fname2
		sed -n '/'$delim_line'/,$p' $fname1 > $fname2

		# remove delim-line, cont-disp, cont-type, empty line, last empty line
		sed -i '1,4d' $fname2
		sed -i '$d' $fname2
		sed -i '$d' $fname2
	fi

	# remove fname2 from fname1 end (\r\n empty lines)
	sed -i '/'$delim_line'/,$d' $fname1
	#sed -i '$d' $fname1 # buggy busybox sed when last chars are '00 00  ff ff'
	flen=$(stat -t $fname1 | cut -d" " -f2)
	dd if=$fname1 of=$fname1 bs=1 seek=$((flen - 2)) count=0 >& /dev/null
	echo $fname1
}

download_file() {
	echo -e "HTTP/1.1 200 OK\r"
	echo -e "Content-Disposition: attachment; filename=\"$(basename $1)\"\r"
	echo -e "Content-Type: application/octet-stream\r\n\r"
	cat $1
}

# from_url location
gotoback() {
	from_url=$(httpd -d "$1")
	if echo "$from_url" | grep -q index.cgi; then
		gotopage /cgi-bin/$2
	else
		gotopage $from_url
	fi
}

gotopage() {
	if echo $0 | grep -q '_proc\.cgi'; then firstboot; fi

	echo -e "HTTP/1.1 303\r"
	echo -e "Content-Type: text/html; charset=UTF-8\r"
	echo -e "Location: $1\r\n\r"

	exit 0
}

js_gotopage() {
	if echo $0 | grep -q '_proc\.cgi'; then firstboot; fi
	html_header
	cat<<-EOF
		<script type="text/javascript">
			window.location.assign("$1")
		</script>
		</body></html>
	EOF
	exit 0
}

# ------------------------------------------------------------------
# Login sessions.
# After a good login, login_proc.cgi calls sess_new, which stores a random
# token in $SESS_DIR (tmpfs). The browser gets it in the ALTSID cookie.
# Every protected page calls check_cookie, the single place that validates it.
# Session file content: "<created> <last-seen> <client-ip> <keep>"
# Settings live in /etc/web-session.conf (see that file).
# ------------------------------------------------------------------
SESS_DIR=/tmp/sessions

sess_conf() {
	SESSION_IDLE=28800
	SESSION_ABS=604800
	SESSION_BIND_IP=yes
	if test -r /etc/web-session.conf; then . /etc/web-session.conf; fi
}

# sess_token: set SESS_TOKEN from the ALTSID cookie (empty if absent or malformed)
sess_token() {
	SESS_TOKEN=""
	_oifs=$IFS; IFS=';'; set -f
	for _kv in $HTTP_COOKIE; do
		_kv=${_kv#"${_kv%%[! ]*}"}
		case "$_kv" in ALTSID=*) SESS_TOKEN=${_kv#ALTSID=} ;; esac
	done
	IFS=$_oifs; set +f
	case "$SESS_TOKEN" in *[!0-9a-f]*) SESS_TOKEN="" ;; esac
	if test "${#SESS_TOKEN}" -ne 64; then SESS_TOKEN=""; fi
}

# sess_rand <bytes>: random hex string from /dev/urandom
sess_rand() {
	dd if=/dev/urandom bs="$1" count=1 2>/dev/null | hexdump -ve '/1 "%02x"'
}

# sess_cleanup: drop expired sessions and stale login challenges. No cron needed,
# it runs on every login.
sess_cleanup() {
	sess_conf
	_now=$(date +%s)
	for _f in "$SESS_DIR"/*; do
		if ! test -f "$_f"; then continue; fi
		_c=""; _l=""
		read -r _c _l _rest < "$_f"
		case "${_f##*/}" in
			salt.*) if test $((_now - ${_c:-0})) -gt 600; then rm -f "$_f"; fi ;;
			*)
				if test $((_now - ${_l:-0})) -gt "$SESSION_IDLE" -o $((_now - ${_c:-0})) -gt "$SESSION_ABS"; then
					rm -f "$_f"
				fi ;;
		esac
	done
}

# sess_new <yes|no>: create a session for the current client, sets SESS_TOKEN
sess_new() {
	sess_conf
	mkdir -p "$SESS_DIR"; chmod 700 "$SESS_DIR"
	sess_cleanup
	SESS_TOKEN=$(sess_rand 32)
	_now=$(date +%s)
	( umask 077; echo "$_now $_now ${REMOTE_ADDR:--} $1" > "$SESS_DIR/$SESS_TOKEN" )
}

# sess_cookie <yes|no> [secure]: print the Set-Cookie header for SESS_TOKEN
sess_cookie() {
	_ck="ALTSID=$SESS_TOKEN; Path=/; HttpOnly; SameSite=Strict"
	if test "$1" = yes; then _ck="$_ck; Max-Age=$SESSION_ABS"; fi
	if test -n "$2"; then _ck="$_ck; Secure"; fi
	printf 'Set-Cookie: %s\r\n' "$_ck"
}

# sess_end: delete the session of the current request and print an expiring cookie
sess_end() {
	sess_token
	if test -n "$SESS_TOKEN"; then rm -f "$SESS_DIR/$SESS_TOKEN"; fi
	printf 'Set-Cookie: ALTSID=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0\r\n'
}

# sess_valid: true if the request carries a live session. Slides the idle timeout.
sess_valid() {
	sess_conf
	sess_token
	if test -z "$SESS_TOKEN" -o ! -f "$SESS_DIR/$SESS_TOKEN"; then return 1; fi
	read -r _c _l _ip _keep < "$SESS_DIR/$SESS_TOKEN" || return 1
	_now=$(date +%s)
	if test $((_now - ${_l:-0})) -gt "$SESSION_IDLE" -o $((_now - ${_c:-0})) -gt "$SESSION_ABS"; then
		rm -f "$SESS_DIR/$SESS_TOKEN"
		return 1
	fi
	if test "$SESSION_BIND_IP" = yes -a "$_ip" != "-" -a -n "$REMOTE_ADDR" -a "$_ip" != "$REMOTE_ADDR"; then
		logger -t httpd "Session used from a different address ($REMOTE_ADDR, not $_ip)"
		return 1
	fi
	# the file already exists with mode 600, so a plain redirect keeps it private
	echo "$_c $_now $_ip $_keep" > "$SESS_DIR/$SESS_TOKEN"
	return 0
}

# csrf_ok: state-changing (POST) requests must come from this very site.
# Browsers always send Origin or Referer on a cross-site POST, so require one of them
# and require its host to match the Host header.
csrf_ok() {
	if test "$REQUEST_METHOD" != POST; then return 0; fi
	_o=$HTTP_ORIGIN
	if test "$_o" = null; then _o=""; fi
	if test -z "$_o"; then _o=$HTTP_REFERER; fi
	if test -z "$_o"; then return 1; fi
	_h=${_o#*://}; _h=${_h%%/*}
	test "$_h" = "$HTTP_HOST"
}

# check_cookie [api]: call at the top of every protected page. Lets valid sessions through;
# otherwise answers 401 to background requests (or whenever "api" is given) and sends
# people to the login page.
check_cookie() {
	if sess_valid; then
		if csrf_ok; then return 0; fi
		logger -t httpd "Rejected a form post from another site (${HTTP_ORIGIN:-$HTTP_REFERER})"
		printf 'Status: 403 Forbidden\r\nContent-Type: text/plain\r\n\r\nThis request did not come from the Alt-F pages.\n'
		exit 0
	fi

	if test -n "$HTTP_X_REQUESTED_WITH" -o "$1" = api; then
		printf 'Status: 401 Unauthorized\r\nContent-Type: text/plain\r\n\r\nPlease sign in again.\n'
		exit 0
	fi

	_to=/cgi-bin/login.cgi
	if test "$REQUEST_METHOD" != POST -a -n "$REQUEST_URI"; then
		case "${REQUEST_URI%%\?*}" in
			/cgi-bin/home.cgi|/cgi-bin/shares.cgi|/cgi-bin/advanced.cgi|/cgi-bin/confirm.cgi|/cgi-bin/files.cgi|/cgi-bin/status.cgi|/cgi-bin/classic.cgi)
				_to="$_to?$REQUEST_URI" ;;
			*)	# a classic page: after signing in, bring it back inside its frames
				_to="$_to?/cgi-bin/classic.cgi?p=$(qencode "$REQUEST_URI")" ;;
		esac
	fi
	printf 'HTTP/1.1 303\r\nContent-Type: text/html; charset=UTF-8\r\nCache-Control: no-store\r\nLocation: %s\r\n\r\n' "$_to"
	exit 0
}

busy_cursor_start() {
	html_header
	cat<<-EOF
		<script type="text/javascript">
			document.body.style.cursor = 'wait';
		</script>
	EOF
}

busy_cursor_end() {
	cat<<-EOF
		<script type="text/javascript">
			document.body.style.cursor = '';
		</script>
	EOF
}

# wait_count $1=msg
wait_count_start() {
	tmp_id=$(mktemp -t)
	tid=$(basename $tmp_id)
	cat<<-EOF
		$1: <span id="$tid">0</span>
		<script type="text/javascript">
			function wait_count_update(id) {
				obj = document.getElementById(id);
				obj.innerHTML = parseInt(obj.innerHTML) + 1;
			}
			var waittimerID;
			waittimerID = setInterval("wait_count_update('$tid')",1000);
			document.body.style.cursor = 'wait';
		</script>
	EOF
}

wait_count_stop() {
	rm -f $tmp_id
	cat<<-EOF
		<script type="text/javascript">
			clearInterval(waittimerID);
			document.body.style.cursor = '';
		</script>
	EOF
}

# use an iframe to embed apps own webpages
# FIXME, iframe height!
# $1=url to open, $2=page title
embed_page() {
	write_header ""

	cat<<-EOF
		<form name="embedf" action="zpto" method="post">
		<input type=hidden name="ifsrc" value="$1">
		<input type=hidden name="ifname" value="$2">
		</form>
		<iframe src="$1" width="100%" height="95%" frameborder="0" scrolling="auto"></iframe>
		</body></html>
	EOF
	exit 0
}

# Contributed by Dwight Hubbard, dwight.hubbard <guess> gmail.com, adapted by Joao Cardoso
# draws a bar graph, $1 is the percentage to display (1-100) and $2 is the text to display,
# if $2 is not present $1 is displayed for the text. Normally $2 is used when graphing data
# that has a range other than 1-100. Since this graph uses a div it doesn't display inline
drawbargraph() {

	linewidth="$1"
	if test "$linewidth" -gt 100; then
		linewidth="100"
	fi

	if test "$2" == ""; then text="$1%"; else text="$2"; fi
	if test "$3" == ""; then yellow=80; else yellow=$3; fi
	if test "$4" == ""; then red=90; else red=$4; fi

	if test "$linewidth" -gt $red; then
		bgcolor="#F66"
		fgcolor="#FFF"
	elif test "$linewidth" -gt $yellow; then
		bgcolor="#FF5"
		fgcolor="#000"
	else
		bgcolor="#6F6"
		fgcolor="#000"
	fi

	cat <<-EOF
	<div class="meter-wrap">
		<div class="meter-value" style="background-color: $bgcolor; width: $linewidth%;">
			<div class="meter-text" style="color: $fgcolor;">$text</div>
		</div>
	</div>
	EOF
}

# usage: mktt tt_id "tooltip msg"
mktt() {
	echo "<div id=\"$1\" class=\"ttip\">$2</div>"
}

# usage: mktt tt_id "tooltip message"
# <input ... $(ttip tt_id)>
ttip() {
	echo "onmouseover=\"popUp(event,'$1')\" onmouseout=\"popDown('$1')\""
}

menu_setup() {
	cat<<-EOF
		<script type="text/javascript">
		var menu = new Array();
		var men = {label:"Logout", url:"/cgi-bin/logout.cgi"};
		menu.push(men);
		men = {label:"Status", url:"/cgi-bin/status.cgi"};
		menu.push(men);
	EOF
	for i in Shortcuts $(cat Main.men); do
		echo -n "men = {label:\"$i\", smenu:["
		awk -F\| '{printf("{item:\"%s\", url:\"%s\"},\n", $1, $2)}' $i*.men
		cat<<-EOF
			]};
			menu.push(men);
		EOF
	done
	echo "menuSetup(\"$1\",\"$2\");"
	echo "</script>"
}

load_thm() {
	SCRIPTS=/scripts
	if test -f /usr/www/$SCRIPTS/$1; then
		while read ln; do
			if echo $ln | grep -q .js; then
				echo "<script type=\"text/javascript\" src=\"$SCRIPTS/$ln\"></script>"
			elif echo $ln | grep -q .css; then
				echo "<link rel=\"stylesheet\" type=\"text/css\" href=\"$SCRIPTS/$ln\">"
			elif echo $ln | grep -q .thm; then
				load_thm $ln
			fi
		done < /usr/www/$SCRIPTS/$1
	fi
}

# args: title [onload action]
write_header() {
	firstboot
	HTML_HEADER_DONE="yes"

	echo -e "Content-Type: text/html; charset=UTF-8\r\n\r"
	cat<<-EOF
		<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">
		<html>
		<head profile="http://www.w3.org/2005/10/profile">
		<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
		<link rel="icon" type="image/png" href="../dns-323.png">
	EOF

	if ! loadsave_settings -st >/dev/null; then
		warn_tt="The following files have changed since the last save:<br>$(loadsave_settings -lc | sed -n 's/ /<br>/gp')"
		warn=$(cat<<-EOF
			<h5 class="error"><a  class="error" href="/cgi-bin/settings.cgi" $(ttip tt_settings)>
			When done you must <u>save settings</u>
			<img src="../help.png" width="11" height="11" alt="help"></a></h5>
			EOF
			)
	fi

	if test "$#" = 2; then act="onLoad=\"$2\""; fi

	hf=${0%.cgi}_hlp.html
	if test -f /usr/www/$hf; then
		hlp="<a href=\"../$hf\" $(ttip tt_help)><img src=\"../help.png\" alt=\"help\" border=0></a>"
	fi

	if test -s "$CONF_MISC"; then . $CONF_MISC; fi

	cat<<-EOF
		<title>$1</title>
		<style type="text/css">
			$(echo "$LOCAL_STYLE")
		</style>
		$(load_thm default.thm)
		</head>
		<body $act>
		$(menu_setup "top" "$TOP_MENU")
		$(mktt tt_help "Get a descriptive help")
		$(mktt tt_settings "$warn_tt")
		<h2 class="title">$1 $hlp</h2>
		$warn
		$firstmsg
	EOF
}

md5() {
cat<<-EOF
	<script type="text/javascript">
	// https://github.com/jbt/js-crypto/blob/master/md5-min.js
	md5=function(){
		for(var m=[], l=0; 64>l;)
			m[l] = 0|4294967296*Math.abs(Math.sin(++l));
		return function(c){
			var e,g,f,a,h=[];
			c = unescape(encodeURI(c));
			for(var b=c.length, k=[e=1732584193,g=-271733879,~e,~g], d=0; d<=b;)
				h[d>>2] |= (c.charCodeAt(d)||128)<<8*(d++%4);
			h[c=16*(b+8>>6)+14]=8*b;
			for(d=0; d<c; d+=16){
				b=k;
				for(a=0; 64>a;)
					b = [f=b[3],(e=b[1]|0)+((f=b[0]+[e&(g=b[2])|~e&f,f&e|~f&g,e^g^f,g^(e|~f)][b=a>>4]+(m[a]+(h[[a,5*a+1,3*a+5,7*a][b]%16+d]|0)))<<(b=[7,12,17,22,5,9,14,20,4,11,16,23,6,10,15,21][4*b+a++%4])|f>>>32-b),e,g];
				for(a=4; a;)
					k[--a] = k[a]+b[a]
			}
			for(c=""; 32>a;)
				c += (k[a>>3]>>4*(1^a++&7)&15).toString(16);
			return c
		}
	}()
	</script>
EOF
}

# ------------------------------------------------------------------
# Shared page shell for the new web UI (alt-f.css / alt-f.js).
# Old pages keep using write_header; new pages call page_start/page_end.
# ------------------------------------------------------------------

# esc <text>: print text safe for HTML body and attribute values.
# Only forks sed when the text really contains a special character.
esc() {
	case "$1" in
		*[\&\<\>\"\']*)
			printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' \
				-e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&#39;/g" ;;
		*) printf '%s' "$1" ;;
	esac
}

# hsize <bytes>: human readable size
hsize() {
	awk -v b="${1:-0}" 'BEGIN {
		split("B KB MB GB TB PB", u, " "); i = 1
		while (b >= 1024 && i < 6) { b /= 1024; i++ }
		if (i == 1) printf "%d %s", b, u[i]; else printf "%.1f %s", b, u[i]
	}'
}

# ui_meter <percent> <label> [warn-at] [bad-at]: usage bar, colored by level
ui_meter() {
	_p=${1:-0}
	case "$_p" in ''|*[!0-9]*) _p=0 ;; esac
	if test "$_p" -gt 100; then _p=100; fi
	_c=""
	if test "$_p" -ge "${4:-90}"; then _c=" bad"
	elif test "$_p" -ge "${3:-80}"; then _c=" warn"; fi
	printf '<div class="meter%s" role="img" aria-label="%s"><i class="w%d"></i></div><span class="mt">%s</span>\n' \
		"$_c" "$(esc "$2")" "$_p" "$(esc "$2")"
}

# page_start <title> [section]: HTTP header, <head>, top bar and navigation.
# section is one of home files shares status advanced; it marks the current link.
# section "login" prints a bare page with no navigation (used before signing in).
page_start() {
	HTML_HEADER_DONE="yes"
	_sec="$2"
	# The first-time wizard is made of classic pages, which need their frames. When a
	# new page is opened on its own while the wizard is running, continue the wizard
	# inside the classic frames. Elsewhere the classic rules apply (firstboot).
	if test -f /tmp/firstboot -a "$_sec" != login -a "$HTTP_SEC_FETCH_DEST" = document; then
		_fb=$(cat /tmp/firstboot)
		_fb=${_fb%_?}
		if test "$_fb" != "$(basename "${0%.cgi}")" -a -f "./$_fb.cgi"; then
			gotopage "$(classic_url "$_fb.cgi")"
		fi
	fi
	firstboot
	if test -s "$CONF_MISC"; then . "$CONF_MISC"; fi

	printf 'Content-Type: text/html; charset=UTF-8\r\nCache-Control: no-store\r\n\r\n'
	cat<<-EOF
		<!DOCTYPE html>
		<html lang="en"><head>
		<meta charset="utf-8">
		<meta name="viewport" content="width=device-width, initial-scale=1">
		<meta name="color-scheme" content="light dark">
		<title>$(esc "$1") - Alt-F</title>
		<base target="_top">
		<link rel="icon" type="image/png" href="/dns-323.png">
		<link rel="stylesheet" href="/alt-f.css">
		<script>try{var t=localStorage.getItem('altf-theme');if(t==='light'||t==='dark')document.documentElement.setAttribute('data-theme',t)}catch(e){}</script>
		$(if test "$_sec" = login; then echo '<script>if(window.top!==window.self){window.top.location.href=window.location.href}</script>'; fi)
		</head><body>
		<a class="skip" href="#main">Skip to content</a>
	EOF
	if test "$_sec" != login; then
		cat<<-EOF
			<header class="topbar"><div class="topbar-in">
			<a class="brand" href="/cgi-bin/home.cgi">Alt-F</a>
			<button type="button" class="navtoggle" id="navtoggle" aria-expanded="false" aria-controls="nav">Menu</button>
			<nav class="nav" id="nav" aria-label="Main">
		EOF
		for _i in "home|Home|home.cgi" "files|Files|files.cgi" "shares|Shared folders|shares.cgi" \
				"status|Health|status.cgi" "advanced|Advanced|advanced.cgi"; do
			_k=${_i%%|*}; _r=${_i#*|}; _l=${_r%%|*}; _u=${_r#*|}
			if test "$_k" = "$_sec"; then _cur=' aria-current="page"'; else _cur=""; fi
			echo "<a href=\"/cgi-bin/$_u\"$_cur>$_l</a>"
		done
		cat<<-EOF
			<form method="post" action="/cgi-bin/logout.cgi"><button type="submit">Sign out</button></form>
			</nav></div></header>
		EOF
	fi
	echo '<main id="main">'
	if test -n "$firstmsg"; then echo "<div class=\"banner warn\">$firstmsg</div>"; fi
	case "$_sec" in advanced)
		if ! loadsave_settings -st >/dev/null 2>&1; then
			echo '<div class="banner warn">You have changed some settings that are not saved yet. They will be lost when the NAS restarts. <a href="/cgi-bin/settings.cgi">Save them now</a>.</div>'
		fi ;;
	esac
}

# page_end: footer, theme switch and script
page_end() {
	_ver=""
	read -r _ver < /etc/Alt-F 2>/dev/null
	cat<<-EOF
		</main>
		<footer class="foot">
		<span>Alt-F $(esc "$_ver")</span>
		$(if test "$_sec" != login; then echo '<a href="/cgi-bin/classic.cgi">Classic Alt-F pages</a>'; fi)
		<label class="theme" for="theme-select"><span>Appearance</span>
		<select id="theme-select"><option value="auto">Automatic</option><option value="light">Light</option><option value="dark">Dark</option></select></label>
		</footer>
		<script src="/alt-f.js"></script>
		</body></html>
	EOF
}

# page_error <plain-language message> [technical detail]: friendly error page.
# The technical detail is kept in a collapsed box for the administrator.
page_error() {
	page_start "Something went wrong" "${3:-}"
	echo "<div class=\"card\"><h1>Something went wrong</h1><p>$(esc "$1")</p>"
	if test -n "$2"; then
		echo "<details><summary>Technical details</summary><pre>$(esc "$2")</pre></details>"
	fi
	echo '<div class="actions"><a class="btn primary" href="/cgi-bin/home.cgi">Back to Home</a></div></div>'
	page_end
	exit 0
}

# storage_info: sets ST_TOTAL and ST_USED (KB), ST_PCT (overall) and ST_MAXPCT (fullest disk)
storage_info() {
	eval $(df -k 2>/dev/null | awk '$1 ~ /^\/dev\/(sd|md|dm-)/ && !seen[$1]++ {
			t += $2; u += $3; p = $5 + 0; if (p > m) m = p }
		END { printf "ST_TOTAL=%.0f; ST_USED=%.0f; ST_MAXPCT=%d; ST_PCT=%d",
			t, u, m, (t ? u * 100 / t : 0) }')
	ST_TOTAL=${ST_TOTAL:-0}; ST_USED=${ST_USED:-0}; ST_PCT=${ST_PCT:-0}; ST_MAXPCT=${ST_MAXPCT:-0}
}

# health_check: cheap checks from /proc and /sys only (does not wake sleeping disks).
# Sets HEALTH_LEVEL (ok, warn or bad) and HEALTH_MSGS (one plain sentence per line).
health_check() {
	HEALTH_LEVEL=ok; HEALTH_MSGS=""
	ST_TOTAL=0; ST_USED=0; ST_PCT=0; ST_MAXPCT=0
	_hc_add() {
		HEALTH_MSGS="${HEALTH_MSGS}${HEALTH_MSGS:+
}$2"
		if test "$1" = bad -o "$HEALTH_LEVEL" = ok; then HEALTH_LEVEL=$1; fi
	}

	_nd=0
	for _d in /dev/sd?; do if test -b "$_d"; then _nd=$((_nd + 1)); fi; done
	if test "$_nd" -eq 0; then
		_hc_add warn "No disks found. Plug in a drive and refresh."
	else
		storage_info
		if test "$ST_MAXPCT" -ge 95; then
			_hc_add bad "A disk is almost full. Delete files you no longer need, or add a bigger disk."
		elif test "$ST_MAXPCT" -ge 85; then
			_hc_add warn "A disk is getting full ($ST_MAXPCT% used)."
		fi
		if awk '$1 ~ /^\/dev\/(sd|md|dm-)/ { n = split($4, a, ","); for (i = 1; i <= n; i++) if (a[i] == "ro") f = 1 }
				END { exit !f }' /proc/mounts; then
			_hc_add bad "A disk can only be read right now, not written to. It may need a check. Ask whoever looks after the NAS."
		fi
	fi

	for _m in /sys/block/md[0-9]*/md/degraded; do
		if test -f "$_m"; then
			read -r _dg < "$_m"
			if test "${_dg:-0}" != 0; then
				_hc_add bad "One disk in your mirrored pair has a problem. Your files are still there, but they are no longer duplicated."
			fi
		fi
	done

	if test -r /tmp/sys/temp1_input; then
		read -r _tmp < /tmp/sys/temp1_input
		_crit=54
		if test -f /etc/sysctrl.conf; then . /etc/sysctrl.conf; _crit=${crit_temp:-54}; fi
		if test $((${_tmp:-0} / 1000)) -ge "$_crit"; then
			_hc_add bad "The NAS is running hot. Make sure the vents are not blocked."
		fi
	fi

	if test -s /var/log/systemerror.log; then
		_hc_add warn "The NAS has recorded a warning. Open Health for details."
	fi
}

# qparam <name>: print the still percent-encoded value of one query-string field.
# Reads only the field asked for, so nothing a visitor sends is ever evaluated.
qparam() {
	_oifs=$IFS; IFS='&'; set -f
	for _kv in $QUERY_STRING; do
		case "$_kv" in "$1="*) printf '%s' "${_kv#*=}"; break ;; esac
	done
	IFS=$_oifs; set +f
}

# risk_of <page>: which kind of care a settings page needs (empty if none).
# Used by the Advanced page and by confirm.cgi, so both always agree.
risk_of() {
	case "${1%%\?*}" in
		diskwiz.cgi|diskpart.cgi|diskmaint.cgi|raid.cgi|lvm.cgi|cryptsetup.cgi) echo disk ;;
		host.cgi|dnsmasq.cgi|hosts.cgi) echo network ;;
		firmware.cgi) echo firmware ;;
		settings.cgi) echo settings ;;
	esac
}

# classic_url <page>: address of a classic Alt-F page shown inside the classic frames
classic_url() {
	echo "/cgi-bin/classic.cgi?p=/cgi-bin/$(qencode "$1")"
}

# qencode <text>: escape the few characters that would break a query-string value
qencode() {
	printf '%s' "$1" | sed -e 's/%/%25/g' -e 's/?/%3F/g' -e 's/&/%26/g' -e 's/=/%3D/g' -e 's/+/%2B/g' -e 's/ /%20/g'
}

# shares_tsv: "name<TAB>path" for each Samba shared folder
shares_tsv() {
	awk '
	function flush() {
		l = tolower(name)
		if (name != "" && path != "" && l != "global" && l != "printers" && l != "homes" && l != "print$")
			print name "\t" path
	}
	/^[ \t]*[#;]/ { next }
	/^[ \t]*\[/ { flush(); name = $0; sub(/^[ \t]*\[/, "", name); sub(/\].*$/, "", name); path = ""; next }
	/^[ \t]*path[ \t]*=/ { path = $0; sub(/^[^=]*=[ \t]*/, "", path); sub(/[ \t\r]*$/, "", path) }
	END { flush() }' /etc/samba/smb.conf 2>/dev/null
}
