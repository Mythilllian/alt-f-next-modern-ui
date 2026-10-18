#!/bin/sh

SECR=/etc/web-secret
TZF=/etc/TZ

source ./common.sh

# Read only the fields this page knows about. This runs before anyone is signed in,
# so it must not use read_args, which would let a visitor set arbitrary variables.
read -r args
passwd=""; passwd_again=""; pwhash=""; salt=""; from_url=""; keep=""
_oifs=$IFS; IFS='&'; set -f
for _kv in $args; do
	case "$_kv" in
		passwd=*) passwd=${_kv#passwd=} ;;
		passwd_again=*) passwd_again=${_kv#passwd_again=} ;;
		pwhash=*) pwhash=${_kv#pwhash=} ;;
		salt=*) salt=${_kv#salt=} ;;
		from_url=*) from_url=${_kv#from_url=} ;;
		keep=yes) keep=yes ;;
	esac
done
IFS=$_oifs; set +f

# a sign-in problem the person can fix by trying again
login_error() {
	page_start "Sign in" login
	cat<<-EOT
		<div class="login"><div class="card"><h1>That did not work</h1>
		<p>$(esc "$1")</p>
		<div class="actions"><a class="btn primary" href="/cgi-bin/login.cgi">Back to sign in</a></div>
		</div></div>
	EOT
	page_end
	exit 0
}

try_again() {
	sleep 2
	_back="/cgi-bin/login.cgi?e=1"
	if test -n "$from_url"; then _back="$_back&f=$from_url"; fi
	gotopage "$_back"
}

if ! test -s "$SECR"; then
	# first time: choose the password
	if test -z "$passwd"; then
		login_error "The password can't be empty."
	elif test "$passwd" != "$passwd_again"; then
		login_error "The two passwords don't match."
	fi

	if ! passwd=$(checkpass "$passwd"); then
		login_error "$passwd"
	fi

	echo -n $passwd > $SECR
	chmod og-r $SECR
	# FIXME: if root already has a password, don't change it?
	echo "root:$passwd" | chpasswd > /dev/null 2>&1

	echo -e "username=Administrator\npassword=$passwd" > /etc/samba/credentials.root
	chmod og-rw /etc/samba/credentials.root
	if ! grep -q '^root = ' /etc/samba/smbusers 2>/dev/null; then
		echo "root = \"Administrator\"" >> /etc/samba/smbusers
	fi
	echo -e "$passwd\n$passwd" | smbpasswd -s -a root >& /dev/null

	sed -i '/root/d' /etc/rsyncd.secrets
	echo -e "root:$passwd" >> /etc/rsyncd.secrets

	if test -z "$(loadsave_settings -ls)"; then
		echo host > /tmp/firstboot
		loc=$(classic_url host.cgi)
	else
		loc="/cgi-bin/home.cgi"
	fi
else
	# Normal sign in. The login page left a one-time challenge ("salt") on disk;
	# the browser answers with md5(password + salt). It is deleted on first use.
	case "$salt" in ''|*[!0-9a-f]*) try_again ;; esac
	if test "${#salt}" -ne 32 -o ! -f "$SESS_DIR/salt.$salt"; then try_again; fi
	read -r _issued < "$SESS_DIR/salt.$salt"
	rm -f "$SESS_DIR/salt.$salt"
	# a challenge is good for 10 minutes
	if test $(($(date +%s) - ${_issued:-0})) -gt 600; then try_again; fi

	if test -z "$pwhash"; then
		# no JavaScript: the password arrived as typed, so hash it here
		pwhash=$(printf '%s%s' "$(httpd -d "$passwd")" "$salt" | md5sum | cut -d" " -f1)
	fi
	expect=$( { cat "$SECR"; printf '%s' "$salt"; } | md5sum | cut -d" " -f1)
	if test "$pwhash" != "$expect"; then
		logger -t httpd "Failed web login from ${REMOTE_ADDR:-unknown}"
		try_again
	fi

	loc="/cgi-bin/home.cgi"
	if test -n "$from_url"; then
		want=$(httpd -d "$from_url")
		# only ever send people to a page on this NAS, and refuse anything that could
		# smuggle in extra response headers
		case "$want" in
			/cgi-bin/login*|/cgi-bin/logout*|*..*) ;;
			/cgi-bin/*[!-A-Za-z0-9_./?=\&%:+~,@]*) ;;
			/cgi-bin/*) loc=$want ;;
		esac
	fi
fi

sess_new "${keep:-no}"
secure=""
case "${HTTP_ORIGIN:-$HTTP_REFERER}" in https://*) secure=yes ;; esac

printf 'HTTP/1.1 303\r\nContent-Type: text/html\r\nCache-Control: no-store\r\n'
sess_cookie "${keep:-no}" "$secure"
printf 'Location: %s\r\n\r\n' "$loc"
