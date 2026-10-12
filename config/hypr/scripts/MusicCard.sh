#!/usr/bin/env bash
# Background of the hyprlock music card, as an image (hyprlock's image reload_cmd runs this and loads
# whatever path it prints). Modern "glass" card: the current album art, heavily blurred and darkened,
# rounded 28px, thin light border, plus the play-button circle. Rebuilt only when the track art or the
# wallust colors change. Prints a blank image when no media player is open, so the card disappears.
# Geometry matches hyprlock.conf: 720x170 card, play circle r=30 at +255 from center (x=615, y=85).
DIR="$HOME/.cache/hyprlock-art"
BLANK="$DIR/blank.png"
WAL="$HOME/.config/hypr/wallust/wallust-hyprland.conf"
W=720 H=170 R=28
mkdir -p "$DIR"
[[ -f "$BLANK" ]] || magick -size 1x1 xc:none "$BLANK"

if [[ -z "$(playerctl -l 2>/dev/null)" ]]; then
    ln -sfn "$BLANK" "$DIR/current.png"; echo "$BLANK"; exit 0
fi

ART=$("$HOME/.config/hypr/scripts/LockAlbumArt.sh")
[[ "$ART" == "$BLANK" ]] && ART=""
key=$( { echo "$ART"; stat -c %Y "$WAL" 2>/dev/null; echo v4; } | md5sum | cut -c1-12)
CARD="$DIR/card-$key.png"

if [[ ! -s "$CARD" ]]; then
    find "$DIR" -name 'card-*.png' -mmin +60 -delete 2>/dev/null
    RING="#$(sed -n 's/^\$color13 = rgb(\(.*\))/\1/p' "$WAL" 2>/dev/null)"
    [[ "$RING" == "#" ]] && RING="#AF5CE5"
    # Neutral glass (same look as the rest of the lock screen) + a soft glow of the album's main
    # color that fades out from behind the artwork, so the card hints at the track without shouting
    GLOW=""
    if [[ -n "$ART" ]]; then
        GLOW=$(magick "$ART" -resize 1x1\! -modulate 100,140 -format '%[hex:p{0,0}]' info: 2>/dev/null | cut -c1-6)
    fi
    BG=(-size "${W}x${H}" xc:"rgba(255,255,255,0.07)")
    if [[ -n "$GLOW" ]]; then
        BG+=(\( -size "${H}x$((W*6/10))" gradient:"#${GLOW}55-#${GLOW}00" -rotate -90 -gravity west -background none -extent "${W}x${H}" \) -compose Over -composite)
    fi
    magick "${BG[@]}" \
        \( -size "${W}x${H}" xc:none -fill white -draw "roundrectangle 0,0 $((W-1)),$((H-1)) $R,$R" \) \
        -alpha set -compose DstIn -composite -compose Over \
        -fill none -stroke "rgba(255,255,255,0.14)" -strokewidth 1 \
        -draw "roundrectangle 0.5,0.5 $((W-1)).5,$((H-1)).5 $R,$R" \
        -fill "rgba(255,255,255,0.92)" -stroke none \
        -draw "circle 615,85 615,57" \
        "$CARD.tmp.png" && mv "$CARD.tmp.png" "$CARD"
fi

# current.png is what hyprlock loads at startup (lock scripts run this first)
ln -sfn "$CARD" "$DIR/current.png"
echo "$CARD"
