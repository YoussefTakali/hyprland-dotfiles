#!/bin/bash
# Outputs a unicode progress bar string

POS=$(playerctl metadata --format '{{position}}' 2>/dev/null)
LEN=$(playerctl metadata mpris:length 2>/dev/null)

if [[ -z "$POS" || -z "$LEN" || "$LEN" == "0" ]]; then
    echo "──────────────────────"
    exit 0
fi

TOTAL=22  # number of characters wide
FILLED=$(awk "BEGIN { print int(($POS / $LEN) * $TOTAL) }")
EMPTY=$((TOTAL - FILLED))

BAR=""
for ((i=0; i<FILLED; i++)); do BAR+="─"; done
BAR+="●"
for ((i=0; i<EMPTY; i++)); do BAR+="─"; done

echo "$BAR"
