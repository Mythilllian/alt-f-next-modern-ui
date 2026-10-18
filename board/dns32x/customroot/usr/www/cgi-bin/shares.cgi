#!/bin/sh

source ./common.sh
check_cookie

page_start "Shared folders" shares

nas=$(hostname -s)

cat<<-EOT
	<h1>Shared folders</h1>
	<p class="lead">These folders can be opened from other computers, phones and TVs on your home network.</p>
EOT

list=$(shares_tsv)
if test -z "$list"; then
	cat<<-EOT
		<div class="card empty"><p>No shared folders yet.</p>
		<p class="hint">Whoever looks after the NAS can add them under Advanced.</p></div>
	EOT
else
	echo '<div class="grid wide">'
	echo "$list" | while IFS="	" read -r name path; do
		cat<<-EOT
			<section class="card"><h2>$(esc "$name")</h2>
			<dl class="facts">
			<dt>Where it is</dt><dd>$(esc "$path")</dd>
			<dt>On Windows</dt><dd>\\\\$(esc "$nas")\\$(esc "$name")</dd>
			<dt>On Mac or Linux</dt><dd>smb://$(esc "$nas")/$(esc "$name")</dd>
			</dl></section>
		EOT
	done
	echo '</div>'
fi

echo "<p class=\"hint\">To add, remove or change who can use a shared folder, open <a href=\"$(classic_url smb.cgi)\">the Samba settings</a>.</p>"

page_end
