#!/usr/bin/env bash
# Run in the real desktop terminal; restricted agent environments cannot probe GPU devices.
set -u
failed=0
check() { printf '\n%s\n' "$1"; shift; "$@" || failed=1; }
check 'GPU hardware and kernel driver' bash -c "lspci -nnk | rg -A3 -i 'vga|3d|display'"
if lspci -n 2>/dev/null | rg -q '03[0-9a-f]{2}: 10de:'; then
    check 'NVIDIA runtime (real device access)' nvidia-smi
fi
check 'Hyprland renderer and driver information' /usr/bin/hyprctl systeminfo
check 'Portal, audio, and graphical session status' systemctl --user is-active graphical-session.target xdg-desktop-portal.service xdg-desktop-portal-hyprland.service pipewire.service wireplumber.service
check 'Recent portal logs' journalctl --user -b -u xdg-desktop-portal -u xdg-desktop-portal-hyprland -n 35 --no-pager
exit "$failed"
