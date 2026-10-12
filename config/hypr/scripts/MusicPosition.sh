#!/bin/bash
# Current position; while dragging the bar, shows the time you'd jump to.
PREVIEW="${XDG_RUNTIME_DIR:-/tmp}/hyprlock-scrub"
if [[ -f "$PREVIEW" ]]; then
    LEN=$(playerctl metadata mpris:length 2>/dev/null)
    awk -v f="$(<"$PREVIEW")" -v l="${LEN:-0}" 'BEGIN { s = int(f * l / 1000000); printf "%d:%02d\n", s / 60, s % 60 }'
    exit 0
fi
playerctl metadata --format '{{duration(position)}}' 2>/dev/null || echo "0:00"
