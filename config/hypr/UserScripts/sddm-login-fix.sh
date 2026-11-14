#!/usr/bin/env bash
# SDDM login screen fixes (run once with sudo): visible mouse cursor + your keyboard layout.
#
# v2: runs the login screen (greeter) on X11 instead of Weston. Weston's cursor stayed invisible on this
# laptop; X11 draws the cursor itself and already uses the localectl layout (fr / azerty).
# Your desktop session (Hyprland) still runs on Wayland — only the login screen changes.
#
# Undo: sudo rm /etc/sddm.conf.d/20-login-fix.conf   (back to SDDM's defaults)
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo bash $0"; exit 1; }

USER_HOME=$(getent passwd "${SUDO_USER:-$(logname 2>/dev/null)}" | cut -d: -f6)
CURSOR=Bibata-Modern-Ice

# 1. X11 greeter packages
if command -v dnf >/dev/null; then
    rpm -q sddm-x11 >/dev/null || dnf swap -y sddm-wayland-generic sddm-x11   # the two greeter packages conflict
    dnf install -y xorg-x11-server-Xorg
elif command -v pacman >/dev/null; then
    pacman -S --needed --noconfirm xorg-server
elif command -v apt-get >/dev/null; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y xserver-xorg-core xserver-xorg-input-libinput
fi

# 2. Cursor theme readable by the sddm user (it can't read your home folder)
if [[ -d "$USER_HOME/.icons/$CURSOR" && ! -d "/usr/share/icons/$CURSOR" ]]; then
    cp -r "$USER_HOME/.icons/$CURSOR" /usr/share/icons/
    chmod -R a+rX "/usr/share/icons/$CURSOR"
fi

# 3. Keyboard layout for X11: keep the system's; if none is set yet, use the console keymap (e.g. fr, de, us)
if ! localectl status | grep -q "X11 Layout"; then
    vc=$(localectl status | awk -F': ' '/VC Keymap/ {print $2}' | cut -d- -f1)
    [[ -n "$vc" && "$vc" != "n/a" ]] && localectl set-x11-keymap "$vc" || true
fi

# 4. SDDM: X11 greeter with the Bibata cursor (keeps your theme — Hypr Login Styles)
[[ -f /etc/sddm.conf.d/20-login-fix.conf ]] && cp -a /etc/sddm.conf.d/20-login-fix.conf /etc/sddm.conf.d/20-login-fix.conf.weston.bak
cat > /etc/sddm.conf.d/20-login-fix.conf <<EOF
# Written by sddm-login-fix.sh v2 — X11 login screen: visible cursor + system keyboard layout
[General]
DisplayServer=x11

[Theme]
CursorTheme=$CURSOR
CursorSize=24
EOF

echo "Done. Reboot (or log out) to see the new login screen."
echo "If it ever fails to appear: Ctrl+Alt+F3, log in, run: sudo rm /etc/sddm.conf.d/20-login-fix.conf"
