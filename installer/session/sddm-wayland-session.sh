#!/bin/sh
# Preserve Fedora/user login profiles; skip Nix probes only for the RPM launcher.
record() {
    directory="$HOME/.local/state/session-startup"
    mkdir -p "$directory"
    read -r uptime idle < /proc/uptime
    printf '%s %s\n' "$1" "$uptime" >> "$directory/launcher.log"
}
case ${1:-} in
    --launch-rpm-hyprland)
        shift
        record profile-complete
        export HYPRLAND_LOGIN_PROFILE=1
        if [ -f "$HOME/.config/hypr/scripts/StartHyprland.py" ]; then
            exec /usr/bin/python3 "$HOME/.config/hypr/scripts/StartHyprland.py" "$@"
        fi
        exec /usr/bin/start-hyprland --no-nixgl "$@"
        ;;
    /usr/bin/start-hyprland|start-hyprland)
        shift
        record session-entry
        exec /etc/sddm/wayland-session "$0" --launch-rpm-hyprland "$@"
        ;;
    *) exec /etc/sddm/wayland-session "$@" ;;
esac
