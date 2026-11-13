#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# Scripts for refreshing ags, waybar, rofi, swaync, wallust

SCRIPTSDIR=$HOME/.config/hypr/scripts
UserScripts=$HOME/.config/hypr/UserScripts

# Define file_exists function
file_exists() {
  if [ -e "$1" ]; then
    return 0 # File exists
  else
    return 1 # File does not exist
  fi
}

# quit ags & relaunch ags
#ags -q && ags &

# quit quickshell & relaunch quickshell
# (2026-10-28) only the KooL overview: `pkill qs` also killed the volume/brightness OSD, the calendar popup and
# could kill the lock screen; and the bare `qs` it relaunched has no config here, so the overview stayed dead.
if pgrep -u "$(id -u)" -f "[q]s -c overview" >/dev/null; then
  pkill -u "$(id -u)" -f "[q]s -c overview"
  setsid -f qs -c overview >/dev/null 2>&1
fi
pgrep -f "[q]uickshell/osd/shell.qml" >/dev/null || setsid -f qs -p "$HOME/.config/quickshell/osd/shell.qml" >/dev/null 2>&1

# Reload the current bar and notifications using their selected settings.
bash "$SCRIPTSDIR/WaybarMode.sh" --refresh
swaync-client --reload-config

# Relaunching rainbow borders if the script exists
sleep 1
if file_exists "${UserScripts}/RainbowBorders.sh"; then
  ${UserScripts}/RainbowBorders.sh &
fi

exit 0
