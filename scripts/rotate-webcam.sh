#! /usr/bin/env bash
# Run this stream transformation to make a virtual video device
# '/dev/video22' available with the rotated webcam feed.
#
# Copied from:
# https://askubuntu.com/a/1103255

# You may need to enable the v4l2loopback kernel module:
# $ sudo modprobe v4l2loopback video_nr=22 exclusive_caps=1 card_label='Rotated Logitech c930e'  --first-time

# This runs the rotation transformation from the raw webcam device
# (assumed to be '/dev/video2') to the virtual device.
# Rotates 270 degrees clockwise.
ffmpeg -f v4l2 -i /dev/video2 -vf "transpose=3,format=yuv420p" -f v4l2 /dev/video22

# If this doesn't work, check the available devices with:
# $ v4l2-ctl --list-devices
