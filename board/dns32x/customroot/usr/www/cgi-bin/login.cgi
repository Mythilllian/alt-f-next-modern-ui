#!/bin/sh

source ./common.sh

SECR=/etc/web-secret

# already signed in: go straight to the home page
if sess_valid; then
	gotopage /cgi-bin/home.cgi
fi

# On a failed attempt login_proc.cgi sends us back with e=1 (and the page we wanted in f=).
# Otherwise the query string is the page that sent us here.
err=""; from="$QUERY_STRING"
case "$QUERY_STRING" in
	e=1\&f=*) err=1; from=${QUERY_STRING#e=1&f=} ;;
	e=1) err=1; from="" ;;
esac

page_start "Sign in" login
echo '<div class="login">'

if test -n "$(ls /tmp/check-* 2> /dev/null)"; then
	echo '<div class="banner warn">The NAS is checking its disks, so your files may not be available yet. You can follow the progress on the Health page after you sign in.</div>'
	if test ! -f $SECR -a -z "$(loadsave_settings -ls)"; then
		echo '<div class="banner bad">This is the first time you are signing in. Please wait for the disk check to finish before you continue.</div>'
	fi
fi

if test -n "$err"; then
	echo '<div class="banner bad" role="alert">That password did not work. Please try again.</div>'
fi

if ! test -s $SECR; then
	if echo "$HTTP_REFERER" | grep -q '^http://'; then
		echo "<div class=\"banner warn\">This page is not encrypted, so your password could be seen by others on your network. <a href=\"https://${HTTP_HOST%%:*}\" target=\"_top\">Use the secure version instead</a>.</div>"
	fi
	cat<<-EOF
		<form class="card" method="post" action="/cgi-bin/login_proc.cgi">
		<h1>Welcome</h1>
		<p class="lead">Choose a password for your NAS. You will use it to sign in here, and it also becomes the administrator password.</p>
		<div class="field"><label for="passwd_id">New password</label>
		<input type="password" name="passwd" id="passwd_id" autocomplete="new-password" required autofocus></div>
		<div class="field"><label for="passwd_again">Type it again</label>
		<input type="password" name="passwd_again" id="passwd_again" autocomplete="new-password" required></div>
		<input type="hidden" name="from_url" value="$(esc "$from")">
		<div class="actions"><button class="btn primary" type="submit">Set password</button></div>
		</form>
	EOF
else
	mkdir -p "$SESS_DIR"; chmod 700 "$SESS_DIR"
	salt=$(sess_rand 16)
	date +%s > "$SESS_DIR/salt.$salt"

	cat<<-EOF
		<form class="card" method="post" action="/cgi-bin/login_proc.cgi" id="loginf">
		<h1>Sign in</h1>
		<p class="lead">Enter your NAS password to continue.</p>
		<div class="field"><label for="passwd_id">Password</label>
		<input type="password" name="passwd" id="passwd_id" autocomplete="current-password" required autofocus></div>
		<label class="check"><input type="checkbox" name="keep" value="yes"> Keep me signed in on this device</label>
		<input type="hidden" name="salt" value="$salt">
		<input type="hidden" name="pwhash" id="pwhash_id" value="">
		<input type="hidden" name="from_url" value="$(esc "$from")">
		<div class="actions"><button class="btn primary" type="submit">Sign in</button></div>
		</form>
	EOF
	md5
	cat<<-EOF
		<script>
		/* Send a hash instead of the typed password. Without JavaScript the form
		   still works: the server then does the hashing itself. */
		document.getElementById('loginf').addEventListener('submit', function (e) {
			var f = e.target;
			f.pwhash.value = md5(f.passwd.value + f.salt.value);
			f.passwd.value = '';
		});
		</script>
	EOF
fi

echo '</div>'
page_end
