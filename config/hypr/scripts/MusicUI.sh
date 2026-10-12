#!/bin/bash
# Prints one widget rendered by MusicUId.py, starting the renderer if it isn't running.
# Usage: MusicUI.sh bar|pos|len|glow_prev|glow_play|glow_next|icon_prev|icon_play|icon_next
D="${XDG_RUNTIME_DIR:-/tmp}/hyprlock-ui"
{ pid=$(<"$D/pid"); } 2>/dev/null
if [[ -z "$pid" || ! -d /proc/$pid ]]; then
    setsid -f python3 -I "$HOME/.config/hypr/scripts/MusicUId.py" </dev/null >/dev/null 2>&1
fi
if [[ -f "$D/$1" ]]; then echo "$(<"$D/$1")"; else echo " "; fi
