#!/usr/bin/env bash
# Prints the path of a rounded thumbnail of the current wallpaper for fastfetch's logo.
# Rebuilt only when the wallpaper changes, so terminal startup stays fast.
SRC="$HOME/.config/hypr/wallpaper_effects/.wallpaper_current"
OUT="$HOME/.cache/fastfetch/wall-logo.png"
if [[ -f "$SRC" && ( ! -f "$OUT" || "$SRC" -nt "$OUT" ) ]]; then
    mkdir -p "${OUT%/*}"
    magick "$SRC" -resize 520x520^ -gravity center -extent 520x520 \
        \( -size 520x520 xc:none -fill white -draw "roundrectangle 0,0 519,519 70,70" \) \
        -alpha set -compose DstIn -composite "$OUT.tmp.png" 2>/dev/null && mv "$OUT.tmp.png" "$OUT"
fi
[[ -f "$OUT" ]] && echo "$OUT"
