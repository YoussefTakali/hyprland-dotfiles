#!/usr/bin/env bash
# SDDM login screen fixes (run once with sudo):
#   - French AZERTY keyboard on the login screen (the greeter runs on Weston, which ignores localectl's X11 layout)
#   - visible mouse cursor (NVIDIA hides Weston's hardware cursor; WESTON_FORCE_RENDERER draws it in software,
#     like cursor:no_hardware_cursors in Hyprland) using your Bibata-Modern-Ice cursor theme
#   - touchpad tap-to-click on the login screen
# Undo: sudo rm /etc/sddm.conf.d/20-login-fix.conf /etc/sddm/weston.ini
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo bash $0"; exit 1; }

USER_HOME=$(getent passwd "${SUDO_USER:-rhast}" | cut -d: -f6)
CURSOR=Bibata-Modern-Ice

# 1. Cursor theme readable by the sddm user (it can't read your home folder)
if [[ -d "$USER_HOME/.icons/$CURSOR" && ! -d "/usr/share/icons/$CURSOR" ]]; then
    cp -r "$USER_HOME/.icons/$CURSOR" /usr/share/icons/
    chown -R root:root "/usr/share/icons/$CURSOR"
    chmod -R a+rX "/usr/share/icons/$CURSOR"
    echo "Copied cursor theme to /usr/share/icons/$CURSOR"
fi

# 2. Weston config for the greeter
mkdir -p /etc/sddm
cat > /etc/sddm/weston.ini <<EOF
# Weston config for the SDDM login screen (written by sddm-login-fix.sh)
[core]
shell=kiosk

[keyboard]
keymap_layout=fr
keymap_variant=azerty

[shell]
cursor-theme=$CURSOR
cursor-size=24

[libinput]
enable-tap=true
EOF

# 3. SDDM: Wayland greeter on Weston with that config, software cursor, matching Qt cursor
cat > /etc/sddm.conf.d/20-login-fix.conf <<EOF
# Written by sddm-login-fix.sh — French keyboard + visible cursor on the login screen
[General]
DisplayServer=wayland
GreeterEnvironment=XCURSOR_THEME=$CURSOR,XCURSOR_SIZE=24,XKB_DEFAULT_LAYOUT=fr,XKB_DEFAULT_VARIANT=azerty

[Wayland]
CompositorCommand=env WESTON_FORCE_RENDERER=1 XKB_DEFAULT_LAYOUT=fr XKB_DEFAULT_VARIANT=azerty weston --shell=kiosk -c /etc/sddm/weston.ini

[Theme]
CursorTheme=$CURSOR
CursorSize=24
EOF

echo "Done. The login screen uses these settings from the next logout or reboot."
