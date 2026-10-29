#!/usr/bin/env bash
# Super+Q: close the active window — except Spotify, which is hidden in the "music" special workspace so the music
# keeps playing. Super+Alt+M (SpotifyToggle.sh) brings it back.
class=$(hyprctl activewindow -j | python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("class",""))' 2>/dev/null)
case "${class,,}" in
    spotify|com.spotify.client) hyprctl dispatch movetoworkspacesilent special:music >/dev/null ;;
    *) hyprctl dispatch killactive >/dev/null ;;
esac
