#!/usr/bin/env bash

MAXNUM=0
cd '/home/rowan/screenshots/'
for i in screenshot*.png
    do echo $i
    NUM=$(echo $i | tr -dc '0-9')
    if [ -n "$NUM" ]
    then
        if [ "$NUM" -ge "$MAXNUM" ]
        then
            MAXNUM=$NUM;
            echo $MAXNUM
        fi
    fi
done
NEWNUM=$(($MAXNUM+1))
cd ~/
import -window root "/home/rowan/screenshots/screenshot$NEWNUM.png"
