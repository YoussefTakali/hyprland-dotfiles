#!/usr/bin/env bash
# Import the compositor environment before starting the graphical session and portals.
set -euo pipefail
[[ -n ${WAYLAND_DISPLAY:-} && -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || {
    echo 'Run this inside your Hyprland session.' >&2; exit 1;
}
exec 9>"${XDG_RUNTIME_DIR:?}/hyprland-session-init.lock"
flock -w 10 9 || exit 1
export XDG_CURRENT_DESKTOP=Hyprland XDG_SESSION_TYPE=wayland
vars=(WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE HYPRLAND_INSTANCE_SIGNATURE)
[[ -z ${DISPLAY:-} ]] || vars+=(DISPLAY)
dbus-update-activation-environment --systemd "${vars[@]}"
# Reload unit files only when a session unit is new or changed: a reload costs ~150 ms at every login.
if [[ $(systemctl --user show -P LoadState hyprland-dotfiles-session.target 2>/dev/null) != loaded ]] \
    || systemctl --user show -P NeedDaemonReload hyprland-dotfiles-session.target swaync.service 2>/dev/null | grep -qx yes; then
    systemctl --user daemon-reload
fi
# Fedora's graphical-session.target refuses direct starts. Pull it in with our target.
systemctl --user start hyprland-dotfiles-session.target
# The startup queue uses this before launching toolkit applications, so portal
# D-Bus activation cannot race the graphical-session prerequisite.
[[ ${1:-} != --prepare-only ]] || exit 0
# Start the notification center with its systemd theme override and imported display environment.
if command -v swaync >/dev/null; then
    if ! systemctl --user start swaync.service 2>/dev/null; then
        swaync 9>&- &
    fi
fi
# D-Bus activated units may not be loaded yet. This cleanup is best-effort;
# start/restart below must still run and report any real failure.
systemctl --user reset-failed xdg-desktop-portal.service xdg-desktop-portal-hyprland.service 2>/dev/null || true
if [[ ${1:-} == --restart ]]; then
    systemctl --user restart xdg-desktop-portal-hyprland.service xdg-desktop-portal.service
else
    systemctl --user start xdg-desktop-portal-hyprland.service xdg-desktop-portal.service
fi
systemctl --user is-active graphical-session.target xdg-desktop-portal-hyprland.service xdg-desktop-portal.service pipewire.service wireplumber.service
