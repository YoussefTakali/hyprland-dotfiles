#!/usr/bin/env bash
# Toggle the window layout without replacing any keybinds.
set -euo pipefail
layout=$(hyprctl -j getoption general:layout | jq -r '.str')
case "$layout" in
    master) next=dwindle ;;
    dwindle) next=master ;;
    *) exit 0 ;;
esac
out="$HOME/.config/hypr/UserConfigs/WindowLayout.conf"
tmp=$(mktemp "$out.XXXXXX")
printf 'general {\n    layout = %s\n}\n' "$next" > "$tmp"
mv "$tmp" "$out"
hyprctl reload >/dev/null
notify-send -u low 'Window layout' "$next"
