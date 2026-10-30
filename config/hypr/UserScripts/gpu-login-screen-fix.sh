#!/usr/bin/env bash
# Hybrid laptops: keep the login screen's X server (SDDM) on the integrated GPU only. Otherwise it attaches the
# NVIDIA/AMD GPU as a secondary GPU and holds it open for the whole session, so that GPU never sleeps (~15-20 W).
# Takes effect the next time the login screen starts (log out, or reboot). Run with sudo.
# Undo: sudo rm /etc/X11/xorg.conf.d/20-login-screen-igpu.conf
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo bash $0"; exit 1; }
F=/etc/X11/xorg.conf.d/20-login-screen-igpu.conf
mkdir -p /etc/X11/xorg.conf.d
cat > "$F" <<'CONF'
# Written by gpu-login-screen-fix.sh: the X server (login screen) uses only the GPU that drives the screen,
# so the discrete GPU of a hybrid laptop can power down after login.
Section "ServerFlags"
    Option "AutoAddGPU" "false"
EndSection
CONF
echo "Done: $F"
echo "Log out and back in (or reboot); the discrete GPU can then sleep while you work."
