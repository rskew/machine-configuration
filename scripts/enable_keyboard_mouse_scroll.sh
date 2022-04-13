#! /usr/bin/env bash

# Enable middle-button scrolling from bluetooth keyboard mouse.
# Every time it reconnects it presents a new device id in `input list`, so just set it
# for all the entries with the right name (which `xinput set-prop` doesn't support).
for id in $(xinput list | grep "TEX-BLE-KB-1 Mouse" |  grep pointer | cut -d "=" -f 2 | cut -f 1); 
do  
    xinput set-prop $id "libinput Scroll Method Enabled" 0, 0, 1
done

# At the moment I also manually run this to apply the keymap for tex bt kb
# xkbcomp /etc/nixos/keymap.xkb $DISPLAY
