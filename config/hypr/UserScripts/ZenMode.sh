#!/usr/bin/env bash
# Ultimate pack - Zen mode (from Omarchy's gaps toggle, extended).
# Toggles: no gaps, no borders, no rounding, no waybar  <->  your normal theme.
flag="/tmp/hypr-zen-$USER"
if [[ -f "$flag" ]]; then
  rm -f "$flag"
  hyprctl reload >/dev/null          # restores theme values
  pgrep -x waybar >/dev/null || (waybar >/dev/null 2>&1 &)
  notify-send -u low "Zen mode off"
else
  touch "$flag"
  hyprctl --batch "keyword general:gaps_in 0; keyword general:gaps_out 0; keyword general:border_size 0; keyword decoration:rounding 0" >/dev/null
  pkill -x waybar
  notify-send -u low "Zen mode on" "SUPER+SHIFT+Backspace to exit"
fi
