#!/bin/sh

ipaddr_wlp3s0=`ifconfig wlp3s0 | awk '/inet / {gsub(" ", "", $2); print $2}'`
#ipaddr_enp0s26u1u2=`ifconfig enp0s26u1u2 | awk '/inet / {gsub(" ", "", $2); print $2}'`

#if [ -z "$ipaddr_wlp3s0" ]
#then
#    echo $ipaddr_enp0s26u1u2
#else
#    echo $ipaddr_wlp3s0
#fi

echo $ipaddr_wlp3s0

exit 0
