#!/bin/sh
# Switch monitor setups (replaces the xrandr bindings from i3).
#   external: use the external monitor(s) only and turn off the laptop screen
#   all:      turn every connected monitor on
#   auto:     "external" if an external monitor is connected, else "all"
#   watch:    run "auto" now, switch to workspace 7, then run "auto" again
#             whenever an external monitor is plugged in or unplugged, or the
#             config reloads (a reload turns the laptop screen back on).
#             When that turns the laptop screen on or off, go back to the
#             workspace that was showing before.
laptop=eDP-1

# Monitor rules for the laptop screen, as Lua for `hyprctl eval`.
# hl.monitor() updates the output's existing rule and keeps the fields it
# isn't given, so laptop_on has to clear "disabled" explicitly.
laptop_off="hl.monitor({ output = \"$laptop\", disabled = true })"
# Same as the hl.monitor() call in hyprland.lua.
laptop_on="hl.monitor({ output = \"$laptop\", mode = \"preferred\", position = \"auto\", scale = 1, disabled = false })"

# Connected monitors other than the laptop screen (Hyprland adds a FALLBACK
# monitor while nothing is connected).
externals() {
  hyprctl monitors all -j | jq --arg l "$laptop" \
    '[.[] | select(.name != $l and .name != "FALLBACK")] | length'
}

# Prints "on" or "off".
laptop_state() {
  hyprctl monitors -j | jq -r --arg l "$laptop" \
    'if any(.[]; .name == $l) then "on" else "off" end'
}

# Show workspace $1 on the laptop screen ("on") or on the remaining screen ("off").
refocus() {
  [ "$2" = on ] && hyprctl dispatch "hl.dsp.focus({ monitor = \"$laptop\" })"
  hyprctl dispatch "hl.dsp.focus({ workspace = $1, on_current_monitor = true })"
}

case "$1" in
  external)
    if [ "$(externals)" -gt 0 ]; then
      hyprctl eval "$laptop_off"
    else
      notify-send "No external monitor connected"
    fi
    ;;
  all)
    hyprctl eval "$laptop_on"
    ;;
  auto)
    if [ "$(externals)" -gt 0 ]; then
      hyprctl eval "$laptop_off"
    else
      hyprctl eval "$laptop_on"
    fi
    ;;
  watch)
    "$0" auto
    hyprctl dispatch 'hl.dsp.focus({ workspace = 7 })'
    # $ws follows the focused workspace.  While the laptop screen is turning
    # on or off, $saved holds the workspace to go back to and $ws stops
    # following (Hyprland briefly focuses a temporary FALLBACK monitor and a
    # new empty workspace).  An empty $saved means no switch is pending.
    ws=7
    saved=
    socat -U - "UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" |
      while IFS= read -r event; do
        case "$event" in
          # Sent once the laptop screen is on or off (from "auto" below).
          "monitoradded>>$laptop")
            [ -n "$saved" ] && refocus "$saved" on
            saved= ;;
          "monitorremoved>>$laptop")
            [ -n "$saved" ] && refocus "$saved" off
            saved= ;;
          monitoradded\>\>* | monitorremoved\>\>* | configreloaded\>\>*)
            # Save the workspace if "auto" is about to turn the laptop
            # screen on or off.  (Hyprland would otherwise show whichever
            # workspace that screen had last.)
            want=on
            [ "$(externals)" -gt 0 ] && want=off
            [ -z "$saved" ] && [ "$(laptop_state)" != "$want" ] && saved=$ws
            "$0" auto ;;
          # workspacev2>>ID,NAME and focusedmonv2>>MONITOR,ID.  Skip special
          # workspaces (negative IDs).
          workspacev2\>\>[0-9]*)
            [ -z "$saved" ] && { ws=${event#*>>}; ws=${ws%%,*}; } ;;
          focusedmonv2\>\>*,[0-9]*)
            [ -z "$saved" ] && ws=${event##*,} ;;
        esac
      done
    ;;
  *)
    echo "usage: $0 external|all|auto|watch" >&2
    exit 1
    ;;
esac
