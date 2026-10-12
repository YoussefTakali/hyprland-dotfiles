#!/usr/bin/env bash
# Pick a color anywhere on screen; the hex code goes to the clipboard.
color=$(hyprpicker -a -f hex 2>/dev/null) || exit 0
[[ -z "$color" ]] && exit 0
img="${XDG_RUNTIME_DIR:-/tmp}/picked-color.png"
magick -size 64x64 "xc:$color" "$img" 2>/dev/null || convert -size 64x64 "xc:$color" "$img" 2>/dev/null
notify-send -a "Color picker" -i "$img" "$color" "Copied to clipboard"
