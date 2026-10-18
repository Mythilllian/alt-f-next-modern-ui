#!/bin/sh
# The original Alt-F pages live in a frameset (menu on the left, page on the right).
# classic.cgi?p=/cgi-bin/<page> builds that frameset around any one page.

source ./common.sh

p=$(httpd -d "$(qparam p)")
# only a page of this NAS, no ".." and nothing that could break out of the attribute
case "$p" in
	/cgi-bin/classic.cgi*|/cgi-bin/login*|/cgi-bin/logout*) p=/cgi-bin/about.cgi ;;
	/cgi-bin/*[!-A-Za-z0-9_./?=\&%:+~,@]*|*..*) p=/cgi-bin/about.cgi ;;
	/cgi-bin/*) ;;
	*) p=/cgi-bin/about.cgi ;;
esac

printf 'Content-Type: text/html; charset=UTF-8\r\nCache-Control: no-store\r\n\r\n'
cat<<-EOT
	<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Frameset//EN" "http://www.w3.org/TR/html4/frameset.dtd">
	<html><head profile="http://www.w3.org/2005/10/profile">
	<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
	<link rel="icon" type="image/png" href="/dns-323.png">
	<title>Alt-F classic pages</title>
	</head>
	<frameset id="altf" name="altf" cols="15%,*" frameborder="no" border="0">
	<frame id="nav" name="nav" src="/cgi-bin/index.cgi">
	<frame id="content" name="content" src="$(esc "$p")">
	<noframes><body><p>These pages need frames. <a href="$(esc "$p")">Open the page on its own</a>.</p></body></noframes>
	</frameset>
	</html>
EOT
