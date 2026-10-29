#!/usr/bin/env bash
# Super+Alt+M: show / hide Spotify (kept running in the "music" special workspace). Starts it if it isn't running.
win=$(hyprctl clients -j | python3 -I -c '
import json,sys
for c in json.load(sys.stdin):
    if c["class"].lower() in ("spotify", "com.spotify.client"):
        print(c["address"], c["workspace"]["name"]); break')
if [[ -z $win ]]; then
    setsid -f flatpak run com.spotify.Client >/dev/null 2>&1
    exit 0
fi
read -r addr ws <<<"$win"
if [[ $ws == special:music ]]; then
    hyprctl dispatch togglespecialworkspace music >/dev/null
else
    hyprctl dispatch focuswindow "address:$addr" >/dev/null
fi
