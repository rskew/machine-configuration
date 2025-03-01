#!/usr/bin/env bash
# Use `arandr` to find a configuration and generate the script line.

#POSITION_EXT_TO_LAPPY="right-of"
POSITION_EXT_TO_LAPPY="left-of"
#POSITION_EXT_TO_LAPPY="above"

#LAPPY_RES="1920x1080"
LAPPY_RES="3840x2160"

DISPLAY_CONNECTED=$(DISPLAY=:0 xrandr | grep ' connected' | grep -v eDP-1 | cut -d " " -f1)
echo "$DISPLAY_CONNECTED"

if [ -n "$(echo $DISPLAY_CONNECTED | grep VGA-1)" ]; then
  xrandr --newmode "1680x1050_60.00"  146.25  1680 1784 1960 2240  1050 1053 1059 1089 -hsync +vsync
  xrandr --addmode VGA-1 1680x1050_60.00
  DISPLAY=:0 xrandr --output VGA-1 --auto --"$POSITION_EXT_TO_LAPPY" eDP-1 --primary --output eDP-1 --mode "$LAPPY_RES"

elif [ -n "$(echo $DISPLAY_CONNECTED | grep HDMI-1)" ]; then
  DISPLAY=:0 xrandr --output eDP-1 --rotate normal --output HDMI-1 --primary --mode  1920x1080 --rotate normal --scale 2 --output eDP-1 --mode "$LAPPY_RES" --pos 0x2160

elif [ -n "$(echo $DISPLAY_CONNECTED | grep HDMI-2)" ]; then
  DISPLAY=:0 xrandr --output eDP-1 --rotate normal --output HDMI-2 --primary --mode 1920x1080 --rotate normal --"$POSITION_EXT_TO_LAPPY" eDP-1 --ouptut eDP-1 --mode "$LAPPY_RES"

elif [ -n "$(echo $DISPLAY_CONNECTED | grep DP-2-3)" ]; then
  DISPLAY=:0 xrandr --output eDP-1 --mode 3840x2160 --pos 0x2050 --output DP-2-3 --scale 2 --primary --mode 1680x1050 --pos 0x0

elif [ -n "$(echo $DISPLAY_CONNECTED | grep DP-3-2)" ]; then
  DISPLAY=:0 xrandr --output eDP-1 --mode 3840x2160 --pos 0x2100 --output DP-3-2 --scale 2 --primary --mode 1680x1050 --pos 0x0

elif [ -n "$(echo $DISPLAY_CONNECTED | grep DP-3)" ]; then
  DISPLAY=:0 xrandr --output eDP-1 --mode 3840x2160 --pos 0x2160 --output DP-3 --scale 1 --primary --mode 3840x2160 --pos 0x0

elif [ -n "$(echo $DISPLAY_CONNECTED | grep DP-3-1)" ]; then
  DISPLAY=:0 xrandr --output eDP-1 --mode 3840x2160 --pos 0x2160 --output DP-3-1 --scale 1 --primary --mode 3840x2160 --pos 0x0

elif [ -n "$(echo $DISPLAY_CONNECTED | grep DP-3-3)" ]; then
  #DISPLAY=:0 xrandr --output eDP-1 --mode 3840x2160 --pos 0x2050 --output DP-3-3 --scale 2 --primary --mode 1680x1050 --pos 0x0
  DISPLAY=:0 xrandr --output eDP-1 --mode 3840x2160 --pos 0x1440 --output DP-3-3 --scale 2 --primary --mode 2560x1440 --pos 0x0

elif [ -n "$DISPLAY_CONNECTED" ]; then
  DISPLAY=:0 xrandr --output "$DISPLAY_CONNECTED" --"$POSITION_EXT_TO_LAPPY" eDP-1 --primary --output eDP-1 --mode "$LAPPY_RES"

else
  for DISPLAY in DP-1 DP-1-1 DP-2 DP-2-2 DP-2-3 DP-3 DP-3-1 DP-3-2 DP-3-3 DP-4 DVI-I-1-1 DVI-I-2-2 VGA-1 HDMI-1 HDMI-2
  do
    DISPLAY=:0 xrandr --output $DISPLAY --off
  done
  DISPLAY=:0 xrandr --output eDP-1 --primary --mode "$LAPPY_RES"
fi

# Reset the wallpaper
DISPLAY=:0 ~/.fehbg
DISPLAY=:0 xmonad --restart
