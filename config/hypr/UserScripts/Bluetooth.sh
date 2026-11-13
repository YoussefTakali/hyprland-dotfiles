#!/usr/bin/env bash
# Fedora Blueman UI with scoped, source-checked service-menu fixes.
set -euo pipefail
logs="$HOME/.local/state/bluetooth-menu"
mkdir -p "$logs"
if [[ ${1:-} == --restart-ui ]]; then
    timeout 3s gapplication action org.blueman.Manager Quit 2>/dev/null || true
    for ((i=0; i<30; i++)); do
        pgrep -x blueman-manager >/dev/null || break
        sleep 0.1
    done
    if pgrep -x blueman-manager >/dev/null; then
        echo 'Bluetooth window did not close. Close it with Ctrl+Q, then reopen from Waybar.' >&2
        exit 1
    fi
fi
if ! command -v blueman-manager >/dev/null; then
    notify-send -u critical Bluetooth 'Install the blueman and bluez packages for your distribution.'
    exit 1
fi
# Close obsolete custom windows without touching the radio or its pairing records.
gapplication action local.dotfiles.Bluetooth Quit 2>/dev/null || true
gapplication action local.dotfiles.BluetoothControl Quit 2>/dev/null || true
if ! pgrep -x blueman-applet >/dev/null; then
    nohup blueman-applet >>"$logs/applet.log" 2>&1 </dev/null &
fi
fixes="$HOME/.config/hypr/UserScripts/BluemanFixes.py"
if [[ -f $fixes ]]; then
    exec /usr/bin/python3 "$fixes" --loglevel info >>"$logs/blueman.log" 2>&1
fi
exec blueman-manager --loglevel info >>"$logs/blueman.log" 2>&1
