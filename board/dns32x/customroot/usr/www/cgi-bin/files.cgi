#!/bin/sh

source ./common.sh
source ./fs_common.sh
check_cookie

page_start "Files" files

cat<<-EOT
	<h1>Files</h1>
	<p class="lead">Open a folder to look inside. Tap a file to download it.</p>
EOT

if test "$(fs_param nojs)" = 1; then
	# page for browsers without JavaScript: the same listing, built on the server
	p=$(fs_param p)
	if test -z "$p"; then p=$FS_ROOT; fi
	if fs_resolve "$p" && test -d "$FS_REAL"; then
		echo '<nav aria-label="You are here"><ol class="crumbs">'
		echo "<li><a href=\"/cgi-bin/files.cgi?nojs=1&amp;p=$FS_ROOT\">All disks</a></li>"
		_acc=$FS_ROOT
		_rest=${FS_REAL#$FS_ROOT}
		_oifs=$IFS; IFS=/; set -f
		for _seg in $_rest; do
			if test -z "$_seg"; then continue; fi
			_acc="$_acc/$_seg"
			echo "<li><a href=\"/cgi-bin/files.cgi?nojs=1&amp;p=$(url_encode "$_acc")\">$(esc "$_seg")</a></li>"
		done
		IFS=$_oifs; set +f
		echo '</ol></nav><div class="card">'
		fs_list "$FS_REAL" html
		echo '</div>'
		if test "$FS_REAL" = "$FS_ROOT" && test -z "$(ls "$FS_ROOT" 2>/dev/null)"; then
			echo '<p class="empty">No disks found. Plug in a drive and refresh.</p>'
		fi
	else
		echo "<div class=\"banner bad\">$(esc "$(fs_message "${FS_ERR:-missing}")")</div>"
		echo '<div class="actions"><a class="btn primary" href="/cgi-bin/files.cgi?nojs=1">Back to all disks</a></div>'
	fi
else
	cat<<-EOT
		<noscript><div class="banner warn">Folders open one page at a time because JavaScript is off.
		<a href="/cgi-bin/files.cgi?nojs=1">Open the simple file list</a>.</div></noscript>
		<div id="fb" data-root="$FS_ROOT" data-list="/cgi-bin/files_list.cgi" data-get="/cgi-bin/files_get.cgi">
		<p class="empty" id="fb-loading" role="status">Loading your files&hellip;</p></div>
		<script src="/files.js"></script>
	EOT
fi

page_end
