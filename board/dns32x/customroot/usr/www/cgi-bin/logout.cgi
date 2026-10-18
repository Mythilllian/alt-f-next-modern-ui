#!/bin/sh

source ./common.sh

rm -f /tmp/cookie /tmp/firstboot

printf 'HTTP/1.1 303\r\nContent-Type: text/html\r\nCache-Control: no-store\r\n'
sess_end
printf 'Location: /cgi-bin/login.cgi\r\n\r\n'
