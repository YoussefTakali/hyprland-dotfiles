#!/usr/bin/env bash
# Theme borders (replaces KooL's random rainbow borders; Refresh.sh still calls this file).
# Active window: a soft gradient of 3 colors from the current wallpaper's wallust palette
# (accent -> secondary -> accent), slowly rotated by the borderangle animation.
WAL="$HOME/.config/hypr/wallust/wallust-hyprland.conf"
c() { sed -n "s/^\$color$1 = rgb(\(.*\))/\1/p" "$WAL" 2>/dev/null; }
a=$(c 13); b=$(c 12); d=$(c 14)
[[ -z "$a" ]] && exit 0
hyprctl keyword general:col.active_border "rgb($a) rgb(${b:-$a}) rgb(${d:-$a}) 45deg" >/dev/null
