#!/bin/bash
# Restart hyprlock when track changes so album art refreshes

LAST=""
while true; do
    CURRENT=$(playerctl metadata mpris:trackid 2>/dev/null)
    if [[ "$CURRENT" != "$LAST" && -n "$LAST" ]]; then
        # Track changed — if hyprlock is running, kill and relaunch
        if pgrep -x hyprlock > /dev/null; then
            pkill hyprlock
            sleep 0.3
            hyprlock &
        fi
    fi
    LAST="$CURRENT"
    sleep 2
done
