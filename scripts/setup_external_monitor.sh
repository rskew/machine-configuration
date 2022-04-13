#!/usr/bin/env bash
# Automatically setup external monitor, assuming one configuration per set 
# of screens attached (e.g. one configuration for LVDA+HDMI).
# Use `arandr` to find a configuration and generate the script line.

#POSITION_EXT_TO_LAPPY="right-of"
POSITION_EXT_TO_LAPPY="above"

is_vga_connected=`DISPLAY=:0 xrandr | sed -n '/VGA-1 connected/p'`
is_dp1_connected=`DISPLAY=:0 xrandr | sed -n '/[^e]DP-1 connected/p'`
is_dp11_connected=`DISPLAY=:0 xrandr | sed -n '/DP-1-1 connected/p'`
is_dp22_connected=`DISPLAY=:0 xrandr | sed -n '/DP-2-2 connected/p'`
is_hdmi1_connected=`DISPLAY=:0 xrandr | sed -n '/HDMI-1 connected/p'`
is_hdmi2_connected=`DISPLAY=:0 xrandr | sed -n '/HDMI-2 connected/p'`
is_dvi1_connected=`DISPLAY=:0 xrandr | sed -n '/DVI-I-1-1 connected/p'`
is_dvi2_connected=`DISPLAY=:0 xrandr | sed -n '/DVI-I-2-2 connected/p'`

if [ -n "$is_vga_connected" ]; then
  xrandr --newmode "1680x1050_60.00"  146.25  1680 1784 1960 2240  1050 1053 1059 1089 -hsync +vsync
  xrandr --addmode VGA-1 1680x1050_60.00
  DISPLAY=:0 xrandr --output VGA-1 --auto --"$POSITION_EXT_TO_LAPPY" eDP-1 --primary
elif [ -n "$is_dp1_connected" ]; then
  DISPLAY=:0 xrandr --output DP-1 --auto --"$POSITION_EXT_TO_LAPPY" eDP-1 --primary
elif [ -n "$is_dp11_connected" ]; then
  DISPLAY=:0 xrandr --output DP-1-1 --auto --"$POSITION_EXT_TO_LAPPY" eDP-1 --primary
elif [ -n "$is_dp22_connected" ]; then
  DISPLAY=:0 xrandr --output DP-2-2 --auto --"$POSITION_EXT_TO_LAPPY" eDP-1 --primary
elif [ -n "$is_hdmi1_connected" ]; then
  DISPLAY=:0 xrandr --output eDP-1 --rotate normal --output HDMI-1 --primary --mode 1680x1050 --rotate normal --"$POSITION_EXT_TO_LAPPY" eDP-1
elif [ -n "$is_hdmi2_connected" ]; then
  DISPLAY=:0 xrandr --output eDP-1 --rotate normal --output HDMI-2 --primary --mode 1920x1080 --rotate normal --"$POSITION_EXT_TO_LAPPY" eDP-1
elif [ -n "$is_dvi1_connected" ]; then
  DISPLAY=:0 xrandr --output DVI-I-1-1 --auto --"$POSITION_EXT_TO_LAPPY" eDP-1 --primary --rotate normal
  DISPLAY=:0 xrandr --output DVI-I-2-2 --auto  --"$POSITION_EXT_TO_LAPPY" DVI-I-1-1 --rotate left
else
  DISPLAY=:0 xrandr --output VGA-1 --off
  DISPLAY=:0 xrandr --output DP-1 --off
  DISPLAY=:0 xrandr --output DP-1-1 --off
  DISPLAY=:0 xrandr --output DP-2-1 --off
  DISPLAY=:0 xrandr --output DP-2-2 --off
  DISPLAY=:0 xrandr --output HDMI-1 --off
  DISPLAY=:0 xrandr --output HDMI-2 --off
  DISPLAY=:0 xrandr --output DVI-I-1-1 --off
  DISPLAY=:0 xrandr --output DVI-I-2-2 --off
fi

# Reset the wallpaper
~/.fehbg
