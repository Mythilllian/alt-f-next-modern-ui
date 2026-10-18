#!/bin/sh
# A gentle "are you sure?" step before risky pages and actions. Works without JavaScript.
#   confirm.cgi?go=<page>   continue to a settings page
#   confirm.cgi?act=reboot|poweroff

source ./common.sh
check_cookie

act=$(qparam act)
go=$(httpd -d "$(qparam go)")

case "$act" in
	reboot)
		title="Restart the NAS?"
		text="The NAS will restart now. Your files will not be available for about a minute, and anything being copied right now will stop."
		value=Reboot; yes="Yes, restart" ;;
	poweroff)
		title="Switch off the NAS?"
		text="The NAS will switch off. To use it again you will need to press its power button."
		value=Poweroff; yes="Yes, switch off" ;;
	*)
		# a settings page: must be a real page in this folder, nothing else
		case "$go" in
			''|*[!-A-Za-z0-9_.?=\&%/]*|*..*|/*) go="" ;;
		esac
		if test -z "$go" -o ! -f "./${go%%\?*}"; then
			page_error "That page could not be found." "" advanced
		fi
		case "$(risk_of "$go")" in
			disk) title="Careful: this page can change your disks"
				text="Partitioning, formatting and RAID changes can erase what is stored on your disks. Only continue if you know what you are doing and your important files are backed up." ;;
			network) title="Careful: this changes how the NAS connects"
				text="A wrong network setting can make the NAS impossible to reach from this page. If that happens you may need to find its new address or reset it." ;;
			firmware) title="Careful: this replaces the NAS software"
				text="Do not switch the NAS off or unplug it while it installs. Make sure you have the right firmware file for your model." ;;
			settings) title="Careful: this can undo your changes"
				text="Loading or restoring settings replaces the ones the NAS uses now." ;;
			*) gotopage "$(classic_url "$go")" ;;
		esac
		yes="Yes, I know what I'm doing" ;;
esac

page_start "Before you continue" advanced
echo "<div class=\"card login\"><h1>$title</h1><p>$text</p><div class=\"actions\">"
if test -n "$act"; then
	cat<<-EOT
		<form method="post" action="/cgi-bin/sys_utils_proc.cgi"><input type="hidden" name="action" value="$value">
		<button class="btn danger" type="submit">$yes</button></form>
	EOT
else
	echo "<a class=\"btn danger\" href=\"$(classic_url "$go")\">$yes</a>"
fi
echo '<a class="btn primary" href="/cgi-bin/advanced.cgi">Go back</a></div></div>'
page_end
