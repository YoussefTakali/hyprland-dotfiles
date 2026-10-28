#!/usr/bin/env bash
# Calendar + forecast popup under the Waybar clock (Quickshell). Run again to close it.
QML="$HOME/.config/quickshell/calendar/shell.qml"
pids=$(pgrep -f "[q]uickshell/calendar/shell.qml") && { kill $pids; exit 0; }
exec qs -p "$QML" >/dev/null 2>&1
