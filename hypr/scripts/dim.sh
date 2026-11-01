#!/bin/sh
# Slowly dim the screens as a warning before hypridle locks the session
# (like GNOME's fade before its screensaver).  Run from hypridle.conf.
#   fade [SECONDS]: dim every screen to a fifth of its brightness over
#                   SECONDS (default 30): the laptop screen with brightnessctl,
#                   external monitors with ddcutil (DDC/CI).  If it's stopped
#                   early (Ctrl+C, kill, hangup), it restores the brightness.
#   restore:        stop fading and put the brightness back
#
# $saved keeps the brightness to go back to, one "SCREEN BRIGHTNESS" line per
# screen ("laptop", or an external monitor's serial number), until it has
# been restored.  It survives logging out, and a screen with a line there
# counts as still dimmed: a new fade starts from the saved brightness rather
# than the dimmed one, and a restore that fails (say, the monitor was
# unplugged) is tried again by the next restore, including the one at login.
saved=${XDG_STATE_HOME:-$HOME/.local/state}/hypr/brightness
pid=$XDG_RUNTIME_DIR/hypr/dim.pid
steps=15

# "laptop", and the serial number of each external monitor that supports
# DDC/CI.  (`ddcutil detect --brief` lists those as "Display N" with a
# "Monitor: MFG:MODEL:SERIAL" line, and the laptop screen as "Invalid display".)
screens() {
  echo laptop
  ddcutil detect --brief |
    awk '/^[^ ]/ { valid = /^Display / } valid && /^ *Monitor:/ { n = split($0, f, ":"); print f[n] }'
}

get_brightness() {
  if [ "$1" = laptop ]; then
    brightnessctl get
  else
    # --brief prints "VCP 10 C CURRENT MAX".
    ddcutil --sn "$1" getvcp 10 --brief | cut -d' ' -f4
  fi
}

set_brightness() {
  if [ "$1" = laptop ]; then
    brightnessctl -q set "$2"
  else
    ddcutil --sn "$1" --noverify setvcp 10 "$2"
  fi
}

# Put back each saved brightness, keeping the lines that fail.
restore() {
  [ -f "$saved" ] || return
  failed=
  while read -r screen value; do
    set_brightness "$screen" "$value" </dev/null || failed="$failed$screen $value
"
  done < "$saved"
  if [ -n "$failed" ]; then
    printf %s "$failed" > "$saved"
  else
    rm -f "$saved"
  fi
}

case "$1" in
  fade)
    mkdir -p "${saved%/*}" "${pid%/*}"
    echo $$ > "$pid"
    trap 'restore; rm -f "$pid"; exit 1' INT TERM HUP
    current=$(screens)
    for screen in $current; do
      grep -q "^$screen " "$saved" 2>/dev/null && continue
      value=$(get_brightness "$screen") && [ -n "$value" ] &&
        echo "$screen $value" >> "$saved"
    done
    i=1
    while [ "$i" -le "$steps" ]; do
      for screen in $current; do
        value=$(sed -n "s/^$screen //p" "$saved")
        [ -n "$value" ] && set_brightness "$screen" $((value - value * 4 * i / (5 * steps)))
      done
      # In the background so that a signal doesn't wait for the sleep.
      sleep $((${2:-30} / steps)) &
      wait $!
      i=$((i + 1))
    done
    rm -f "$pid"
    ;;
  restore)
    # Stop a running fade, including a ddcutil it's in the middle of.
    # (Stopping it first keeps it from starting another one.)
    if [ -f "$pid" ]; then
      p=$(cat "$pid")
      kill -STOP "$p" 2>/dev/null && { pkill -P "$p"; kill -KILL "$p"; }
      rm -f "$pid"
    fi
    restore
    ;;
  *)
    echo "usage: $0 fade [SECONDS] | restore" >&2
    exit 1
    ;;
esac
