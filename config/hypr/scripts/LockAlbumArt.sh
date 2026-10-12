#!/usr/bin/env bash
# Prints a PNG path of the current track's album art for hyprlock's image reload_cmd.
# Path changes per track so hyprlock reloads it; prints a blank image when nothing plays.

DIR="$HOME/.cache/hyprlock-art"
BLANK="$DIR/blank.png"
mkdir -p "$DIR"
[[ -f "$BLANK" ]] || magick -size 1x1 xc:none "$BLANK" 2>/dev/null

URL=$(playerctl metadata mpris:artUrl 2>/dev/null)
if [[ -z "$URL" ]]; then
    echo "$BLANK"
    exit 0
fi

OUT="$DIR/$(printf '%s' "$URL" | md5sum | cut -c1-16).png"
if [[ ! -s "$OUT" ]]; then
    find "$DIR" -name '*.png' ! -name blank.png -mmin +60 -delete 2>/dev/null
    TMP="$DIR/dl.tmp"
    if [[ "$URL" == file://* ]]; then
        P="${URL#file://}"
        cp "$(printf '%b' "${P//%/\\x}")" "$TMP" 2>/dev/null   # decode %20 etc.
    else
        curl -sfL --max-time 5 "$URL" -o "$TMP"
    fi
    # Convert to real PNG (hyprlock rejects JPEGs named .png) and square-crop
    magick "$TMP" -resize 256x256^ -gravity center -extent 256x256 "$OUT" 2>/dev/null
    rm -f "$TMP"
fi

[[ -s "$OUT" ]] && echo "$OUT" || echo "$BLANK"
