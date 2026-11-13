#!/usr/bin/env bash
# Select a persistent animation override or inherit the desktop theme's preset.
set -euo pipefail
root="$HOME/.config/hypr"
out="$root/UserConfigs/AnimationOverride.conf"
choice=${1:-}
if [[ -z "$choice" ]]; then
    choice=$({
        printf '%s\n' 'Follow desktop theme'
        find -L "$root/animations" -maxdepth 1 -type f -name '*.conf' -printf '%f
' | sed 's/.conf$//' | sort -V
    } | rofi -i -dmenu -no-custom -config "$HOME/.config/rofi/config-Animations.rasi" -p 'Animations') || exit 0
fi
[[ -n "$choice" ]] || exit 0

if [[ "$choice" == 'Follow desktop theme' ]]; then
    line='source = $HOME/.config/hypr/UserConfigs/Ultimate/Animations.conf'
elif [[ "$choice" != */* && -f "$root/animations/$choice.conf" ]]; then
    printf -v line 'source = $HOME/.config/hypr/animations/%s.conf' "$choice"
else
    exit 1
fi
tmp=$(mktemp "$out.XXXXXX")
printf '%s\n' "$line" >"$tmp"
mv "$tmp" "$out"
hyprctl reload >/dev/null
notify-send -u low 'Animations' "$choice"
