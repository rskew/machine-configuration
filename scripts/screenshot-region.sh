#!/usr/bin/env bash

MAXNUM=0
cd '/home/rowan/screenshots/'
for i in screenshot*.png;
    do
    NUM=$(echo $i | tr -dc '0-9');
    if [ $NUM -ge $MAXNUM ]
      then
        MAXNUM=$NUM;
    fi;
done;
NEWNUM=$(($MAXNUM+1))
import "/home/rowan/screenshots/screenshot$NEWNUM.png"
