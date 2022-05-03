#!/usr/bin/env bash
# Use `arandr` to find a configuration and generate the script line.

#POSITION_EXT_TO_LAPPY="right-of"
POSITION_EXT_TO_LAPPY="above"

#LAPPY_RES="1920x1080"
LAPPY_RES="3840x2160"

DISPLAY_CONNECTED=$(DISPLAY=:0 xrandr | grep connected | grep -v disconnected | grep -v eDP-1 | cut -d " " -f1)
echo "$DISPLAY_CONNECTED"

if [ -n "$(echo $DISPLAY_CONNECTED | grep VGA-1)" ]; then
  xrandr --newmode "1680x1050_60.00"  146.25  1680 1784 1960 2240  1050 1053 1059 1089 -hsync +vsync
  xrandr --addmode VGA-1 1680x1050_60.00
  DISPLAY=:0 xrandr --output VGA-1 --auto --"$POSITION_EXT_TO_LAPPY" eDP-1 --primary --output eDP-1 --mode "$LAPPY_RES"

elif [ -n "$(echo $DISPLAY_CONNECTED | grep HDMI-1)" ]; then
  DISPLAY=:0 xrandr --output eDP-1 --rotate normal --output HDMI-1 --primary --mode 1680x1050 --rotate normal --"$POSITION_EXT_TO_LAPPY" eDP-1 --output eDP-1 --mode "$LAPPY_RES"

elif [ -n "$(echo $DISPLAY_CONNECTED | grep HDMI-2)" ]; then
  DISPLAY=:0 xrandr --output eDP-1 --rotate normal --output HDMI-2 --primary --mode 1920x1080 --rotate normal --"$POSITION_EXT_TO_LAPPY" eDP-1 --ouptut eDP-1 --mode "$LAPPY_RES"

elif [ -n "$(echo $DISPLAY_CONNECTED | grep DP-2-3)" ]; then
  DISPLAY=:0 xrandr \
      --output eDP-1 --mode "$LAPPY_RES" --pos 0x2100 \
      --output "$DISPLAY_CONNECTED" --primary --scale 2 --pos 0x0 --auto

elif [ -n "$DISPLAY_CONNECTED" ]; then
  DISPLAY=:0 xrandr --output "$DISPLAY_CONNECTED" --auto --"$POSITION_EXT_TO_LAPPY" eDP-1 --primary --output eDP-1 --mode "$LAPPY_RES"

else
  for DISPLAY in DP-1 DP-1-1 DP-2-2 DP-2-3 DVI-I-1-1 DVI-I-2-2 VGA-1 HDMI-1 HDMI-2
  do
    DISPLAY=:0 xrandr --output $DISPLAY --off
  done
  DISPLAY=:0 xrandr --output eDP-1 --primary --mode "$LAPPY_RES"
fi

# Reset the wallpaper
DISPLAY=:0 ~/.fehbg
xmonad --restart
