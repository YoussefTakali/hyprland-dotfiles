#!/usr/bin/env bash
# Power menu: Quickshell (~/.config/quickshell/power). Run again to close it. Falls back to wlogout.
QML="$HOME/.config/quickshell/power/shell.qml"
if pid=$(pgrep -f "qs -p $QML"); then kill $pid; exit 0; fi
if command -v qs >/dev/null && [[ -f $QML ]]; then
    exec qs -p "$QML" >/dev/null 2>&1
fi
pgrep -x wlogout >/dev/null && { pkill -x wlogout; exit 0; }
exec wlogout --protocol layer-shell -b 5 -T 200 -B 200
