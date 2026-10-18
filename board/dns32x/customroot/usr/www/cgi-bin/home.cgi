#!/bin/sh

source ./common.sh
check_cookie

page_start "Home" home
health_check

nshares=$(shares_tsv | grep -c .)

cat<<-EOT
	<h1>Welcome back</h1>
	<p class="lead">Here is how your NAS is doing today.</p>
EOT

case "$HEALTH_LEVEL" in
	ok)
		echo '<div class="banner ok">Everything looks fine.</div>' ;;
	*)
		echo "<div class=\"banner $HEALTH_LEVEL\">Something needs a look. <a href=\"/cgi-bin/status.cgi\">See the details</a></div>" ;;
esac

echo '<div class="grid">'

# Files: the one thing most people come here for
cat<<-EOT
	<a class="card tile" href="/cgi-bin/files.cgi">
	<h2>Files</h2>
	<p>Browse your folders, open pictures and documents, and download what you need.</p>
	<span class="btn primary">Open Files</span>
	</a>
EOT

# Disk health and space
echo '<a class="card tile" href="/cgi-bin/status.cgi"><h2>Disk health and space</h2>'
if test -z "$ST_TOTAL_H"; then
	echo '<p>No disks found. Plug in a drive and refresh.</p>'
else
	ui_meter "$ST_PCT" "$ST_USED_H used of $ST_TOTAL_H"
	if test "$ST_MAXPCT" -ge 95; then
		echo '<p>A disk is almost full.</p>'
	elif test "$ST_MAXPCT" -ge 85; then
		echo '<p>A disk is getting full.</p>'
	else
		echo '<p>There is plenty of room left.</p>'
	fi
fi
echo '<span class="go">See disk details</span></a>'

# Shared folders
cat<<-EOT
	<a class="card tile" href="/cgi-bin/shares.cgi">
	<h2>Shared folders</h2>
EOT
case "$nshares" in
	0) echo '<p>No shared folders yet.</p>' ;;
	1) echo '<p>1 folder is shared with the computers on your network.</p>' ;;
	*) echo "<p>$nshares folders are shared with the computers on your network.</p>" ;;
esac
echo '<span class="go">See shared folders</span></a>'

# Is everything OK?
echo '<a class="card tile" href="/cgi-bin/status.cgi"><h2>Is everything OK?</h2>'
if test "$HEALTH_LEVEL" = ok; then
	echo '<p>Yes. The disks, temperature and warnings all look fine.</p>'
else
	echo '<ul>'
	echo "$HEALTH_MSGS" | while read -r _m; do echo "<li>$(esc "$_m")</li>"; done
	echo '</ul>'
fi
echo '<span class="go">See full health report</span></a>'

echo '</div>'
page_end
