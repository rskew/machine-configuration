#!/usr/bin/env sh

INTERFACE=wlp0s20f3

essid=`nmcli | awk "/$INTERFACE"': connected to/ {print $4}'`

echo $essid

exit 0
