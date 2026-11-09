#!/usr/bin/env bash
# Ultimate pack - pop the active window out (from Omarchy's "omarchy-hyprland-window-pop").
# 1st press: float + resize to 60% + center + pin on top of every workspace.
# 2nd press: unpin and put it back in the tiling layout.
info=$(hyprctl activewindow -j)
[[ "$info" == "{}" ]] && exit 0
floating=$(jq -r '.floating' <<<"$info")
pinned=$(jq -r '.pinned' <<<"$info")

if [[ "$floating" == "true" && "$pinned" == "true" ]]; then
  hyprctl --batch "dispatch pin active; dispatch settiled active" >/dev/null
else
  [[ "$floating" == "true" ]] || hyprctl dispatch setfloating active >/dev/null
  hyprctl --batch "dispatch resizeactive exact 60% 60%; dispatch centerwindow; dispatch pin active" >/dev/null
fi
