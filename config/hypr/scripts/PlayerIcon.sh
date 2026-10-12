#!/bin/bash
# Returns path to the correct icon based on active player
ICON_DIR="$HOME/.config/hypr/assets/player_icons"
FALLBACK="$ICON_DIR/music.png"

PLAYER=$(playerctl -l 2>/dev/null | head -1 | cut -d'.' -f1 | tr '[:upper:]' '[:lower:]')

case "$PLAYER" in
    spotify)   echo "$ICON_DIR/spotify.png" ;;
    firefox)   echo "$ICON_DIR/firefox.png" ;;
    chromium)  echo "$ICON_DIR/chromium.png" ;;
    vlc)       echo "$ICON_DIR/vlc.png" ;;
    *)         echo "$FALLBACK" ;;
esac
