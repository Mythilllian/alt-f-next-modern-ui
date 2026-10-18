#!/bin/sh

source ./common.sh
check_cookie

# Based on original idea and code contributed by Dwight Hubbard, dwight.hubbard <guess> gmail.com
# Modified and adapted by Joao Cardoso
# Markup rewritten for the shared Alt-F stylesheet; the data collection is unchanged.

# live <section>: print the section inside a wrapper that the page can refresh by itself.
# The wrapper stays empty (and hidden) when the section has nothing to show.
live() {
	printf '<div class="live" id="%s" data-refresh="/cgi-bin/status.cgi?refresh=%s">' "$1" "$1"
	$1
	printf '</div>\n'
}

error_st() {
	if test -s $SERRORL; then
		cat<<-EOF
			<section class="card"><h2>Warnings</h2>
			<form action="/cgi-bin/sys_utils_proc.cgi" method="post">
			<p>The NAS has recorded these warnings. Once you have dealt with them, you can clear the list.</p>
			<ul>$(cat $SERRORL)</ul>
			<div class="actions"><button class="btn" type="submit" name="logaction" value="$SERRORL">Clear the warnings</button></div>
			</form></section>
		EOF
	fi
}

news_st() {
	if test -s $NEWSL; then
		cat<<-EOF
			<section class="card"><h2>News</h2>
			<form action="/cgi-bin/sys_utils_proc.cgi" method="post">
			<pre>$(esc "$(cat $NEWSL)")</pre>
			<div class="actions"><button class="btn" type="submit" name="logaction" value="/var/log/news.log">Mark news as read</button></div>
			</form></section>
		EOF
	fi
}

systems_st() {
	cpu="$(top -bn1 | awk '/^CPU:/ {printf "%d", 100 - $8}')"
	loadv=$(cut -f1 -d" " /proc/loadavg)
	load=$(awk '{printf "%d", 50 * $1 }' /proc/loadavg)

	mem=0; physmem=0
	swap=0; swapv="None"
	eval $(free | awk '/^Mem:/ { physmem=$2; printf "mem=%d; physmem=%d;", $3*100/physmem, physmem/1024}')
	eval $(free | awk '/^Swap:/ { if ($2 != 0) { printf "swap=%d; swapv=\"%dMB\";", $3*100/$2, $2/1024}}')
	if test "$swapv" = "None"; then
		memalert=""
		swap=100	# Trigger red alert if no swap
	else
		memalert="101 102"	# always green as long as we have swap configured
		swapv="$swap% of $swapv"
	fi
	if test $physmem -eq 0; then
		physmem="Unknown"
	else # Round up memory
		if test $physmem -le 64; then physmem="64MB"
		elif test $physmem -le 128; then physmem="128MB"
		elif test $physmem -le 256; then physmem="256MB"
		elif test $physmem -le 512; then physmem="512MB"
		elif test $physmem -le 1024; then physmem="1GB"
		fi
	fi

	eval $(awk '{ days = $1/86400; hours = $1 % 86400 / 3600; \
		printf "up=\"%d day(s) %d hour(s)\"", days, hours }' /proc/uptime)

	board=$(cat /tmp/board)

	if test "$board" = "Unknown"; then
		fan=0; fanv="Unknown"
		temp=0; tempv="Unknown"
		device="Unknown"
	else
		max_fan_speed=6000
		crit_temp=54
		if test -f /etc/sysctrl.conf; then
			. /etc/sysctrl.conf
		fi

		eval $(awk '{printf "tempt=\"%.1f\"; temp=\"%d\"", $1 / 1000, $1 / 10 / '$crit_temp'}' /tmp/sys/temp1_input)
		tempv="${tempt}°C/$(celtofar $tempt)°F"
		fanv=$(cat /tmp/sys/fan1_input)
		fan=$(expr $fanv \* 100 / $max_fan_speed)
	fi

	cat<<-EOF
		<section class="card"><h2>System</h2>
		<div class="stats">
		<div><div class="bgl">Temperature</div>$(ui_meter $temp "$tempv")</div>
		<div><div class="bgl">Fan speed</div>$(ui_meter $fan "$fanv")</div>
		<div><div class="bgl">Load</div>$(ui_meter $load "$loadv")</div>
		<div><div class="bgl">CPU</div>$(ui_meter $cpu "$cpu%")</div>
		<div><div class="bgl">Memory</div>$(ui_meter $mem "$mem% of $physmem" $memalert)</div>
		<div><div class="bgl">Swap</div>$(ui_meter $swap "$swapv")</div>
		</div>
		<dl class="facts">
		<dt>Name</dt><dd>$(esc "$(hostname -s)")</dd>
		<dt>Model</dt><dd>$(esc "$board")</dd>
		<dt>Date</dt><dd>$(esc "$(date)")</dd>
		<dt>Uptime</dt><dd>$up</dd>
		</dl></section>
	EOF
}

network_st() {
	Mode=$(cat /sys/class/net/eth0/duplex)
	MTU=$(cat /sys/class/net/eth0/mtu)

	eval $(ifconfig eth0 | awk \
			'/RX bytes/ {printf "Rx=\"%s%s\";", $3, $4} \
			/TX bytes/ {printf "Tx=\"%s%s\";", $7, $8} \
			/inet6/ { if (! match($3, "^fe80:")) ipv6=$3"; "ipv6} \
			/inet addr/{printf "IP=\"%s\";", substr($2,6)} \
			END {printf "ipv6=\"%s\"", ipv6}' | tr -d "()")

	if test -n "$ipv6"; then
		IPV6="<dt>IPv6</dt><dd>$(esc "$ipv6")</dd>"
	fi

	cat<<-EOF
		<section class="card"><h2>Network</h2>
		<dl class="facts">
		<dt>Speed</dt><dd>$(cat /sys/class/net/eth0/speed) Mbps</dd>
		<dt>Duplex</dt><dd>$(esc "$Mode")</dd>
		<dt>MTU</dt><dd>$(esc "$MTU")</dd>
		<dt>Sent</dt><dd>$(esc "$Tx")</dd>
		<dt>Received</dt><dd>$(esc "$Rx")</dd>
		<dt>IP address</dt><dd>$(esc "$IP")</dd>
		$IPV6
		</dl></section>
	EOF
}

disks_st() {
	_any=""
	for _d in /dev/sd?; do if test -b "$_d"; then _any=yes; fi; done
	if test -z "$_any"; then
		echo '<section class="card"><h2>Disks</h2><p class="empty">No disks found. Plug in a drive and refresh.</p></section>'
		return 0
	fi

	cat<<-EOF
		<section class="card"><h2>Disks</h2>
		<div class="tablewrap"><table class="stack"><thead><tr><th>Bay</th>
		<th>Device</th>
		<th>Model</th>
		<th>Capacity</th>
		<th>Power</th>
		<th>Temperature</th>
		<th>Health</th>
		</tr></thead><tbody>
	EOF

	for i in /dev/sd?; do
		dsk=$(basename $i)

		temp="--"; fam=""; mod="None"; tcap=""; pstatus="--"; health_st="--"; health_cls=""
		disk_details $dsk

		smartctl -n standby -iAH $i >& /tmp/smt_$dsk

		eval $(awk -v st=$? '
			/^194/ { printf "temp=\"%d\";", $10}
			/not support SMART|Device is in/ {
				print "health_st=\"--\";"
				if (st == 2) print "pstatus=\"standby\";"}
			/SMART overall-health/ {
				if (st == 0) cls="ok"
				else if  (st == 32) cls="warn"
				else cls="bad"
				printf "health_cls=\"%s\"; health_st=\"%s\";", cls, tolower($NF) }
			/Power mode is:/ { printf "pstatus=\"%s\";",
				tolower(substr($0, index($0,":")+2))} ' /tmp/smt_$dsk)
		rm -f /tmp/smt_$dsk

		if isnumber $temp; then
			temp="${temp}°C/$(celtofar $temp)°F"
		fi

		if test -n "$health_cls"; then
			health_html="<span class=\"pill $health_cls\">$(esc "$health_st")</span>"
		else
			health_html="$(esc "$health_st")"
		fi

		cat<<-EOF
			<tr>
			<td data-label="Bay">$(esc "$dbay")</td>
			<td data-label="Device">$(esc "$dsk")</td>
			<td data-label="Model">$(esc "$dmod")</td>
			<td data-label="Capacity">$(esc "$dcap")</td>
			<td data-label="Power" id="${dsk}_pstatus_id">$(esc "$pstatus")</td>
			<td data-label="Temperature" id="${dsk}_temp_id">$temp</td>
			<td data-label="Health" id="${dsk}_health_id">$health_html</td>
			</tr>
		EOF

	done
	echo "</tbody></table></div></section>"
}

raid_st() {
	if ! grep -q ARRAY /etc/mdadm.conf 2>/dev/null; then
		return 0
	fi

	cat<<-EOF
		<section class="card"><h2>RAID</h2>
		<div class="tablewrap"><table class="stack"><thead><tr>
		<th>Device</th>
		<th>Capacity</th>
		<th>Level</th><th>State</th>
		<th>Status</th><th>Action</th>
		<th>Done</th><th>ETA</th>
		</tr></thead><tbody>
	EOF

	for i in /dev/md[0-9]*; do
		if ! test -b $i; then continue; fi
		mdev=$(basename $i)
		state=$(cat /sys/block/$mdev/md/array_state)
		# if test "$state" = "clear"; then continue; fi

		type=$(cat /sys/block/$mdev/md/level)

		sz=""; deg=""; act=""; compl=""; exp="";
		if test "$state" != "inactive"; then
			sz=$(awk '{ printf "%.1fGB", $1/2/1024/1024}' /sys/block/$mdev/size)
			if test "$type" = "raid1" -o "$type" = "raid5"; then
				if test "$(cat /sys/block/$mdev/md/degraded)" != 0; then
					deg="<span class=\"pill bad\">degraded</span>"
				else
					deg="<span class=\"pill ok\">OK</span>"
				fi
				act=$(cat /sys/block/$mdev/md/sync_action)
				scompl=$(cat /sys/block/$mdev/md/sync_completed)
				if test "$act" != "idle"; then
					act="<span class=\"red\">$(esc "$act")</span>"
					if test "$scompl" != "delayed"; then
						pc=$(echo $scompl | awk '{printf "%d", $1 * 100 / $3}')
						compl=$(ui_meter $pc "$pc%")
						speed=$(cat /sys/block/$mdev/md/sync_speed)
						exp=$(echo $scompl | awk '{printf "%.1fmin", ($3 - $1) * 512 / 1000 / '$speed' / 60}' 2> /dev/null)
					else
						compl=$(ui_meter 0 "0%")
						exp="delayed"
					fi
				fi
			fi
		fi
		cat<<-EOF
			<tr>
			<td data-label="Device">$(esc "$mdev")</td>
			<td data-label="Capacity">$sz</td>
			<td data-label="Level">$(esc "$type")</td>
			<td data-label="State">$(esc "$state")</td>
			<td data-label="Status">$deg</td>
			<td data-label="Action">$act</td>
			<td data-label="Done">$compl</td>
			<td data-label="ETA">$exp</td>
			</tr>
		EOF
	done
	echo "</tbody></table></div></section>"
}

filesys() {
	dsk="$1"
	dev=$(basename $dsk)
	dname=$dev
	# show LV name?
	if test ${dev:0:3} = "dm-"; then
		dname=$(cat /sys/block/$dev/dm/name)
	fi

	cnt=""; dirty=""; days="";
	cap=0; free=0; perc=0

	if test -b $dsk; then
		eval $(df -h $dsk | awk '/'$dev'/{printf "cap=%s;free=%s;perc=%d", $2, $4, $5}')
		type=$(blkid -s TYPE -o value $dsk)
		lbl="$(plabel $dsk)"

		if test "$type" == "ext2" -o "$type" == "ext3" -o "$type" == "ext4"; then
			if res=$(tune2fs -l $dsk 2> /dev/null); then
				eval $(echo "$res" | awk \
					'/^Filesystem state:/ { if ($3 != "clean") printf "dirty=*;"}')
				eval $(echo "$res" | awk \
					'/^Mount count:/ {FS=":"; printf "curr_cnt=%d", $3}')
				eval $(echo "$res" | awk \
					'/^Maximum mount count:/ {FS=":"; printf "max_cnt=%d", $4}')
				eval $(echo "$res" | awk \
					'/^Next check after:/ {FS=" ";
						mth = index("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", $5) / 4 + 1;
						printf "days=\"%s-%d-%s %s\";", $8, mth, $6, $7 }')
				cnt=$(expr "$max_cnt" - "$curr_cnt")
			fi

			if test -n "$days"; then
				days=$(expr \( $(date -d "$days" +%s) - $(date +%s) \) / 86400)
				if test "$days" -lt 5 ; then
					days="<span class=\"red\">$days days</span>"
				else
					days="$days days"
				 fi
			fi

			if test -n "$cnt"; then
				if test "$cnt" -lt 5 ; then
					cnt="<span class=\"red\">$cnt mounts or</span>"
				else
					cnt="$cnt mounts or"
				fi
			fi
		fi
	fi

	MD="$(awk '$1 == "/dev/'$dev'" { n = split($4, a,",")
		for (i=1;i<=n;i++) {
			if (a[i] == "ro") {
				printf ("<span class=\"red\">%s</span>", toupper(a[i])); exit }
			else if(a[i] == "rw") {
				print toupper(a[i]); exit }
		}
	} ' /proc/mounts)"

	cat<<-EOF
		<tr>
		<td data-label="Device">$(esc "$dname")</td>
		<td data-label="Label">$(esc "$lbl")</td>
		<td data-label="Capacity" class="num">${cap}B</td>
		<td data-label="Available">$(ui_meter $perc "${free}B free")</td>
		<td data-label="Type">$(esc "$type")</td>
		<td data-label="Mode">$MD</td>
		<td data-label="Dirty"><span class="red">$dirty</span></td>
		<td data-label="Automatic check in">$cnt $days</td>
		</tr>
	EOF
}

mounted_filesystems_st() {
	if ! grep -q '^/dev/\(sd\|md\|dm-\)' /proc/mounts; then
		return 0
	fi

	cat<<-EOF
		<section class="card"><h2>Mounted filesystems</h2>
		<div class="tablewrap"><table class="stack"><thead><tr>
		<th>Device</th>
		<th>Label</th>
		<th class="num">Capacity</th><th>Available</th>
		<th>Type</th><th>Mode</th>
		<th>Dirty</th><th>Automatic check in</th>
		</tr></thead><tbody>
	EOF

	for dsk in $(cut -d" " -f1 /proc/mounts | grep '^/dev/\(sd\|md\|dm-\)' | sort -u); do
		filesys $dsk
	done

	echo "</tbody></table></div></section>"
}

mounted_remote_filesystems_st() {
	if ! grep -q '\(nfs \|cifs\)' /proc/mounts; then
		return 0
	fi

	cat<<-EOF
		<section class="card"><h2>Folders mounted from other computers</h2>
		<div class="tablewrap"><table class="stack"><thead><tr>
		<th>Host</th>
		<th>Remote share</th>
		<th>Local folder</th>
		<th class="num">Capacity</th><th>Available</th>
		<th>Type</th>
		</tr></thead><tbody>
	EOF

	while read -r rhost mnt fs rest; do
		if test "$fs" = "nfs" -o $fs = "cifs"; then
			mnt=$(path_unescape $mnt)
			if ! test -d "$mnt"; then continue; fi
			if test "$fs" = "cifs"; then
				rrhost=$(echo $rhost | cut -d'/' -f3)
				rrdir=$(echo $rhost | cut -d'/' -f4)
			else
				rrhost=${rhost%:*}
				rrdir=${rhost#*:/}
			fi
			rrhost=$(gethname "$rrhost")

			# "df" breaks lines when they are long, usernames can have spaces
			eval $(df -h "$mnt" | grep -v Filesystem | tr -d '\n' | awk '{bs=NF-4; printf "sz=%sB; avai=%sB; perc=%d", $bs, $(bs+2), $(bs+3)}')
			echo "<tr><td data-label=\"Host\">$(esc "$rrhost")</td>
				<td data-label=\"Remote share\">$(esc "$rrdir")</td>
				<td data-label=\"Local folder\">$(esc "$mnt")</td>
				<td data-label=\"Capacity\" class=\"num\">$sz</td>
				<td data-label=\"Available\">$(ui_meter $perc "$avai free")</td>
				<td data-label=\"Type\">$fs</td></tr>"
		fi
	done < /proc/mounts
	echo "</tbody></table></div></section>"
}

remotely_mounted_filesystems_st() {
	smbm="$(smbstatus -S 2> /dev/null | tail -n +4)"
	nfsm="$(showmount --no-headers --all 2> /dev/null)"

	if test -z "$smbm" -a -z "$nfsm"; then
		return 0
	fi

	cat<<-EOF
		<section class="card"><h2>Computers using your shared folders</h2>
		<div class="tablewrap"><table class="stack"><thead><tr>
		<th>Host</th>
		<th>Share</th>
		<th>Type</th>
		</tr></thead><tbody>
	EOF

	if test -n "$smbm"; then
		echo "$smbm" | awk '{
			srv = NF - 7
			pos = index($0, $(srv + 1))
			share = substr($0, 1, pos-1)
			host = $(srv+2)
			gsub(/&/, "\\&amp;", share); gsub(/</, "\\&lt;", share); gsub(/>/, "\\&gt;", share)
			gsub(/&/, "\\&amp;", host); gsub(/</, "\\&lt;", host); gsub(/>/, "\\&gt;", host)
			printf("<tr><td data-label=\"Host\">%s</td><td data-label=\"Share\">%s</td><td data-label=\"Type\">cifs</td></tr>\n", host, share)
			}' | sort -u
	fi

	if test -n "$nfsm"; then
		OIFS="$IFS"; IFS=:
		echo "$nfsm" | while read host dir; do
			host=$(gethname "$host")
			echo "<tr><td data-label=\"Host\">$(esc "$host")</td><td data-label=\"Share\">$(esc "$dir")</td><td data-label=\"Type\">nfs</td></tr>"
		done
		IFS="$OIFS"
	fi
	echo "</tbody></table></div></section>"
}

backup_st() {
	if ! test -e /var/run/backup.pid; then
		return 0
	fi

	bpid=$(cat /var/run/backup.pid)
	if ! kill -0 $bpid >& /dev/null; then
		rm /var/run/backup.pid
		return
	fi

	cat<<-EOF
		<section class="card"><h2>Backup</h2>
		<div class="tablewrap"><table class="stack"><thead><tr><th>ID</th><th>Type</th><th>Folder</th><th>State</th></tr></thead><tbody>
	EOF

	for i in /tmp/backup-state.*; do
		id=${i##*.}
		if ! grep -q "^$id;" /etc/backup.conf; then
			rm $i
			continue
		fi

		st=$(cat $i)
		bdir=$(grep ^$id /etc/backup.conf | cut -d";" -f6)
		type=$(grep ^$id /etc/backup.conf | cut -d";" -f2)
		if test "$st" = "In progress"; then
			st="<span class=\"red\">In progress</span>"
		else
			st=$(esc "$st")
		fi
		echo "<tr><td data-label=\"ID\">$(esc "$id")</td><td data-label=\"Type\">$(esc "$type")</td><td data-label=\"Folder\">$(esc "$bdir")</td><td data-label=\"State\">$st</td></tr>"
	done

	echo "</tbody></table></div></section>"
}

filesystem_maintenance_st() {
	if ! test -n "$(ls /tmp/check-* /tmp/fix-* /tmp/format-* /tmp/convert-* \
		/tmp/shrink-* /tmp/enlarg-* /tmp/wip-* 2> /dev/null)"; then
		return 0
	fi

	cat<<-EOF
		<section class="card"><h2>Disk maintenance in progress</h2>
		<div class="tablewrap"><table class="stack"><thead><tr><th>Device</th><th>Label</th><th>Operation</th></tr></thead><tbody>
	EOF

	for j in /dev/sd[a-z][1-9] /dev/md[0-9]* /dev/dm-*; do
		part=$(basename $j)
		fs_progress $part # global ln
		if test -n "$ln"; then
			cat<<-EOF
				<tr><td data-label="Device">$(esc "$part")</td><td data-label="Label">$(esc "$(plabel $part)")</td>
				<td data-label="Operation"><span class="red">$ln</span></td></tr>
			EOF
		fi
	done
	echo "</tbody></table></div></section>"
}

printers_st() {
	if ! test -f /etc/printcap -a -n "$(grep '^[^#]' /etc/printcap 2> /dev/null)"; then
		return 0
	fi

	cat<<-EOF
		<section class="card"><h2>Printers</h2>
		<div class="tablewrap"><table class="stack"><thead><tr><th>Name</th><th>Model</th><th>Jobs</th></tr></thead><tbody>
	EOF

	while read ln; do
		if test "${ln:0:1}" = "#"; then continue; fi
		jb="?"
		eval $(echo $ln | sed 's/:/|/g' | \
			awk -F '|' '{printf "pr=%s;desc=\"%s\";%s", $1, $2, $3}')
		if test -d /var/spool/lpd/$pr; then
			#host="local"
			jb=$(ls /var/spool/lpd/$pr | wc -l)
		else
			#host="remote"
			if test -f /usr/bin/lpstat; then
				jb=$(lpstat 2> /dev/null | grep ^$pr | wc -l)
			fi
		fi
		echo "<tr><td data-label=\"Name\">$(esc "$pr")</td><td data-label=\"Model\">$(esc "$desc")</td><td data-label=\"Jobs\">$jb</td></tr>"

	done < /etc/printcap
	echo "</tbody></table></div></section>"
}

if test -n "$QUERY_STRING"; then
	parse_qstring
fi

SERRORL=/var/log/systemerror.log
NEWSL=/var/log/news.log
MISCC=/etc/misc.conf

if test -s $MISCC; then
	. $MISCC
fi

apl="error_st news_st systems_st network_st disks_st raid_st mounted_filesystems_st
mounted_remote_filesystems_st remotely_mounted_filesystems_st backup_st
filesystem_maintenance_st printers_st"

if test -n "$refresh"; then
	if echo $apl | grep -qw $refresh; then
		printf 'Content-Type: text/html; charset=UTF-8\r\nCache-Control: no-store\r\n\r\n'
		$refresh
	fi
	exit 0
fi

page_start "Health" status

health_check
case "$HEALTH_LEVEL" in
	ok)   echo '<div class="banner ok">Everything looks fine.</div>' ;;
	warn) echo "<div class=\"banner warn\">$(esc "$HEALTH_MSGS" | sed 's/$/<br>/')</div>" ;;
	bad)  echo "<div class=\"banner bad\">$(esc "$HEALTH_MSGS" | sed 's/$/<br>/')</div>" ;;
esac

cat<<EOF
<h1>Health</h1>
<p class="lead">How the disks, network and the NAS itself are doing. Alt-F $(esc "$(cat /etc/Alt-F)").</p>
<noscript><p class="notice">Automatic refresh needs JavaScript. You can still reload this page yourself.</p></noscript>
<form action="" class="check"><label class="check"><input type="checkbox" id="autorefresh"> Refresh this page automatically every few seconds</label></form>
EOF

for i in $apl; do live $i; done

page_end
