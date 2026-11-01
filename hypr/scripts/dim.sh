#!/bin/sh
# Slowly dim the screens as a warning before hypridle locks the session
# (like GNOME's fade before its screensaver).  Run from hypridle.conf.
#   fade [SECONDS]: dim every screen to a fifth of its brightness over
#                   SECONDS (default 30): the laptop screen with brightnessctl,
#                   external monitors with ddcutil (DDC/CI)
#   restore:        stop fading and put the brightness back
dir=$XDG_RUNTIME_DIR/hypr/dim
steps=15

case "$1" in
  fade)
    mkdir -p "$dir"
    echo $$ > "$dir/pid"
    # One "SCREEN BRIGHTNESS" line per screen: "laptop" or a ddcutil display number.
    echo "laptop $(brightnessctl get)" > "$dir/saved"
    for d in $(ddcutil detect --brief | sed -n 's/^Display //p'); do
      # --brief prints "VCP 10 C CURRENT MAX".
      echo "$d $(ddcutil --display "$d" getvcp 10 --brief | cut -d' ' -f4)" >> "$dir/saved"
    done
    i=1
    while [ "$i" -le "$steps" ]; do
      while read -r screen value; do
        value=$((value - value * 4 * i / (5 * steps)))
        if [ "$screen" = laptop ]; then
          brightnessctl -q set "$value"
        else
          ddcutil --display "$screen" --noverify setvcp 10 "$value"
        fi
      done < "$dir/saved"
      sleep $((${2:-30} / steps))
      i=$((i + 1))
    done
    rm -f "$dir/pid"
    ;;
  restore)
    # Stop the fade, including a ddcutil it's in the middle of.  (Stopping
    # it first keeps it from starting another one.)
    if [ -f "$dir/pid" ]; then
      pid=$(cat "$dir/pid")
      kill -STOP "$pid" 2>/dev/null && { pkill -P "$pid"; kill -KILL "$pid"; }
    fi
    if [ -f "$dir/saved" ]; then
      while read -r screen value; do
        if [ "$screen" = laptop ]; then
          brightnessctl -q set "$value"
        else
          ddcutil --display "$screen" --noverify setvcp 10 "$value"
        fi
      done < "$dir/saved"
    fi
    rm -f "$dir/pid" "$dir/saved"
    ;;
  *)
    echo "usage: $0 fade [SECONDS] | restore" >&2
    exit 1
    ;;
esac
