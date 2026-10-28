#!/usr/bin/env bash
# Show the volume / brightness / mic OSD (~/.config/quickshell/osd). Exits non-zero if the OSD isn't running,
# so callers can fall back to a notification:   Osd.sh volume 45 || notify-send ...
#   Osd.sh <volume|brightness|mic> <value> [muted]
kind=$1 value=${2:-0} muted=false
[[ ${3:-} == muted ]] && muted=true
value=${value%%%}; value=${value%%.*}; [[ $value =~ ^[0-9]+$ ]] || value=0
qs ipc --path "$HOME/.config/quickshell/osd/shell.qml" call osd popup "$kind" "$value" "$muted" >/dev/null 2>&1
