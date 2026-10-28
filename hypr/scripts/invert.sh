#!/bin/sh
# Toggle inverted screen colors (replaces `xcalib -invert -alter` from i3).
shader="$HOME/.config/hypr/shaders/invert.frag"
current=$(hyprctl getoption decoration.screen_shader -j | jq -r '.str')
if [ "$current" = "$shader" ]; then
  hyprctl eval 'hl.config({ decoration = { screen_shader = "" } })'
else
  hyprctl eval "hl.config({ decoration = { screen_shader = \"$shader\" } })"
fi
