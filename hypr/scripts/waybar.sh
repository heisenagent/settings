#!/bin/sh
# (Re)start waybar.  Also starts it if it crashed.
#
# Waybar runs its custom-module scripts through `sh -c` and leaves them
# running when it's killed, so stop those too, or every restart leaves
# another set of media scripts (and their playerctl/mediaplayer.py) behind.
pkill -x waybar
while pgrep -x waybar >/dev/null; do sleep 0.1; done
pkill -f '\.config/waybar/scripts/'
pkill -xf 'playerctl --follow status'
pkill -f '/usr/share/waybar/custom_modules/mediaplayer\.py'
hyprctl dispatch 'hl.dsp.exec_cmd("waybar")' >/dev/null
