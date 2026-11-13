#!/usr/bin/env bash
# Fedora 45 desktop/login repair. Run as your normal user.
# --user-only reapplies portable GPU defaults without changing the login manager.
# System setup keeps the current session running; SDDM takes over at the next boot.
set -euo pipefail
SELF=$(readlink -f "$0")
MODE=${1:-all}
export REPAIR_REPO="$(cd "$(dirname "$SELF")/../.." && pwd)"

if [[ "$MODE" == --system ]]; then
    [[ $EUID == 0 ]] || { echo 'Administrator access required.' >&2; exit 1; }
    LOGIN_USER=${2:?Missing account name}
    ACCOUNT_HOME=$(getent passwd "$LOGIN_USER" | cut -d: -f6)
    [[ -n "$ACCOUNT_HOME" && "$LOGIN_USER" != root ]] || exit 1
    THEME_SOURCE="$ACCOUNT_HOME/.cache/sddm-astronaut-repair"
    [[ -f "$THEME_SOURCE/Themes/jake_the_dog.conf" ]] || { echo 'Run this script as your normal user first.' >&2; exit 1; }
    dnf install -y --allowerasing sddm-x11 xorg-x11-server-Xorg qt6-qtdeclarative qt6-qtsvg qt6-qtvirtualkeyboard qt6-qtmultimedia
    python3 "$REPAIR_REPO/installer/install-session.py"
    BACKUP="/var/backups/desktop-login-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP" /etc/sddm.conf.d /usr/share/sddm/themes /var/lib/sddm
    for item in /etc/sddm.conf /etc/sddm.conf.d /var/lib/sddm/state.conf; do
        [[ ! -e "$item" ]] || cp -a --parents "$item" "$BACKUP/"
    done
    THEME=/usr/share/sddm/themes/sddm-astronaut-theme
    [[ ! -e "$THEME" ]] || mv "$THEME" "$BACKUP/theme"
    mkdir -p "$THEME"
    tar -C "$THEME_SOURCE" --exclude=.git --exclude=Previews -cf - . | tar -C "$THEME" -xf -
    chown -R root:root "$THEME"
    chmod -R a+rX "$THEME"
    sed -i 's|^ConfigFile=.*|ConfigFile=Themes/jake_the_dog.conf|' "$THEME/metadata.desktop"
    mkdir -p /usr/local/share/fonts/sddm-astronaut
    cp -a "$THEME/Fonts/." /usr/local/share/fonts/sddm-astronaut/
    fc-cache -f
    # /etc/sddm.conf has higher priority than conf.d. Update it without discarding other settings.
    python3 - <<'PY'
import configparser
from pathlib import Path
p = Path('/etc/sddm.conf')
c = configparser.ConfigParser(interpolation=None, strict=False)
c.optionxform = str
if p.exists(): c.read(p)
# Keep a separately validated Hyprland greeter when reinstalling the theme.
server = 'x11'
if c.get('General', 'DisplayServer', fallback='') == 'wayland' and c.get('Wayland', 'CompositorCommand', fallback='').endswith('--config /etc/sddm/hyprland-greeter.lua'):
    server = 'wayland'
for section, values in {
    'General': {'DisplayServer': server, 'InputMethod': 'qtvirtualkeyboard'},
    'Theme': {'Current': 'sddm-astronaut-theme', 'CursorTheme': 'Adwaita', 'CursorSize': '24'},
}.items():
    if not c.has_section(section): c.add_section(section)
    for key, value in values.items(): c.set(section, key, value)
with p.open('w') as f: c.write(f, space_around_delimiters=False)
PY
    cat > /etc/sddm.conf.d/99-desktop-login.conf <<'CONF'
[General]
DisplayServer=x11
InputMethod=qtvirtualkeyboard
[Theme]
Current=sddm-astronaut-theme
CursorTheme=Adwaita
CursorSize=24
CONF
    printf '[Last]\nUser=%s\nSession=/usr/share/wayland-sessions/hyprland-dotfiles.desktop\n' "$LOGIN_USER" > /var/lib/sddm/state.conf
    chown sddm:sddm /var/lib/sddm/state.conf
    restorecon -RF "$THEME" /etc/sddm.conf /etc/sddm.conf.d /var/lib/sddm/state.conf
    python3 "$REPAIR_REPO/installer/session/repair-greeter-handoff.py" --fix-locale
    python3 "$REPAIR_REPO/installer/session/repair-greeter-handoff.py" --jake-backdrop
    python3 "$ACCOUNT_HOME/.config/hypr/scripts/LoginThemes.py" --system-install --assets "$ACCOUNT_HOME/.local/share/hypr-login-themes"
    # Deliberately no --now: replacing the running manager would close the desktop.
    systemctl disable gdm.service 2>/dev/null || true
    systemctl enable --force sddm.service
    echo "SDDM Jake theme installed. Backup: $BACKUP"
    echo 'SDDM will be used on the next boot. Current desktop was kept running.'
    exit 0
fi

[[ $EUID != 0 ]] || { echo "Run as your normal user: bash $SELF" >&2; exit 1; }
[[ "$MODE" == all || "$MODE" == --user-only ]] || { echo "Usage: $SELF [--user-only]"; exit 1; }
python3 - <<'PY'
from pathlib import Path
import datetime, shutil, subprocess
h = Path.home()
b = h / '.local/state/desktop-login-backups' / datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
def backup(p):
    if p.exists():
        dest = b / p.relative_to(h)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(p, dest)

# Remove only the old repair's machine-specific managed block and preserve
# everything the user may have added after it.
p = h / '.config/uwsm/env-hyprland'
if p.exists():
    old = p.read_text()
    marker = '# BEGIN desktop-login-repair\n'
    lines = [marker,
        'export AQ_DRM_DEVICES="$(readlink -f /dev/dri/by-path/pci-0000:01:00.0-card)"\n',
        'export GBM_BACKEND=nvidia-drm\n',
        'export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json\n',
        'export __GLX_VENDOR_LIBRARY_NAME=nvidia\n']
    block = ''.join(lines)
    # An earlier version used a different comment for the same exact exports.
    earlier = '# NVIDIA startup repair: set these before the compositor loads EGL.\n' + ''.join(lines[1:])
    cleaned = old.replace(block, '', 1).replace(earlier, '', 1)
    if cleaned != old:
        backup(p)
        p.write_text(cleaned)

# GPU.conf is derived from the actual display-connected GPU. Never write an
# NVIDIA PCI address or force its libraries on a different computer.
script = h / '.config/hypr/scripts/GpuConfig.sh'
if script.exists():
    gpu = h / '.config/hypr/UserConfigs/GPU.conf'
    backup(gpu)
    subprocess.run(['bash', str(script)], check=True)
print('GPU settings detected for this computer. Backups:', b)
PY
Hyprland --verify-config
[[ "$MODE" != --user-only ]] || exit 0
THEME_SOURCE="$HOME/.cache/sddm-astronaut-repair"
if [[ ! -f "$THEME_SOURCE/Themes/jake_the_dog.conf" ]]; then
    git clone --depth=1 https://github.com/Keyitdev/sddm-astronaut-theme.git "$THEME_SOURCE"
fi
if sudo -n true 2>/dev/null; then
    exec sudo /usr/bin/bash "$SELF" --system "$(id -un)"
elif command -v pkexec >/dev/null 2>&1; then
    exec pkexec /usr/bin/bash "$SELF" --system "$(id -un)"
else
    exec sudo /usr/bin/bash "$SELF" --system "$(id -un)"
fi
