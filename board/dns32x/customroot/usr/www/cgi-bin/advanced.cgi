#!/bin/sh

source ./common.sh
check_cookie

page_start "Advanced" advanced

cat<<-EOT
	<h1>Advanced</h1>
	<p class="lead">Every Alt-F setting lives here. Most people never need this page. Pages that can change or erase things ask you to confirm first.</p>
EOT

# SSH: read-only status. The SSH settings page is linked, nothing is changed here.
ssh_port=$(awk '$6 == "/usr/sbin/dropbear" && $1 !~ /^#/ { print ($1 == "ssh_alt" ? 2222 : 22); exit }' /etc/inetd.conf 2>/dev/null)
if test -z "$ssh_port" && pidof dropbear > /dev/null 2>&1; then ssh_port=22; fi
if test -n "$ssh_port"; then
	ssh_state="<span class=\"pill ok\">On</span> Logins over SSH are accepted on port $ssh_port."
else
	ssh_state='<span class="pill">Off</span> SSH logins are not being accepted.'
fi

cat<<-EOT
	<section class="card"><h2>Remote access (SSH)</h2>
	<p>$ssh_state</p>
	<div class="actions"><a class="btn" href="$(classic_url dropbear.cgi)">SSH settings</a></div>
	</section>
	<h2>Power</h2>
	<div class="card"><p>Restart or switch off the NAS. You will be asked to confirm.</p>
	<div class="actions">
	<a class="btn" href="/cgi-bin/confirm.cgi?act=reboot">Restart the NAS</a>
	<a class="btn" href="/cgi-bin/confirm.cgi?act=poweroff">Switch off</a>
	</div></div>
	<h2>All settings</h2>
	<div class="grid">
EOT

# one card per menu of the classic Alt-F pages; the menu files are the single source
for menu in $(cat Main.men); do
	echo "<section class=\"card\"><h3>$(esc "$menu")</h3><ul>"
	cat $menu*.men | while IFS='|' read -r label url; do
		case "$url" in
			*onclick*|'#'|'') continue ;;
		esac
		if test -n "$(risk_of "$url")"; then
			href="/cgi-bin/confirm.cgi?go=$(qencode "$url")"
		else
			href=$(classic_url "$url")
		fi
		echo "<li><a href=\"$(esc "$href")\">$(esc "$label")</a></li>"
	done
	echo "</ul></section>"
done

cat<<-EOT
	</div>
	<h2>Classic view</h2>
	<div class="card"><p>The original Alt-F layout, with its menu on the left.</p>
	<div class="actions"><a class="btn" href="/cgi-bin/classic.cgi">Open the classic pages</a></div></div>
EOT

page_end
