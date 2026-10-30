#!/bin/sh
# Switch monitor setups (replaces the xrandr bindings from i3).
#   external: use the external monitor(s) only and turn off the laptop screen
#   all:      turn every connected monitor on
#   auto:     "external" if an external monitor is connected, else "all"
#   watch:    run "auto" now, switch to workspace 7, then run "auto" again
#             whenever an external monitor is plugged in or unplugged, or the
#             config reloads (a reload turns the laptop screen back on).
#             When that turns the laptop screen on or off, go back to the
#             workspace that was showing before, and restart waybar.  Logs
#             what it does to $log.
laptop=eDP-1
scripts=$(dirname "$0")
log=$XDG_RUNTIME_DIR/hypr/monitors-watch.log

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

# Prints the focused workspace's number (empty for a special workspace).
active_ws() {
  hyprctl activeworkspace -j | jq -r '.id // empty'
}

# After refocus: Hyprland 0.57 can still move the laptop screen to the
# workspace it showed last (or a new workspace 1) after reporting the
# switch, so check again once things have settled.  Also restart waybar,
# which doesn't survive the laptop screen turning on or off, once Hyprland's
# temporary FALLBACK monitor is gone.
settle() {
  for delay in 1 2; do
    sleep "$delay"
    active=$(active_ws)
    log "settle: on '$active', want $1"
    [ "$active" = "$1" ] || refocus "$1" "$2"
    [ "$delay" = 1 ] && "$scripts/waybar.sh"
  done
}

log() {
  echo "$(date +%T.%3N) $*" >> "$log"
}

# Milliseconds since the epoch.
now() {
  date +%s%3N
}

# Workspace $1 just got focus at time $2.  The previous one counts as
# $stable if it kept focus for at least a second.
seen_ws() {
  [ $(($2 - cur_at)) -ge 1000 ] && stable=$cur
  cur=$1
  cur_at=$2
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
    # $cur is the focused workspace, and $stable is the last one that kept
    # focus for at least a second.  Hyprland switches workspaces itself just
    # before it reports a monitor change (e.g. the external monitor takes
    # back its old workspace and the laptop screen moves to another one), so
    # a switch less than a second before a monitor event doesn't count.
    # While the laptop screen is turning on or off, $saved holds the
    # workspace to go back to and focus changes are ignored.  An empty
    # $saved means no switch is pending.
    cur=7
    cur_at=0
    stable=7
    saved=
    : > "$log"
    socat -U - "UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" |
      while IFS= read -r event; do
        case "$event" in
          # Sent once the laptop screen is on or off (from "auto" below).
          "monitoradded>>$laptop" | "monitorremoved>>$laptop")
            log "$event, saved '$saved'"
            state=on
            [ "${event%%>>*}" = monitorremoved ] && state=off
            [ -n "$saved" ] && { refocus "$saved" "$state"; settle "$saved" "$state" & }
            saved= ;;
          monitoradded\>\>* | monitorremoved\>\>* | configreloaded\>\>*)
            # Save the workspace if "auto" is about to turn the laptop
            # screen on or off.  (Hyprland would otherwise show whichever
            # workspace that screen had last.)
            [ $(($(now) - cur_at)) -ge 1000 ] && stable=$cur
            want=on
            [ "$(externals)" -gt 0 ] && want=off
            state=$(laptop_state)
            [ -z "$saved" ] && [ "$state" != "$want" ] && saved=$stable
            log "$event: laptop $state, want $want, saved '$saved'"
            "$0" auto ;;
          # workspacev2>>ID,NAME and focusedmonv2>>MONITOR,ID.  Skip special
          # workspaces (negative IDs in 0.56, "special:NAME" in 0.57).
          workspacev2\>\>[0-9]*)
            id=${event#*>>}
            [ -z "$saved" ] && seen_ws "${id%%,*}" "$(now)" ;;
          focusedmonv2\>\>*,[0-9]*)
            [ -z "$saved" ] && seen_ws "${event##*,}" "$(now)" ;;
        esac
      done
    ;;
  *)
    echo "usage: $0 external|all|auto|watch" >&2
    exit 1
    ;;
esac
